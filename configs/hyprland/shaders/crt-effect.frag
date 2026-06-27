#version 300 es

precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
uniform float time;
out vec4 fragColor;

float hash(float n) { return fract(sin(n) * 43758.5453); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

// --- tunables ---
const float WOBBLE      = 0.0014;
const float SATURATION  = 1.35;
const float CONTRAST    = 1.12;
const float GRADE_STR   = 0.28;   // neon color cast strength
const float BLOOM_STR   = 0.35;
const float BLOOM_THR   = 0.60;
const float SCAN_DEPTH  = 0.16;
const float GRAIN        = 0.030;
const float VIGNETTE     = 0.24;

// neon targets
const vec3 SHADOW_TINT   = vec3(0.85, 0.45, 0.25); // warm amber (was teal/blue)
const vec3 HILIGHT_TINT  = vec3(0.95, 0.35, 0.55); // warm pink/magenta

void main() {
    vec2 uv = v_texcoord;

    // tube wobble
    uv.x += sin(uv.y * 40.0 + time * 2.0) * WOBBLE;

    // rolling VHS tracking band
    float roll  = fract(uv.y + time * 0.15);
    float track = smoothstep(0.0, 0.05, roll) * smoothstep(0.12, 0.07, roll);
    uv.x += track * 0.010 * sin(time * 30.0);

    // datamosh blocks: occasional cells jump sideways
    vec2 grid  = vec2(24.0, 14.0);
    vec2 cell  = floor(uv * grid);
    float bsd  = floor(time * 9.0);
    float bh   = hash2(cell + bsd);
    float blk  = step(0.96, bh);
    uv += blk * (vec2(hash2(cell + bsd + 3.1), hash2(cell + bsd + 7.7)) - 0.5) * 0.06;

    // thin glitch tear bands
    float seed = floor(time * 12.0);
    float band = floor(gl_FragCoord.y / 8.0);
    float torn = step(0.92, hash(band + seed));
    uv.x += torn * (hash(band + seed + 1.7) - 0.5) * 0.045;

    // heavy chromatic / RGB split (pulsing, stronger on glitches)
    float ca = 0.0026 + 0.0014 * sin(time * 3.0) + (torn + blk) * 0.006;
    vec3 col;
    col.r = texture(tex, uv + vec2(ca, 0.0)).r;
    col.g = texture(tex, uv).g;
    col.b = texture(tex, uv - vec2(ca, 0.0)).b;

    // neon bloom (4-tap), tinted cyan/magenta by where it blooms
    vec2 r = vec2(0.0024);
    vec3 b = texture(tex, uv + vec2( r.x, 0.0)).rgb
           + texture(tex, uv + vec2(-r.x, 0.0)).rgb
           + texture(tex, uv + vec2(0.0,  r.y)).rgb
           + texture(tex, uv + vec2(0.0, -r.y)).rgb;
    b *= 0.25;
    vec3 bloom = max(b - BLOOM_THR, 0.0);
    col += bloom * BLOOM_STR * vec3(1.05, 0.85, 1.15);

    // neon color grade: lerp shadow->highlight tint by luma, then sat + contrast
    float l = dot(col, vec3(0.299, 0.587, 0.114));
    vec3 tint = mix(SHADOW_TINT, HILIGHT_TINT, smoothstep(0.15, 0.85, l));
    col = mix(col, col * tint * 1.6, GRADE_STR);
    col = mix(vec3(l), col, SATURATION);          // saturation
    col = (col - 0.5) * CONTRAST + 0.5;            // contrast

    // drifting scanlines
    float scan = sin((gl_FragCoord.y + time * 8.0) * 3.14159265) * 0.5 + 0.5;
    col *= mix(1.0 - SCAN_DEPTH, 1.0, scan);

    // band/block pops
    col *= 1.0 + track * 0.18 + torn * 0.06 + blk * 0.10;

    // animated grain
    float n = hash2(uv * vec2(640.0, 360.0) + time * 60.0) - 0.5;
    col += n * GRAIN;

    // mains flicker
    col *= 1.0 + 0.025 * sin(time * 50.0);

    // vignette (neutral, no blue)
    float d = distance(v_texcoord, vec2(0.5));
    float vig = smoothstep(0.35, 0.95, d);
    col *= mix(1.0, 1.0 - VIGNETTE, vig);

    fragColor = vec4(max(col, 0.0), 1.0);
}
