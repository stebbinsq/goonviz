"""Every knob in the system. MIDI, keyboard and presets all talk to these."""

import math
import random

# name, min, max, default, options
#   curve:  "lin" or "exp" (exp for things like zoom where you want fine control near 1)
#   int:    snap to whole numbers
#   scope:  "preset" params reset to defaults when a preset loads,
#           "master" params (colour, brightness, etc.) survive preset changes
#   chaos:  (lo, hi) range used by the randomize action; omitted = never randomized
PARAM_DEFS = [
    ("speed",      0.0, 4.0,  1.0,  dict(scope="preset", chaos=(0.4, 1.8))),
    ("a",          0.0, 1.0,  0.5,  dict(scope="preset", chaos=(0.0, 1.0))),
    ("b",          0.0, 1.0,  0.5,  dict(scope="preset", chaos=(0.0, 1.0))),
    ("c",          0.0, 1.0,  0.5,  dict(scope="preset", chaos=(0.0, 1.0))),
    ("d",          0.0, 1.0,  0.5,  dict(scope="preset", chaos=(0.0, 1.0))),
    ("zoom",       0.25, 4.0, 1.0,  dict(scope="preset", curve="exp", chaos=(0.6, 1.8))),
    ("feedback",   0.0, 0.98, 0.0,  dict(scope="preset", chaos=(0.3, 0.92))),
    ("fb_zoom",   -1.0, 1.0,  0.0,  dict(scope="preset", chaos=(-0.6, 0.8))),
    ("fb_rotate", -1.0, 1.0,  0.0,  dict(scope="preset", chaos=(-0.5, 0.5))),
    ("fb_hue",     0.0, 1.0,  0.0,  dict(scope="preset", chaos=(0.0, 0.3))),
    ("kaleido",    0.0, 12.0, 0.0,  dict(scope="preset", int=True)),
    ("warp",       0.0, 1.0,  0.0,  dict(scope="preset", chaos=(0.0, 0.4))),
    ("chroma",     0.0, 1.0,  0.15, dict(scope="preset", chaos=(0.0, 0.5))),
    ("glow",       0.0, 1.0,  0.45, dict(scope="preset", chaos=(0.25, 0.8))),
    ("palette",    0.0, 9.0,  0.0,  dict(scope="preset", int=True)),   # index into prism/palettes.py
    ("hue",        0.0, 1.0,  0.0,  dict(scope="master")),
    ("saturation", 0.0, 2.0,  1.0,  dict(scope="master")),
    ("brightness", 0.0, 2.0,  1.0,  dict(scope="master")),
    ("contrast",   0.5, 2.0,  1.0,  dict(scope="master")),
    ("video_mix",  0.0, 1.0,  0.0,  dict(scope="master")),
    ("cam_view",   0.0, 3.0,  2.0,  dict(scope="master", int=True)),   # 360 cams: flat/look/planet/hole
    ("cam_spin",  -1.0, 1.0,  0.15, dict(scope="master")),
    ("react",      0.0, 2.0,  1.0,  dict(scope="master")),
    ("strobe",     0.0, 1.0,  0.0,  dict(scope="master")),
    ("ap_intensity", 0.0, 1.0, 0.5, dict(scope="master")),   # autopilot: how often and how wild
    ("invert",     0.0, 1.0,  0.0,  dict(scope="master")),
]

KALEIDO_CHAOS = [0, 0, 0, 3, 4, 5, 6, 8]


class Param:
    SMOOTH_TAU = 0.06  # seconds; hides the 128-step graininess of MIDI knobs

    def __init__(self, name, lo, hi, default, curve="lin", int=False, scope="preset", chaos=None):
        self.name = name
        self.lo, self.hi = lo, hi
        self.default = default
        self.curve = curve
        self.is_int = int
        self.scope = scope
        self.chaos = chaos
        self.norm = self.to_norm(default)
        self.target = self.norm

    def to_norm(self, v):
        v = min(max(v, self.lo), self.hi)
        if self.curve == "exp":
            return math.log(v / self.lo) / math.log(self.hi / self.lo)
        return (v - self.lo) / (self.hi - self.lo)

    def from_norm(self, n):
        n = min(max(n, 0.0), 1.0)
        if self.curve == "exp":
            return self.lo * (self.hi / self.lo) ** n
        return self.lo + n * (self.hi - self.lo)

    @property
    def value(self):
        v = self.from_norm(self.norm)
        return float(round(v)) if self.is_int else v

    @property
    def target_value(self):
        v = self.from_norm(self.target)
        return float(round(v)) if self.is_int else v

    def set_value(self, v, immediate=False):
        self.set_norm(self.to_norm(v), immediate)

    def set_norm(self, n, immediate=False):
        self.target = min(max(n, 0.0), 1.0)
        if immediate or self.is_int:
            self.norm = self.target

    def nudge(self, amount):
        self.set_norm(self.target + amount)

    def update(self, dt):
        k = 1.0 - math.exp(-dt / self.SMOOTH_TAU)
        self.norm += (self.target - self.norm) * k


class ParamSet:
    def __init__(self):
        self.list = [Param(name, lo, hi, d, **opts) for name, lo, hi, d, opts in PARAM_DEFS]
        self.by_name = {p.name: p for p in self.list}

    def __getitem__(self, name):
        return self.by_name[name]

    def __contains__(self, name):
        return name in self.by_name

    def v(self, name):
        return self.by_name[name].value

    def update(self, dt):
        for p in self.list:
            p.update(dt)

    def load_preset(self, preset_params):
        """Reset preset-scoped params, then apply the preset's own values."""
        for p in self.list:
            if p.scope == "preset":
                p.set_value(p.default, immediate=True)
        for name, value in preset_params.items():
            if name in self.by_name:
                self.by_name[name].set_value(value, immediate=True)

    def randomize(self, rng=random):
        for p in self.list:
            if p.chaos:
                p.set_value(rng.uniform(*p.chaos))
        self.by_name["kaleido"].set_value(rng.choice(KALEIDO_CHAOS))
        self.by_name["palette"].set_value(rng.randrange(int(self.by_name["palette"].hi) + 1))

    def snapshot(self):
        return {p.name: round(p.target_value, 4) for p in self.list}

    def restore(self, values):
        for name, value in values.items():
            if name in self.by_name:
                self.by_name[name].set_value(value)
