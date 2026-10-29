// @preset {"name": "Sound Halo", "labels": {"a": "filaments", "b": "radius", "c": "spikes", "d": "color"}, "params": {"palette": 1, "glow": 0.7, "feedback": 0.7, "fb_zoom": 0.35, "fb_hue": 0.08, "kaleido": 0}}
// The spectrum wrapped into a mirrored halo of glowing filaments; feedback spreads it into a corona.

vec3 scene(vec2 p, vec2 uv) {
    float r = length(p);
    float a = atan(p.y, p.x);
    float m = abs(a) / PI;                        // mirrored: bass at the top, treble at the bottom
    float spec = fft(m * 0.85);
    float base = 0.35 + uB * 0.4;
    float radius = base + spec * (0.15 + uC * 0.45);

    vec3 col = vec3(0.0);
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float rr = radius * (1.0 - fi * 0.08 * (0.5 + uA));
        float wob = 0.01 * sin(a * (12.0 + fi * 6.0) + uTime * (1.0 + fi));
        float d = abs(r - rr - wob);
        col += glowpal(m * 0.6 + fi * 0.15 + uD) * 0.004 / (d + 0.004) * (1.0 - fi * 0.15);
    }
    // fine radial filaments, brightness from the spectrum
    float fil = pow(abs(cos(a * (40.0 + uA * 80.0))), 40.0);
    col += glowpal(m + uD + 0.3) * fil * spec * smoothstep(radius + 0.2, radius, r) * smoothstep(base * 0.5, base, r);
    // inner orb breathes with the bass
    col += glowpal(uD + 0.6) * 0.02 / (abs(r - base * 0.4 * (0.6 + uBass)) + 0.02) * 0.3;
    return col;
}
