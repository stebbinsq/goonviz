// Display pass: colour grading and master controls, drawn straight to the
// projector at full resolution. Kept out of the feedback loop on purpose.

uniform sampler2D uComp;
uniform float uHue, uSat, uBright, uContrast;
uniform float uInvert, uStrobe, uBeat, uFlash, uBlackout, uTime;

in vec2 vUV;
out vec4 fragColor;

void main() {
    vec3 c = texture(uComp, vUV).rgb;

    if (uHue > 0.001) c = hueRotate(c, uHue * TAU);
    c = mix(vec3(luma(c)), c, uSat);
    c = (c - 0.5) * uContrast + 0.5;
    c *= uBright;
    c = mix(c, 1.0 - c, uInvert);

    float flash = max(uFlash, uStrobe * uBeat * uBeat);
    c = mix(c, vec3(1.0), clamp(flash, 0.0, 1.0));

    c *= 1.0 - uBlackout;
    // Tiny dither: hides 8-bit banding in dark gradients, which projectors exaggerate.
    c += (hash12(gl_FragCoord.xy + fract(uTime) * 100.0) - 0.5) / 255.0;
    fragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
