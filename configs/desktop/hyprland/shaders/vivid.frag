#version 300 es
// @label Vivid

precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

#include "color.glsl"

const float SATURATION = 1.10;
const float VIBRANCE = 0.15;
const float CHROMA_MAX = 0.32;

void main() {
    vec3 lab = linear_to_oklab(srgb_to_linear(texture(tex, v_texcoord).rgb));
    float chroma = length(lab.yz);
    float boost = SATURATION * (1.0 + VIBRANCE * (1.0 - clamp(chroma / CHROMA_MAX, 0.0, 1.0)));
    // near-neutral surfaces keep the palette's hue and contrast
    boost = mix(1.0, boost, smoothstep(0.015, 0.05, chroma));
    vec3 rgb = oklab_to_linear(vec3(lab.x, lab.yz * boost));
    if (any(lessThan(rgb, vec3(0.0))) || any(greaterThan(rgb, vec3(1.0)))) {
        rgb = oklab_to_linear(vec3(lab.x, lab.yz * mix(1.0, boost, 0.5)));
    }
    fragColor = vec4(linear_to_srgb(rgb), 1.0);
}
