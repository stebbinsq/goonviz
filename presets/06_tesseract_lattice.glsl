// @preset {"heavy": true, "name": "Tesseract Lattice", "labels": {"a": "beam thickness", "b": "4D spin", "c": "beat snap", "d": "color"}, "params": {"palette": 4, "glow": 0.6, "feedback": 0.3, "chroma": 0.25, "c": 0.5}}
// An endless grid of four-dimensional hypercubes (tesseracts), rotating through the 4th dimension and
// sliced into 3D. Beams slide through each other, split and rejoin in ways that only make sense in 4D.
// The 4D rotation snaps forward on the beat. Heavy: best on a Mac.

float beamId;

vec4 rotate4(vec4 q) {
    float s = uTime * (0.1 + uB * 0.4) + (uBeatCount - uBeat * uBeat) * uC * 0.35;
    q.xw = rot(s) * q.xw;
    q.yw = rot(s * 0.71 + 0.5) * q.yw;
    q.zw = rot(s * 0.53 + 1.1) * q.zw;
    return q;
}

float tess(vec3 p) {
    vec4 q = rotate4(vec4(p, 0.0));
    q = mod(q + 1.0, 2.0) - 1.0;                         // a 4D grid of cells, corners at +-1
    vec4 a = abs(q) - 1.0;                               // distance to each pair of cell faces
    // an edge runs along one axis where the other three coordinates sit on cell faces
    float ex = length(a.yzw), ey = length(a.xzw), ez = length(a.xyw), ew = length(a.xyz);
    float d = min(min(ex, ey), min(ez, ew));
    beamId = d == ex ? 0.0 : d == ey ? 1.0 : d == ez ? 2.0 : 3.0;
    float node = length(a) - (0.14 + uA * 0.12);          // a hub at every 4D corner
    return min(d - (0.05 + uA * 0.09), node);
}

vec3 scene(vec2 p, vec2 uv) {
    vec3 ro = vec3(0.3, 0.2, uPulse * 0.4);
    vec3 rd = normalize(vec3(p, 1.5 - uBass * 0.2));
    rd.xz = rot(0.4 + uTime * 0.03) * rd.xz;
    rd.yz = rot(0.3 * sin(uTime * 0.05)) * rd.yz;

    float t = 0.0, d = 1.0, glow = 0.0, gId = 0.0;
    for (int i = 0; i < 90; i++) {
        d = tess(ro + rd * t);
        float g = 0.012 / (1.0 + d * d * 900.0);
        glow += g;
        gId += beamId * g;
        if (d < 0.0008 * t || t > 16.0) break;
        t += d * 0.8;
    }
    vec3 fogc = uPal[0];
    vec3 col = fogc;
    if (d < 0.01) {
        vec3 pos = ro + rd * t;
        float id = beamId;
        vec2 e = vec2(0.001, -0.001);
        vec3 n = normalize(e.xyy * tess(pos + e.xyy) + e.yyx * tess(pos + e.yyx) +
                           e.yxy * tess(pos + e.yxy) + e.xxx * tess(pos + e.xxx));
        float fres = pow(1.0 - max(dot(n, -rd), 0.0), 2.0);
        vec3 c = glowpal(id * 0.25 + uD);                 // each 4D axis has its own colour
        col = c * (0.35 + 0.9 * max(dot(n, normalize(vec3(0.5, 0.8, -0.3))), 0.0)) + c * fres * 1.4;
        col = mix(col, fogc, 1.0 - exp(-t * 0.1));
    }
    col += glowpal(gId / max(glow, 1e-4) * 0.25 + uD) * glow * 0.8 * (0.5 + uMid);
    return col * (0.95 + uBeat * 0.3);
}
