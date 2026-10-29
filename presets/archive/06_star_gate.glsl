// @preset {"name": "Star Gate", "labels": {"a": "star density", "b": "gate rings", "c": "ring spacing", "d": "color"}, "params": {"palette": 4, "glow": 0.6, "feedback": 0.82, "fb_zoom": 0.7, "chroma": 0.35, "speed": 1.2}}
// Hyperspace: layers of stars rushing past, through ringed log-space portals. Feedback zoom = light streaks.

vec3 scene(vec2 p, vec2 uv) {
    vec3 col = vec3(0.0);
    float t = uPulse * 0.25;
    p = rot(uTime * 0.04) * p;
    float density = 8.0 + uA * 24.0;

    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float depth = fract(fi / 5.0 + t);
        float scale = mix(density, 0.5, depth);
        float fade = depth * smoothstep(1.0, 0.8, depth);
        vec2 q = p * scale + fi * 17.3;
        vec2 id = floor(q);
        vec2 gv = fract(q) - 0.5;
        vec2 h = hash22(id + fi * 31.0);
        float d = length(gv - (h - 0.5) * 0.7);
        float star = 0.0025 / (d * d + 0.0025) * step(0.55, h.x) * smoothstep(0.5, 0.2, d);
        col += glowpal(h.y + uD + fi * 0.1) * star * fade;
    }

    float r = length(p);
    float v = log(r) * (2.0 + uC * 4.0) - t * 4.0;
    float iso = abs(fract(v) - 0.5) / max(fwidth(v), 1e-4);
    float rings = 1.0 / (1.0 + iso * iso * 0.5);
    float a = atan(p.y, p.x);
    float lace = 0.6 + 0.4 * cos(a * 12.0 + v * 2.0);
    col += glowpal(floor(v) * 0.17 + uD) * rings * lace * uB * smoothstep(0.05, 0.4, r) * (0.6 + uBeat);
    col += glowpal(uD + 0.3) * 0.006 / (r + 0.01) * (0.5 + uBass);
    return col;
}
