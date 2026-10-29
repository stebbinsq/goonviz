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
      for (const p of this.presets) this.compilePreset(p);
      if (!this.presets.some((p) => p.program)) throw new Error("no presets compiled; see console");

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

    program(frag) {
      const gl = this.gl;
      const prog = gl.createProgram();
      gl.attachShader(prog, this.shader(gl.VERTEX_SHADER, HEADER + VERT));
      gl.attachShader(prog, this.shader(gl.FRAGMENT_SHADER, HEADER + frag));
      gl.bindAttribLocation(prog, 0, "in_pos");
      gl.linkProgram(prog);
      if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(prog));
      const uniforms = {};
      const n = gl.getProgramParameter(prog, gl.ACTIVE_UNIFORMS);
      for (let i = 0; i < n; i++) {
        const info = gl.getActiveUniform(prog, i);
        const name = info.name.replace(/\[0\]$/, "");
        uniforms[name] = gl.getUniformLocation(prog, info.name);
      }
      return { prog, uniforms };
    }

    compilePreset(preset) {
      const S = this.data.shaders;
      try {
        preset.program = this.program(S.lib + S.scene_header + preset.source + SCENE_MAIN);
        preset.error = null;
      } catch (e) {
        preset.error = String(e.message || e);
        console.error(`[preset] ${preset.key} failed to compile:\n${preset.error}`);
      }
      return !preset.error;
    }

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
      this.internal = [iw, ih];
      for (const t of this._owned || []) (t instanceof WebGLTexture ? gl.deleteTexture(t) : gl.deleteFramebuffer(t));
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

    // Same as Engine._meter in prism/engine.py: measure the composited frame's average brightness;
    // above a mean luma of 0.32 step the exposure down, below it creep back up to 1 (never brighter).
    meter(i) {
      if (!this.autoExposure) { this.exposure = 1; return; }
      if (++this.frameNo % 6) return;
      const gl = this.gl;
      gl.bindTexture(gl.TEXTURE_2D, this.compTex[i]);
      gl.generateMipmap(gl.TEXTURE_2D);
      gl.bindFramebuffer(gl.READ_FRAMEBUFFER, this.meterFbo[i]);
      gl.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, this.meterPx);
      gl.bindFramebuffer(gl.READ_FRAMEBUFFER, null);
      const [r, g, b] = this.meterPx;
      const mean = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
      this.exposure *= mean > 0.32 ? Math.pow(0.32 / mean, 0.35) : 1.04;
      this.exposure = Math.min(1, Math.max(0.35, this.exposure));
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
