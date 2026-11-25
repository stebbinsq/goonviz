// @preset {"energy": 2, "family": "object3d", "heavy": true, "manual": true, "name": "Overkill", "labels": {"a": "load", "b": "look around", "c": "dispersion", "d": "color"}, "params": {"palette": 0, "glow": 0.3, "feedback": 0.85, "chroma": 0.0, "a": 0.15, "c": 0.5}}
// A spectral Monte Carlo path tracer, built to be too much. Every pixel fires many random light paths; each
// carries one wavelength and bounces through a glass gyroid sculpture (refraction with dispersion, so white
// light splits into rainbows), off a glossy floor and matte walls, and scatters through fog lit by direct
// light sampling (god rays). A real lens aperture gives depth of field. LOAD (A) sets samples per pixel and
// bounce depth; the top of the range is meant to bring a laptop to its knees. Trails average the noise.
// Manual only: autopilot and random picks never land on it. Frames are capped below the GPU watchdog.

float sdBox(vec3 p, vec3 b) { vec3 q = abs(p) - b; return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0); }

// ---- random numbers (PCG hash) ------------------------------------------------------------
uint gSeed;
float rnd() {
    gSeed = gSeed * 747796405u + 2891336453u;
    uint w = ((gSeed >> ((gSeed >> 28u) + 4u)) ^ gSeed) * 277803737u;
    return float((w >> 22u) ^ w) / 4294967295.0;
}
vec3 rndDir() {                                        // uniform on the sphere
    float z = rnd() * 2.0 - 1.0, a = rnd() * TAU;
    return vec3(sqrt(1.0 - z * z) * vec2(cos(a), sin(a)), z);
}
vec3 cosDir(vec3 n) { return normalize(n + rndDir()); }   // cosine-weighted about n

// ---- the scene -------------------------------------------------------------------------
// the glass sculpture: a gyroid lattice (the minimal surface found in butterfly wings) carved into a sphere,
// its cells shrinking toward the middle, slowly turning. A true signed distance, so rays can travel inside it.
mat3 gRot;
float crystal(vec3 p) {
    p = gRot * p;
    float r = length(p);
    float sc = 6.0;
    vec3 q = p * sc * (1.0 + 0.35 * (1.0 - r));
    float g = dot(sin(q), cos(q.yzx));
    float lattice = (abs(g) - 0.38 - uBass * 0.08) / (sc * 1.6);
    return max(lattice, r - 1.05);
}

const float FLOOR = -1.15;
const float ROOM = 4.5;
const float CEIL = 3.2;
const vec2 BOX = vec2(1.6, 1.6);    // softbox half-size, on the ceiling

// material ids: 0 glass, 1 floor, 2 walls, 3 softbox, 4 ring light, 5 side panels
float map(vec3 p, out int mat) {
    float d = crystal(p); mat = 0;
    float df = p.y - FLOOR;
    if (df < d) { d = df; mat = 1; }
    float dw = min(ROOM - max(abs(p.x), abs(p.z)), CEIL - p.y);
    if (dw < d) { d = dw; mat = 2; }
    float sb = sdBox(p - vec3(0.0, CEIL - 0.02, 0.0), vec3(BOX.x, 0.02, BOX.y));
    if (sb < d) { d = sb; mat = 3; }
    vec3 rq = p - vec3(0.0, 1.9, 0.0);
    float ring = length(vec2(length(rq.xz) - 1.5, rq.y)) - 0.05;
    if (ring < d) { d = ring; mat = 4; }
    float panel = sdBox(vec3(abs(p.x) - ROOM + 0.03, p.y - 0.4, p.z), vec3(0.03, 0.9, 1.4));
    if (panel < d) { d = panel; mat = 5; }
    return d;
}
float mapD(vec3 p) { int m; return map(p, m); }

vec3 normalAt(vec3 p) {
    vec2 h = vec2(0.0006, -0.0006);
    return normalize(h.xyy * mapD(p + h.xyy) + h.yyx * mapD(p + h.yyx) + h.yxy * mapD(p + h.yxy) + h.xxx * mapD(p + h.xxx));
}

// march; inside = travelling through glass (using the sculpture's interior distance)
float march(vec3 ro, vec3 rd, float tmax, bool inside, out int mat) {
    float t = 0.002;
    for (int i = 0; i < 120; i++) {
        vec3 p = ro + rd * t;
        float d;
        if (inside) { d = -crystal(p); mat = 0; } else d = map(p, mat);
        if (d < 0.0005 * (1.0 + t)) return t;
        t += d * 0.9;
        if (t > tmax) break;
    }
    mat = -1;
    return t;
}

vec3 ringLe(vec3 p) { return glowpal(0.5 + uD + atan(p.z, p.x) / TAU * 0.4) * (5.0 + uBass * 14.0); }
vec3 softboxLe() { return mix(vec3(1.0, 0.96, 0.9), glowpal(0.75 + uD), 0.25) * 3.0; }

vec3 emission(int mat, vec3 p) {
    if (mat == 3) return softboxLe();
    if (mat == 4) return ringLe(p);
    if (mat == 5) return glowpal(0.25 + uD + step(0.0, p.x) * 0.5) * (1.5 + uBeat * 6.0);
    return vec3(0.0);
}

// direct light from the softbox (next-event estimation): radiance arriving at p along a shadow ray,
// already divided by the sampling pdf; dir returned for the cosine term
vec3 softboxLight(vec3 p, out vec3 dir) {
    vec3 lp = vec3((rnd() * 2.0 - 1.0) * BOX.x, CEIL - 0.045, (rnd() * 2.0 - 1.0) * BOX.y);
    vec3 ld = lp - p;
    float l2 = dot(ld, ld), l = sqrt(l2);
    dir = ld / l;
    float cosL = max(dir.y, 0.0);                        // the softbox faces down; light leaves it downward
    if (cosL <= 0.0) return vec3(0.0);
    int sm;
    float st = march(p, dir, l - 0.03, false, sm);
    if (st < l - 0.06 && sm != 3) return vec3(0.0);     // blocked (glass blocks it too: caustics come from paths)
    float area = 4.0 * BOX.x * BOX.y;
    return softboxLe() * cosL * area / l2;
}

// direct light from the ring (a thin torus): pick a point on its circle, treat it as a glowing tube
vec3 ringLight(vec3 p, out vec3 dir) {
    float a = rnd() * TAU;
    vec3 lp = vec3(cos(a) * 1.5, 1.9, sin(a) * 1.5);
    vec3 ld = lp - p;
    float l2 = dot(ld, ld), l = sqrt(l2);
    dir = ld / l;
    lp -= dir * 0.06;                                    // aim at the near side of the tube
    int sm;
    float st = march(p, dir, l - 0.1, false, sm);
    if (st < l - 0.12 && sm != 4) return vec3(0.0);
    float area = TAU * 1.5 * TAU * 0.05;
    return ringLe(lp) * area * 0.5 / max(l2, 0.5);       // about half the tube faces any point (clamped up close)
}

// wavelength (nm) -> RGB weight, normalised so a uniform spectrum averages to white
vec3 spectrum(float l) {
    vec3 w = vec3(exp(-0.5 * pow((l - 600.0) / 40.0, 2.0)) + 0.35 * exp(-0.5 * pow((l - 445.0) / 22.0, 2.0)),
                  exp(-0.5 * pow((l - 550.0) / 42.0, 2.0)),
                  exp(-0.5 * pow((l - 450.0) / 28.0, 2.0)));
    return w * vec3(2.9294, 3.3246, 5.0179);
}

vec3 scene(vec2 p, vec2 uv) {
    gSeed = uint(gl_FragCoord.x) * 1973u + uint(gl_FragCoord.y) * 9277u + uint(mod(uRealTime * 60.0, 100000.0)) * 26699u + 1u;
    float a1 = uTime * 0.11, a2 = uTime * 0.07;
    gRot = mat3(cos(a1), 0.0, sin(a1), 0.0, 1.0, 0.0, -sin(a1), 0.0, cos(a1)) * mat3(1.0, 0.0, 0.0, 0.0, cos(a2), -sin(a2), 0.0, sin(a2), cos(a2));

    // LOAD (knob A): samples per pixel and bounce depth
    // hard cap: never more than ~3 million pixel-samples a frame, whatever the knob says (~0.3 s on an M4)
    int spp = min(1 + int(uA * uA * 31.0), max(1, int(3.0e6 / (uRes.x * uRes.y))));
    int bounces = 2 + int(uA * 4.0);                    // matte bounces; glass gets up to 24 events
    float ang = uTime * 0.05 + sin(uTime * 0.03) * uB * 1.5;
    vec3 ro = vec3(sin(ang) * 3.3, 0.15 + 0.25 * sin(uTime * 0.04), cos(ang) * 3.3);
    vec3 fw = normalize(-ro + vec3(0.0, -0.05, 0.0));
    vec3 rt = normalize(cross(fw, vec3(0.0, 1.0, 0.0))), up = cross(rt, fw);
    float focus = length(ro) - 0.4;
    const float SIGMA = 0.012;                          // fog density
    vec3 acc = vec3(0.0);
    for (int s = 0; s < 32; s++) {
        if (s >= spp) break;
        // the lens: jittered pixel, a round aperture focused on the sculpture
        vec2 jp = p + (vec2(rnd(), rnd()) - 0.5) * 2.0 / uRes.y;
        vec3 rd = normalize(jp.x * rt + jp.y * up + 1.7 * fw);
        vec3 fp = ro + rd * focus / dot(rd, fw);
        float la = rnd() * TAU, lr = sqrt(rnd()) * 0.05;
        vec3 o = ro + (rt * cos(la) + up * sin(la)) * lr;
        rd = normalize(fp - o);
        // each path carries one wavelength: the glass bends each colour by a different amount
        float lambda = 380.0 + (float(s) + rnd()) / float(spp) * 350.0;   // spread over the spectrum
        float ior = 1.5 + (0.004 + uC * 0.06) * (1.0 / pow(lambda * 0.001, 2.0) - 3.3);
        vec3 thr = vec3(1.0), col = vec3(0.0);
        bool inside = false, sampledLight = false;
        int diffuse = 0;
        for (int b = 0; b < 24; b++) {
            if (diffuse > bounces) break;
            int mat;
            float t = march(o, rd, 14.0, inside, mat);
            // fog: the photon may scatter before it reaches the surface
            float tf = inside ? 1e9 : -log(1.0 - rnd() * 0.9999) / SIGMA;
            if (tf < t) {
                o += rd * tf;
                vec3 ld;
                vec3 Li = softboxLight(o, ld) + ringLight(o, ld);
                col += thr * Li * 0.92 / (4.0 * PI);            // isotropic phase
                rd = rndDir();
                thr *= 0.92;
                sampledLight = true;
                diffuse++;
                continue;
            }
            if (mat < 0) break;
            vec3 pos = o + rd * t;
            if (mat >= 3) {
                // the softbox's direct light was already sampled by the last diffuse/fog event
                if (!((mat == 3 || mat == 4) && sampledLight)) col += thr * emission(mat, pos);
                break;
            }
            vec3 n = normalAt(pos);
            sampledLight = false;
            if (mat == 0) {
                // glass: Fresnel picks reflection or refraction for this wavelength
                vec3 nn = inside ? -n : n;
                float eta = inside ? ior : 1.0 / ior;
                float cosi = clamp(dot(-rd, nn), 0.0, 1.0);
                float r0 = pow((1.0 - ior) / (1.0 + ior), 2.0);
                float fr = r0 + (1.0 - r0) * pow(1.0 - cosi, 5.0);
                vec3 rr = refract(rd, nn, eta);
                if (dot(rr, rr) < 0.5 || rnd() < fr) {
                    rd = reflect(rd, nn);
                    o = pos + nn * 0.002;
                } else {
                    rd = rr;
                    o = pos - nn * 0.002;
                    inside = !inside;
                }
            } else {
                // floor (pale, slightly glossy, so it catches caustics) and matte walls
                vec3 alb = mat == 1 ? vec3(0.6) : vec3(0.32);
                if (mat == 1 && rnd() < 0.15) {
                    rd = normalize(reflect(rd, n) + rndDir() * 0.08);
                    o = pos + n * 0.002;
                    thr *= 0.9;
                } else {
                    vec3 ld, ld2;
                    vec3 Lb = softboxLight(pos + n * 0.003, ld);
                    vec3 Lr = ringLight(pos + n * 0.003, ld2);
                    col += thr * alb / PI * (Lb * max(dot(n, ld), 0.0) + Lr * max(dot(n, ld2), 0.0));
                    rd = cosDir(n);
                    o = pos + n * 0.003;
                    thr *= alb;
                    sampledLight = true;
                    diffuse++;
                }
            }
            if (diffuse > 1) {                               // Russian roulette
                float q = clamp(max(thr.x, max(thr.y, thr.z)), 0.05, 1.0);
                if (rnd() > q) break;
                thr /= q;
            }
        }
        acc += min(col, vec3(8.0)) * spectrum(lambda);       // clamp rare fireflies
    }
    return acc / float(spp) * 1.1;
}
