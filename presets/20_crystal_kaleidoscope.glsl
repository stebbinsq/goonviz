// @preset {"name": "Crystal Kaleidoscope", "labels": {"a": "cell size", "b": "turbulence", "c": "camera (0 = none)", "d": "color"}, "params": {"palette": 2, "glow": 0.5, "feedback": 0.3, "chroma": 0.25, "c": 0.0}}
// A real mirror kaleidoscope: a hex lattice of 12-way mirrored cells (wallpaper group p6m), seamless
// across every edge. The "glass" holds flowing ink and jewels, and knob C pours in the camera.

vec2 hexLocal(vec2 q, out vec2 id) {
    const vec2 s = vec2(1.0, 1.7320508);
    vec4 hc = floor(vec4(q, q - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
    vec4 h = vec4(q - hc.xy * s, q - (hc.zw + 0.5) * s);
    bool first = dot(h.xy, h.xy) < dot(h.zw, h.zw);
    id = first ? hc.xy : hc.zw + 0.5;
    return first ? h.xy : h.zw;
}

vec3 scene(vec2 p, vec2 uv) {
    float scale = 0.45 + uA * 1.2;
    vec2 id;
    vec2 local = hexLocal(rot(uTime * 0.02) * p * scale, id);
    vec2 k = kaleido(local, 6.0);                           // 6 wedges, each mirrored = 12-fold
    vec2 src = rot(uTime * 0.07) * k * 0.9 + vec2(uTime * 0.05, -uTime * 0.03);

    // generative glass: warped ink with luminous filaments and jewels
    vec2 w = vec2(fbm(src * 1.3 + uTime * 0.1), fbm(src * 1.3 + vec2(4.1, 2.7) - uTime * 0.08));
    float f = fbm(src * 1.4 + w * (1.5 + uB * 3.0));
    float v = f * 5.0 - uTime * 0.3;
    float iso = abs(fract(v) - 0.5) / max(fwidth(v), 1e-4);
    vec3 glass = uPal[1] * 0.25 * f + pal(f * 0.8 + uD) * pow(f, 5.0) * 0.5;
    glass += glowpal(f + uD + 0.3) / (1.0 + iso * iso * 1.2) * 0.6 * smoothstep(0.3, 0.6, f) * (0.6 + uMid);
    float jewel = length(k - vec2(0.33, 0.06));
    glass += glowpal(f + uD + 0.6) * pow(smoothstep(0.7, 0.95, f), 3.0) * 0.6 * (1.0 + uBeat);
    glass += glowpal(uD + 0.15 + float(int(mod(id.x + id.y, 3.0))) * 0.2) * 0.0012 / (jewel * jewel + 0.0015) * (0.5 + uBass);

    // camera through the mirrors
    vec3 cam = video(fract(src * 0.18 + 0.5)) * (0.8 + uBass * 0.4);
    vec3 col = mix(glass, cam + glass * 0.35, uC);

    // the mirror seams themselves catch the light
    float seam = min(abs(k.y), abs(k.y - k.x * 0.57735) );
    float px = fwidth(p.x) * scale * 1.5;
    col += glowpal(uD + 0.8) * px / (seam + px) * 0.25;
    return col;
}
