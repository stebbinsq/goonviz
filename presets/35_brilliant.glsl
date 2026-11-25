// @preset {"energy": 2, "family": "object3d", "heavy": true, "name": "Brilliant", "labels": {"a": "fire", "b": "look around", "c": "beat snap", "d": "color"}, "params": {"palette": 0, "glow": 0.45, "feedback": 0.1, "chroma": 0.0, "a": 0.5, "c": 0.5}}
// A giant brilliant-cut diamond with real optics, in a dark temple of light. The gem is the intersection of 57
// facet planes in brilliant-cut proportions, so rays hit facets exactly (crisp, no noise). Light reflects off
// the crown, refracts in at diamond's index (2.42), bounces by total internal reflection, and wherever it leaks
// out it splits into wavelengths (dispersion, boosted past real diamond) - the fire. A mirror floor reflects
// it, with rainbow flecks where its fire lands, and a sacred-geometry halo turns behind it. FIRE (A) sets the
// wavelengths, bounces and antialiasing; BEAT SNAP (C) clicks it round a facet on the beat.

// ---- the gem: a brilliant cut as the intersection of 57 half-spaces (exact, so rays hit facets analytically) --
const int NP = 57;
vec4 gP[57];       // facet planes: xyz = outward normal, w = offset (inside where dot(n, p) < w)

void buildGem() {
    const float CROWN = 0.6021;    // 34.5 degrees
    const float PAV = 0.7112;      // 40.75 degrees
    int k = 0;
    gP[k++] = vec4(0.0, 1.0, 0.0, 0.34);                    // table
    for (int i = 0; i < 8; i++) {
        float a = float(i) * PI * 0.25;
        float b = a + PI * 0.125;
        // crown: bezel (main) facets, stars between them near the table, upper girdle facets near the edge
        gP[k++] = vec4(sin(CROWN) * cos(a), cos(CROWN), sin(CROWN) * sin(a), sin(CROWN) * 1.0 + 0.03 * cos(CROWN));
        gP[k++] = vec4(sin(0.38) * cos(b), cos(0.38), sin(0.38) * sin(b), 0.3 * cos(0.38) + 0.62 * sin(0.38));
        gP[k++] = vec4(sin(0.73) * cos(b), cos(0.73), sin(0.73) * sin(b), sin(0.73) * 1.005 + 0.03 * cos(0.73));
        // pavilion: main facets down to the culet, lower girdle facets between them
        gP[k++] = vec4(sin(PAV) * cos(a), -cos(PAV), sin(PAV) * sin(a), sin(PAV) * 1.0 + 0.0);
        gP[k++] = vec4(sin(0.77) * cos(b), -cos(0.77), sin(0.77) * sin(b), sin(0.77) * 1.003);
        // the girdle: a ring of thin vertical facets
        gP[k++] = vec4(cos(a), 0.0, sin(a), 1.0);
        gP[k++] = vec4(cos(b), 0.0, sin(b), 1.0);
    }
}

mat3 gRot;   // the gem's turn

// ray vs gem (in the gem's frame): entry/exit distances and the facet normals there
bool hitGem(vec3 ro, vec3 rd, out float t0, out float t1, out vec3 n0, out vec3 n1) {
    t0 = -1e9; t1 = 1e9;
    n0 = vec3(0.0); n1 = vec3(0.0);
    for (int i = 0; i < NP; i++) {
        vec3 n = gP[i].xyz;
        float dn = dot(n, rd), dist = gP[i].w - dot(n, ro);
        if (abs(dn) < 1e-6) { if (dist < 0.0) return false; continue; }
        float t = dist / dn;
        if (dn < 0.0) { if (t > t0) { t0 = t; n0 = n; } }   // entering this half-space
        else { if (t < t1) { t1 = t; n1 = n; } }            // leaving it
    }
    return t0 < t1;
}

// ---- the temple of light around it: dark, with a filigree dome and small hot lights (they make the fire) ----
vec3 env(vec3 d, float lights, bool nebula) {
    float el = asin(clamp(d.y, -1.0, 1.0));
    float az = atan(d.z, d.x);
    vec3 c = uPal[0] * 0.12;
    if (nebula) {
        float neb = fbm(vec2(az * 1.6, el * 3.0) + uTime * 0.01);
        c += glowpal(neb + uD + el * 0.2) * neb * neb * neb * 0.35;
    }
    // the mandala dome overhead: luminous filigree in a stereographic view of the sky
    if (d.y > -0.1) {
        vec2 q = d.xz / (1.0 + d.y + 0.15);
        float r = length(q), a = atan(q.y, q.x);
        float petal = abs(fract(a * 24.0 / TAU + 0.5) - 0.5);
        float lr = log(r + 1e-3);
        float ring = abs(fract(lr * 4.0 - uTime * 0.04) - 0.5);
        float ring2 = abs(fract(lr * 9.0 + petal * 3.0) - 0.5);
        float arcs = abs(fract(a * 12.0 / TAU + lr * 2.0) - 0.5);
        float fil = exp(-petal * 90.0) * smoothstep(0.05, 0.3, ring) * 0.7 + exp(-ring * 120.0) + exp(-ring2 * 140.0) * 0.45
                  + exp(-arcs * 110.0) * 0.35;
        c += glowpal(lr * 0.25 + uD + 0.5) * fil * 0.55 * smoothstep(-0.1, 0.35, d.y);
    }
    // a thin line of light on the horizon, and slim light strips around us
    c += glowpal(0.25 + uD) * exp(-abs(el + 0.02) * 40.0) * 0.6;
    float strip = pow(max(cos(az * 4.0 + 0.4 + uTime * 0.05), 0.0), 2500.0) * smoothstep(0.55, 0.35, abs(el - 0.3));
    c += mix(vec3(1.0), glowpal(az / TAU + uD), 0.6) * strip * 4.0 * (1.0 + uBeat * 1.5) * mix(0.25, 1.0, lights);
    // small hot lights all around: these are what make a diamond throw fire
    for (int i = 0; i < 9; i++) {
        float fi = float(i);
        vec3 L = normalize(vec3(cos(fi * 2.4 + 0.3), 0.15 + 0.6 * fract(fi * 0.37), sin(fi * 2.4 + 0.3)));
        c += mix(vec3(1.0), glowpal(fi * 0.17 + uD), 0.55) * pow(max(dot(d, L), 0.0), 2200.0) * 60.0 * (1.0 + uBass) * lights;
    }
    // the ring light right overhead
    c += glowpal(0.5 + uD) * exp(-abs(el - 1.22) * 60.0) * 2.5 * (1.0 + uBass * 2.0);
    return c;
}

// wavelength (nm) -> RGB weight, normalised so a uniform spectrum averages to white
vec3 spectrum(float l) {
    vec3 w = vec3(exp(-0.5 * pow((l - 600.0) / 40.0, 2.0)) + 0.35 * exp(-0.5 * pow((l - 445.0) / 22.0, 2.0)),
                  exp(-0.5 * pow((l - 550.0) / 42.0, 2.0)),
                  exp(-0.5 * pow((l - 450.0) / 28.0, 2.0)));
    return w * vec3(2.9294, 3.3246, 5.0179);
}

float fresnel(float cosi, float n1, float n2) {
    float sint = n1 / n2 * sqrt(max(0.0, 1.0 - cosi * cosi));
    if (sint >= 1.0) return 1.0;
    float cost = sqrt(max(0.0, 1.0 - sint * sint));
    float rs = (n1 * cosi - n2 * cost) / (n1 * cosi + n2 * cost);
    float rp = (n1 * cost - n2 * cosi) / (n1 * cost + n2 * cosi);
    return 0.5 * (rs * rs + rp * rp);
}

// the gem as seen along a ray (world space): reflection off the facet it hits plus every wavelength's own path
// through it, entering, bouncing by total internal reflection, and leaking out into the room
vec3 gemColor(vec3 ro, vec3 rd, int nw, int nb, float disp, out bool hit) {
    hit = false;
    float bq = dot(ro, rd), bc = dot(ro, ro) - 1.1;            // bounding sphere first: most rays miss the gem
    if (bq * bq - bc < 0.0) return vec3(0.0);
    vec3 o = gRot * ro, d = gRot * rd;
    mat3 back = transpose(gRot);
    float t0, t1;
    vec3 n0, n1;
    hit = hitGem(o, d, t0, t1, n0, n1) && t0 > 0.0;
    if (!hit) return vec3(0.0);
    vec3 pos = o + d * t0;
    float cosi = max(dot(-d, n0), 0.0);
    vec3 col = env(back * reflect(d, n0), 1.0, false) * fresnel(cosi, 1.0, 2.42);
    // one path through the inside (at diamond's mean index), split into wavelengths wherever light leaks out
    const float IOR = 2.42;
    vec3 dir = refract(d, n0, 1.0 / IOR);
    float thr = 1.0 - fresnel(cosi, 1.0, IOR);
    vec3 q = pos + dir * 1e-4;
    vec3 lc = vec3(0.0);
    for (int b = 0; b < 10; b++) {
        if (b >= nb) break;
        float e0, e1;
        vec3 m0, m1;
        hitGem(q - dir * 0.01, dir, e0, e1, m0, m1);        // from inside: e1 is where we reach the far facet
        vec3 hp = q - dir * 0.01 + dir * e1;
        float ci = max(dot(dir, m1), 0.0);
        float fr = fresnel(ci, IOR, 1.0);
        if (fr < 1.0) {
            vec3 leak = vec3(0.0);
            for (int w = 0; w < 16; w++) {
                if (w >= nw) break;
                float lambda = 380.0 + (float(w) + 0.5) / float(nw) * 350.0;
                float ior = IOR + disp * (1.0 / pow(lambda * 0.001, 2.0) - 3.3) * 0.25;
                vec3 out_ = refract(dir, -m1, ior);
                if (dot(out_, out_) > 0.5) leak += env(back * out_, 1.0, false) * spectrum(lambda);
            }
            lc += leak / float(nw) * thr * (1.0 - fr);
        }
        thr *= fr;                                           // the rest reflects back inside
        dir = reflect(dir, -m1);
        q = hp + dir * 1e-4;
        if (thr < 0.01) break;
    }
    return col + lc;
}

// a radiant sacred-geometry halo behind the gem, drawn around its place on screen
vec3 halo(vec2 q) {
    float r = length(q), a = atan(q.y, q.x);
    float spin = uTime * 0.05;
    float petal = abs(fract((a + spin) * 12.0 / TAU + 0.5) - 0.5);
    float petal2 = abs(fract((a - spin * 1.7) * 24.0 / TAU + 0.5) - 0.5);
    float lr = log(r + 1e-3);
    float rings = abs(fract(lr * 3.0 - uTime * 0.06) - 0.5);
    float lace = exp(-abs(petal - 0.25 * smoothstep(0.4, 1.4, r)) * 70.0) * smoothstep(0.35, 0.6, r) * smoothstep(1.9, 1.1, r);
    lace += exp(-rings * 80.0) * smoothstep(0.4, 0.7, r) * 0.7;
    lace += exp(-petal2 * 120.0) * smoothstep(0.9, 1.1, r) * smoothstep(1.6, 1.3, r) * 0.6;
    float rays = pow(0.5 + 0.5 * cos((a + spin * 0.5) * 36.0), 30.0) * exp(-r * 1.2) * smoothstep(0.3, 0.5, r);
    vec3 c = glowpal(lr * 0.3 + uD + 0.5) * lace * (0.55 + uMid * 0.5);
    c += glowpal(0.5 + uD) * rays * (0.4 + uBeat * 0.8);
    c += glowpal(0.75 + uD) * exp(-r * 2.5) * 0.12;
    return c;
}

vec3 scene(vec2 p, vec2 uv) {
    buildGem();
    float snap = (uBeatCount - uBeat * uBeat) * uC * PI * 0.125;   // the gem clicks round a facet on the beat
    float a1 = uTime * 0.12 + snap, a2 = 0.35 + 0.25 * sin(uTime * 0.07);
    gRot = mat3(cos(a1), 0.0, -sin(a1), 0.0, 1.0, 0.0, sin(a1), 0.0, cos(a1));
    gRot = mat3(1.0, 0.0, 0.0, 0.0, cos(a2), sin(a2), 0.0, -sin(a2), cos(a2)) * gRot;
    float ang = uTime * 0.04 + sin(uTime * 0.05) * uB;
    vec3 ro = vec3(sin(ang) * 2.15, 0.85 + 0.3 * sin(uTime * 0.03), cos(ang) * 2.15);
    vec3 fw = normalize(vec3(0.0, -0.08, 0.0) - ro);
    vec3 rt = normalize(cross(fw, vec3(0.0, 1.0, 0.0))), up = cross(rt, fw);
    const float FL = 2.1;
    // FIRE (knob A): more wavelengths, more internal bounces, more antialiasing
    int nw = 4 + int(uA * 12.0);
    int nb = 4 + int(uA * 6.0);
    int aa = uA > 0.66 ? 2 : 1;
    float disp = 0.09 + uA * 0.12;                      // past real diamond, on purpose: more fire
    const float FLOOR = -1.05;
    // the gem's centre on screen, for the halo
    vec3 gv = vec3(0.0, -0.1, 0.0) - ro;
    vec2 gscr = vec2(dot(gv, rt), dot(gv, up)) / dot(gv, fw) * FL;
    vec3 acc = vec3(0.0);
    for (int sy = 0; sy < 2; sy++) for (int sx = 0; sx < 2; sx++) {
        if (sx >= aa || sy >= aa) continue;
        vec2 jp = p + (vec2(float(sx), float(sy)) + 0.5 - float(aa) * 0.5) / float(aa) * 2.0 / uRes.y;
        vec3 rd = normalize(jp.x * rt + jp.y * up + FL * fw);
        bool hit;
        vec3 col = gemColor(ro, rd, nw, nb, disp, hit);
        if (!hit) {
            float tf = (FLOOR - ro.y) / rd.y;
            if (rd.y < 0.0 && tf > 0.0) {
                // the black mirror floor: the gem and the room reflected in it, and a pool of the gem's fire
                vec3 fp = ro + rd * tf;
                vec3 rr = reflect(rd, vec3(0.0, 1.0, 0.0));
                bool rh;
                vec3 refl = gemColor(fp, rr, max(3, nw / 3), max(3, nb / 2), disp, rh);
                if (!rh) refl = env(rr, 0.1, true);
                float fres = 0.25 + 0.75 * pow(1.0 - max(-rd.y, 0.0), 4.0);
                // the gem's fire landing on the floor: scattered rainbow flecks that shift as it turns
                float fr = length(fp.xz);
                vec3 fire = vec3(0.0);
                for (int k = 0; k < 2; k++) {
                    vec2 g = rot(a1 * (1.0 + float(k) * 0.6)) * fp.xz * (9.0 + float(k) * 7.0);
                    vec2 id = floor(g), f = fract(g) - 0.5;
                    vec2 h = hash22(id + float(k) * 31.0 + floor(snap * 2.0));
                    float fleck = smoothstep(0.12, 0.0, length(f - (h - 0.5) * 0.7)) * step(0.72, h.x);
                    fire += spectrum(380.0 + h.y * 350.0) * fleck;
                }
                fire *= smoothstep(1.7, 0.4, fr) * 0.35 * (0.6 + uBass + uBeat);
                col = refl * fres * 0.75 + fire + uPal[0] * 0.04;
                col *= smoothstep(9.0, 3.0, tf);
                col += env(rd, 0.1, true) * (1.0 - smoothstep(9.0, 3.0, tf));
            } else {
                col = env(rd, 0.1, true) + halo((jp - gscr) * 0.62) * 3.0;
            }
        }
        acc += col;
    }
    return acc / float(aa * aa);
}
