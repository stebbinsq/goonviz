"""Audio analysis: bass/mid/high bands, beat detection and a 128-bin log spectrum.

All values are auto-gained (normalized against a slowly decaying peak), so the
visuals react the same whether you feed in a quiet USB mic or a hot line-out
from the DJ mixer.
"""

import math
import threading
import time

import numpy as np

FFT_SIZE = 2048
FFT_BINS = 128


class AudioInput:
    def __init__(self, device=None, samplerate=48000, fake=False, gain=1.0, noise_floor=0.015,
                 fallback_to_default=True):
        self.device = device
        self.fallback_to_default = fallback_to_default
        self.samplerate = samplerate
        self.fake = fake
        self.gain = gain
        self.noise_floor = noise_floor

        self.bass = self.mid = self.high = self.level = 0.0
        self.beat = 0.0
        self.beat_count = 0
        self.fft = np.zeros(FFT_BINS, dtype=np.uint8)
        self.status = "off"
        self.external_beats_until = 0.0  # while MIDI clock is running, it supplies the beats

        self._buf = np.zeros(FFT_SIZE, dtype=np.float32)
        self._lock = threading.Lock()
        self._stream = None
        self._last_try = -999.0
        self._peaks = np.full(4, 1e-3)
        self._spec_peak = 1e-3
        self._spec_smooth = np.zeros(FFT_BINS)
        self._bass_avg = 0.0
        self._last_beat = 0.0
        self._window = np.hanning(FFT_SIZE).astype(np.float32)
        self._bin_edges = None
        self._fake_t = 0.0

        if not fake:
            self._open()

    # ---- device --------------------------------------------------------

    def _open(self):
        self._last_try = time.monotonic()
        try:
            import sounddevice as sd
        except (ImportError, OSError) as e:
            self.status = f"no sounddevice ({e.__class__.__name__})"
            return
        devices = [self.device]
        if self.device is not None and self.fallback_to_default:
            devices.append(None)  # e.g. Insta360 mic not exposed -> use the default input instead
        for device in devices:
            try:
                self._start(sd, device)
                return
            except Exception as e:
                self._stream = None
                self.status = "no input"
                print(f"[audio] could not open input {device!r} ({e}); "
                      + ("trying default input" if device is not devices[-1] else "will retry"))

    def _start(self, sd, device):
        self._stream = sd.InputStream(device=device, channels=1, samplerate=self.samplerate,
                                      blocksize=512, dtype="float32", callback=self._callback)
        self._stream.start()
        self.samplerate = int(self._stream.samplerate)
        self.status = "live"
        print(f"[audio] listening on {sd.query_devices(self._stream.device)['name']} @ {self.samplerate} Hz")

    def _callback(self, indata, frames, t, status):
        mono = indata[:, 0]
        with self._lock:
            n = len(mono)
            if n >= FFT_SIZE:
                self._buf[:] = mono[-FFT_SIZE:]
            else:
                self._buf[:-n] = self._buf[n:]
                self._buf[-n:] = mono

    def close(self):
        if self._stream:
            self._stream.stop()
            self._stream.close()

    # ---- analysis ------------------------------------------------------

    def _band_edges(self):
        freqs = np.fft.rfftfreq(FFT_SIZE, 1.0 / self.samplerate)
        edges = np.geomspace(30.0, 16000.0, FFT_BINS + 1)
        lo = np.searchsorted(freqs, edges[:-1])
        hi = np.maximum(np.searchsorted(freqs, edges[1:]), lo + 1)
        self._bin_edges = (lo, hi)
        self._bands = [(freqs >= a) & (freqs < b) for a, b in ((20, 150), (150, 2000), (2000, 12000))]

    def update(self, dt):
        if self.fake:
            self._update_fake(dt)
            return
        if self._stream is None:
            if time.monotonic() - self._last_try > 5.0:
                self._open()
            self._decay(dt)
            return
        if self._bin_edges is None:
            self._band_edges()

        with self._lock:
            x = self._buf.copy() * self.gain
        mags = np.abs(np.fft.rfft(x * self._window)) * (2.0 / self._window.sum())

        raw = np.array([np.sqrt(np.mean(mags[m] ** 2)) for m in self._bands] + [np.sqrt(np.mean(x ** 2))])
        # Auto-gain: each band is divided by its own peak, which decays by half every ~6s.
        self._peaks = np.maximum(np.maximum(raw, self._peaks * 0.5 ** (dt / 6.0)), self.noise_floor)
        norm = np.clip(raw / self._peaks, 0.0, 1.0)
        if raw[3] < self.noise_floor * 0.5:
            norm[:] = 0.0  # silence: don't amplify hiss into visuals

        self.bass = self._follow(self.bass, norm[0], dt)
        self.mid = self._follow(self.mid, norm[1], dt)
        self.high = self._follow(self.high, norm[2], dt)
        self.level = self._follow(self.level, norm[3], dt)
        self._detect_beat(norm[0], dt)

        lo, hi = self._bin_edges
        spec = np.array([mags[a:b].max() for a, b in zip(lo, hi)])
        self._spec_peak = max(spec.max(), self._spec_peak * 0.5 ** (dt / 4.0), self.noise_floor)
        spec = np.sqrt(np.clip(spec / self._spec_peak, 0.0, 1.0))
        rise = spec > self._spec_smooth
        k_up, k_down = 1.0 - math.exp(-dt * 40.0), 1.0 - math.exp(-dt * 6.0)
        self._spec_smooth += (spec - self._spec_smooth) * np.where(rise, k_up, k_down)
        self.fft = (self._spec_smooth * 255.0).astype(np.uint8)

    @staticmethod
    def _follow(cur, target, dt):
        """Fast attack, slow release, so hits pop and then glide back."""
        rate = 35.0 if target > cur else 5.0
        return cur + (target - cur) * (1.0 - math.exp(-dt * rate))

    def _detect_beat(self, bass, dt):
        now = time.monotonic()
        self._bass_avg += (bass - self._bass_avg) * (1.0 - math.exp(-dt * 2.0))
        if now < self.external_beats_until:
            pass
        elif bass > 0.35 and bass > self._bass_avg * 1.3 + 0.05 and now - self._last_beat > 0.27:
            self._last_beat = now
            self.trigger_beat()
        self.beat *= math.exp(-dt * 7.0)

    def trigger_beat(self):
        self.beat = 1.0
        self.beat_count += 1

    def _decay(self, dt):
        k = math.exp(-dt * 4.0)
        self.bass *= k
        self.mid *= k
        self.high *= k
        self.level *= k
        self.beat *= k
        self.fft = (self.fft * k).astype(np.uint8)

    def _update_fake(self, dt, bpm=124.0):
        """Synthetic 4-on-the-floor so you can test without an audio input."""
        self.status = "fake"
        self._fake_t += dt
        t = self._fake_t
        phase = (t * bpm / 60.0) % 1.0
        prev_phase = ((t - dt) * bpm / 60.0) % 1.0
        if phase < prev_phase:
            self.trigger_beat()
        self.beat *= math.exp(-dt * 7.0)
        self.bass = math.exp(-phase * 5.0)
        self.mid = 0.5 + 0.3 * math.sin(t * 3.1) * math.sin(t * 0.7)
        self.high = 0.5 * (1.0 - abs(math.sin(t * bpm / 60.0 * math.pi * 2.0)))
        self.level = 0.4 * self.bass + 0.3 * self.mid + 0.3 * self.high
        x = np.linspace(0.0, 1.0, FFT_BINS)
        spec = (self.bass * np.exp(-x * 8.0) + self.mid * 0.6 * np.exp(-((x - 0.45) * 5.0) ** 2)
                + self.high * 0.4 * np.exp(-((x - 0.8) * 6.0) ** 2))
        spec *= 0.85 + 0.15 * np.sin(x * 40.0 + t * 5.0)
        self.fft = (np.clip(spec, 0.0, 1.0) * 255.0).astype(np.uint8)


def list_devices():
    try:
        import sounddevice as sd
    except (ImportError, OSError) as e:
        print(f"sounddevice unavailable: {e}")
        return
    for i, d in enumerate(sd.query_devices()):
        if d["max_input_channels"] > 0:
            print(f"  [{i}] {d['name']}  ({d['max_input_channels']} in, {int(d['default_samplerate'])} Hz)")
