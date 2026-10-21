#version 300 es
// @label Colorblind correction
// @variants deuteranopia protanopia tritanopia

precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

#include "color.glsl"

const int VARIANT = 0;

const mat3 SHIFT_RED_GREEN = mat3(0.0, 0.0, 0.0,
                                  0.7, 1.0, 0.0,
                                  0.7, 0.0, 1.0);
const mat3 SHIFT_BLUE_YELLOW = mat3(1.0, 0.0, 0.7,
                                    0.0, 1.0, 0.7,
                                    0.0, 0.0, 0.0);

void main() {
    vec3 c = srgb_to_linear(texture(tex, v_texcoord).rgb);
    vec3 lost = c - c * machado_cvd(VARIANT);
    mat3 shift = VARIANT == CVD_TRITANOPIA ? SHIFT_BLUE_YELLOW : SHIFT_RED_GREEN;
    fragColor = vec4(linear_to_srgb(c + lost * shift), 1.0);
}
