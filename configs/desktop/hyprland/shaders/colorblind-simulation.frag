#version 300 es
// @label Colorblind simulation
// @variants deuteranopia protanopia tritanopia

precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

#include "color.glsl"

const int VARIANT = 0;

void main() {
    vec3 c = srgb_to_linear(texture(tex, v_texcoord).rgb);
    fragColor = vec4(linear_to_srgb(c * machado_cvd(VARIANT)), 1.0);
}
