#!/usr/bin/env python3
"""Render every preset offscreen (no window, fake audio) and save a contact sheet.

    python tools/render_presets.py                   # all presets -> preview/
    python tools/render_presets.py tunnel kifs       # just these
    python tools/render_presets.py --seconds 8 --size 960x540

Good for checking a shader edit compiles and looks right before a show.
"""

import argparse
import os
import sys

import numpy as np
import moderngl
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from prism.engine import Engine, load_presets  # noqa: E402
from prism.params import ParamSet  # noqa: E402
from prism.audio import AudioInput  # noqa: E402


class FakeVideo:
    """Moving shapes standing in for a camera, so video presets have something to chew on."""
    active = True
    is_360 = False

    def __init__(self, w=320, h=180):
        self.w, self.h, self.t, self.id = w, h, 0.0, 0
        yy, xx = np.mgrid[0:h, 0:w]
        self.xx, self.yy = xx / w, yy / h

    def step(self, dt):
        self.t += dt
        self.id += 1

    def latest(self):
        t = self.t
        cx, cy = 0.5 + 0.25 * np.sin(t), 0.5 + 0.2 * np.cos(t * 1.3)
        d = np.hypot((self.xx - cx) * 1.8, self.yy - cy)
        face = (d < 0.18).astype(np.float32)
        bars = (np.sin(self.xx * 20 + t * 2) > 0.6).astype(np.float32) * 0.5
        b = np.clip(face * 0.9 + bars * (1 - face), 0, 1)
        img = np.stack([b * 0.6, b * 0.8, b], axis=-1)  # BGR
        return self.id, (img * 255).astype(np.uint8)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="*")
    ap.add_argument("--size", default="640x360")
    ap.add_argument("--seconds", type=float, default=6.0)
    ap.add_argument("--fps", type=float, default=30.0)
    ap.add_argument("--out", default="preview")
    ap.add_argument("--frames", type=int, default=1, help="frames per preset to save (spread over time)")
    args = ap.parse_args()

    w, h = (int(x) for x in args.size.split("x"))
    ctx = moderngl.create_standalone_context(require=330)
    presets = load_presets()
    if args.names:
        presets = [p for p in presets if p.key in args.names]
    engine = Engine(ctx, (w, h), scale=1.0, presets=presets)
    target_tex = ctx.texture((w, h), 4)
    target = ctx.framebuffer([target_tex])
    os.makedirs(args.out, exist_ok=True)

    shots = []
    for preset in presets:
        if not preset.program:
            print(f"SKIP {preset.key}: compile error")
            continue
        params = ParamSet()
        params.load_preset(preset.params)
        audio = AudioInput(fake=True)
        video = FakeVideo()
        engine.resize((w, h))
        state = {"time": 0.0, "pulse": 0.0, "real_time": 0.0, "flash": 0.0, "blackout": 0.0}
        dt = 1.0 / args.fps
        n = int(args.seconds * args.fps)
        save_at = {int(n * (i + 1) / args.frames) - 1 for i in range(args.frames)}
        for f in range(n):
            audio.update(dt)
            params.update(dt)
            video.step(dt)
            engine.update_video(video)
            engine.update_palette(params.v("palette"), 1.0 if f == 0 else dt)
            state["time"] += dt * params.v("speed")
            state["pulse"] += dt * params.v("speed") * (1 + audio.bass * 1.5)
            state["real_time"] += dt
            engine.render(preset, params, state, audio, target=target)
            if f in save_at:
                img = Image.frombytes("RGBA", (w, h), target.read(components=4)).transpose(Image.FLIP_TOP_BOTTOM)
                path = os.path.join(args.out, f"{preset.key}_{f:04d}.png")
                img.convert("RGB").save(path)
                shots.append((preset.name, path))
        print(f"ok   {preset.key}")

    if shots:
        cols = 4 if args.frames == 1 else args.frames
        tw, th = 320, 180
        rows = (len(shots) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * tw, rows * (th + 18)), "black")
        draw = ImageDraw.Draw(sheet)
        for i, (name, path) in enumerate(shots):
            x, y = (i % cols) * tw, (i // cols) * (th + 18)
            sheet.paste(Image.open(path).resize((tw, th)), (x, y))
            draw.text((x + 4, y + th + 2), name, fill=(220, 220, 220))
        sheet_path = os.path.join(args.out, "contact_sheet.png")
        sheet.save(sheet_path)
        print(f"contact sheet: {sheet_path}")


if __name__ == "__main__":
    main()
