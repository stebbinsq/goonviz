// @preset {"energy": 2, "family": "fractal2d", "name": "Apollonian Lace", "labels": {"a": "inversion", "b": "drift", "c": "lace brightness", "d": "color"}, "params": {"palette": 6, "glow": 0.5, "feedback": 0.25, "zoom": 0.9, "kaleido": 6, "fb_rotate": 0.15}}
// Circle-inversion fractal (Apollonian gasket): infinite nested bubbles traced in light.

vec3 scene(vec2 p, vec2 uv) {
    vec2 q = rot(uTime * 0.03) * p * 2.2 + vec2(uTime * 0.05 * uB, 0.0);
    float s = 1.12 + uA * 0.25 + 0.04 * sin(uTime * 0.2) + uBass * 0.03;
    float scale = 1.0;
    vec4 trap = vec4(1e3);
    for (int i = 0; i < 8; i++) {
        q = -1.0 + 2.0 * fract(0.5 * q + 0.5);
        float r2 = dot(q, q);
        trap = min(trap, vec4(abs(q), r2, length(q - vec2(0.3, 0.2))));
        float k = s / r2;
        q *= k;
        scale *= k;
    }
    float d = 0.25 * abs(q.y) / scale;
    float px = fwidth(p.x) * 1.5;
    float lines = px / (d + px) * (0.4 + uC);

    float depth = clamp(log(scale) * 0.08, 0.0, 1.0);   // how deep into the nesting we are
    vec3 col = glowpal(depth * 1.5 + trap.z * 0.3 + uD + uTime * 0.02) * lines * (1.0 - depth * 0.7);
    col += uPal[1] * 0.12 * smoothstep(0.5, 0.0, trap.w);
    return col * (0.85 + uBeat * 0.4);
}
