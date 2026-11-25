// @preset {"energy": 3, "family": "flight3d", "heavy": true, "name": "Meme Odyssey", "labels": {"a": "chaos", "b": "look around", "c": "deep fry", "d": "color"}, "params": {"palette": 0, "glow": 0.5, "feedback": 0.12, "chroma": 0.2, "c": 0.3, "a": 0.4, "d": 0.0}}
// A journey through five meme worlds, 20 seconds each, each flying into the next through a swirling portal:
//   1 VAPORWAVE: a neon grid valley under a striped sunset, marble columns and chrome orbs floating by
//   2 MOAI AVENUE: towering stone heads; every beat is a "vine boom" punch-in, and their eyes fire lasers
//   3 ILLUMINATI CONFIRMED: a golden Sierpinski pyramid (an eye glints on every capstone) beneath the
//     Eye of Providence; the camera ends by flying into its pupil
//   4 GALAXY BRAIN: a brain that expands through four stages, glowing, electric, then a starlit brain at the
//     heart of a spiral galaxy
//   5 STONKS: up a canyon of neon candlestick charts and spinning gold coins, chasing the arrow to the moon
// Original takes on meme ideas, no copied characters. Unlike other presets, the worlds keep the colours the
// memes are known by (stonks green, Illuminati gold, moai stone), tinted by the palette; D shifts it.
// A = chaos (beat punch-ins and shake), C = deep fry (saturation, burn, permanent laser eyes). Heavy.

const float ZT = 20.0;    // seconds in each world
const float TR = 2.6;     // portal into the next world opens over the last TR seconds

// ---- shared bits ---------------------------------------------------------------------------

float sdBox(vec3 p, vec3 b) { vec3 q = abs(p) - b; return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0); }
float sdCapsule(vec3 p, vec3 a, vec3 b, float r) { vec3 pa = p - a, ba = b - a; return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)) - r; }
float smin(float a, float b, float k) { float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0); return mix(b, a, h) - k * h * (1.0 - h); }

vec3 camRay(vec2 p, vec3 fw, float roll, float fl) {
    vec3 rt = normalize(cross(fw, vec3(0.0, 1.0, 0.0)));
    vec3 up = cross(rt, fw);
    p = rot(roll) * p;
    return normalize(p.x * rt + p.y * up + fl * fw);
}

// ---- 1. VAPORWAVE: a neon grid sea under a striped sunset, marble columns floating by -------

float vwTerrain(vec2 xz) {
    float ax = abs(xz.x);
    float valley = pow(max(ax - 2.2, 0.0), 1.4) * 0.45;
    float m = noise(xz * vec2(0.25, 0.12)) * 1.2 + noise(xz * 0.6) * 0.3;
    return valley * (0.6 + m);
}

float vwColumns(vec3 p, out float isCol) {
    // two rows of floating Doric columns, slowly turning, plus chrome orbs
    vec3 q = p;
    q.x = abs(q.x) - 3.0;
    float cell = floor(q.z / 7.0);
    q.z = mod(q.z, 7.0) - 3.5;
    q.y -= 1.6 + 0.25 * sin(uTime * 0.6 + cell * 1.7);
    q.xz = rot(uTime * 0.2 + cell) * q.xz;
    float a = atan(q.z, q.x);
    float r = length(q.xz) - 0.26 - 0.018 * cos(a * 16.0);    // fluted shaft
    float shaft = max(r, abs(q.y) - 1.0);
    float cap = sdBox(q - vec3(0.0, 1.05, 0.0), vec3(0.4, 0.08, 0.4));
    float base = sdBox(q + vec3(0.0, 1.05, 0.0), vec3(0.38, 0.07, 0.38));
    float col = min(shaft, min(cap, base));
    vec3 o = p;
    o.z = mod(o.z + 3.5, 7.0) - 3.5;
    o.x = abs(o.x) - 1.6;
    o.y -= 2.4 + 0.3 * sin(uTime + floor((p.z + 3.5) / 7.0));
    float orb = length(o) - 0.28 - uBass * 0.05;
    isCol = step(col, orb);
    return min(col, orb);
}

vec3 vwSky(vec3 rd, float lt) {
    float h = rd.y;
    vec3 col = mix(glowpal(0.25 + uD) * 0.9, uPal[0] * 0.6 + glowpal(uD) * 0.25, smoothstep(0.0, 0.45, h));
    // stars
    vec2 sp = rd.xz / max(rd.y, 0.05) * 30.0;
    col += vec3(1.0) * smoothstep(0.985, 1.0, hash12(floor(sp))) * smoothstep(0.15, 0.4, h) * 0.8;
    // the sun: a big disc, warm to hot pink, with horizontal bands cut out of its lower half
    vec2 sq = vec2(rd.x, rd.y - 0.2) / 0.32;
    float r = length(sq);
    if (r < 1.0) {
        float y = sq.y;
        float band = fract(y * 7.0 + lt * 0.5);
        float cut = y < 0.15 ? step(band, mix(0.15, 0.7, smoothstep(0.15, -1.0, y))) : 0.0;
        vec3 sun = mix(glowpal(0.25 + uD), glowpal(0.5 + uD) * 1.3, smoothstep(-0.9, 0.9, y));
        vec3 gap = uPal[0] * 0.5 + glowpal(uD) * 0.15;      // the bands show the dusk behind the sun
        col = mix(col, mix(sun * (1.0 + uBeat * 0.4), gap, cut), smoothstep(1.0, 0.97, r));
    } else {
        col += glowpal(0.3 + uD) * 0.3 * exp(-(r - 1.0) * 3.0);   // sun glow
    }
    return col;
}

vec3 vaporwave(vec2 p, float lt) {
    vec3 ro = vec3(sin(lt * 0.21) * 0.6, 0.75 + 0.15 * sin(lt * 0.33), lt * 3.2 + (uPulse - uTime) * 1.5);
    vec3 fw = normalize(vec3(sin(lt * 0.13) * (0.1 + uB * 0.4), -0.06, 1.0));
    vec3 rd = camRay(p, fw, sin(lt * 0.17) * 0.06, 1.3);
    float t = 0.05, d = 1.0, isCol = 0.0, hitTerrain = 0.0;
    for (int i = 0; i < 90; i++) {
        vec3 pos = ro + rd * t;
        float dt = (pos.y - vwTerrain(pos.xz)) * 0.6;
        float dc = vwColumns(pos, isCol);
        d = min(dt, dc);
        hitTerrain = step(dt, dc);
        if (d < 0.002 * t || t > 60.0) break;
        t += d;
    }
    vec3 sky = vwSky(rd, lt);
    if (t > 60.0) return sky;
    vec3 pos = ro + rd * t;
    vec3 col;
    if (hitTerrain > 0.5) {
        // glowing grid lines, thicker with distance so they don't shimmer; the floor mirrors the sky
        vec2 g = abs(fract(pos.xz * vec2(1.0, 1.0) + vec2(0.5, 0.0)) - 0.5);
        float w = 0.02 + t * 0.002;
        float line = max(smoothstep(w, 0.0, g.x), smoothstep(w, 0.0, g.y));
        float pulse = 0.5 + 0.5 * smoothstep(0.85, 1.0, sin(pos.z * 0.5 - uPulse * 6.0));
        vec3 lc = mix(glowpal(0.25 + uD), glowpal(0.75 + uD), smoothstep(1.5, 6.0, abs(pos.x)));
        col = uPal[0] * 0.3 + lc * line * (1.1 + pulse * 0.8 + uBeat * 0.6);
        vec3 rr = reflect(rd, vec3(0.0, 1.0, 0.0));
        col += vwSky(rr, lt) * 0.35 * smoothstep(0.5, 0.0, pos.y);
    } else {
        vec2 e = vec2(0.002, 0.0);
        float dd;
        vec3 n = normalize(vec3(vwColumns(pos + e.xyy, dd) - vwColumns(pos - e.xyy, dd),
                                vwColumns(pos + e.yxy, dd) - vwColumns(pos - e.yxy, dd),
                                vwColumns(pos + e.yyx, dd) - vwColumns(pos - e.yyx, dd)));
        float fres = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        vec3 rr = reflect(rd, n);
        if (isCol > 0.5) {
            // pink-veined marble lit by the sunset
            float vein = smoothstep(0.55, 0.5, abs(noise(pos.xy * 6.0 + pos.z * 3.0) - 0.5) + 0.45);
            vec3 marble = mix(vec3(0.85, 0.8, 0.86), glowpal(0.25 + uD), 0.25 + vein * 0.4);
            float dif = max(dot(n, normalize(vec3(0.3, 0.4, 1.0))), 0.0);
            col = marble * (0.15 + 0.85 * dif) * mix(vec3(1.0), glowpal(0.3 + uD), 0.4) + vwSky(rr, lt) * fres * 0.6;
        } else {
            col = vwSky(rr, lt) * (0.6 + 0.4 * fres);   // chrome orbs mirror the sunset
        }
    }
    return mix(sky, col, exp(-t * 0.035));
}


// ---- 2. MOAI AVENUE: walking between stone heads that boom on the beat and fire laser eyes ---

float moaiHead(vec3 q) {
    // q: the statue's own frame, facing +x, ground at y = 0. Heavy brow, long nose, pout, jutting chin.
    float taper = 0.4 - (q.y - 2.0) * 0.04;
    float head = sdBox(q - vec3(0.0, 2.0, 0.0), vec3(taper, 1.05, 0.34)) - 0.1;
    float brow = sdBox(q - vec3(0.4, 2.62, 0.0), vec3(0.17, 0.1, 0.34)) - 0.04;
    float ny = clamp((2.5 - q.y) / 1.0, 0.0, 1.0);           // the nose widens and juts as it goes down
    float nose = sdBox(q - vec3(0.5 + ny * 0.2, 2.0, 0.0), vec3(0.08 + ny * 0.08, 0.52, 0.06 + ny * 0.09)) - 0.03;
    float lips = sdBox(q - vec3(0.6, 1.3, 0.0), vec3(0.07, 0.065, 0.19)) - 0.04;
    float chin = sdBox(q - vec3(0.52, 1.02, 0.0), vec3(0.14, 0.14, 0.28)) - 0.06;
    float ears = sdBox(vec3(q.x, q.y, abs(q.z)) - vec3(-0.02, 2.15, 0.46), vec3(0.08, 0.5, 0.05)) - 0.03;
    float body = sdBox(q - vec3(-0.05, 0.45, 0.0), vec3(0.44, 0.55, 0.56)) - 0.1;
    float d = smin(head, brow, 0.08);
    d = smin(d, nose, 0.07);
    d = smin(d, lips, 0.05);
    d = smin(d, chin, 0.12);
    d = smin(d, ears, 0.05);
    d = smin(d, body, 0.2);
    float eye = length((vec3(q.x, q.y, abs(q.z)) - vec3(0.5, 2.38, 0.19)) * vec3(1.0, 1.9, 1.0)) - 0.11;
    return max(d, -eye);                                     // deep sockets under the brow
}

const float MZ = 7.0;    // spacing along the avenue
const float MX = 3.8;    // distance of each row from the path
const float MS = 1.9;    // statue scale: they tower over the camera
const float MYAW = -0.55; // turned three-quarters toward whoever walks up the avenue

float moaiField(vec3 p) {
    vec3 q = vec3(abs(p.x), p.y, mod(p.z, MZ) - MZ * 0.5);
    q.x = MX - q.x;                                          // x now points to the path
    q.xz = rot(MYAW) * q.xz;
    float d = moaiHead(q / MS) * MS;
    float ground = p.y + 0.12 * noise(p.xz * 0.7) + 0.05 * noise(p.xz * 3.0);
    return min(d, ground);
}

// where a statue's eye is in the world, and which way it stares
void moaiEye(float cellZ, float side, float eyeSide, out vec3 e, out vec3 f) {
    vec2 lxz = vec2(0.5, 0.19 * eyeSide) * MS;               // eye in the statue frame (x to the path, z sideways)
    vec2 fxz = vec2(1.0, 0.0);
    mat2 r = rot(-MYAW);
    lxz = r * lxz;
    fxz = r * fxz;
    e = vec3(side * (MX - lxz.x), 2.38 * MS, cellZ + lxz.y);
    f = normalize(vec3(-side * fxz.x, -0.04, fxz.y));
}

vec3 moai(vec2 p, float lt) {
    float boom = uBeat * uBeat;                              // "vine boom": every beat punches the view in
    vec3 ro = vec3(0.5 * sin(lt * 0.3), 1.45 + 0.04 * sin(lt * 2.0), lt * 1.7 + (uPulse - uTime));
    vec3 fw = normalize(vec3(sin(lt * 0.23) * (0.2 + uB * 0.5), 0.2 + 0.06 * sin(lt * 0.4), 1.0));
    vec3 rd = camRay(p, fw, 0.0, 1.15 + boom * 0.4);
    float t = 0.05, d = 1.0;
    for (int i = 0; i < 120; i++) {
        d = moaiField(ro + rd * t);
        if (d < 0.002 * t || t > 55.0) break;
        t += d * 0.8;
    }
    // dusk sky: a huge moon and stars over the island
    vec3 sky = mix(glowpal(0.25 + uD) * 0.18 + uPal[1] * 0.25, uPal[0] * 0.4, smoothstep(-0.05, 0.45, rd.y));
    vec3 haze = sky;
    vec2 mq = vec2(rd.x - 0.3, rd.y - 0.42);
    float moon = length(mq);
    sky += vec3(1.0, 0.95, 0.85) * smoothstep(0.12, 0.115, moon) * (0.75 + 0.25 * noise(mq * 40.0));
    sky += glowpal(0.5 + uD) * 0.12 * exp(-moon * 5.0);
    vec2 sp = rd.xy / max(rd.z, 0.1) * 70.0;
    sky += smoothstep(0.985, 1.0, hash12(floor(sp))) * smoothstep(0.05, 0.3, rd.y);
    vec3 col = sky;
    if (t < 55.0) {
        vec3 pos = ro + rd * t;
        vec2 e = vec2(0.004, 0.0);
        vec3 n = normalize(vec3(moaiField(pos + e.xyy) - moaiField(pos - e.xyy),
                                moaiField(pos + e.yxy) - moaiField(pos - e.yxy),
                                moaiField(pos + e.yyx) - moaiField(pos - e.yyx)));
        float stone = 0.55 + 0.45 * noise(pos.xy * 7.0 + pos.z * 3.0);   // pitted volcanic tuff
        vec3 alb = mix(vec3(0.34, 0.33, 0.32), glowpal(0.6 + uD) * 0.4, 0.1) * stone;
        if (pos.y < 0.25) alb = mix(vec3(0.07, 0.11, 0.05), glowpal(0.8 + uD) * 0.2, 0.35) * stone;
        vec3 ld = normalize(vec3(-0.45, 0.55, -0.7));        // warm dusk light from behind the camera
        vec3 lm = normalize(vec3(0.3, 0.45, 0.85));           // the moon ahead, as a cold rim
        float dif = max(dot(n, ld), 0.0);
        float ao = clamp(moaiField(pos + n * 0.25) / 0.25, 0.0, 1.0);
        col = alb * (0.08 + dif * mix(vec3(1.0, 0.85, 0.7), glowpal(0.5 + uD), 0.15)) * (0.4 + 0.6 * ao);
        col += glowpal(0.75 + uD) * pow(max(dot(n, lm), 0.0), 3.0) * 0.35 * ao;
        col += glowpal(0.25 + uD) * pow(1.0 - max(dot(n, -rd), 0.0), 3.0) * 0.2 * ao;
        col = mix(haze, col, exp(-t * 0.035));
    }
    // laser eyes: exact ray-to-beam distance for the statues ahead (thin beams are easy to step over)
    float fire = clamp(uBeat * (0.6 + uC) + uC * 0.3, 0.0, 1.6);   // deep fry = permanent laser eyes
    if (fire > 0.01) {
        vec3 lc = mix(vec3(1.0, 0.06, 0.03), glowpal(0.25 + uD), 0.2);
        float c0 = floor(ro.z / MZ);
        float glow = 0.0, core = 0.0;
        for (int i = -1; i < 7; i++) {
            float cz = (c0 + float(i) + 0.5) * MZ;
            for (int k = 0; k < 4; k++) {
                vec3 e, f;
                moaiEye(cz, k < 2 ? -1.0 : 1.0, mod(float(k), 2.0) * 2.0 - 1.0, e, f);
                vec3 w0 = ro - e;
                float b = dot(rd, f), dd = dot(rd, w0), ee = dot(f, w0);
                float den = max(1.0 - b * b, 1e-4);
                float sr = max((b * ee - dd) / den, 0.0);
                float sl = clamp((ee - b * dd) / den, 0.0, 40.0);
                vec3 cp = e + f * sl;
                sr = max(dot(cp - ro, rd), 0.0);
                if (sr > t) continue;                        // hidden behind stone
                float dist = length(ro + rd * sr - cp);
                float fall = 1.0 / (1.0 + sr * 0.08);
                float w = 1.0 + sr * 0.25;
                glow += (exp(-dist * 90.0 / w) * 1.6 + exp(-dist * 10.0 / w) * 0.12) * fall;
                core += exp(-dist * 300.0 / w) * fall;
                // flare at the eye itself
                float de = length(cross(e - ro, rd));
                if (dot(e - ro, rd) < t + 0.2) glow += exp(-de * 40.0) * 1.5 * fall;
            }
        }
        col += lc * glow * fire + vec3(1.0, 0.9, 0.85) * min(core, 1.0) * fire;   // white-hot cores
    }
    return col;
}


// ---- 3. ILLUMINATI CONFIRMED: a golden Sierpinski pyramid, an eye on every capstone --------

float sdPyramid(vec3 p, float h) {
    // iq's square pyramid: base 1 x 1 centred on the origin, apex at height h
    float m2 = h * h + 0.25;
    p.xz = abs(p.xz);
    p.xz = (p.z > p.x) ? p.zx : p.xz;
    p.xz -= 0.5;
    vec3 q = vec3(p.z, h * p.y - 0.5 * p.x, h * p.x + 0.5 * p.y);
    float s = max(-q.x, 0.0);
    float t = clamp((q.y - 0.5 * p.z) / (m2 + 0.25), 0.0, 1.0);
    float a = m2 * (q.x + s) * (q.x + s) + q.y * q.y;
    float b = m2 * (q.x + 0.5 * t) * (q.x + 0.5 * t) + (q.y - m2 * t) * (q.y - m2 * t);
    float d2 = min(q.y, -q.x * m2 - q.y * 0.5) > 0.0 ? 0.0 : min(a, b);
    return sqrt((d2 + q.z * q.z) / m2) * sign(max(q.z, -p.y));
}

const float PH = 0.75;  // pyramid height for a base of 1
float iTrap;

float sierpinski(vec3 p) {
    // five half-size copies: four base corners and the apex
    float s = 1.0;
    iTrap = 0.0;
    for (int i = 0; i < 6; i++) {
        vec3 c = vec3(0.0, PH * 0.5, 0.0);                       // apex copy
        float best = dot(p - c, p - c);
        vec3 corner = vec3(sign(p.x) * 0.25, 0.0, sign(p.z) * 0.25);
        float dc = dot(p - corner, p - corner);
        if (dc < best) { best = dc; c = corner; } else { iTrap += 1.0; }
        p = (p - c) * 2.0;
        s *= 2.0;
    }
    return sdPyramid(p, PH) / s;
}

float illuScene(vec3 p) {
    float d = sierpinski(p / 4.0) * 4.0;
    return min(d, p.y + 0.002);
}

float sdEqTri(vec2 p) {
    const float k = 1.7320508;
    p.x = abs(p.x) - 1.0;
    p.y = p.y + 1.0 / k;
    if (p.x + k * p.y > 0.0) p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
    p.x -= clamp(p.x, -2.0, 0.0);
    return -length(p) * sign(p.y);
}

// the Eye of Providence: a glowing triangle with an almond eye. u: its own coords (triangle half-width 1)
vec3 providence(vec2 u, float lt, out float a) {
    float tri = sdEqTri(u);
    vec3 gold = mix(vec3(1.0, 0.78, 0.3), glowpal(0.5 + uD), 0.3);
    vec3 col = gold * (exp(-abs(tri) * 30.0) * 2.0 + exp(-abs(tri) * 5.0) * 0.4);   // the burning outline
    a = smoothstep(0.02, -0.02, tri);
    col += gold * a * 0.12;
    // the eye, with a lid that blinks now and then
    vec2 e = (u - vec2(0.0, -0.12)) / 0.62;
    float open = 0.5 * (1.0 - smoothstep(0.9, 1.0, pow(abs(sin(lt * 0.45)), 8.0)));
    float lidEdge = (1.0 - e.x * e.x) * open - abs(e.y);
    float white = smoothstep(0.0, 0.03, lidEdge);
    vec2 ip = e - vec2(0.18 * sin(lt * 0.6), 0.03 * sin(lt * 0.9));
    float ir = length(ip);
    vec3 eyeC = vec3(0.95, 0.92, 0.88);
    vec3 iris = glowpal(0.75 + uD + ir * 0.6) * (0.7 + 0.5 * sin(atan(ip.y, ip.x) * 28.0) * smoothstep(0.34, 0.12, ir));
    eyeC = mix(eyeC, iris, smoothstep(0.36, 0.32, ir));
    eyeC = mix(eyeC, vec3(0.0), smoothstep(0.15 + uBass * 0.06, 0.12 + uBass * 0.06, ir));   // pupil breathes with the bass
    eyeC += vec3(1.0) * smoothstep(0.07, 0.0, length(ip - vec2(0.09, 0.09)));
    col = mix(col, eyeC * 1.3, white * a);
    col += gold * exp(-abs(lidEdge) * 40.0) * a * 1.5;   // glowing lids
    return col;
}

vec3 illuminati(vec2 p, float lt) {
    // circle the pyramid, rising, and finally fly into the eye's pupil
    float f = clamp(lt / ZT, -0.2, 1.0);
    vec3 eyeP = vec3(0.0, 3.55 + 0.05 * sin(lt * 1.5), 0.0);
    float ang = 0.6 + f * 3.0 + sin(lt * 0.3) * 0.15 * uB;
    float dist = mix(5.8, 0.35, smoothstep(0.0, 1.0, f) * smoothstep(0.0, 1.0, f));
    vec3 ro = vec3(sin(ang) * dist, mix(0.45, 3.55, smoothstep(0.2, 0.9, f)), -cos(ang) * dist);
    vec3 target = mix(vec3(0.0, 1.4, 0.0), eyeP, smoothstep(0.25, 0.75, f));
    vec3 fw = normalize(target - ro);
    vec3 rd = camRay(p, fw, 0.0, 1.4);
    float t = 0.05, d = 1.0;
    float glowAcc = 0.0;
    for (int i = 0; i < 110; i++) {
        vec3 pos = ro + rd * t;
        d = illuScene(pos);
        glowAcc += exp(-d * 30.0) * 0.01;
        if (d < 0.0012 * t || t > 30.0) break;
        t += d * 0.9;
    }
    vec3 toEye = normalize(eyeP - ro);
    vec3 col = uPal[0] * 0.5 + glowpal(0.5 + uD) * 0.05;
    vec2 sp = vec2(atan(rd.x, rd.z), rd.y) * 80.0;
    col += smoothstep(0.985, 1.0, hash12(floor(sp))) * 0.7;
    if (t < 30.0) {
        vec3 pos = ro + rd * t;
        vec2 e = vec2(0.002, 0.0);
        vec3 n = normalize(vec3(illuScene(pos + e.xyy) - illuScene(pos - e.xyy),
                                illuScene(pos + e.yxy) - illuScene(pos - e.yxy),
                                illuScene(pos + e.yyx) - illuScene(pos - e.yyx)));
        illuScene(pos);
        float tr = iTrap;
        vec3 gold = mix(vec3(1.0, 0.72, 0.22), glowpal(0.5 + uD + tr * 0.03), 0.3);
        vec3 l = normalize(eyeP - pos);
        float dif = max(dot(n, l), 0.0);
        float ao = clamp(illuScene(pos + n * 0.06) / 0.06, 0.0, 1.0);
        float spec = pow(max(dot(reflect(rd, n), l), 0.0), 24.0);
        col = gold * (0.12 + 0.25 * max(n.y, 0.0) + dif * 1.6 / (1.0 + dot(eyeP - pos, eyeP - pos) * 0.04)) * (0.4 + 0.6 * ao);
        col += vec3(1.0, 0.9, 0.7) * spec * 0.7 * ao;
        if (pos.y < 0.01) col = vec3(0.12, 0.09, 0.06) * (0.3 + dif * 0.5 / (1.0 + dot(eyeP - pos, eyeP - pos) * 0.1));  // desert floor
        // a tiny eye glints on every little capstone: illuminati confirmed, all the way down
        col += glowpal(0.75 + uD) * smoothstep(5.5, 6.0, tr) * pow(max(dot(n, -rd), 0.0), 4.0) * (0.5 + uHigh * 2.0) * 0.6;
        col = mix(uPal[0] * 0.5, col, exp(-t * 0.03));
    }
    col += glowpal(0.5 + uD) * glowAcc * 0.4;
    // radiant beams fanning out from the eye
    vec3 rt = normalize(cross(fw, vec3(0.0, 1.0, 0.0))), up = cross(rt, fw);
    vec3 v = eyeP - ro;
    float vz = dot(v, fw);
    if (vz > 0.05) {
        vec2 c = vec2(dot(v, rt), dot(v, up)) / vz * 1.4;    // the eye's position on screen
        float s = 1.4 * 0.42 / vz;                           // and its size
        vec2 u = (p - c) / s;
        float ra = atan(u.y, u.x), rr = length(u);
        col += glowpal(0.5 + uD) * (0.5 + 0.5 * sin(ra * 16.0 + lt * 0.8)) * exp(-rr * 0.45) * smoothstep(0.9, 1.6, rr) * 0.6 * (1.0 + uBeat * 1.2);
        float a;
        vec3 pc = providence(u, lt, a);
        col = mix(col, pc, a) + pc * (1.0 - a);
    }
    return col;
}

// ---- 4. GALAXY BRAIN: a brain that expands, stage by stage, into a cosmos -------------------

float gyroid(vec3 p) { return dot(sin(p), cos(p.yzx)); }
float bFold;   // how deep in a fold (sulcus) the last brain() point was

float brain(vec3 p, float grow) {
    p /= grow;
    vec3 q = p;
    q.x = abs(q.x) - 0.44;                                   // two hemispheres with the fissure between
    float squash = 1.0 + smoothstep(0.0, -0.5, p.y) * 0.5;   // flatter underneath
    vec3 r = vec3(0.52, 0.6 / squash, 0.82);
    float hemi = (length(q / r) - 1.0) * min(r.x, min(r.y, r.z));
    float cereb = (length((p - vec3(0.0, -0.42, -0.55)) / vec3(0.6, 0.25, 0.32)) - 1.0) * 0.25;
    float stem = sdCapsule(p, vec3(0.0, -0.4, -0.25), vec3(0.0, -1.0, -0.35), 0.11);
    float g = gyroid(p * 11.0 + vec3(0.0, 0.0, 1.3));
    bFold = abs(g);
    float d = min(hemi + 0.035 * (1.0 - smoothstep(0.0, 0.5, abs(g))), cereb + 0.015 * abs(gyroid(p * 24.0)));
    d = min(d, stem);
    return d * grow;
}

vec3 galaxyBrain(vec2 p, float lt) {
    float st = clamp(lt / (ZT * 0.25), -1.0, 4.0);           // 0..4: small brain, glowing, electric, cosmic
    float glowS = smoothstep(0.8, 1.6, st), elecS = smoothstep(1.8, 2.6, st), cosS = smoothstep(2.7, 3.5, st);
    float grow = 1.0 + 0.35 * glowS + 0.25 * cosS + uBass * 0.04;
    float ang = lt * 0.22 + 0.5 + sin(lt * 0.3) * 0.2 * uB;
    float dist = mix(3.0, 6.4, smoothstep(0.5, 3.6, st));
    vec3 ro = vec3(sin(ang) * dist, 0.6 + 0.9 * cosS + 0.3 * sin(lt * 0.25), cos(ang) * dist);
    vec3 fw = normalize(vec3(0.0, -0.05, 0.0) - ro);
    vec3 rd = camRay(p, fw, 0.1 * sin(lt * 0.2), 1.5);
    float t = 0.1, d = 1.0, aura = 0.0;
    for (int i = 0; i < 90; i++) {
        vec3 pos = ro + rd * t;
        d = brain(pos, grow);
        aura += exp(-max(d, 0.0) * 12.0) * 0.012;
        if (d < 0.0015 * t || t > 14.0) break;
        t += d * 0.7;
    }
    // deep space: nebula and stars, brighter as the brain ascends
    vec3 bg = uPal[0] * 0.4;
    float neb = fbm(vec2(atan(rd.x, rd.z) * 2.0, rd.y * 3.0) + lt * 0.02);
    bg += glowpal(neb + uD + 0.6) * neb * neb * (0.06 + 0.2 * cosS);
    vec2 sp = vec2(atan(rd.x, rd.z), asin(clamp(rd.y, -1.0, 1.0))) * 90.0;
    bg += smoothstep(0.98, 1.0, hash12(floor(sp))) * (0.4 + 0.6 * cosS);
    // the galaxy: a spiral disc around the brain, appearing in the final stage
    vec3 col = bg;
    float tPlane = (-0.15 - ro.y) / rd.y;
    vec3 gal = vec3(0.0);
    if (tPlane > 0.0 && cosS > 0.0) {
        vec2 g = (ro + rd * tPlane).xz;
        float r = length(g), a = atan(g.y, g.x);
        float arms = pow(0.5 + 0.5 * cos(2.0 * (a - log(r + 0.01) * 2.2) - lt * 0.25), 3.0);
        float dens = exp(-r * 0.45) * (0.3 + arms * (0.7 + 0.6 * fbm(g * 2.0))) * smoothstep(0.9, 1.6, r);
        dens += smoothstep(0.985, 1.0, hash12(floor(g * 40.0))) * exp(-r * 0.3) * 2.0;   // star clusters
        gal = glowpal(r * 0.08 + uD + 0.2) * dens * cosS * 2.6;
    }
    if (t < 14.0) {
        vec3 pos = ro + rd * t;
        vec2 e = vec2(0.002, 0.0);
        vec3 n = normalize(vec3(brain(pos + e.xyy, grow) - brain(pos - e.xyy, grow),
                                brain(pos + e.yxy, grow) - brain(pos - e.yxy, grow),
                                brain(pos + e.yyx, grow) - brain(pos - e.yyx, grow)));
        brain(pos, grow);
        float fold = 1.0 - smoothstep(0.0, 0.45, bFold);
        vec3 ld = normalize(vec3(0.5, 0.8, 0.4));
        float wrap = max(dot(n, ld) * 0.6 + 0.4, 0.0);       // soft, fleshy wrap lighting
        float fres = pow(1.0 - max(dot(n, -rd), 0.0), 2.5);
        vec3 flesh = mix(vec3(0.95, 0.55, 0.6), glowpal(0.25 + uD), 0.3);
        vec3 c = flesh * wrap * (1.0 - fold * 0.55) * (1.0 - cosS * 0.7);
        c += flesh * fres * 0.4;
        // stage 2: the folds light up from within
        c += glowpal(0.75 + uD + pos.y * 0.3) * fold * glowS * (0.6 + uMid * 0.8);
        // stage 3: electric sparks racing along the folds, flaring on the beat
        float spark = pow(0.5 + 0.5 * sin(dot(pos, vec3(9.0, 7.0, 11.0)) - lt * 9.0), 12.0) * fold;
        c += vec3(0.8, 0.9, 1.0) * spark * elecS * (1.0 + uBeat * 3.0);
        // stage 4: the brain turns to starlight
        c += glowpal(0.6 + uD + fres) * fres * cosS * 1.5;
        c += smoothstep(0.97, 1.0, hash12(floor(pos.xy * 60.0 + pos.z * 37.0))) * cosS * 1.5;
        col = c;
        if (tPlane > 0.0 && tPlane < t) col += gal;          // galaxy in front of the brain
    } else {
        col += gal;
    }
    col += glowpal(0.7 + uD) * aura * (0.2 + glowS + elecS * 1.5 + uBeat * elecS);
    // stage 3+: radiant rays burst out from behind the brain
    vec2 sc = p;
    col += glowpal(0.5 + uD) * pow(0.5 + 0.5 * sin(atan(sc.y, sc.x) * 20.0 + lt), 6.0) * exp(-length(sc) * 1.5) * elecS * 0.5;
    return col;
}

// ---- 5. STONKS: up a canyon of candlestick charts, chasing a giant arrow to the moon ---------

const float CZ = 0.7;    // one candle per CZ along the chart

float price(float i, float row) {
    // a rising random walk: the trend always wins
    return i * 0.09 + 1.2 * noise(vec2(i * 0.21, row * 3.7)) + 0.5 * noise(vec2(i * 0.9, row * 1.3));
}

float sCandle;   // +1 green (up), -1 red (down) for the last stonks() hit
float sCoin;
float sEdge;     // how close the last point is to a candle's edges (for the neon outlines)

float stonks(vec3 p) {
    float d = 1e3;
    // six rows of charts on each side of the canyon
    float side = sign(p.x);
    float ax = abs(p.x) - 1.6;
    float row = clamp(floor(ax / 0.9 + 0.5), 0.0, 5.0);
    float rx = ax - row * 0.9;
    float i = floor(p.z / CZ);
    float lz = p.z - (i + 0.5) * CZ;
    float rowId = row + step(0.0, side) * 7.0;
    float o = price(i - 1.0, rowId) + row * 1.15, c = price(i, rowId) + row * 1.15;   // outer charts sit higher: a canyon
    float lo = min(o, c) - 0.15 - 0.2 * hash12(vec2(i, rowId)), hi = max(o, c) + 0.15 + 0.25 * hash12(vec2(rowId, i));
    float bounce = uBeat * 0.15 * hash12(vec2(i, rowId + 3.0));
    vec3 bq = vec3(rx, p.y - (o + c) * 0.5 - bounce, lz), bb = vec3(0.16, max(abs(c - o) * 0.5, 0.02), 0.2);
    float body = sdBox(bq, bb);
    vec3 en = min(abs(bq) / bb, 1.0);
    sEdge = en.x + en.y + en.z - max(en.x, max(en.y, en.z)) - min(en.x, min(en.y, en.z));   // the middle one
    float wick = sdBox(vec3(rx, p.y - (lo + hi) * 0.5 - bounce, lz), vec3(0.025, (hi - lo) * 0.5, 0.025));
    float cd = min(body, wick);
    if (ax > -0.5) d = cd;
    sCandle = c >= o ? 1.0 : -1.0;
    // money printer go brrr: gold coins spinning down the middle of the canyon
    vec3 q = p;
    float ci = floor(q.z / 2.3);
    q.z -= (ci + 0.5) * 2.3;
    q.x -= 0.9 * sin(ci * 2.1);
    q.y -= 3.0 + ci * 0.21 * 2.3 / CZ * 0.09 + 0.8 * sin(ci * 1.3 + uTime);
    q.xz = rot(uTime * 2.0 + ci) * q.xz;
    float coin = max(length(q.xy) - 0.32, abs(q.z) - 0.035) - 0.01;
    sCoin = step(coin, d);
    return min(d, coin);
}

vec3 stonksWorld(vec2 p, float lt) {
    float z = lt * 3.2 + (uPulse - uTime) * 1.5;
    float trend = z / CZ * 0.09;
    vec3 ro = vec3(0.3 * sin(lt * 0.4), trend + 2.0, z);
    vec3 fw = normalize(vec3(sin(lt * 0.3) * (0.1 + uB * 0.35), 0.16, 1.0));
    vec3 rd = camRay(p, fw, sin(lt * 0.25) * 0.08, 1.3);
    float t = 0.05, d = 1.0, haze = 0.0;
    for (int i = 0; i < 110; i++) {
        d = stonks(ro + rd * t);
        haze += exp(-d * 8.0) * 0.012 * (sCandle > 0.0 ? 1.0 : 0.4);
        if (d < 0.0015 * t || t > 40.0) break;
        t += d * 0.6;
    }
    // night sky over the market, and the moon we're going to
    vec3 sky = mix(uPal[0] * 0.5 + vec3(0.0, 0.06, 0.03), vec3(0.0, 0.015, 0.01), smoothstep(-0.2, 0.5, rd.y));
    sky += vec3(0.1, 0.9, 0.4) * 0.12 * exp(-abs(rd.y + 0.05) * 8.0);   // a green glow on the horizon
    vec2 mq = vec2(rd.x + 0.15, rd.y - 0.38);
    sky += vec3(1.0, 0.97, 0.9) * smoothstep(0.1, 0.095, length(mq)) * (0.8 + 0.2 * noise(mq * 50.0));
    sky += vec3(0.7, 1.0, 0.8) * 0.08 * exp(-length(mq) * 6.0);
    vec2 sp = rd.xy / max(rd.z, 0.1) * 70.0;
    sky += smoothstep(0.985, 1.0, hash12(floor(sp))) * smoothstep(0.0, 0.3, rd.y) * 0.8;
    vec3 green = mix(vec3(0.1, 1.0, 0.35), glowpal(0.75 + uD), 0.2), red = mix(vec3(1.0, 0.12, 0.15), glowpal(0.25 + uD), 0.2);
    vec3 col = sky;
    if (t < 40.0) {
        vec3 pos = ro + rd * t;
        stonks(pos);
        float isCoin = sCoin, up = sCandle;
        vec2 e = vec2(0.002, 0.0);
        vec3 n = normalize(vec3(stonks(pos + e.xyy) - stonks(pos - e.xyy), stonks(pos + e.yxy) - stonks(pos - e.yxy),
                                stonks(pos + e.yyx) - stonks(pos - e.yyx)));
        float fres = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        if (isCoin > 0.5) {
            vec3 gold = vec3(1.0, 0.78, 0.28);
            col = gold * (0.25 + max(dot(n, normalize(vec3(0.3, 0.8, -0.4))), 0.0)) + gold * fres + vec3(1.0) * pow(max(dot(reflect(rd, n), normalize(vec3(0.3, 0.8, -0.4))), 0.0), 40.0);
        } else {
            // glass candles glowing from their edges: green up, red down
            vec3 cc = up > 0.0 ? green : red;
            vec3 ld = normalize(vec3(0.2, 0.7, -0.6));
            float spec = pow(max(dot(reflect(rd, n), ld), 0.0), 50.0);
            float edge = smoothstep(0.82, 0.97, sEdge);
            col = cc * (0.03 + 0.12 * max(dot(n, ld), 0.0)) + cc * fres * 0.5 + vec3(1.0) * spec * 0.5;
            col += cc * edge * 1.6;                                       // neon outlines
            col += cc * 0.25 * pow(0.5 + 0.5 * sin(pos.y * 3.0 - lt * 4.0), 4.0);   // a ticker pulse running up each candle
            col *= 0.85 + uBeat * 0.7;
        }
        col = mix(sky, col, exp(-t * 0.05));
    }
    col += green * haze * 0.5;
    // the STONKS arrow: a giant glowing zig-zag rising ahead, always just out of reach
    float tA = 30.0;
    vec3 ap = ro + rd * (tA / max(rd.z, 0.05));
    vec2 a2 = vec2(ap.x - ro.x, ap.y - ro.y) * 0.25 - vec2(-1.2, 0.0);
    vec2 pts[5];
    pts[0] = vec2(0.0, 0.0); pts[1] = vec2(0.9, 1.0); pts[2] = vec2(1.4, 0.55); pts[3] = vec2(2.3, 1.9); pts[4] = vec2(2.9, 1.5);
    float da = 1e3;
    float flow = 0.0;
    for (int k = 0; k < 3; k++) {
        vec2 aa = pts[k] + vec2(-1.2, -0.6), bb = pts[k + 1] + vec2(-1.2, -0.6);
        if (k == 2) bb = vec2(2.6, 2.4) + vec2(-1.2, -0.6) - vec2(0.15, 0.15);
        vec2 pa = a2 - aa, ba = bb - aa;
        float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
        float dk = length(pa - ba * h);
        if (dk < da) { da = dk; flow = float(k) + h; }
    }
    vec2 tip = vec2(2.6, 2.4) + vec2(-1.2, -0.6);
    vec2 dir = normalize(vec2(0.9, 1.35));
    vec2 lp = a2 - tip;
    vec2 tl = vec2(dot(lp, dir), dot(lp, vec2(-dir.y, dir.x)));
    float head = max(-tl.x - 0.45, abs(tl.y) - (-tl.x) * 0.75);   // arrowhead triangle
    float arrow = min(da - 0.09, head);
    if (rd.z > 0.0) {
        float pulse = 0.5 + 0.5 * sin(flow * 4.0 - lt * 6.0);
        col = mix(col, green * (1.2 + pulse * 0.6 + uBeat), smoothstep(0.01, -0.01, arrow));
        col += green * exp(-max(arrow, 0.0) * 18.0) * 0.6;
    }
    return col;
}

// ---- the journey -------------------------------------------------------------------------

vec3 world(int z, vec2 p, float lt) {
    if (z == 0) return vaporwave(p, lt);
    if (z == 1) return moai(p, lt);
    if (z == 2) return illuminati(p, lt);
    if (z == 3) return galaxyBrain(p, lt);
    return stonksWorld(p, lt);
}

vec3 scene(vec2 p, vec2 uv) {
    // CHAOS (knob A): every beat punches the view in and shakes it
    p *= 1.0 - uBeat * uBeat * uA * 0.14;
    p += uA * uBeat * 0.025 * vec2(sin(uRealTime * 47.0), cos(uRealTime * 41.0));
    float k = floor(uTime / ZT);
    float lt = uTime - k * ZT;
    int z = int(mod(k, 5.0));
    int zn = int(mod(k + 1.0, 5.0));
    float tr = smoothstep(ZT - TR, ZT, lt);           // how far the portal has opened
    float R = tr * tr * 2.3;                           // portal radius, growing to cover the screen
    float r = length(p);
    // the portal swirls: inside it the next world spins into place
    float inside = smoothstep(R + 0.015, R - 0.015, r);
    vec3 col = vec3(0.0);
    if (inside < 1.0) col = world(z, p, lt);
    if (inside > 0.0) {
        vec2 q = rot((1.0 - tr) * 2.5 * (1.0 - r / max(R, 0.01))) * p * (0.6 + 0.4 * tr);
        col = mix(col, world(zn, q, lt - ZT), inside);
    }
    float rim = exp(-abs(r - R) * 40.0) * step(0.001, tr) * (1.0 - tr * 0.6);
    col += glowpal(atan(p.y, p.x) / TAU + uTime * 0.2 + uD) * rim * 2.0;
    // DEEP FRY (knob C): crank saturation and contrast, burn toward orange, flare the highlights
    float l = dot(col, vec3(0.299, 0.587, 0.114));
    vec3 fried = mix(vec3(l), col, 1.0 + 1.8 * uC);
    fried = pow(max(fried, 0.0), vec3(1.0 + 0.5 * uC)) * (1.0 + 0.8 * uC);
    fried *= mix(vec3(1.0), vec3(1.25, 1.0, 0.7), uC * 0.8);
    fried += vec3(1.0, 0.6, 0.2) * smoothstep(0.7, 1.4, l) * uC * 0.5;
    return mix(col, max(fried, 0.0), smoothstep(0.0, 0.3, uC));
}
