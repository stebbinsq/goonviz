// Port of prism/autopilot.py (keep the two in step). Switches presets on the beat and keeps the knobs
// gliding the whole time; everything scales with the "ap_intensity" knob. Touched knobs are left alone
// until the next preset switch.
(function () {
  "use strict";
  const Prism = (window.Prism = window.Prism || {});
  const DRIFT = ["a", "b", "c", "d", "speed", "zoom", "feedback", "fb_zoom", "fb_rotate", "fb_hue", "warp", "chroma", "glow"];
  const lerp = (a, b, t) => a + (b - a) * t;
  const uniform = (lo, hi) => lo + Math.random() * (hi - lo);

  class Autopilot {
    constructor(params, kaleidoChaos, paletteCount) {
      this.p = params;
      this.kaleidoChaos = kaleidoChaos;
      this.paletteCount = paletteCount;
      this.enabled = false;
      this.base = {};
      this.dest = {};
      this.touched = new Set();
      this.homeHue = null; // your hue: autopilot wobbles around it (reset when autopilot is switched on)
      this.resetCounters();
    }

    get intensity() { return this.p.v("ap_intensity"); }
    switchBeats() { return Math.max(4, Math.round(lerp(64, 8, this.intensity) / 4) * 4); }
    beatsUntilSwitch() { return Math.max(0, this.switchBeats() - this.beatsSinceSwitch); }

    resetCounters() {
      this.beatsSinceSwitch = this.beatsSinceDrift = 0;
      this.timeSinceSwitch = this.timeSinceDrift = 0;
    }

    startPreset() {
      if (this.homeHue === null || this.touched.has("hue")) this.homeHue = this.p.get("hue").target;
      this.base = Object.fromEntries(DRIFT.map((n) => [n, this.p.get(n).target]));
      this.base.hue = this.homeHue;
      this.touched.clear();
      this.resetCounters();
      this.retarget();
    }

    touch(name) {
      this.touched.add(name);
      delete this.dest[name];
    }

    retarget() {
      const amount = 0.15 + 0.85 * this.intensity;
      for (const n of DRIFT) {
        if (this.touched.has(n)) continue;
        const prm = this.p.get(n);
        const [lo, hi] = prm.chaos || [prm.lo, prm.hi];
        const wild = prm.toNorm(uniform(lo, hi));
        this.dest[n] = this.base[n] + (wild - this.base[n]) * amount;
      }
      if (!this.touched.has("hue")) {
        // wobble around your hue setting rather than wandering off (palettes go murky far from home)
        this.dest.hue = Math.min(1, Math.max(0, this.base.hue + uniform(-1, 1) * 0.08 * this.intensity));
      }
    }

    // returns events for the app: "switch", "flash"
    update(dt, beats) {
      if (!this.enabled) return [];
      const I = this.intensity;
      const events = [];
      this.beatsSinceSwitch += beats;
      this.beatsSinceDrift += beats;
      this.timeSinceSwitch += dt;
      this.timeSinceDrift += dt;

      if (this.beatsSinceSwitch >= this.switchBeats() || this.timeSinceSwitch >= lerp(60, 12, I)) events.push("switch");
      if (this.beatsSinceDrift >= Math.max(1, Math.round(lerp(16, 2, I))) || this.timeSinceDrift >= lerp(10, 1.5, I)) {
        this.beatsSinceDrift = 0;
        this.timeSinceDrift = 0;
        this.retarget();
      }

      const k = 1 - Math.exp(-dt / lerp(4, 0.8, I));
      for (const [n, d] of Object.entries(this.dest)) {
        const prm = this.p.get(n);
        prm.setNorm(prm.target + (d - prm.target) * k);
      }

      for (let b = 0; b < beats; b++) {
        if (I > 0.4 && Math.random() < (I - 0.4) * 0.35) {
          const roll = Math.random();
          if (roll < 0.45 && !this.touched.has("kaleido"))
            this.p.get("kaleido").setValue(this.kaleidoChaos[Math.floor(Math.random() * this.kaleidoChaos.length)]);
          else if (roll < 0.85 && !this.touched.has("palette"))
            this.p.get("palette").setValue(Math.floor(Math.random() * this.paletteCount));
          else if (I > 0.8) events.push("flash");
        }
      }
      return events;
    }

    onSwitched() {
      const I = this.intensity;
      if (Math.random() < I) this.p.get("palette").setValue(Math.floor(Math.random() * this.paletteCount));
      if (Math.random() < I * 0.7)
        this.p.get("kaleido").setValue(this.kaleidoChaos[Math.floor(Math.random() * this.kaleidoChaos.length)]);
      this.startPreset();
    }
  }

  Prism.Autopilot = Autopilot;
})();
