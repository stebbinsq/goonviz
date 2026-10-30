// @preset {"energy": 2, "family": "flight3d", "heavy": true, "name": "Hypergyroid", "labels": {"a": "cave scale", "b": "4D spin", "c": "wall thickness", "d": "color"}, "params": {"palette": 6, "glow": 0.55, "feedback": 0.25, "chroma": 0.2, "c": 0.4}}
// Flying through caves in a four-dimensional gyroid, sliced into 3D. As it turns through the 4th
// dimension the walls flow, open and seal around you. Iridescent thin-film walls. Heavy: best on a Mac.

float hgyroid(vec3 p) {
    float sc = 2.6 + uA * 3.0;
    vec4 q = vec4(p * sc, 0.0);
    float s = uTime * (0.05 + uB * 0.25) + (uBeatCount - uBeat * uBeat) * 0.12 * uB;
    q.xw = rot(s) * q.xw;
    q.zw = rot(s * 0.7 + 0.8) * q.zw;
    float g = sin(q.x) * cos(q.y) + sin(q.y) * cos(q.z) + sin(q.z) * cos(q.w) + sin(q.w) * cos(q.x);
    float walls = (abs(g) - 0.08 - uC * 0.35) / sc * 0.55;
    float tunnel = 0.3 - length(p.xy - vec2(0.2 * sin(p.z * 0.3), 0.2 * cos(p.z * 0.23)));   // a flight path
    return max(walls, tunnel);
}

vec3 scene(vec2 p, vec2 uv) {
    float z = uPulse * 0.5;
    vec3 ro = vec3(0.2 * sin(z * 0.3), 0.2 * cos(z * 0.23), z);
    vec3 rd = normalize(vec3(p, 1.4 - uBass * 0.2));
    rd.xy = rot(uTime * 0.05) * rd.xy;

    float t = 0.05, d = 1.0, glow = 0.0;
    for (int i = 0; i < 90; i++) {
        d = hgyroid(ro + rd * t);
        glow += 0.01 / (1.0 + d * d * 500.0);
        if (d < 0.0015 || t > 9.0) break;
        t += d;
    }
    vec3 col = vec3(0.0);
    vec3 pos = ro + rd * t;
    float fog = exp(-t * 0.22);
    if (d < 0.01) {
        vec2 e = vec2(0.003, 0.0);
        vec3 n = normalize(vec3(hgyroid(pos + e.xyy) - hgyroid(pos - e.xyy),
                                hgyroid(pos + e.yxy) - hgyroid(pos - e.yxy),
                                hgyroid(pos + e.yyx) - hgyroid(pos - e.yyx)));
        float ndv = clamp(dot(n, -rd), 0.0, 1.0);
        float fres = pow(1.0 - ndv, 3.0);
        vec3 film = glowpal(ndv * 0.9 + pos.z * 0.04 + uD);
        float ao = clamp(hgyroid(pos + n * 0.12) / 0.12, 0.0, 1.0);
        vec3 lig = normalize(vec3(0.3, 0.8, 0.5));
        float dif = max(dot(n, lig), 0.0);
        col = film * (0.06 + dif * 0.7) * ao + glowpal(uD + 0.55 + fres) * fres * 0.9 * ao;
    }
    col *= fog;
    col += glowpal(t * 0.08 + uD + 0.3) * glow * 0.5 * (0.4 + uMid * 0.6);
    return col * (0.95 + uBeat * 0.3);
}
