// GoonViz (Prism) for the browser: main loop, actions, keyboard, MIDI handling and the control panel.
// Mirrors prism/app.py so the MPD32 and keyboard behave the same as on the Pi.
(function () {
  "use strict";
  const D = window.PRISM_DATA;
  const $ = (sel) => document.querySelector(sel);
  const store = {
    get(key, fallback) {
      try { const v = localStorage.getItem("prism." + key); return v === null ? fallback : JSON.parse(v); }
      catch (e) { return fallback; }
    },
    set(key, value) { try { localStorage.setItem("prism." + key, JSON.stringify(value)); } catch (e) { /* private mode etc */ } },
  };

  const PARAM_LABELS = {
    a: "Knob A", b: "Knob B", c: "Knob C", d: "Knob D", speed: "Speed", zoom: "Zoom",
    feedback: "Trails", fb_zoom: "Trail zoom", fb_rotate: "Trail spin", fb_hue: "Trail hue",
    kaleido: "Kaleido", warp: "Warp", chroma: "Chroma", glow: "Glow", palette: "Palette",
    hue: "Hue", saturation: "Saturation", brightness: "Master", contrast: "Contrast",
    video_mix: "Camera mix", cam_view: "360 view", cam_spin: "360 spin", react: "Audio react",
    strobe: "Strobe", invert: "Invert", ap_intensity: "Intensity",
  };
  const ACTION_LABELS = {
    next: "Next ▶", prev: "◀ Prev", random_preset: "Random preset", randomize: "Randomize FX",
    reset: "Reset knobs", autopilot: "Autopilot", blackout: "Blackout", flash: "Flash", freeze: "Freeze",
    shift: "Shift", tap: "Tap beat", video: "Camera on/off", hud: "Overlay",
  };
  const STATE_ACTIONS = new Set(D.stateActions);

  // Phones and tablets get a lighter profile; desktops are untouched. iPadOS reports itself as a Mac, so
  // a Mac with a touchscreen counts as a tablet.
  // ?profile=pi|mobile|desktop in the address forces a profile (handy for testing on another machine).
  const FORCED = new URLSearchParams(location.search).get("profile");
  const MOBILE = FORCED ? FORCED === "mobile" :
                 !!(navigator.userAgentData?.mobile) || /Android|iPhone|iPad|iPod/i.test(navigator.userAgent) ||
                 (/Macintosh/.test(navigator.userAgent) && navigator.maxTouchPoints > 1);

  class App {
    constructor() {
      this.mobile = MOBILE;
      document.body.classList.toggle("mobile", MOBILE);
      this.canvas = $("#view");
      this.engine = new Prism.Engine(this.canvas, D);
      // Raspberry Pi (and similar small ARM boards): recognised by the Pi's Broadcom/V3D graphics chip, or by
      // being an ARM Linux machine that isn't a phone. Gets a light profile and skips heavy presets when
      // choosing at random (autopilot). Desktops and phones are unaffected.
      this.pi = FORCED ? FORCED === "pi" :
                /v3d|videocore|broadcom/i.test(this.engine.renderer) ||
                (/Linux (aarch64|armv)/i.test(navigator.userAgent) && !/Android/i.test(navigator.userAgent));
      this.lowPower = this.mobile || this.pi;
      document.body.classList.toggle("pi", this.pi);
      this.presets = this.engine.presets;
      this.params = new Prism.ParamSet(D.params, D.kaleidoChaos, D.palettes.length);
      this.audio = new Prism.Audio();
      this.midi = new Prism.MidiInput((m) => this.handleMidi(m));
      this.video = $("#cam");

      this.mapName = store.get("mapName", "akai_mpd32");
      this.loadMap();
      this.snapshots = store.get("snapshots", {});
      this.settings = Object.assign({ quality: "auto", pickup: false, osd: true }, store.get("settings", {}));
      this.pilot = new Prism.Autopilot(this.params, D.kaleidoChaos, D.palettes.length);
      // autopilot may only pick what works right now: no camera presets without a camera, nothing heavy on a Pi
      this.pilot.configure(this.presets, (i) => {
        const p = this.presets[i];
        return !p.error && !(p.family === "video" && !this.engine.videoOn) && !(this.pi && p.heavy);
      });
      this.params.get("ap_intensity").setValue(store.get("apIntensity", 0.5), true);

      this.st = { time: 0, pulse: 0, realTime: 0, flash: 0, blackout: 0, camYaw: 0, transition: 0 };
      this.shift = this.frozen = this.flashHeld = false;
      this.blackoutTarget = 0;
      this.videoActive = true;
      this.video360 = false;
      this.showHud = false;
      this.learning = null;
      this.picked = new Set();
      this.clockTicks = 0;
      this.lastBeatCount = 0;
      this.fps = 60;
      this.dyn = 1;              // adaptive resolution multiplier (1 = the quality setting's full size)
      this.dynByPreset = {};     // what each preset settled on, so switching back starts at the right size
      this.frameMs = 16.7;       // smoothed frame time
      this.refreshMs = 16.7;     // the display's refresh interval (see adaptResolution)
      this.recentMs = [];
      this.dynCheck = 0;

      this.buildPanel();
      if (!window.isSecureContext) this.insecureWarning();
      this.selectPreset(0);
      this.bindKeys();
      this.bindTouch();
      document.addEventListener("visibilitychange", () => { if (this.started) this.keepAwake(); });
      new ResizeObserver(() => this.resize()).observe(this.canvas);
      document.addEventListener("fullscreenchange", () => { this.resize(); this.refreshChrome(); });
      this.resize();
      this.last = performance.now();
      requestAnimationFrame((t) => this.frame(t));
    }

    // ---- maps, snapshots ----------------------------------------------

    loadMap() {
      let saved = store.get("map." + this.mapName, null);
      // The first MPD32 map assumed factory preset 18 (ArkaosVJ); real controllers start on preset 1 and send
      // different numbers. A saved copy built on that old map would hide the corrected one, so drop it.
      if (saved && /ArkaosVJ/.test(saved.device_preset || "")) {
        try { localStorage.removeItem("prism.map." + this.mapName); } catch (e) { /* ignore */ }
        saved = null;
      }
      this.map = new Prism.MidiMap(saved || D.maps[this.mapName] || {}, D.mmc);
      this.mapEdited = !!saved;
    }
    saveMap() {
      store.set("map." + this.mapName, this.map.toJSON());
      this.mapEdited = true;
      this.refreshMapUi();
    }

    saveSnapshot(slot) {
      this.snapshots[slot] = { preset: this.preset.key, params: this.params.snapshot() };
      store.set("snapshots", this.snapshots);
      this.notify(`saved snapshot ${slot + 1}`);
      this.refreshSnapshots();
    }
    recallSnapshot(slot) {
      const snap = this.snapshots[slot];
      if (!snap) return this.notify(`snapshot ${slot + 1} is empty (shift + it to save)`);
      const i = this.presets.findIndex((p) => p.key === snap.preset);
      if (i >= 0) this.presetIndex = i;
      this.params.restore(snap.params);
      this.picked.clear();
      this.notify(`snapshot ${slot + 1}`);
      this.refreshPresetButtons();
    }

    // ---- presets & actions --------------------------------------------

    get preset() { return this.presets[this.presetIndex]; }

    selectPreset(index) {
      const n = this.presets.length;
      const before = this.presetIndex;
      for (let step = 0; step < n; step++) {
        const i = (((index + step) % n) + n) % n;
        if (this.engine.ensure(this.presets[i])) { this.presetIndex = i; break; }
      }
      if (before !== undefined && before !== this.presetIndex) {
        this.st.transition = 1; // melt old into new
        this.dynByPreset[this.presets[before].key] = this.dyn;
        const remembered = this.dynByPreset[this.preset.key];
        if (remembered !== undefined && remembered !== this.dyn) { this.dyn = remembered; this.resize(); }
      }
      this.params.loadPreset(this.preset.params);
      this.picked.clear();
      this.pilot?.startPreset(this.preset);
      this.notify(this.preset.name);
      this.refreshPresetButtons();
      this.refreshLabels();
    }

    doAction(action, pressed = true) {
      if (action === "shift") this.shift = pressed;
      else if (action === "flash") this.flashHeld = pressed;
      if (!pressed) return this.refreshChrome();
      const n = this.presets.length;
      if (action === "next") this.selectPreset(this.presetIndex + 1);
      else if (action === "prev") this.selectPreset(this.presetIndex - 1);
      else if (action === "random_preset") {
        // on a Pi, random picks (and so autopilot) avoid the heavy 3D/4D presets; you can still pick them by hand
        const pool = this.presets.map((p, i) => i).filter((i) => i !== this.presetIndex && !(this.pi && this.presets[i].heavy));
        this.selectPreset(pool.length ? pool[Math.floor(Math.random() * pool.length)] : this.presetIndex);
      } else if (action === "randomize") { this.params.randomize(); this.picked.clear(); }
      else if (action === "reset") { this.params.loadPreset(this.preset.params); this.picked.clear(); }
      else if (action === "autopilot") {
        this.pilot.enabled = !this.pilot.enabled;
        if (this.pilot.enabled) { this.pilot.homeHue = null; this.pilot.startPreset(this.preset); }
        this.notify(`autopilot ${this.pilot.enabled ? "on" : "off"}`);
      }
      else if (action === "blackout") this.blackoutTarget = 1 - this.blackoutTarget;
      else if (action === "freeze") this.frozen = !this.frozen;
      else if (action === "tap") this.audio.triggerBeat();
      else if (action === "video") { this.videoActive = !this.videoActive; this.notify(`camera ${this.videoActive ? "on" : "off"}`); }
      else if (action === "hud") this.showHud = !this.showHud;
      else if (action.startsWith("preset:")) this.selectPreset(parseInt(action.split(":")[1], 10) % n);
      else if (action.startsWith("snapshot:")) {
        const slot = parseInt(action.split(":")[1], 10);
        this.shift ? this.saveSnapshot(slot) : this.recallSnapshot(slot);
      }
      this.refreshChrome();
    }

    setState(action, on) {
      if (action === "blackout") this.blackoutTarget = on ? 1 : 0;
      else if (action === "freeze") this.frozen = on;
      else if (action === "autopilot") { if (this.pilot.enabled !== on) this.doAction("autopilot"); }
      else if (action === "video") this.videoActive = on;
      else if (action === "hud") this.showHud = on;
      else if (action === "shift") this.shift = on;
      this.refreshChrome();
    }

    apply(target, value, pressed, source) {
      if (this.params.has(target)) {
        const p = this.params.get(target);
        if (this.settings.pickup && !this.picked.has(target)) {
          if (Math.abs(value - p.target) > 0.04) return; // soft takeover
          this.picked.add(target);
        }
        p.setNorm(value);
        this.pilot.touch(target);
        return;
      }
      const latching = source === "cc" || source === "toggle_pad";
      if (STATE_ACTIONS.has(target) && latching) this.setState(target, pressed);
      else if (source === "toggle_pad") {
        // latching pads: note-on on one hit, note-off on the next, so every message is a hit
        if (target === "flash") this.st.flash = 1;
        else this.doAction(target, true);
      } else this.doAction(target, pressed);
    }

    handleMidi(m) {
      if (m.type === "clock") {
        this.clockTicks++;
        this.audio.externalBeatsUntil = performance.now() / 1000 + 1;
        if (this.clockTicks % 24 === 0) this.audio.triggerBeat();
        return;
      }
      if (m.type === "start") { this.clockTicks = 0; return; }
      if (m.type === "active_sensing") return;
      if (this.learning) {
        const result = this.map.learn(m, this.learning);
        if (result) {
          this.learning = null;
          this.saveMap();
          this.notify(`learned ${result}`);
          this.refreshLearn();
        }
        return;
      }
      const r = this.map.resolve(m);
      if (!r) return;
      this.apply(...r);
      const [target, , pressed, source] = r;
      // momentary pads also send a release; only the press (or a switch turning off) is worth showing
      if (this.params.has(target) || pressed || source === "cc") this.indicate(this.controlName(m), target);
    }

    // ---- indicator: what the last control changed ---------------------------

    // The physical control behind a MIDI message, from the map's layout (e.g. "F1", "Bank B K3", "Pad C14").
    controlName(m) {
      const key = `${m.channel + 1}:${m.num}`;
      const lay = this.map.extra.layout || {};
      const is = (k) => String(k) === key || String(k) === String(m.num);
      if (m.type === "cc") {
        for (const [bank, groups] of Object.entries(lay.control_banks || {}))
          for (const [g, letter] of [["knobs", "K"], ["faders", "F"], ["switches", "S"]]) {
            const i = (groups[g] || []).findIndex(is);
            if (i >= 0) return `${bank === "A" ? "" : "Bank " + bank + " "}${letter}${i + 1}`;
          }
        const t = (lay.transport || []).findIndex(is);
        if (t >= 0) return ["◀◀", "▶▶", "■ Stop", "▶ Play", "● Rec"][t];
        return `CC ${m.num}`;
      }
      if (m.type === "note_on" || m.type === "note_off") {
        for (const [bank, notes] of Object.entries(lay.pad_banks || {})) {
          const i = notes.findIndex((k) => String(k) === key || (!String(k).includes(":") && String(k) === String(m.num)));
          if (i >= 0) return `Pad ${bank}${i + 1}`;
        }
        return `Note ${m.num}`;
      }
      if (m.type === "program_change") return `Program ${m.num}`;
      return "MIDI";
    }

    // Show "<control> <what> <value>" over the visuals for a moment. Only user input calls this.
    indicate(ctrl, target) {
      if (!this.settings.osd) return;
      const esc = (s) => String(s).replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c]);
      let label, value = "", norm = null;
      const onOff = (on) => `<span class="${on ? "on" : ""}">${on ? "ON" : "OFF"}</span>`;
      if (this.params.has(target)) {
        const p = this.params.get(target);
        const presetLabel = "abcd".includes(target) && this.preset.labels[target];
        label = (PARAM_LABELS[target] || target) + (presetLabel ? ` · ${presetLabel}` : "");
        const v = p.targetValue;
        value = target === "palette" ? D.palettes[Math.round(v) % D.palettes.length].name
              : target === "kaleido" ? (v < 2 ? "off" : `${Math.round(v)} mirrors`)
              : p.isInt ? String(Math.round(v)) : v.toFixed(2);
        norm = p.target;
      } else if (/^(preset:|next|prev|random_preset)/.test(target)) {
        label = `${this.presetIndex + 1} · ${this.preset.name}`;
      } else if (target.startsWith("snapshot:")) {
        const slot = +target.split(":")[1];
        label = `Snapshot ${slot + 1}`;
        value = this.shift ? "saved" : this.snapshots[slot] ? "recalled" : "empty (hold SHIFT to save)";
      } else {
        label = target === "osd_on" ? "Indicator" : ACTION_LABELS[target] || target;
        if (target === "osd_on") value = onOff(true);
        const state = { autopilot: this.pilot.enabled, blackout: this.blackoutTarget > 0, freeze: this.frozen,
                        video: this.videoActive, hud: this.showHud, shift: this.shift }[target];
        if (state !== undefined) value = onOff(state);
        if (target === "autopilot" && this.pilot.enabled) value += ` · intensity ${Math.round(this.pilot.intensity * 100)}%`;
      }
      const el = $("#osd");
      el.innerHTML = `<span class="ctrl">${esc(ctrl)}</span><span class="lbl">${esc(label)}</span>` +
        (norm !== null ? `<span class="bar"><i style="width:${Math.round(norm * 100)}%"></i></span>` : "") +
        (value ? `<span class="val">${value.includes("<span") ? value : esc(value)}</span>` : "");
      el.classList.add("show");
      clearTimeout(this._osd);
      this._osd = setTimeout(() => el.classList.remove("show"), 1600);
    }

    // ---- keyboard -------------------------------------------------------

    bindKeys() {
      const keymap = { r: "randomize", p: "random_preset", Backspace: "reset", a: "autopilot", b: "blackout",
                       z: "freeze", t: "tap", v: "video", h: "hud", ArrowRight: "next", ArrowLeft: "prev" };
      window.addEventListener("keydown", (e) => {
        if (e.target.closest("input, select, textarea")) return;
        if (e.metaKey || e.ctrlKey || e.altKey) return;
        if (e.key === " ") { e.preventDefault(); if (!e.repeat) this.doAction("flash", true); return; }
        if (e.repeat) return;
        if (e.key === "Escape" && this.learning) { this.learning = null; this.refreshLearn(); return; }
        if (e.key === "Escape" && document.body.classList.contains("immersive")) { this.setImmersive(false); return; }
        if (e.key === "f") { this.toggleFullscreen(); return; }
        if (e.key === "i" || e.key === "I") {
          this.settings.osd = !this.settings.osd; store.set("settings", this.settings); $("#osdToggle").checked = this.settings.osd;
          if (this.settings.osd) this.indicate("Key I", "osd_on"); else { $("#osd").classList.remove("show"); this.notify("indicator off"); }
          return;
        }
        if (/^[0-9]$/.test(e.key)) { this.selectPreset((parseInt(e.key, 10) + 9) % 10); this.indicate(`Key ${e.key}`, "next"); return; }
        const action = keymap[e.key] || keymap[e.key.toLowerCase()];
        if (action) {
          e.preventDefault();
          this.doAction(action);
          const keyName = { ArrowRight: "→", ArrowLeft: "←", Backspace: "⌫" }[e.key] || e.key.toUpperCase();
          this.indicate(`Key ${keyName}`, action);
        }
      });
      window.addEventListener("keyup", (e) => { if (e.key === " ") this.doAction("flash", false); });
    }

    // ---- devices ----------------------------------------------------------

    async start() {
      if (!window.isSecureContext) return this.insecureWarning();
      $("#start").disabled = true;
      $("#start").textContent = "Starting…";
      await this.midi.start();
      const savedMic = store.get("micId", null), savedCam = store.get("camId", null);
      try { await this.audio.start(savedMic); }
      catch (e) {
        try { await this.audio.start(null); } catch (e2) { this.notify("microphone blocked: using the demo beat"); this.audio.fake = true; }
      }
      await this.startCamera(savedCam);
      await this.listDevices();
      $("#start").hidden = true;
      $("body").classList.add("started");
      this.started = true;
      this.keepAwake();
      this.refreshChrome();
    }

    // Chrome only offers camera, mic and MIDI on https (or localhost / a file on disk), and on plain http
    // it doesn't even ask. Say so instead of failing silently.
    insecureWarning() {
      const secure = location.href.replace(/^http:/, "https:");
      $("#introText").innerHTML = `This page was opened over plain <b>http</b>, so Chrome won't allow the camera,
        microphone or MIDI (it doesn't even ask). Open the secure version: <a href="${secure}">${secure}</a>`;
      this.notify("needs https for camera, mic and MIDI");
    }

    async startCamera(deviceId) {
      if (this.camStream) this.camStream.getTracks().forEach((t) => t.stop());
      this.camStream = null;
      if (deviceId === "none") { this.video.srcObject = null; return; }
      try {
        this.camStream = await navigator.mediaDevices.getUserMedia({
          video: { deviceId: deviceId ? { exact: deviceId } : undefined, width: { ideal: 1280 }, height: { ideal: 720 } },
          audio: false,
        });
      } catch (e) {
        if (deviceId) return this.startCamera(null);
        this.camStatus = "blocked or missing";
        this.notify("camera blocked or missing");
        return;
      }
      this.video.srcObject = this.camStream;
      await this.video.play().catch(() => {});
      const track = this.camStream.getVideoTracks()[0];
      this.camStatus = track.label;
      this.video360 = /insta360|theta|360/i.test(track.label);
      $("#cam360row").hidden = !this.video360;
      document.body.classList.toggle("cam360", this.video360);
    }

    async listDevices() {
      const devices = await navigator.mediaDevices.enumerateDevices();
      const fill = (sel, kind, current, extra) => {
        sel.innerHTML = "";
        for (const [v, label] of extra) sel.add(new Option(label, v));
        devices.filter((d) => d.kind === kind).forEach((d, i) => sel.add(new Option(d.label || `${kind} ${i + 1}`, d.deviceId)));
        if (current) sel.value = current;
      };
      const camTrack = this.camStream?.getVideoTracks()[0];
      const micTrack = this.audio.stream?.getAudioTracks()[0];
      fill($("#camSel"), "videoinput", camTrack?.getSettings().deviceId || (this.camStream ? "" : "none"), [["none", "No camera"]]);
      fill($("#micSel"), "audioinput", this.audio.fake ? "demo" : micTrack?.getSettings().deviceId, [["demo", "Demo beat (no mic)"]]);
    }

    // ---- fullscreen / projector --------------------------------------------

    async toggleFullscreen() {
      if (document.body.classList.contains("immersive")) return this.setImmersive(false);
      if (document.fullscreenElement || document.webkitFullscreenElement)
        return (document.exitFullscreen || document.webkitExitFullscreen).call(document);
      const stage = $("#stage");
      if (!stage.requestFullscreen) {
        // iPhone Safari can't fullscreen a page element: fill the screen ourselves instead
        if (stage.webkitRequestFullscreen) return stage.webkitRequestFullscreen();
        return this.setImmersive(true);
      }
      let screen;
      if ("getScreenDetails" in window) {
        try {
          const details = await window.getScreenDetails();
          // prefer an external screen (the projector) over the laptop's built-in one
          screen = details.screens.find((s) => !s.isInternal && s !== details.currentScreen) ||
                   details.screens.find((s) => s !== details.currentScreen);
        } catch (e) { /* permission denied: fullscreen on this screen */ }
      }
      try { await stage.requestFullscreen(screen ? { screen, navigationUI: "hide" } : { navigationUI: "hide" }); }
      catch (e) { await stage.requestFullscreen(); }
    }

    setImmersive(on) {
      document.body.classList.toggle("immersive", on);
      this.resize();
      if (on) this.notify("double-tap or Esc to exit");
    }

    // Swipe left/right on the visuals for next/previous preset; double-tap for fullscreen.
    bindTouch() {
      const stage = $("#stage");
      let sx = 0, sy = 0, st = 0, lastTap = 0;
      stage.addEventListener("touchstart", (e) => {
        if (e.touches.length !== 1) return;
        sx = e.touches[0].clientX; sy = e.touches[0].clientY; st = performance.now();
      }, { passive: true });
      stage.addEventListener("touchend", (e) => {
        if (e.target.closest("button")) return;
        const t = e.changedTouches[0];
        const dx = t.clientX - sx, dy = t.clientY - sy, quick = performance.now() - st < 600;
        if (quick && Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(dy) * 1.5) {
          this.doAction(dx < 0 ? "next" : "prev");
          this.indicate(dx < 0 ? "Swipe ←" : "Swipe →", "next");
          lastTap = 0;
        } else if (Math.abs(dx) < 14 && Math.abs(dy) < 14) {
          const now = performance.now();
          if (now - lastTap < 320) { e.preventDefault(); this.toggleFullscreen(); lastTap = 0; } else lastTap = now;
        }
      });
    }

    // Ask the device not to dim or sleep the screen while GoonViz runs (re-asked when the tab returns).
    async keepAwake() {
      try {
        if ("wakeLock" in navigator && document.visibilityState === "visible") this.wakeLock = await navigator.wakeLock.request("screen");
      } catch (e) { /* not supported or refused: harmless */ }
    }

    resize() {
      // phones have 3x screens; 2x is plenty for the display pass and saves a lot of fill rate
      const dpr = Math.min(window.devicePixelRatio || 1, this.lowPower ? 2 : Infinity);
      const w = Math.max(16, Math.round(this.canvas.clientWidth * dpr));
      const h = Math.max(16, Math.round(this.canvas.clientHeight * dpr));
      if (this.canvas.width !== w || this.canvas.height !== h) { this.canvas.width = w; this.canvas.height = h; }
      const q = this.settings.quality;
      const targetWidth = q === "low" ? 800 : q === "medium" ? 1200 : q === "high" ? 1920
                        : this.mobile ? 720 : this.pi ? 768 : this.engine.weakGpu ? 960 : 1440; // auto: phones, Pis and Intel graphics get a lighter load
      this.engine.resize(w, h, Math.min(1, targetWidth / w) * this.dyn);
    }

    // Adaptive resolution: if frames run late for a second, render ~12% fewer pixels; when there's
    // headroom for a few seconds, step back up. Keeps motion smooth on heavy 3D presets.
    adaptResolution(dt, now) {
      const ms = dt * 1000;
      this.frameMs += (ms - this.frameMs) * 0.08;
      this.recentMs.push(ms);
      if (this.recentMs.length > 120) this.recentMs.shift();
      if (now < this.dynCheck) return;
      // refresh interval = the typical fast frame (20th percentile), snapped to a real display rate,
      // so a few early/odd frames can't fool it
      const sorted = [...this.recentMs].sort((a, b) => a - b);
      const p20 = sorted[Math.floor(sorted.length * 0.2)] || 16.7;
      this.refreshMs = [144, 120, 100, 90, 75, 60, 50, 30].map((hz) => 1000 / hz)
        .reduce((best, x) => (Math.abs(x - p20) < Math.abs(best - p20) ? x : best));
      // Phones: if even the lowest resolution can't hold the display rate, settle for a steady half rate
      // (30 fps on a 60 Hz phone) and spend the extra time on sharpness instead of mush. Desktops never do this.
      const floor = this.lowPower ? 0.45 : 0.5;
      if (this.lowPower && !this.halfRate && this.dyn <= floor && this.frameMs > this.refreshMs * 1.18) this.halfRate = true;
      const target = this.refreshMs * (this.halfRate ? 2 : 1);
      if (this.frameMs > target * 1.18 && this.dyn > floor) {
        this.dyn = Math.max(floor, this.dyn * 0.88);
        this.dynCheck = now + 1000;
        this.resize();
      } else if (this.frameMs < target * 1.04 && this.dyn < 1) {
        this.dyn = Math.min(1, this.dyn * 1.06);
        this.dynCheck = now + 3000;
        this.resize();
      } else this.dynCheck = now + 500;
    }

    // ---- frame ----------------------------------------------------------------

    frame(now) {
      const dt = Math.min((now - this.last) / 1000, 0.1);
      this.last = now;
      if (dt > 0) this.fps += (1 / dt - this.fps) * 0.05;
      if (dt > 0 && this.settings.quality === "auto") this.adaptResolution(dt, now);
      const P = this.params, st = this.st;

      this.engine.pump();
      this.audio.update(dt);
      P.update(dt);
      this.tickAutopilot(dt);
      this.engine.updateVideo(this.video, this.videoActive, this.video360);
      this.engine.updatePalette(P.v("palette"), dt);

      if (!this.frozen) {
        st.time += dt * P.v("speed");
        st.pulse += dt * P.v("speed") * (1 + this.audio.bass * P.v("react") * 1.5);
      }
      st.realTime = now / 1000;
      st.camYaw = (st.camYaw + dt * P.v("cam_spin") * 0.6) % (Math.PI * 2);
      st.flash = this.flashHeld ? 1 : st.flash * Math.exp(-dt * 10);
      st.blackout += (this.blackoutTarget - st.blackout) * (1 - Math.exp(-dt * 4));
      st.transition = Math.max(0, st.transition - dt / 1.2); // 1.2 s melt between presets

      this.engine.render(this.preset, P, st, this.audio);
      if ((this._uiTick = (this._uiTick || 0) + 1) % 6 === 0) this.refreshLive();
      requestAnimationFrame((t) => this.frame(t));
    }

    tickAutopilot(dt) {
      const beats = this.audio.beatCount - this.lastBeatCount;
      this.lastBeatCount = this.audio.beatCount;
      for (const ev of this.pilot.update(dt, beats, this.audio)) {
        if (ev.type === "switch") {
          this.selectPreset(ev.index);          // also restarts the pilot's phrase on the new preset
          if (ev.cut) this.st.transition = 0;   // drops cut hard instead of melting
        } else if (ev.type === "flash") this.st.flash = Math.max(this.st.flash, ev.amount);
      }
    }

    notify(text) {
      const el = $("#toast");
      el.textContent = text;
      el.classList.add("show");
      clearTimeout(this._toast);
      this._toast = setTimeout(() => el.classList.remove("show"), 1800);
    }

    // ---- control panel ----------------------------------------------------------

    learnButton(target) {
      const b = document.createElement("button");
      b.className = "learn";
      b.title = "MIDI learn: click, then move a knob or hit a pad";
      b.textContent = "L";
      b.dataset.target = target;
      b.onclick = (e) => {
        e.stopPropagation();
        this.learning = this.learning === target ? null : target;
        if (this.learning) this.notify(`MIDI learn: move a control for “${this.labelFor(target)}”`);
        this.refreshLearn();
      };
      return b;
    }

    labelFor(target) {
      if (PARAM_LABELS[target]) return PARAM_LABELS[target];
      if (ACTION_LABELS[target]) return ACTION_LABELS[target];
      if (target.startsWith("preset:")) return this.presets[+target.split(":")[1]]?.name || target;
      if (target.startsWith("snapshot:")) return `Snapshot ${+target.split(":")[1] + 1}`;
      return target;
    }

    buildPanel() {
      $("#start").onclick = () => this.start();
      $("#fullscreen").onclick = () => this.toggleFullscreen();
      $("#gpu").textContent = this.engine.renderer;

      // presets
      const grid = $("#presets");
      this.presetButtons = this.presets.map((p, i) => {
        const b = document.createElement("button");
        b.className = "preset";
        b.innerHTML = `<span class="n">${i + 1}</span><span class="name"></span>`;
        b.querySelector(".name").textContent = p.name.replace(" (video)", "");
        if (/\(video\)/.test(p.name)) b.classList.add("video");
        if (p.heavy) { b.classList.add("heavy"); b.title = "3D/4D: heavy. Fine on a Mac or modern phone, slow on a Raspberry Pi"; }
        if (p.error) { b.disabled = true; b.title = p.error; }
        b.onclick = () => this.selectPreset(i);
        b.appendChild(this.learnButton(`preset:${i}`));
        grid.appendChild(b);
        return b;
      });

      // knobs
      const knobs = $("#knobs");
      this.sliders = {};
      for (const p of this.params.list) {
        const row = document.createElement("label");
        row.className = "knob" + (p.scope === "master" ? " master" : "");
        row.innerHTML = `<span class="lbl"></span><input type="range" min="0" max="1" step="0.001"><output></output>`;
        row.querySelector(".lbl").textContent = PARAM_LABELS[p.name] || p.name;
        const input = row.querySelector("input");
        input.oninput = () => {
          p.setNorm(+input.value);
          if (p.name === "ap_intensity") store.set("apIntensity", p.targetValue);
          else this.pilot.touch(p.name); // autopilot leaves knobs you've moved alone until the next switch
          this.indicate("Slider", p.name);
        };
        row.appendChild(this.learnButton(p.name));
        if (p.name.startsWith("cam_")) row.classList.add("cam360");
        (p.name === "ap_intensity" ? $("#pilotKnob") : knobs).appendChild(row);
        this.sliders[p.name] = { row, input, out: row.querySelector("output"), lbl: row.querySelector(".lbl") };
      }

      // actions
      const acts = $("#actions");
      this.actionButtons = {};
      for (const a of D.actions.filter((a) => !a.startsWith("snapshot:"))) {
        if (a === "autopilot") continue; // lives in the Autopilot section
        const b = document.createElement("button");
        b.className = "action";
        b.textContent = ACTION_LABELS[a] || a;
        if (D.momentary.includes(a)) {
          b.onpointerdown = () => this.doAction(a, true);
          b.onpointerup = b.onpointerleave = () => this.doAction(a, false);
        } else b.onclick = () => this.doAction(a);
        b.appendChild(this.learnButton(a));
        acts.appendChild(b);
        this.actionButtons[a] = b;
      }

      // autopilot toggle
      const pb = $("#pilotBtn");
      pb.onclick = () => this.doAction("autopilot");
      pb.appendChild(this.learnButton("autopilot"));
      this.actionButtons.autopilot = pb;

      // snapshots
      const snaps = $("#snapshots");
      this.snapButtons = [];
      for (let i = 0; i < 8; i++) {
        const b = document.createElement("button");
        b.className = "snap";
        b.textContent = i + 1;
        b.title = "click: recall · shift-click: save";
        b.onclick = (e) => (e.shiftKey || this.shift ? this.saveSnapshot(i) : this.recallSnapshot(i));
        b.appendChild(this.learnButton(`snapshot:${i}`));
        snaps.appendChild(b);
        this.snapButtons.push(b);
      }

      // devices
      $("#camSel").onchange = (e) => { store.set("camId", e.target.value); this.startCamera(e.target.value); };
      $("#micSel").onchange = async (e) => {
        const id = e.target.value;
        store.set("micId", id === "demo" ? null : id);
        this.audio.fake = id === "demo";
        if (!this.audio.fake) await this.audio.start(id).catch(() => this.notify("could not open that input"));
        else this.audio.stop();
      };
      $("#quality").value = this.settings.quality;
      $("#quality").onchange = (e) => { this.settings.quality = e.target.value; store.set("settings", this.settings); this.resize(); };
      $("#pickup").checked = this.settings.pickup;
      $("#osdToggle").checked = this.settings.osd;
      $("#osdToggle").onchange = (e) => { this.settings.osd = e.target.checked; store.set("settings", this.settings); if (!this.settings.osd) $("#osd").classList.remove("show"); };
      $("#pickup").onchange = (e) => { this.settings.pickup = e.target.checked; store.set("settings", this.settings); };

      // MIDI map
      const mapSel = $("#mapSel");
      for (const name of Object.keys(D.maps)) mapSel.add(new Option(D.maps[name].controller || name, name));
      mapSel.value = this.mapName;
      mapSel.onchange = () => { this.mapName = mapSel.value; store.set("mapName", this.mapName); this.loadMap(); this.refreshMapUi(); };
      $("#mapReset").onclick = () => {
        if (!confirm("Forget your MIDI-learn changes for this controller and go back to the original map?")) return;
        try { localStorage.removeItem("prism.map." + this.mapName); } catch (e) { /* ignore */ }
        this.loadMap(); this.refreshMapUi(); this.notify("map reset");
      };
      $("#exportBtn").onclick = () => this.exportSettings();
      $("#importFile").onchange = (e) => this.importSettings(e.target.files[0]);
      this.refreshMapUi();
      this.refreshSnapshots();
    }

    exportSettings() {
      const data = { prism: 1, mapName: this.mapName, map: this.map.toJSON(), snapshots: this.snapshots, settings: this.settings };
      const a = document.createElement("a");
      a.href = URL.createObjectURL(new Blob([JSON.stringify(data, null, 2)], { type: "application/json" }));
      a.download = `goonviz-settings-${new Date().toISOString().slice(0, 10)}.json`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 1000);
    }

    async importSettings(file) {
      if (!file) return;
      try {
        const data = JSON.parse(await file.text());
        if (data.mapName && data.map) { this.mapName = data.mapName; store.set("mapName", this.mapName); store.set("map." + this.mapName, data.map); }
        if (data.snapshots) { this.snapshots = data.snapshots; store.set("snapshots", this.snapshots); }
        if (data.settings) { Object.assign(this.settings, data.settings); store.set("settings", this.settings); }
        this.loadMap(); this.refreshMapUi(); this.refreshSnapshots();
        $("#mapSel").value = this.mapName;
        this.notify("settings imported");
      } catch (e) { this.notify("that file isn't a GoonViz settings export"); }
    }

    refreshPresetButtons() {
      this.presetButtons?.forEach((b, i) => b.classList.toggle("on", i === this.presetIndex));
    }
    refreshLabels() {
      if (!this.sliders) return;
      for (const k of "abcd") {
        const lab = this.preset.labels[k];
        this.sliders[k].lbl.textContent = lab ? `${k.toUpperCase()} · ${lab}` : PARAM_LABELS[k];
      }
      $("#nowName").textContent = this.preset.name;
    }
    refreshSnapshots() { this.snapButtons?.forEach((b, i) => b.classList.toggle("filled", !!this.snapshots[i])); }
    refreshLearn() {
      document.querySelectorAll(".learn").forEach((b) => b.classList.toggle("armed", b.dataset.target === this.learning));
      $("body").classList.toggle("learning", !!this.learning);
    }
    refreshMapUi() { $("#mapState").textContent = this.mapEdited ? "includes your MIDI-learn changes" : "original"; }
    refreshChrome() {
      const on = { autopilot: this.pilot.enabled, blackout: this.blackoutTarget > 0, freeze: this.frozen, shift: this.shift,
                   video: this.videoActive, hud: this.showHud };
      for (const [a, b] of Object.entries(this.actionButtons || {})) b.classList.toggle("on", !!on[a]);
      $("#hud").hidden = !this.showHud;
      $("#pilotBtn").firstChild.textContent = this.pilot.enabled ? "Autopilot ON" : "Autopilot off";
    }
    refreshLive() {
      this.presetButtons.forEach((b, i) => { if (this.presets[i].error && !b.disabled) { b.disabled = true; b.title = this.presets[i].error; } });
      for (const p of this.params.list) {
        const s = this.sliders[p.name];
        if (document.activeElement !== s.input) s.input.value = p.target;
        const v = p.targetValue;
        s.out.textContent = p.name === "palette" ? D.palettes[Math.round(v) % D.palettes.length].name
                          : p.isInt ? String(Math.round(v)) : v.toFixed(2);
      }
      const a = this.audio;
      const bar = (x) => `<i style="width:${Math.round(Math.min(1, x) * 100)}%"></i>`;
      $("#meters").innerHTML = `<span>bass</span><b>${bar(a.bass)}</b><span>mid</span><b>${bar(a.mid)}</b><span>high</span><b>${bar(a.high)}</b>` +
        `<span class="beat ${a.beat > 0.5 ? "hit" : ""}">●</span>`;
      $("#fps").textContent = `${Math.round(this.fps)}/${Math.round(1000 / this.refreshMs / (this.halfRate ? 2 : 1))} fps · ${this.engine.internal[0]}×${this.engine.internal[1]}`;
      $("#midiStatus").textContent = this.midi.status;
      $("#midiLast").textContent = this.midi.last;
      $("#audioStatus").textContent = a.fake ? "demo beat" : a.status === "live" ? a.label : a.status;
      $("#camStatus").textContent = this.camStatus || "off";
      const I = this.pilot.intensity;
      $("#pilotInfo").textContent = this.pilot.enabled
        ? `${this.pilot.status()} · next change in ${this.pilot.beatsUntilSwitch()} beats`
        : `changes every ${this.pilot.phraseBeats()} beats, follows drops and breakdowns`;
      $("#hud").innerHTML = `<b>${this.preset.name}</b> · ${Math.round(this.fps)} fps` +
        (this.pilot.enabled ? ` · AUTOPILOT ${Math.round(this.pilot.intensity * 100)}%` : "") + (this.frozen ? " · FROZEN" : "") +
        (this.blackoutTarget ? " · BLACKOUT" : "") + (this.shift ? " · SHIFT" : "");
    }
  }

  window.addEventListener("DOMContentLoaded", () => {
    try { window.prism = new App(); }
    catch (e) {
      document.body.classList.add("failed");
      $("#fatal").textContent = `GoonViz couldn't start: ${e.message}`;
      console.error(e);
    }
  });
})();
