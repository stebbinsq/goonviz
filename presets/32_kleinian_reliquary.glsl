// @preset {"energy": 3, "family": "flight3d", "heavy": true, "name": "Kleinian Reliquary", "labels": {"a": "morph", "b": "look around", "c": "reflections", "d": "color"}, "params": {"palette": 0, "glow": 0.5, "feedback": 0.15, "chroma": 0.15, "c": 0.6, "a": 0.35}}
// A flight through a pseudo-Kleinian fractal: the limit set of a group of sphere inversions, which grows
// endless halls of nested round portals, lace walls and glass-like arches. Each chamber holds a relic:
// nested glowing wireframe polyhedra that keep morphing between Platonic and Archimedean solids. The relics
// light the chambers, shine in the polished walls, and pulse with the beat; light waves run through the veins.
// The space tiles seamlessly (the box fold is a mirror), so the flight never ends. Morph (A) reshapes the
// ornament from smooth organic tubes to fine lace without touching the halls the camera flies through.
// Heavy: best on a Mac.

const vec3 CS = vec3(0.808, 0.808, 1.167);
const float L = 2.334;          // chamber length (two per tile)
const vec2 AXIS = vec2(0.808);
const float RB = 0.17;          // relic bounding sphere

vec3 kTrap;
float jTrap;

float kleinian(vec3 p) {
    p = mod(p + 2.0 * CS, 4.0 * CS) - 2.0 * CS;
    float de = 1.0;
    float t1 = 1e3, t2 = 1e3;
    float size = 0.68 + uA * 0.4 + sin(uTime * 0.05) * 0.03;   // reshapes the ornament; the halls stay put
    for (int i = 0; i < 7; i++) {
        p = 2.0 * clamp(p, -CS, CS) - p;
        float r2 = dot(p, p);
        float k = max(size / r2, 1.0);
        p *= k;
        de *= k;
        t1 = min(t1, r2);
        t2 = min(t2, abs(p.z) + abs(p.x) * 0.3);
    }
    kTrap = vec3(t1, t2, log2(de));
    float rxy = length(p.xy);
    return max(rxy - 0.92784, abs(rxy * p.z) / length(p)) / de;
}

float chamber(float z) { return floor(z / L); }
vec3 relicPos(float z) { return vec3(AXIS, (chamber(z) + 0.5) * L); }
vec3 relicCol(float j) { return glowpal(uD + 0.1 + 0.37 * j); }

// The relic: three nested wireframe polyhedra from icosahedral mirror folds (Wythoff's construction, after
// knighty). Where the corner point sits inside the fold's triangle decides the solid (icosahedron,
// dodecahedron, the truncated and snub-like ones between); it drifts, so each shell keeps morphing.
const float COSPIN = 0.80901699;                       // cos(pi/5)
const vec3 NC = vec3(-0.5, -0.80901699, 0.30776835);    // fold plane normal; z = sqrt(0.75 - cos^2(pi/5))
const vec3 PAB = vec3(0.0, 0.0, 1.0);
const vec3 PBC = vec3(0.52573111, 0.0, 0.85065081);
const vec3 PCA = vec3(0.0, 0.35682209, 0.93417236);

vec3 icoFold(vec3 p) {
    for (int i = 0; i < 5; i++) {
        p.xy = abs(p.xy);
        p -= 2.0 * min(0.0, dot(p, NC)) * NC;
    }
    return p;
}

float wire(vec3 p, vec3 v, float r) {
    p -= v;
    float a = length(p - min(0.0, p.x) * vec3(1.0, 0.0, 0.0));
    float b = length(p - min(0.0, p.y) * vec3(0.0, 1.0, 0.0));
    float c = length(p - min(0.0, dot(p, NC)) * NC);
    return min(min(a, b), c) - r;
}

float jewel(vec3 q, float j) {
    float d = 1e3;
    jTrap = 0.0;
    for (int s = 0; s < 3; s++) {
        float fs = float(s);
        vec3 w = 0.55 + 0.45 * sin(uTime * (0.11 + 0.04 * fs) + j * vec3(1.3, 2.1, 0.7) + fs * vec3(2.0, 4.0, 1.0));
        vec3 v = normalize(w.x * PAB + w.y * PBC + w.z * PCA) * (1.0 - 0.3 * fs);
        vec3 r = q;
        r.xz = rot(uTime * (0.3 - 0.22 * fs) + j + fs) * r.xz;
        r.yz = rot(uTime * (0.17 + 0.1 * fs) - fs * 0.6) * r.yz;
        float e = wire(icoFold(r), v, 0.022 - 0.005 * fs);
        if (e < d) { d = e; jTrap = fs; }
    }
    return d;
}

vec3 path(float z) {
    float j = floor(z / L), f = z / L - j;
    float s = sin(PI * f);
    float r = 0.45 * s * s;
    float a = j * 2.39996 + f * 1.5;
    return vec3(AXIS + r * vec2(cos(a), sin(a)), z);
}

vec3 nrm(vec3 p, float e) {
    vec2 h = vec2(e, -e);
    return normalize(h.xyy * kleinian(p + h.xyy) + h.yyx * kleinian(p + h.yyx) +
                     h.yxy * kleinian(p + h.yxy) + h.xxx * kleinian(p + h.xxx));
}

// light falling on the walls from the two nearest relics
vec3 relicLight(vec3 pos, vec3 n, vec3 rd, out float glow, out vec3 spec) {
    vec3 c = vec3(0.0);
    glow = 0.0;
    spec = vec3(0.0);
    float j0 = chamber(pos.z);
    float j1 = j0 + (fract(pos.z / L) > 0.5 ? 1.0 : -1.0);
    for (int k = 0; k < 2; k++) {
        float j = k == 0 ? j0 : j1;
        vec3 ld = vec3(AXIS, (j + 0.5) * L) - pos;
        float d2 = dot(ld, ld);
        float a = (1.0 + uBeat * 1.2) / (0.03 + d2 * 0.9);
        glow += a;
        vec3 l = ld * inversesqrt(d2);
        c += relicCol(j) * (0.25 + max(dot(n, l), 0.0)) * a;
        spec += relicCol(j) * pow(max(dot(n, normalize(l - rd)), 0.0), 60.0) * a;
    }
    return c;
}

vec3 shade(vec3 pos, vec3 n, vec3 rd, float t, bool cheap) {
    float tr1 = kTrap.x, tr2 = kTrap.y;
    float ao = 1.0;
    if (!cheap) {
        float occ = 0.0, sca = 1.0;
        for (int k = 1; k <= 5; k++) {
            float h = 0.01 + 0.03 * float(k);
            occ += (h - kleinian(pos + n * h)) * sca;
            sca *= 0.7;
        }
        ao = clamp(1.0 - 3.0 * occ, 0.0, 1.0);
    }
    float la;
    vec3 sp;
    vec3 rl = relicLight(pos, n, rd, la, sp);
    float fres = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
    vec3 albedo = mix(vec3(0.1), pal(sqrt(tr1) * 1.3 + kTrap.z * 0.04 + uD + 0.2), 0.6);
    vec3 key = glowpal(uD + 0.8) * (0.15 + 0.85 * max(dot(n, normalize(vec3(0.4, 0.7, 0.3))), 0.0)) * 0.5;
    vec3 col = albedo * (0.03 + rl + key) * ao;
    col += albedo * glowpal(uD + 0.6) * max(dot(n, -rd), 0.0) * 0.5 / (1.0 + t * t * 3.0) * ao;   // lantern
    // thin-film iridescence on the rims
    col += glowpal(fres * 0.6 + tr1 + uD + 0.3) * fres * (0.2 + la * 0.3) * ao;
    col += sp * uC * 1.5 * ao;   // glossy highlights of the relics
    // luminous veins along the gasket rims; a wave travels through them with the music
    float vein = exp(-tr2 * 30.0);
    float wave = 0.3 + 0.7 * smoothstep(0.6, 1.0, sin(tr1 * 18.0 - uPulse * 4.0));
    float neon = 0.25 + 0.75 * pow(1.0 - max(dot(n, -rd), 0.0), 1.5) + 0.2 * sin(tr1 * 70.0);   // glass tubes: bright rims
    col += glowpal(uD + 0.55 + tr1 * 0.3) * vein * wave * neon * (0.9 + uBeat * 1.0);
    return col;
}

vec3 scene(vec2 p, vec2 uv) {
    float z = uPulse * 0.45;
    vec3 ro = path(z);
    vec3 fw = normalize(path(z + 0.35) - ro);
    float look = 0.15 + uB * 0.6;
    fw.xz = rot(look * sin(uTime * 0.09)) * fw.xz;
    fw.yz = rot(look * 0.7 * sin(uTime * 0.07 + 1.0)) * fw.yz;
    vec3 up0 = vec3(sin(uTime * 0.05), cos(uTime * 0.05), 0.0);
    vec3 rt = normalize(cross(fw, up0)), up = cross(rt, fw);
    float roll = (uBeatCount - uBeat * uBeat) * PI * 0.125;
    vec2 q = rot(roll) * p;
    vec3 rd = normalize(q.x * rt + q.y * up + 1.15 * fw);

    float t = 0.0, d = 1.0, pix = 1.6 / uRes.y;
    vec3 mist = vec3(0.0);
    bool relic = false;
    float hitJ = 0.0, halo = 0.0, haloJ = 0.0;
    for (int i = 0; i < 150; i++) {
        vec3 pos = ro + rd * t;
        d = kleinian(pos);
        vec3 rp = relicPos(pos.z);
        float j = chamber(pos.z);
        float dr = length(pos - rp) - RB;
        if (dr < 0.02) dr = max(dr, jewel((pos - rp) / RB, j) * RB);
        mist += glowpal(sqrt(kTrap.x) * 0.6 + uD) * exp(-d * 60.0) * 0.012 * exp(-t * 0.35);
        float hl = exp(-max(dr, 0.0) * 14.0);   // halo from how close the ray passes to a relic
        if (hl > halo) { halo = hl; haloJ = j; }
        float eps = pix * t * 0.6 + 0.0001;
        if (dr < eps * 0.5) { relic = true; hitJ = j; d = dr; break; }
        if (d < eps || t > 8.0) break;   // past this the fog has swallowed everything
        t += min(d, dr) * 0.85;
    }
    vec3 fogc = uPal[0] * 0.5 + uPal[1] * 0.05;
    vec3 col = fogc;
    vec3 pos = ro + rd * t;
    if (relic) {
        vec3 rp = relicPos(pos.z);
        vec3 lq = (pos - rp) / RB;
        vec2 e = vec2(0.001, -0.001);
        vec3 n = normalize(e.xyy * jewel(lq + e.xyy, hitJ) + e.yyx * jewel(lq + e.yyx, hitJ) +
                           e.yxy * jewel(lq + e.yxy, hitJ) + e.xxx * jewel(lq + e.xxx, hitJ));
        jewel(lq, hitJ);
        float fres = pow(1.0 - max(dot(n, -rd), 0.0), 2.0);
        col = glowpal(uD + 0.1 + 0.37 * hitJ + jTrap * 0.22) * (0.55 + 0.45 * max(dot(n, normalize(vec3(0.3, 0.8, -0.5))), 0.0));
        col += vec3(1.0) * fres * 0.4;
        col += vec3(1.0) * pow(max(dot(reflect(rd, n), normalize(vec3(0.3, 0.8, -0.5))), 0.0), 30.0);
        col *= (1.0 + uBeat * 0.7 + uHigh * 0.5) * (0.45 + 0.55 * smoothstep(0.15, 0.8, t));   // don't blind on a close pass
    } else if (d < 0.02) {
        vec3 n = nrm(pos, max(pix * t * 0.5, 0.0002));
        col = shade(pos, n, rd, t, false);
        // one reflection bounce: polished stone mirrors the glowing chambers (only up close: far off, fog hides it)
        float reflW = uC * smoothstep(4.5, 2.5, t);
        if (reflW > 0.01) {
        float fres = 0.3 + 0.7 * pow(1.0 - max(dot(n, -rd), 0.0), 4.0);
        vec3 r = reflect(rd, n);
        float t2 = 0.01, d2 = 1.0, glint = 0.0;
        vec3 rc = fogc;
        for (int i = 0; i < 32; i++) {
            vec3 p2 = pos + r * t2;
            d2 = kleinian(p2);
            float dr = length(p2 - relicPos(p2.z)) - RB;
            glint = max(glint, exp(-max(dr, 0.0) * 10.0));      // the relics shine in the polished walls
            if (d2 < pix * (t + t2) + 0.0002 || t2 > 2.5) break;
            t2 += min(d2, max(dr, 0.01)) * 0.9;
        }
        if (d2 < 0.02) {
            vec3 p2 = pos + r * t2;
            rc = mix(fogc, shade(p2, nrm(p2, 0.002), r, t + t2, true), exp(-t2 * 0.6));
        }
        col += (rc + relicCol(chamber(pos.z)) * glint * glint * 1.5) * fres * reflW;
        }
        col = mix(fogc, col, exp(-t * 0.25));
    }
    col += mist;
    col += relicCol(haloJ) * halo * halo * (0.35 + uBeat * 0.4 + uMid * 0.3) * smoothstep(0.1, 0.9, t);
    return col;
}
