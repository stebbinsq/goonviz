"""MIDI input with hot-plug, a JSON mapping file and MIDI learn.

Mapping file format (see maps/*.json):

    {
      "cc":   {"1": "a", "2:7": "brightness"},      "num" or "channel:num" (channels 1-16)
      "note": {"36": "preset:0", "48": "next"},
      "mmc":  {"play": "autopilot", "stop": "blackout"},  transport buttons (MIDI Machine Control)
      "pad_mode": "momentary",                            or "toggle" for latching pads
      "program_change_selects_preset": true
    }

A target is either a param name (CC value 0-127 sets it) or an action. How an
action responds depends on what sent it; see App.apply. See ACTIONS for the list.
"""

import json
import os
import queue
import time

ACTIONS = {
    "next": "next preset",
    "prev": "previous preset",
    "random_preset": "jump to a random preset",
    "randomize": "randomize the FX knobs",
    "reset": "reset knobs to the preset's defaults",
    "autopilot": "toggle auto-cycling presets on the beat",
    "blackout": "toggle fade to black",
    "flash": "white flash while held (momentary)",
    "freeze": "toggle pausing time",
    "shift": "hold: snapshot buttons save instead of recall (momentary)",
    "tap": "fake a beat (tap along when there's no audio)",
    "video": "toggle video input on/off",
    "hud": "toggle the on-screen overlay",
    "preset:N": "jump to preset N (0-based)",
    "snapshot:N": "recall snapshot N (shift + it saves)",
}
MOMENTARY = {"flash", "shift"}
# On/off actions: a latching pad or switch sets them to its own state
# (so the pad LED matches), anything else toggles them.
STATE_ACTIONS = {"blackout", "freeze", "autopilot", "video", "hud", "shift"}
MMC_COMMANDS = {1: "stop", 2: "play", 3: "play", 4: "fast_forward", 5: "rewind", 6: "record", 9: "pause"}


def is_action(target, params):
    return target not in params


class MidiMap:
    def __init__(self, path):
        self.path = path
        self.cc, self.note, self.mmc, self.pc_presets = {}, {}, {}, True
        self.pad_mode = "momentary"
        self.load()

    def load(self):
        if not os.path.exists(self.path):
            print(f"[midi] no map at {self.path}; starting empty (use MIDI learn)")
            return
        with open(self.path) as f:
            data = json.load(f)
        self.cc = {str(k): v for k, v in data.get("cc", {}).items()}
        self.note = {str(k): v for k, v in data.get("note", {}).items()}
        self.mmc = data.get("mmc", {})
        self.pad_mode = data.get("pad_mode", "momentary")
        self.pc_presets = data.get("program_change_selects_preset", True)
        self.extra = {k: v for k, v in data.items()
                      if k not in ("cc", "note", "mmc", "pad_mode", "program_change_selects_preset")}

    def save(self):
        data = dict(self.extra)
        data.update({"cc": self.cc, "note": self.note, "mmc": self.mmc, "pad_mode": self.pad_mode,
                     "program_change_selects_preset": self.pc_presets})
        with open(self.path, "w") as f:
            json.dump(data, f, indent=2)
        print(f"[midi] saved map to {self.path}")

    @staticmethod
    def _lookup(table, channel, number):
        return table.get(f"{channel + 1}:{number}") or table.get(str(number))

    def resolve(self, msg):
        """Returns (target, value 0..1, pressed, source) or None.
        source is "cc", "note", "toggle_pad" (a latching pad), "pc" or "mmc"."""
        if msg.type == "control_change":
            target = self._lookup(self.cc, msg.channel, msg.control)
            return (target, msg.value / 127.0, msg.value >= 64, "cc") if target else None
        if msg.type in ("note_on", "note_off"):
            target = self._lookup(self.note, msg.channel, msg.note)
            on = msg.type == "note_on" and msg.velocity > 0
            source = "toggle_pad" if self.pad_mode == "toggle" else "note"
            return (target, msg.velocity / 127.0 if on else 0.0, on, source) if target else None
        if msg.type == "program_change" and self.pc_presets:
            return (f"preset:{msg.program}", 1.0, True, "pc")
        if msg.type == "sysex" and len(msg.data) >= 4 and msg.data[0] == 0x7F and msg.data[2] == 0x06:
            target = self.mmc.get(MMC_COMMANDS.get(msg.data[3], ""))
            return (target, 1.0, True, "mmc") if target else None
        return None

    def learn(self, msg, target):
        """Bind the control that sent msg to target. Returns a description or None."""
        if msg.type == "control_change":
            table, num, kind = self.cc, msg.control, "CC"
        elif msg.type == "note_on" and msg.velocity > 0:
            table, num, kind = self.note, msg.note, "note"
        else:
            return None
        key = f"{msg.channel + 1}:{num}"
        for k in [k for k, v in table.items() if k in (key, str(num))]:
            del table[k]  # replace any existing binding of this control
        table[key] = target
        self.save()
        return f"{kind} {num} (ch {msg.channel + 1}) -> {target}"


class MidiInput:
    RESCAN_SECONDS = 2.0

    def __init__(self, port_filter=None):
        self.port_filter = (port_filter or "").lower()
        self.queue = queue.Queue()
        self.ports = {}
        self.last_message = ""
        self._last_scan = 0.0
        try:
            import mido
            self.mido = mido
        except ImportError:
            self.mido = None
            print("[midi] mido not installed; MIDI disabled")

    def _scan(self):
        self._last_scan = time.monotonic()
        try:
            names = set(self.mido.get_input_names())
        except Exception as e:
            print(f"[midi] port scan failed: {e}")
            return
        for name in list(self.ports):
            if name not in names:
                print(f"[midi] disconnected: {name}")
                try:
                    self.ports.pop(name).close()
                except Exception:
                    pass
        for name in names - set(self.ports):
            if "through" in name.lower():
                continue
            if self.port_filter and self.port_filter not in name.lower():
                continue
            try:
                self.ports[name] = self.mido.open_input(name, callback=self.queue.put)
                print(f"[midi] connected: {name}")
            except Exception as e:
                print(f"[midi] could not open {name}: {e}")

    def poll(self):
        if self.mido is None:
            return []
        if time.monotonic() - self._last_scan > self.RESCAN_SECONDS:
            self._scan()
        msgs = []
        while True:
            try:
                msgs.append(self.queue.get_nowait())
            except queue.Empty:
                break
        shown = [m for m in msgs if m.type not in ("clock", "active_sensing")]
        if shown:
            self.last_message = str(shown[-1])
        return msgs

    def close(self):
        for port in self.ports.values():
            port.close()


def monitor():
    """Print every incoming MIDI message: handy for writing a map by hand."""
    m = MidiInput()
    if m.mido is None:
        return
    print("Listening for MIDI. Move knobs / hit pads. Ctrl+C to stop.")
    try:
        while True:
            for msg in m.poll():
                if msg.type != "clock":
                    print(msg)
            time.sleep(0.01)
    except KeyboardInterrupt:
        pass


def learn_pads(map_path):
    """Hit each pad in order to record what it sends, then rewrite the map.

    For controllers whose pads don't send what the map assumes. Pads are learned bank by bank (in the
    order listed under layout.pad_banks); bindings move with the pad, so pad 5 keeps doing what pad 5 did.
    Pads are recorded as "channel:note", so banks that span several MIDI channels work too.
    """
    m = MidiInput()
    if m.mido is None:
        return
    mm = MidiMap(map_path)
    banks = mm.extra.get("layout", {}).get("pad_banks") or {"A": [36 + i for i in range(16)]}
    remap = {}
    try:
        for bank, old_keys in banks.items():
            print(f"\nSelect PAD BANK {bank}, then hit its pads 1-16 in order "
                  f"(pad 1 = bottom left, along the row, then up). Ctrl+C when done.")
            got = []
            while len(got) < len(old_keys):
                for msg in m.poll():
                    key = f"{msg.channel + 1}:{msg.note}" if msg.type == "note_on" else None
                    if key and msg.velocity > 0 and key not in got:
                        got.append(key)
                        print(f"  pad {len(got):2d} -> note {msg.note} (ch {msg.channel + 1})")
                time.sleep(0.005)
            remap.update({str(old): new for old, new in zip(old_keys, got)})
            banks[bank] = got
    except KeyboardInterrupt:
        print()
    if not remap:
        return
    mm.note = {remap.get(k, k): target for k, target in mm.note.items()}
    mm.extra.setdefault("layout", {})["pad_banks"] = banks
    mm.save()