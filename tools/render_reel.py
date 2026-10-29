#!/usr/bin/env python3
"""Render a demo reel MP4: a tour through the presets with fake 124 bpm audio,
including a few live-style knob moves (kaleido, palette, trails).

    python tools/render_reel.py                      # -> preview/prism_demo.mp4
    python tools/render_reel.py --seconds 6 --size 1920x1080
    python tools/render_reel.py 28_fractal_cathedral 29_mandelbulb_bloom --out preview/new.mp4

Needs: pip install moderngl numpy imageio-ffmpeg
"""

import argparse
import math
import os
import sys

import moderngl
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from prism.engine import Engine, load_presets  # noqa: E402
from prism.params import ParamSet  # noqa: E402
from prism.audio import AudioInput  # noqa: E402

# Knob moves per preset: name -> list of (param, start_value, end_value), swept over the clip.
MOVES = {
    "03_liquid_spirit": [("kaleido", 0, 6)],
    "04_flower_of_life": [("palette", 3, 0), ("fb_rotate", 0.1, 0.5)],
    "06_star_gate": [("speed", 1.0, 2.2)],
    "09_bio_cells": [("kaleido", 0, 8), ("fb_hue", 0.0, 0.2), ("feedback", 0.3, 0.7)],
    "11_spiral_vortex": [("palette", 7, 2)],
    "12_sound_halo": [("kaleido", 0, 5)],
    "13_yantra": [("warp", 0.0, 0.35), ("feedback", 0.4, 0.8)],
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", default="960x540")
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--seconds", type=float, default=4.0, help="per preset")
    ap.add_argument("--out", default="preview/prism_demo.mp4")
    ap.add_argument("--include-video", action="store_true", help="also show the camera presets")
    ap.add_argument("names", nargs="*", help="only these presets (file names without .glsl)")
    args = ap.parse_args()

    import imageio_ffmpeg

    w, h = (int(x) for x in args.size.split("x"))
    ctx = moderngl.create_standalone_context(require=330)
    presets = load_presets()
    if not args.include_video:
        presets = [p for p in presets if "(video)" not in p.name]
    if args.names:
        presets = [p for p in presets if p.key in args.names]
    engine = Engine(ctx, (w, h), scale=1.0, presets=presets)
    target = ctx.framebuffer([ctx.texture((w, h), 4)])
    audio = AudioInput(fake=True)
    params = ParamSet()
    state = {"time": 0.0, "pulse": 0.0, "real_time": 0.0, "flash": 0.0, "blackout": 1.0, "cam_yaw": 0.0}

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    writer = imageio_ffmpeg.write_frames(args.out, (w, h), fps=args.fps, codec="libx264",
                                         pix_fmt_out="yuv420p", quality=6, macro_block_size=2)
    writer.send(None)

    dt = 1.0 / args.fps
    per = int(args.seconds * args.fps)
    total = per * len(presets)
    for i, preset in enumerate(presets):
        params.load_preset(preset.params)
        moves = MOVES.get(preset.key, [])
        print(f"{i + 1:2d}/{len(presets)} {preset.name}")
        for f in range(per):
            k = f / max(per - 1, 1)
            ease = 0.5 - 0.5 * math.cos(math.pi * min(1.0, max(0.0, (k - 0.25) / 0.6)))
            for name, a, b in moves:
                params[name].set_value(a + (b - a) * ease)
            audio.update(dt)
            params.update(dt)
            engine.update_palette(params.v("palette"), dt)
            state["time"] += dt * params.v("speed")
            state["pulse"] += dt * params.v("speed") * (1.0 + audio.bass * 1.5)
            state["real_time"] += dt
            # fade in from black at the start, out at the end
            g = i * per + f
            state["blackout"] = max(1.0 - g / (args.fps * 1.0), 0.0, 1.0 - (total - g) / (args.fps * 1.0))
            engine.render(preset, params, state, audio, target=target)
            frame = np.frombuffer(target.read(components=3), dtype=np.uint8).reshape(h, w, 3)[::-1]
            writer.send(np.ascontiguousarray(frame))
    writer.close()
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
