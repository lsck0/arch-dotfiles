#version 300 es
// @label Smart invert

precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

#include "color.glsl"

const float LIGHTNESS_FLOOR = 0.15;

void main() {
    vec3 lab = linear_to_oklab(srgb_to_linear(texture(tex, v_texcoord).rgb));
    lab.x = mix(LIGHTNESS_FLOOR, 1.0, 1.0 - lab.x);
    fragColor = vec4(linear_to_srgb(oklab_to_linear(lab)), 1.0);
}
