#version 300 es
// @label Colorblind simulation
// @variants deuteranopia protanopia tritanopia

// Machado 2009 at severity 1.0, applied in linear light as the model is defined (see color.glsl).

precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

#include "color.glsl"

// rewritten by toggle-shader.sh from @variants, CVD_* order
const int VARIANT = 0;

void main() {
    vec3 c = srgb_to_linear(texture(tex, v_texcoord).rgb);
    fragColor = vec4(linear_to_srgb(c * machado_cvd(VARIANT)), 1.0);
}
