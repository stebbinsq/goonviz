// @preset {"energy": 1, "family": "flight3d", "heavy": true, "name": "Coastline", "labels": {"a": "dive speed", "b": "look around", "c": "survey lines", "d": "film"}, "params": {"palette": 5, "glow": 0.22, "feedback": 0.0, "chroma": 0.03, "c": 0.5, "a": 0.4, "d": 0.0}}
// An endless dive toward a fractal coastline, shot like aerial photography (after Max Cooper's science-art).
// The land has detail at every scale: the octaves of its noise slide down the scale as we zoom, new fine ones
// fading in as coarse ones fade out, so the dive never ends and the coastline only gets more intricate (the
// coastline paradox). Thin white survey lines trace the shore, the contours and a grid that subdivides as we
// fall, pulsing with the beat. Film (D): natural colour, silver monochrome, false-colour infrared.

const int NOCT = 12;
const float ALT = 1.0;      // camera height, in view units (the world rescales around us)

float gS;      // zoom level: grows forever
vec2 gC;       // the point we dive toward, on the ground
float gMoist;  // mid-scale variation of the last terrain() call (forest vs fields)
float gTex;    // fine-scale variation (tree canopy, rock texture)

// value noise with its derivatives (after iq): x = value 0..1, yz = gradient
vec3 noised(vec2 x) {
    vec2 i = floor(x), f = fract(x);
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
    float a = hash12(i), b = hash12(i + vec2(1.0, 0.0)), c = hash12(i + vec2(0.0, 1.0)), d = hash12(i + vec2(1.0, 1.0));
    float k1 = b - a, k2 = c - a, k4 = a - b - c + d;
    return vec3(a + k1 * u.x + k2 * u.y + k4 * u.x * u.y, du * vec2(k1 + k4 * u.y, k2 + k4 * u.x));
}

// height (view units) and gradient at ground point x; octaves finer than `lod` are skipped
vec3 terrain(vec2 x, float lod) {
    vec2 q = rot(uTime * 0.012) * (x - gC);
    float fs = fract(gS), is = floor(gS);
    float h = 0.0;
    vec2 g = vec2(0.0), dsum = vec2(0.0);
    gMoist = 0.0;
    gTex = 0.0;
    for (int k = 0; k < NOCT; k++) {
        float rel = float(k) - fs;                       // this octave's place in the stack: 0 coarse .. fine
        float freq = 0.3 * exp2(rel);
        if (freq * lod > 1.1) break;                     // smaller than a pixel from here
        float amp = 0.42 * exp2(-rel * 0.95);
        float w = smoothstep(0.0, 1.0, rel) * (1.0 - smoothstep(float(NOCT) - 2.0, float(NOCT) - 1.0, rel));
        vec2 off = hash22(vec2(is + float(k), 3.7)) * 64.0;   // each octave its own field, stable as it slides
        vec3 n = noised(q * freq + off);
        dsum += n.yz * freq * amp * w;
        float ero = 1.0 / (1.0 + dot(dsum, dsum) * 0.6);      // erosion: steep ground keeps less fine detail
        // inland the noise turns ridged: sharp mountain crests and drainage valleys
        float rmix = smoothstep(0.04, 0.16, h) * step(1.0, rel);
        float ridge = 1.0 - abs(n.x * 2.0 - 1.0);
        float v = mix(n.x - 0.5, (ridge - 0.62) * 0.9, rmix);
        vec2 gv = mix(n.yz, -sign(n.x * 2.0 - 1.0) * 2.0 * n.yz * 0.9, rmix);
        h += amp * w * v * ero;
        g += amp * w * gv * freq * ero;
        if (rel > 1.5 && rel < 5.0) gMoist += (n.x - 0.5) * w * exp2(-(rel - 1.5) * 0.5);
        if (rel > 5.0) gTex += (n.x - 0.5) * w;
    }
    g = g * rot(uTime * 0.012);                          // gradient back to view axes
    return vec3(h + 0.03, g);
}

// clouds we fall through: three sheets that rise toward the camera as we dive, then pass above it
float cloudY(int m) { return ALT * (exp2(fract(gS * 0.5 + float(m) / 3.0) * 2.0) - 1.0) / 3.0; }

float cloudSheet(vec2 x, int m, out float y) {
    float ph = fract(gS * 0.5 + float(m) / 3.0);
    float sc = exp2(ph * 2.0);
    y = ALT * (sc - 1.0) / 3.0;
    vec2 q = rot(uTime * 0.012) * (x - gC) / sc + float(m) * 17.3 + vec2(uTime * 0.01, 0.0);
    float d = fbm(q * 2.2) * 0.8 + fbm(q * 7.0) * 0.25 - 0.66 + 0.04 * float(m);
    d = smoothstep(0.0, 0.12, d);
    return d * smoothstep(0.0, 0.15, ph) * (1.0 - smoothstep(0.6, 0.85, ph)) * 0.92;
}

vec3 sky(vec3 rd) {
    return mix(vec3(0.55, 0.63, 0.74), vec3(0.22, 0.36, 0.58), smoothstep(-0.1, 0.5, rd.y));
}

vec3 scene(vec2 p, vec2 uv) {
    gS = uTime * (0.03 + uA * 0.18) + (uPulse - uTime) * 0.03;
    float pitch = 0.78 + 0.08 * sin(uTime * 0.05);
    vec3 ro = vec3(0.0, ALT, 0.0);
    vec3 fw = normalize(vec3(sin(uTime * 0.04) * (0.05 + uB * 0.35), -sin(pitch), cos(pitch)));
    gC = vec2(0.0, ALT / tan(pitch));                    // dive toward the point the camera looks at
    vec3 rt = normalize(cross(fw, vec3(0.0, 1.0, 0.0))), up = cross(rt, fw);
    vec3 rd = normalize(p.x * rt + p.y * up + 1.6 * fw);
    float pixA = 1.4 / uRes.y;                           // pixel footprint per unit of distance

    // march the height field (the sea is flat at 0)
    float t = rd.y < 0.0 ? (ALT - 0.45) / -rd.y : 0.02;   // nothing stands taller than 0.45: skip the air
    vec3 ter;
    for (int i = 0; i < 110; i++) {
        vec3 pos = ro + rd * t;
        ter = terrain(pos.xz, t * pixA * 5.0);           // coarse while searching
        float dh = pos.y - max(ter.x, 0.0);
        if (dh < 0.0015 * t || t > 9.0) break;
        t += dh * (dh > 0.04 ? 0.8 : 0.45);              // long strides high up, careful near the ground
    }
    vec3 haze = sky(rd);
    if (t > 9.0) return haze;
    vec3 pos = ro + rd * t;
    ter = terrain(pos.xz, t * pixA * 0.5);
    float h = ter.x;
    float moist = gMoist;
    float texv = gTex;
    vec3 n = normalize(vec3(-ter.y, 1.0, -ter.z));
    vec3 sun = normalize(vec3(-0.6, 0.33, 0.4));


    // shadows from the terrain itself, and from the clouds overhead
    float sh = 1.0;
    {
        float st = 0.01;
        for (int i = 0; i < 10; i++) {                   // the big landforms cast the shadows that read from the air
            vec3 sp = pos + sun * st;
            vec3 ts = terrain(sp.xz, 0.02 + (t + st) * pixA * 25.0);
            sh = min(sh, 12.0 * (sp.y - max(ts.x, 0.0)) / st);
            st += max(0.03, (sp.y - ts.x) * 0.7);
            if (sh < 0.01 || st > 1.5) break;
        }
        sh = clamp(sh, 0.0, 1.0);
    }
    float cshadow = 1.0;
    for (int m = 0; m < 3; m++) {
        float cy = cloudY(m);
        vec3 cp = pos + sun * ((cy - pos.y) / sun.y);
        float cyy;
        cshadow *= 1.0 - 0.7 * cloudSheet(cp.xz, m, cyy);
    }
    sh *= cshadow;

    // what's on the ground: materials as weights, so the film knob can recolour them
    float slope = 1.0 - n.y;
    float water = step(h, 0.0);
    float sand = (1.0 - water) * (1.0 - smoothstep(0.004, 0.014, h)) * (1.0 - smoothstep(0.3, 0.5, slope));
    float snow = (1.0 - water) * smoothstep(0.2, 0.26, h + moist * 0.03) * (1.0 - smoothstep(0.35, 0.6, slope));
    float rock = (1.0 - water) * (1.0 - snow) * smoothstep(0.32, 0.55, slope + moist * 0.1);
    float veg = max(0.0, 1.0 - water - sand - snow - rock);
    float forest = smoothstep(-0.05, 0.12, moist);
    vec3 vegC = mix(vec3(0.33, 0.36, 0.17), vec3(0.11, 0.2, 0.09), forest);
    vegC *= 0.8 + 0.5 * texv;                             // canopy texture
    vec3 albN = sand * vec3(0.74, 0.67, 0.5) + snow * vec3(0.93, 0.95, 0.98) + rock * vec3(0.42, 0.38, 0.33) + veg * vegC;
    vec3 albIR = sand * vec3(0.82, 0.76, 0.8) + snow * vec3(1.0) + rock * vec3(0.5, 0.56, 0.62) + veg * mix(vec3(0.85, 0.3, 0.3), vec3(0.75, 0.05, 0.12), forest);
    float dif = max(dot(n, sun), 0.0) * sh;
    float amb = 0.14 + 0.16 * n.y;
    vec3 light = vec3(1.0, 0.94, 0.82) * dif * 1.6 + vec3(0.42, 0.52, 0.7) * amb;
    vec3 col = albN * light;
    vec3 colIR = albIR * light;
    if (water > 0.5) {
        // the sea: deep to turquoise shallows, foam on the shore, sun glint on the waves
        float depth = -h;
        vec3 wn = normalize(vec3((noise(pos.xz * 220.0 + uTime * 0.4) - 0.5) * 0.25, 1.0, (noise(pos.zx * 230.0 - uTime * 0.35) - 0.5) * 0.25));
        float fres = 0.02 + 0.98 * pow(1.0 - max(dot(wn, -rd), 0.0), 5.0);
        vec3 wc = mix(vec3(0.08, 0.36, 0.38), vec3(0.01, 0.06, 0.11), smoothstep(0.0, 0.06, depth));
        wc *= 0.6 + 0.4 * cshadow;
        wc = mix(wc, sky(reflect(rd, wn)), fres * 0.6);
        wc += vec3(1.0, 0.95, 0.85) * pow(max(dot(reflect(rd, wn), sun), 0.0), 120.0) * 2.0 * cshadow;
        float foam = (1.0 - smoothstep(0.0, 0.004, depth)) * (0.6 + 0.4 * noise(pos.xz * 400.0));
        wc = mix(wc, vec3(0.9), foam * 0.8);
        col = wc;
        colIR = mix(vec3(0.01, 0.02, 0.05), vec3(0.9), foam * 0.8) + vec3(1.0) * pow(max(dot(reflect(rd, wn), sun), 0.0), 120.0) * cshadow;
    }
    // FILM (knob D): natural -> silver monochrome -> false-colour infrared
    float lum = dot(col, vec3(0.3, 0.59, 0.11));
    vec3 mono = vec3(pow(lum, 1.15) * 1.15) * vec3(0.98, 1.0, 1.03);
    vec3 film = uD < 0.5 ? mix(col, mono, uD * 2.0) : mix(mono, colIR, uD * 2.0 - 1.0);
    // aerial perspective
    film = mix(haze * mix(1.0, 0.85, step(0.5, uD)), film, exp(-t * 0.08));

    // SURVEY LINES (knob C): the shore, contours, and a grid that subdivides as we fall
    float px = t * pixA;
    float gl = length(ter.yz) + 1e-4;
    float shore = 1.0 - smoothstep(px * 0.6, px * 1.6, abs(h) / gl);
    float cl = 0.045;
    float cf = abs(fract(max(h, 0.0) / cl + 0.5) - 0.5) * cl / gl;
    float contour = (1.0 - smoothstep(px * 0.4, px * 1.2, cf)) * (1.0 - water);
    float wave = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(length(pos.xz - gC) * 6.0 - uPulse * 3.0), 6.0);
    vec2 gq = pos.xz - gC;
    float fs = fract(gS);
    float sp = 0.18 * exp2(fs);                          // grid lines spread as we zoom; new ones fade in between
    vec2 gi = floor(gq / sp + 0.5);
    vec2 gd = abs(gq - gi * sp);
    float odd = max(mod(gi.x, 2.0), 0.0);
    float lineX = (1.0 - smoothstep(px * 0.4, px * 1.1, gd.x)) * mix(1.0, fs, mod(gi.x, 2.0));
    float lineZ = (1.0 - smoothstep(px * 0.4, px * 1.1, gd.y)) * mix(1.0, fs, mod(gi.y, 2.0));
    float grid = max(lineX, lineZ) * exp(-t * 0.4);
    vec3 ink = vec3(1.0);
    film = mix(film, ink, shore * min(uC * 1.4, 1.0));
    film = mix(film, ink, contour * min(uC * 0.9, 0.8) * wave * (1.0 + uBeat));
    film = mix(film, ink * 0.9, grid * uC * 0.35);

    // the clouds we're falling through, over everything
    for (int m = 0; m < 3; m++) {
        float cy = cloudY(m);
        if (rd.y >= 0.0 || cy >= ALT) continue;
        float tc = (cy - ALT) / rd.y;
        if (tc > t) continue;
        float cyy;
        vec2 cxz = (ro + rd * tc).xz;
        float dens = cloudSheet(cxz, m, cyy);
        if (dens < 0.003) continue;
        float toward = cloudSheet(cxz + normalize(sun.xz) * 0.03, m, cyy);   // thicker toward the sun = shaded
        vec3 cc = mix(vec3(1.0, 0.98, 0.95), vec3(0.55, 0.6, 0.7), clamp((toward - dens) * 2.5 + 0.25, 0.0, 1.0));
        if (uD >= 0.5) cc = vec3(dot(cc, vec3(0.33)));
        film = mix(film, cc, dens);
    }
    // a survey crosshair on the dive point
    vec2 cp = abs(p);
    float cross = max(step(cp.y, 0.0015) * step(0.03, cp.x) * step(cp.x, 0.07), step(cp.x, 0.0015) * step(0.03, cp.y) * step(cp.y, 0.07));
    film = mix(film, ink, cross * uC * 0.6);
    return film;
}
