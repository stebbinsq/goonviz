// @preset {"energy": 1, "family": "flight3d", "heavy": true, "name": "Vortex", "labels": {"a": "particles", "b": "palette", "c": "twist", "d": "depth of field"}, "params": {"palette": 5, "glow": 0.45, "feedback": 0.0, "chroma": 0.02, "a": 0.6, "b": 0.0, "c": 0.5, "d": 0.3}}
// A whirlpool of particles: a disc of concentric ring strands whose plane tilts with radius, so the outer
// rings lie flat, the inner ones twist up into a spout, and the whole sheet warps like silk in a vortex.
// Clumps stream around each ring at its own speed (faster inside, like real orbits), so the flow shears.
// Rendered like Stardust: real particles placed one per voxel by a 3D DDA (stable, no flicker), drawn as
// discs of max(pixel, circle of confusion), plus a soft glow where the strands are densest.
// A = particle count, B = palette tint, C = twist, D = depth of field. Beats pull the rings tighter.

vec3 hash33(vec3 p3) {
    p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}
float hash13(vec3 p3) {
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec3 p) {
    vec3 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
               mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

const float R = 1.25;     // the cloud's bounding sphere
const float CS = 0.013;   // voxel size of the fine particles
const float BS = 0.55;    // voxel size of the bokeh dust

// the vortex sheet: 0 empty .. ~1 on a dense ring strand
float dust(vec3 p) {
    float r = length(p);
    float tw = 0.6 + uC * 1.6;
    // the ring plane tilts with radius (spout inside, flat outside) and precesses slowly
    float tilt = mix(1.35, -0.2, smoothstep(0.12, 1.0, r)) * (0.5 + 0.5 * tw) + 0.2 * sin(uTime * 0.05);
    float az = r * 2.2 * tw - uTime * 0.05;
    vec3 n = vec3(sin(tilt) * cos(az), cos(tilt), sin(tilt) * sin(az));
    float hgt = dot(p, n) + 0.05 * (vnoise(p * 3.0 + uTime * 0.05) - 0.5);
    float w = 0.012 + 0.05 * r * r;
    float sheet = exp(-hgt * hgt / (w * w));
    // angle around the ring, in the ring's own plane
    vec3 b1 = normalize(cross(n, vec3(0.31, 0.12, 0.94)));
    vec3 b2 = cross(n, b1);
    float ang = atan(dot(p, b2), dot(p, b1));
    // concentric strands, tightening on the beat
    float rr = r * (1.0 + uBeat * 0.04);
    float rings = pow(0.5 + 0.5 * cos(rr * 85.0 + sin(p.x * 3.0 + p.z * 2.0) * 2.0), 4.0);
    // clumps streaming around: inner rings orbit faster
    float flow = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(ang * 3.0 - uTime * 0.35 / (r + 0.25) + r * 9.0), 2.0);
    float env = smoothstep(0.06, 0.25, r) * smoothstep(R, 0.8, r);
    // the inner edge is brightest, like the reference's luminous throat
    return env * sheet * (0.15 + 0.85 * rings) * flow * (0.6 + 0.9 * smoothstep(0.6, 0.2, r));
}

vec3 tint(vec3 c, float k) { return mix(c, glowpal(k) * luma(c) * 1.8, uB); }

vec3 scene(vec2 p, vec2 uv) {
    float ang = uTime * 0.025;
    vec3 ro = vec3(sin(ang) * 1.85, 0.6 + 0.35 * sin(uTime * 0.021), cos(ang) * 1.85);
    vec3 fw = normalize(-ro + vec3(0.0, 0.05, 0.0));
    vec3 rt = normalize(cross(fw, vec3(0.0, 1.0, 0.0))), up = cross(rt, fw);
    vec3 rd = normalize(p.x * rt + p.y * up + 1.7 * fw);
    rd += 1e-6 * step(abs(rd), vec3(1e-6));
    float pix = 2.0 / (uRes.y * 1.7);                                        // one pixel's width per unit distance
    float focus = length(ro);
    float aper = uD * 0.05;
    vec3 col = vec3(0.0);
    float dens = uA * uA * 1.3 + 0.12;                                     // particles per unit of field

    // ---- the cloud: voxel DDA inside the bounding sphere, in a tilted frame so voxel layers never line up with the view
    mat3 G = mat3(0.8165, -0.4082, -0.4082, 0.0, 0.7071, -0.7071, 0.5774, 0.5774, 0.5774);
    vec3 rd0 = rd, ro0 = ro;
    rd = G * rd; ro = G * ro;
    rd += 1e-6 * step(abs(rd), vec3(1e-6));
    float b = dot(ro, rd), c = dot(ro, ro) - R * R, h = b * b - c;
    if (h > 0.0) {
        h = sqrt(h);
        float t0 = max(-b - h, 0.0), t1 = -b + h;
        vec3 ps = (ro + rd * (t0 + 1e-4)) / CS;
        vec3 cell = floor(ps);
        vec3 sg = sign(rd);
        vec3 tDel = abs(CS / rd);
        vec3 tMax = ((cell + max(sg, 0.0)) * CS - ro) / rd;
        float t = t0;
        vec3 haze = vec3(0.0);
        for (int i = 0; i < 420; i++) {
            float tn = min(tMax.x, min(tMax.y, tMax.z));
            vec3 cc = (cell + 0.5) * CS;
            float f = dust(cc * G);                               // back to the world frame
            vec3 hh = hash33(cell);
            if (hh.x < f * dens * 1.6) {
                // a particle somewhere in this voxel, drifting a little
                vec3 hp = hash33(cell + 71.3);
                vec3 q = cc + (hp - 0.5) * CS * 0.86 + 0.06 * CS * sin(uRealTime * (0.5 + hp.zxy) + hp * 6.28);
                vec3 rel = q - ro;
                float tq = dot(rel, rd);
                float dp = length(rel - rd * tq);
                float rp = max(pix * tq, min(abs(tq - focus) * aper, CS * 0.45));
                float e = exp(-dp * dp / (rp * rp) * 1.8) * (pix * tq * pix * tq) / (rp * rp);
                float br = 0.35 + 2.5 * pow(hh.y, 6.0);                    // a few much brighter grains
                vec3 pc = hh.z < 0.06 ? vec3(1.0, 0.7, 0.85) : mix(vec3(0.5, 0.55, 1.0), vec3(0.92, 0.94, 1.0), smoothstep(0.1, 0.7, f));
                col += tint(pc, hh.y + f) * e * br;
            }
            if (tn > t1) break;
            t = tn;
            if (tMax.x == tn) { cell.x += sg.x; tMax.x += tDel.x; }
            else if (tMax.y == tn) { cell.y += sg.y; tMax.y += tDel.y; }
            else { cell.z += sg.z; tMax.z += tDel.z; }
        }
        // the luminous gas along the filaments: a separate smooth march (per-voxel samples would band)
        float hs = (t1 - t0) / 56.0;
        float th = t0 + hs * hash12(uv * uRes);
        for (int i = 0; i < 56; i++) {
            float f = dust((ro + rd * th) * G);
            haze += f * hs * 1.6 * mix(vec3(0.3, 0.35, 0.9), vec3(0.75, 0.8, 1.0), f);
            th += hs;
        }
        col += tint(haze, 0.3) * 0.4 * (1.0 + uBeat * 0.5);
    }

    rd = rd0; ro = ro0;

    // ---- the bokeh dust: sparse coarse voxels between the camera and well behind the cloud
    {
        vec3 cell = floor(ro / BS);
        vec3 sg = sign(rd);
        vec3 tDel = abs(BS / rd);
        vec3 tMax = ((cell + max(sg, 0.0)) * BS - ro) / rd;
        float t = 0.0;
        for (int i = 0; i < 28; i++) {
            float tn = min(tMax.x, min(tMax.y, tMax.z));
            vec3 hh = hash33(cell * 1.7 + 11.0);
            if (hh.x < 0.003 + uA * 0.004) {
                vec3 hp = hash33(cell + 5.1);
                vec3 q = (cell + 0.5 + (hp - 0.5) * 0.4) * BS + 0.04 * sin(uRealTime * 0.3 + hp * 6.28);
                vec3 rel = q - ro;
                float tq = dot(rel, rd);
                if (tq > 0.15) {
                    // bokeh discs are round on the sensor, so measure them in screen space (no wide-angle stretch)
                    float zf = dot(rel, fw);
                    vec2 sp = vec2(dot(rel, rt), dot(rel, up)) / zf * 1.7;
                    float dp = length(sp - p);
                    float rp = max(pix * 1.7 * 1.5, min(abs(zf - focus) * aper * 2.2, BS * 0.3) / zf * 1.7);
                    float disc = smoothstep(rp, rp * 0.82, dp);            // a hard-edged lens disc
                    float rim = smoothstep(rp * 0.6, rp, dp) * 0.6 + 0.6;   // brighter at the rim, like real bokeh
                    // chromatic fringe: warm on one side, cool on the other
                    vec3 fr = mix(vec3(1.0, 0.55, 0.25), vec3(0.45, 0.65, 1.0), smoothstep(-rp, rp, (sp.x - p.x) + (sp.y - p.y)));
                    vec3 pc = hh.z < 0.3 ? vec3(1.0, 0.75, 0.9) : vec3(0.7, 0.75, 1.0);
                    float e = disc * rim * clamp(pix * 1.7 * 6.0 / rp, 0.12, 1.0) * (0.3 + 1.2 * hh.y * hh.y);
                    col += tint(mix(pc, fr, 0.5), hh.y) * e * 1.4;
                }
            }
            if (tn > 9.0) break;
            t = tn;
            if (tMax.x == tn) { cell.x += sg.x; tMax.x += tDel.x; }
            else if (tMax.y == tn) { cell.y += sg.y; tMax.y += tDel.y; }
            else { cell.z += sg.z; tMax.z += tDel.z; }
        }
    }
    return col;
}
