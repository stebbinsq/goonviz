// @preset {"name": "Flower of Life", "labels": {"a": "scale", "b": "second layer", "c": "line width", "d": "color"}, "params": {"palette": 3, "glow": 0.6, "feedback": 0.5, "fb_zoom": -0.15, "fb_rotate": 0.1}}
// Overlapping circles on a hex lattice (two counter-rotating layers), lit from the centre.

float flowerLines(vec2 g, float w) {
    // g in lattice units; circles of radius 1 centred on every hex lattice point
    float j0 = floor(g.y / 0.8660254);
    float i0 = floor(g.x - j0 * 0.5);
    float acc = 0.0;
    for (int dj = -2; dj <= 2; dj++) {
        for (int di = -2; di <= 2; di++) {
            float j = j0 + float(dj);
            float i = i0 + float(di);
            vec2 c = vec2(i + j * 0.5, j * 0.8660254);
            float d = abs(length(g - c) - 1.0);
            acc += w / (d + w * 1.5);
        }
    }
    return acc;
}

vec3 scene(vec2 p, vec2 uv) {
    float r = length(p);
    float sc = 0.18 + uA * 0.25 + uBass * 0.02;
    float w = 0.006 + uC * 0.02;
    vec2 g1 = rot(uTime * 0.05) * p / sc;
    vec2 g2 = rot(-uTime * 0.07 + 0.5236) * p / (sc * 1.7320508);
    float l1 = flowerLines(g1, w);
    float l2 = flowerLines(g2, w) * uB;

    float fall = exp(-r * (1.6 - uLevel * 0.6));           // light from the centre
    vec3 col = glowpal(r * 0.6 - uTime * 0.05 + uD) * l1 * fall * 0.35;
    col += glowpal(r * 0.6 + 0.5 + uD) * l2 * fall * 0.3;

    // the seed: inner rings pulse on the beat
    col += glowpal(uD + 0.2) * 0.004 / (abs(r - sc) + 0.004) * (0.4 + uBeat);
    col += uPal[1] * 0.25 * fall;
    return col;
}
