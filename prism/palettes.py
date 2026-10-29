"""Curated colour palettes shared by every preset.

Each palette is five stops, darkest first. Stop 0 is the "void" the visuals
glow out of; keep it near-black so the projector shows depth instead of a
washed-out grey wall. Edit freely: hex strings, cyclic order matters.
"""

PALETTES = [
    ("Astral",         ["#07021a", "#3a0ca3", "#f72585", "#ffb703", "#4cc9f0"]),
    ("Ayahuasca",      ["#010b10", "#0a6f72", "#94d2bd", "#ee9b00", "#9b2226"]),
    ("Jewel",          ["#0a0018", "#5a189a", "#e0aaff", "#ff006e", "#00f5d4"]),
    ("Ember",          ["#030510", "#6a040f", "#dc2f02", "#f48c06", "#ffd166"]),
    ("Bioluminescent", ["#000610", "#003566", "#00b4d8", "#caf0f8", "#b5179e"]),
    ("Iridescent",     ["#0d0d1f", "#ff7eb3", "#7afcff", "#feff9c", "#b388ff"]),
    ("Forest Spirit",  ["#03100b", "#2d6a4f", "#95d5b2", "#ffd166", "#ef476f"]),
    ("Ultraviolet",    ["#08000f", "#4b0082", "#9d4edd", "#ff9e00", "#ff4d6d"]),
    ("Jade",           ["#020a08", "#0d5c47", "#3fcf9a", "#f0c35a", "#9b7bff"]),
    ("Cicada",         ["#030705", "#245c3f", "#9fe8b0", "#e8a83a", "#c44569"]),
]


def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


PALETTE_RGB = [[hex_to_rgb(c) for c in cols] for _, cols in PALETTES]
PALETTE_NAMES = [name for name, _ in PALETTES]
