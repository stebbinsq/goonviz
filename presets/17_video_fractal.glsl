// @preset {"name": "Video Fractal (video)", "labels": {"a": "folds", "b": "spread", "c": "tint", "d": "color"}, "params": {"palette": 0, "glow": 0.5, "feedback": 0.4, "chroma": 0.3}}
// The video fed into a kaleidoscopic fold fractal: infinite mirrored copies of the room.

vec3 scene(vec2 p, vec2 uv) {
    vec2 q = rot(uTime * 0.05) * p;
    float iters = 2.0 + floor(uA * 4.0);
    vec3 col = vec3(0.0);
    float wsum = 0.0;
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        if (fi >= iters) break;
        q = abs(q) - (0.3 + uB * 0.4);
        q = rot(0.5 + 0.2 * sin(uTime * 0.2 + fi)) * q;
        q *= 1.25;
        vec3 v = video(q * 0.35 + 0.5);
        float wgt = 1.0 / (1.0 + fi);
        col += v * wgt;
        wsum += wgt;
    }
    col /= wsum;
    float lum = luma(col);
    vec3 tint = pal(lum * 1.2 + uD + uTime * 0.03) * (0.3 + lum * 1.2);
    col = mix(col, tint, uC);
    col += glowpal(uD + 0.5) * 0.002 / (abs(q.y) * 0.1 + 0.003) * 0.15;
    return col;
}
