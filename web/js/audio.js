// Port of prism/audio.py on top of Web Audio: auto-gained bass/mid/high, beat detection,
// and a 128-bin log spectrum. Also has a synthetic 124 bpm "demo beat" for testing without a mic.
(function () {
  "use strict";
  const Prism = (window.Prism = window.Prism || {});
  const FFT_SIZE = 2048;
  const BINS = 128;

  const follow = (cur, target, dt) => cur + (target - cur) * (1 - Math.exp(-dt * (target > cur ? 35 : 5)));

  class Audio {
    constructor() {
      this.bass = this.mid = this.high = this.level = 0;
      this.beat = 0;
      this.beatCount = 0;
      this.fft = new Uint8Array(BINS);
      this.status = "off";
      this.fake = false;
      this.gain = 1;
      // Auto-gain never amplifies past this level: a quiet room through a laptop mic must not be
      // boosted until typing and talking look like bass hits.
      this.noiseFloor = 0.015;
      this.externalBeatsUntil = 0; // while MIDI clock runs, it supplies the beats
      this._peaks = [1e-3, 1e-3, 1e-3, 1e-3];
      this._specPeak = 1e-3;
      this._spec = new Float32Array(BINS);
      this._bassAvg = 0;
      this._lastBeat = 0;
      this._fakeT = 0;
    }

    async start(deviceId) {
      this.stop();
      try {
        this.stream = await navigator.mediaDevices.getUserMedia({
          audio: {
            deviceId: deviceId ? { exact: deviceId } : undefined,
            // all off: we want the raw room/mixer sound, not a voice-call cleanup
            echoCancellation: false, noiseSuppression: false, autoGainControl: false,
          },
        });
      } catch (e) {
        this.status = "no access";
        throw e;
      }
      this.ctx = this.ctx || new AudioContext();
      await this.ctx.resume();
      this.source = this.ctx.createMediaStreamSource(this.stream);
      this.analyser = this.ctx.createAnalyser();
      this.analyser.fftSize = FFT_SIZE;
      this.analyser.smoothingTimeConstant = 0;
      this.source.connect(this.analyser);
      this._freq = new Float32Array(this.analyser.frequencyBinCount);
      this._time = new Float32Array(FFT_SIZE);
      this._edges(this.ctx.sampleRate);
      this.label = this.stream.getAudioTracks()[0]?.label || "input";
      this.status = "live";
    }

    stop() {
      if (this.stream) this.stream.getTracks().forEach((t) => t.stop());
      if (this.source) this.source.disconnect();
      this.stream = this.source = this.analyser = null;
      this.status = "off";
    }

    _edges(rate) {
      const n = FFT_SIZE / 2;
      const idx = (f) => Math.min(n - 1, Math.max(0, Math.round((f * FFT_SIZE) / rate)));
      this._lo = [];
      this._hi = [];
      for (let b = 0; b < BINS; b++) {
        const a = 30 * Math.pow(16000 / 30, b / BINS), z = 30 * Math.pow(16000 / 30, (b + 1) / BINS);
        const lo = idx(a);
        this._lo.push(lo);
        this._hi.push(Math.max(idx(z), lo + 1));
      }
      this._bands = [[20, 150], [150, 2000], [2000, 12000]].map(([a, z]) => [idx(a), Math.max(idx(z), idx(a) + 1)]);
    }

    triggerBeat() {
      this.beat = 1;
      this.beatCount++;
    }

    update(dt) {
      if (this.fake) return this._updateFake(dt);
      if (!this.analyser) {
        const k = Math.exp(-dt * 4);
        this.bass *= k; this.mid *= k; this.high *= k; this.level *= k; this.beat *= k;
        for (let i = 0; i < BINS; i++) this.fft[i] *= k;
        return;
      }
      this.analyser.getFloatFrequencyData(this._freq); // dB
      this.analyser.getFloatTimeDomainData(this._time);
      const mags = this._freq;
      const g = this.gain;
      for (let i = 0; i < mags.length; i++) mags[i] = Math.pow(10, mags[i] / 20) * g; // -> linear magnitude
      const rms = (a, b) => { let s = 0; for (let i = a; i < b; i++) s += mags[i] * mags[i]; return Math.sqrt(s / (b - a)); };
      let t2 = 0;
      for (let i = 0; i < this._time.length; i++) t2 += this._time[i] * this._time[i];
      const raw = [...this._bands.map(([a, b]) => rms(a, b)), Math.sqrt(t2 / this._time.length) * g];

      // Auto-gain: each band is divided by its own peak, which decays by half every ~6s.
      const decay = Math.pow(0.5, dt / 6);
      const norm = raw.map((r, i) => {
        this._peaks[i] = Math.max(r, this._peaks[i] * decay, this.noiseFloor);
        return Math.min(1, r / this._peaks[i]);
      });
      if (raw[3] < this.noiseFloor * 0.5) norm.fill(0); // silence: don't amplify hiss

      this.bass = follow(this.bass, norm[0], dt);
      this.mid = follow(this.mid, norm[1], dt);
      this.high = follow(this.high, norm[2], dt);
      this.level = follow(this.level, norm[3], dt);
      this._detectBeat(norm[0], dt);

      let peak = 0;
      const spec = new Float32Array(BINS);
      for (let b = 0; b < BINS; b++) {
        let m = 0;
        for (let i = this._lo[b]; i < this._hi[b]; i++) m = Math.max(m, mags[i]);
        spec[b] = m;
        peak = Math.max(peak, m);
      }
      this._specPeak = Math.max(peak, this._specPeak * Math.pow(0.5, dt / 4), this.noiseFloor);
      const up = 1 - Math.exp(-dt * 40), down = 1 - Math.exp(-dt * 6);
      for (let b = 0; b < BINS; b++) {
        const v = Math.sqrt(Math.min(1, spec[b] / this._specPeak));
        this._spec[b] += (v - this._spec[b]) * (v > this._spec[b] ? up : down);
        this.fft[b] = this._spec[b] * 255;
      }
    }

    _detectBeat(bass, dt) {
      const now = performance.now() / 1000;
      this._bassAvg += (bass - this._bassAvg) * (1 - Math.exp(-dt * 2));
      if (now >= this.externalBeatsUntil && bass > 0.35 && bass > this._bassAvg * 1.3 + 0.05 && now - this._lastBeat > 0.27) {
        this._lastBeat = now;
        this.triggerBeat();
      }
      this.beat *= Math.exp(-dt * 7);
    }

    _updateFake(dt, bpm = 124) {
      this.status = "demo beat";
      this._fakeT += dt;
      const t = this._fakeT;
      const phase = ((t * bpm) / 60) % 1, prev = (((t - dt) * bpm) / 60) % 1;
      if (phase < prev) this.triggerBeat();
      this.beat *= Math.exp(-dt * 7);
      this.bass = Math.exp(-phase * 5);
      this.mid = 0.5 + 0.3 * Math.sin(t * 3.1) * Math.sin(t * 0.7);
      this.high = 0.5 * (1 - Math.abs(Math.sin(((t * bpm) / 60) * Math.PI * 2)));
      this.level = 0.4 * this.bass + 0.3 * this.mid + 0.3 * this.high;
      for (let b = 0; b < BINS; b++) {
        const x = b / (BINS - 1);
        let s = this.bass * Math.exp(-x * 8) + this.mid * 0.6 * Math.exp(-(((x - 0.45) * 5) ** 2)) +
                this.high * 0.4 * Math.exp(-(((x - 0.8) * 6) ** 2));
        s *= 0.85 + 0.15 * Math.sin(x * 40 + t * 5);
        this.fft[b] = Math.min(1, Math.max(0, s)) * 255;
      }
    }
  }

  Prism.Audio = Audio;
})();
