"""Autopilot as a VJ: it follows the shape of the music and plays planned routines instead of random moves.
web/js/autopilot.js is a line-for-line port; keep the two in step.

 - Energy: short- vs long-term loudness tells a drop (cut to something intense, with a flash), a breakdown
   (ease into something calm) and normal flow (change on phrase boundaries).
 - Phrases: changes land every 8/16/32/64 beats (by intensity), never mid-phrase unless the music drops.
 - Preset choice: match the music's energy, vary the style family, avoid anything shown recently, skip what
   can't work right now (camera presets with no camera, heavy presets on a Pi).
 - Routines: during a phrase it performs one planned move that suits the preset (bloom, spin, dive, breathe,
   colour walk, drift), plus gentle drift of the other knobs within ranges known to look good.
 - Knobs you touch are yours until the next change; knobs a preset uses as counts are never glided.
"""

import math
import random

# Where each knob may wander (real values): tighter than "randomize", picked to stay good-looking.
RANGES = {
    "speed": (0.7, 1.4), "zoom": (0.85, 1.35), "feedback": (0.15, 0.6), "fb_zoom": (-0.15, 0.45),
    "fb_rotate": (-0.25, 0.25), "fb_hue": (0.0, 0.12), "warp": (0.0, 0.2), "chroma": (0.05, 0.3), "glow": (0.3, 0.65),
}
DRIFT = ("a", "b", "c", "d") + tuple(RANGES)

# Which routines suit which kind of picture.
ROUTINES = {
    "mandala": ["spin", "bloom", "breathe", "colorwalk"], "kaleido": ["spin", "bloom", "breathe", "colorwalk"],
    "fractal2d": ["spin", "bloom", "breathe", "colorwalk"], "organic": ["drift", "breathe", "colorwalk", "bloom"],
    "tunnel": ["dive", "breathe", "colorwalk"], "flight3d": ["dive", "breathe", "colorwalk", "bloom"],
    "object3d": ["breathe", "bloom", "colorwalk"], "video": ["breathe", "spin", "bloom"],
}
ROUTINE_NAMES = {"spin": "Spin", "bloom": "Bloom", "breathe": "Breathe", "colorwalk": "Colour walk",
                 "dive": "Dive", "drift": "Drift"}


def lerp(a, b, t):
    return a + (b - a) * t


def clamp01(x):
    return min(1.0, max(0.0, x))


class Autopilot:
    def __init__(self, params, kaleido_chaos, palette_count, rng=random):
        self.p = params
        self.kaleido_chaos = kaleido_chaos
        self.palette_count = palette_count
        self.rng = rng
        self.enabled = False
        self.presets = []
        self.can_use = lambda i: True
        self.base, self.dest = {}, {}
        self.touched, self.stepped = set(), set()
        self.home_hue = None   # your hue: the colour walk wanders around it (reset when autopilot is switched on)
        self.history = []
        self.current = None
        self.routine = "drift"
        self.section = "flow"  # flow | build | drop | breakdown
        self.energy_fast = self.energy_slow = self.energy_prev = 0.3
        self.quiet_beats = 0
        self.drop_cooldown = 0.0
        self.base_kaleido = 0.0
        self._reset_counters()

    def configure(self, presets, can_use):
        """The app tells the pilot about its presets and what can be used right now."""
        self.presets, self.can_use = presets, can_use

    @property
    def intensity(self):
        return self.p.v("ap_intensity")

    def phrase_beats(self):
        """Phrase length in beats: long and patient when calm, short and busy when wild."""
        I = self.intensity
        return 64 if I < 0.25 else 32 if I < 0.5 else 16 if I < 0.75 else 8

    switch_beats = phrase_beats

    def beats_until_switch(self):
        return max(0, self.phrase_beats() - self.beats_in_phrase)

    @property
    def amp(self):
        return 0.3 + 0.7 * self.intensity   # how big the routine's moves are

    def _reset_counters(self):
        self.beats_in_phrase = self.beats_since_drift = 0
        self.time_in_phrase = self.time_since_drift = 0.0

    def start_preset(self, preset):
        """Called whenever a preset loads (by hand or by the pilot): its own look becomes home base."""
        self.current = preset
        self.stepped = set(getattr(preset, "stepped", ()) or ())
        if self.home_hue is None or "hue" in self.touched:
            self.home_hue = self.p["hue"].target
        self.touched.clear()
        self.base = {n: self.p[n].target for n in DRIFT}
        self.base["hue"] = self.home_hue
        self.base_kaleido = self.p["kaleido"].target_value
        self._reset_counters()
        self._choose_routine()
        self._retarget()
        if preset is not None:
            self.history = ([preset.key] + [k for k in self.history if k != preset.key])[:8]

    def touch(self, name):
        self.touched.add(name)
        self.dest.pop(name, None)

    # ---- what to do next -----------------------------------------------------

    def _choose_routine(self):
        options = ROUTINES.get(getattr(self.current, "family", "organic"), ROUTINES["organic"])
        if self.section == "breakdown":
            options = [r for r in options if r in ("drift", "breathe", "colorwalk")]
        if self.section in ("drop", "build"):
            options = [r for r in options if r in ("bloom", "dive", "spin")]
        options = options or ["breathe"]
        fresh = [r for r in options if r != self.routine]   # don't repeat the last routine if there's a choice
        self.routine = self.rng.choice(fresh or options)

    def _target_energy(self):
        """What energy (1 calm .. 3 intense) the next preset should have."""
        if self.section == "drop":
            return 3.0
        if self.section == "breakdown":
            return 1.0
        level = self.energy_slow
        e = 2.6 if level > 0.6 else 1.4 if level < 0.25 else 2.0
        ratio = self.energy_fast / max(0.05, self.energy_slow)
        if ratio > 1.25:
            e += 0.6
        elif ratio < 0.75:
            e -= 0.6
        return min(3.0, max(1.0, e + (self.intensity - 0.5)))   # intensity leans the choice

    def _choose_preset(self):
        target = self._target_energy()
        cur_family = getattr(self.current, "family", None)
        best, best_score = -1, -math.inf
        for i, p in enumerate(self.presets):
            if p is self.current or not self.can_use(i):
                continue
            score = 3 * (1 - abs(getattr(p, "energy", 2) - target) / 2)
            if getattr(p, "family", None) != cur_family:
                score += 1.2                                    # vary the style
            if p.key in self.history:
                score -= 4 * (1 - self.history.index(p.key) / len(self.history))   # avoid repeats
            score += self.rng.random() * 1.4                    # keep it from being predictable
            if score > best_score:
                best, best_score = i, score
        return best

    # ---- knob drift within good-looking ranges ------------------------------------

    def _retarget(self):
        amount = 0.25 + 0.6 * self.intensity
        for n in DRIFT:
            if n in self.touched or n in self.stepped:
                continue
            prm = self.p[n]
            if n in RANGES:
                wild = prm.to_norm(self.rng.uniform(*RANGES[n]))
            else:
                wild = clamp01(self.base[n] + (self.rng.random() - 0.5) * 0.5)   # a-d: stay near the preset's look
            self.dest[n] = self.base[n] + (wild - self.base[n]) * amount

    # ---- routines: one planned move per phrase -----------------------------------

    def _routine_targets(self, p, b):
        """The knob values (name -> 0..1) the routine wants right now. p = progress through the phrase (0..1),
        b = beats into the phrase."""
        A, base, out = self.amp, self.base, {}

        def add(n, delta):
            if n in base:
                out[n] = clamp01(base[n] + delta)

        r = self.routine
        if r == "bloom":        # build toward the change: glow and trails rise, a little chroma at the peak
            add("glow", 0.3 * A * p)
            add("feedback", 0.3 * A * p)
            add("chroma", 0.2 * A * p * p)
            add("zoom", 0.05 * A * p)
        elif r == "spin":       # trails swirl one way then the other; the kaleidoscope steps up every bar
            add("fb_rotate", 0.22 * A * math.sin(p * math.pi * 2))
            add("feedback", 0.12 * A)
            steps = (0, 4, 6, 8, 6, 4)
            if "kaleido" not in self.touched and "kaleido" not in self.stepped:
                out["kaleido_abs"] = steps[int(b // 4) % len(steps)] if self.intensity > 0.2 else self.base_kaleido
        elif r == "dive":       # accelerate into it: forward trail zoom and speed build through the phrase
            add("fb_zoom", 0.35 * A * p)
            add("speed", 0.18 * A * p)
            add("feedback", 0.2 * A * p)
        elif r == "breathe":    # zoom and glow pulse in four-bar cycles, locked to the beat count
            add("zoom", 0.06 * A * math.sin(b / 16 * math.pi * 2))
            add("glow", 0.08 * A * (0.5 + 0.5 * math.sin(b / 16 * math.pi * 2)))
        elif r == "colorwalk":  # the hue takes a slow walk away from home and back over the phrase
            out["hue"] = clamp01(self.home_hue + 0.14 * A * math.sin(p * math.pi * 2))
        return out              # drift: only the gentle background drift

    # ---- per frame ------------------------------------------------------------------

    def update(self, dt, beats, level=0.3):
        """Advance by dt seconds and `beats` new beats, with the audio level (0..1). Returns events for the app:
        ("switch", index, cut): change to this preset (cut = hard cut, for drops); ("flash", amount)."""
        if not self.enabled:
            return []
        I = self.intensity
        events = []
        self.beats_in_phrase += beats
        self.time_in_phrase += dt
        self.beats_since_drift += beats
        self.time_since_drift += dt
        self.drop_cooldown = max(0.0, self.drop_cooldown - dt)

        self.energy_fast += (level - self.energy_fast) * (1 - math.exp(-dt / 1.0))
        self.energy_slow += (level - self.energy_slow) * (1 - math.exp(-dt / 12.0))
        self.energy_prev += (self.energy_slow - self.energy_prev) * (1 - math.exp(-dt / 4.0))
        if beats:
            self.quiet_beats = self.quiet_beats + beats if self.energy_fast < self.energy_slow * 0.55 else 0

        # a drop: loud now, after a quieter stretch
        was_quiet = self.section == "breakdown" or self.energy_prev < self.energy_slow * 0.85
        if (self.drop_cooldown == 0 and I > 0.2 and was_quiet and beats > 0
                and self.energy_fast > max(0.5, self.energy_slow * 1.45)):
            self.section = "drop"
            self.drop_cooldown = 8.0
            i = self._choose_preset()
            if i >= 0:
                events.append(("switch", i, I > 0.45))
            if I > 0.55:
                events.append(("flash", 0.4 + 0.5 * I))
            return events
        if self.quiet_beats >= 8 and self.section != "breakdown":
            self.section = "breakdown"
            # don't sit on an intense picture through a quiet passage
            if getattr(self.current, "energy", 2) >= (2 if I >= 0.5 else 3):
                i = self._choose_preset()
                if i >= 0:
                    return [("switch", i, False)]
            self._choose_routine()
        elif self.section == "breakdown" and self.quiet_beats == 0:
            self.section = "build"
            self._choose_routine()

        # phrase boundary: change preset (no beats at all? fall back to time)
        if self.beats_in_phrase >= self.phrase_beats() or self.time_in_phrase >= lerp(70, 14, I):
            if self.section == "drop":
                self.section = "flow"
            i = self._choose_preset()
            if i >= 0:
                events.append(("switch", i, False))
            else:
                self._reset_counters()
                self._choose_routine()
            return events

        # background drift retargets every few bars; the routine moves continuously on top
        if self.beats_since_drift >= max(4, round(lerp(16, 4, I))) or self.time_since_drift >= lerp(10, 3, I):
            self.beats_since_drift, self.time_since_drift = 0, 0.0
            self._retarget()
        rt = self._routine_targets(min(1.0, self.beats_in_phrase / self.phrase_beats()), self.beats_in_phrase)
        glide = 1 - math.exp(-dt / lerp(4, 1.2, I))
        for n, d in self.dest.items():
            if n in rt or n in self.touched:
                continue
            prm = self.p[n]
            prm.set_norm(prm.target + (d - prm.target) * glide)
        follow = 1 - math.exp(-dt / 0.35)   # routines follow their curve closely
        for n, v in rt.items():
            if n == "kaleido_abs":
                if self.p["kaleido"].target_value != v:
                    self.p["kaleido"].set_value(v)
                continue
            if n in self.touched or n in self.stepped:
                continue
            prm = self.p[n]
            prm.set_norm(prm.target + (v - prm.target) * follow)
        return events

    def on_switched(self, preset):
        self.start_preset(preset)

    def status(self):
        sec = {"flow": "", "build": " · building", "drop": " · DROP", "breakdown": " · breakdown"}[self.section]
        return ROUTINE_NAMES.get(self.routine, self.routine) + sec
