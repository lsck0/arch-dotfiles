#version 300 es

precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

const float SATURATION = 1.035; // overall saturation
const float VIBRANCE   = 0.05;  // extra boost for the LESS saturated pixels
const float CONTRAST   = 1.05;  // gentle S-curve around mid grey
const float GAMMA      = 1.07;  // >1 deepens mids/shadows ("less gamma" lift)
const float BLACKPOINT = 0.010; // crush the very darkest a touch -> deeper blacks

void main() {
    vec3 c = texture(tex, v_texcoord).rgb;

    float l = dot(c, vec3(0.2126, 0.7152, 0.0722));

    // vibrance: push low-saturation pixels harder, leave vivid ones alone
    float mx  = max(c.r, max(c.g, c.b));
    float mn  = min(c.r, min(c.g, c.b));
    float sat = mx - mn;
    c = mix(vec3(l), c, 1.0 + VIBRANCE * (1.0 - sat));

    // overall saturation
    c = mix(vec3(l), c, SATURATION);

    // contrast around mid grey
    c = (c - 0.5) * CONTRAST + 0.5;

    // black point + gamma deepen
    c = max(c - BLACKPOINT, 0.0) / (1.0 - BLACKPOINT);
    c = pow(max(c, 0.0), vec3(GAMMA));

    fragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
