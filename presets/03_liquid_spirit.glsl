// @preset {"energy": 1, "family": "organic", "name": "Liquid Spirit", "labels": {"a": "turbulence", "b": "filaments", "c": "filament count", "d": "color"}, "params": {"palette": 1, "glow": 0.55, "feedback": 0.4, "fb_zoom": 0.1}}
// Ink in water: domain-warped noise, mostly dark, with luminous filaments riding the flow.

vec3 scene(vec2 p, vec2 uv) {
    p *= 0.6;
    float t = uPulse * 0.1;
    vec2 q = vec2(fbm(p * 0.8 + vec2(0.0, t)), fbm(p * 0.8 + vec2(5.2, 1.3) - t));
    float amt = 1.5 + uA * 3.0;
    vec2 r = vec2(fbm(p + amt * q + vec2(1.7, 9.2) + t * 1.5),
                  fbm(p + amt * q + vec2(8.3, 2.8) - t * 1.2));
    float f = fbm(p + amt * r);

    vec3 col = pal(0.1 + f * 0.6 + uD) * pow(f, 2.5) * 1.1;

    float k = 2.0 + uC * 6.0;
    float v = f * k - uTime * 0.15;
    float iso = abs(fract(v) - 0.5) / max(fwidth(v), 1e-4);
    float fil = 1.0 / (1.0 + iso * iso * 0.25);
    float zone = smoothstep(0.35, 0.75, f);
    col += glowpal(f * 1.2 + length(q) * 0.5 + uD) * fil * zone * (0.25 + uB) * (0.6 + uMid * 0.8);

    // a soft core of light where the ink is densest
    col += glowpal(f + 0.5 + uD) * pow(smoothstep(0.55, 0.9, f), 4.0) * (1.0 + uBeat * 1.5);
    return col;
}
