// Port of prism/midi.py on Web MIDI: hot-plug, JSON maps (same files as the Pi), MIDI learn, MMC transport.
(function () {
  "use strict";
  const Prism = (window.Prism = window.Prism || {});

  class MidiMap {
    constructor(data, mmcCommands) {
      this.mmcCommands = mmcCommands;
      this.load(data);
    }
    load(data) {
      data = JSON.parse(JSON.stringify(data || {}));
      this.cc = data.cc || {};
      this.note = data.note || {};
      this.mmc = data.mmc || {};
      this.padMode = data.pad_mode || "momentary";
      this.pcPresets = data.program_change_selects_preset !== false;
      this.extra = {};
      for (const [k, v] of Object.entries(data))
        if (!["cc", "note", "mmc", "pad_mode", "program_change_selects_preset"].includes(k)) this.extra[k] = v;
    }
    toJSON() {
      return { ...this.extra, cc: this.cc, note: this.note, mmc: this.mmc, pad_mode: this.padMode,
               program_change_selects_preset: this.pcPresets };
    }
    static lookup(table, channel, num) { return table[`${channel + 1}:${num}`] || table[String(num)]; }

    // msg: {type, channel, num, value, data} -> [target, value 0..1, pressed, source] | null
    resolve(m) {
      if (m.type === "cc") {
        const t = MidiMap.lookup(this.cc, m.channel, m.num);
        return t ? [t, m.value / 127, m.value >= 64, "cc"] : null;
      }
      if (m.type === "note_on" || m.type === "note_off") {
        const t = MidiMap.lookup(this.note, m.channel, m.num);
        const on = m.type === "note_on" && m.value > 0;
        return t ? [t, on ? m.value / 127 : 0, on, this.padMode === "toggle" ? "toggle_pad" : "note"] : null;
      }
      if (m.type === "program_change" && this.pcPresets) return [`preset:${m.num}`, 1, true, "pc"];
      if (m.type === "sysex" && m.data.length >= 6 && m.data[1] === 0x7f && m.data[3] === 0x06) {
        const t = this.mmc[this.mmcCommands[String(m.data[4])] || ""];
        return t ? [t, 1, true, "mmc"] : null;
      }
      return null;
    }
    learn(m, target) {
      let table, kind;
      if (m.type === "cc") { table = this.cc; kind = "CC"; }
      else if (m.type === "note_on" && m.value > 0) { table = this.note; kind = "note"; }
      else return null;
      const key = `${m.channel + 1}:${m.num}`;
      for (const k of Object.keys(table)) if (k === key || k === String(m.num)) delete table[k];
      table[key] = target;
      return `${kind} ${m.num} (ch ${m.channel + 1}) → ${target}`;
    }
  }

  function parse(bytes) {
    const st = bytes[0];
    if (st === 0xf8) return { type: "clock" };
    if (st === 0xfa) return { type: "start" };
    if (st === 0xfe) return { type: "active_sensing" };
    if (st === 0xf0) return { type: "sysex", data: Array.from(bytes) };
    const kind = st & 0xf0, channel = st & 0x0f;
    if (kind === 0x90) return { type: bytes[2] > 0 ? "note_on" : "note_off", channel, num: bytes[1], value: bytes[2] };
    if (kind === 0x80) return { type: "note_off", channel, num: bytes[1], value: 0 };
    if (kind === 0xb0) return { type: "cc", channel, num: bytes[1], value: bytes[2] };
    if (kind === 0xc0) return { type: "program_change", channel, num: bytes[1] };
    return null;
  }

  function describe(m) {
    if (!m) return "";
    if (m.type === "cc") return `CC ${m.num} = ${m.value} (ch ${m.channel + 1})`;
    if (m.type === "note_on" || m.type === "note_off") return `${m.type === "note_on" ? "note on" : "note off"} ${m.num} (ch ${m.channel + 1})`;
    if (m.type === "program_change") return `program ${m.num}`;
    if (m.type === "sysex") return `sysex ${m.data.slice(0, 6).map((b) => b.toString(16).padStart(2, "0")).join(" ")}`;
    return m.type;
  }

  class MidiInput {
    constructor(onMessage) {
      this.onMessage = onMessage;
      this.ports = [];
      this.status = "not started";
      this.last = "";
    }
    async start() {
      if (!navigator.requestMIDIAccess) {
        this.status = "this browser has no Web MIDI (use Chrome or Edge)";
        return;
      }
      try {
        this.access = await navigator.requestMIDIAccess({ sysex: true }); // sysex = MPD32 transport (MMC)
      } catch (e) {
        try { this.access = await navigator.requestMIDIAccess(); }
        catch (e2) { this.status = "MIDI access denied"; return; }
      }
      this.access.onstatechange = () => this.attach();
      this.attach();
    }
    attach() {
      this.ports = [];
      for (const input of this.access.inputs.values()) {
        if (/through/i.test(input.name)) continue;
        input.onmidimessage = (e) => {
          const m = parse(e.data);
          if (!m) return;
          if (m.type !== "clock" && m.type !== "active_sensing") this.last = describe(m);
          this.onMessage(m);
        };
        if (input.state === "connected") this.ports.push(input.name);
      }
      this.status = this.ports.length ? this.ports.join(", ") : "no controller connected";
    }
  }

  Prism.MidiMap = MidiMap;
  Prism.MidiInput = MidiInput;
  Prism.parseMidi = parse;
})();
