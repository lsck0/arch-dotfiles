#version 300 es
// @label Composition grid

precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
uniform vec2 fullSize;
out vec4 fragColor;

#include "color.glsl"

const float LINE_PX = 1.0;
const float THIRDS_ALPHA = 0.35;
const float CENTER_ALPHA = 0.22;
const float CENTER_DASH_PX = 8.0;

// 1 within half a line of a guide at uv fraction f on this axis, in physical pixels
float guide(float uv, float size, float f) {
    return step(abs(uv - f) * size, LINE_PX * 0.5);
}

void main() {
    vec3 c = texture(tex, v_texcoord).rgb;
    vec2 px = v_texcoord * fullSize;
    float thirds = max(max(guide(v_texcoord.x, fullSize.x, 1.0 / 3.0), guide(v_texcoord.x, fullSize.x, 2.0 / 3.0)),
                       max(guide(v_texcoord.y, fullSize.y, 1.0 / 3.0), guide(v_texcoord.y, fullSize.y, 2.0 / 3.0)));
    float center = max(guide(v_texcoord.x, fullSize.x, 0.5) * step(0.5, fract(px.y / CENTER_DASH_PX)),
                       guide(v_texcoord.y, fullSize.y, 0.5) * step(0.5, fract(px.x / CENTER_DASH_PX)));
    // white over dark content, black over light, so the guide never disappears
    vec3 ink = vec3(1.0 - step(0.5, dot(c, LUMA)));
    c = mix(c, ink, max(thirds * THIRDS_ALPHA, center * CENTER_ALPHA));
    fragColor = vec4(c, 1.0);
}
