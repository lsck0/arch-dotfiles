#version 300 es
// @label Vivid

// The saturation boost the hardware grading cannot do (a CTM with negative entries is rejected).
// Chroma is scaled in OKLab so hue and lightness stay put; vibrance adds more to muted colors than
// to already saturated ones, which keeps skin and brand colors from blowing out.

precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

#include "color.glsl"

const float SATURATION = 1.12;
const float VIBRANCE = 0.25;
// OKLab chroma of the most saturated sRGB primaries, about 0.32 for blue; normalizes vibrance
const float CHROMA_MAX = 0.32;

void main() {
    vec3 lab = linear_to_oklab(srgb_to_linear(texture(tex, v_texcoord).rgb));
    float chroma = length(lab.yz);
    lab.yz *= SATURATION * (1.0 + VIBRANCE * (1.0 - clamp(chroma / CHROMA_MAX, 0.0, 1.0)));
    fragColor = vec4(linear_to_srgb(oklab_to_linear(lab)), 1.0);
}
