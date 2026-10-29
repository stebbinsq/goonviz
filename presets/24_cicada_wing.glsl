// @preset {"name": "Cicada Wing", "labels": {"a": "wing spread", "b": "vein density", "c": "iridescence", "d": "color"}, "params": {"palette": 9, "glow": 0.5, "feedback": 0.3, "chroma": 0.2}}
// A cicada seen from above: mirrored translucent fore and hind wings with amber veins, a lattice of
// cells, and thin-film iridescence that shifts as the wings flutter on the beat. Spores drift behind.

// Signed distance to a tapered wing outline (wing runs along +x from the root at the origin).
float wingShape(vec2 w, float len, float width) {
    float x = w.x / len;
    float hw = width * sqrt(max(0.0, x * (1.0 - x))) * (1.15 - 0.45 * x);  // broad near root, narrow tip
    return max(abs(w.y - 0.08 * width * sin(x * 3.14)) - hw, max(-w.x, w.x - len));
}

vec2 cellEdges(vec2 x) {
    // Voronoi F2-F1 (cell edge distance) and the cell's id hash
    vec2 n = floor(x), f = fract(x);
    float md = 8.0, md2 = 8.0;
    vec2 mid = vec2(0.0);
    for (int j = -1; j <= 1; j++)
    for (int i = -1; i <= 1; i++) {
        vec2 g = vec2(float(i), float(j));
        vec2 o = 0.5 + 0.35 * sin(TAU * hash22(n + g));
        vec2 r = g + o - f;
        float d = dot(r, r);
        if (d < md) { md2 = md; md = d; mid = n + g; } else if (d < md2) md2 = d;
    }
    return vec2(sqrt(md2) - sqrt(md), hash12(mid));
}

vec3 wing(vec2 w, float len, float width, float px, float seed) {
    float d = wingShape(w, len, width);
    if (d > 0.08) return vec3(0.0);
    float inside = smoothstep(px, -px, d);
    float x = clamp(w.x / len, 0.0, 1.0);
    float hw = max(width * sqrt(max(0.0, x * (1.0 - x))) * (1.15 - 0.45 * x), 1e-3);
    float v = (w.y - 0.08 * width * sin(x * 3.14)) / hw;     // -1..1 across the wing

    // longitudinal veins (follow the wing's curve) and the leading-edge vein
    float nv = 4.0 + floor(uB * 6.0);
    float lv = abs(fract(v * nv * 0.5 + 0.5) - 0.5) * 2.0 * hw / nv;
    float edge = abs(d);
    // cross veins: stretched cells
    vec2 ce = cellEdges(vec2(x * (10.0 + uB * 14.0), v * 2.2) + seed);
    float cross = ce.x * len / (10.0 + uB * 14.0);

    vec3 amber = glowpal(0.62 + uD);
    vec3 col = vec3(0.0);
    col += amber * px / (lv + px) * 0.9 * inside * smoothstep(0.0, 0.08, x);
    col += amber * px * 1.5 / (cross + px * 1.5) * 0.7 * inside;
    col += glowpal(0.6 + uD) * px * 2.0 / (edge + px * 2.0) * 1.2;              // outline
    // membrane: thin-film colour that shifts across the wing and over time
    float film = v * 0.35 + x * 0.6 + ce.y * 0.15 + uTime * 0.04 + uBeat * 0.1;
    col += glowpal(film + uD) * inside * (0.06 + 0.22 * uC) * (0.6 + 0.4 * sin(x * 9.0 + v * 4.0 + uTime));
    col += uPal[1] * inside * 0.12;
    return col;
}

vec3 scene(vec2 p, vec2 uv) {
    vec2 sp0 = p;
    p = p * 0.62 + vec2(0.0, 0.1);                               // frame the insect large
    vec2 q = vec2(abs(p.x), p.y);                               // bilateral symmetry
    float px = fwidth(p.x) * 1.3;  // (p is already scaled, so lines stay one pixel wide)
    float flutter = sin(uTime * 2.0) * 0.03 + uBeat * 0.06;
    float spread = -0.15 + uA * 0.45;                           // wings swept back like a resting cicada, A opens them
    vec3 col = vec3(0.0);

    // drifting spores in the dark
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        vec2 sp = sp0 * (3.0 + fi * 2.0) + vec2(uTime * 0.05 * (fi + 1.0), -uTime * 0.08);
        vec2 id = floor(sp), f = fract(sp) - 0.5;
        vec2 h = hash22(id + fi * 13.0);
        float d = length(f - (h - 0.5) * 0.7);
        col += glowpal(h.x + uD + 0.3) * 0.0008 / (d * d + 0.0008) * step(0.82, h.y) * (0.4 + 0.3 * fi);
    }

    // hind wing, then fore wing on top
    vec2 root = vec2(0.06, 0.12);
    vec2 hwing = rot(-(spread * 0.6 + 0.35) - flutter * 0.7) * (q - root - vec2(0.0, -0.06));
    col += wing(hwing, 0.75, 0.42, px, 3.0) * 0.8;
    vec2 fw = rot(-(spread + 0.08) - flutter) * (q - root);
    col = max(col, wing(fw, 1.15, 0.38, px, 0.0));

    // body: thorax, segmented abdomen, glowing eyes
    vec2 b = p - vec2(0.0, 0.02);
    float thorax = length(b * vec2(1.6, 1.0)) - 0.13;
    float abdomen = length((b - vec2(0.0, -0.32)) * vec2(1.8, 0.7)) - 0.14;
    float body = min(thorax, abdomen);
    float seg = abs(fract((b.y + 0.18) * 14.0) - 0.5) * step(b.y, -0.15);
    col = mix(col, uPal[1] * 0.5 + glowpal(0.3 + uD) * 0.12, smoothstep(px, -px, body));
    col += glowpal(0.62 + uD) * px / (abs(body) + px) * 0.9;
    col += glowpal(0.62 + uD) * (1.0 - smoothstep(0.0, 0.06, seg)) * 0.25 * smoothstep(px, -px, abdomen);
    vec2 e = vec2(abs(p.x) - 0.085, p.y - 0.14);
    col += glowpal(0.9 + uD) * 0.0012 / (dot(e, e) + 0.0012) * (0.6 + uBass);
    return col;
}
