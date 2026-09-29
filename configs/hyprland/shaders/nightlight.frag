#version 300 es

// night light: scale by a 4000K white point

precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

// 4000K from Tanner Helland's blackbody fit, rgb(255, 206, 166) over 255
const vec3 WHITE_POINT = vec3(1.0, 0.8078, 0.6510);

void main() {
    vec3 c = texture(tex, v_texcoord).rgb;
    fragColor = vec4(c * WHITE_POINT, 1.0);
}
