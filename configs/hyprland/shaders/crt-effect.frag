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
const float SATURATION = 1.35;
const float CONTRAST = 1.14;
const float SHADOW_LIFT = 0.60;     // how far near-black is pulled to BACKGROUND
const float SHADOW_LUMA_MAX = 0.30; // luma where the lift fades out
const float HIGHLIGHT_TINT = 0.22;  // accent tint on bright areas
const vec3 SHADOW_HEAT = vec3(1.25, 0.55, 0.85); // magenta push in the mids, against the accent highlights
const float HEAT_MIX = 0.18;

// glow: 4-tap bloom above a luma threshold, coloured toward ACCENT
const float BLOOM_RADIUS_UV = 0.0030;
const float BLOOM_THRESHOLD = 0.55;
const float BLOOM_ACCENT_MIX = 0.70;

// tube
const float WOBBLE_UV = 0.0018;
const float ROLL_SPEED = 0.18;      // tracking band sweeps per second
const float ROLL_SHIFT_UV = 0.014;
const float FLICKER = 0.035;

// rgb split: pulsing base, kicked by every glitch
const float ABERRATION_UV = 0.0030;
const float ABERRATION_PULSE_UV = 0.0018;
const float ABERRATION_KICK_UV = 0.009;

// tear bands
const float TEAR_RATE_HZ = 14.0;
const float TEAR_BAND_PX = 7.0;
const float TEAR_CHANCE = 0.09;     // share of bands torn per slot
const float TEAR_SHIFT_UV = 0.05;

// datamosh cells jumping sideways
const vec2 BLOCK_GRID = vec2(28.0, 16.0);
const float BLOCK_RATE_HZ = 10.0;
const float BLOCK_CHANCE = 0.045;
const float BLOCK_SHIFT_UV = 0.08;

// hsync jolt: the whole frame slips for a few frames, roughly every couple of seconds
const float JOLT_SLOT_S = 0.09;
const float JOLT_CHANCE = 0.035;
const float JOLT_SHIFT_UV = 0.035;

const float SCANLINE_BOOST = 2.5;   // theme scanline opacity is tuned for the bar, the screen gets more
const float SCANLINE_DRIFT_PX = 9.0;
const float GRAIN = 0.035;
const float VIGNETTE = 0.45;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

float hash(float n) {
    return fract(sin(n) * 43758.5453);
}
float hash2(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    vec2 uv = v_texcoord;

    float jslot = floor(time / JOLT_SLOT_S);
    float jolt = step(1.0 - JOLT_CHANCE, hash(jslot * 1.91));
    uv.x += jolt * (hash(jslot) - 0.5) * JOLT_SHIFT_UV;
    uv.y += jolt * (hash(jslot + 4.2) - 0.5) * JOLT_SHIFT_UV * 0.4;

    uv.x += sin(uv.y * 42.0 + time * 2.3) * WOBBLE_UV;

    float roll = fract(uv.y + time * ROLL_SPEED);
    float track = smoothstep(0.0, 0.05, roll) * smoothstep(0.12, 0.07, roll);
    uv.x += track * ROLL_SHIFT_UV * sin(time * 31.0);

    vec2 cell = floor(uv * BLOCK_GRID);
    float bslot = floor(time * BLOCK_RATE_HZ);
    float blk = step(1.0 - BLOCK_CHANCE, hash2(cell + bslot));
    uv += blk * (vec2(hash2(cell + bslot + 3.1), hash2(cell + bslot + 7.7)) - 0.5) * BLOCK_SHIFT_UV;

    float tslot = floor(time * TEAR_RATE_HZ);
    float band = floor(gl_FragCoord.y / TEAR_BAND_PX);
    float torn = step(1.0 - TEAR_CHANCE, hash(band + tslot));
    uv.x += torn * (hash(band + tslot + 1.7) - 0.5) * TEAR_SHIFT_UV;

    float glitch = clamp(torn + blk + jolt + track, 0.0, 1.0);
    float ca = ABERRATION_UV + ABERRATION_PULSE_UV * sin(time * 3.1) + glitch * ABERRATION_KICK_UV;
    vec3 col;
    col.r = texture(tex, uv + vec2(ca, ca * 0.3)).r;
    col.g = texture(tex, uv).g;
    col.b = texture(tex, uv - vec2(ca, ca * 0.3)).b;

    vec3 b = texture(tex, uv + vec2(BLOOM_RADIUS_UV, 0.0)).rgb
            + texture(tex, uv - vec2(BLOOM_RADIUS_UV, 0.0)).rgb
            + texture(tex, uv + vec2(0.0, BLOOM_RADIUS_UV)).rgb
            + texture(tex, uv - vec2(0.0, BLOOM_RADIUS_UV)).rgb;
    vec3 bloom = max(b * 0.25 - BLOOM_THRESHOLD, 0.0);
    float bloomLuma = dot(bloom, LUMA);
    col += mix(bloom, ACCENT * bloomLuma * 2.0, BLOOM_ACCENT_MIX) * GLOW * 1.6;

    float l = dot(col, LUMA);
    col = mix(col, col * SHADOW_HEAT, HEAT_MIX * (1.0 - smoothstep(0.35, 0.8, l)));
    col = mix(vec3(l), col, SATURATION);
    col = (col - 0.5) * CONTRAST + 0.5;
    col = mix(col, max(col, BACKGROUND), SHADOW_LIFT * (1.0 - smoothstep(0.0, SHADOW_LUMA_MAX, l)));
    col = mix(col, col * (0.5 + ACCENT), HIGHLIGHT_TINT * smoothstep(0.5, 1.0, l));

    // torn bands and moshed cells flash toward the accent
    col = mix(col, col + ACCENT * 0.35, (torn * 0.6 + blk * 0.8) * hash(band * 3.3 + tslot));

    float scan = sin((gl_FragCoord.y + time * SCANLINE_DRIFT_PX) * 3.14159265 * 2.0 / SCANLINE_SPACING_PX) * 0.5 + 0.5;
    col *= 1.0 - SCANLINE_OPACITY * SCANLINE_BOOST * scan;

    col *= 1.0 + track * 0.22 + jolt * 0.15;
    col += (hash2(uv * vec2(640.0, 360.0) + time * 60.0) - 0.5) * GRAIN;
    col *= 1.0 + FLICKER * sin(time * 50.0);

    // vignette into the theme background, not black
    float vig = smoothstep(0.30, 0.95, distance(v_texcoord, vec2(0.5)));
    col = mix(col, BACKGROUND, vig * VIGNETTE);

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
