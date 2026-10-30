"""GPU pipeline: preset scene -> composite (bloom, kaleido, feedback) -> display (grading).

    scene pass      preset shader at internal res          -> scene_tex (mipmapped for bloom)
    composite pass  warp/kaleido/chroma/bloom + feedback    -> comp[cur]  (reads comp[prev])
    display pass    hue/sat/contrast/strobe/blackout        -> projector, full res
"""

import glob
import json
import os
import re

import numpy as np
import moderngl

from .palettes import PALETTE_RGB

HERE = os.path.dirname(os.path.abspath(__file__))
SHADER_DIR = os.path.join(HERE, "shaders")
PRESET_DIR = os.path.join(os.path.dirname(HERE), "presets")

VERT = """
in vec2 in_pos;
out vec2 vUV;
void main() {
    vUV = in_pos * 0.5 + 0.5;
    gl_Position = vec4(in_pos, 0.0, 1.0);
}
"""

SCENE_MAIN = """
void main() {
    vec2 p = vUV * 2.0 - 1.0;
    p.x *= uRes.x / uRes.y;
    p /= uZoom;
    fragColor = vec4(tonemap(scene(p, vUV)), 1.0);
}
"""

META_RE = re.compile(r"//\s*@preset\s*(\{.*\})")
KNOB_RE = re.compile(r"\bu([ABCD])\b")


def stepped_knobs(source):
    """Knobs a preset rounds to whole numbers (petal counts, polygon sides...). Gliding those makes the
    shape pop, so autopilot leaves them alone. Any line with floor( or int( counts."""
    found = set()
    for line in source.splitlines():
        code = line.split("//")[0]
        if "floor(" in code or "int(" in code:
            found.update(k.lower() for k in KNOB_RE.findall(code))
    return found


def _read(name):
    with open(os.path.join(SHADER_DIR, name)) as f:
        return f.read()


def glsl_header(ctx):
    """Pi 4/5 Mesa gives desktop GL 3.1 (GLSL 140); macOS/PC give 3.3+; GLES as a fallback."""
    version = ctx.info.get("GL_VERSION", "")
    if "OpenGL ES" in version:
        return "#version 300 es\nprecision highp float;\nprecision highp int;\nprecision highp sampler2D;\n"
    if ctx.version_code >= 330:
        return "#version 330\n"
    return "#version 140\n"


class Preset:
    def __init__(self, path):
        self.path = path
        self.key = os.path.splitext(os.path.basename(path))[0]
        self.program = None
        self.vao = None
        self.error = None
        self.mtime = 0
        self.read()

    def read(self):
        with open(self.path) as f:
            self.source = f.read()
        self.mtime = os.path.getmtime(self.path)
        meta = {}
        m = META_RE.search(self.source)
        if m:
            try:
                meta = json.loads(m.group(1))
            except json.JSONDecodeError as e:
                print(f"[preset] bad @preset header in {self.path}: {e}")
        self.name = meta.get("name", self.key.replace("_", " ").title())
        self.params = meta.get("params", {})
        self.labels = meta.get("labels", {})
        self.heavy = bool(meta.get("heavy", False))   # raymarched 3D/4D: too much for a Raspberry Pi
        self.stepped = stepped_knobs(self.source)

    def changed_on_disk(self):
        try:
            return os.path.getmtime(self.path) != self.mtime
        except OSError:
            return False


def load_presets(directory=PRESET_DIR):
    return [Preset(p) for p in sorted(glob.glob(os.path.join(directory, "*.glsl")))]


class Engine:
    def __init__(self, ctx, size, scale=0.5, presets=None):
        self.ctx = ctx
        # OpenCV/picamera2 frames arrive BGR; the web version defines this as rgb
        self.header = glsl_header(ctx) + "#define VIDEO_SWIZZLE bgr\n"
        self.lib = _read("lib.glsl")
        self.scene_header = _read("scene_header.glsl")
        self.quad = ctx.buffer(np.array([-1.0, -1.0, 3.0, -1.0, -1.0, 3.0], dtype="f4"))

        self.comp_prog, self.comp_vao = self._build(self.lib + _read("composite.glsl"))
        self.disp_prog, self.disp_vao = self._build(self.lib + _read("display.glsl"))

        self.presets = presets if presets is not None else load_presets()
        for preset in self.presets:
            self.compile_preset(preset)
        if not any(p.program for p in self.presets):
            raise RuntimeError("no presets compiled; see errors above")

        self.fft_tex = ctx.texture((128, 1), 1, dtype="f1")
        self.video_tex = ctx.texture((1, 1), 3, data=b"\x00\x00\x00")
        self.video_frame_id = -1
        self.video_on = False
        self.video_360 = False

        self.palette = np.array(PALETTE_RGB[0], dtype="f4")
        self.exposure = 1.0
        self.auto_exposure = True
        self._frame = 0
        self.scale = scale
        self.cur = 0
        self.resize(size)

    # ---- setup ---------------------------------------------------------

    def _build(self, frag):
        prog = self.ctx.program(vertex_shader=self.header + VERT, fragment_shader=self.header + frag)
        vao = self.ctx.vertex_array(prog, [(self.quad, "2f", "in_pos")])
        return prog, vao

    def compile_preset(self, preset):
        try:
            prog, vao = self._build(self.lib + self.scene_header + preset.source + SCENE_MAIN)
        except Exception as e:  # moderngl raises a plain Error with the GLSL log
            preset.error = str(e)
            print(f"[preset] {preset.key} failed to compile:\n{e}")
            return False
        if preset.vao:
            preset.vao.release()
            preset.program.release()
        preset.program, preset.vao, preset.error = prog, vao, None
        return True

    def reload_if_changed(self, preset):
        if preset.changed_on_disk():
            preset.read()
            if self.compile_preset(preset):
                print(f"[preset] reloaded {preset.key}")
                return True
        return False

    def resize(self, size):
        self.screen_size = size
        w = max(16, int(size[0] * self.scale))
        h = max(16, int(size[1] * self.scale))
        self.internal_size = (w, h)
        for attr in ("scene_fbo", "scene_tex"):
            obj = getattr(self, attr, None)
            if obj:
                obj.release()
        for fbo, tex in getattr(self, "comp", []):
            fbo.release()
            tex.release()

        self.scene_tex = self.ctx.texture((w, h), 4)
        self.scene_tex.filter = (moderngl.LINEAR_MIPMAP_LINEAR, moderngl.LINEAR)
        self.scene_tex.repeat_x = self.scene_tex.repeat_y = False
        self.scene_tex.build_mipmaps()
        self.scene_fbo = self.ctx.framebuffer([self.scene_tex])

        self.comp = []
        for _ in range(2):
            tex = self.ctx.texture((w, h), 4)
            tex.repeat_x = tex.repeat_y = False
            fbo = self.ctx.framebuffer([tex])
            fbo.clear(0.0, 0.0, 0.0, 1.0)
            self.comp.append((fbo, tex))

    # ---- per-frame inputs ---------------------------------------------

    def update_video(self, video):
        if video is None:
            self.video_on = False
            return
        frame_id, frame = video.latest()
        self.video_on = frame is not None and video.active
        self.video_360 = video.is_360
        if frame is None or frame_id == self.video_frame_id:
            return
        h, w = frame.shape[:2]
        if self.video_tex.size != (w, h):
            self.video_tex.release()
            self.video_tex = self.ctx.texture((w, h), 3)
            self.video_tex.repeat_x = True   # 360 panoramas wrap horizontally
            self.video_tex.repeat_y = False
        self.video_tex.write(np.ascontiguousarray(frame).tobytes())
        self.video_frame_id = frame_id

    def update_palette(self, index, dt):
        target = np.array(PALETTE_RGB[int(index) % len(PALETTE_RGB)], dtype="f4")
        self.palette += (target - self.palette) * min(1.0, dt * 2.5)  # ~0.4s crossfade

    # ---- render --------------------------------------------------------

    def _meter(self, tex):
        """Auto-exposure on the composited frame (scene + bloom + trails): its 1x1 mip is the average
        colour. Above a mean luma of 0.32 the exposure steps down; below it creeps back up to 1.
        It never brightens past 1, so dark presets are untouched."""
        self._frame += 1
        if not self.auto_exposure:
            self.exposure = 1.0
            return
        if self._frame % 15:  # the readback stalls the GPU briefly, so keep it rare on the Pi
            return
        tex.build_mipmaps()
        tex.filter = (moderngl.LINEAR, moderngl.LINEAR)  # build_mipmaps switches to mip filtering; undo
        level = int(np.floor(np.log2(max(self.internal_size))))
        r, g, b = tex.read(level=level)[:3]
        mean = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
        self.exposure *= (0.32 / mean) ** 0.5 if mean > 0.32 else 1.08
        self.exposure = min(1.0, max(0.35, self.exposure))

    @staticmethod
    def _set(prog, name, value):
        if name in prog:
            prog[name].value = value

    def render(self, preset, P, state, audio, target=None):
        """P = ParamSet, state = dict of times/flags from the app, audio = AudioInput.
        target defaults to the window; pass an fbo to render offscreen."""
        ctx = self.ctx
        react = P.v("react")
        prev_fbo, prev_tex = self.comp[self.cur]
        out_fbo, out_tex = self.comp[1 - self.cur]
        res = tuple(float(x) for x in self.internal_size)

        self.fft_tex.write(audio.fft.tobytes())
        prev_tex.use(0)
        self.video_tex.use(1)
        self.fft_tex.use(2)

        # Scene
        prog = preset.program
        self.scene_fbo.use()
        ctx.viewport = (0, 0) + self.internal_size
        s = self._set
        s(prog, "uRes", res)
        s(prog, "uTime", state["time"])
        s(prog, "uPulse", state["pulse"])
        s(prog, "uRealTime", state["real_time"])
        for knob in "abcd":
            s(prog, "u" + knob.upper(), P.v(knob))
        s(prog, "uZoom", P.v("zoom"))
        s(prog, "uBass", min(1.0, audio.bass * react))
        s(prog, "uMid", min(1.0, audio.mid * react))
        s(prog, "uHigh", min(1.0, audio.high * react))
        s(prog, "uLevel", min(1.0, audio.level * react))
        s(prog, "uBeat", audio.beat * min(1.0, react))
        s(prog, "uBeatCount", float(audio.beat_count))
        s(prog, "uVideoOn", 1.0 if self.video_on else 0.0)
        s(prog, "uVideo360", 1.0 if self.video_360 else 0.0)
        s(prog, "uCamView", P.v("cam_view"))
        s(prog, "uCamYaw", state.get("cam_yaw", 0.0))
        s(prog, "uPrev", 0)
        s(prog, "uVideo", 1)
        s(prog, "uFFT", 2)
        if "uPal" in prog:
            prog["uPal"].write(self.palette.tobytes())
        preset.vao.render(moderngl.TRIANGLES)
        self.scene_tex.build_mipmaps()

        # Composite (feedback loop)
        out_fbo.use()
        cp = self.comp_prog
        self.scene_tex.use(3)
        s(cp, "uScene", 3)
        s(cp, "uPrev", 0)
        s(cp, "uVideo", 1)
        s(cp, "uRes", res)
        s(cp, "uTime", state["time"])
        s(cp, "uFeedback", P.v("feedback"))
        s(cp, "uFbZoom", P.v("fb_zoom"))
        s(cp, "uFbRot", P.v("fb_rotate"))
        s(cp, "uFbHue", P.v("fb_hue"))
        s(cp, "uKaleido", P.v("kaleido"))
        s(cp, "uWarp", P.v("warp"))
        s(cp, "uChroma", P.v("chroma"))
        s(cp, "uGlow", P.v("glow"))
        s(cp, "uExposure", self.exposure)
        s(cp, "uTransition", state.get("transition", 0.0))
        s(cp, "uVideoMix", P.v("video_mix"))
        s(cp, "uVideoOn", 1.0 if self.video_on else 0.0)
        s(cp, "uVideo360", 1.0 if self.video_360 else 0.0)
        s(cp, "uCamView", P.v("cam_view"))
        s(cp, "uCamYaw", state.get("cam_yaw", 0.0))
        s(cp, "uBeat", audio.beat * min(1.0, react))
        s(cp, "uBass", min(1.0, audio.bass * react))
        self.comp_vao.render(moderngl.TRIANGLES)
        self._meter(out_tex)

        # Display
        target = target or ctx.screen
        target.use()
        ctx.viewport = (0, 0) + tuple(self.screen_size)
        dp = self.disp_prog
        out_tex.use(0)
        s(dp, "uComp", 0)
        s(dp, "uHue", P.v("hue"))
        s(dp, "uSat", P.v("saturation"))
        s(dp, "uBright", P.v("brightness"))
        s(dp, "uContrast", P.v("contrast"))
        s(dp, "uInvert", P.v("invert"))
        s(dp, "uStrobe", P.v("strobe"))
        s(dp, "uBeat", audio.beat)
        s(dp, "uFlash", state["flash"])
        s(dp, "uBlackout", state["blackout"])
        s(dp, "uTime", state["real_time"])
        self.disp_vao.render(moderngl.TRIANGLES)

        self.cur = 1 - self.cur
        return out_tex
