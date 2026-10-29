// @preset {"name": "Video Melt (video)", "labels": {"a": "melt", "b": "flow speed", "c": "contours", "d": "color"}, "params": {"palette": 0, "glow": 0.4, "feedback": 0.5, "fb_zoom": 0.1, "warp": 0.15}}
// Video poured through a domain-warped flow field, then gradient-mapped to the palette.

vec3 scene(vec2 p, vec2 uv) {
    float t = uTime * (0.1 + uB * 0.4);
    vec2 w = vec2(fbm(p * 1.5 + t), fbm(p * 1.5 + vec2(3.1, 7.7) - t)) - 0.5;
    w += (vec2(fbm(p * 4.0 - t * 2.0), fbm(p * 4.0 + 9.0 + t * 2.0)) - 0.5) * 0.3;
    vec2 q = uv + w * (0.05 + uA * 0.3) * (1.0 + uBass * 0.5);
    vec3 v = video(q);
    float lum = luma(v);
    vec3 col = pal(lum * 0.9 + uD + t * 0.2) * (0.1 + lum * lum * 1.2);  // smooth gradient map
    float levels = 4.0 + uC * 12.0;
    float iso = abs(fract(lum * levels - t) - 0.5) / max(fwidth(lum * levels), 1e-3);
    col += glowpal(lum + uD + 0.4) / (1.0 + iso * iso * 0.15) * 0.5;   // luminous contour lines
    col = mix(col, v * 0.8, 0.12);
    return col;
}
