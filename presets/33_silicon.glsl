// @preset {"energy": 2, "family": "flight3d", "heavy": true, "name": "Silicon", "labels": {"a": "magnification", "b": "look around", "c": "data flow", "d": "oxide colour"}, "params": {"palette": 4, "glow": 0.3, "feedback": 0.0, "chroma": 0.05, "c": 0.35}}
// A macro flight over a silicon die, lit like a microscope photo. The die is built procedurally from blocks of
// random logic (four routing layers, alternating direction), memory arrays, dummy fill and spiral inductors, with
// aluminium power straps between them and tungsten vias under the wire ends. Copper, aluminium and tungsten use
// their real reflectances; the rainbow is thin-film interference in the glass over everything (knob D sets the
// oxide thickness). Far away the die melts into a defocused wash with bokeh, like a real macro lens.
// Data flow (C) sends pulses racing along the traces, harder on the beat; bass charges the power straps.
// Unlike most presets it keeps physical material colours; the palette only colours the data pulses. Heavy.

float sdBox(vec3 p, vec3 b) { vec3 q = abs(p) - b; return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0); }

const float BLOCK = 3.0;     // functional blocks on the die
const float TOP = 0.21;      // nothing is taller than this

float mMat;     // material of the last hit: 0 silicon, 1 copper, 2 aluminium, 3 tungsten via
vec2 mInfo;     // along-trace coordinate and a per-trace random, for the data pulses

// One routing layer: parallel tracks (pitch apart), each split into cells holding at most one wire segment,
// with a via dropping from each end of some segments. alongX: tracks run along x, else along z.
float layer(vec3 p, float y0, float y1, float pitch, float width, float cellLen, float fill, float seed, bool alongX,
            float fixedLen, out vec2 info) {
    vec2 q = alongX ? p.zx : p.xz;                    // q.x across the tracks, q.y along them
    float lane = floor(q.x / pitch);
    float lx = q.x - (lane + 0.5) * pitch;
    float cell = floor(q.y / cellLen);
    float ly = q.y - (cell + 0.5) * cellLen;
    float h = hash12(vec2(lane, cell) + seed);
    float h2 = hash12(vec2(cell + seed, lane * 1.3));
    float half_ = fixedLen > 0.0 ? fixedLen : cellLen * (0.2 + 0.28 * h2);
    float off = fixedLen > 0.0 ? 0.0 : (hash12(vec2(lane + seed, cell * 3.1)) - 0.5) * (cellLen - 2.0 * half_) * 0.9;
    float yc = (y0 + y1) * 0.5, hy = (y1 - y0) * 0.5;
    float d = 1e3;
    if (h < fill) {
        d = sdBox(vec3(lx, p.y - yc, ly - off), vec3(width * 0.5, hy, half_));
        float vgap = 0.012;
        if (h2 > 0.35 && fixedLen <= 0.0) {
            float e = abs(ly - off) - half_ + width * 0.5;      // a via under each end
            d = min(d, sdBox(vec3(lx, p.y - (y0 - vgap * 0.5), e), vec3(width * 0.32, vgap * 0.5 + 0.001, width * 0.32)));
        }
    }
    info = vec2(q.y, h);
    // never step past this track's cell: a neighbour may hold metal (keeps the distance a lower bound)
    float bound = min(pitch * 0.5 - abs(lx), cellLen * 0.5 - abs(ly));
    float vy = max(p.y - y1, (y0 - 0.014) - p.y);
    return min(d, max(vy, bound + 0.003));
}

// square spiral inductor in thick top copper, centred in its block
float inductor(vec3 p, vec2 c) {
    vec2 q = p.xz - c;
    float r = max(abs(q.x), abs(q.y));                 // square "radius"
    float a = (atan(q.y, q.x) + PI) / TAU;
    float pitch = 0.17;
    float s = r - a * pitch;
    float ring = abs(fract((s - 0.32) / pitch + 0.5) - 0.5) * pitch - 0.055;
    ring = max(ring, max(0.3 - r, r - 1.3));
    return max(ring, abs(p.y - 0.17) - 0.035);
}

float die(vec3 p) {
    if (p.y > TOP + 0.02) { mMat = 0.0; return p.y - TOP; }
    vec2 bid = floor(p.xz / BLOCK);
    vec2 bl = p.xz - (bid + 0.5) * BLOCK;               // position inside the block
    float bh = hash12(bid * 1.37 + 4.1);
    float type = bh < 0.5 ? 0.0 : bh < 0.75 ? 1.0 : bh < 0.88 ? 2.0 : 3.0;   // logic, memory, fill, inductor
    float d = p.y;                                       // the silicon
    mMat = 0.0;
    vec2 inf;
    float dl;
    if (type == 1.0) {
        // memory: a dead-regular array of bit cells under continuous word lines
        dl = layer(p, 0.008, 0.02, 0.035, 0.022, 0.05, 1.0, 11.0, true, 0.016, inf);
        if (dl < d) { d = dl; mMat = 1.0; mInfo = inf; }
        dl = layer(p, 0.03, 0.042, 0.05, 0.012, 3.0, 1.0, 12.0, false, 1.5, inf);
        if (dl < d) { d = dl; mMat = 1.0; mInfo = inf; }
        dl = layer(p, 0.055, 0.072, 0.14, 0.05, 1.2, 0.5, 13.0, true, 0.0, inf);
        if (dl < d) { d = dl; mMat = 1.0; mInfo = inf; }
    } else if (type == 2.0) {
        // dummy fill: chequered squares the fab adds to keep the layers flat
        dl = layer(p, 0.03, 0.044, 0.1, 0.07, 0.1, 1.0, 21.0, true, 0.035, inf);
        if (dl < d) { d = dl; mMat = 1.0; mInfo = inf; }
        dl = layer(p, 0.07, 0.09, 0.2, 0.12, 0.2, 1.0, 22.0, false, 0.06, inf);
        if (dl < d) { d = dl; mMat = 1.0; mInfo = inf; }
    } else {
        // random logic: four layers of routing, alternating direction, getting wider going up
        dl = layer(p, 0.008, 0.02, 0.045, 0.016, 0.32, 0.7, 31.0, true, 0.0, inf);
        if (dl < d) { d = dl; mMat = 1.0; mInfo = inf; }
        dl = layer(p, 0.032, 0.046, 0.06, 0.022, 0.42, 0.65, 32.0, false, 0.0, inf);
        if (dl < d) { d = dl; mMat = 1.0; mInfo = inf; }
        if (type == 0.0 || max(abs(bl.x), abs(bl.y)) > 1.4) {
            dl = layer(p, 0.058, 0.076, 0.09, 0.034, 0.6, 0.55, 33.0, true, 0.0, inf);
            if (dl < d) { d = dl; mMat = 1.0; mInfo = inf; }
            dl = layer(p, 0.09, 0.118, 0.16, 0.06, 0.9, 0.45, 34.0, false, 0.0, inf);
            if (dl < d) { d = dl; mMat = 1.0; mInfo = inf; }
        }
        if (type == 3.0) {
            dl = inductor(p, (bid + 0.5) * BLOCK);
            if (dl < d) { d = dl; mMat = 1.0; mInfo = vec2(0.0, 1.0); }
        }
    }
    // wide aluminium power straps along the channels between blocks
    float strap = sdBox(vec3(abs(bl.x) - BLOCK * 0.5 + 0.11, p.y - 0.15, 0.0), vec3(0.09, 0.03, 10.0));
    strap = min(strap, sdBox(vec3(0.0, p.y - 0.15, abs(bl.y) - BLOCK * 0.5 + 0.11), vec3(10.0, 0.03, 0.09)));
    if (strap < d) { d = strap; mMat = 2.0; mInfo = vec2(0.0, 1.0); }
    // stay inside this block: the next one is built differently
    float edge = BLOCK * 0.5 - max(abs(bl.x), abs(bl.y));
    return min(d, max(p.y - TOP, edge + 0.004));
}

vec3 dieNormal(vec3 p, float e) {
    vec2 h = vec2(e, -e);
    return normalize(h.xyy * die(p + h.xyy) + h.yyx * die(p + h.yyx) + h.yxy * die(p + h.yxy) + h.xxx * die(p + h.xxx));
}

// colour reflected by a thin glass (SiO2) film of `nm` thickness: the rainbow of a real die photo
vec3 thinFilm(float nm, float cosT) {
    float n = 1.46;
    float cosR = sqrt(1.0 - (1.0 - cosT * cosT) / (n * n));
    vec3 phase = TAU * 2.0 * n * nm * cosR / vec3(650.0, 532.0, 450.0);
    return 0.5 + 0.5 * cos(phase);
}

// the microscope's light: a bright ring light and softbox overhead, a dark lab around
vec3 lab(vec3 r) {
    float up = r.y;
    vec3 c = vec3(0.015, 0.018, 0.022) + vec3(0.85, 0.9, 1.0) * smoothstep(0.35, 1.0, up) * 0.38;
    c += vec3(1.0, 0.96, 0.9) * exp(-pow((up - 0.8) * 3.5, 2.0)) * 0.5;    // ring light, diffused
    return c;
}

float softShadow(vec3 ro, vec3 rd) {
    float res = 1.0, t = 0.004;
    for (int i = 0; i < 20; i++) {
        float h = die(ro + rd * t);
        res = min(res, 10.0 * h / t);
        t += clamp(h, 0.003, 0.03);
        if (res < 0.02 || t > 0.4) break;
    }
    return clamp(res, 0.0, 1.0);
}

// what a macro lens makes of everything out of focus: soft gradient and bokeh discs of the chip's colours
vec3 bokeh(vec2 p, vec3 base) {
    vec3 c = base;
    for (int i = 0; i < 2; i++) {
        float sc = 3.5 + float(i) * 3.0;
        vec2 g = p * sc + vec2(uTime * 0.02 * (1.0 + float(i)), 0.0);
        vec2 id = floor(g), f = fract(g) - 0.5;
        vec2 h = hash22(id + float(i) * 17.0);
        float r = length(f - (h - 0.5) * 0.3);
        float disc = (smoothstep(0.4, 0.3, r) * 0.6 + smoothstep(0.42, 0.37, r) * smoothstep(0.3, 0.38, r)) * step(0.78, h.x);
        vec3 bc = h.y < 0.6 ? vec3(1.0, 0.62, 0.48) : thinFilm(300.0 + h.y * 600.0, 1.0);
        c += bc * disc * 0.07 * (1.0 + uHigh);
    }
    return c;
}

// the die as a defocused lens sees it: each block a soft wash of its oxide colour and copper
vec3 dieBlur(vec3 pos) {
    vec2 b = pos.xz / BLOCK;
    vec2 i = floor(b - 0.5), f = smoothstep(0.0, 1.0, fract(b - 0.5));
    vec3 c = vec3(0.0);
    for (int k = 0; k < 4; k++) {
        vec2 o = vec2(float(k % 2), float(k / 2));
        float h = hash12(i + o + 2.0);
        vec3 film = thinFilm(260.0 + uD * 520.0 + 220.0 * h + 45.0, 0.9);
        vec3 bc = mix(film * 0.3, vec3(0.95, 0.64, 0.54) * 0.45, 0.55);
        float w = (o.x > 0.5 ? f.x : 1.0 - f.x) * (o.y > 0.5 ? f.y : 1.0 - f.y);
        c += bc * w;
    }
    return c;
}

vec3 scene(vec2 p, vec2 uv) {
    float height = 0.3 + uA * 1.1;
    float z = uPulse * (0.1 + height * 0.22);
    vec3 ro = vec3(0.7 * sin(uTime * 0.045) + 0.3 * sin(uTime * 0.11), height, z);
    vec3 fw = normalize(vec3(sin(uTime * 0.07) * (0.12 + uB * 0.5), -0.78 - 0.1 * sin(uTime * 0.09), 1.0));
    vec3 rt = normalize(cross(fw, vec3(0.0, 1.0, 0.0))), up = cross(rt, fw);
    vec3 rd = normalize(p.x * rt + p.y * up + 1.7 * fw);
    // macro depth of field: sharp at the focus distance, melting into bokeh beyond it
    float focus = height * 1.25;
    float tFar = focus * 3.5;                                // past this everything is the defocused wash
    float t = 0.0, d = 1.0;
    if (rd.y < 0.0) t = max(0.0, (ro.y - TOP - 0.01) / -rd.y);   // skip the empty air straight to the chip
    for (int i = 0; i < 150; i++) {
        d = die(ro + rd * t);
        if (d < 0.0003 * (1.0 + t * 2.0) || t > tFar) break;
        t += d * 0.9;
    }
    float blur = smoothstep(focus * 1.3, tFar, t);
    // where the ray would meet the chip's surface (for the wash's colour), even if we stopped short
    vec3 pos = ro + rd * (rd.y < -0.01 ? max(t, (ro.y - 0.06) / -rd.y) : t);
    vec3 bg = bokeh(p, dieBlur(pos) * mix(1.0, 0.4, smoothstep(6.0, 14.0, length(pos - ro))));
    if (blur > 0.999) return bg;
    pos = ro + rd * t;
    die(pos);
    float mat = mMat;
    vec2 info = mInfo;
    vec3 n = dieNormal(pos, 0.0005 * (1.0 + t * 2.0));
    vec3 r = reflect(rd, n);
    float cosT = max(dot(n, -rd), 0.0);
    vec3 ld = normalize(vec3(0.35, 1.0, -0.45));
    float sh = softShadow(pos + n * 0.002, ld);
    float ao = clamp(die(pos + n * 0.02) / 0.02, 0.0, 1.0) * 0.5 + clamp(die(pos + n * 0.06) / 0.06, 0.0, 1.0) * 0.5;
    float dif = max(dot(n, ld), 0.0) * sh;
    vec3 col;
    // oxide thickness: patches per region, rows of standard cells, and the colour knob
    vec2 bid = floor(pos.xz / BLOCK);
    float oxBlock = 260.0 + uD * 520.0 + 220.0 * hash12(bid + 2.0);
    float ox = oxBlock + 90.0 * hash12(floor(pos.xz * 3.0) + bid) + 40.0 * noise(pos.xz * 4.0);
    ox += 60.0 * step(0.5, fract(pos.z * 8.0)) * (1.0 - smoothstep(0.5, 1.5, t));   // cell rows, fading before they shimmer
    if (mat == 0.0) {
        // silicon under its glass: interference colour, faint gate stripes of the transistors
        vec3 film = mix(vec3(0.45), thinFilm(ox, cosT), 0.75);
        float gates = 0.85 + 0.15 * step(0.6, fract(pos.x * 60.0)) * step(0.3, fract(pos.z * 8.0)) * (1.0 - smoothstep(0.3, 0.9, t));
        col = film * (0.08 + 0.55 * dif + 0.35 * lab(r).g) * gates * ao;
    } else {
        vec3 f0 = mat == 1.0 ? vec3(0.955, 0.638, 0.538) : mat == 2.0 ? vec3(0.913, 0.922, 0.924) : vec3(0.6, 0.6, 0.62);
        vec3 fres = f0 + (1.0 - f0) * pow(1.0 - cosT, 5.0);
        float rough = mat == 2.0 ? 0.35 : 0.15;
        vec3 envc = mix(lab(r), lab(normalize(n + vec3(0.0, 0.5, 0.0))) * 0.8, rough);
        col = fres * envc * (0.35 + 0.65 * sh) * ao * 0.85;
        col += f0 * dif * 0.25 * ao;
        // grain and faint polishing (CMP) marks in the metal, fading with distance
        float near = 1.0 - smoothstep(0.4, 1.5, t);
        col *= 1.0 + (0.1 * (noise(pos.xz * 90.0) - 0.5) + 0.05 * sin(dot(pos.xz, vec2(140.0, 37.0)) + noise(pos.xz * 6.0) * 6.0)) * near;
        col *= mix(vec3(1.0), thinFilm(oxBlock * 0.45, cosT) * 1.15, 0.2);   // the passivation glass tints the metal too
        // DATA FLOW (knob C): pulses racing along the traces, harder on the beat
        float pulse = pow(0.5 + 0.5 * sin(info.x * 9.0 - uPulse * 5.0 * (0.6 + info.y) + info.y * 60.0), 40.0);
        float live = step(info.y, 0.45);
        col += glowpal(info.y * 2.0 + uD) * pulse * live * uC * (0.8 + uBeat * 2.5) * 2.0;
        if (mat == 2.0) col += glowpal(0.6 + uD) * uBass * uC * 0.25;                       // power rails charge with the bass
    }
    return mix(col, bg, blur);
}
