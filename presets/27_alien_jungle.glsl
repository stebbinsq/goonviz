// @preset {"energy": 1, "family": "organic", "name": "Alien Jungle", "labels": {"a": "leaf size", "b": "sway", "c": "fireflies", "d": "color"}, "params": {"palette": 8, "glow": 0.6, "feedback": 0.3, "chroma": 0.15}}
// Three depths of glowing alien leaves: pointed blades with a midrib and chevron side veins, swaying,
// lit along their edges, with fireflies hanging in the haze between the layers.

// One layer of scattered leaves. Returns colour in rgb and coverage in a.
vec4 leaves(vec2 p, float depth, float px) {
    float cs = 0.55 + uA * 0.5 - depth * 0.15;            // cell size: nearer layers have bigger leaves
    vec2 q = p / cs + vec2(uTime * 0.03 * (1.0 + depth), depth * 5.7);
    vec2 n = floor(q);
    vec4 best = vec4(0.0);
    float bestD = 1e3;
    for (int j = -1; j <= 1; j++)
    for (int i = -1; i <= 1; i++) {
        vec2 id = n + vec2(float(i), float(j));
        vec2 h = hash22(id + depth * 17.0);
        if (h.x < 0.25) continue;                          // some cells stay empty: gaps to see through
        vec2 origin = id + h * 0.8;
        float ang = h.y * TAU + sin(uTime * (0.4 + h.x) + h.y * 9.0) * (0.1 + uB * 0.3);
        float len = 0.9 + h.x * 0.7;
        vec2 l = rot(-ang) * (q - origin);                 // leaf runs along +x from its stem
        float x = l.x / len;
        float w = 0.24 * pow(max(0.0, sin(PI * clamp(x, 0.0, 1.0))), 0.8) * (1.0 - 0.3 * x);
        float d = max(abs(l.y) - w, max(-l.x, l.x - len));
        if (d < bestD) {
            bestD = d;
            float inside = smoothstep(px, -px, d * cs);
            float rib = abs(l.y);
            float veinsC = abs(fract((x - abs(l.y) * 1.6) * 9.0) - 0.5) / 9.0;   // chevron side veins
            vec3 c = glowpal(h.x * 0.25 + depth * 0.15 + uD);
            vec3 col = uPal[1] * (0.25 + 0.2 * depth) + c * 0.08;
            col += c * px / (rib * cs + px) * 0.7;
            col += c * px / (veinsC * cs + px) * 0.35 * smoothstep(0.0, 0.1, x);
            col *= inside;
            col += glowpal(0.62 + uD) * px * 2.0 / (abs(d) * cs + px * 2.0) * 0.8;   // glowing edge
            best = vec4(col, inside);
        }
    }
    return best;
}

vec3 scene(vec2 p, vec2 uv) {
    float px = fwidth(p.x) * 1.2;
    vec3 col = uPal[0] + uPal[1] * 0.1 * (1.0 - uv.y);     // haze, brighter near the floor
    for (int i = 0; i < 3; i++) {
        float depth = float(i) / 2.0;                      // 0 = far, 1 = near
        vec4 lf = leaves(p * (1.0 + depth * 0.4), depth, px);
        float fog = 0.45 + 0.55 * depth;                   // far layers sink into the haze
        col = mix(col, lf.rgb * fog, lf.a * (0.7 + 0.3 * depth)) + lf.rgb * (1.0 - lf.a) * fog;
        // fireflies in front of this layer
        vec2 ff = p * (2.0 + depth * 2.0) + vec2(uTime * 0.03, sin(uTime * 0.2 + depth) * 0.2);
        vec2 id = floor(ff), f = fract(ff) - 0.5;
        vec2 h = hash22(id + depth * 31.0);
        vec2 o = (h - 0.5) * 0.6 + 0.1 * vec2(sin(uTime * (1.0 + h.x) + h.y * 6.0), cos(uTime * (1.3 + h.y)));
        float d = length(f - o);
        float blink = 0.5 + 0.5 * sin(uTime * (2.0 + h.x * 3.0) + h.y * 20.0);
        col += glowpal(0.62 + uD) * 0.0006 / (d * d + 0.0006) * step(0.72, h.y) * blink * uC * 1.6 * (0.7 + uHigh);
    }
    return col * (0.9 + uBeat * 0.2);
}
