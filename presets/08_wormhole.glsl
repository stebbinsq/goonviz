// @preset {"energy": 3, "family": "tunnel", "name": "Wormhole", "labels": {"a": "twist", "b": "segments", "c": "ornament", "d": "color"}, "params": {"palette": 7, "glow": 0.5, "feedback": 0.5, "fb_zoom": 0.4, "chroma": 0.3}}
// Infinite tunnel whose walls are tiled with glowing rosette ornaments.

vec3 scene(vec2 p, vec2 uv) {
    float r = length(p);
    float a = atan(p.y, p.x);
    float z = 0.35 / (r + 0.01) + uPulse * 0.6;
    float tw = (uA - 0.5) * 2.0;
    float segs = floor(4.0 + uB * 8.0);
    vec2 tc = vec2((a + tw * z * 0.3 + uTime * 0.05) * segs / TAU, z * 1.5);
    vec2 cell = fract(tc) - 0.5;
    vec2 id = floor(tc);

    vec2 k = abs(cell);
    float d1 = abs(length(k - 0.5) - 0.35);
    float d2 = abs(length(k) - 0.22 - 0.05 * uBass);
    float d3 = abs(k.x + k.y - 0.5) + 0.15 * (1.0 - uC);
    float d = min(min(d1, d2), d3);

    // pixel footprint in tile units (atan seam safe)
    float fw = max(fwidth(p.x) * segs / (TAU * max(r, 1e-3)), fwidth(z) * 1.5);
    float lines = 1.4 * fw / (d + fw) + 0.35 * exp(-d * 18.0);

    vec3 col = glowpal(id.y * 0.07 + uD + floor(cell.x + 0.5) * 0.1) * lines;
    col *= smoothstep(0.0, 0.35, r) * (0.7 + uBass * 0.6);
    col += glowpal(uD + 0.5) * 0.012 / (r + 0.012) * (0.5 + uBeat);
    return col;
}
