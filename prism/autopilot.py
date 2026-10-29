"""Autopilot: switches presets on the beat and keeps the knobs moving the whole time.

Everything scales with the "ap_intensity" knob (0 = slow and gentle, 1 = wild):
  - preset switch every 64 beats at 0 down to every 8 at 1 (or a time limit when there's no beat)
  - knob drift: every few beats each drifting knob picks a new destination and glides there smoothly,
    so the visuals keep evolving between switches
  - beat events above 0.4: kaleidoscope and palette jumps, and white flashes near the top
Knobs you touch yourself (MIDI, slider, keyboard) are left alone until the next preset switch.
web/js/autopilot.js is a line-for-line port; keep the two in step.
"""

import math
import random

DRIFT = ("a", "b", "c", "d", "speed", "zoom", "feedback", "fb_zoom", "fb_rotate", "fb_hue", "warp", "chroma", "glow")


def lerp(a, b, t):
    return a + (b - a) * t


class Autopilot:
    def __init__(self, params, kaleido_chaos, palette_count, rng=random):
        self.p = params
        self.kaleido_chaos = kaleido_chaos
        self.palette_count = palette_count
        self.rng = rng
        self.enabled = False
        self.base = {}
        self.dest = {}
        self.touched = set()
        self.stepped = set()
        self.home_hue = None  # your hue: autopilot wobbles around it (reset when autopilot is switched on)
        self._reset_counters()

    @property
    def intensity(self):
        return self.p.v("ap_intensity")

    # how often things happen, from the intensity
    def switch_beats(self):
        return max(4, int(round(lerp(64, 8, self.intensity) / 4.0)) * 4)

    def _reset_counters(self):
        self.beats_since_switch = self.beats_since_drift = 0
        self.time_since_switch = self.time_since_drift = 0.0

    def start_preset(self, stepped=()):
        """Call after a preset loads: its values become the centre the knobs drift around.
        stepped: knobs the preset rounds to whole numbers; they stay put (gliding them makes shapes pop)."""
        self.stepped = set(stepped)
        if self.home_hue is None or "hue" in self.touched:
            self.home_hue = self.p["hue"].target
        self.base = {n: self.p[n].target for n in DRIFT}
        self.base["hue"] = self.home_hue
        self.touched.clear()
        self._reset_counters()
        self._retarget()

    def touch(self, name):
        self.touched.add(name)
        self.dest.pop(name, None)

    def _retarget(self):
        amount = 0.15 + 0.85 * self.intensity  # how far from the preset's own look the knobs may wander
        for n in DRIFT:
            if n in self.touched or n in self.stepped:
                continue
            prm = self.p[n]
            lo, hi = prm.chaos or (prm.lo, prm.hi)
            wild = prm.to_norm(self.rng.uniform(lo, hi))
            self.dest[n] = self.base[n] + (wild - self.base[n]) * amount
        if "hue" not in self.touched:
            # wobble around your hue setting rather than wandering off (palettes go murky far from home)
            self.dest["hue"] = min(1.0, max(0.0, self.base["hue"] + self.rng.uniform(-1.0, 1.0) * 0.08 * self.intensity))

    def update(self, dt, beats):
        """Advance by dt seconds and `beats` new beats. Returns a list of events for the app:
        "switch" (change preset), "flash"."""
        if not self.enabled:
            return []
        I = self.intensity
        events = []
        self.beats_since_switch += beats
        self.beats_since_drift += beats
        self.time_since_switch += dt
        self.time_since_drift += dt

        if self.beats_since_switch >= self.switch_beats() or self.time_since_switch >= lerp(60.0, 12.0, I):
            events.append("switch")  # the app picks a preset, then calls start_preset()
        if self.beats_since_drift >= max(1, round(lerp(16, 2, I))) or self.time_since_drift >= lerp(10.0, 1.5, I):
            self.beats_since_drift, self.time_since_drift = 0, 0.0
            self._retarget()

        k = 1.0 - math.exp(-dt / lerp(4.0, 0.8, I))  # glide: slow sweeps at low intensity, quick at high
        for n, d in self.dest.items():
            prm = self.p[n]
            prm.set_norm(prm.target + (d - prm.target) * k)

        for _ in range(beats):
            if I > 0.4 and self.rng.random() < (I - 0.4) * 0.35:
                roll = self.rng.random()
                if roll < 0.45 and "kaleido" not in self.touched:
                    self.p["kaleido"].set_value(self.rng.choice(self.kaleido_chaos))
                elif roll < 0.85 and "palette" not in self.touched:
                    self.p["palette"].set_value(self.rng.randrange(self.palette_count))
                elif I > 0.8:
                    events.append("flash")
        return events

    def on_switched(self):
        """After an autopilot preset switch: bolder looks get bigger jumps."""
        I = self.intensity
        if self.rng.random() < I:
            self.p["palette"].set_value(self.rng.randrange(self.palette_count))
        if self.rng.random() < I * 0.7:
            self.p["kaleido"].set_value(self.rng.choice(self.kaleido_chaos))
        self.start_preset(self.stepped)
