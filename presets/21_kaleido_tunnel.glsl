// @preset {"name": "Kaleido Tunnel", "labels": {"a": "segments", "b": "rings per depth", "c": "ornament", "d": "color"}, "params": {"palette": 7, "glow": 0.55, "feedback": 0.45, "fb_zoom": 0.35, "chroma": 0.3, "speed": 1.1}}
// Endless rings of ornate kaleidoscopic tiles stream toward you. Log-polar space makes every ring a
// scaled copy of the last, so the tunnel is self-similar at every depth.

vec3 scene(vec2 p, vec2 uv) {
    float r = length(p);
    float a = atan(p.y, p.x);
    float segs = floor(6.0 + uA * 10.0);
    float rings = 1.0 + uB * 2.0;
    float t = uPulse * 0.35;
    vec2 tc = vec2(a * segs / TAU + t * 0.2, log(max(r, 1e-4)) * segs / TAU * rings - t);
    vec2 id = floor(tc);
    vec2 cell = fract(tc) - 0.5;

    // each tile is its own little 8-fold rosette, rotating with its ring
    vec2 k = kaleido(rot(id.y * 0.7 + uTime * 0.3) * cell, 8.0);
    float d1 = abs(length(k - vec2(0.25, 0.0)) - 0.12);
    float d2 = abs(length(k) - 0.36);
    float d3 = abs(k.y - 0.08 * sin(k.x * 30.0 + uTime)) + max(0.0, length(k) - 0.3);
    float d4 = abs(length(k - vec2(0.42, 0.0)) - 0.04);
    float d = min(min(d1, d2 + 0.02 * (1.0 - uC)), min(d3 + 0.04 * (1.0 - uC), d4));

    float fw = max(fwidth(p.x) * segs / (TAU * max(r, 1e-3)) * rings, 1e-3) * 1.4;
    float lines = fw / (d + fw) + 0.12 * exp(-d * 30.0);
    vec3 col = glowpal(id.y * 0.09 + uD + mod(id.x, 2.0) * 0.12) * lines;
    col += glowpal(id.y * 0.09 + uD + 0.5) * 0.0003 / (dot(k, k) + 0.0008) * (0.5 + uHigh);
    col *= smoothstep(0.0, 0.3, r) * (0.75 + uBass * 0.5);
    col += glowpal(uD + 0.4) * 0.012 / (r + 0.012) * (0.5 + uBeat);
    return col;
}
