// @preset {"name": "Yantra", "labels": {"a": "triangles", "b": "lotus petals", "c": "line glow", "d": "color"}, "params": {"palette": 3, "glow": 0.6, "feedback": 0.4, "fb_zoom": -0.1}}
// Interlocking up/down triangles inside lotus rings: sacred geometry in lines of fire.

float triDist(vec2 p, float s) {
    // distance to an equilateral triangle outline of "radius" s
    const float k = 1.7320508;
    p.x = abs(p.x) - s;
    p.y = p.y + s / k;
    if (p.x + k * p.y > 0.0) p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
    p.x -= clamp(p.x, -2.0 * s, 0.0);
    return abs(-length(p) * sign(p.y));
}

vec3 scene(vec2 p, vec2 uv) {
    float r = length(p);
    float a = atan(p.y, p.x);
    vec3 col = vec3(0.0);
    float w = 0.002 + uC * 0.004;
    float n = 3.0 + floor(uA * 4.0);
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        if (fi >= n) break;
        float up = mod(fi, 2.0) * 2.0 - 1.0;
        float s = 0.7 - fi * 0.09 + 0.01 * sin(uTime + fi);
        vec2 q = rot(uTime * 0.02 * up) * p;
        q.y *= up;
        q.y += (fi - n * 0.5) * 0.04 * up;
        float d = triDist(q, s * 0.85);
        col += glowpal(fi * 0.15 + uD + uTime * 0.02) * w / (d + w) * (0.6 + uBeat * 0.4);
    }
    // lotus petal rings
    float petals = 8.0 + floor(uB * 4.0) * 4.0;
    for (int j = 0; j < 2; j++) {
        float fj = float(j);
        float pr = 0.78 + fj * 0.12;
        float shape = pr + 0.06 * abs(sin(a * petals * 0.5 * (1.0 + fj) + uTime * 0.1 * (fj * 2.0 - 1.0)));
        col += glowpal(fj * 0.3 + uD + 0.4) * 0.0025 / (abs(r - shape) + 0.003);
        col += glowpal(fj * 0.3 + uD + 0.6) * 0.0015 / (abs(r - pr) + 0.003);
    }
    // bindu: the central point
    col += glowpal(uD + 0.1) * 0.006 / (r + 0.006) * (0.7 + uBass);
    col += uPal[1] * 0.15 * exp(-r * 1.5);
    return col;
}
