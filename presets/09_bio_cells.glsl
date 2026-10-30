// @preset {"energy": 1, "family": "organic", "name": "Bioluminescence", "labels": {"a": "cell size", "b": "wobble", "c": "nuclei", "d": "color"}, "params": {"palette": 4, "glow": 0.6, "feedback": 0.3}}
// Living Voronoi tissue: glowing membranes, and each cell's nucleus pulses with its own slice of the spectrum.

vec3 voronoi(vec2 x) {
    vec2 n = floor(x);
    vec2 f = fract(x);
    float md = 8.0, md2 = 8.0;
    vec2 mid = vec2(0.0);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 g = vec2(float(i), float(j));
            vec2 o = hash22(n + g);
            o = 0.5 + 0.45 * sin(uTime * 0.6 + TAU * o);
            vec2 r = g + o - f;
            float d = dot(r, r);
            if (d < md) { md2 = md; md = d; mid = n + g; }
            else if (d < md2) { md2 = d; }
        }
    }
    return vec3(sqrt(md), sqrt(md2) - sqrt(md), hash12(mid));
}

vec3 scene(vec2 p, vec2 uv) {
    vec2 q = p * (2.0 + uA * 4.0);
    q += (vec2(fbm(p * 1.5 + uTime * 0.1), fbm(p * 1.5 - uTime * 0.1 + 4.0)) - 0.5) * uB * 2.5;
    vec3 v = voronoi(q);

    float px = fwidth(q.x) * 1.5;
    float membrane = px / (v.y + px) + 0.35 * exp(-v.y * 10.0);
    float nucleus = exp(-v.x * v.x * 40.0) * (0.3 + 1.5 * fft(v.z)) * uC * 2.0;

    vec3 col = glowpal(v.z * 0.6 + uD) * membrane * 0.8;
    col += glowpal(v.z * 0.6 + uD + 0.5) * nucleus;
    col += pal(v.z + uD) * 0.25 * (1.0 - v.x);

    // finer capillaries
    vec3 v2 = voronoi(q * 3.1 + 7.0);
    col += glowpal(v2.z + uD + 0.25) * 0.15 * exp(-v2.y * 14.0);
    return col * (0.85 + uBeat * 0.3);
}
