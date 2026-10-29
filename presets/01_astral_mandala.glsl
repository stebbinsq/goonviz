// @preset {"name": "Astral Mandala", "labels": {"a": "petals", "b": "layers", "c": "filigree", "d": "color drift"}, "params": {"palette": 0, "glow": 0.55, "feedback": 0.45, "fb_zoom": 0.2, "a": 0.4, "b": 0.7}}
// Concentric scalloped rings of glowing filigree, counter-rotating, with beads of light.

vec3 scene(vec2 p, vec2 uv) {
    float r = length(p);
    float a = atan(p.y, p.x);
    float n = floor(6.0 + uA * 12.0);
    float layers = 3.0 + floor(uB * 5.0);
    vec3 col = vec3(0.0);

    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        if (fi >= layers) break;
        float dir = mod(fi, 2.0) * 2.0 - 1.0;
        float r0 = 0.14 + fi * 0.15 + 0.02 * sin(uTime * 0.7 + fi) + uBass * 0.03 * (fi + 1.0);
        float k = n * (1.0 + mod(fi, 3.0));                 // outer rings get more petals
        float aa = a * k * 0.5 + dir * uTime * 0.12 / (1.0 + fi * 0.3);
        float shape = r0 * (0.84 + 0.16 * abs(cos(aa)));
        float d = abs(r - shape);
        vec3 c1 = glowpal(fi * 0.17 + uD + uTime * 0.02);
        vec3 c2 = glowpal(fi * 0.17 + uD + 0.45);

        col += c1 * 0.0018 / (d + 0.003);
        // inner echo of the scallop, fainter
        col += c1 * 0.0007 / (abs(r - shape * 0.93) + 0.003);

        // filigree spokes inside each band
        float band = smoothstep(0.07, 0.0, abs(r - shape * 0.96));
        float spokes = pow(abs(cos(a * k + dir * uTime * 0.2 + fi)), 30.0 + 60.0 * uC);
        col += c2 * spokes * band * 0.5;

        // beads of light riding the ring
        float seg = TAU / k;
        float ba = mod(a + dir * uTime * 0.05 + fi, seg) - seg * 0.5;
        vec2 bp = vec2(ba * r, r - shape * 1.06);
        col += c2 * 0.00004 / (dot(bp, bp) + 0.00003) * (0.6 + uHigh);
    }

    // central sun
    col += glowpal(uTime * 0.05 + uD) * 0.012 / (r + 0.012) * (0.6 + uBeat);
    // star dust haze in the void
    col += uPal[1] * pow(fbm(p * 2.5 + uTime * 0.03), 3.0) * 0.6 * smoothstep(0.3, 1.4, r);
    return col;
}
