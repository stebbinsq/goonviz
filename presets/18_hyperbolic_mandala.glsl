// @preset {"name": "Hyperbolic Mandala", "labels": {"a": "polygon sides", "b": "meeting at each corner", "c": "flow", "d": "color"}, "params": {"palette": 2, "glow": 0.55, "feedback": 0.35, "chroma": 0.2, "a": 0.3, "b": 0.0}}
// A {p,q} tiling of the hyperbolic plane (Poincare disk, Escher's Circle Limit): polygons shrink
// forever toward the rim. A Mobius transform keeps it flowing; outside the disk it's mirrored.

vec2 cmul(vec2 a, vec2 b) { return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x); }
vec2 cdiv(vec2 a, vec2 b) { return vec2(a.x * b.x + a.y * b.y, a.y * b.x - a.x * b.y) / dot(b, b); }

vec3 scene(vec2 p, vec2 uv) {
    float q = 3.0 + floor(uB * 2.99);
    float pmin = q < 3.5 ? 7.0 : 5.0;                       // keep 1/p + 1/q < 1/2 (hyperbolic)
    float pp = max(floor(5.0 + uA * 5.99), pmin);
    float cq = cos(PI / q), sp = sin(PI / pp);
    float k = 1.0 / sqrt(cq * cq - sp * sp);
    vec2 C = vec2(cq * k, 0.0);                             // edge circle, orthogonal to the unit disk
    float R = sp * k;

    vec2 z = p * 0.92;
    float rim = length(z);
    if (rim > 1.0) z /= dot(z, z);                          // mirror the outside back into the disk

    // flow: Mobius translation along a slowly turning direction
    vec2 t = 0.35 * uC * vec2(cos(uTime * 0.13), sin(uTime * 0.17)) * (0.6 + 0.4 * sin(uTime * 0.07));
    z = cdiv(z + t, vec2(1.0, 0.0) + cmul(vec2(t.x, -t.y), z));
    z = rot(uTime * 0.05) * z;

    float depth = 0.0;
    float wedge = PI / pp;
    for (int i = 0; i < 14; i++) {
        float a = atan(z.y, z.x);
        a = mod(a + wedge, 2.0 * wedge) - wedge;            // fold into the wedge around angle 0
        z = length(z) * vec2(cos(a), abs(sin(a)));
        vec2 w = z - C;
        float w2 = dot(w, w);
        if (w2 >= R * R) break;
        z = C + w * (R * R / w2);                           // invert across the polygon edge
        depth += 1.0;
    }

    float edge = abs(length(z - C) - R);                    // distance to the polygon's edge
    float spoke = abs(z.y);                                  // mirror line through polygon centre
    float shrink = 1.0 - dot(z, z);                          // hyperbolic metric: features shrink near rim
    float px = fwidth(p.x) * 1.5;
    vec3 col = vec3(0.0);
    vec3 c1 = glowpal(depth * 0.12 + uD + uTime * 0.02);
    vec3 c2 = glowpal(depth * 0.12 + uD + 0.45);
    col += c1 * px / (edge + px) * 1.1;
    col += c1 * 0.002 / (edge + 0.012) * 0.4;
    col += c2 * px / (spoke + px) * 0.35;
    // a jewel at every polygon centre and a ring of light inside each tile
    col += c2 * 0.0006 / (dot(z, z) + 0.0015) * (0.5 + uBass);
    col += glowpal(depth * 0.12 + uD + 0.7) * 0.0015 / (abs(length(z) - 0.35 * (1.0 - C.x + R)) + 0.006) * 0.5;
    col += pal(depth * 0.1 + uD + 0.2) * 0.04 * shrink;
    col += glowpal(uD + 0.3) * 0.003 / (abs(rim - 1.0) + 0.004) * 0.5;   // the rim
    return col * (0.85 + uBeat * 0.35);
}
