// @preset {"name": "Fractal Temple", "labels": {"a": "symmetry", "b": "spread", "c": "fold angle", "d": "color"}, "params": {"palette": 2, "glow": 0.5, "feedback": 0.3, "chroma": 0.2}}
// Kaleidoscopic IFS: repeated mirror-fold-rotate-scale, with glowing line and ring traps.

vec3 scene(vec2 p, vec2 uv) {
    float t = uTime * 0.15;
    vec2 q = kaleido(rot(t * 0.3) * p, floor(5.0 + uA * 5.0));
    float s = 1.0;
    vec3 col = vec3(0.0);
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        q = abs(q) - vec2(0.55 + 0.1 * sin(t * 1.3), 0.3 + 0.2 * uB + 0.03 * uBass);
        q = rot(0.6 + uC * 1.2 + 0.2 * sin(t + fi)) * q;
        q *= 1.38;
        s *= 1.38;
        float dl = abs(q.y) / s;
        float dc = abs(length(q) - 0.4) / s;
        vec3 c = glowpal(fi * 0.29 + uD + t * 0.2);
        col += c * (0.0005 / (dl + 0.002) + 0.0008 / (dc + 0.002)) * (0.45 + 0.1 * fi);
    }
    col *= 0.8 + uBeat * 0.6;
    col += uPal[1] * 0.08 * (1.0 - length(p) * 0.5);
    return col;
}
