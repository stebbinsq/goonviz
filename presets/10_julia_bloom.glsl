// @preset {"energy": 1, "family": "fractal2d", "name": "Julia Bloom", "labels": {"a": "seed angle", "b": "morph speed", "c": "detail", "d": "color"}, "params": {"palette": 2, "glow": 0.5, "feedback": 0.35, "fb_rotate": 0.1, "a": 0.55}}
// Julia set whose seed orbits the Mandelbrot boundary (where all the lacy spirals live),
// coloured by smooth escape time and orbit traps.

vec3 scene(vec2 p, vec2 uv) {
    float ang = uA * TAU + uTime * (0.01 + uB * 0.05);
    vec2 c = 0.7885 * vec2(cos(ang), sin(ang)) * (1.0 - uBass * 0.01);
    vec2 z = rot(uTime * 0.02) * p * 0.9;
    float trap = 1e3, trap2 = 1e3, it = 0.0;
    float maxit = 40.0 + uC * 56.0;
    for (int i = 0; i < 96; i++) {
        if (float(i) >= maxit) break;
        z = vec2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
        trap = min(trap, abs(length(z) - 0.6));
        trap2 = min(trap2, abs(z.x * z.y));
        if (dot(z, z) > 64.0) break;
        it += 1.0;
    }
    vec3 col = uPal[0];
    if (it < maxit) {
        float sm = it - log2(log2(dot(z, z))) + 4.0;
        float edge = smoothstep(2.0, maxit * 0.5, sm);
        col += pal(sm * 0.04 + uD + uTime * 0.02) * (0.02 + 0.7 * edge * edge);  // dark far away, glowing near the set
        col += glowpal(trap * 2.0 + uD) * 0.003 / (trap + 0.01) * (0.3 + edge);
        col += glowpal(trap2 + uD + 0.4) * 0.001 / (trap2 + 0.006) * edge * (0.4 + uHigh);
    }
    return col * (0.85 + uBeat * 0.35);
}
