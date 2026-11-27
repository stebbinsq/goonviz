// @preset {"energy": 3, "family": "object3d", "heavy": true, "name": "Disco Booty", "labels": {"a": "jiggle", "b": "twerk", "c": "camera", "d": "material"}, "params": {"palette": 5, "glow": 0.5, "feedback": 0.0, "chroma": 0.03, "a": 0.6, "b": 0.6, "c": 0.5, "d": 0.0}}
// A giant disco-ball booty twerking in a club. The hips pop up and back on every beat, swaying side to side
// over two beats; each cheek bounces on its own damped spring (the beat's decay tells us the time since the
// hit), leading cheek alternating, with a squeeze-and-release "clap" every fourth beat and a bass wobble.
// MATERIAL (D): mirror-tile mosaic (every tile tilted a little, so it sparkles, and it throws light spots
// across the walls), liquid chrome, gold glitter, holographic film. The club: moving lamps, LED strips
// chasing on the beat, light shafts in the haze. A = jiggle, B = twerk, C = camera angle.

float sdEll(vec3 p, vec3 r) {
    float k0 = length(p / r), k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / k1;
}
float sdCap(vec3 p, vec3 a, vec3 b, float ra, float rb) {
    vec3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - mix(ra, rb, h);
}
float smin(float a, float b, float k) { float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0); return mix(b, a, h) - k * h * (1.0 - h); }
float smax(float a, float b, float k) { return -smin(-a, -b, k); }
vec3 hash33b(vec3 p3) {
    p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// ---- the dance (set once per pixel in scene(), read by the SDF)
vec3 gHip;        // hip offset
float gTilt;      // hips popped up/back (rotation about x)
float gRoll;      // side tilt with the sway
vec3 gCheek[2];   // each cheek's bounce offset
vec3 gSquash[2];  // and its squash/stretch

void dance() {
    float tb = -log(max(uBeat, 0.001)) / 7.0;                  // seconds since the last beat (uBeat decays as exp(-7t))
    float pop = pow(uBeat, 1.4);
    float lead = mod(uBeatCount, 2.0) < 0.5 ? 1.0 : -1.0;       // which cheek leads this beat
    float phase = uBeatCount + min(tb / 0.47, 1.0);             // beat-locked phase (holds still if the music stops)
    float sway = sin(PI * phase) * (0.6 + 0.4 * uB) + 0.25 * sin(uTime * 0.6);
    gHip = vec3(sway * 0.07, pop * (0.04 + 0.1 * uB), pop * (0.03 + 0.07 * uB));
    gTilt = -pop * (0.1 + 0.28 * uB) - 0.04 * sin(uTime * 1.3);
    gRoll = sway * 0.06;
    float clap = mod(uBeatCount, 4.0) < 0.5 ? uBeat : 0.0;     // every fourth beat: squeeze together
    for (int i = 0; i < 2; i++) {
        float s = i == 0 ? -1.0 : 1.0;
        bool leads = s * lead > 0.0;
        // a damped spring kicked by the beat: ~5 Hz, the trailing cheek a touch late and softer
        float spring = uBeat * sin(tb * 32.0 + (leads ? 0.0 : 1.1)) * (leads ? 1.0 : 0.75);
        float wob = uBass * 0.35 * sin(uRealTime * 23.0 + s * 1.7);
        float b = (spring + wob) * (0.3 + 0.9 * uA);
        gCheek[i] = vec3(-s * clap * 0.035, b * 0.055, b * 0.02);
        gSquash[i] = vec3(1.0 + b * 0.07 + clap * 0.05, 1.0 - b * 0.11, 1.0 + b * 0.04);
    }
}

vec3 toLocal(vec3 p) {
    p -= gHip;
    p.yz = rot(gTilt) * p.yz;
    p.xy = rot(gRoll) * p.xy;
    return p;
}
vec3 toWorldDir(vec3 n) {
    n.xy = rot(-gRoll) * n.xy;
    n.yz = rot(-gTilt) * n.yz;
    return n;
}

float bootyL(vec3 p) {
    // bent forward (the torso leans away from us), knees bent and apart: a twerk stance
    float back = sdEll(p - vec3(0.0, 0.58, -0.24), vec3(0.33, 0.4, 0.24));
    back = smin(back, sdEll(p - vec3(0.0, 0.92, -0.58), vec3(0.37, 0.3, 0.3)), 0.2);
    float pelvis = sdEll(p - vec3(0.0, 0.17, -0.08), vec3(0.5, 0.36, 0.33));
    float d = smin(back, pelvis, 0.22);
    for (int i = 0; i < 2; i++) {
        float s = i == 0 ? -1.0 : 1.0;
        vec3 c = vec3(s * 0.215, -0.03, 0.11) + gCheek[i];
        d = smin(d, sdEll(p - c, vec3(0.29, 0.3, 0.27) * gSquash[i]), 0.16);
        vec3 knee = vec3(s * 0.42, -1.0, -0.26);
        float thigh = sdCap(p, vec3(s * 0.25, -0.2, 0.0), knee, 0.205, 0.165);
        d = smin(d, thigh, 0.07);
        d = smin(d, sdCap(p, knee, vec3(s * 0.45, -1.88, 0.02), 0.15, 0.1), 0.05);
    }
    // a soft cartoon crease down the middle
    d = smax(d, -sdEll(p - vec3(0.0, -0.09, 0.32), vec3(0.02, 0.28, 0.15)), 0.035);
    return d;
}

vec3 bootyNormalL(vec3 p) {
    vec2 h = vec2(0.001, -0.001);
    return normalize(h.xyy * bootyL(p + h.xyy) + h.yyx * bootyL(p + h.yyx) + h.yxy * bootyL(p + h.yxy) + h.xxx * bootyL(p + h.xxx));
}

// ---- the club, as seen in a reflection (and behind the dancer)
vec3 lampDir(int i) {
    float fi = float(i);
    float a = uTime * (0.25 + 0.07 * fi) + fi * 1.26;
    return normalize(vec3(sin(a) * 0.9, 0.3 + 0.25 * sin(uTime * 0.4 + fi * 2.0), cos(a) * 0.9 + 0.3));
}
vec3 club(vec3 d) {
    float az = atan(d.x, d.z);
    // the room itself: dim coloured walls, a little brighter toward the floor's glow
    vec3 c = glowpal(az * 0.08 + 0.4) * 0.025 + vec3(0.01, 0.008, 0.014);
    c += glowpal(az * 0.05 + uTime * 0.02) * 0.05 * smoothstep(0.1, -0.5, d.y) * (0.6 + 0.6 * uBeat);
    // moving lamps around the room
    for (int i = 0; i < 5; i++) {
        float k = max(dot(d, lampDir(i)), 0.0);
        c += glowpal(float(i) * 0.2 + uTime * 0.03) * (pow(k, 1200.0) * 40.0 + pow(k, 60.0) * 0.35) * (0.6 + 0.8 * uBeat);
    }
    // the follow spots behind the camera, aimed at the dancer: what makes the tiles flash
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        vec3 fd = normalize(vec3((fi - 1.0) * 0.55 + 0.1 * sin(uTime * 0.3 + fi), 0.45 + 0.1 * fi, 0.85));
        float k = max(dot(d, fd), 0.0);
        vec3 fc = i == 1 ? vec3(1.0, 0.92, 0.85) : glowpal(fi * 0.4 + 0.15);
        c += fc * (pow(k, 400.0) * 12.0 + pow(k, 20.0) * 0.25);
    }
    // neon strips around the walls, with pulses chasing along them on the beat
    for (int j = 0; j < 2; j++) {
        float el = j == 0 ? 0.14 : -0.12;
        float strip = exp(-pow((d.y - el) / 0.006, 2.0)) + exp(-pow((d.y - el) / 0.03, 2.0)) * 0.12;
        float chase = pow(0.5 + 0.5 * sin(az * 6.0 + (j == 0 ? 1.0 : -1.0) * uPulse * 3.0), 6.0);
        c += glowpal(az * 0.16 + float(j) * 0.5 + uTime * 0.05) * strip * (0.35 + 1.4 * chase) * (0.8 + 0.6 * uBeat);
    }
    return c;
}

// the light-up dance floor: squares flashing in palette colours, a new pattern every beat
vec3 danceFloor(vec2 q) {
    vec2 ci = floor(q * 1.6), cf = fract(q * 1.6) - 0.5;
    float h = hash12(ci + floor(uBeatCount) * 7.31);
    float on = step(0.55, h);
    float edge = smoothstep(0.5, 0.42, max(abs(cf.x), abs(cf.y)));
    return glowpal(h * 2.0 + uTime * 0.02) * on * edge * (0.25 + 0.6 * uBeat) + vec3(0.01) * edge;
}

// what a reflection sees from point pos in direction d: the room, or the dance floor below
vec3 envAt(vec3 pos, vec3 d) {
    if (d.y < -0.01) {
        float tf = (-1.9 - pos.y) / d.y;
        vec3 fp = pos + d * tf;
        return danceFloor(fp.xz) * exp(-tf * 0.08) + club(reflect(d, vec3(0.0, 1.0, 0.0))) * 0.2;
    }
    return club(d);
}

vec3 scene(vec2 p, vec2 uv) {
    dance();
    // camera: knob C swings it around, with a slow drift and a little shake on the beat
    float ang = (uC - 0.5) * 1.6 + 0.3 * sin(uTime * 0.07);
    float dist = 2.25 - 0.2 * sin(uTime * 0.05);
    vec3 ta = vec3(0.0, -0.2, 0.0) + vec3(sin(uRealTime * 31.0), cos(uRealTime * 27.0), 0.0) * 0.006 * uBeat;
    vec3 ro = vec3(sin(ang) * dist, -0.05 + 0.15 * sin(uTime * 0.045), cos(ang) * dist);
    vec3 fw = normalize(ta - ro);
    vec3 rt = normalize(cross(fw, vec3(0.0, 1.0, 0.0))), up = cross(rt, fw);
    vec3 rd = normalize(p.x * rt + p.y * up + 1.6 * fw);

    // march, inside a bounding sphere around the dancer
    vec3 oc = ro - vec3(0.0, -0.5, -0.1);
    float b = dot(oc, rd), c = dot(oc, oc) - 1.75 * 1.75, h = b * b - c;
    float t = 1e3;
    if (h > 0.0) {
        float tt = max(-b - sqrt(h), 0.0), te = -b + sqrt(h);
        for (int i = 0; i < 110; i++) {
            float d = bootyL(toLocal(ro + rd * tt));
            if (d < 0.0006 * tt) { t = tt; break; }
            tt += d * 0.9;
            if (tt > te) break;
        }
    }

    // mirror-ball weight (drives the light spots on the walls)
    float m = uD * 3.0;
    float wMirror = 1.0 - smoothstep(0.0, 1.0, m);
    vec3 col;
    if (t > 100.0 && rd.y < 0.0 && ro.y + rd.y * 60.0 < -1.9) {
        // the dance floor (it reflects the room a little)
        float tf = (-1.9 - ro.y) / rd.y;
        vec3 fp = ro + rd * tf;
        col = danceFloor(fp.xz) + club(reflect(rd, vec3(0.0, 1.0, 0.0))) * 0.25;
        col *= exp(-tf * 0.08);
    } else if (t > 100.0) {
        col = club(rd);
        // light thrown off the mirror tiles, sweeping over the walls as the hips move
        vec3 dd = rd;
        dd.xz = rot(gHip.x * 6.0 + uTime * 0.15) * dd.xz;
        vec2 sp = vec2(atan(dd.x, dd.z), asin(clamp(dd.y, -1.0, 1.0))) * vec2(9.0, 9.0);
        vec2 ci = floor(sp), cf = fract(sp) - 0.5 - (hash22(ci) - 0.5) * 0.6;
        float spot = step(0.55, hash12(ci + 3.1)) * smoothstep(0.12, 0.05, length(cf));
        col += glowpal(hash12(ci) + uTime * 0.02) * spot * (0.15 + 0.55 * wMirror) * (0.5 + uBeat);
    } else {
        vec3 pos = ro + rd * t;
        vec3 pl = toLocal(pos);
        vec3 nl = bootyNormalL(pl);
        vec3 n = toWorldDir(nl);
        float fres = pow(1.0 - max(dot(n, -rd), 0.0), 5.0);
        float ao = clamp(bootyL(pl + nl * 0.08) / 0.08, 0.25, 1.0);

        // the knob crossfades between neighbouring materials; only the ones in use are evaluated
        float m0 = clamp(1.0 - m, 0.0, 1.0), m1 = clamp(1.0 - abs(m - 1.0), 0.0, 1.0);
        float m2 = clamp(1.0 - abs(m - 2.0), 0.0, 1.0), m3 = clamp(m - 2.0, 0.0, 1.0);
        vec3 r = reflect(rd, n);
        vec3 envR = (m1 + m2 + m3) > 0.0 ? envAt(pos, r) : vec3(0.0);
        col = vec3(0.0);
        if (m0 > 0.0) {
            // 1) mirror tiles: a mosaic laid on the body (triplanar), each tile tilted at random, dark grout between
            vec3 an = abs(nl);
            vec2 tp = an.x > an.y && an.x > an.z ? pl.yz : an.y > an.z ? pl.xz : pl.xy;
            float axis = an.x > an.y && an.x > an.z ? 0.0 : an.y > an.z ? 1.0 : 2.0;
            vec2 cell = floor(tp / 0.05);
            vec2 f = fract(tp / 0.05) - 0.5;
            float grout = smoothstep(0.4, 0.47, max(abs(f.x), abs(f.y)));
            vec3 tn = toWorldDir(normalize(nl + (hash33b(vec3(cell, axis * 17.0)) - 0.5) * 0.3));
            col += (envAt(pos, reflect(rd, tn)) * 0.95 * (1.0 - grout * 0.9) + vec3(0.01) * grout) * m0;
        }
        // 2) liquid chrome
        if (m1 > 0.0) col += envR * mix(0.55, 1.0, fres) * vec3(0.95, 0.97, 1.0) * m1;
        if (m2 > 0.0) {
            // 3) gold glitter: warm metal with tiny flakes catching the lamps
            vec3 gold = vec3(1.0, 0.72, 0.3) * (envR * 0.6 + 0.03);
            vec3 gc = floor(pl * 90.0);
            vec3 fl = toWorldDir(normalize(nl + (hash33b(gc) - 0.5) * 1.2));
            vec3 fr = reflect(rd, fl);
            float flake = 0.0;
            for (int i = 0; i < 5; i++) flake += pow(max(dot(fr, lampDir(i)), 0.0), 300.0);
            gold += vec3(1.0, 0.85, 0.5) * flake * 6.0 * step(0.5, hash33b(gc + 7.0).x);
            col += gold * m2;
        }
        if (m3 > 0.0) {
            // 4) holographic film: rainbow interference that shifts with the viewing angle
            float film = dot(n, -rd) * 2.2 + noise(pl.xy * 3.0) * 0.6 + uTime * 0.05;
            col += (mix(glowpal(film), glowpal(film + 0.33), 0.5) * (0.25 + 0.5 * fres) + envR * 0.6) * m3;
        }
        col *= ao;
        col += vec3(1.0, 0.9, 0.8) * fres * 0.05;               // rim light
    }

    // light shafts from three lamps through the haze
    for (int i = 0; i < 3; i++) {
        vec3 a = vec3((float(i) - 1.0) * 2.6, 3.2, -2.5 + float(i));
        vec3 dir = normalize(vec3(0.3 * sin(uTime * 0.3 + float(i) * 2.0), -0.2, 0.0) - a);
        vec3 w0 = ro - a;
        float bb = dot(rd, dir), dd = dot(rd, w0), ee = dot(dir, w0);
        float den = max(1.0 - bb * bb, 1e-4);
        float sc = (bb * ee - dd) / den;
        float tc = max((ee - bb * dd) / den, 0.0);
        float dist = length(w0 + rd * sc - dir * tc);
        float wid = 0.06 + tc * 0.12;
        float shaft = exp(-dist * dist / (wid * wid)) * step(0.0, sc) * step(sc, t) * exp(-tc * 0.25);
        col += glowpal(float(i) * 0.3 + 0.1 + uTime * 0.02) * shaft * 0.12 * (0.6 + uBeat);
    }
    return col;
}
