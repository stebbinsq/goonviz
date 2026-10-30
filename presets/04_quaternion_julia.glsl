// @preset {"energy": 2, "family": "object3d", "heavy": true, "name": "Quaternion Julia", "labels": {"a": "shape", "b": "4th-dimension slice", "c": "detail (heavy)", "d": "color"}, "params": {"palette": 2, "glow": 0.55, "feedback": 0.2, "chroma": 0.15, "c": 0.5}}
// A four-dimensional Julia fractal (quaternions), sliced into 3D. The seed drifts and the slice moves
// through the fourth dimension, so the form folds and turns inside itself in ways no 3D object can.
// Lit like a render. Heavy: best on a Mac.

float qTrap;

vec4 qsq(vec4 a) { return vec4(a.x * a.x - dot(a.yzw, a.yzw), 2.0 * a.x * a.yzw); }

float qjulia(vec3 p) {
    float t = uTime * 0.15;
    // seed orbit from the classic quaternion-Julia family; A scales how far it strays (wilder shapes)
    vec4 c = (0.38 + uA * 0.14) * cos(vec4(0.5, 3.9, 1.4, 1.1) + t * vec4(1.2, 1.7, 1.3, 2.5)) - vec4(0.3, 0.0, 0.0, 0.0);
    float w = (uB - 0.5) * 1.2 + 0.25 * sin(uTime * 0.21);        // where the 3D slice cuts the 4th dimension
    vec4 z = vec4(p, w);
    float md2 = 1.0, mz2 = dot(z, z);
    float trap = 1e3;
    int iters = 7 + int(uC * 5.0);
    for (int i = 0; i < 12; i++) {
        if (i >= iters) break;
        md2 *= 4.0 * mz2;
        z = qsq(z) + c;
        mz2 = dot(z, z);
        trap = min(trap, abs(z.x) + 0.5 * abs(z.w));
        if (mz2 > 4.0) break;
    }
    qTrap = trap;
    return 0.25 * sqrt(mz2 / md2) * log(max(mz2, 1e-6));
}

vec3 scene(vec2 p, vec2 uv) {
    float a = uTime * 0.07;
    float dist = 1.85 - uBass * 0.1;
    vec3 ro = vec3(sin(a) * dist, 0.6 * sin(uTime * 0.05), cos(a) * dist);
    vec3 fw = normalize(-ro), rt = normalize(cross(vec3(0.0, 1.0, 0.0), fw)), up = cross(fw, rt);
    vec3 rd = normalize(p.x * rt + p.y * up + 1.8 * fw);

    vec3 col = uPal[0];
    float glow = 0.0;
    float b = dot(ro, rd), h = b * b - (dot(ro, ro) - 2.25);   // bounding sphere r = 1.5
    if (h > 0.0) {
        float t = max(0.0, -b - sqrt(h)), d = 1.0;
        float tmax = -b + sqrt(h);
        for (int i = 0; i < 90; i++) {
            d = qjulia(ro + rd * t);
            glow += 0.015 / (1.0 + d * d * 1500.0);
            if (d < 0.0006 * t || t > tmax) break;
            t += d;
        }
        if (d < 0.005) {
            vec3 pos = ro + rd * t;
            float tr = qTrap;
            vec2 e = vec2(0.0008, -0.0008);
            vec3 n = normalize(e.xyy * qjulia(pos + e.xyy) + e.yyx * qjulia(pos + e.yyx) +
                               e.yxy * qjulia(pos + e.yxy) + e.xxx * qjulia(pos + e.xxx));
            vec3 lig = normalize(vec3(0.6, 0.7, -0.4));
            float dif = max(dot(n, lig), 0.0);
            float back = max(dot(n, -lig), 0.0);
            float fres = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
            float spe = pow(max(dot(n, normalize(lig - rd)), 0.0), 48.0);
            float occ = clamp(tr * 2.5, 0.15, 1.0);
            vec3 albedo = glowpal(tr * 1.8 + uD + uTime * 0.02);
            col = albedo * (0.05 + dif * 1.1 + back * glowpal(uD + 0.6) * 0.35) * occ;
            col += glowpal(fres + uD + 0.4) * fres * 0.9;
            col += vec3(1.0) * spe * 0.5 * occ;
        }
    }
    col += glowpal(uD + 0.5) * glow * 0.5 * (0.5 + uMid);
    col += uPal[1] * 0.12 * exp(-length(p) * 1.4);
    return col * (0.95 + uBeat * 0.3);
}
