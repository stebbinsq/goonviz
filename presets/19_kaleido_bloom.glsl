// @preset {"energy": 2, "family": "mandala", "name": "Kaleido Bloom", "labels": {"a": "petals", "b": "layers", "c": "inner detail", "d": "color"}, "params": {"palette": 0, "glow": 0.55, "feedback": 0.4, "fb_zoom": 0.15, "a": 0.4, "b": 0.7, "c": 0.6}}
// Layer upon layer of counter-rotating petal rings, each petal holding its own smaller rosette.

vec3 rosette(vec2 q, float n, float w, vec3 c1, vec3 c2) {
    // a little mandala in local coords (radius ~1)
    vec2 k = kaleido(q, n);
    float petal = abs(length((k - vec2(0.55, 0.0)) * vec2(1.0, 2.2)) - 0.3);
    float ring = abs(length(k) - 0.28);
    float ring2 = abs(length(k) - 0.92);
    float dot1 = length(k - vec2(0.92, 0.0));
    return c1 * w / (petal + w) + c2 * w / (ring + w) * 0.7 + c2 * w / (ring2 + w) * 0.4
         + c1 * 0.25 * w * w / (dot1 * dot1 + w * w * 2.0);
}

vec3 scene(vec2 p, vec2 uv) {
    float r = length(p);
    float a = atan(p.y, p.x);
    float n = floor(6.0 + uA * 8.0);
    float layers = 3.0 + floor(uB * 4.0);
    float px = fwidth(p.x) * 1.3;
    vec3 col = vec3(0.0);

    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        if (fi >= layers) break;
        float dir = mod(fi, 2.0) * 2.0 - 1.0;
        float R = 0.2 + fi * 0.19 + 0.015 * sin(uTime * 0.6 + fi) + uBass * 0.02 * (fi + 1.0);
        float k = n * (1.0 + floor(fi * 0.5));              // outer layers carry more petals
        float seg = TAU / k;
        float aa = a + dir * uTime * 0.08 / (1.0 + fi * 0.4) + fi * 0.3;
        float cellA = mod(aa, seg) - seg * 0.5;
        // local frame of the petal under this pixel
        vec2 lp = vec2(r - R, cellA * R);
        float size = R * seg * 0.42;
        vec2 q = rot(uTime * 0.2 * dir) * (lp / size);
        vec3 c1 = glowpal(fi * 0.17 + uD + uTime * 0.015);
        vec3 c2 = glowpal(fi * 0.17 + uD + 0.5);
        float wl = px / size;
        // the petal outline itself, then the rosette inside it
        float outline = abs(length(lp / size * vec2(0.8, 1.0)) - 1.0) * size;
        col += c1 * px / (outline + px) * 0.55;
        col += rosette(q, 6.0, wl, c2, c1) * uC * 0.45 * smoothstep(1.15, 0.9, length(lp / size));
        // ring the layer sits on
        col += c2 * px / (abs(r - R) + px) * 0.25;
    }
    col += glowpal(uD + 0.15) * 0.007 / (r + 0.012) * (0.5 + uBeat);
    col += uPal[1] * 0.1 * exp(-r * 1.4);
    return col;
}
