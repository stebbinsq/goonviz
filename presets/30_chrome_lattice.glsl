// @preset {"name": "Chrome Lattice", "labels": {"a": "tube thickness", "b": "ripple", "c": "beat snap", "d": "color"}, "params": {"palette": 0, "glow": 0.5, "feedback": 0.25, "chroma": 0.12, "c": 0.5}}
// Flying through an infinite lattice of liquid-chrome tubes. The chrome reflects a glowing environment
// built from the palette, ripples with the bass, and the camera snaps on the beat. Heavy: best on a Mac.

float lattice(vec3 p) {
    vec3 q = mod(p, 2.0) - 1.0;
    float rr = 0.08 + uA * 0.16;
    // three rods per cell, smooth-unioned into blobby junctions
    float dx = length(q.yz), dy = length(q.xz), dz = length(q.xy);
    float k = 0.12;
    float d = -k * log(exp(-dx / k) + exp(-dy / k) + exp(-dz / k));
    // liquid ripple running along the rods
    d -= (0.008 + uB * 0.03) * sin(p.x * 6.0 + uTime * 2.0) * sin(p.y * 6.0 - uTime * 1.7) * sin(p.z * 6.0 + uTime * 1.3) * (1.0 + uBass * 1.2);
    return d - rr;
}

vec3 env(vec3 d) {
    // procedural environment the chrome reflects: glowing palette bands and scattered lights
    float e = d.y;
    vec3 c = uPal[0] + uPal[1] * (0.25 + 0.2 * e);            // a lit sky, not black, so the chrome reads
    c += glowpal(e * 0.8 + uD) * pow(0.5 + 0.5 * sin(e * 10.0 + uTime * 0.5), 6.0) * 0.8;
    c += glowpal(d.x * 0.3 + d.z * 0.2 + uD + 0.4) * pow(max(0.0, 1.0 - abs(e)), 6.0) * 0.5;   // seamless (no atan wrap)
    c += glowpal(0.1 + uD) * pow(max(dot(d, normalize(vec3(0.4, 0.7, 0.3))), 0.0), 40.0) * 2.0;   // sun
    c += glowpal(0.5 + uD) * smoothstep(0.02, 0.0, abs(e + 0.05)) * 0.6;                         // horizon
    float stars = step(0.985, hash12(floor(d.xz / max(0.2, 1.0 - abs(e)) * 30.0 + floor(e * 30.0) * 17.0)));
    c += glowpal(0.6 + uD) * stars * 1.5;
    return c;
}

vec3 scene(vec2 p, vec2 uv) {
    float snap = (uBeatCount - uBeat * uBeat) * uC * PI * 0.25;
    vec3 ro = vec3(0.0, 0.0, uPulse * 0.6);
    vec3 rd = normalize(vec3(rot(snap) * p, 1.5 - uBass * 0.2));
    // look across the lattice diagonally so tubes recede in every direction
    rd.xz = rot(0.62 + uTime * 0.05) * rd.xz;
    rd.yz = rot(0.45 + 0.2 * sin(uTime * 0.035)) * rd.yz;

    float t = 0.0, d = 1.0, glow = 0.0;
    for (int i = 0; i < 90; i++) {
        d = lattice(ro + rd * t);
        glow += 0.01 / (1.0 + d * d * 600.0);
        if (abs(d) < 0.0008 * t || t > 18.0) break;
        t += d * 0.8;
    }
    vec3 fogc = uPal[0];
    vec3 col = env(rd) * 0.3;
    if (abs(d) < 0.02) {
        vec3 pos = ro + rd * t;
        vec2 e = vec2(0.001, -0.001);
        vec3 n = normalize(e.xyy * lattice(pos + e.xyy) + e.yyx * lattice(pos + e.yyx) +
                           e.yxy * lattice(pos + e.yxy) + e.xxx * lattice(pos + e.xxx));
        vec3 rf = reflect(rd, n);
        float fres = 0.3 + 0.7 * pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        vec3 chrome = env(rf) * fres;
        // a little tint so it reads as coloured chrome, not mirror
        chrome *= mix(vec3(1.0), glowpal(0.2 + uD), 0.35);
        float ao = clamp(lattice(pos + n * 0.15) / 0.15, 0.0, 1.0);
        col = chrome * (0.4 + 0.6 * ao);
        col = mix(col, fogc, 1.0 - exp(-t * 0.1));
    }
    col += glowpal(t * 0.05 + uD + 0.5) * glow * 0.5 * (0.5 + uMid);
    return col * (0.95 + uBeat * 0.3);
}
