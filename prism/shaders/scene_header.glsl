// Uniforms and helpers available to every preset. A preset only has to define:
//
//     vec3 scene(vec2 p, vec2 uv)
//
// p  = centered, aspect-corrected coords (y runs -1..1, already divided by zoom)
// uv = 0..1 screen coords

uniform vec2 uRes;
uniform float uTime;      // time scaled by the speed knob
uniform float uPulse;     // like uTime but surges forward on bass hits
uniform float uRealTime;  // wall-clock seconds
uniform float uA, uB, uC, uD;   // the four preset knobs
uniform float uZoom;
uniform float uBass, uMid, uHigh, uLevel;  // 0..1, already scaled by the react knob
uniform float uBeat;      // 1.0 on a detected beat, decays to 0
uniform float uBeatCount; // increments every beat
uniform float uVideoOn;
uniform float uVideo360;  // 1.0 when the source is a 360 camera (equirectangular)
uniform float uCamView;   // 360 projection mode, see project360()
uniform float uCamYaw;    // 360 look direction, radians
uniform sampler2D uPrev;  // last composited frame (for feedback tricks)
uniform sampler2D uVideo; // live video input (channel order set by VIDEO_SWIZZLE)
uniform sampler2D uFFT;   // 128-bin log spectrum in .r
uniform vec3 uPal[5];     // current palette (5 colour stops, cyclic, darkest first)

in vec2 vUV;
out vec4 fragColor;

// Spectrum lookup, x = 0 (bass) .. 1 (treble).
float fft(float x) {
    return texture(uFFT, vec2(clamp(x, 0.0, 1.0), 0.5)).r;
}

// Live video. With no camera connected this falls back to the feedback buffer,
// so video presets still do something interesting.
vec3 video(vec2 uv) {
    uv = mirrorUV(uv);
    if (uVideoOn < 0.5) return texture(uPrev, uv).rgb;
    if (uVideo360 > 0.5) uv = project360(uv, uRes.x / uRes.y, uCamView, uCamYaw);
    return texture(uVideo, vec2(uv.x, 1.0 - uv.y)).VIDEO_SWIZZLE;
}

// Sample the active palette. t wraps, so pal(t + time) cycles smoothly.
// Stop 0 is the dark "void" colour; higher stops are the luminous ones.
vec3 pal(float t) {
    float x = fract(t) * 5.0;
    int i = int(floor(x));
    float f = smoothstep(0.0, 1.0, fract(x));
    return mix(uPal[i], uPal[int(mod(float(i + 1), 5.0))], f);
}

// Palette skipping the dark stop: always a bright, glowing colour.
vec3 glowpal(float t) {
    float x = fract(t) * 4.0;
    int i = int(floor(x));
    float f = smoothstep(0.0, 1.0, fract(x));
    return mix(uPal[1 + i], uPal[1 + int(mod(float(i + 1), 4.0))], f);
}

vec3 prev(vec2 uv) {
    return texture(uPrev, mirrorUV(uv)).rgb;
}
