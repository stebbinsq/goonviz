// @preset {"energy": 2, "family": "flight3d", "heavy": true, "ship": true, "name": "Wasteland", "labels": {"a": "throttle", "b": "steer", "c": "altitude", "d": "radiation"}, "params": {"palette": 5, "glow": 0.45, "feedback": 0.0, "chroma": 0.03, "a": 0.45, "b": 0.5, "c": 0.3, "d": 0.3}}
// You fly a ship over a nuclear lava wasteland, chase-cam. The app keeps the ship's position and heading
// (uShip), so it really steers: knob B (centre = straight) or the left/right arrow keys turn it, the camera
// lags into the turn and the ship banks; knob A is the throttle (it still surges on bass hits); knob C or
// up/down set the altitude (it always clears the ridges ahead). Below: a sea of lava under a cracked black
// crust (Voronoi plates, glowing seams, open channels where it runs deep), jagged basalt ridges lit from
// beneath, embers streaming up past the ship, a ceiling of ash lit orange by the lava, and volcanic
// lightning on the beat. RADIATION (D): toxic green vents and pools spread until the whole sea glows green.

const float LAVA = 0.0;

vec3 hash33e(vec3 p3) {
    p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}
const float TMAX = 42.0;

// ---------------------------------------------------------------- terrain
// large-scale rock: plateaus and ridge lines, about half the land under the lava
float rockBase(vec2 q) {
    float n = noise(q * 0.09) * 0.55 + noise(q * 0.21 + 3.7) * 0.3 + noise(q * 0.47 + 9.1) * 0.15;
    float r = 1.0 - abs(noise(q * 0.13 + 1.3) * 2.0 - 1.0);
    return (n - 0.5) * 3.4 + r * r * 1.3 - 0.68;
}
// with jagged basalt detail; lod (0..4) fades the octaves in, so distant ground is cheap and nothing pops
float rockH(vec2 q, float lod) {
    float h = rockBase(q);
    float a = 0.2, f = 1.1;
    mat2 m = mat2(0.8, 0.6, -0.6, 0.8);
    for (int i = 0; i < 4; i++) {
        float w = clamp(lod - float(i), 0.0, 1.0);
        if (w <= 0.0) break;
        float rn = 1.0 - abs(noise(q * f + float(i) * 7.1) * 2.0 - 1.0);
        h += (rn * rn - 0.45) * a * w;
        a *= 0.45; f *= 2.3; q = m * q;
    }
    return h;
}
float lodAt(float t) { return clamp(4.6 - t * 0.22, 0.6, 4.0); }
float ground(vec2 q, float lod) { return max(rockH(q, lod), LAVA); }

vec3 groundNormal(vec2 q, float e, float lod) {
    float hx = ground(q + vec2(e, 0.0), lod) - ground(q - vec2(e, 0.0), lod);
    float hz = ground(q + vec2(0.0, e), lod) - ground(q - vec2(0.0, e), lod);
    return normalize(vec3(-hx, 2.0 * e, -hz));
}

// crust plates: distance to the nearest seam, and the plate's id
vec2 voronoi(vec2 x) {
    vec2 n = floor(x), f = fract(x), mg = vec2(0.0), mr = vec2(0.0);
    float md = 8.0;
    for (int j = -1; j <= 1; j++)
    for (int i = -1; i <= 1; i++) {
        vec2 g = vec2(float(i), float(j));
        vec2 r = g + hash22(n + g) - f;
        float d = dot(r, r);
        if (d < md) { md = d; mr = r; mg = g; }
    }
    md = 8.0;
    for (int j = -1; j <= 1; j++)
    for (int i = -1; i <= 1; i++) {
        vec2 g = mg + vec2(float(i), float(j));
        vec2 r = g + hash22(n + g) - f;
        if (dot(mr - r, mr - r) > 1e-5) md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
    }
    return vec2(md, hash12(n + mg));
}

// ---------------------------------------------------------------- colour
// incandescence: dull red, orange, yellow, white-hot
vec3 heat(float T) {
    T = max(T, 0.0);
    return vec3(1.0, 0.16, 0.02) * smoothstep(0.02, 0.35, T) * 1.1
         + vec3(1.0, 0.45, 0.08) * smoothstep(0.3, 0.7, T) * 1.4
         + vec3(1.0, 0.85, 0.5) * smoothstep(0.72, 1.0, T) * 2.0;
}
// the same, irradiated: sickly green
vec3 toxic(float T) {
    T = max(T, 0.0);
    return vec3(0.2, 1.0, 0.1) * smoothstep(0.02, 0.4, T) * 0.9
         + vec3(0.55, 1.0, 0.3) * smoothstep(0.35, 0.75, T) * 1.3
         + vec3(0.9, 1.0, 0.8) * smoothstep(0.72, 1.0, T) * 1.8;
}
// how irradiated this part of the world is (D spreads it from scattered zones to everywhere)
float radAt(vec2 q) {
    // D grows the irradiated zones (fully green inside, so they never mix into a muddy yellow) until they cover everything
    float thr = mix(1.02, 0.3, uD);
    float n = noise(q * 0.05 + 40.0) * 0.7 + noise(q * 0.13 + 7.0) * 0.3;
    return max(smoothstep(thr, thr + 0.04, n), smoothstep(0.85, 0.97, uD));
}
vec3 glowCol(float T, float rad) { return mix(heat(T), toxic(T), rad); }

// ---------------------------------------------------------------- sky
float gBolt;     // lightning this frame: 0..1
float gBoltAz;   // its bearing

vec3 skyCol(vec3 ro, vec3 rd) {
    float rad = radAt(ro.xz);
    vec3 under = mix(vec3(0.75, 0.2, 0.05), vec3(0.25, 0.7, 0.12), rad);      // lava light on the ash
    // the ash ceiling, a plane far overhead, so it slides past as you fly
    float ch = 9.0 - ro.y;
    vec2 cuv = ro.xz + rd.xz * ch / max(rd.y, 0.04);
    float cl = fbm(cuv * 0.07 + vec2(uTime * 0.01, 0.0));
    float cl2 = fbm(cuv * 0.21 - vec2(0.0, uTime * 0.02));
    float y = max(rd.y, 0.0);
    vec3 c = under * exp(-y * 7.0) * 0.5;                                      // glowing haze at the horizon
    c += under * (0.06 + 0.32 * cl * cl2) * exp(-y * 2.2) * smoothstep(-0.02, 0.06, rd.y);
    c += vec3(0.008, 0.006, 0.008);
    // volcanic lightning: a jagged bolt from the clouds to the horizon, and the clouds around it flashing
    if (gBolt > 0.0) {
        float az = atan(rd.x, rd.z);
        float el = asin(clamp(rd.y, -1.0, 1.0));
        float seed = floor(uBeatCount);
        float path = gBoltAz + (noise(vec2(el * 18.0, seed)) - 0.5) * 0.09 + (noise(vec2(el * 70.0, seed + 3.0)) - 0.5) * 0.025;
        float da = abs(mod(az - path + PI, TAU) - PI) * cos(el);
        float inSky = smoothstep(-0.01, 0.01, el) * smoothstep(0.45, 0.3, el);
        c += vec3(0.75, 0.8, 1.0) * (exp(-da * 900.0) * 6.0 + exp(-da * 90.0) * 0.4) * inSky * gBolt;
        float near = exp(-abs(mod(az - gBoltAz + PI, TAU) - PI) * 3.0);
        c += vec3(0.5, 0.55, 0.8) * near * cl * smoothstep(0.1, 0.5, el) * gBolt * 0.9;
    }
    return c;
}

// ---------------------------------------------------------------- ship
float gShipMat;  // 0 hull, 1 canopy, 2 engine nozzle

float sdEllipsoid(vec3 p, vec3 r) {
    float k0 = length(p / r), k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / k1;
}
float smin(float a, float b, float k) { float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0); return mix(b, a, h) - k * h * (1.0 - h); }

// a dart-shaped craft, nose along +z, about 0.4 long
float ship(vec3 p) {
    vec3 q = vec3(abs(p.x), p.y, p.z);
    float body = sdEllipsoid(p - vec3(0.0, 0.0, 0.01), vec3(0.042, 0.03, 0.21));
    // swept delta wings, thinning toward the tips
    float le = dot(vec2(q.x, q.z - 0.07), normalize(vec2(0.95, 1.0)));
    float wing = max(max(le, -0.13 - q.z), max(q.x - 0.2, abs(q.y + 0.006 + q.x * 0.05) - 0.007 * (1.0 - q.x * 3.0)));
    // canted tail fins
    vec3 fq = q - vec3(0.075, 0.0, 0.0);
    float fin = max(max(abs(fq.x - fq.y * 0.45) - 0.004, max(fq.y - 0.075, -fq.y)), max(-0.14 - q.z, q.z + 0.05 + fq.y * 0.9));
    // twin engines
    vec3 eq = q - vec3(0.045, -0.004, -0.09);
    float eng = max(length(eq.xy) - 0.022, abs(eq.z) - 0.065);
    float d = smin(body, wing, 0.012);
    d = min(d, fin);
    d = smin(d, eng, 0.008);
    float canopy = sdEllipsoid(p - vec3(0.0, 0.022, 0.07), vec3(0.022, 0.02, 0.065));
    gShipMat = 0.0;
    if (canopy < d) { d = canopy; gShipMat = 1.0; }
    float nozzle = max(length(eq.xy) - 0.017, abs(eq.z + 0.066) - 0.004);
    if (nozzle < d + 0.002) gShipMat = 2.0;
    return d;
}

vec3 shipNormal(vec3 p) {
    vec2 h = vec2(0.0008, -0.0008);
    return normalize(h.xyy * ship(p + h.xyy) + h.yyx * ship(p + h.yyx) + h.yxy * ship(p + h.yxy) + h.xxx * ship(p + h.xxx));
}

// ---------------------------------------------------------------- the picture
vec3 scene(vec2 p, vec2 uv) {
    // --- where the ship is (the app flies it), and how it sits
    vec2 S = uShip.xy;
    float yaw = uShip.z, steer = uShip.w;
    vec2 f2 = vec2(sin(yaw), cos(yaw));
    // altitude: the setting, but always clear of the ground under and ahead of the ship
    float clear = max(max(ground(S, 1.0), ground(S + f2 * 1.2, 1.0)), max(ground(S + f2 * 2.4, 1.0), ground(S - f2 * 0.8, 1.0)));
    float shipY = max(LAVA + 0.22 + uShip2.y * 2.3, clear + 0.32) + 0.015 * sin(uRealTime * 2.1);
    vec3 SP = vec3(S.x, shipY, S.y);
    float roll = steer * 0.6 + 0.03 * sin(uRealTime * 1.3);      // bank into the turn

    // --- chase camera: behind and above, lagging into the turn
    float cyaw = yaw + steer * 0.32;
    vec3 cf = vec3(sin(cyaw), 0.0, cos(cyaw));
    vec3 ro = SP - cf * 0.9 + vec3(0.0, 0.25, 0.0);
    ro.y = max(ro.y, ground(ro.xz, 1.0) + 0.15);
    vec3 ta = SP + cf * 1.6 + vec3(0.0, 0.06, 0.0);
    vec3 fw = normalize(ta - ro);
    float croll = -steer * 0.14;                                 // (opposite sign convention to the ship's roll matrix)
    vec3 rt0 = normalize(cross(fw, vec3(0.0, 1.0, 0.0))), up0 = cross(rt0, fw);
    vec3 rt = cos(croll) * rt0 + sin(croll) * up0;
    vec3 up = cross(rt, fw);
    vec3 rd = normalize(p.x * rt + p.y * up + 1.45 * fw);

    // --- lightning: about every other beat, somewhere ahead
    float bh = hash12(vec2(floor(uBeatCount), 7.7));
    gBolt = step(bh, 0.55) * uBeat * uBeat * (0.7 + 0.3 * step(0.5, fract(uRealTime * 14.0)));
    gBoltAz = yaw + (hash12(vec2(floor(uBeatCount), 3.1)) - 0.5) * 1.6;
    vec3 boltDir = normalize(vec3(sin(gBoltAz), 0.6, cos(gBoltAz)));

    // --- march the ground
    float t = 0.05, h = 1.0, tPrev = 0.05;
    bool hit = false;
    for (int i = 0; i < 170; i++) {
        vec3 q = ro + rd * t;
        if (q.y > 3.2 && rd.y > 0.0) break;
        h = q.y - ground(q.xz, lodAt(t));
        if (h < 0.0015 * t) { hit = true; break; }
        tPrev = t;
        t += h * 0.6;
        if (t > TMAX) break;
    }
    if (hit) {                                                   // refine
        float a = tPrev, b = t;
        for (int i = 0; i < 4; i++) {
            float m = 0.5 * (a + b);
            vec3 q = ro + rd * m;
            if (q.y - ground(q.xz, lodAt(m)) > 0.0) a = m; else b = m;
        }
        t = b;
    }

    vec3 col;
    float radHere = radAt(ro.xz);
    vec3 hazeC = mix(vec3(0.3, 0.07, 0.02), vec3(0.08, 0.25, 0.05), radHere);
    if (!hit) {
        col = skyCol(ro, rd);
        t = TMAX;
    } else {
        vec3 pos = ro + rd * t;
        float lod = lodAt(t);
        float rk = rockH(pos.xz, lod);
        float rad = radAt(pos.xz);
        float px = t * 2.0 / (uRes.y * 1.45);
        // engine light from the ship's exhaust on the ground below
        vec3 ex = SP - vec3(f2.x, 0.0, f2.y) * 0.18;
        float ed = length(pos - ex);
        vec3 engL = glowpal(0.35) * (0.4 + uA) * 0.35 / (1.0 + ed * ed * 10.0);

        if (rk <= LAVA) {
            // ---- lava: black crust plates drifting on the flow, seams glowing, open channels where it's deep
            float depth = LAVA - rockH(pos.xz, 1.0);
            vec2 flow = vec2(noise(pos.xz * 0.05) - 0.5, noise(pos.xz * 0.05 + 9.0) - 0.5) * uTime * 0.12;
            vec2 vq = pos.xz * 1.8 + flow;
            // warp the plates so they're irregular slabs, not a honeycomb
            vq += (vec2(noise(vq * 0.6), noise(vq * 0.6 + 3.3)) - 0.5) * 1.3;
            vec2 vo = voronoi(vq);
            vec2 vo2 = voronoi(vq * 3.1 + 5.0);
            float aa = smoothstep(0.0, 0.04, px);                // far away: cracks thinner than a pixel, keep their average
            float width = mix(55.0, 14.0, pow(noise(vq * 0.9 + 1.7), 2.0));   // mostly hairline cracks, a few wide rifts
            float seam = mix(exp(-vo.x * width), 0.08, aa);
            float seam2 = exp(-vo2.x * 45.0) * (1.0 - smoothstep(0.003, 0.015, px)) * smoothstep(0.3, 0.7, noise(vq * 0.4));
            // open channels where the lava runs deep: streaky flow with rafts of crust riding on it
            float open = smoothstep(0.35, 1.1, depth) * smoothstep(0.45, 0.75, noise(pos.xz * 0.5 + 11.0));
            vec2 fq = pos.xz * vec2(1.0, 4.0) * 1.5 - flow * 6.0;
            float streak = noise(fq) * 0.6 + noise(fq * 2.7 + 2.0) * 0.4;
            float raft = smoothstep(0.05, 0.12, vo2.x) * step(0.45, vo2.y);
            float hot = noise(vq * 0.35 + 8.0);                  // some regions run hotter
            float T = seam * (0.32 + 0.35 * hot) + seam2 * 0.25;
            T = max(T, open * (0.35 + 0.5 * streak) * (1.0 - raft * 0.85));
            T += 0.05 * smoothstep(0.2, 0.8, depth) * (0.5 + hot);   // thin crust: a dull red cast
            T *= 1.0 + uBeat * 0.45;                            // the sea flares on the beat
            T *= 0.85 + 0.15 * sin(uTime * 0.7 + vo.y * 20.0);    // slow breathing per plate
            float shore = smoothstep(0.0, 0.1, depth);           // cooled, ashy rim along the rocks
            T *= mix(0.3, 1.0, shore);
            vec3 crust = vec3(0.03, 0.025, 0.024) * (0.6 + 0.8 * vo.y) * (0.7 + 0.6 * noise(vq * 4.0));
            // the crust reflects a little of the glowing sky
            vec3 n = normalize(vec3((noise(vq * 1.3) - 0.5) * 0.25, 1.0, (noise(vq * 1.3 + 4.0) - 0.5) * 0.25));
            float fres = pow(1.0 - max(dot(n, -rd), 0.0), 5.0);
            // crust: rough, its edges lit by the seams beside them, fine cracks catching a little glow
            float rough = noise(vq * 7.0) * 0.6 + noise(vq * 19.0) * 0.4;
            crust *= 0.5 + rough;
            col = crust * (0.4 + engL * 3.0) + glowCol(0.45, rad) * exp(-vo.x * 7.0) * 0.12 * (0.5 + rough)
                + skyCol(pos, reflect(rd, n)) * fres * 0.25 * (1.0 - open);
            col += glowCol(T, rad);
            col += vec3(0.6, 0.65, 1.0) * gBolt * 0.06;
        } else {
            // ---- basalt: lit from below by the lava, from above by the ash and the lightning
            vec3 n = groundNormal(pos.xz, 0.002 + t * 0.0015, lod);
            float hy = pos.y - LAVA;
            // how much lava is around (coarse look-around), for the under-lighting
            float lv = 0.0;
            for (int k = 0; k < 4; k++) {
                vec2 o = vec2(cos(float(k) * 1.571 + 0.4), sin(float(k) * 1.571 + 0.4)) * 0.7;
                lv += smoothstep(0.15, -0.25, rockBase(pos.xz + o));
            }
            lv *= 0.25;
            vec3 lavaL = mix(vec3(1.0, 0.32, 0.06), vec3(0.35, 1.0, 0.15), rad) * lv * exp(-hy * 1.6) * (0.25 + 0.75 * clamp(0.6 - 0.6 * n.y, 0.0, 1.0)) * 1.6;
            vec3 ashL = mix(vec3(0.16, 0.06, 0.03), vec3(0.06, 0.12, 0.04), rad) * (0.5 + 0.5 * n.y);
            vec3 boltL = vec3(0.6, 0.7, 1.0) * gBolt * max(dot(n, boltDir), 0.0) * 1.5;
            float ash = smoothstep(0.75, 0.95, n.y) * smoothstep(0.3, 0.9, hy);
            vec3 alb = mix(vec3(0.07, 0.06, 0.06) * (0.7 + 0.6 * noise(pos.xz * 9.0)), vec3(0.2, 0.19, 0.18), ash);
            float ao = clamp(0.5 + 0.5 * (pos.y + n.y * 0.1 - ground(pos.xz + n.xz * 0.1, 1.0)) / 0.1, 0.3, 1.0);
            col = alb * (lavaL + ashL + boltL + engL * 4.0) * ao;
            // glassy obsidian: the faces catch the glowing horizon and the lava around them
            vec3 rr = reflect(rd, n);
            float ofres = 0.04 + 0.5 * pow(1.0 - max(dot(n, -rd), 0.0), 5.0);
            vec3 rcol = rr.y > 0.0 ? skyCol(pos, rr) : mix(vec3(1.0, 0.3, 0.06), vec3(0.3, 1.0, 0.12), rad) * lv * 0.5;
            col += rcol * ofres * ao * (0.4 + 0.6 * smoothstep(0.4, 0.7, noise(pos.xz * 5.0)));
            // molten veins in the rock just above the lava line
            float vein = 1.0 - abs(noise(pos.xz * 4.0 + pos.y * 3.0) * 2.0 - 1.0);
            col += glowCol(smoothstep(0.965, 1.0, vein) * smoothstep(0.25, 0.0, hy) * 0.7, rad) * (1.0 - smoothstep(0.004, 0.02, px));
            // radioactive vents: green fumaroles on irradiated ground
            vec2 vc = floor(pos.xz * 1.2), vf = fract(pos.xz * 1.2) - 0.25 - 0.5 * hash22(vc + 3.0);
            float vent = step(0.7, hash12(vc + 9.0)) * exp(-dot(vf, vf) * 900.0) * (0.7 + 0.3 * sin(uRealTime * 3.0 + hash12(vc) * 9.0));
            col += toxic(0.8) * rad * vent * 2.0 * (1.0 - smoothstep(0.004, 0.03, px));
        }
        // smoke and the lava's glow in the air: thick near the sea, thinner up high
        float fog = 1.0 - exp(-t * 0.055 * (0.6 + 0.8 * exp(-max(pos.y, 0.0) * 1.2)));
        col = mix(col, hazeC * (0.7 + 0.3 * exp(-max(rd.y, 0.0) * 6.0)), fog);
    }

    // --- the ship (inside a bounding sphere)
    vec3 shipCol = vec3(0.0);
    float shipA = 0.0;
    {
        vec3 oc = ro - SP;
        float b = dot(oc, rd), c = dot(oc, oc) - 0.09;
        float disc = b * b - c;
        if (disc > 0.0) {
            mat2 ry = rot(-yaw), rr = rot(roll);
            float ts = max(-b - sqrt(disc), 0.0), te = -b + sqrt(disc);
            bool sh = false;
            vec3 lp;
            for (int i = 0; i < 64; i++) {
                vec3 wp = ro + rd * ts - SP;
                lp = wp; lp.xz = ry * lp.xz; lp.xy = rr * lp.xy;
                float d = ship(lp);
                if (d < 0.0004) { sh = true; break; }
                ts += d;
                if (ts > te) break;
            }
            if (sh && ts < t) {
                float mat = gShipMat;
                vec3 ln = shipNormal(lp);
                // back to world space
                mat2 iry = rot(yaw), irr = rot(-roll);
                vec3 n = ln; n.xy = irr * n.xy; n.xz = iry * n.xz;
                vec3 r = reflect(rd, n);
                float fres = pow(1.0 - max(dot(n, -rd), 0.0), 4.0);
                float rad = radAt(SP.xz);
                vec3 lavaGlow = mix(vec3(1.0, 0.35, 0.08), vec3(0.3, 1.0, 0.15), rad);
                float lift = exp(-(shipY - LAVA) * 0.9);
                // what the hull reflects: the glowing sea below, the dark ash above
                vec3 env = r.y < 0.0 ? lavaGlow * (0.35 + 0.65 * lift) * smoothstep(0.0, -0.3, r.y) * 1.4 + hazeC * 0.5 : skyCol(SP, r);
                vec3 under = lavaGlow * max(-n.y, 0.0) * lift * 1.5;
                vec3 top = vec3(0.15, 0.07, 0.04) * max(n.y, 0.0) + vec3(0.6, 0.7, 1.0) * gBolt * max(dot(n, boltDir), 0.0) * 2.0;
                if (mat == 1.0) {
                    shipCol = vec3(0.01, 0.015, 0.02) + env * (0.1 + 0.9 * fres) + glowpal(0.6) * 0.04;
                } else if (mat == 2.0) {
                    shipCol = glowpal(0.35) * (0.25 + uA * 0.5 + uBeat * 0.6);
                } else {
                    // gunmetal panels with a few seams
                    vec3 a = abs(lp);
                    float panel = step(0.92, fract(lp.z * 18.0)) * step(a.y, 0.03) + step(0.95, fract(a.x * 22.0)) * step(0.05, a.x);
                    vec3 alb = vec3(0.09, 0.09, 0.1) * (1.0 - 0.5 * clamp(panel, 0.0, 1.0));
                    shipCol = alb * (under + top + 0.05) + env * mix(0.12, 0.85, fres);
                    // nav lights: red port, green starboard, a white strobe on the tail
                    float tip = smoothstep(0.012, 0.0, length(vec2(a.x - 0.195, lp.z + 0.12)));
                    shipCol += (lp.x < 0.0 ? vec3(1.0, 0.05, 0.03) : vec3(0.1, 1.0, 0.2)) * tip * 4.0;
                    shipCol += vec3(1.0) * step(0.93, fract(uRealTime * 1.1)) * smoothstep(0.012, 0.0, length(lp - vec3(0.0, 0.03, -0.13))) * 8.0;
                }
                shipA = 1.0;
            }
        }
    }
    col = mix(col, shipCol, shipA);

    // --- the exhaust: twin plumes of hot gas streaming back from the nozzles
    {
        mat2 iry = rot(yaw), irr = rot(-roll);
        for (int k = 0; k < 2; k++) {
            vec3 nl = vec3(k == 0 ? 0.045 : -0.045, -0.004, -0.16);
            nl.xy = irr * nl.xy; nl.xz = iry * nl.xz;
            vec3 a = SP + nl, dir = -vec3(f2.x, 0.0, f2.y);
            float len = 0.12 + uA * 0.3 + uBeat * 0.1;
            // closest approach between the view ray and the plume's axis
            vec3 w0 = ro - a;
            float bb = dot(rd, dir), dd = dot(rd, w0), ee = dot(dir, w0);
            float den = max(1.0 - bb * bb, 1e-4);
            float sc = (bb * ee - dd) / den;          // along the ray
            float tc = clamp((ee - bb * dd) / den, 0.0, len);
            float dist = length(w0 + rd * sc - dir * tc);
            float fall = 1.0 - tc / len;
            float w = 0.007 + 0.013 * (1.0 - fall);
            float glow = exp(-dist * dist / (w * w)) * fall * fall * step(0.0, sc) * step(sc, t + 0.3);
            float flick = 0.8 + 0.2 * noise(vec2(tc * 40.0 - uRealTime * 30.0, float(k)));
            col += mix(glowpal(0.35), vec3(1.0), 0.5 * fall * fall) * glow * flick * (0.45 + uA * 0.9 + uBeat * 0.8);
        }
    }

    // --- embers streaming up past the ship (sparse voxels near the camera, each ember rising inside its cell)
    {
        const float CE = 0.45;
        vec3 cell = floor(ro / CE);
        vec3 sg = sign(rd + 1e-6);
        vec3 tDel = abs(CE / (rd + 1e-6));
        vec3 tMax = ((cell + max(sg, 0.0)) * CE - ro) / (rd + 1e-6);
        float tEnd = min(t, 9.0);
        for (int i = 0; i < 30; i++) {
            float tn = min(tMax.x, min(tMax.y, tMax.z));
            vec3 hh = hash33e(cell);
            float lowness = exp(-max((cell.y + 0.5) * CE - LAVA, 0.0) * 0.9);
            if (hh.x < 0.17 * lowness * (0.6 + uBeat)) {
                float life = fract(hh.y + uTime * (0.25 + 0.3 * hh.z));
                vec3 q = (cell + vec3(0.15 + 0.7 * hh.z, 0.05 + 0.9 * life, 0.15 + 0.7 * fract(hh.y * 7.3))) * CE;
                q.x += 0.03 * sin(uTime * 2.0 + hh.y * 20.0);
                vec3 rel = q - ro;
                float tq = dot(rel, rd);
                if (tq > 0.05 && tq < tEnd) {
                    // a short vertical streak (motion blur of the rise)
                    vec3 cp = rel - rd * tq;
                    float pr = 2.0 / (uRes.y * 1.45) * tq;
                    float dy = cp.y; float dxz = length(cp - vec3(0.0, cp.y, 0.0));
                    float e = exp(-(dxz * dxz) / (pr * pr * 1.5)) * exp(-(dy * dy) / (pr * pr * 9.0 + 0.0004));
                    float fade = sin(life * PI);
                    col += glowCol(0.5 + 0.45 * hh.z, radAt(q.xz)) * e * fade * 0.6;
                }
            }
            if (tn > tEnd) break;
            if (tMax.x == tn) { cell.x += sg.x; tMax.x += tDel.x; }
            else if (tMax.y == tn) { cell.y += sg.y; tMax.y += tDel.y; }
            else { cell.z += sg.z; tMax.z += tDel.z; }
        }
    }
    return col;
}
