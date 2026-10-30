// @preset {"energy": 1, "family": "organic", "name": "Nautilus", "labels": {"a": "spiral growth", "b": "chambers", "c": "nacre sheen", "d": "color"}, "params": {"palette": 8, "glow": 0.5, "feedback": 0.25, "fb_rotate": 0.12}}
// A chambered shell growing on a logarithmic spiral: glowing septa between chambers, a mother-of-pearl
// sheen that shifts like thin film, and the whole shell slowly turning.

vec3 scene(vec2 p, vec2 uv) {
    float growth = 0.12 + uA * 0.18;                        // b in r = e^(b*theta)
    vec2 q = rot(uTime * 0.08) * (p + vec2(0.12, 0.0));
    float r = length(q);
    float a = atan(q.y, q.x);
    // which whorl are we on? unwrap the angle so r ~ e^(growth*theta)
    float lr = log(max(r, 1e-4));
    float turn = (lr / growth - a) / TAU;                   // whorl coordinate: integer = shell wall
    float whorl = floor(turn);
    float wall = abs(fract(turn) - 0.5) * 2.0;              // 1 at walls, 0 mid-whorl
    float theta = a + (whorl + 0.5) * TAU;                  // continuous angle along the spiral
    float chambers = 6.0 + floor(uB * 10.0);
    // septa curve back toward the centre like a real shell's chamber walls
    float bend = 0.35 * sin(fract(turn) * PI) + 0.15 * fract(turn);
    float septum = abs(fract(theta / TAU * chambers + bend - uTime * 0.05) - 0.5);

    float px = fwidth(p.x) / max(r, 1e-3) / growth / TAU * 1.5;
    float pxs = fwidth(p.x) / max(r, 1e-3) / TAU * chambers * 1.5;
    vec3 col = vec3(0.0);
    float shell = smoothstep(0.98, 0.9, wall);               // inside a whorl
    // nacre: thin-film colour that changes with the angle and a wavy grain
    float grain = fbm(vec2(theta * 1.5, fract(turn) * 4.0) + uTime * 0.05);
    float film = fract(turn) * 0.7 + theta * 0.05 + grain * 0.5 + uTime * 0.03;
    col += glowpal(film + uD) * shell * (0.05 + 0.25 * uC) * (0.5 + grain);
    col += uPal[1] * shell * 0.08 * (1.0 - fract(turn));
    // shell walls and the septa between chambers
    col += glowpal(0.6 + uD) * px / (1.0 - wall + px) * 0.9;
    col += glowpal(0.62 + uD + whorl * 0.05) * pxs / (septum + pxs) * shell * 0.7;
    // siphuncle: a bright thread running through every chamber
    float siph = abs(fract(turn) - 0.35);
    col += glowpal(0.85 + uD) * px / (siph + px) * 0.4 * shell * (0.6 + uBass);
    // fade the impossible tiny inner whorls and the far outside
    col *= smoothstep(0.0, 0.05, r) * smoothstep(2.2, 1.2, r);
    col += glowpal(uD + 0.3) * 0.004 / (r + 0.01) * (0.4 + uBeat);
    return col;
}
