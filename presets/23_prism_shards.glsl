// @preset {"name": "Prism Shards", "labels": {"a": "shard size", "b": "refraction", "c": "seed light", "d": "color"}, "params": {"palette": 2, "glow": 0.2, "feedback": 0.0, "fb_hue": 0.0, "chroma": 0.35, "c": 0.6}}
// Crystal shards that each show a turned, zoomed reflection of the previous frame. The image recurses
// into itself forever; a mandala of light seeds it, and the camera can too (camera mix fader).

vec3 shardVoronoi(vec2 x, out vec2 cellCenter) {
    vec2 n = floor(x), f = fract(x);
    float md = 8.0, md2 = 8.0;
    vec2 mc = vec2(0.0), mid = vec2(0.0);
    for (int j = -1; j <= 1; j++)
    for (int i = -1; i <= 1; i++) {
        vec2 g = vec2(float(i), float(j));
        vec2 o = hash22(n + g);
        o = 0.5 + 0.4 * sin(uTime * 0.2 + TAU * o);
        vec2 r = g + o - f;
        float d = dot(r, r);
        if (d < md) { md2 = md; md = d; mc = n + g + o; mid = n + g; }
        else if (d < md2) md2 = d;
    }
    cellCenter = mc;
    return vec3(sqrt(md2) - sqrt(md), hash12(mid), hash12(mid + 7.0));
}

vec3 scene(vec2 p, vec2 uv) {
    float asp = uRes.x / uRes.y;
    float scale = 2.0 + uA * 5.0;
    vec2 kp = kaleido(rot(uTime * 0.04) * p, 6.0);
    vec2 cc;
    vec3 v = shardVoronoi(kp * scale, cc);
    // each shard re-projects the last frame around its own centre: rotated, zoomed, offset
    vec2 c = cc / scale;
    float ang = (v.y - 0.5) * (0.6 + uB * 2.0);
    float zoom = 1.15 + v.z * 0.6 * (0.5 + uB);
    vec2 rp = rot(ang) * (kp - c) * zoom + c * 0.6;
    vec2 ruv = vec2(rp.x / asp, rp.y) * 0.5 + 0.5;
    // the reflection loses light each bounce (and the tonemap compresses it), so it fades instead of whiting out
    vec3 refl = hueRotate(prev(ruv), 0.08) * (0.3 + 0.08 * v.z);

    // the seed: a small luminous mandala in the middle
    float r = length(p);
    vec2 m = kaleido(rot(-uTime * 0.1) * p, 12.0);
    float seed = abs(length(m - vec2(0.18, 0.0)) - 0.06) + max(0.0, r - 0.35);
    vec3 col = refl;
    col += glowpal(uTime * 0.03 + uD) * 0.004 / (seed + 0.004) * uC * 2.0 * (0.6 + uBeat);
    col += glowpal(uD + 0.5) * 0.006 / (r + 0.01) * uC;

    // shard edges glint
    float px = fwidth(kp.x) * scale * 1.5;
    col += glowpal(v.y + uD + 0.25) * px / (v.x + px) * 0.3 * (0.6 + uHigh);
    return col;
}
