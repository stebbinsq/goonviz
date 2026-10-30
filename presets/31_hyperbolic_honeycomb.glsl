// @preset {"heavy": true, "name": "Hyperbolic Honeycomb", "labels": {"a": "edge thickness", "b": "look around", "c": "stained glass", "d": "color"}, "params": {"palette": 0, "glow": 0.45, "feedback": 0.2, "chroma": 0.2, "c": 0.5}}
// The {4,3,5} honeycomb: hyperbolic space tiled by cubes with FIVE around every edge (impossible in
// ordinary space). Drawn in the Poincare ball, the cubes shrink forever toward a glowing horizon in every
// direction. The camera flies cell to cell; one cell along, the view is identical, so the flight never ends.
// Heavy: best on a Mac.

// Face of the central cube: a sphere orthogonal to the unit ball. Five cubes per edge means a 72 degree
// dihedral angle, which gives cos(108 deg) = -1/R^2 and D^2 = 1 + R^2.
const float R = 1.79890;
const float D = 2.05817;

float hFace;    // distance to the nearest cube wall (in folded space)
float hKey;     // where on its wall this point sits, in the cube's own frame: same in every cell
float hVert;    // 1 if the nearest feature is a corner hub, 0 if a beam

// Fold a point into the fundamental piece of the central cube, crossing walls by sphere inversion.
// Returns the distance to the nearest edge or vertex, converted back to unfolded units.
float honeycomb(vec3 p) {
    float scl = 1.0;
    for (int i = 0; i < 14; i++) {                    // rays stop ~8 cells deep, so 14 crossings is plenty
        p = abs(p);
        if (p.x < p.y) p.xy = p.yx;                     // sort x >= y >= z: the cube's own symmetry
        if (p.y < p.z) p.yz = p.zy;
        if (p.x < p.y) p.xy = p.yx;
        vec3 q = p - vec3(D, 0.0, 0.0);
        float q2 = dot(q, q);
        if (q2 >= R * R) break;                         // inside the central cube: done
        float k = R * R / q2;                           // cross the wall (invert in the face sphere)
        p = vec3(D, 0.0, 0.0) + q * k;
        scl *= k;
    }
    float sx = length(p - vec3(D, 0.0, 0.0)) - R;       // distances to the three nearest walls
    float sy = length(p - vec3(0.0, D, 0.0)) - R;
    float sz = length(p - vec3(0.0, 0.0, D)) - R;
    float th = 0.0025 + uA * 0.009 + uBass * 0.003;
    float edge = length(vec2(sx, sy)) - th;
    float vert = length(vec3(sx, sy, sz)) - th * 2.4;
    hFace = sx / scl;
    hKey = p.y * 1.7 + p.z * 2.9;
    hVert = step(vert, edge);
    return min(edge, vert) / scl;
}

// Moebius addition a (+) p: the hyperbolic "translation" that carries the ball's centre to a.
vec3 mobius(vec3 a, vec3 p) {
    float ap = dot(a, p), aa = dot(a, a), pp = dot(p, p);
    return ((1.0 + 2.0 * ap + pp) * a + (1.0 - aa) * p) / (1.0 + 2.0 * ap + aa * pp);
}

// Distance in view space: move the view point into the world, measure there, and divide by how much the
// translation stretches lengths at that point (its conformal factor).
float viewDE(vec3 pv, vec3 a) {
    float aa = dot(a, a);
    float lam = (1.0 - aa) / (1.0 + 2.0 * dot(a, pv) + aa * dot(pv, pv));
    return honeycomb(mobius(a, pv)) / lam;
}

vec3 scene(vec2 p, vec2 uv) {
    // fly along +x from cell centre to cell centre; one cell along, the view repeats exactly
    float cell = 2.0 * atanh(1.0 / D);                  // hyperbolic distance between neighbouring centres
    float h = mod(uPulse * 0.35, cell);
    vec3 a = vec3(tanh(h * 0.5), 0.0, 0.0);

    // look forward along +x, gently looking around (B), with a crisp roll on each beat
    float roll = uTime * 0.05 + (uBeatCount - uBeat * uBeat) * PI * 0.125;
    vec3 rd = normalize(vec3(1.5, rot(roll) * p));
    float look = 0.25 + uB * 0.9;
    rd.xz = rot(look * sin(uTime * 0.07)) * rd.xz;
    rd.xy = rot(look * 0.7 * sin(uTime * 0.05 + 1.3)) * rd.xy;

    float t = 0.0, d = 1.0;
    vec3 glass = vec3(0.0);
    float halo = 0.0;
    float lastT = 0.0;
    for (int i = 0; i < 100; i++) {
        vec3 pv = rd * t;
        if (dot(pv, pv) > 0.997) break;                 // reached the horizon of the ball
        d = viewDE(pv, a);
        // stained glass: tint the ray each time it passes close to a cube wall
        float aa = dot(a, a);
        float lam = (1.0 - aa) / (1.0 + 2.0 * dot(a, pv) + aa * dot(pv, pv));
        float wall = abs(hFace / lam);
        float stepLen = t - lastT;
        lastT = t;
        // colour and fade by true (hyperbolic) distance from the camera, not by cell count: the count jumps
        // by one whenever the camera enters a new cell, which would make every colour pop at once
        float hd = 2.0 * atanh(min(length(pv), 0.999));
        if (hd > 7.5) break;                            // deeper than this is fogged to nothing: stop early (big saving)
        glass += glowpal(hKey + hd * 0.08 + uD + 0.45) * exp(-wall * 400.0) * stepLen * 4.0 * exp(-hd * 0.3);
        halo += 0.00012 / (d + 0.002) * exp(-hd * 0.28);
        if (d < 0.00025 * (1.0 + t)) break;
        t += d * 0.75;
    }

    vec3 pv = rd * t;
    float depth = 2.0 * atanh(min(length(pv), 0.999));   // hyperbolic distance from the camera
    vec3 col = vec3(0.0);
    // the horizon where the cells become infinitely small
    float horizon = smoothstep(0.9, 0.999, length(pv));
    col += glowpal(uD + 0.3 + uTime * 0.01) * horizon * 0.08;
    if (d < 0.002) {
        vec2 e = vec2(0.0004, 0.0);
        vec3 n = normalize(vec3(viewDE(pv + e.xyy, a) - viewDE(pv - e.xyy, a),
                                viewDE(pv + e.yxy, a) - viewDE(pv - e.yxy, a),
                                viewDE(pv + e.yyx, a) - viewDE(pv - e.yyx, a)));
        float fres = pow(1.0 - max(dot(n, -rd), 0.0), 2.0);
        vec3 c = glowpal(depth * 0.16 + hKey * 0.3 + uD);
        // the nearest beams are huge on screen; keep them from overpowering the depths behind them
        float fade = exp(-depth * 0.32) * mix(0.55, 1.0, smoothstep(0.15, 0.5, t));
        col = c * (0.35 + 0.65 * max(dot(n, normalize(vec3(0.4, 0.8, 0.3))), 0.0)) * fade * (1.0 + uBeat * 0.8);
        col += glowpal(depth * 0.16 + uD + 0.6) * fres * fade * 0.8;
        col += glowpal(uD + 0.75) * hVert * fade * (0.4 + uHigh * 1.6);   // corner hubs sparkle with the highs
    }
    col += glass * uC;
    col += glowpal(uD + 0.15) * halo * 0.35 * (0.6 + uMid);
    return col;
}
