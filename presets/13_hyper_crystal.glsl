// @preset {"energy": 2, "family": "object3d", "heavy": true, "name": "Hyper Crystal", "labels": {"a": "fold angle", "b": "4th-dimension slice", "c": "facets", "d": "color"}, "params": {"palette": 4, "glow": 0.6, "feedback": 0.25, "chroma": 0.2}}
// A kaleidoscopic fractal folded in four dimensions and sliced into 3D: a crystal that keeps re-faceting
// itself as the slice moves through the 4th dimension. Glassy rims, glowing inner edges.
// Heavy: best on a Mac.

float crystalTrap;

float crystal(vec3 p) {
    vec4 q = vec4(p, (uB - 0.5) * 1.4 + 0.3 * sin(uTime * 0.17));
    float sc = 1.0;
    float trap = 1e3;
    float ang = 0.35 + uA * 0.9 + 0.1 * sin(uTime * 0.11);
    int iters = 3 + int(uC * 4.0);                       // few folds = big readable facets
    for (int i = 0; i < 10; i++) {
        if (i >= iters) break;
        q = abs(q);
        // fold across the 4D mirror planes x=y, y=z, z=w (a hyper-kaleidoscope)
        if (q.x < q.y) q.xy = q.yx;
        if (q.y < q.z) q.yz = q.zy;
        if (q.z < q.w) q.zw = q.wz;
        if (q.x < q.y) q.xy = q.yx;
        q = q * 1.75 - vec4(1.0, 0.7, 0.5, 0.3) * 0.75;
        q.xw = rot(ang) * q.xw;
        q.yz = rot(ang * 0.6 + uTime * 0.03) * q.yz;
        sc *= 1.75;
        trap = min(trap, length(q.xy));
    }
    crystalTrap = trap;
    // a hyper-octahedron at the core gives flat, glassy faces
    return (dot(abs(q), vec4(0.5)) - 0.9) / sc;
}

vec3 scene(vec2 p, vec2 uv) {
    float a = uTime * 0.06;
    float dist = 2.6 - uBass * 0.12;
    vec3 ro = vec3(sin(a) * dist, 0.5 * sin(uTime * 0.04) * dist, cos(a) * dist);
    vec3 fw = normalize(-ro), rt = normalize(cross(vec3(0.0, 1.0, 0.0), fw)), up = cross(fw, rt);
    vec3 rd = normalize(p.x * rt + p.y * up + 1.8 * fw);

    float t = 0.0, d = 1.0, glow = 0.0;
    for (int i = 0; i < 100; i++) {
        d = crystal(ro + rd * t);
        glow += 0.01 / (1.0 + d * d * 1500.0);
        if (d < 0.0007 * t || t > 9.0) break;
        t += d;
    }
    vec3 col = uPal[0];
    if (d < 0.01) {
        vec3 pos = ro + rd * t;
        float tr = crystalTrap;
        vec2 e = vec2(0.0008, -0.0008);
        vec3 n = normalize(e.xyy * crystal(pos + e.xyy) + e.yyx * crystal(pos + e.yyx) +
                           e.yxy * crystal(pos + e.yxy) + e.xxx * crystal(pos + e.xxx));
        vec3 lig = normalize(vec3(0.4, 0.8, -0.4));
        float dif = max(dot(n, lig), 0.0);
        float fres = pow(1.0 - max(dot(n, -rd), 0.0), 2.5);
        float spe = pow(max(dot(n, normalize(lig - rd)), 0.0), 64.0);
        vec3 glass = glowpal(dot(n, vec3(0.3, 0.5, 0.2)) + tr * 0.6 + uD);   // facets catch different colours
        col = glass * (0.06 + dif * 0.8) + glowpal(fres + uD + 0.5) * fres * 1.1 + vec3(1.0) * spe * 0.6;
        col += glowpal(uD + 0.75) * smoothstep(0.08, 0.0, tr) * 0.8 * (0.5 + uBass);   // inner glowing edges
    }
    col += glowpal(uD + 0.4) * glow * 0.5 * (0.5 + uMid);
    col += uPal[1] * 0.1 * exp(-length(p) * 1.5);
    return col * (0.95 + uBeat * 0.3);
}
