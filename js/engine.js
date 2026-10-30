// WebGL2 port of prism/engine.py: preset scene -> composite (bloom, kaleido, feedback) -> display (grading).
// Uses the exact same GLSL sources as the Pi/desktop version (bundled by tools/build_web.py).
(function () {
  "use strict";
  const Prism = (window.Prism = window.Prism || {});

  const HEADER =
    "#version 300 es\nprecision highp float;\nprecision highp int;\nprecision highp sampler2D;\n" +
    "#define VIDEO_SWIZZLE rgb\n"; // browser video frames are RGB (OpenCV's are BGR)

  const VERT = `
in vec2 in_pos;
out vec2 vUV;
void main() {
    vUV = in_pos * 0.5 + 0.5;
    gl_Position = vec4(in_pos, 0.0, 1.0);
}
`;

  const SCENE_MAIN = `
void main() {
    vec2 p = vUV * 2.0 - 1.0;
    p.x *= uRes.x / uRes.y;
    p /= uZoom;
    fragColor = vec4(tonemap(scene(p, vUV)), 1.0);
}
`;

  const META_RE = /\/\/\s*@preset\s*(\{.*\})/;

  // Same as stepped_knobs in prism/engine.py: knobs a preset rounds to whole numbers (counts), which
  // autopilot must not glide (the shape would pop). Any line with floor( or int( counts.
  function steppedKnobs(source) {
    const found = new Set();
    for (const line of source.split("\n")) {
      const code = line.split("//")[0];
      if (code.includes("floor(") || code.includes("int(")) for (const m of code.matchAll(/\bu([ABCD])\b/g)) found.add(m[1].toLowerCase());
    }
    return found;
  }

  function parsePreset(key, source) {
    let meta = {};
    const m = source.match(META_RE);
    if (m) {
      try { meta = JSON.parse(m[1]); } catch (e) { console.warn(`bad @preset header in ${key}`, e); }
    }
    return {
      key, source,
      name: meta.name || key.replace(/^\d+_/, "").replace(/_/g, " "),
      params: meta.params || {},
      labels: meta.labels || {},
      stepped: steppedKnobs(source),
      program: null, error: null,
    };
  }

  function hexToRgb(h) {
    h = h.replace("#", "");
    return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16) / 255);
  }

  class Engine {
    constructor(canvas, data) {
      const gl = canvas.getContext("webgl2", {
        antialias: false, alpha: false, depth: false, stencil: false,
        preserveDrawingBuffer: false, powerPreference: "high-performance",
      });
      if (!gl) throw new Error("WebGL2 is not available in this browser");
      this.gl = gl;
      this.canvas = canvas;
      this.data = data;
      const dbg = gl.getExtension("WEBGL_debug_renderer_info");
      this.renderer = dbg ? gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
      this.weakGpu = /intel/i.test(this.renderer) && !/arc/i.test(this.renderer);

      this.quad = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, this.quad);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
      this.vao = gl.createVertexArray();
      gl.bindVertexArray(this.vao);
      gl.enableVertexAttribArray(0);
      gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);

      const S = data.shaders;
      this.comp = this.program(S.lib + S.composite);
      this.disp = this.program(S.lib + S.display);
      this.presets = data.presets.map((p) => parsePreset(p.key, p.source));
      // Compile the first working preset now, the rest in the background (see pump), so the page is up
      // in a moment even on a phone. With KHR_parallel_shader_compile the driver compiles them all in
      // parallel; without it pump() finishes one per frame.
      this.parallel = gl.getExtension("KHR_parallel_shader_compile");
      if (!this.presets.some((p) => this.ensure(p))) throw new Error("no presets compiled; see console");
      if (this.parallel) for (const p of this.presets) if (!p.program && !p.error) this.startPreset(p);

      this.palettes = data.palettes.map((p) => p.colors.map(hexToRgb));
      this.palette = new Float32Array(this.palettes[0].flat());

      this.fftTex = this.texture(gl.R8, 128, 1, gl.LINEAR);
      this.videoTex = this.texture(gl.RGBA8, 1, 1, gl.LINEAR);
      gl.bindTexture(gl.TEXTURE_2D, this.videoTex);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT); // 360 panoramas wrap
      this.videoOn = false;
      this.video360 = false;
      this.lastVideoTime = -1;
      this.cur = 0;
      this.scale = 0.75;
      this.exposure = 1;
      this.autoExposure = true;
      this.frameNo = 0;
      this.meterPx = new Uint8Array(4);
      this.screenSize = [0, 0];
    }

    // ---- setup ---------------------------------------------------------

    shader(type, src) {
      const gl = this.gl;
      const sh = gl.createShader(type);
      gl.shaderSource(sh, src);
      gl.compileShader(sh);
      if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
        const log = gl.getShaderInfoLog(sh);
        gl.deleteShader(sh);
        throw new Error(log);
      }
      return sh;
    }

    // Two-phase build: startProgram() kicks off compile + link without asking for the result (asking
    // blocks until the GPU driver is done); finishProgram() collects it.
    startProgram(frag) {
      const gl = this.gl;
      const mk = (type, src) => { const sh = gl.createShader(type); gl.shaderSource(sh, src); gl.compileShader(sh); return sh; };
      const vs = mk(gl.VERTEX_SHADER, HEADER + VERT);
      const fs = mk(gl.FRAGMENT_SHADER, HEADER + frag);
      const prog = gl.createProgram();
      gl.attachShader(prog, vs);
      gl.attachShader(prog, fs);
      gl.bindAttribLocation(prog, 0, "in_pos");
      gl.linkProgram(prog);
      return { prog, vs, fs };
    }

    finishProgram(job) {
      const gl = this.gl;
      const { prog, vs, fs } = job;
      if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
        const log = gl.getShaderInfoLog(fs) || gl.getShaderInfoLog(vs) || gl.getProgramInfoLog(prog);
        gl.deleteProgram(prog);
        throw new Error(log);
      }
      gl.detachShader(prog, vs); gl.deleteShader(vs);
      gl.detachShader(prog, fs); gl.deleteShader(fs);
      const uniforms = {};
      const n = gl.getProgramParameter(prog, gl.ACTIVE_UNIFORMS);
      for (let i = 0; i < n; i++) {
        const info = gl.getActiveUniform(prog, i);
        const name = info.name.replace(/\[0\]$/, "");
        uniforms[name] = gl.getUniformLocation(prog, info.name);
      }
      return { prog, uniforms };
    }

    program(frag) { return this.finishProgram(this.startProgram(frag)); }

    startPreset(preset) {
      const S = this.data.shaders;
      preset.job = this.startProgram(S.lib + S.scene_header + preset.source + SCENE_MAIN);
    }

    finishPreset(preset) {
      try {
        preset.program = this.finishProgram(preset.job);
        preset.error = null;
      } catch (e) {
        preset.error = String(e.message || e);
        console.error(`[preset] ${preset.key} failed to compile:\n${preset.error}`);
      }
      preset.job = null;
    }

    // Make sure a preset is usable right now (blocks if it is still compiling). Returns false if broken.
    ensure(preset) {
      if (preset.program) return true;
      if (preset.error) return false;
      if (!preset.job) this.startPreset(preset);
      this.finishPreset(preset);
      return !!preset.program;
    }

    // Call once per frame: collect background compiles that have finished.
    pump() {
      const gl = this.gl;
      for (const p of this.presets) {
        if (p.program || p.error) continue;
        if (this.parallel) {
          if (p.job && gl.getProgramParameter(p.job.prog, this.parallel.COMPLETION_STATUS_KHR)) this.finishPreset(p);
        } else {
          this.ensure(p); // no background compiling available: one per frame
          return;
        }
      }
    }

    get readyCount() { return this.presets.filter((p) => p.program).length; }

    texture(internal, w, h, filter, mip = false) {
      const gl = this.gl;
      const tex = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, tex);
      const levels = mip ? Math.floor(Math.log2(Math.max(w, h))) + 1 : 1;
      gl.texStorage2D(gl.TEXTURE_2D, levels, internal, w, h);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, mip ? gl.LINEAR_MIPMAP_LINEAR : filter);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, filter);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      return tex;
    }

    target(tex) {
      const gl = this.gl;
      const fbo = gl.createFramebuffer();
      gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
      gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0);
      gl.clearColor(0, 0, 0, 1);
      gl.clear(gl.COLOR_BUFFER_BIT);
      return fbo;
    }

    resize(w, h, scale) {
      const gl = this.gl;
      this.scale = scale;
      this.screenSize = [w, h];
      const iw = Math.max(16, Math.round(w * scale));
      const ih = Math.max(16, Math.round(h * scale));
      if (this.internal && this.internal[0] === iw && this.internal[1] === ih) return;
      const old = this.internal && { fbo: this.compFbo[this.cur], w: this.internal[0], h: this.internal[1], owned: this._owned };
      this.internal = [iw, ih];
      this.sceneTex = this.texture(gl.RGBA8, iw, ih, gl.LINEAR, true);
      this.sceneFbo = this.target(this.sceneTex);
      // comp textures get a mip chain (sampled without mips) so the meter can read their 1x1 average
      this.compTex = [0, 1].map(() => {
        const t = this.texture(gl.RGBA8, iw, ih, gl.LINEAR, true);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        return t;
      });
      this.compFbo = this.compTex.map((t) => this.target(t));
      // auto-exposure meters: framebuffers on each comp texture's 1x1 mip level (its average colour)
      const top = Math.floor(Math.log2(Math.max(iw, ih)));
      this.meterFbo = this.compTex.map((t) => {
        const fbo = gl.createFramebuffer();
        gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
        gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, t, top);
        return fbo;
      });
      this._owned = [this.sceneTex, this.sceneFbo, ...this.compTex, ...this.compFbo, ...this.meterFbo];
      if (old) {
        // carry the current frame over (scaled) so a resolution change doesn't flash the trails to black
        gl.bindFramebuffer(gl.READ_FRAMEBUFFER, old.fbo);
        gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, this.compFbo[this.cur]);
        gl.blitFramebuffer(0, 0, old.w, old.h, 0, 0, iw, ih, gl.COLOR_BUFFER_BIT, gl.LINEAR);
        gl.bindFramebuffer(gl.FRAMEBUFFER, null);
        if (this.meterFence) { gl.deleteSync(this.meterFence); this.meterFence = null; }
        for (const t of old.owned) (t instanceof WebGLTexture ? gl.deleteTexture(t) : gl.deleteFramebuffer(t));
      }
    }

    // ---- per-frame inputs ---------------------------------------------

    updateVideo(video, active, is360) {
      const gl = this.gl;
      this.videoOn = !!(video && active && video.readyState >= 2 && video.videoWidth);
      this.video360 = is360;
      if (!this.videoOn || video.currentTime === this.lastVideoTime) return;
      this.lastVideoTime = video.currentTime;
      gl.bindTexture(gl.TEXTURE_2D, this.videoTex);
      if (this.videoSize?.[0] !== video.videoWidth || this.videoSize?.[1] !== video.videoHeight) {
        gl.deleteTexture(this.videoTex);
        this.videoTex = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, this.videoTex);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        this.videoSize = [video.videoWidth, video.videoHeight];
      }
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, video);
    }

    updatePalette(index, dt) {
      const target = this.palettes[((Math.round(index) % this.palettes.length) + this.palettes.length) % this.palettes.length].flat();
      const k = Math.min(1, dt * 2.5); // ~0.4s crossfade
      for (let i = 0; i < 15; i++) this.palette[i] += (target[i] - this.palette[i]) * k;
    }

    // ---- render --------------------------------------------------------

    // Auto-exposure, same rule as Engine._meter in prism/engine.py: above a mean luma of 0.32 step the
    // exposure down, below it creep back up to 1 (never brighter). The 1-pixel average is read back
    // asynchronously (pixel buffer + fence) so the CPU never waits on the GPU: no stutter.
    meter(i) {
      const gl = this.gl;
      if (!this.autoExposure) { this.exposure = 1; return; }
      if (this.meterFence) {
        const st = gl.clientWaitSync(this.meterFence, 0, 0);
        if (st === gl.ALREADY_SIGNALED || st === gl.CONDITION_SATISFIED) {
          gl.bindBuffer(gl.PIXEL_PACK_BUFFER, this.meterPbo);
          gl.getBufferSubData(gl.PIXEL_PACK_BUFFER, 0, this.meterPx);
          gl.bindBuffer(gl.PIXEL_PACK_BUFFER, null);
          gl.deleteSync(this.meterFence);
          this.meterFence = null;
          const [r, g, b] = this.meterPx;
          const mean = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
          this.exposure *= mean > 0.32 ? Math.pow(0.32 / mean, 0.35) : 1.04;
          this.exposure = Math.min(1, Math.max(0.35, this.exposure));
        }
        return;
      }
      if (++this.frameNo % 6) return;
      if (!this.meterPbo) {
        this.meterPbo = gl.createBuffer();
        gl.bindBuffer(gl.PIXEL_PACK_BUFFER, this.meterPbo);
        gl.bufferData(gl.PIXEL_PACK_BUFFER, 4, gl.STREAM_READ);
      }
      gl.bindTexture(gl.TEXTURE_2D, this.compTex[i]);
      gl.generateMipmap(gl.TEXTURE_2D);
      gl.bindFramebuffer(gl.READ_FRAMEBUFFER, this.meterFbo[i]);
      gl.bindBuffer(gl.PIXEL_PACK_BUFFER, this.meterPbo);
      gl.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, 0);
      gl.bindBuffer(gl.PIXEL_PACK_BUFFER, null);
      gl.bindFramebuffer(gl.READ_FRAMEBUFFER, null);
      this.meterFence = gl.fenceSync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0);
    }

    set(p, name, ...v) {
      const loc = p.uniforms[name];
      if (loc === undefined) return;
      const gl = this.gl;
      if (v.length === 1) gl.uniform1f(loc, v[0]);
      else if (v.length === 2) gl.uniform2f(loc, v[0], v[1]);
    }

    setTex(p, name, unit, tex) {
      const loc = p.uniforms[name];
      if (loc === undefined) return;
      const gl = this.gl;
      gl.activeTexture(gl.TEXTURE0 + unit);
      gl.bindTexture(gl.TEXTURE_2D, tex);
      gl.uniform1i(loc, unit);
    }

    render(preset, P, st, audio) {
      const gl = this.gl;
      const s = this.set.bind(this);
      const react = P.v("react");
      const prevTex = this.compTex[this.cur];
      const outFbo = this.compFbo[1 - this.cur];
      const outTex = this.compTex[1 - this.cur];
      const [iw, ih] = this.internal;
      const bass = Math.min(1, audio.bass * react);
      const beat = audio.beat * Math.min(1, react);
      const videoOn = this.videoOn ? 1 : 0;
      const v360 = this.video360 ? 1 : 0;

      gl.activeTexture(gl.TEXTURE2);
      gl.bindTexture(gl.TEXTURE_2D, this.fftTex);
      gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
      gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, 128, 1, gl.RED, gl.UNSIGNED_BYTE, audio.fft);

      // Scene
      const p = preset.program;
      gl.useProgram(p.prog);
      gl.bindFramebuffer(gl.FRAMEBUFFER, this.sceneFbo);
      gl.viewport(0, 0, iw, ih);
      s(p, "uRes", iw, ih);
      s(p, "uTime", st.time);
      s(p, "uPulse", st.pulse);
      s(p, "uRealTime", st.realTime);
      s(p, "uA", P.v("a")); s(p, "uB", P.v("b")); s(p, "uC", P.v("c")); s(p, "uD", P.v("d"));
      s(p, "uZoom", P.v("zoom"));
      s(p, "uBass", bass);
      s(p, "uMid", Math.min(1, audio.mid * react));
      s(p, "uHigh", Math.min(1, audio.high * react));
      s(p, "uLevel", Math.min(1, audio.level * react));
      s(p, "uBeat", beat);
      s(p, "uBeatCount", audio.beatCount);
      s(p, "uVideoOn", videoOn);
      s(p, "uVideo360", v360);
      s(p, "uCamView", P.v("cam_view"));
      s(p, "uCamYaw", st.camYaw);
      this.setTex(p, "uPrev", 0, prevTex);
      this.setTex(p, "uVideo", 1, this.videoTex);
      this.setTex(p, "uFFT", 2, this.fftTex);
      if (p.uniforms.uPal) gl.uniform3fv(p.uniforms.uPal, this.palette);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      gl.bindTexture(gl.TEXTURE_2D, this.sceneTex);
      gl.generateMipmap(gl.TEXTURE_2D);

      // Composite (feedback loop)
      const c = this.comp;
      gl.useProgram(c.prog);
      gl.bindFramebuffer(gl.FRAMEBUFFER, outFbo);
      this.setTex(c, "uScene", 3, this.sceneTex);
      this.setTex(c, "uPrev", 0, prevTex);
      this.setTex(c, "uVideo", 1, this.videoTex);
      s(c, "uRes", iw, ih);
      s(c, "uTime", st.time);
      s(c, "uFeedback", P.v("feedback"));
      s(c, "uFbZoom", P.v("fb_zoom"));
      s(c, "uFbRot", P.v("fb_rotate"));
      s(c, "uFbHue", P.v("fb_hue"));
      s(c, "uKaleido", P.v("kaleido"));
      s(c, "uWarp", P.v("warp"));
      s(c, "uChroma", P.v("chroma"));
      s(c, "uGlow", P.v("glow"));
      s(c, "uExposure", this.exposure);
      s(c, "uTransition", st.transition || 0);
      s(c, "uVideoMix", P.v("video_mix"));
      s(c, "uVideoOn", videoOn);
      s(c, "uVideo360", v360);
      s(c, "uCamView", P.v("cam_view"));
      s(c, "uCamYaw", st.camYaw);
      s(c, "uBeat", beat);
      s(c, "uBass", bass);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      this.meter(1 - this.cur);

      // Display
      const d = this.disp;
      gl.useProgram(d.prog);
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      gl.viewport(0, 0, this.screenSize[0], this.screenSize[1]);
      this.setTex(d, "uComp", 0, outTex);
      s(d, "uHue", P.v("hue"));
      s(d, "uSat", P.v("saturation"));
      s(d, "uBright", P.v("brightness"));
      s(d, "uContrast", P.v("contrast"));
      s(d, "uInvert", P.v("invert"));
      s(d, "uStrobe", P.v("strobe"));
      s(d, "uBeat", audio.beat);
      s(d, "uFlash", st.flash);
      s(d, "uBlackout", st.blackout);
      s(d, "uTime", st.realTime);
      gl.drawArrays(gl.TRIANGLES, 0, 3);

      this.cur = 1 - this.cur;
    }
  }

  Prism.Engine = Engine;
  Prism.parsePreset = parsePreset;
})();
