// @preset {"name": "Third Eye", "labels": {"a": "iris fibres", "b": "lid rays", "c": "eye size", "d": "color"}, "params": {"palette": 0, "glow": 0.6, "feedback": 0.45, "fb_zoom": 0.25}}
// A visionary eye: almond lids, a fibrous jewelled iris, pupil dilating with the bass, rays of light.

vec3 scene(vec2 p, vec2 uv) {
    float sz = 0.6 + uC * 0.5;
    vec2 q = p / sz;
    float r = length(q);
    float a = atan(q.y, q.x);
    vec3 col = vec3(0.0);

    // almond lids: two arcs
    float lid = abs(abs(q.y) - 0.55 * (1.0 - q.x * q.x)) ;
    float inside = step(abs(q.y), 0.55 * (1.0 - q.x * q.x)) * step(abs(q.x), 1.0);
    col += glowpal(uD + 0.2) * 0.004 / (lid + 0.004) * step(abs(q.x), 1.05);
    for (int i = 1; i < 4; i++) {
        float fi = float(i);
        float l2 = abs(abs(q.y) - (0.55 + fi * 0.12) * (1.0 - q.x * q.x / (1.0 + fi * 0.3)));
        col += glowpal(uD + fi * 0.12) * 0.002 / (l2 + 0.004) * (1.0 - fi * 0.2);
    }

    // iris
    float ir = 0.42;
    float pupil = 0.1 + 0.08 * uBass + 0.03 * sin(uTime * 0.5);
    float fibres = pow(abs(sin(a * (30.0 + uA * 60.0) + sin(r * 30.0 - uTime) * 0.4)), 6.0);
    float irisMask = smoothstep(ir, ir - 0.02, r) * smoothstep(pupil, pupil + 0.03, r);
    vec3 iris = glowpal(r * 2.0 - uTime * 0.05 + uD) * (0.15 + 0.85 * fibres) * irisMask;
    iris += glowpal(uD + 0.5) * 0.003 / (abs(r - ir) + 0.004);
    iris += glowpal(uD + 0.7) * 0.003 / (abs(r - pupil) + 0.004) * (0.6 + uBeat);
    col += iris * inside;

    // rays emanating outward
    float rays = pow(abs(cos(a * (8.0 + floor(uB * 8.0)) + uTime * 0.05)), 20.0);
    col += glowpal(a / TAU + uD + 0.3) * rays * (1.0 - inside) * smoothstep(0.6, 1.0, r) * exp(-r * 0.8) * 0.8;
    col += uPal[1] * 0.12 * exp(-r);
    return col;
}
