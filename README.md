# GoonViz

A live visual synth for projectors. GPU shader presets in the visionary-art vein (glowing filigree,
sacred geometry, fractals, crystal caves), played from a MIDI controller, reacting to audio, and
able to chew on live video.

It runs two ways from the same presets, palettes and MIDI maps:
- **In Chrome on a Mac** (Intel or Apple Silicon), at **https://goonviz.live** or offline from this folder. This is the main setup.
- **On a Raspberry Pi** as a boot-to-visuals box. See [Raspberry Pi](#shopping-list) below.

## On a Mac (Chrome)

Needs **Google Chrome** (or Edge); Safari can't talk to MIDI controllers.

1. Open **https://goonviz.live** in Chrome, or, with no internet, double-click **Open GoonViz.command** in this folder.
   The first time, macOS may say it's from an unidentified developer: right-click it → Open.
2. Plug in the MPD32 (load its preset **18 ArkaosVJ**), click **Start GoonViz**, and allow the camera, microphone and MIDI.
3. Pick the camera and audio input in the panel on the right. A USB audio interface fed from the mixer locks to the beat
   best. **Demo beat** works with no audio at all.
4. Connect the projector as a **separate display** (not mirrored), then click **⛶ Projector** (or press **F**). Chrome asks once
   for permission to use your displays, then sends the visuals fullscreen to the projector. **Esc** comes back.

**On a phone or tablet** it works too (open goonviz.live): swipe the visuals left/right to change preset and
double-tap for fullscreen (on iPhone, which can't fullscreen a page, it fills the screen instead). Phones get a
lighter profile automatically (lower internal resolution, and a steady 30 fps on the heaviest presets if 60 isn't
possible) while desktops keep full quality. MIDI controllers work in Chrome on Android, but not on iPhone/iPad
(no browser there supports MIDI).

Before a show:
- Plug the MacBook into power. A MacBook Air has no fan, so expect it to get warm; if the frame rate drops, set
  **Quality** to Medium.
- Turn off auto-lock: System Settings → Lock Screen → turn off the screen saver and display sleep while on power.
- Print the [cheat sheet](docs/akai_mpd32_cheatsheet.pdf).

**Indicator:** while you learn the controller, every move pops up in the bottom-left corner for a moment
(e.g. `F1 · Trails 0.62`, `S7 · Blackout ON`, `Pad C14 · 31 · Hyperbolic Honeycomb`), in fullscreen too, so it also
shows on the projector. Turn it off with the **Indicator** checkbox in Settings or the **I** key.

**MIDI learn** in the browser: every slider, button and preset has a small **L**. Click it, move a control, done.
Changes and snapshots are saved in that Mac's Chrome. Use **Export settings** / **Import** to copy them to your other Mac.

**Quality: Auto** renders at about 1440 px wide, or about 960 px on Intel graphics (Intel MacBook Pros), and upscales to the
projector. Bloom and colour grading always run at full resolution. On top of that, **adaptive resolution** watches the
frame rate: if frames run late it renders slightly fewer pixels, and steps back up when there's headroom, so heavy
presets stay smooth. The fps readout shows `actual/display` (e.g. `60/60`). A 60 Hz screen or projector can't show
more than 60 fps; on a 120 Hz display GoonViz will run at 120 when the preset allows.

The **3D and 4D sets** are raymarched: full scenes with lighting. 3D: Mandelbox, Apollonian Foam, Fractal Cathedral,
Mandelbulb Bloom, Chrome Lattice. 4D (four-dimensional shapes sliced into 3D as they turn through the 4th
dimension): Quaternion Julia, Tesseract Lattice, Hyper Crystal, Hypergyroid. Hyperbolic: Hyperbolic Honeycomb,
a flight through the {4,3,5} honeycomb (cubes, five around every edge) in the Poincaré ball that loops seamlessly. They're the heaviest presets and are
meant for the Mac; on a Pi they'll crawl.

**On a Raspberry Pi** (the website in Chromium, or the native app) GoonViz recognises the Pi and uses a light
profile: a lower starting resolution, a steady 30 fps fallback, and the heavy 3D/4D presets (marked "3D" on the
Pi) are left out of random picks and autopilot so a hands-off show never lands on one that crawls. You can still
pick them by hand. To try the Pi profile on another machine, open `goonviz.live/?profile=pi`
(`?profile=mobile` and `?profile=desktop` work too). Presets opt in to this with `"heavy": true` in their header.

Retired presets live in `presets/archive/` (not loaded). To bring one back, move it into `presets/`, give it a
free number, and run `python3 tools/build_web.py`.

### Editing presets for the web version

The web app loads everything from `web/bundle.js`, built from `presets/`, `prism/shaders/`, `prism/palettes.py`,
`prism/params.py` and `maps/`. After editing any of those:

```bash
python3 tools/build_web.py
```

To publish to goonviz.live, commit, then run `tools/deploy_web.sh`. It pushes `main` and copies `web/` to the
`gh-pages` branch, which GitHub Pages serves.
To try changes locally first: `python3 -m http.server 8765 --directory web`, then open http://localhost:8765.

# Raspberry Pi

## Shopping list

| item | notes |
|---|---|
| **Raspberry Pi 5**, 4 GB or 8 GB | A Pi 4 works too, at a lower render resolution. Pi 3 and older can't run it. |
| **Official 27 W USB-C power supply** | Needed so the Pi can power the MPD32 and the X4 over USB. Others limit USB power. |
| **Pi 5 Active Cooler** (or a case with a fan) | Without it the Pi slows down when hot, and the frame rate drops mid-set. |
| **microSD card**, 32 GB or more, "A2" rated | e.g. SanDisk Extreme / Samsung PRO Plus. |
| **micro-HDMI → HDMI cable** | The Pi has *micro*-HDMI ports, so a normal HDMI cable won't fit. |
| **USB-C cable** for the Insta360 X4 | Use the one that came with the camera, or any USB 3 data cable (not charge-only). |
| USB-B cable for the MPD32 | Comes with it. |
| *Optional:* USB audio interface with line-in | Locks to the beat better than the camera mic when you have a mixer feed. |
| *Optional:* powered USB hub | Only if devices drop out (lightning-bolt icon on screen). |
| *Optional:* a USB keyboard | Only for MIDI learn or the on-screen overlay; not needed for shows. |

You also need a **microSD card reader** for your Mac if it has no SD slot.

## When the Pi arrives

Everything is prepared on the Mac side: an SSH key (`~/.ssh/id_ed25519`) so the Pi can be set up
without typing passwords, and a one-command installer.

1. **Flash the card** with [Raspberry Pi Imager](https://www.raspberrypi.com/software/):
   - **Device:** your Pi
   - **OS:** Raspberry Pi OS (other) → **Raspberry Pi OS Lite (64-bit)**
   - **Storage:** the SD card
   - **Customisation:**
     - **Hostname:** `prism`
     - **Username and password:** your choice
     - **Wi-Fi:** the same network as your Mac, and set the Wi-Fi country
     - **SSH:** on, **public-key authentication only**. Imager fills in the key from this Mac.
2. **Boot it:** card in, projector on **HDMI 0** (the port nearest the power jack), MPD32 and X4 plugged in, then power on.
   The first boot takes 2–3 minutes, ending at a login prompt on the projector.
3. **Install** from the Mac, in this folder:

   ```bash
   ./install_to_pi.sh yourname@prism.local
   ```

   This copies Prism over, installs everything, sets it to start on boot, reboots the Pi, and lists the
   MIDI ports, cameras and audio inputs it can see. Or ask Claude to run it and check the results.
4. **On the gear:** load preset **18 ArkaosVJ** on the MPD32, and pick **Webcam Mode** on the X4's USB menu.

After that, Prism starts by itself on every boot. Re-run `install_to_pi.sh` any time you edit presets
on the Mac; files changed on the Pi (like MIDI maps saved by MIDI learn) aren't overwritten.

Autostart drives the display directly (KMS), which is why it's **Pi OS Lite**. On the desktop image, set
`raspi-config → System → Boot → Console Autologin`.

### Manual install (without the Mac script)

Copy this folder to `~/prism` on the Pi, then:

```bash
cd ~/prism && bash setup_pi.sh --service && sudo reboot
```

Useful checks:

```bash
.venv/bin/python run.py --list-audio      # find your audio interface
.venv/bin/python run.py --midi-monitor    # see what your controller sends
sudo systemctl stop prism                 # stop the boot instance while you tinker
journalctl -u prism -f                    # logs
```

## Configure: `config.json`

| key | what |
|---|---|
| `render_scale` | Internal resolution. `0.5` = 960×540 on a 1080p projector. Pi 4: try `0.4`. |
| `audio.device` | Name fragment or index from `--list-audio`. Default `"Insta360"`; `null` = default input |
| `audio.fallback_to_default` | If that device is missing, use the default input instead of staying silent |
| `audio.gain` | Pre-gain. The analysis auto-levels, so this rarely needs touching |
| `video.source` | `"insta360"` (default, auto-detected), `0` (other USB cam / capture dongle), `"picam"`, a video file path (loops), or `null` (off) |
| `video.capture_size` | Resolution requested from the camera. 360 default `[1920, 960]`; `[2880, 1440]` is sharper but heavier on the Pi |
| `midi.map` | Which mapping file to use. Default `maps/akai_mpd32.json`; also `generic.json`, `nanokontrol2.json`, or your own |
| `midi.clock_beats` | If your DJ gear sends MIDI clock, use it for beats instead of audio detection |
| `midi.pickup` | Soft takeover: a knob does nothing until it reaches the current value (no jumps after preset changes) |
| `autopilot` | `enabled` (start with autopilot on) and `intensity` (0 calm … 1 wild) |

Everything also works as a flag: `run.py --windowed --video 0 --fake-audio --preset wormhole`.

## Akai MPD32

The map is built for the MPD32's **preset 1 "LiveLite"**, which is what it starts on, so there's nothing to set
up on the controller. It was recorded from a real MPD32: knobs K1–K8 send CC 22–29, faders F1–F8 CC 12–19,
switches S1–S8 CC 32–39 (they toggle: press once for on, again for off), and the transport buttons CC 115–119.
Control bank B sends the same numbers on MIDI channel 2.

**Print the cheat sheet:** [docs/akai_mpd32_cheatsheet.pdf](docs/akai_mpd32_cheatsheet.pdf) (two pages, US Letter landscape).
Page 1 shows every pad, knob, fader, switch and transport button; page 2 shows what knobs A–D do in each preset.
If you remap anything, regenerate it with `python tools/make_cheatsheet.py`.

The main layout:
- **Pad bank A:** presets 1–16. **Pad bank B:** preset 17, random, randomize, reset, prev/next, tap, flash, and snapshots 1–8.
- **Pad bank C:** presets 18–31.
- **Control bank A:**
  - Knobs: A–D, speed, zoom, palette, hue.
  - Faders: trails ×4, glow, kaleido, camera mix, MASTER.
  - Switches: autopilot, freeze, camera, strobe, invert, overlay, BLACKOUT, SHIFT.
- **Control bank B:** warp, chroma, saturation, contrast, audio react…, the 360 view and spin (faders F5, F6), and
  **autopilot intensity** (fader F7).
- **Transport:** ◀◀ / ▶▶ prev/next, ■ blackout, ▶ autopilot, ● randomize.

If you switch the MPD32 to a different preset, the numbers change. Re-map with MIDI learn (the **L** buttons), or
on the Pi run `.venv/bin/python run.py --learn-pads` and hit the pads in order.

## Insta360 X4

1. Turn the X4 on, connect it to the Pi with USB-C, and pick **Webcam Mode** on the camera's USB menu.
2. Prism finds it by name and asks for its 2:1 panorama (it's the default `video.source`).
3. Choose how the 360° image is projected with **360 view** (MPD32 bank B, F5):
   - flat panorama
   - look-around (a camera slowly panning the room)
   - **tiny planet** (the default)
   - rabbit hole

   **360 spin** (F6) sets the pan speed and direction.
4. The camera feeds the three video presets (15–17) and the **camera mix** fader (bank A, F7) over any preset.

Some caveats:
- **Linux support:** Insta360 only officially tests webcam mode with OBS. It's a standard USB (UVC) webcam, so Linux
  should see it, but check once with `v4l2-ctl --list-devices` (from the `v4l-utils` package).
- **Microphone:** whether the X4 exposes its mic over USB in webcam mode isn't documented. Run `--list-audio`. If no
  Insta360 entry appears, Prism falls back to the default input, so plug in a USB audio interface.
- **Power and heat:** long sessions on USB power can make the camera hot. Keep it ventilated.

## Autopilot

Turn it on (switch S1, ▶ PLAY on the MPD32, **A** on the keyboard, or the panel button) and GoonViz plays itself
like a VJ: it listens to the shape of the music and performs planned moves instead of random ones.
**Intensity** (bank B fader F7, or the slider in the panel) sets how hard:

| | calm (0) | middle (0.5) | wild (1) |
|---|---|---|---|
| preset changes | every 64 beats | every 32 beats | every 8 beats |
| moves | small and slow | bigger | full size, quick |
| drops | follow on the next phrase | hard cut to something intense | hard cut plus a flash |

- **Phrases:** changes land on phrase boundaries (8/16/32/64 beats), never mid-phrase, unless the music drops.
- **Sections:** it compares the last second of loudness with the last ten or so. A sudden jump after a quieter
  stretch is a **drop**, so it cuts to an intense preset. A long quiet stretch is a **breakdown**, so it moves to
  a calm one. The panel shows what it's doing, e.g. "Dive · DROP · next change in 12 beats".
- **Choosing presets:** each preset has an energy (calm 1 … intense 3) and a style family (mandala, kaleido,
  2D fractal, organic, tunnel, 3D flight, 3D object, camera). It picks one whose energy suits the music, in a
  different family from the last, and not one shown recently. Camera presets only come up while the camera
  is on, and heavy 3D/4D ones never on a Pi.
- **Routines:** each phrase it performs one move that suits the preset: *Spin* (trails swirl, the kaleidoscope
  steps up each bar), *Bloom* (glow and trails build toward the change), *Dive* (fly faster, trails stream
  forward), *Breathe* (zoom and glow pulse in four-bar cycles), *Colour walk* (the hue wanders away and back)
  or *Drift*. Underneath, the other knobs drift gently within ranges that keep the picture good-looking.

Any knob you move yourself is left alone until the next change, so you can steer one thing while autopilot
handles the rest.

Presets **melt** into each other over about a second instead of cutting. Knobs a preset uses as a count
(petals, polygon sides, chambers: anything it rounds to a whole number) are never glided by autopilot,
because the shape would pop each time the count changed.

**Auto-exposure** watches the average brightness of the picture and dims it smoothly if a combination washes
out. It never brightens, so dark presets are untouched and flashes still hit full white.

## Controls

Every preset has four of its own knobs (**a, b, c, d**; the HUD shows what each one does for
that preset) plus shared FX and master controls:

- **speed, zoom**
- **feedback, fb_zoom, fb_rotate, fb_hue**: Milkdrop-style trails, tunnels and hue drift
- **kaleido** (0 = off, 2–12 mirror segments), **warp**, **chroma** (RGB split)
- **glow**: bloom haze; **palette**: 10 curated palettes (including Jade and Cicada) that crossfade when switched
- **hue, saturation, brightness, contrast, invert**: master grading, kept when presets change
- **video_mix**: blend the camera over any preset
- **cam_view, cam_spin**: 360-camera projection (flat / look-around / tiny planet / rabbit hole) and pan
- **react**: how hard the audio drives everything; **strobe**: white flash on the beat

Actions (mappable to pads/buttons): `next` `prev` `random_preset` `randomize` `reset`
`autopilot` `blackout` `flash` (held) `freeze` `shift` (held) `tap` `video` `hud`
`preset:N` `snapshot:N`. Hold **shift** + a snapshot button to save the current look;
press it alone to recall it.

### MIDI mapping

**MIDI learn** (plug in a keyboard once): press `H` to show the HUD, use ↑/↓ to pick a knob or
action, press `L`, then move the control. It's saved to the active map file immediately.

Or edit the map JSON directly: `"cc": {"21": "feedback"}`, `"note": {"36": "preset:0"}`.
Prefix a channel to restrict it: `"10:36"`. Program Change messages select presets.

### Keyboard (for setup)

| key | | key | |
|---|---|---|---|
| ← → | prev / next preset | 1–0 | presets 1–10 |
| ↑ ↓ | select knob/action | `-` `=` | adjust (shift = coarse) |
| Enter | trigger selected action | L | MIDI learn |
| F1–F8 | recall snapshot (shift = save) | R / P | randomize FX / random preset |
| A | autopilot | B | blackout |
| Space | flash (held) | Z | freeze |
| T | tap beat | V | video on/off |
| H | HUD | Backspace | reset knobs |
| F5 | reload changed presets | Esc | quit |

## Presets

`presets/*.glsl`, ordered by filename. The first line is a JSON header:

```glsl
// @preset {"name": "My Thing", "labels": {"a": "twist"}, "params": {"feedback": 0.6, "palette": 2}}
vec3 scene(vec2 p, vec2 uv) {
    float r = length(p);
    return glowpal(r - uTime * 0.1) * 0.004 / (abs(r - 0.5) + 0.004);
}
```

`p` is centered and aspect-correct; `uv` runs 0–1. Available inside a preset:

- **time:** `uTime` (speed-scaled), `uPulse` (lurches forward on bass)
- **knobs:** `uA`–`uD`
- **audio:** `uBass` `uMid` `uHigh` `uLevel` `uBeat` `fft(x)`
- **inputs:** `video(uv)`, `prev(uv)` (last frame)
- **palette:** `pal(t)` (whole palette), `glowpal(t)` (skips the dark stop)
- **helpers:** `fbm` `noise` `rot` `kaleido` `hueRotate` …, all in `prism/shaders/lib.glsl`

Output can go above 1.0: a filmic tonemap and bloom handle it. Lines drawn as
`k / (distance + k)` give the luminous look.

**Live coding:** while Prism runs, save a preset file and it recompiles in about a second.
A broken shader keeps the last good version and prints the error.

**Preview without a Pi:** `python tools/render_presets.py` renders every preset offscreen to
`preview/contact_sheet.png` (needs `pip install moderngl numpy pillow`).

Palettes live in `prism/palettes.py`: five hex colours each, darkest first.

## Performance tips

- Start with `render_scale` 0.5 (Pi 5) or 0.4 (Pi 4). Bloom and grading run at full resolution regardless.
- The heaviest presets are Crystal Caverns, Julia Bloom and Apollonian Lace. Their **c** knob is quality/detail.
- Cool the Pi (an active cooler on a Pi 5). Thermal throttling looks like a slow fps decline mid-set.
