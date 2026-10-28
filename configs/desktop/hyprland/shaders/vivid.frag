#version 300 es
// @label Vivid

precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

#include "color.glsl"

const float SATURATION = 1.08;
const float VIBRANCE = 0.15;
const float CHROMA_MAX = 0.32;

void main() {
    vec3 lab = linear_to_oklab(srgb_to_linear(texture(tex, v_texcoord).rgb));
    float chroma = length(lab.yz);
    lab.yz *= SATURATION * (1.0 + VIBRANCE * (1.0 - clamp(chroma / CHROMA_MAX, 0.0, 1.0)));
    fragColor = vec4(linear_to_srgb(oklab_to_linear(lab)), 1.0);
}
