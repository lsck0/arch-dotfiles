#version 300 es

// THEME constants are rewritten by toggle-shader.sh

precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
uniform float time;
out vec4 fragColor;

// THEME
const vec3 BACKGROUND = vec3(0.0431, 0.0549, 0.0784);
const vec3 ACCENT = vec3(0.2235, 0.7294, 0.9020);
const float GLOW = 0.55;
const float SCANLINE_OPACITY = 0.06;
const float SCANLINE_SPACING_PX = 3.0;

// grade
const float SATURATION = 1.10;
const float CONTRAST = 1.06;
const float SHADOW_LIFT = 0.60;     // how far near-black is pulled to BACKGROUND
const float SHADOW_LUMA_MAX = 0.30; // luma where the lift fades out
const float HIGHLIGHT_TINT = 0.08;  // accent tint on bright areas

// glow: 4-tap bloom above a luma threshold, coloured toward ACCENT
const float BLOOM_RADIUS_UV = 0.0022;
const float BLOOM_THRESHOLD = 0.62;
const float BLOOM_ACCENT_MIX = 0.55;

// constant, small rgb split; the tear adds to it
const float ABERRATION_UV = 0.0007;

// tear: fires ~once every few seconds
const float TEAR_SLOT_S = 0.12;
const float TEAR_CHANCE = 0.03;
const float TEAR_BAND_PX = 6.0;
const float TEAR_BANDS_PER_SLOT = 0.985; // share of bands left untouched in a firing slot
const float TEAR_SHIFT_UV = 0.012;

const float GRAIN = 0.012;
const float VIGNETTE = 0.35;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

float hash(float n) {
    return fract(sin(n) * 43758.5453);
}
float hash2(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    vec2 uv = v_texcoord;

    // signal tear
    float slot = floor(time / TEAR_SLOT_S);
    float firing = step(1.0 - TEAR_CHANCE, hash(slot));
    float band = floor(gl_FragCoord.y / TEAR_BAND_PX);
    float torn = firing * step(TEAR_BANDS_PER_SLOT, hash(band + slot * 7.13));
    uv.x += torn * (hash(band + slot) - 0.5) * TEAR_SHIFT_UV;

    // rgb split
    float ca = ABERRATION_UV * (1.0 + torn * 4.0);
    vec3 col;
    col.r = texture(tex, uv + vec2(ca, 0.0)).r;
    col.g = texture(tex, uv).g;
    col.b = texture(tex, uv - vec2(ca, 0.0)).b;

    // neon glow
    vec3 b = texture(tex, uv + vec2(BLOOM_RADIUS_UV, 0.0)).rgb
            + texture(tex, uv - vec2(BLOOM_RADIUS_UV, 0.0)).rgb
            + texture(tex, uv + vec2(0.0, BLOOM_RADIUS_UV)).rgb
            + texture(tex, uv - vec2(0.0, BLOOM_RADIUS_UV)).rgb;
    vec3 bloom = max(b * 0.25 - BLOOM_THRESHOLD, 0.0);
    float bloomLuma = dot(bloom, LUMA);
    col += mix(bloom, ACCENT * bloomLuma * 2.0, BLOOM_ACCENT_MIX) * GLOW;

    // grade
    float l = dot(col, LUMA);
    col = mix(vec3(l), col, SATURATION);
    col = (col - 0.5) * CONTRAST + 0.5;
    col = mix(col, max(col, BACKGROUND), SHADOW_LIFT * (1.0 - smoothstep(0.0, SHADOW_LUMA_MAX, l)));
    col = mix(col, col * (0.5 + ACCENT), HIGHLIGHT_TINT * smoothstep(0.5, 1.0, l));

    // scanlines, matches Ui/Scanlines.qml
    col *= 1.0 - SCANLINE_OPACITY * step(mod(gl_FragCoord.y, SCANLINE_SPACING_PX), 1.0);

    col += (hash2(uv * vec2(640.0, 360.0) + time * 60.0) - 0.5) * GRAIN;

    // vignette into the theme background, not black
    float vig = smoothstep(0.35, 0.95, distance(v_texcoord, vec2(0.5)));
    col = mix(col, BACKGROUND, vig * VIGNETTE);

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
