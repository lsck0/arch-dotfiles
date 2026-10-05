#version 300 es
// @label False color

// Luma of the encoded signal (what a waveform shows) through Google's Turbo colormap: dark blue
// shadows, green mids, red highlights. Zebra stripes mark <= 2% (crushed) and >= 98% (clipped).

precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

#include "color.glsl"

const float CRUSHED = 0.02;
const float CLIPPED = 0.98;
const float ZEBRA_PERIOD_PX = 12.0;
// share of the original image kept under the heatmap, so text stays readable
const float DETAIL = 0.25;

// Turbo, Anton Mikhailov (Google AI, 2019), his published polynomial fit
vec3 turbo(float x) {
    const vec4 R4 = vec4(0.13572138, 4.61539260, -42.66032258, 132.13108234);
    const vec4 G4 = vec4(0.09140261, 2.19418839, 4.84296658, -14.18503333);
    const vec4 B4 = vec4(0.10667330, 12.64194608, -60.58204836, 110.36276771);
    const vec2 R2 = vec2(-152.94239396, 59.28637943);
    const vec2 G2 = vec2(4.27729857, 2.82956604);
    const vec2 B2 = vec2(-89.90310912, 27.34824973);
    x = clamp(x, 0.0, 1.0);
    vec4 v4 = vec4(1.0, x, x * x, x * x * x);
    vec2 v2 = v4.zw * v4.z;
    return clamp(vec3(dot(v4, R4) + dot(v2, R2), dot(v4, G4) + dot(v2, G2), dot(v4, B4) + dot(v2, B2)), 0.0, 1.0);
}

void main() {
    vec3 c = texture(tex, v_texcoord).rgb;
    float luma = dot(c, LUMA);
    vec3 heat = mix(turbo(luma), vec3(luma), DETAIL);
    float stripe = step(0.5, fract((gl_FragCoord.x + gl_FragCoord.y) / ZEBRA_PERIOD_PX));
    if (luma <= CRUSHED)
        heat = mix(vec3(0.0), vec3(0.45, 0.2, 0.9), stripe);
    else if (luma >= CLIPPED)
        heat = mix(vec3(1.0), vec3(1.0, 0.1, 0.1), stripe);
    fragColor = vec4(heat, 1.0);
}
