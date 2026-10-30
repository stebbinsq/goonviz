#!/usr/bin/env python3
"""Build a printable cheat sheet (HTML, and PDF if Chrome is installed) from a MIDI map.

    python tools/make_cheatsheet.py                       # uses the map in config.json
    python tools/make_cheatsheet.py maps/akai_mpd32.json

Re-run after MIDI learn and the sheet matches your controller again.
Output: docs/<map name>_cheatsheet.html / .pdf  (US Letter, landscape, 2 pages)
"""

import html
import json
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from prism.engine import load_presets  # noqa: E402

PARAM_INFO = {
    "a": ("Knob A", "preset's own control"), "b": ("Knob B", "preset's own control"),
    "c": ("Knob C", "preset's own control"), "d": ("Knob D", "preset's own control"),
    "speed": ("Speed", "time rate"), "zoom": ("Zoom", "scale the scene"),
    "feedback": ("Trails", "feedback amount"), "fb_zoom": ("Trail zoom", "tunnel in / out"),
    "fb_rotate": ("Trail spin", "swirl left / right"), "fb_hue": ("Trail hue", "rainbow drift"),
    "kaleido": ("Kaleido", "off → 12 mirrors"), "warp": ("Warp", "liquid distortion"),
    "chroma": ("Chroma", "RGB split"), "glow": ("Glow", "bloom haze"),
    "palette": ("Palette", "10 colour sets"), "hue": ("Hue", "master colour shift"),
    "saturation": ("Saturation", "grey → vivid"), "brightness": ("MASTER", "brightness"),
    "contrast": ("Contrast", ""), "video_mix": ("Camera mix", "blend live video"),
    "react": ("Audio react", "how hard sound hits"), "audio_sens": ("Mic sensitivity", "quiet room ↑ · loud club ↓"), "strobe": ("Strobe", "flash on beats"),
    "invert": ("Invert", "negative image"), "ap_intensity": ("Autopilot", "intensity: calm → wild"),
    "cam_view": ("360 view", "flat · look · planet · hole"), "cam_spin": ("360 spin", "pan the room ◀ ▶"),
}
ACTION_INFO = {
    "next": "Next ▶", "prev": "◀ Prev", "random_preset": "Random preset", "randomize": "Randomize FX",
    "reset": "Reset knobs", "autopilot": "Autopilot", "blackout": "BLACKOUT", "flash": "Flash",
    "freeze": "Freeze", "shift": "SHIFT", "tap": "Tap beat", "video": "Camera on/off", "hud": "Overlay",
}
HOT = {"blackout", "brightness", "shift"}


def label(target, presets):
    if target is None:
        return None, "", ""
    if target.startswith("preset:"):
        i = int(target.split(":")[1])
        name = presets[i].name if i < len(presets) else f"Preset {i + 1}"
        return "preset", f"{i + 1}", name
    if target.startswith("snapshot:"):
        n = int(target.split(":")[1]) + 1
        return "snap", f"Snap {n}", "SHIFT + hit = save"
    if target in PARAM_INFO:
        title, sub = PARAM_INFO[target]
        return ("hot" if target in HOT else "param"), title, sub
    return ("hot" if target in HOT else "action"), ACTION_INFO.get(target, target), ""


def cell(kind, title, sub, tag, cls=""):
    if kind is None:
        return f'<div class="ctl empty {cls}"><span class="tag">{tag}</span><b>—</b></div>'
    return (f'<div class="ctl {kind} {cls}"><span class="tag">{tag}</span>'
            f'<b>{html.escape(title)}</b><small>{html.escape(sub)}</small></div>')


def lookup(table, num):
    return table.get(str(num)) or next((v for k, v in table.items() if k.endswith(f":{num}")), None)


def pad_grid(notes, note_map, presets, bank, compact=False):
    # MPC layout: pad 1 bottom-left, pads 13-16 across the top. compact: only rows with something mapped
    rows = []
    for row in (3, 2, 1, 0):
        if compact and not any(lookup(note_map, notes[row * 4 + c]) for c in range(4)):
            continue
        cells = []
        for col in range(4):
            idx = row * 4 + col
            kind, title, sub = label(lookup(note_map, notes[idx]), presets)
            if kind == "preset":
                cells.append(f'<div class="pad preset"><span class="tag">{bank}{idx + 1}</span>'
                             f'<b class="num">{title}</b><small>{html.escape(sub)}</small></div>')
            elif kind is None:
                cells.append(f'<div class="pad empty"><span class="tag">{bank}{idx + 1}</span></div>')
            else:
                cells.append(f'<div class="pad {kind}"><span class="tag">{bank}{idx + 1}</span>'
                             f'<b>{html.escape(title)}</b><small>{html.escape(sub)}</small></div>')
        rows.append("".join(cells))
    return f'<div class="pads">{"".join(rows)}</div>'


def control_bank(bank, nums, cc_map, presets):
    out = []
    for group, letter, shape in (("knobs", "K", "knob"), ("faders", "F", "fader"), ("switches", "S", "switch")):
        if not any(lookup(cc_map, n) for n in nums[group]):
            continue  # nothing mapped on this row: leave it off the sheet
        cells = "".join(cell(*label(lookup(cc_map, n), presets), f"{letter}{i + 1}", shape)
                        for i, n in enumerate(nums[group]))
        out.append(f'<div class="rowlabel">{group}</div><div class="row8">{cells}</div>')
    return "".join(out)


CSS = """
@page { size: letter landscape; margin: 0.35in; }
* { box-sizing: border-box; }
body { margin: 0; font: 10px/1.25 "Helvetica Neue", Helvetica, Arial, sans-serif; color: #111; background: #fff;
       -webkit-print-color-adjust: exact; print-color-adjust: exact; }
.page { width: 10.3in; height: 7.8in; page-break-after: always; display: flex; flex-direction: column; gap: 8px; }
.page:last-child { page-break-after: auto; }
header { display: flex; justify-content: space-between; align-items: baseline; border-bottom: 2px solid #111; padding-bottom: 4px; }
h1 { font-size: 20px; margin: 0; letter-spacing: 0.5px; }
h1 span { font-weight: 400; color: #666; }
h2 { font-size: 11px; text-transform: uppercase; letter-spacing: 1.2px; margin: 0 0 4px; }
h2 em { font-style: normal; font-weight: 400; text-transform: none; letter-spacing: 0; color: #666; }
.note { font-size: 9.5px; color: #444; }
.main { display: grid; grid-template-columns: 3.55in 1fr; gap: 14px; flex: 1; }
.padbanks { display: flex; flex-direction: column; gap: 10px; }
.pads { display: grid; grid-template-columns: repeat(4, 1fr); gap: 4px; }
.pad { position: relative; height: 0.62in; border: 1.5px solid #111; border-radius: 5px; padding: 12px 4px 3px;
       display: flex; flex-direction: column; justify-content: center; align-items: center; text-align: center; }
.pad b { font-size: 10px; }
.pad b.num { font-size: 15px; }
.pad small { font-size: 7.5px; color: #333; line-height: 1.1; }
.tag { position: absolute; top: 2px; left: 4px; font-size: 7px; color: #888; font-weight: 700; }
.pad.preset { background: #f1f1f1; }
.pad.snap { background: #e6eefc; border-color: #2350a0; }
.pad.action { background: #fff; }
.pad.empty { border-style: dashed; border-color: #bbb; }
.banks { display: flex; flex-direction: column; gap: 10px; }
.rowlabel { font-size: 8px; text-transform: uppercase; letter-spacing: 1px; color: #777; margin: 3px 0 1px; }
.row8 { display: grid; grid-template-columns: repeat(8, 1fr); gap: 4px; }
.ctl { position: relative; border: 1.5px solid #111; padding: 11px 3px 3px; min-height: 0.48in; text-align: center;
       display: flex; flex-direction: column; justify-content: center; }
.ctl b { font-size: 9.5px; }
.ctl small { font-size: 7px; color: #444; line-height: 1.1; }
.ctl.knob { border-radius: 999px; }
.ctl.knob .tag { left: 50%; transform: translateX(-50%); top: 2px; }
.ctl.fader { border-radius: 3px; min-height: 0.62in; }
.ctl.switch { border-radius: 3px; }
.ctl.empty { border-style: dashed; border-color: #bbb; color: #bbb; }
.ctl.hot, .pad.hot { background: #111; color: #fff; }
.ctl.hot small, .pad.hot small { color: #ddd; }
.ctl.hot .tag, .pad.hot .tag { color: #bbb; }
.ctl.action, .pad.action { background: #fff7df; }
.transport { display: grid; grid-template-columns: repeat(5, 1fr); gap: 4px; }
.transport .ctl { min-height: 0.36in; border-radius: 3px; }
.legend { display: flex; gap: 12px; flex-wrap: wrap; font-size: 8.5px; color: #333; }
.sw { display: inline-block; width: 10px; height: 10px; border: 1.5px solid #111; vertical-align: -2px; margin-right: 3px; }
table { border-collapse: collapse; width: 100%; font-size: 9px; }
th, td { border-bottom: 1px solid #ccc; padding: 3px 5px; text-align: left; vertical-align: top; }
th { font-size: 8px; text-transform: uppercase; letter-spacing: 1px; border-bottom: 1.5px solid #111; }
td.n { font-weight: 700; width: 22px; }
.cols2 { display: grid; grid-template-columns: 1.55fr 1fr; gap: 16px; flex: 1; }
.box { border: 1.5px solid #111; border-radius: 5px; padding: 7px 9px; }
.box ol, .box ul { margin: 0; padding-left: 16px; }
.box li { margin-bottom: 2px; }
kbd { font: 700 8.5px Menlo, monospace; border: 1px solid #999; border-radius: 3px; padding: 0 3px; }
"""


def build(map_path):
    with open(map_path) as f:
        m = json.load(f)
    presets = load_presets()
    layout = m.get("layout", {})
    cc_map, note_map, mmc = m.get("cc", {}), m.get("note", {}), m.get("mmc", {})
    name = m.get("controller", os.path.splitext(os.path.basename(map_path))[0])

    used_banks = [(b, notes) for b, notes in layout.get("pad_banks", {}).items()
                  if any(lookup(note_map, n) for n in notes)]
    # two full pad banks fit down the left; any more go compact in the right column
    pads_html = "".join(
        f'<div><h2>Pad bank {b} <em>press PAD BANK {b}</em></h2>{pad_grid(notes, note_map, presets, b)}</div>'
        for b, notes in used_banks[:2])
    extra_pads_html = "".join(
        f'<div><h2>Pad bank {b} <em>press PAD BANK {b}</em></h2>{pad_grid(notes, note_map, presets, b, compact=True)}</div>'
        for b, notes in used_banks[2:])
    banks_html = "".join(
        f'<div><h2>Control bank {b} <em>{"default bank" if b == "A" else f"press CONTROL BANK until {b} is lit"}</em></h2>'
        f'{control_bank(b, nums, cc_map, presets)}</div>'
        for b, nums in layout.get("control_banks", {}).items()
        if any(lookup(cc_map, n) for g in nums.values() for n in g))
    # transport buttons: CC numbers listed in the layout (e.g. preset 1), else MIDI Machine Control
    tcc = layout.get("transport")
    tnames = ("rewind", "fast_forward", "stop", "play", "record")
    ttarget = (lambda i, k: lookup(cc_map, tcc[i])) if tcc else (lambda i, k: mmc.get(k))
    transport = "".join(cell(*label(ttarget(i, k), presets), lbl)
                        for i, (k, lbl) in enumerate(zip(tnames, ("◀◀", "▶▶", "■ STOP", "▶ PLAY", "● REC"))))

    rows = "".join(
        f'<tr><td class="n">{i + 1}</td><td><b>{html.escape(p.name)}</b></td>'
        + "".join(f"<td>{html.escape(p.labels.get(k, '—'))}</td>" for k in "abcd") + "</tr>"
        for i, p in enumerate(presets))

    setup = html.escape(m.get("device_preset", ""))
    return f"""<!doctype html><html><head><meta charset="utf-8"><title>{html.escape(name)} cheat sheet</title>
<style>{CSS}</style></head><body>
<section class="page">
  <header><h1>GOONVIZ <span>× {html.escape(name)}</span></h1><div class="note">{setup}</div></header>
  <div class="main">
    <div class="padbanks">{pads_html}
      <div><h2>Transport</h2><div class="transport">{transport}</div></div>
    </div>
    <div class="banks">{banks_html}{extra_pads_html}
      <div class="legend">
        <span><span class="sw" style="background:#111"></span>show-critical</span>
        <span><span class="sw" style="background:#fff7df"></span>action</span>
        <span><span class="sw" style="background:#e6eefc;border-color:#2350a0"></span>snapshot (hold SHIFT to save)</span>
        <span><span class="sw" style="background:#f1f1f1"></span>preset</span>
        <span>Switches: on = engaged · works in momentary (hold) or toggle mode</span>
      </div>
    </div>
  </div>
</section>
<section class="page">
  <header><h1>GOONVIZ <span>presets &amp; knobs A–D</span></h1><div class="note">Knobs K1–K4 (and bank B faders F1–F4) change meaning per preset.</div></header>
  <div class="cols2">
    <table><tr><th>#</th><th>Preset</th><th>A (K1)</th><th>B (K2)</th><th>C (K3)</th><th>D (K4)</th></tr>{rows}</table>
    <div style="display:flex;flex-direction:column;gap:10px">
      <div class="box"><h2>Show checklist</h2><ol>
        <li>Power the MPD32. It starts on preset <b>1 LiveLite</b>, which is what this sheet is for.</li>
        <li>Switches S1–S8 toggle: press once for on, again for off.</li>
        <li>Bring MASTER (F8) up. Keep a finger near <b>BLACKOUT</b> (S7) or ■ STOP.</li>
        <li><b>Autopilot</b> (S1 / ▶ PLAY) switches presets and keeps every knob moving. Bank B F7 sets intensity, from calm to wild.
            Any knob you touch, autopilot leaves alone until the next switch.</li>
        <li>Save looks: S8 SHIFT on, hit a blue snapshot pad, SHIFT off.</li>
      </ol></div>
      <div class="box"><h2>If something's off</h2><ul>
        <li>Pads do nothing: on the Pi run <kbd>run.py --learn-pads</kbd> and hit the pads in order.</li>
        <li>Change any control: plug in a keyboard, <kbd>H</kbd>, ↑↓ to choose, <kbd>L</kbd>, move the control.</li>
        <li>Then reprint: <kbd>python tools/make_cheatsheet.py</kbd></li>
        <li>No reaction to music: check the audio input, then raise Mic sensitivity (bank B F8). Audio react (bank B K5) sets how hard it hits.</li>
      </ul></div>
      <div class="box"><h2>Keyboard</h2>
        <kbd>←</kbd><kbd>→</kbd> preset · <kbd>R</kbd> randomize · <kbd>B</kbd> blackout · <kbd>A</kbd> autopilot ·
        <kbd>Space</kbd> flash · <kbd>H</kbd> overlay · <kbd>F1</kbd>–<kbd>F8</kbd> snapshots · <kbd>Esc</kbd> quit
      </div>
    </div>
  </div>
</section>
</body></html>"""


def find_chrome():
    for path in ("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                 "/Applications/Chromium.app/Contents/MacOS/Chromium"):
        if os.path.exists(path):
            return path
    for name in ("chromium", "chromium-browser", "google-chrome"):
        if shutil.which(name):
            return shutil.which(name)
    return None


def main():
    if len(sys.argv) > 1:
        map_path = sys.argv[1]
    else:
        with open(os.path.join(ROOT, "config.json")) as f:
            map_path = os.path.join(ROOT, json.load(f)["midi"]["map"])
    out_dir = os.path.join(ROOT, "docs")
    os.makedirs(out_dir, exist_ok=True)
    base = os.path.splitext(os.path.basename(map_path))[0] + "_cheatsheet"
    html_path = os.path.join(out_dir, base + ".html")
    with open(html_path, "w") as f:
        f.write(build(map_path))
    print(f"wrote {html_path}")

    chrome = find_chrome()
    if chrome:
        pdf_path = os.path.join(out_dir, base + ".pdf")
        subprocess.run([chrome, "--headless", "--disable-gpu", "--no-pdf-header-footer",
                        f"--print-to-pdf={pdf_path}", "file://" + html_path],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print(f"wrote {pdf_path}")
    else:
        print("no Chrome/Chromium found: open the HTML and print it (landscape)")


if __name__ == "__main__":
    main()
