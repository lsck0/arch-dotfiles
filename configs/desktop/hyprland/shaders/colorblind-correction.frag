#version 300 es
// @label Colorblind correction
// @variants deuteranopia protanopia tritanopia

// Daltonization after Fidaner, Lin, Ozguven, "Analysis of Color Blindness" (2005): simulate the
// deficiency (Machado 2009, color.glsl), take what got lost, and add it back on channels the viewer
// still distinguishes. Red-green losses go to green and blue, blue-yellow losses to red and green.
// Done in linear light so the error is a physical difference, not a gamma-encoded one.

precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

#include "color.glsl"

// rewritten by toggle-shader.sh from @variants, CVD_* order
const int VARIANT = 0;

// Fidaner 2005 error shift for protan and deutan, rows: red error into green and blue
const mat3 SHIFT_RED_GREEN = mat3(0.0, 0.0, 0.0,
                                  0.7, 1.0, 0.0,
                                  0.7, 0.0, 1.0);
// the same idea mirrored for tritan, rows: blue error into red and green
const mat3 SHIFT_BLUE_YELLOW = mat3(1.0, 0.0, 0.7,
                                    0.0, 1.0, 0.7,
                                    0.0, 0.0, 0.0);

void main() {
    vec3 c = srgb_to_linear(texture(tex, v_texcoord).rgb);
    vec3 lost = c - c * machado_cvd(VARIANT);
    mat3 shift = VARIANT == CVD_TRITANOPIA ? SHIFT_BLUE_YELLOW : SHIFT_RED_GREEN;
    fragColor = vec4(linear_to_srgb(c + lost * shift), 1.0);
}
