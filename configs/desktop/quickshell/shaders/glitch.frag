// one-shot glitch for Ui/Glitch.qml: rgb split plus per-row offsets under a sine envelope
// that is zero at both ends, so the effect never leaves a frame behind.
// qt6 ShaderEffect only reads baked shaders: restart.sh runs
//   qsb --qt6 -o glitch.frag.qsb glitch.frag
// (qsb from qt6-shadertools) when the .qsb is missing or older; without it the glitch is skipped.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_progress;
    float u_rows;
    float u_seed;
};

layout(binding = 1) uniform sampler2D source;

const float PI = 3.14159265;
// fraction of rows that shift, and how far at the peak
const float ROW_SHARE = 0.3;
const float ROW_SHIFT = 0.06;
const float SPLIT = 0.012;

float hash(float n) {
    return fract(sin(n) * 43758.5453);
}

void main() {
    float env = sin(PI * clamp(u_progress, 0.0, 1.0));
    float row = floor(qt_TexCoord0.y * u_rows);
    float moved = step(1.0 - ROW_SHARE, hash(row + u_seed));
    float shift = moved * (hash(row * 1.7 + u_seed) - 0.5) * 2.0 * ROW_SHIFT * env;
    vec2 uv = vec2(qt_TexCoord0.x + shift, qt_TexCoord0.y);
    vec2 split = vec2(SPLIT * env, 0.0);
    vec4 base = texture(source, uv);
    float r = texture(source, uv + split).r;
    float b = texture(source, uv - split).b;
    fragColor = vec4(r, base.g, b, base.a) * qt_Opacity;
}
