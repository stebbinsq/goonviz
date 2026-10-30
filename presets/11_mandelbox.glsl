// @preset {"energy": 2, "family": "object3d", "heavy": true, "name": "Mandelbox", "labels": {"a": "fold scale", "b": "camera distance", "c": "detail (heavy)", "d": "color"}, "params": {"palette": 3, "glow": 0.5, "feedback": 0.2, "chroma": 0.15, "a": 0.4, "c": 0.5}}
// The Mandelbox: box fold, sphere fold, scale, repeat. It grows a whole alien architecture of towers,
// chambers and lattices. Orbit-trap colour, ambient occlusion and a slow camera drift around it.
// Heavy: best on a Mac.

float boxTrap;

float mbox(vec3 pos) {
    float S = -1.6 - uA * 0.9 + 0.05 * sin(uTime * 0.1);
    const float MR2 = 0.25;
    vec4 sv = vec4(S, S, S, abs(S)) / MR2;
    vec4 p = vec4(pos, 1.0), p0 = p;
    float trap = 1e3;
    int iters = 7 + int(uC * 5.0);
    for (int i = 0; i < 13; i++) {
        if (i >= iters) break;
        p.xyz = clamp(p.xyz, -1.0, 1.0) * 2.0 - p.xyz;
        float r2 = dot(p.xyz, p.xyz);
        trap = min(trap, r2);
        p *= clamp(max(MR2 / r2, MR2), 0.0, 1.0);
        p = p * sv + p0;
    }
    boxTrap = trap;
    return (length(p.xyz) - abs(S - 1.0)) / p.w - pow(abs(S), 1.0 - float(iters));
}

vec3 scene(vec2 p, vec2 uv) {
    float a = uTime * 0.04;
    float dist = 3.0 + uB * 2.5 - uBass * 0.2;
    vec3 ro = vec3(sin(a) * dist, 1.2 + 1.5 * sin(uTime * 0.03), cos(a) * dist);
    vec3 ta = vec3(0.0, 0.3 * sin(uTime * 0.05), 0.0);
    vec3 fw = normalize(ta - ro), rt = normalize(cross(vec3(0.0, 1.0, 0.0), fw)), up = cross(fw, rt);
    vec3 rd = normalize(p.x * rt + p.y * up + 1.7 * fw);

    float t = 0.0, d = 1.0, glow = 0.0;
    for (int i = 0; i < 90; i++) {
        d = mbox(ro + rd * t);
        glow += 0.01 / (1.0 + d * d * 400.0);
        if (d < 0.0008 * t || t > 30.0) break;
        t += d;
    }
    vec3 fogc = uPal[0] + uPal[1] * 0.06;
    vec3 col = fogc;
    if (d < 0.02) {
        vec3 pos = ro + rd * t;
        float tr = boxTrap;
        vec2 e = vec2(0.0015 * t * 0.2 + 0.0005, 0.0);
        vec3 n = normalize(vec3(mbox(pos + e.xyy) - mbox(pos - e.xyy),
                                mbox(pos + e.yxy) - mbox(pos - e.yxy),
                                mbox(pos + e.yyx) - mbox(pos - e.yyx)));
        float ao = 0.0, sca = 1.0;
        for (int k = 1; k <= 4; k++) {
            float hh = 0.03 * float(k * k);
            ao += (hh - mbox(pos + n * hh)) * sca;
            sca *= 0.55;
        }
        ao = clamp(1.0 - 3.0 * ao, 0.0, 1.0);
        vec3 l1 = normalize(vec3(0.6, 0.8, 0.2)), l2 = normalize(vec3(-0.6, 0.2, -0.7));
        vec3 albedo = mix(glowpal(sqrt(tr) * 0.8 + uD), glowpal(uD + 0.5), smoothstep(0.2, 1.0, tr));
        float dif = max(dot(n, l1), 0.0), fill = max(dot(n, l2), 0.0);
        float fres = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        float spe = pow(max(dot(n, normalize(l1 - rd)), 0.0), 32.0);
        col = albedo * (0.04 + dif * 1.2 + fill * glowpal(uD + 0.75) * 0.4) * ao * ao;
        col += glowpal(uD + 0.3 + fres) * fres * 0.5 * ao;
        col += vec3(1.0) * spe * 0.4 * ao;
        col = mix(col, fogc, 1.0 - exp(-t * 0.04));
    }
    col += glowpal(uD + 0.6) * glow * 0.35 * (0.5 + uMid);
    return col * (0.95 + uBeat * 0.3);
}
