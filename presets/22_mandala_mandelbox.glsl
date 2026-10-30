// @preset {"energy": 2, "family": "fractal2d", "name": "Mandala Mandelbox", "labels": {"a": "fold scale", "b": "symmetry", "c": "detail", "d": "color"}, "params": {"palette": 3, "glow": 0.5, "feedback": 0.3, "a": 0.5, "b": 0.5}}
// A 2D Mandelbox (box fold + sphere fold + scale) behind a kaleidoscope: dense jewelled filigree
// coloured by orbit traps.

vec3 scene(vec2 p, vec2 uv) {
    float sym = 4.0 + floor(uB * 3.0) * 2.0;
    vec2 c = kaleido(rot(uTime * 0.03) * p * 1.6, sym);
    c += 0.08 * vec2(sin(uTime * 0.11), cos(uTime * 0.13));
    float scale = -1.6 - uA * 0.8 + 0.05 * sin(uTime * 0.2) + uBass * 0.03;
    vec2 z = c;
    float dr = 1.0;
    float trapR = 1e3, trapX = 1e3, trapC = 1e3;
    int iters = 6 + int(uC * 6.0);
    for (int i = 0; i < 12; i++) {
        if (i >= iters) break;
        z = clamp(z, -1.0, 1.0) * 2.0 - z;                  // box fold
        float r2 = dot(z, z);
        if (r2 < 0.25) { z *= 4.0; dr *= 4.0; }             // sphere fold
        else if (r2 < 1.0) { z /= r2; dr /= r2; }
        z = z * scale + c;
        dr = dr * abs(scale) + 1.0;
        trapR = min(trapR, abs(length(z) - 1.0));
        trapX = min(trapX, abs(z.x * z.y));
        trapC = min(trapC, length(z - vec2(0.5, 0.0)));
    }
    float dist = length(z) / abs(dr);
    float px = fwidth(p.x) * 1.6;
    float inside = smoothstep(px * 1.5, px * 0.3, dist);     // deep inside the set: dist collapses to ~0
    // glowing shell around the set, fading outward
    vec3 col = glowpal(trapC * 0.4 + uD + uTime * 0.02) * px / (abs(dist - px * 2.0) + px) * (1.0 - inside) * 0.9;
    col += glowpal(trapC * 0.4 + uD + 0.2) * 0.0015 / (dist + 0.01) * (1.0 - inside) * 0.3;
    // inside: fine orbit-trap filigree on darkness
    float iw = px * 2.0;
    col += glowpal(trapR * 0.8 + uD + 0.35) * iw / (trapR + iw) * 0.7 * inside;
    col += glowpal(trapX + uD + 0.65) * iw / (trapX + iw) * 0.4 * inside * (0.5 + uHigh);
    col += pal(trapC * 0.3 + uD + 0.15) * 0.04 * inside;
    return col * (0.85 + uBeat * 0.35);
}
