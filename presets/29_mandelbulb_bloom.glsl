// @preset {"name": "Mandelbulb Bloom", "labels": {"a": "power", "b": "orbit distance", "c": "detail (heavy)", "d": "color"}, "params": {"palette": 2, "glow": 0.6, "feedback": 0.25, "chroma": 0.25, "c": 0.5}}
// The 3D Mandelbrot set, slowly morphing its power, orbited by the camera and lit like a render:
// colour from orbit traps, ambient occlusion from the fractal's own iteration depth, rim light and a halo.
// Heavy: best on a Mac.

vec4 bulbTrap;

float bulb(vec3 p) {
    float power = 6.0 + uA * 4.0 + 0.8 * sin(uTime * 0.07) + uBass * 0.3;
    vec3 z = p;
    float dr = 1.0, r = 0.0;
    vec4 trap = vec4(abs(z), dot(z, z));
    int iters = 5 + int(uC * 4.0);
    for (int i = 0; i < 9; i++) {
        if (i >= iters) break;
        r = length(z);
        if (r > 2.0) break;
        float theta = acos(clamp(z.z / max(r, 1e-6), -1.0, 1.0)) * power + uTime * 0.05;
        float phi = atan(z.y, z.x) * power;
        dr = pow(r, power - 1.0) * power * dr + 1.0;
        float zr = pow(r, power);
        z = zr * vec3(sin(theta) * cos(phi), sin(phi) * sin(theta), cos(theta)) + p;
        trap = min(trap, vec4(abs(z), dot(z, z)));
    }
    bulbTrap = trap;
    return 0.5 * log(max(r, 1e-6)) * r / dr;
}

vec3 scene(vec2 p, vec2 uv) {
    float dist = 1.65 + uB * 0.9 - uBass * 0.1;
    float a = uTime * 0.08;
    vec3 ro = vec3(sin(a) * dist, 0.35 * sin(uTime * 0.05) * dist, cos(a) * dist);
    vec3 fw = normalize(-ro);
    vec3 rt = normalize(cross(vec3(0.0, 1.0, 0.0), fw));
    vec3 up = cross(fw, rt);
    vec3 rd = normalize(p.x * rt + p.y * up + 1.7 * fw);

    float t = 0.0, d = 1.0, glow = 0.0;
    // skip empty space to the bounding sphere
    float b = dot(ro, rd), c = dot(ro, ro) - 1.44, h = b * b - c;
    vec3 col = uPal[0];
    if (h > 0.0) {
        t = max(0.0, -b - sqrt(h));
        for (int i = 0; i < 80; i++) {
            d = bulb(ro + rd * t);
            glow += 0.02 / (1.0 + d * d * 900.0);
            if (d < 0.0008 * t || t > dist + 2.0) break;
            t += d;
        }
        if (d < 0.01) {
            vec3 pos = ro + rd * t;
            vec4 tr = bulbTrap;
            vec2 e = vec2(0.0008, -0.0008);
            vec3 n = normalize(e.xyy * bulb(pos + e.xyy) + e.yyx * bulb(pos + e.yyx) +
                               e.yxy * bulb(pos + e.yxy) + e.xxx * bulb(pos + e.xxx));
            float occ = clamp(tr.w * 2.2 - 0.1, 0.0, 1.0);          // deep folds = darker
            vec3 lig = normalize(vec3(0.5, 0.8, 0.3));
            float dif = max(dot(n, lig), 0.0);
            float fres = pow(1.0 - max(dot(n, -rd), 0.0), 2.5);
            vec3 hal = normalize(lig - rd);
            float spe = pow(max(dot(n, hal), 0.0), 32.0);
            vec3 albedo = mix(glowpal(tr.x * 1.5 + uD), glowpal(tr.y * 1.2 + uD + 0.4), clamp(tr.z * 1.5, 0.0, 1.0));
            col = albedo * (0.04 + dif * 1.1) * occ * occ;
            col += glowpal(fres * 0.8 + uD + 0.6) * fres * 0.8 * occ;
            col += vec3(1.0) * spe * 0.35 * occ;
            col += glowpal(tr.w + uD + 0.2) * (1.0 - occ) * 0.25 * (0.5 + uBass);   // emissive deep folds
        }
    }
    col += glowpal(uD + 0.5) * glow * 0.6 * (0.5 + uMid);
    col += uPal[1] * 0.15 * exp(-length(p) * 1.5);
    return col * (0.95 + uBeat * 0.3);
}
