// Port of prism/params.py. The definitions themselves come from the bundle, so both versions share them.
(function () {
  "use strict";
  const Prism = (window.Prism = window.Prism || {});
  const SMOOTH_TAU = 0.06; // seconds; hides the 128-step graininess of MIDI knobs

  class Param {
    constructor(def) {
      Object.assign(this, { name: def.name, lo: def.lo, hi: def.hi, def: def.default });
      this.curve = def.curve || "lin";
      this.isInt = !!def.int;
      this.scope = def.scope || "preset";
      this.chaos = def.chaos || null;
      this.norm = this.target = this.toNorm(this.def);
    }
    toNorm(v) {
      v = Math.min(Math.max(v, this.lo), this.hi);
      if (this.curve === "exp") return Math.log(v / this.lo) / Math.log(this.hi / this.lo);
      return (v - this.lo) / (this.hi - this.lo);
    }
    fromNorm(n) {
      n = Math.min(Math.max(n, 0), 1);
      if (this.curve === "exp") return this.lo * Math.pow(this.hi / this.lo, n);
      return this.lo + n * (this.hi - this.lo);
    }
    get value() { const v = this.fromNorm(this.norm); return this.isInt ? Math.round(v) : v; }
    get targetValue() { const v = this.fromNorm(this.target); return this.isInt ? Math.round(v) : v; }
    setValue(v, immediate = false) { this.setNorm(this.toNorm(v), immediate); }
    setNorm(n, immediate = false) {
      this.target = Math.min(Math.max(n, 0), 1);
      if (immediate || this.isInt) this.norm = this.target;
    }
    nudge(amount) { this.setNorm(this.target + amount); }
    update(dt) { this.norm += (this.target - this.norm) * (1 - Math.exp(-dt / SMOOTH_TAU)); }
  }

  class ParamSet {
    constructor(defs, kaleidoChaos, paletteCount) {
      this.list = defs.map((d) => new Param(d));
      this.byName = Object.fromEntries(this.list.map((p) => [p.name, p]));
      this.kaleidoChaos = kaleidoChaos;
      this.paletteCount = paletteCount;
    }
    get(name) { return this.byName[name]; }
    has(name) { return name in this.byName; }
    v(name) { return this.byName[name].value; }
    update(dt) { for (const p of this.list) p.update(dt); }
    loadPreset(presetParams) {
      for (const p of this.list) if (p.scope === "preset") p.setValue(p.def, true);
      for (const [k, v] of Object.entries(presetParams)) if (this.byName[k]) this.byName[k].setValue(v, true);
    }
    randomize() {
      for (const p of this.list) if (p.chaos) p.setValue(p.chaos[0] + Math.random() * (p.chaos[1] - p.chaos[0]));
      this.byName.kaleido.setValue(this.kaleidoChaos[Math.floor(Math.random() * this.kaleidoChaos.length)]);
      this.byName.palette.setValue(Math.floor(Math.random() * this.paletteCount));
    }
    snapshot() { return Object.fromEntries(this.list.map((p) => [p.name, +p.targetValue.toFixed(4)])); }
    restore(values) { for (const [k, v] of Object.entries(values)) if (this.byName[k]) this.byName[k].setValue(v); }
  }

  Prism.ParamSet = ParamSet;
})();
