// @preset {"name": "Crystal Caverns", "labels": {"a": "cave scale", "b": "wall thickness", "c": "quality (Pi: keep low)", "d": "color"}, "params": {"palette": 0, "glow": 0.55, "chroma": 0.3, "c": 0.3, "feedback": 0.25}}
// Flying through gyroid crystal caves: iridescent thin-film walls, fresnel rims, glowing near-misses.

float caveMap(vec3 p) {
    float sc = 1.2 + uA * 2.0;
    vec3 q = p * sc;
    float g = dot(sin(q), cos(q.zxy));
    float walls = (abs(g) - 0.15 - uB * 0.35) / sc * 0.7;
    float tunnel = 0.45 - length(p.xy - vec2(0.3, 0.2));   // carve a flight path for the camera
    return max(walls, tunnel);
}

vec3 scene(vec2 p, vec2 uv) {
    vec3 ro = vec3(0.3, 0.2, uPulse * 0.5);
    vec3 rd = normalize(vec3(p, 1.4));
    rd.xy = rot(uTime * 0.08) * rd.xy;
    rd.xz = rot(sin(uTime * 0.11) * 0.35) * rd.xz;

    float t = 0.05;
    float d = 1.0;
    float glow = 0.0;
    int steps = 24 + int(uC * 40.0);
    for (int i = 0; i < 64; i++) {
        if (i >= steps) break;
        d = caveMap(ro + rd * t);
        glow += 0.01 / (1.0 + d * d * 400.0);
        if (d < 0.002 || t > 8.0) break;
        t += d;
    }

    vec3 col = vec3(0.0);
    vec3 pos = ro + rd * t;
    float fog = exp(-t * 0.32);
    if (d < 0.01) {
        vec2 e = vec2(0.003, 0.0);
        vec3 n = normalize(vec3(caveMap(pos + e.xyy) - caveMap(pos - e.xyy),
                                caveMap(pos + e.yxy) - caveMap(pos - e.yxy),
                                caveMap(pos + e.yyx) - caveMap(pos - e.yyx)));
        float ndv = clamp(dot(n, -rd), 0.0, 1.0);
        float fres = pow(1.0 - ndv, 3.0);
        // thin-film: hue shifts with viewing angle, like oil on glass
        vec3 film = glowpal(ndv * 0.8 + pos.z * 0.05 + uD);
        float bands = 0.5 + 0.5 * sin(dot(pos, vec3(7.0)) + uTime);
        col = film * (0.08 + 0.25 * bands * (1.0 - ndv)) + glowpal(uD + 0.5 + fres) * fres * 0.7;
    }
    col *= fog;
    col += glowpal(t * 0.1 + uD + 0.25) * glow * (0.3 + uMid * 0.5);
    return col * (0.85 + uBeat * 0.4);
}
