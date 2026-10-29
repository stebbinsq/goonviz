// Composite pass: warp + kaleidoscope + chroma on the scene, then the
// Milkdrop-style feedback loop and video blend. The output of this pass is
// fed back into itself next frame, so no colour grading happens here.

uniform sampler2D uScene;
uniform sampler2D uPrev;
uniform sampler2D uVideo;
uniform vec2 uRes;
uniform float uTime;
uniform float uFeedback, uFbZoom, uFbRot, uFbHue;
uniform float uKaleido, uWarp, uChroma, uGlow;
uniform float uExposure;  // auto-exposure: < 1 when the scene is too bright (set by the engine)
uniform float uTransition; // 1 right after a preset change, fading to 0: the old frame melts into the new
uniform float uVideoMix, uVideoOn, uVideo360, uCamView, uCamYaw;
uniform float uBeat, uBass;

in vec2 vUV;
out vec4 fragColor;

void main() {
    float asp = uRes.x / uRes.y;
    vec2 uv = vUV;

    if (uWarp > 0.001) {
        vec2 q = uv * vec2(asp, 1.0) * 2.5;
        vec2 w = vec2(fbm(q + uTime * 0.3), fbm(q + vec2(5.2, 1.3) - uTime * 0.25)) - 0.5;
        uv += w * uWarp * 0.25;
    }

    if (uKaleido >= 1.5) {
        vec2 p = (uv - 0.5) * vec2(asp, 1.0);
        p = kaleido(rot(uTime * 0.05) * p, floor(uKaleido));
        uv = p / vec2(asp, 1.0) + 0.5;
    }
    uv = mirrorUV(uv);

    vec2 dir = (uv - 0.5) * uChroma * 0.04 * (1.0 + uBass);
    vec3 sc = vec3(texture(uScene, mirrorUV(uv + dir)).r,
                   texture(uScene, uv).g,
                   texture(uScene, mirrorUV(uv - dir)).b);

    // Bloom from the scene's mip chain: a wide luminous haze for almost no cost.
    if (uGlow > 0.001) {
        vec3 bloom = textureLod(uScene, uv, 3.0).rgb * 0.5
                   + textureLod(uScene, uv, 5.0).rgb * 0.35
                   + textureLod(uScene, uv, 6.5).rgb * 0.25;
        sc += bloom * bloom * uGlow * (1.6 + uBass);
        sc = softclip(sc);
    }

    sc *= uExposure;

    // Feedback: sample last frame slightly zoomed/rotated, hue-drift it, decay it.
    vec2 f = (vUV - 0.5) * vec2(asp, 1.0);
    f = rot(uFbRot * 0.05) * f;
    f *= 1.0 - (uFbZoom * 0.035 + uBeat * uFbZoom * 0.02);
    f = f / vec2(asp, 1.0) + 0.5;
    vec3 fb = texture(uPrev, mirrorUV(f)).rgb;
    if (uFbHue > 0.001) fb = clamp(hueRotate(fb, uFbHue * 0.25), 0.0, 1.0);
    fb = max(fb * uFeedback - 0.004, 0.0);  // the -0.004 stops 8-bit trails getting stuck

    vec3 c = max(sc, fb);

    // Preset transition: keep the previous frame, drifting slightly in and around, and let the new
    // scene take over as uTransition falls to 0. Cheaper than rendering two presets at once.
    if (uTransition > 0.001) {
        float t = uTransition * uTransition * (3.0 - 2.0 * uTransition);
        vec2 m = (vUV - 0.5) * vec2(asp, 1.0);
        m = rot(0.01 * t) * m * (1.0 - 0.012 * t);
        vec3 held = texture(uPrev, mirrorUV(m / vec2(asp, 1.0) + 0.5)).rgb;
        c = mix(c, held, t * 0.96);
    }

    if (uVideoMix > 0.001 && uVideoOn > 0.5) {
        vec2 vuv = uVideo360 > 0.5 ? project360(vUV, asp, uCamView, uCamYaw) : vUV;
        vec3 v = texture(uVideo, vec2(vuv.x, 1.0 - vuv.y)).VIDEO_SWIZZLE;
        c = mix(c, 1.0 - (1.0 - c) * (1.0 - v), uVideoMix);  // screen blend
    }

    fragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
