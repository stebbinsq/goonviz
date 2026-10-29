// @preset {"name": "Spirit Mirror (video)", "labels": {"a": "edge gain", "b": "aura", "c": "body fill", "d": "color"}, "params": {"palette": 2, "glow": 0.7, "feedback": 0.75, "fb_zoom": 0.2, "fb_hue": 0.1, "kaleido": 0}}
// The camera image traced as a glowing energy body: neon edges, a palette-mapped aura, feedback trails.
// No camera? It processes its own feedback instead.

vec3 scene(vec2 p, vec2 uv) {
    vec2 px = 1.5 / uRes;
    float tl = luma(video(uv + vec2(-px.x, px.y)));
    float tc = luma(video(uv + vec2(0.0, px.y)));
    float tr = luma(video(uv + px));
    float ml = luma(video(uv - vec2(px.x, 0.0)));
    float mr = luma(video(uv + vec2(px.x, 0.0)));
    float bl = luma(video(uv - px));
    float bc = luma(video(uv - vec2(0.0, px.y)));
    float br = luma(video(uv + vec2(px.x, -px.y)));
    float gx = -tl - 2.0 * ml - bl + tr + 2.0 * mr + br;
    float gy = -tl - 2.0 * tc - tr + bl + 2.0 * bc + br;
    float edge = sqrt(gx * gx + gy * gy) * (1.0 + uA * 4.0);

    float lum = luma(video(uv));
    vec3 col = glowpal(lum * 1.5 + uTime * 0.05 + uD) * edge;
    col += pal(lum + uD + 0.3) * lum * uC * 0.6;                       // gradient-mapped body
    float n = fbm(p * 3.0 + vec2(0.0, -uTime * 0.4));
    col += glowpal(n + uD + 0.6) * smoothstep(0.1, 0.6, edge) * n * uB;   // flickering aura
    return col * (0.9 + uBeat * 0.4);
}
