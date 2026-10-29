// @preset {"name": "Spiral Vortex", "labels": {"a": "arms", "b": "tightness", "c": "lattice", "d": "color"}, "params": {"palette": 7, "glow": 0.5, "feedback": 0.55, "fb_rotate": -0.3, "fb_zoom": 0.3}}
// Log-polar spirals: an endless inward zoom along logarithmic arms with a lattice of jewels.

vec3 scene(vec2 p, vec2 uv) {
    float r = length(p);
    float lr = log(r);
    float a = atan(p.y, p.x);
    float arms = floor(2.0 + uA * 7.0);
    float k = 1.0 + uB * 4.0;
    float t = uPulse * 0.4;

    // spiral coordinate: constant along each log-spiral arm
    float s = a * arms / TAU + lr * k - t;
    float fs = fwidth(p.x) * (arms / TAU + k) / max(r, 1e-3);
    float arm = abs(fract(s) - 0.5);
    float armLine = fs / (arm + fs) + 0.3 * exp(-arm * 10.0);

    // counter-spiral lattice of light beads
    float s2 = a * arms / TAU - lr * k * 0.7 - t * 0.5;
    vec2 cell = vec2(fract(s) - 0.5, fract(s2 * 2.0) - 0.5);
    float bead = 0.01 / (dot(cell, cell) * 4.0 + 0.01) * uC * 2.0;
    float s3 = abs(fract(s2 * 2.0) - 0.5);
    float cross = fs / (s3 + fs) * 0.35;   // faint counter-spiral threads

    vec3 col = glowpal(floor(s) * 0.21 + lr * 0.1 + uD) * armLine * 0.8;
    col += glowpal(floor(s2 * 2.0) * 0.13 + uD + 0.5) * (bead * 0.6 * (0.6 + uHigh) + cross);
    col *= smoothstep(0.0, 0.25, r) * (0.8 + uBass * 0.5);
    col += glowpal(uD) * 0.01 / (r + 0.015) * (0.6 + uBeat);
    return col;
}
