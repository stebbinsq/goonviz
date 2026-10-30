// Autopilot as a VJ: it follows the shape of the music and plays planned routines instead of random moves.
// prism/autopilot.py is a port of this file; keep the two in step.
//
//  - Energy: short- vs long-term loudness tells a drop (cut to something intense, with a flash), a breakdown
//    (ease into something calm) and normal flow (change on phrase boundaries).
//  - Phrases: changes land every 8/16/32/64 beats (by intensity), never mid-phrase unless the music drops.
//  - Preset choice: match the music's energy, vary the style family, avoid anything shown recently, skip what
//    can't work right now (camera presets with no camera, heavy presets on a Pi).
//  - Routines: during a phrase it performs one planned move that suits the preset (bloom, spin, dive, breathe,
//    colour walk, drift), plus gentle drift of the other knobs within ranges known to look good.
//  - Knobs you touch are yours until the next change; knobs a preset uses as counts are never glided.
(function () {
  "use strict";
  const Prism = (window.Prism = window.Prism || {});
  const lerp = (a, b, t) => a + (b - a) * t;
  const clamp01 = (x) => Math.min(1, Math.max(0, x));
  const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];

  // Where each knob may wander (real values, not 0..1): tighter than "randomize", picked to stay good-looking.
  const RANGES = {
    speed: [0.7, 1.4], zoom: [0.85, 1.35], feedback: [0.15, 0.6], fb_zoom: [-0.15, 0.45], fb_rotate: [-0.25, 0.25],
    fb_hue: [0.0, 0.12], warp: [0.0, 0.2], chroma: [0.05, 0.3], glow: [0.3, 0.65],
  };
  const DRIFT = ["a", "b", "c", "d", ...Object.keys(RANGES)];

  // Which routines suit which kind of picture.
  const ROUTINES = {
    mandala: ["spin", "bloom", "breathe", "colorwalk"], kaleido: ["spin", "bloom", "breathe", "colorwalk"],
    fractal2d: ["spin", "bloom", "breathe", "colorwalk"], organic: ["drift", "breathe", "colorwalk", "bloom"],
    tunnel: ["dive", "breathe", "colorwalk"], flight3d: ["dive", "breathe", "colorwalk", "bloom"],
    object3d: ["breathe", "bloom", "colorwalk"], video: ["breathe", "spin", "bloom"],
  };
  const ROUTINE_NAMES = { spin: "Spin", bloom: "Bloom", breathe: "Breathe", colorwalk: "Colour walk", dive: "Dive", drift: "Drift" };

  class Autopilot {
    constructor(params, kaleidoChaos, paletteCount) {
      this.p = params;
      this.kaleidoChaos = kaleidoChaos;
      this.paletteCount = paletteCount;
      this.enabled = false;
      this.presets = [];
      this.canUse = () => true;
      this.base = {};
      this.dest = {};
      this.touched = new Set();
      this.stepped = new Set();
      this.homeHue = null;
      this.history = [];
      this.routine = "drift";
      this.section = "flow";      // flow | build | drop | breakdown
      this.energyFast = 0.3;      // ~1 s
      this.energySlow = 0.3;      // ~12 s
      this.energyPrev = 0.3;      // slow energy as it was ~4 s ago (to spot a drop after a quiet stretch)
      this.quietBeats = 0;
      this.dropCooldown = 0;
      this.resetCounters();
    }

    // The app tells the pilot about its presets and what can be used right now.
    configure(presets, canUse) { this.presets = presets; this.canUse = canUse; }

    get intensity() { return this.p.v("ap_intensity"); }
    // phrase length in beats: long and patient when calm, short and busy when wild
    phraseBeats() { const I = this.intensity; return I < 0.25 ? 64 : I < 0.5 ? 32 : I < 0.75 ? 16 : 8; }
    switchBeats() { return this.phraseBeats(); }
    beatsUntilSwitch() { return Math.max(0, this.phraseBeats() - this.beatsInPhrase); }
    get amp() { return 0.3 + 0.7 * this.intensity; }   // how big the routine's moves are

    resetCounters() {
      this.beatsInPhrase = 0;
      this.timeInPhrase = 0;
      this.beatsSinceDrift = 0;
      this.timeSinceDrift = 0;
    }

    // Called whenever a preset loads (by hand or by the pilot): its own look becomes home base.
    startPreset(preset) {
      this.current = preset;
      this.stepped = new Set(preset?.stepped || []);
      if (this.homeHue === null || this.touched.has("hue")) this.homeHue = this.p.get("hue").target;
      this.touched.clear();
      this.base = Object.fromEntries([...DRIFT, "hue"].map((n) => [n, this.p.get(n).target]));
      this.base.hue = this.homeHue;
      this.baseKaleido = this.p.get("kaleido").targetValue;
      this.resetCounters();
      this.chooseRoutine();
      this.retarget();
      if (preset) this.history = [preset.key, ...this.history.filter((k) => k !== preset.key)].slice(0, 8);
    }

    touch(name) { this.touched.add(name); delete this.dest[name]; }

    // ---- what to do next -----------------------------------------------------

    chooseRoutine() {
      const fam = this.current?.family || "organic";
      let options = ROUTINES[fam] || ROUTINES.organic;
      if (this.section === "breakdown") options = options.filter((r) => r === "drift" || r === "breathe" || r === "colorwalk");
      if (this.section === "drop" || this.section === "build") options = options.filter((r) => r === "bloom" || r === "dive" || r === "spin");
      if (!options.length) options = ["breathe"];
      const fresh = options.filter((r) => r !== this.routine);   // don't repeat the last routine if there's a choice
      this.routine = pick(fresh.length ? fresh : options);
    }

    // What energy should the next preset have, given the music right now?
    targetEnergy() {
      if (this.section === "drop") return 3;
      if (this.section === "breakdown") return 1;
      const ratio = this.energyFast / Math.max(0.05, this.energySlow);
      const level = this.energySlow;
      let e = level > 0.6 ? 2.6 : level < 0.25 ? 1.4 : 2;
      if (ratio > 1.25) e += 0.6; else if (ratio < 0.75) e -= 0.6;
      return Math.min(3, Math.max(1, e + (this.intensity - 0.5)));  // intensity leans the choice
    }

    choosePreset() {
      const target = this.targetEnergy();
      const curFam = this.current?.family;
      let best = -1, bestScore = -1e9;
      this.presets.forEach((p, i) => {
        if (!this.canUse(i) || p === this.current) return;
        let score = 3 * (1 - Math.abs((p.energy || 2) - target) / 2);
        if (p.family && p.family !== curFam) score += 1.2;               // vary the style
        const recent = this.history.indexOf(p.key);
        if (recent >= 0) score -= 4 * (1 - recent / this.history.length); // avoid repeats, most recent worst
        score += Math.random() * 1.4;                                   // keep it from being predictable
        if (score > bestScore) { bestScore = score; best = i; }
      });
      return best;
    }

    // ---- knob drift within good-looking ranges ------------------------------------

    retarget() {
      const amount = 0.25 + 0.6 * this.intensity;
      for (const n of DRIFT) {
        if (this.touched.has(n) || this.stepped.has(n)) continue;
        const prm = this.p.get(n);
        let wild;
        if (RANGES[n]) wild = prm.toNorm(RANGES[n][0] + Math.random() * (RANGES[n][1] - RANGES[n][0]));
        else wild = clamp01(this.base[n] + (Math.random() - 0.5) * 0.5);   // a-d: stay near the preset's own look
        this.dest[n] = this.base[n] + (wild - this.base[n]) * amount;
      }
    }

    // ---- routines: one planned move per phrase -----------------------------------

    // The knob values ({param: 0..1}) the routine wants right now. p = progress through the phrase (0..1),
    // b = beats into the phrase.
    routineTargets(p, b) {
      const A = this.amp, base = this.base, out = {};
      const add = (n, delta) => { if (n in base) out[n] = clamp01(base[n] + delta); };
      const bar = Math.floor(b / 4);
      switch (this.routine) {
        case "bloom":      // build toward the change: glow and trails rise, a little chroma at the peak
          add("glow", 0.3 * A * p);
          add("feedback", 0.3 * A * p);
          add("chroma", 0.2 * A * p * p);
          add("zoom", 0.05 * A * p);
          break;
        case "spin": {     // trails swirl one way then the other; the kaleidoscope steps up every bar
          add("fb_rotate", 0.22 * A * Math.sin(p * Math.PI * 2));
          add("feedback", 0.12 * A);
          const steps = [0, 4, 6, 8, 6, 4];
          if (!this.touched.has("kaleido") && !this.stepped.has("kaleido"))
            out.kaleidoAbs = this.intensity > 0.2 ? steps[bar % steps.length] : this.baseKaleido;
          break;
        }
        case "dive":       // accelerate into it: forward trail zoom and speed build through the phrase
          add("fb_zoom", 0.35 * A * p);
          add("speed", 0.18 * A * p);
          add("feedback", 0.2 * A * p);
          break;
        case "breathe":    // zoom and glow pulse in four-bar cycles, locked to the beat count
          add("zoom", 0.06 * A * Math.sin((b / 16) * Math.PI * 2));
          add("glow", 0.08 * A * (0.5 + 0.5 * Math.sin((b / 16) * Math.PI * 2)));
          break;
        case "colorwalk":  // the hue takes a slow walk away from home and back over the phrase
          out.hue = clamp01(this.homeHue + 0.14 * A * Math.sin(p * Math.PI * 2));
          break;
        default:           // drift: only the gentle background drift
          break;
      }
      return out;
    }

    // ---- per frame ------------------------------------------------------------------

    // audio: {level}. Returns events for the app:
    //   {type: "switch", index, cut}  change to this preset (cut = hard cut, for drops)
    //   {type: "flash", amount}
    update(dt, beats, audio) {
      if (!this.enabled) return [];
      const I = this.intensity;
      const events = [];
      this.beatsInPhrase += beats;
      this.timeInPhrase += dt;
      this.beatsSinceDrift += beats;
      this.timeSinceDrift += dt;
      this.dropCooldown = Math.max(0, this.dropCooldown - dt);

      const lvl = audio ? audio.level : 0.3;
      this.energyFast += (lvl - this.energyFast) * (1 - Math.exp(-dt / 1.0));
      this.energySlow += (lvl - this.energySlow) * (1 - Math.exp(-dt / 12.0));
      this.energyPrev += (this.energySlow - this.energyPrev) * (1 - Math.exp(-dt / 4.0));
      if (beats) this.quietBeats = this.energyFast < this.energySlow * 0.55 ? this.quietBeats + beats : 0;

      // a drop: loud now, after a quieter stretch
      const wasQuiet = this.section === "breakdown" || this.energyPrev < this.energySlow * 0.85;
      const drop = this.dropCooldown === 0 && I > 0.2 && wasQuiet &&
                   this.energyFast > Math.max(0.5, this.energySlow * 1.45) && beats > 0;
      if (drop) {
        this.section = "drop";
        this.dropCooldown = 8;
        const i = this.choosePreset();
        if (i >= 0) events.push({ type: "switch", index: i, cut: I > 0.45 });
        if (I > 0.55) events.push({ type: "flash", amount: 0.4 + 0.5 * I });
        return events;
      }
      if (this.quietBeats >= 8 && this.section !== "breakdown") {
        this.section = "breakdown";
        // don't sit on an intense picture through a quiet passage
        if ((this.current?.energy || 2) >= (I >= 0.5 ? 2 : 3)) {
          const i = this.choosePreset();
          if (i >= 0) { events.push({ type: "switch", index: i, cut: false }); return events; }
        }
        this.chooseRoutine();
      } else if (this.section === "breakdown" && this.quietBeats === 0) {
        this.section = "build";
        this.chooseRoutine();
      }

      // phrase boundary: change preset (no beats at all? fall back to time)
      if (this.beatsInPhrase >= this.phraseBeats() || this.timeInPhrase >= lerp(70, 14, I)) {
        if (this.section === "drop") this.section = "flow";
        const i = this.choosePreset();
        if (i >= 0) events.push({ type: "switch", index: i, cut: false });
        else { this.resetCounters(); this.chooseRoutine(); }
        return events;
      }

      // background drift retargets every few bars; the routine moves continuously on top
      if (this.beatsSinceDrift >= Math.max(4, Math.round(lerp(16, 4, I))) || this.timeSinceDrift >= lerp(10, 3, I)) {
        this.beatsSinceDrift = 0;
        this.timeSinceDrift = 0;
        this.retarget();
      }
      const rt = this.routineTargets(Math.min(1, this.beatsInPhrase / this.phraseBeats()), this.beatsInPhrase);
      const glideK = 1 - Math.exp(-dt / lerp(4, 1.2, I));
      for (const [n, d] of Object.entries(this.dest)) {
        if (n in rt || this.touched.has(n)) continue;
        const prm = this.p.get(n);
        prm.setNorm(prm.target + (d - prm.target) * glideK);
      }
      const routineK = 1 - Math.exp(-dt / 0.35);   // routines follow their curve closely
      for (const [n, v] of Object.entries(rt)) {
        if (n === "kaleidoAbs") { if (this.p.get("kaleido").targetValue !== v) this.p.get("kaleido").setValue(v); continue; }
        if (this.touched.has(n) || this.stepped.has(n)) continue;
        const prm = this.p.get(n);
        prm.setNorm(prm.target + (v - prm.target) * routineK);
      }
      return events;
    }

    onSwitched(preset) { this.startPreset(preset); }

    status() {
      const sec = { flow: "", build: " · building", drop: " · DROP", breakdown: " · breakdown" }[this.section];
      return `${ROUTINE_NAMES[this.routine] || this.routine}${sec}`;
    }
  }

  Prism.Autopilot = Autopilot;
})();
