"""Prism: the live app. Window, main loop, keyboard + MIDI control, snapshots, autopilot."""

import argparse
import json
import math
import os
import random
import sys
import time

from .midi import STATE_ACTIONS

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DEFAULT_CONFIG = {
    "fullscreen": True,
    "window_size": [1280, 720],
    "render_scale": 0.5,
    "max_fps": 60,
    "start_preset": 0,
    "audio": {"device": None, "samplerate": 48000, "gain": 1.0, "fake": False, "noise_floor": 0.015},
    "video": {"source": None, "width": 640, "height": 360, "capture_size": None},
    "midi": {"port": None, "map": "maps/akai_mpd32.json", "clock_beats": True, "pickup": False},
    "autopilot": {"enabled": False, "intensity": 0.5},
    "snapshots": "snapshots.json",
}

TRANSITION_SECONDS = 1.2  # how long the old preset takes to melt into the new one

ACTION_ITEMS = ["next", "prev", "random_preset", "randomize", "reset", "autopilot", "blackout",
                "flash", "freeze", "shift", "tap", "video", "hud"] + [f"snapshot:{i}" for i in range(8)]


def deep_merge(base, override):
    out = dict(base)
    for k, v in override.items():
        out[k] = deep_merge(out[k], v) if isinstance(v, dict) and isinstance(out.get(k), dict) else v
    return out


def load_config(path):
    cfg = DEFAULT_CONFIG
    if path and os.path.exists(path):
        with open(path) as f:
            cfg = deep_merge(cfg, json.load(f))
    return cfg


def rel(path):
    return path if os.path.isabs(path) else os.path.join(ROOT, path)


class App:
    def __init__(self, cfg):
        import pygame
        import moderngl
        from .engine import Engine, glsl_header
        from .params import ParamSet
        from .audio import AudioInput
        from .video import VideoInput
        from .midi import MidiInput, MidiMap
        from .hud import Hud
        from .autopilot import Autopilot
        from .params import KALEIDO_CHAOS
        from .palettes import PALETTES

        self.pg = pygame
        self.cfg = cfg
        if sys.platform.startswith("linux") and not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY"):
            os.environ.setdefault("SDL_VIDEODRIVER", "kmsdrm")  # Pi OS Lite: straight to the HDMI output
        pygame.init()
        if sys.platform == "darwin":
            pygame.display.gl_set_attribute(pygame.GL_CONTEXT_MAJOR_VERSION, 3)
            pygame.display.gl_set_attribute(pygame.GL_CONTEXT_MINOR_VERSION, 3)
            pygame.display.gl_set_attribute(pygame.GL_CONTEXT_PROFILE_MASK, pygame.GL_CONTEXT_PROFILE_CORE)
            pygame.display.gl_set_attribute(pygame.GL_CONTEXT_FORWARD_COMPATIBLE_FLAG, True)

        flags = pygame.OPENGL | pygame.DOUBLEBUF
        if cfg["fullscreen"]:
            flags |= pygame.FULLSCREEN
            size = (0, 0)
        else:
            size = tuple(cfg["window_size"])
        pygame.display.set_mode(size, flags, vsync=1)
        pygame.display.set_caption("GoonViz")
        pygame.mouse.set_visible(not cfg["fullscreen"])

        self.ctx = moderngl.create_context(require=310)
        print(f"[gl] {self.ctx.info['GL_RENDERER']} / {self.ctx.info['GL_VERSION']}")
        screen_size = tuple(self.ctx.screen.viewport[2:])

        self.params = ParamSet()
        self.engine = Engine(self.ctx, screen_size, scale=cfg["render_scale"])
        self.presets = self.engine.presets
        self.hud = Hud(self.ctx, glsl_header(self.ctx))

        a = cfg["audio"]
        self.audio = AudioInput(device=a["device"], samplerate=a["samplerate"], fake=a["fake"],
                                gain=a["gain"], noise_floor=a["noise_floor"],
                                fallback_to_default=a.get("fallback_to_default", True))
        v = cfg["video"]
        self.video = None
        if v["source"] not in (None, "", "none"):
            self.video = VideoInput(v["source"], size=(v["width"], v["height"]),
                                    capture_size=v.get("capture_size"))
            self.video.start()

        m = cfg["midi"]
        self.midi = MidiInput(m["port"])
        self.midi_map = MidiMap(rel(m["map"]))
        self.pickup = m["pickup"]
        self.picked = set()
        self.clock_ticks = 0

        self.snap_path = rel(cfg["snapshots"])
        self.snapshots = {}
        if os.path.exists(self.snap_path):
            with open(self.snap_path) as f:
                self.snapshots = json.load(f)

        self.pilot = Autopilot(self.params, KALEIDO_CHAOS, len(PALETTES))
        self.pilot.enabled = cfg["autopilot"]["enabled"]
        self.params["ap_intensity"].set_value(cfg["autopilot"].get("intensity", 0.5), immediate=True)
        self.items = [p.name for p in self.params.list] + ACTION_ITEMS
        self.selected = 0
        self.learning = False
        self.show_hud = False
        self.shift = False
        self.frozen = False
        self.blackout_target = 0.0
        self.flash_held = False
        self.message, self.message_until = "", 0.0
        self.state = {"time": 0.0, "pulse": 0.0, "real_time": 0.0, "flash": 0.0, "blackout": 0.0,
                      "cam_yaw": 0.0, "transition": 0.0}
        self.fps = 0.0
        self.last_reload_check = 0.0
        self.last_beat_count = 0

        self.preset_index = 0
        self.select_preset(self._find_start_preset(cfg["start_preset"]))

    # ---- presets / snapshots -----------------------------------------

    def _find_start_preset(self, start):
        if isinstance(start, str):
            for i, p in enumerate(self.presets):
                if p.key == start or p.name.lower() == start.lower():
                    return i
            return 0
        return int(start) % len(self.presets)

    def select_preset(self, index):
        n = len(self.presets)
        for step in range(n):  # skip presets that failed to compile
            preset = self.presets[(index + step) % n]
            if preset.program:
                break
        if hasattr(self, "state") and self.presets[self.preset_index] is not preset:
            self.state["transition"] = 1.0   # melt from the old preset into this one
        self.preset_index = self.presets.index(preset)
        self.params.load_preset(preset.params)
        self.picked.clear()
        if hasattr(self, "pilot"):
            self.pilot.start_preset(preset.stepped)
        self.notify(preset.name)

    @property
    def preset(self):
        return self.presets[self.preset_index]

    def save_snapshot(self, slot):
        self.snapshots[str(slot)] = {"preset": self.preset.key, "params": self.params.snapshot()}
        with open(self.snap_path, "w") as f:
            json.dump(self.snapshots, f, indent=2)
        self.notify(f"saved snapshot {slot}")

    def recall_snapshot(self, slot):
        snap = self.snapshots.get(str(slot))
        if not snap:
            self.notify(f"snapshot {slot} is empty (shift+press to save)")
            return
        for i, p in enumerate(self.presets):
            if p.key == snap["preset"]:
                self.preset_index = i
        self.params.restore(snap["params"])
        self.picked.clear()
        self.notify(f"snapshot {slot}")

    def notify(self, text):
        print(f"[prism] {text}")
        self.message, self.message_until = text, time.monotonic() + 2.0

    # ---- actions -------------------------------------------------------

    def do_action(self, action, pressed=True):
        if action == "shift":
            self.shift = pressed
        elif action == "flash":
            self.flash_held = pressed
        if not pressed:
            return
        n = len(self.presets)
        if action == "next":
            self.select_preset((self.preset_index + 1) % n)
        elif action == "prev":
            self.select_preset((self.preset_index - 1) % n)
        elif action == "random_preset":
            choices = [i for i in range(n) if i != self.preset_index] or [0]
            self.select_preset(random.choice(choices))
        elif action == "randomize":
            self.params.randomize()
            self.picked.clear()
        elif action == "reset":
            self.params.load_preset(self.preset.params)
            self.picked.clear()
        elif action == "autopilot":
            self.pilot.enabled = not self.pilot.enabled
            if self.pilot.enabled:
                self.pilot.home_hue = None
                self.pilot.start_preset(self.preset.stepped)
            self.notify(f"autopilot {'on' if self.pilot.enabled else 'off'}")
        elif action == "blackout":
            self.blackout_target = 1.0 - self.blackout_target
        elif action == "freeze":
            self.frozen = not self.frozen
        elif action == "tap":
            self.audio.trigger_beat()
        elif action == "video" and self.video:
            self.video.toggle()
            self.notify(f"video {'on' if self.video.active else 'off'}")
        elif action == "hud":
            self.show_hud = not self.show_hud
        elif action.startswith("preset:"):
            self.select_preset(int(action.split(":")[1]) % n)
        elif action.startswith("snapshot:"):
            slot = int(action.split(":")[1])
            self.save_snapshot(slot) if self.shift else self.recall_snapshot(slot)

    def set_state(self, action, on):
        if action == "blackout":
            self.blackout_target = 1.0 if on else 0.0
        elif action == "freeze":
            self.frozen = on
        elif action == "autopilot":
            if self.pilot.enabled != on:
                self.do_action("autopilot")
        elif action == "video" and self.video:
            self.video.active = on
        elif action == "hud":
            self.show_hud = on
        elif action == "shift":
            self.shift = on

    def apply(self, target, value, pressed, source="note"):
        if target in self.params:
            p = self.params[target]
            if self.pickup and target not in self.picked:
                # Soft takeover: ignore the knob until it reaches the current value.
                if abs(value - p.target) > 0.04:
                    return
                self.picked.add(target)
            p.set_norm(value)
            self.pilot.touch(target)
            return
        latching = source in ("cc", "toggle_pad")
        if target in STATE_ACTIONS and latching:
            self.set_state(target, pressed)     # switch/pad state == action state
        elif source == "toggle_pad":
            # A latching pad sends note-on on one hit and note-off on the next,
            # so every message is a hit. Flash becomes a one-shot burst.
            if target == "flash":
                self.state["flash"] = 1.0
            else:
                self.do_action(target, True)
        else:
            self.do_action(target, pressed)

    # ---- input ---------------------------------------------------------

    def handle_midi(self, msg):
        if msg.type == "clock":
            if self.cfg["midi"]["clock_beats"]:
                self.clock_ticks += 1
                self.audio.external_beats_until = time.monotonic() + 1.0
                if self.clock_ticks % 24 == 0:
                    self.audio.trigger_beat()
            return
        if msg.type == "start":
            self.clock_ticks = 0
            return
        if self.learning:
            result = self.midi_map.learn(msg, self.items[self.selected])
            if result:
                self.learning = False
                self.notify(f"learned {result}")
            return
        resolved = self.midi_map.resolve(msg)
        if resolved:
            self.apply(*resolved)

    def handle_key(self, event):
        pg = self.pg
        down = event.type == pg.KEYDOWN
        k = event.key
        if k == pg.K_SPACE:
            self.do_action("flash", down)
            return
        if not down:
            return
        mods = pg.key.get_mods()
        shift = bool(mods & pg.KMOD_SHIFT)
        item = self.items[self.selected]
        step = 0.1 if shift else 0.02

        if k in (pg.K_ESCAPE, pg.K_q):
            self.running = False
        elif k == pg.K_RIGHT:
            self.do_action("next")
        elif k == pg.K_LEFT:
            self.do_action("prev")
        elif k == pg.K_DOWN:
            self.selected = (self.selected + 1) % len(self.items)
            self.show_hud = True
        elif k == pg.K_UP:
            self.selected = (self.selected - 1) % len(self.items)
            self.show_hud = True
        elif k in (pg.K_EQUALS, pg.K_RIGHTBRACKET, pg.K_KP_PLUS) and item in self.params:
            self.params[item].nudge(step)
            self.pilot.touch(item)
        elif k in (pg.K_MINUS, pg.K_LEFTBRACKET, pg.K_KP_MINUS) and item in self.params:
            self.params[item].nudge(-step)
            self.pilot.touch(item)
        elif k == pg.K_RETURN and item not in self.params:
            self.do_action(item)
        elif k == pg.K_l:
            self.learning = not self.learning
            self.show_hud = True
            if self.learning:
                self.notify(f"MIDI learn: move a control for '{item}'")
        elif pg.K_F1 <= k <= pg.K_F8:
            slot = k - pg.K_F1
            self.save_snapshot(slot) if shift else self.recall_snapshot(slot)
        elif pg.K_0 <= k <= pg.K_9:
            self.select_preset((k - pg.K_1) % 10)
        elif k == pg.K_F5:
            for p in self.presets:
                self.engine.reload_if_changed(p)
        else:
            keymap = {pg.K_r: "randomize", pg.K_p: "random_preset", pg.K_BACKSPACE: "reset",
                      pg.K_a: "autopilot", pg.K_b: "blackout", pg.K_z: "freeze", pg.K_t: "tap",
                      pg.K_v: "video", pg.K_h: "hud"}
            if k in keymap:
                self.do_action(keymap[k])

    # ---- per-frame -----------------------------------------------------

    def tick_autopilot(self, dt):
        beats = self.audio.beat_count - self.last_beat_count
        self.last_beat_count = self.audio.beat_count
        for event in self.pilot.update(dt, beats):
            if event == "switch":
                self.do_action("random_preset")
                self.pilot.on_switched()
            elif event == "flash":
                self.state["flash"] = 0.7

    def hud_lines(self):
        white, dim, hot, warn = (235, 235, 235), (140, 140, 160), (255, 200, 90), (255, 110, 110)
        p = self.preset
        a = self.audio
        bar = lambda x, n=10: "#" * int(round(min(1, max(0, x)) * n)) + "." * (n - int(round(min(1, max(0, x)) * n)))
        lines = [
            (f"{p.name}  [{self.preset_index + 1}/{len(self.presets)}]   {self.fps:4.1f} fps", white),
            (f"audio {a.status:8s} bass {bar(a.bass)} mid {bar(a.mid)} high {bar(a.high)} beat {'*' if a.beat > 0.5 else ' '}", dim),
            (f"video {self.video.status if self.video else 'none'}   midi {', '.join(self.midi.ports) or 'no device'}", dim),
            (f"last midi: {self.midi.last_message}", dim),
        ]
        flags = [f for f, on in ((f"AUTOPILOT {self.pilot.intensity:.0%}", self.pilot.enabled), ("FROZEN", self.frozen),
                                 ("BLACKOUT", self.blackout_target > 0), ("SHIFT", self.shift)) if on]
        if flags:
            lines.append(("  ".join(flags), hot))
        if self.learning:
            lines.append((f"MIDI LEARN -> {self.items[self.selected]}: move a knob or hit a pad", warn))
        lines.append(("", dim))
        lo = max(0, min(self.selected - 8, len(self.items) - 18))
        for i in range(lo, min(lo + 18, len(self.items))):
            name = self.items[i]
            label = name
            if name in self.params:
                prm = self.params[name]
                if name in p.labels:
                    label = f"{name} ({p.labels[name]})"
                text = f"{label:22s} {bar(prm.target, 16)} {prm.target_value:7.2f}"
            else:
                text = f"{label:22s} [action]"
            lines.append(((">" if i == self.selected else " ") + text, hot if i == self.selected else white))
        if p.error:
            lines.append(("shader error: see terminal", warn))
        if time.monotonic() < self.message_until:
            lines.append((self.message, hot))
        return lines

    def run(self):
        pg = self.pg
        clock = pg.time.Clock()
        self.running = True
        hud_lines, hud_next = None, 0.0
        start = time.monotonic()
        while self.running:
            dt = min(clock.tick(self.cfg["max_fps"]) / 1000.0, 0.1)
            now = time.monotonic()
            self.fps += (clock.get_fps() - self.fps) * 0.05

            for event in pg.event.get():
                if event.type == pg.QUIT:
                    self.running = False
                elif event.type in (pg.KEYDOWN, pg.KEYUP):
                    self.handle_key(event)
            for msg in self.midi.poll():
                self.handle_midi(msg)

            self.audio.update(dt)
            self.params.update(dt)
            self.tick_autopilot(dt)
            self.engine.update_video(self.video)
            self.engine.update_palette(self.params.v("palette"), dt)

            P, st = self.params, self.state
            if not self.frozen:
                speed = P.v("speed")
                st["time"] += dt * speed
                st["pulse"] += dt * speed * (1.0 + self.audio.bass * P.v("react") * 1.5)
            st["real_time"] = now - start
            st["cam_yaw"] = (st["cam_yaw"] + dt * P.v("cam_spin") * 0.6) % (2.0 * math.pi)
            st["flash"] = 1.0 if self.flash_held else st["flash"] * math.exp(-dt * 10.0)
            st["blackout"] += (self.blackout_target - st["blackout"]) * (1.0 - math.exp(-dt * 4.0))
            st["transition"] = max(0.0, st["transition"] - dt / TRANSITION_SECONDS)

            if now - self.last_reload_check > 1.0:  # live-code presets: save the .glsl and it reloads
                self.last_reload_check = now
                self.engine.reload_if_changed(self.preset)

            self.engine.render(self.preset, P, st, self.audio)
            if self.show_hud:
                if now >= hud_next:  # rebuilding text every frame is wasteful on a Pi
                    hud_lines, hud_next = self.hud_lines(), now + 0.1
                self.hud.draw(hud_lines, self.engine.screen_size)
            pg.display.flip()

        self.audio.close()
        self.midi.close()
        if self.video:
            self.video.stop()
        pg.quit()


def main(argv=None):
    ap = argparse.ArgumentParser(description="Prism: audio/video reactive visual synth")
    ap.add_argument("--config", default=os.path.join(ROOT, "config.json"))
    ap.add_argument("--windowed", action="store_true", help="run in a window instead of fullscreen")
    ap.add_argument("--size", help="window size, e.g. 1280x720")
    ap.add_argument("--scale", type=float, help="internal render scale (0.5 = half res, faster)")
    ap.add_argument("--preset", help="start on this preset (file name or display name)")
    ap.add_argument("--video", help="video source: 0 (USB/HDMI capture), picam, or a file path")
    ap.add_argument("--audio-device", help="sounddevice input name or index")
    ap.add_argument("--fake-audio", action="store_true", help="synthetic 124bpm beat, no input needed")
    ap.add_argument("--midi-port", help="only open MIDI ports containing this text")
    ap.add_argument("--map", help="MIDI map json file")
    ap.add_argument("--autopilot", action="store_true")
    ap.add_argument("--list-audio", action="store_true", help="list audio inputs and exit")
    ap.add_argument("--midi-monitor", action="store_true", help="print incoming MIDI and exit")
    ap.add_argument("--learn-pads", action="store_true", help="hit each pad in order to fix the map's pad notes")
    args = ap.parse_args(argv)

    if args.list_audio:
        from .audio import list_devices
        list_devices()
        return
    if args.midi_monitor:
        from .midi import monitor
        monitor()
        return

    cfg = load_config(args.config)
    if args.learn_pads:
        from .midi import learn_pads
        learn_pads(rel(args.map or cfg["midi"]["map"]))
        return
    if args.windowed:
        cfg["fullscreen"] = False
    if args.size:
        cfg["window_size"] = [int(x) for x in args.size.lower().split("x")]
    if args.scale:
        cfg["render_scale"] = args.scale
    if args.preset:
        cfg["start_preset"] = args.preset
    if args.video:
        cfg["video"]["source"] = args.video
    if args.audio_device:
        dev = args.audio_device
        cfg["audio"]["device"] = int(dev) if dev.isdigit() else dev
    if args.fake_audio:
        cfg["audio"]["fake"] = True
    if args.midi_port:
        cfg["midi"]["port"] = args.midi_port
    if args.map:
        cfg["midi"]["map"] = args.map
    if args.autopilot:
        cfg["autopilot"]["enabled"] = True

    App(cfg).run()
