// @preset {"name": "Fractal Cathedral", "labels": {"a": "hall width", "b": "twist", "c": "beat snap", "d": "color"}, "params": {"palette": 0, "glow": 0.6, "feedback": 0.2, "chroma": 0.15, "c": 0.5, "speed": 0.9}}
// Flying down the halls of an endless Menger-sponge cathedral, lit like a render: ambient occlusion in
// every crevice, two coloured lights, iridescent rims and glowing seams. On each beat the camera snaps
// a precise fraction of a turn and settles. Heavy: best on a Mac.

float sdBox(vec3 p, vec3 b) { vec3 q = abs(p) - b; return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0); }

float cathedral(vec3 p) {
    // twist the world slowly along the flight path
    float tw = (uB - 0.5) * 0.12;
    p.xy = rot(p.z * tw) * p.xy;
    // infinite Menger sponge: a point is empty if it lies in any level's cross-shaped hole
    float d = -1e3;
    float th = 1.05 - uA * 0.3;                             // lower threshold = wider halls
    float s = 1.0;
    for (int m = 0; m < 3; m++) {                          // 3 levels: grand halls, clean stonework
        vec3 a = mod(p * s, 2.0) - 1.0;
        s *= 3.0;
        vec3 r = abs(1.0 - 3.0 * abs(a));
        float da = max(r.x, r.y), db = max(r.y, r.z), dc = max(r.z, r.x);
        float c = (min(da, min(db, dc)) - th) / s;
        d = max(d, c);
    }
    return d;
}

vec3 calcNormal(vec3 p) {
    const vec2 e = vec2(0.0015, -0.0015);
    return normalize(e.xyy * cathedral(p + e.xyy) + e.yyx * cathedral(p + e.yyx) +
                     e.yxy * cathedral(p + e.yxy) + e.xxx * cathedral(p + e.xxx));
}

vec3 scene(vec2 p, vec2 uv) {
    // camera down the big central hall, with a precise beat-snapped roll
    float snap = (uBeatCount - uBeat * uBeat) * uC * PI * 0.25;
    vec3 ro = vec3(0.0, 0.0, uPulse * 0.35);                // the hall axis (holes centre on even coords)
    vec3 rd = normalize(vec3(rot(snap + uTime * 0.03) * p, 1.6 - uBass * 0.25));
    rd.xz = rot(0.12 * sin(uTime * 0.13)) * rd.xz;
    rd.yz = rot(0.08 * sin(uTime * 0.11)) * rd.yz;

    float t = 0.02, d = 1.0, glow = 0.0;
    for (int i = 0; i < 96; i++) {
        d = cathedral(ro + rd * t);
        glow += 0.004 / (1.0 + d * d * 3000.0);
        if (d < 0.0006 * t || t > 14.0) break;
        t += d * 0.9;
    }

    vec3 fogc = uPal[0] + uPal[1] * 0.06;
    vec3 col = fogc;
    if (d < 0.01) {
        vec3 pos = ro + rd * t;
        vec3 n = calcNormal(pos);
        // ambient occlusion: how buried this point is in the sponge
        float ao = 0.0, sca = 1.0;
        for (int k = 1; k <= 5; k++) {
            float h = 0.012 * float(k * k);
            ao += (h - cathedral(pos + n * h)) * sca;
            sca *= 0.6;
        }
        ao = clamp(1.0 - 6.0 * ao, 0.0, 1.0);
        vec3 l1 = normalize(vec3(0.6, 0.8, -0.3)), l2 = normalize(vec3(-0.7, -0.3, 0.6));
        vec3 c1 = glowpal(0.3 + uD), c2 = glowpal(0.85 + uD);   // key and fill lights in two palette colours
        float dif1 = max(dot(n, l1), 0.0), dif2 = max(dot(n, l2), 0.0);
        float fres = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        vec3 h1 = normalize(l1 - rd);
        float spec = pow(max(dot(n, h1), 0.0), 40.0);
        vec3 base = vec3(0.06) + uPal[1] * 0.08;                // dark stone
        float sh = ao * ao;                                     // crevices go properly dark
        col = base * (0.06 + dif1 * c1 * 2.2 + dif2 * c2 * 1.1) * sh;
        col += glowpal(fres + pos.z * 0.05 + uD + 0.3) * fres * 0.7 * sh;     // iridescent rims
        col += c1 * spec * 0.9 * sh;
        // glowing seams deep in the cracks, breathing with the bass
        float seam = smoothstep(0.35, 0.0, ao);
        col += glowpal(0.6 + uD + pos.z * 0.02) * seam * (0.4 + uBass * 1.2);
        col = mix(col, fogc, 1.0 - exp(-t * 0.22));           // fog hides far, sub-pixel detail
    }
    col += glowpal(t * 0.04 + uD + 0.4) * glow * (0.4 + uMid * 0.6);
    return col * (0.95 + uBeat * 0.25);
}
