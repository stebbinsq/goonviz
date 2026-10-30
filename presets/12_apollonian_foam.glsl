// @preset {"heavy": true, "name": "Apollonian Foam", "labels": {"a": "bubble size", "b": "drift", "c": "detail (heavy)", "d": "color"}, "params": {"palette": 2, "glow": 0.5, "feedback": 0.2, "chroma": 0.15}}
// Drifting through a 3D Apollonian gasket: spheres packed inside spheres forever, a foam of bubbles at
// every scale, coloured by orbit traps and lit with soft occlusion. Heavy: best on a Mac.

vec4 foamTrap;

float foam(vec3 p) {
    float s = 1.1 + uA * 0.25 + 0.05 * sin(uTime * 0.13);
    float scale = 1.0;
    vec4 orb = vec4(1e3);
    int iters = 6 + int(uC * 3.0);
    for (int i = 0; i < 9; i++) {
        if (i >= iters) break;
        p = -1.0 + 2.0 * fract(0.5 * p + 0.5);
        float r2 = dot(p, p);
        orb = min(orb, vec4(abs(p), r2));
        float k = s / r2;
        p *= k;
        scale *= k;
    }
    foamTrap = orb;
    return 0.25 * abs(p.y) / scale;
}

vec3 scene(vec2 p, vec2 uv) {
    float tm = uTime * (0.08 + uB * 0.12);
    vec3 ro = vec3(2.8 * cos(0.1 + 0.33 * tm), 0.4 + 0.3 * cos(0.37 * tm), 2.8 * cos(0.5 + 0.35 * tm));
    vec3 ta = vec3(1.9 * cos(1.2 + 0.41 * tm), 0.4 + 0.1 * cos(0.27 * tm), 1.9 * cos(2.0 + 0.38 * tm));
    float roll = 0.2 * cos(0.1 * tm) + (uBeatCount - uBeat * uBeat) * 0.0;
    vec3 fw = normalize(ta - ro);
    vec3 rt = normalize(cross(fw, vec3(sin(roll), cos(roll), 0.0)));
    vec3 up = cross(rt, fw);
    vec3 rd = normalize(p.x * rt + p.y * up + 2.0 * fw);

    float t = 0.01, d = 1.0;
    for (int i = 0; i < 110; i++) {
        d = foam(ro + rd * t);
        if (d < 0.0004 * t || t > 12.0) break;
        t += d;
    }
    vec3 fogc = uPal[0] + uPal[1] * 0.05;
    vec3 col = fogc;
    if (t < 12.0) {
        vec3 pos = ro + rd * t;
        vec4 tr = foamTrap;
        vec2 e = vec2(0.0004 * t, 0.0);
        vec3 n = normalize(vec3(foam(pos + e.xyy) - foam(pos - e.xyy),
                                foam(pos + e.yxy) - foam(pos - e.yxy),
                                foam(pos + e.yyx) - foam(pos - e.yyx)));
        float occ = clamp(2.5 * tr.w, 0.0, 1.0);
        vec3 l1 = normalize(vec3(0.6, 0.8, 0.3));
        float dif = max(dot(n, l1), 0.0) * 0.8 + 0.2;
        float fres = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        vec3 albedo = mix(glowpal(tr.x * 2.0 + uD), glowpal(tr.y * 2.0 + uD + 0.35), clamp(6.0 * tr.y, 0.0, 1.0));
        albedo = mix(albedo, glowpal(uD + 0.7), pow(clamp(1.0 - 2.0 * tr.z, 0.0, 1.0), 8.0));
        col = albedo * dif * occ * occ * 0.9 + albedo * 0.03;
        col += glowpal(uD + 0.5 + fres) * fres * 0.5 * occ;
        col = mix(col, fogc, 1.0 - exp(-t * 0.18));
    }
    return col * (0.95 + uBeat * 0.3);
}
