// @preset {"energy": 1, "family": "flight3d", "heavy": true, "name": "City", "labels": {"a": "density", "b": "look around", "c": "data", "d": "time of day"}, "params": {"palette": 5, "glow": 0.3, "feedback": 0.0, "chroma": 0.03, "a": 0.6, "c": 0.4, "d": 0.75}}
// An aerial flight over an endless procedural city, shot like aerial photography (a companion to Coastline).
// Blocks of four lots, mostly 3-10 storeys, with towers (setbacks, spires) clustering downtown; parks; a
// winding river with a bridge every third street. Facades are glass, stone or brick with window grids;
// streets have sidewalks, lane markings and moving traffic. TIME OF DAY (D): daylight, golden hour with long
// shadows, night (sparse lit windows, sodium streetlights, tower beacons, the river reflecting it all).
// DATA (C): thin survey lines on the curbs and pulses flowing down the streets on the beat. A = density.

float sdBox(vec3 p, vec3 b) { vec3 q = abs(p) - b; return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0); }

const float BP = 1.0;      // block pitch (block + street)
const float SW = 0.085;    // half the street width
const float MAXH = 4.2;    // nothing is taller

float gBld;      // random id of the building last hit (for its windows and colour)
float gKind;     // 0 street/ground, 1 building, 2 water, 3 park
vec3 gLocal;     // position in the building's own frame (for windows)
vec3 gHalf;      // that building's half size

float riverX(float z) { return 7.0 * sin(z * 0.045) + 2.5 * sin(z * 0.11 + 1.3); }

// how built-up this part of town is: towers downtown, low blocks further out (and knob A)
float district(vec2 id) {
    float n = noise(id * 0.06) * 0.7 + noise(id * 0.19 + 5.0) * 0.3;
    return smoothstep(0.72 - uA * 0.2, 0.95 - uA * 0.15, n);
}

float city(vec3 p) {
    vec2 id = floor(p.xz / BP);
    vec2 l = p.xz - (id + 0.5) * BP;
    vec2 c = (id + 0.5) * BP;
    float ground = p.y;
    gKind = 0.0;
    float rv = abs(c.x - riverX(c.y));
    float d = ground;
    float edge = BP * 0.5 - max(abs(l.x), abs(l.y));          // stay inside this block's cell
    if (rv < 1.6) {
        // the river: water a little below the streets, bridges where the cross streets meet it
        float w = p.y + 0.03;
        float bridge = mod(id.y, 3.0) < 0.5 ? sdBox(vec3(l.x, p.y - 0.035, l.y + BP * 0.5), vec3(BP * 0.55, 0.012, SW * 0.8)) : 1e3;   // a bridge every third street
        d = min(w, bridge);
        gKind = w < bridge ? 2.0 : 0.0;
        return min(d, max(p.y - 0.06, edge + 0.01));
    }
    float hb = hash12(id * 1.31 + 7.0);
    if (hb < 0.07) {
        // a park: lawns and the bumps of tree crowns
        vec2 tq = fract(p.xz * 9.0) - 0.5;
        float trees = p.y - 0.035 * smoothstep(0.45, 0.1, length(tq)) * step(abs(l.x), 0.38) * step(abs(l.y), 0.38) * step(0.35, hash12(floor(p.xz * 9.0)));
        gKind = trees < ground + 0.001 ? 3.0 : 0.0;
        if (abs(l.x) < BP * 0.5 - SW && abs(l.y) < BP * 0.5 - SW) gKind = 3.0;
        return min(trees * 0.7, max(p.y - 0.05, edge + 0.01));
    }
    float dist = district(id);
    // four lots per block, one building each, some with a setback tower and a spire on top
    vec2 lq = sign(l + 1e-4);
    vec2 lot = l - lq * (BP * 0.5 - SW) * 0.5;               // into this quarter of the block
    float hl = hash12(id * 2.7 + lq * 13.1);
    float hl2 = hash12(id * 5.3 - lq * 7.7);
    float inset = 0.012 + 0.03 * hl2;
    vec2 half_ = vec2((BP * 0.5 - SW) * 0.5 - inset);
    // mostly 3-10 storeys; downtown, a few blocks shoot up into towers
    float h = 0.05 + 0.16 * hl * hl + pow(hl, 4.0) * dist * 3.6 + dist * 0.12;
    float b = sdBox(vec3(lot.x, p.y - h * 0.5, lot.y), vec3(half_.x, h * 0.5, half_.y));
    gLocal = vec3(lot.x, p.y, lot.y);
    gHalf = vec3(half_.x, h, half_.y);
    if (hl > 0.5 && h > 0.5) {
        float h2 = h * (1.18 + 0.2 * hl2);
        vec2 hs = half_ * (0.62 + 0.2 * hl2);
        float tier = sdBox(vec3(lot.x, p.y - h2 * 0.5, lot.y), vec3(hs.x, h2 * 0.5, hs.y));
        if (tier < b) { gLocal = vec3(lot.x, p.y, lot.y); gHalf = vec3(hs.x, h2, hs.y); }
        b = min(b, tier);
        if (hl2 > 0.6) b = min(b, sdBox(vec3(lot.x, p.y - h2 - 0.12, lot.y), vec3(0.008, 0.12, 0.008)));   // spire
    }
    // rooftop clutter: plant rooms and tanks
    float rc = sdBox(vec3(lot.x - (hl2 - 0.5) * half_.x, p.y - h - 0.012, lot.y + (hl - 0.5) * half_.y), vec3(half_.x * 0.25, 0.012, half_.y * 0.2));
    b = min(b, rc);
    gBld = hash12(id * 3.1 + lq * 1.7);
    if (b < d) { d = b; gKind = 1.0; }
    // stay inside this block (the next one is built differently); and above the tallest towers, just fall
    return min(d, max(p.y - MAXH, edge + 0.01));
}

vec3 cityNormal(vec3 p, float e) {
    vec2 h = vec2(e, -e);
    return normalize(h.xyy * city(p + h.xyy) + h.yyx * city(p + h.yyx) + h.yxy * city(p + h.yxy) + h.xxx * city(p + h.xxx));
}

vec3 skyCol(vec3 rd, vec3 sun, float night) {
    vec3 day = mix(vec3(0.62, 0.72, 0.85), vec3(0.25, 0.42, 0.7), smoothstep(-0.05, 0.5, rd.y));
    vec3 gold = mix(vec3(1.0, 0.6, 0.35), vec3(0.3, 0.32, 0.55), smoothstep(-0.05, 0.4, rd.y));
    vec3 nite = mix(vec3(0.3, 0.15, 0.09) * 0.45, vec3(0.008, 0.01, 0.03), smoothstep(-0.02, 0.18, rd.y));   // orange city glow on the horizon
    float tod = uD;
    vec3 c = tod < 0.5 ? mix(day, gold, tod * 2.0) : mix(gold, nite, tod * 2.0 - 1.0);
    c += vec3(1.0, 0.8, 0.6) * pow(max(dot(rd, sun), 0.0), 300.0) * 4.0 * (1.0 - night);
    return c;
}

float softShadow(vec3 ro, vec3 rd) {
    float res = 1.0, t = 0.01;
    for (int i = 0; i < 32; i++) {
        float h = city(ro + rd * t);
        res = min(res, 8.0 * h / t);
        t += clamp(h, 0.02, 0.4);
        if (res < 0.02 || t > 8.0 || ro.y + rd.y * t > MAXH) break;
    }
    return clamp(res, 0.0, 1.0);
}

vec3 scene(vec2 p, vec2 uv) {
    float tod = uD;                                           // 0 day .. 0.5 golden hour .. 1 night
    float night = smoothstep(0.55, 0.95, tod);
    vec3 sun = normalize(vec3(-0.6, mix(0.75, 0.12, smoothstep(0.0, 0.6, tod)), 0.4));
    float z = uPulse * 0.55;
    vec3 ro = vec3(riverX(z) * 0.4 + 2.0 * sin(uTime * 0.03), 7.0 + 0.8 * sin(uTime * 0.04), z);
    vec3 fw = normalize(vec3(sin(uTime * 0.05) * (0.25 + uB * 0.6), -1.3, 1.0));
    vec3 rt = normalize(cross(fw, vec3(0.0, 1.0, 0.0))), up = cross(rt, fw);
    vec3 rd = normalize(p.x * rt + p.y * up + 1.6 * fw);
    float t = rd.y < 0.0 ? max(0.0, (ro.y - MAXH) / -rd.y) : 0.0;   // skip the air above the skyline
    float d = 1.0;
    for (int i = 0; i < 170; i++) {
        d = city(ro + rd * t);
        if (d < 0.0008 * t || t > 60.0) break;
        t += d * 0.85;
    }
    vec3 sky = skyCol(rd, sun, night);
    vec3 hazeC = mix(mix(vec3(0.6, 0.68, 0.78), vec3(0.85, 0.6, 0.45), smoothstep(0.2, 0.55, tod)), vec3(0.09, 0.05, 0.035), night);
    if (t > 60.0) return sky;
    vec3 pos = ro + rd * t;
    city(pos);
    float kind = gKind, bld = gBld;
    vec3 loc = gLocal, hs = gHalf;
    vec3 n = cityNormal(pos, 0.0008 * t);
    vec2 id = floor(pos.xz / BP);
    vec2 l = pos.xz - (id + 0.5) * BP;
    float px = t * 1.6 / uRes.y;                              // one pixel, in world units here

    float sh = night > 0.95 ? 0.0 : softShadow(pos + n * 0.004, sun);
    float ao = clamp(0.4 + 0.6 * city(pos + n * 0.06) / 0.06, 0.0, 1.0);
    float dif = max(dot(n, sun), 0.0) * sh;
    vec3 sunC = mix(vec3(1.0, 0.95, 0.88), vec3(1.0, 0.62, 0.35), smoothstep(0.2, 0.6, tod)) * (1.0 - smoothstep(0.5, 0.8, tod));
    vec3 ambC = mix(vec3(0.38, 0.46, 0.6), vec3(0.025, 0.03, 0.05), night);
    vec3 col, emit = vec3(0.0);
    float fres = pow(1.0 - max(dot(n, -rd), 0.0), 5.0);

    if (kind == 1.0) {
        float style = fract(bld * 7.13);                      // glass tower, stone/concrete, or brick
        vec3 base = style < 0.35 ? vec3(0.16, 0.22, 0.26) : style < 0.8 ? mix(vec3(0.62, 0.58, 0.52), vec3(0.45, 0.46, 0.48), fract(bld * 3.7)) : vec3(0.48, 0.27, 0.2);
        if (n.y > 0.5) {
            // roofs: gravel, plant rooms; red aircraft lights on the towers at night
            col = mix(vec3(0.32, 0.31, 0.3), vec3(0.22, 0.3, 0.18), step(0.85, fract(bld * 11.0))) * (0.8 + 0.3 * noise(pos.xz * 60.0));
            col *= ambC + sunC * dif * 1.4;
            if (hs.y > 0.8) emit += vec3(1.0, 0.05, 0.02) * step(0.5, fract(uRealTime * 0.7 + bld)) * smoothstep(0.03, 0.0, length(abs(loc.xz) - hs.xz * 0.9)) * 4.0 * night;
        } else {
            // facades: floors of windows
            float u = abs(n.x) > abs(n.z) ? loc.z : loc.x;
            float fy = loc.y / 0.03, fu = u / 0.026;
            vec2 wc = vec2(floor(fu), floor(fy));
            float win = step(0.22, fract(fu)) * step(0.28, fract(fy)) * step(0.06, loc.y) * step(loc.y, hs.y - 0.015);
            if (style < 0.35) win = max(win, 0.6);                // curtain wall: nearly all glass
            float far = smoothstep(0.012, 0.04, px);             // windows smaller than a pixel: use their average
            vec3 refl = skyCol(reflect(rd, n), sun, night);
            col = base * (ambC + sunC * dif * 1.3) * ao;
            vec3 glass = mix(vec3(0.03, 0.05, 0.06) * (1.0 - night * 0.8), refl * (1.0 - night * 0.6), 0.25 + 0.75 * fres) + sunC * pow(max(dot(reflect(rd, n), sun), 0.0), 60.0) * sh * 2.0;
            col = mix(col, glass, mix(win, 0.56, far) * (style < 0.35 ? 0.85 : 0.6));
            // lit windows at night: warm lamps, cool screens, some dark
            float hw = hash12(wc + bld * 97.0);
            float lit = step(hw, mix(0.08, 0.3, night)) * win;
            vec3 lamp = hw < 0.08 ? vec3(0.7, 0.8, 1.0) : mix(vec3(1.0, 0.7, 0.4), vec3(1.0, 0.85, 0.6), fract(hw * 13.0));
            float litAvg = mix(0.08, 0.3, night) * 0.56 * 0.35;
            vec3 glow = mix(lamp * lit * (0.6 + 0.8 * fract(hw * 31.0)), vec3(1.0, 0.8, 0.6) * litAvg, far);
            emit += glow * smoothstep(0.35, 0.8, tod) * 1.1;
        }
    } else if (kind == 2.0) {
        // the river: mirror-calm, the sky and (at night) the city's lights streaked across it
        vec3 refl = skyCol(reflect(rd, vec3(0.0, 1.0, 0.0)), sun, night);
        col = mix(vec3(0.03, 0.06, 0.07), refl, 0.15 + 0.85 * fres);
        float streak = noise(vec2(pos.x * 3.0, pos.z * 40.0 + uTime)) * noise(vec2(pos.x * 9.0, pos.z * 2.0));
        emit += vec3(1.0, 0.7, 0.4) * streak * streak * night * 0.55;
    } else if (kind == 3.0) {
        float tree = smoothstep(0.004, 0.03, pos.y);
        col = mix(vec3(0.22, 0.32, 0.14), vec3(0.1, 0.18, 0.08), tree) * (0.8 + 0.4 * noise(pos.xz * 40.0));
        col *= ambC + sunC * dif * 1.4;
    } else {
        // streets: asphalt, pale sidewalks along the blocks, lane markings, and the traffic
        float edgeD = BP * 0.5 - SW - max(abs(l.x), abs(l.y));    // < 0 in the street
        float side = smoothstep(0.0, -0.004, edgeD) * smoothstep(-0.022, -0.018, edgeD);
        col = mix(vec3(0.17, 0.17, 0.18), vec3(0.45, 0.44, 0.42), side);
        if (edgeD > 0.0) col = vec3(0.42, 0.41, 0.4);             // plazas / courtyards
        bool alongZ = abs(l.x) > abs(l.y);                        // which street we're on
        float across = alongZ ? (abs(l.x) - BP * 0.5) : (abs(l.y) - BP * 0.5);   // 0 at the street's middle
        float along = alongZ ? pos.z : pos.x;
        float laneSide = sign(alongZ ? l.x : l.y) * sign(across + 1e-4);
        float dash = step(abs(across), 0.0025) * step(0.5, fract(along * 6.0));
        col = mix(col, vec3(0.8, 0.75, 0.5), dash * (1.0 - night * 0.6));
        col *= ambC + sunC * dif * 1.4;
        // cars: one lane each way; headlights white, tail-lights red
        float lane = abs(across) - 0.03;
        if (abs(lane) < 0.012 && edgeD < -0.025) {
            float dir = across > 0.0 ? 1.0 : -1.0;
            vec2 sid = floor((alongZ ? pos.xz : pos.zx) / BP);
            float speed = 0.35 + 0.25 * hash12(sid + dir);
            float cc = (along - dir * uPulse * speed) * 3.2 + hash12(sid * 1.7 + dir) * 7.0;
            float car = step(fract(cc), 0.22) * step(0.4, hash12(vec2(floor(cc), sid.x + sid.y * 31.0 + dir)));
            vec3 paint = vec3(0.2) + 0.8 * vec3(hash12(vec2(floor(cc), 1.0)), hash12(vec2(floor(cc), 2.0)), hash12(vec2(floor(cc), 3.0)));
            col = mix(col, paint * (ambC + sunC * 1.2), car * (1.0 - night));
            float frontEnd = dir > 0.0 ? smoothstep(0.15, 0.22, fract(cc)) : smoothstep(0.07, 0.0, fract(cc));
            emit += mix(vec3(1.0, 0.1, 0.05), vec3(1.0, 0.95, 0.85), frontEnd) * car * smoothstep(0.4, 0.8, tod) * 2.5;
        }
        // sodium streetlights along the curbs
        float lampAlong = abs(fract(along * 4.0) - 0.5);
        float pool = exp(-(lampAlong * lampAlong) * 60.0) * exp(-pow(abs(across) - 0.06, 2.0) * 900.0);
        emit += vec3(1.0, 0.55, 0.2) * pool * smoothstep(0.45, 0.85, tod) * 0.9;
        // DATA (knob C): pulses flowing down the street grid, harder on the beat; thin survey lines on the curbs
        float pulse = pow(0.5 + 0.5 * sin(along * 2.0 - uPulse * 4.0 + hash12(floor((alongZ ? pos.xz : pos.zx) / BP)) * 6.3), 24.0);
        emit += glowpal(along * 0.05 + uD) * pulse * step(abs(across), 0.006) * uC * (1.0 + uBeat * 2.0) * 2.0;
        float survey = 1.0 - smoothstep(px * 0.5, px * 1.4, abs(edgeD));
        col = mix(col, vec3(1.0), survey * uC * mix(0.5, 0.18, night));
    }
    col += emit;
    // haze: blue by day, warm at golden hour, the orange glow of the city's own light at night
    col = mix(hazeC, col, exp(-max(t - 6.0, 0.0) * mix(0.022, 0.03, night)));
    return col;
}
