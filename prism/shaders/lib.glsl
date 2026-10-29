// Shared helper functions. Prepended to every shader (scene, composite, display).

#define PI 3.14159265359
#define TAU 6.28318530718

mat2 rot(float a) {
    float c = cos(a), s = sin(a);
    return mat2(c, -s, s, c);
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
               mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    mat2 m = mat2(1.6, 1.2, -1.2, 1.6);
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p = m * p;
        a *= 0.5;
    }
    return v;
}

vec3 hsv2rgb(vec3 c) {
    vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
    return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

// Inigo Quilez cosine palette, for presets that want their own colours.
vec3 cospal(float t, vec3 a, vec3 b, vec3 c, vec3 d) {
    return a + b * cos(TAU * (c * t + d));
}

// Fold a point into one wedge of an n-way mirror kaleidoscope.
vec2 kaleido(vec2 p, float n) {
    float r = length(p);
    float a = atan(p.y, p.x);
    float s = TAU / n;
    a = mod(a, s);
    a = abs(a - s * 0.5);
    return vec2(cos(a), sin(a)) * r;
}

// Mirrored repeat so UVs outside 0..1 reflect instead of clamping.
vec2 mirrorUV(vec2 uv) {
    return 1.0 - abs(1.0 - mod(uv, 2.0));
}

// Hue rotation in YIQ space (angle in radians).
vec3 hueRotate(vec3 c, float a) {
    const mat3 toYIQ = mat3(0.299, 0.596, 0.211, 0.587, -0.274, -0.523, 0.114, -0.322, 0.312);
    const mat3 toRGB = mat3(1.0, 1.0, 1.0, 0.956, -0.272, -1.106, 0.621, -0.647, 1.703);
    vec3 yiq = toYIQ * c;
    float h = atan(yiq.z, yiq.y) + a;
    float ch = length(yiq.yz);
    return toRGB * vec3(yiq.x, ch * cos(h), ch * sin(h));
}

float luma(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

// ACES-style filmic curve: lets presets stack glow without clipping to flat white.
vec3 tonemap(vec3 c) {
    c = max(c, 0.0);
    return clamp(c * (2.51 * c + 0.03) / (c * (2.43 * c + 0.59) + 0.14), 0.0, 1.0);
}

// Linear up to 0.8, then rolls off smoothly towards 1.0 instead of hard clipping.
vec3 softclip(vec3 c) {
    vec3 k = 0.8 + 0.2 * (1.0 - exp(-(c - 0.8) / 0.2));
    return mix(c, k, step(0.8, c));
}

// Map a screen uv (0..1) to equirectangular uv for a 360 camera (Insta360 etc).
// mode 0 = flat panorama, 1 = look-around camera, 2 = tiny planet, 3 = rabbit hole.
vec2 project360(vec2 uv, float aspect, float mode, float yaw) {
    if (mode < 0.5) return vec2(fract(uv.x + yaw / TAU), uv.y);
    vec2 p = uv * 2.0 - 1.0;
    p.x *= aspect;
    float lon, lat;
    if (mode < 1.5) {
        vec3 d = normalize(vec3(p * 0.9, 1.0));               // ~100 degree field of view
        float pitch = 0.15 * sin(yaw);                           // gentle bob
        d.yz = rot(pitch) * d.yz;
        lon = atan(d.x, d.z) + yaw;
        lat = asin(clamp(d.y, -1.0, 1.0));
    } else {
        float r = length(p);
        lon = atan(p.y, p.x) + yaw;
        float c = 2.0 * atan(r * 0.85);                          // stereographic
        lat = mode < 2.5 ? c - PI * 0.5 : PI * 0.5 - c;          // planet: ground in the middle
    }
    return vec2(fract(lon / TAU + 0.5), clamp(lat / PI + 0.5, 0.001, 0.999));
}
