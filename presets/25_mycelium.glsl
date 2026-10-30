// @preset {"energy": 1, "family": "organic", "name": "Mycelium", "labels": {"a": "network scale", "b": "thread sharpness", "c": "pulse speed", "d": "color"}, "params": {"palette": 8, "glow": 0.6, "feedback": 0.45, "fb_zoom": 0.08, "warp": 0.08}}
// A living fungal network: ridged noise draws branching threads, and pulses of light travel along them
// with the music. Fruiting nodes swell on the beat.

float ridge(vec2 p) {
    float v = 0.0, a = 0.55, sharp = 3.0 + uB * 6.0;
    mat2 m = mat2(1.7, 1.1, -1.1, 1.7);
    for (int i = 0; i < 4; i++) {
        float n = 1.0 - abs(noise(p) * 2.0 - 1.0);   // creases of the noise become threads
        v += a * pow(n, sharp);
        p = m * p;
        a *= 0.5;
    }
    return v;
}

vec3 scene(vec2 p, vec2 uv) {
    float sc = 1.6 + uA * 2.5;
    float t = uTime * 0.05;
    vec2 q = p * sc;
    q += 0.6 * vec2(fbm(q * 0.4 + t), fbm(q * 0.4 - t + 3.3));       // organic wander
    float threads = ridge(q + vec2(t * 2.0, 0.0));
    float fine = ridge(q * 2.3 + 11.0);

    // pulses: a travelling wave along a slow field, gated onto the threads
    float phase = fbm(q * 0.3) * 8.0 - uPulse * (0.6 + uC * 2.4);
    float pulse = pow(0.5 + 0.5 * sin(phase * TAU), 12.0);

    vec3 col = uPal[0];
    col += glowpal(0.2 + uD + fbm(q * 0.2) * 0.4) * threads * 0.55;
    col += glowpal(0.45 + uD) * fine * 0.18;
    col += glowpal(0.6 + uD) * threads * pulse * (0.8 + uBass * 1.5);

    // fruiting nodes: bright knots where threads are densest
    vec2 cell = q * 0.7;
    vec2 id = floor(cell), f = fract(cell) - 0.5;
    vec2 h = hash22(id);
    float node = length(f - (h - 0.5) * 0.6);
    float size = 0.05 + 0.04 * uBeat * step(0.5, h.x);
    col += glowpal(h.y * 0.4 + 0.5 + uD) * size * size / (node * node + size * size * 0.6) * 0.6 * step(0.55, h.y);
    return col;
}
