// shared color math, pasted into a shader by toggle-shader.sh where it says #include "color.glsl"
//
// sRGB transfer: IEC 61966-2-1 piecewise curve, the exact inverse pair rather than a 2.2 power.
// OKLab: Bjoern Ottosson, "A perceptual color space for image processing" (2020), matrices as published
// for linear sRGB input; L is perceived lightness in [0, 1], a/b the opponent axes, chroma = length(ab).
// CVD: Machado, Oliveira, Fernandes, "A Physiologically-based Model for Simulation of Color Vision
// Deficiency" (IEEE TVCG 2009), severity 1.0 matrices, defined on linear RGB.
// GLSL mat3 takes columns: every matrix below is written row by row and applied as `v * M`, which is R v.

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722); // ITU-R BT.709 luma weights

// variant order shared by every @variants line that uses machado_cvd
const int CVD_DEUTERANOPIA = 0;
const int CVD_PROTANOPIA = 1;
const int CVD_TRITANOPIA = 2;

vec3 srgb_to_linear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

vec3 linear_to_srgb(vec3 c) {
    c = clamp(c, 0.0, 1.0);
    return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

vec3 linear_to_oklab(vec3 c) {
    // linear sRGB to cone response, rows
    const mat3 LMS = mat3(0.4122214708, 0.5363325363, 0.0514459929,
                          0.2119034982, 0.6806995451, 0.1073969566,
                          0.0883024619, 0.2817188376, 0.6299787005);
    // nonlinear cone response to Lab, rows
    const mat3 LAB = mat3(0.2104542553, 0.7936177850, -0.0040720468,
                          1.9779984951, -2.4285922050, 0.4505937099,
                          0.0259040371, 0.7827717662, -0.8086757660);
    vec3 lms = c * LMS;
    return (sign(lms) * pow(abs(lms), vec3(1.0 / 3.0))) * LAB;
}

vec3 oklab_to_linear(vec3 lab) {
    // Lab to nonlinear cone response, rows
    const mat3 LMS_ = mat3(1.0, 0.3963377774, 0.2158037573,
                           1.0, -0.1055613458, -0.0638541728,
                           1.0, -0.0894841775, -1.2914855480);
    // cone response to linear sRGB, rows
    const mat3 RGB = mat3(4.0767416621, -3.3077115913, 0.2309699292,
                          -1.2684380046, 2.6097574011, -0.3413193965,
                          -0.0041960863, -0.7034186147, 1.7076147010);
    vec3 lms = lab * LMS_;
    return (lms * lms * lms) * RGB;
}

mat3 machado_cvd(int variant) {
    if (variant == CVD_PROTANOPIA)
        return mat3(0.152286, 1.052583, -0.204868,
                    0.114503, 0.786281, 0.099216,
                    -0.003882, -0.048116, 1.051998);
    if (variant == CVD_TRITANOPIA)
        return mat3(1.255528, -0.076749, -0.178779,
                    -0.078411, 0.930809, 0.147602,
                    0.004733, 0.691367, 0.303900);
    return mat3(0.367322, 0.860646, -0.227968,
                0.280085, 0.672501, 0.047413,
                -0.011820, 0.042940, 0.968881);
}
