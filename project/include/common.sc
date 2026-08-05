float luminance(vec3 clr) { return dot(clr, vec3(0.2126, 0.7152, 0.0722)); }

// https://en.wikipedia.org/wiki/SRGB#From_CIE_XYZ_to_sRGB
vec3 linearToSRGB(vec3 c) {
    // Full linear to sRGB function
    return max(mix(12.92 * c, 1.055 * pow(c, 1.0 / 2.4) - 0.055, greaterThan(c, 0.0031308)), 0);
    
    // Approximation
    //return max(pow(c, 1.0 / 2.2), 0);
}

// Bloom implementation is based on: https://learnopengl.com/Guest-Articles/2022/Phys.-Based-Bloom
float KarisAverage(vec3 col) {
    // Formula is 1 / (1 + luma)
    // luma = luminance(gamma_correct(hdr))
    float luma = luminance(linearToSRGB(col)) * 0.25;
    return 1.0 / (1.0 + luma);
}
vec3 upscaleBloomFiltered(vec2 texCoord, mediump sampler2D _sampler, vec2 windowRes) {
    // The filter kernel is applied with a radius, specified in pixels
    // of the final game window output.
    const float filterSize = 12.0;
    vec2 filterOffset = filterSize / windowRes;
    
    float x = filterOffset.x;
    float y = filterOffset.y;
    
    // Take 9 samples around current texel:
    // a - b - c
    // d - e - f
    // g - h - i
    // === ('e' is the current texel) ===
    vec3 a = texture2D(_sampler, vec2(texCoord.x - x, texCoord.y + y)).rgb;
    vec3 b = texture2D(_sampler, vec2(texCoord.x, texCoord.y + y)).rgb;
    vec3 c = texture2D(_sampler, vec2(texCoord.x + x, texCoord.y + y)).rgb;
    
    vec3 d = texture2D(_sampler, vec2(texCoord.x - x, texCoord.y)).rgb;
    vec3 e = texture2D(_sampler, vec2(texCoord.x, texCoord.y)).rgb;
    vec3 f = texture2D(_sampler, vec2(texCoord.x + x, texCoord.y)).rgb;
    
    vec3 g = texture2D(_sampler, vec2(texCoord.x - x, texCoord.y - y)).rgb;
    vec3 h = texture2D(_sampler, vec2(texCoord.x, texCoord.y - y)).rgb;
    vec3 i = texture2D(_sampler, vec2(texCoord.x + x, texCoord.y - y)).rgb;
    
    // Apply weighted distribution, by using a 3x3 tent filter:
    //  1   | 1 2 1 |
    // -- * | 2 4 2 |
    // 16   | 1 2 1 |
    vec3 upsample = e*4.0;
    upsample += (b + d+f + h) * 2.0;
    upsample += (a + c+g + i);
    upsample *= 1.0 / 16.0;
    return upsample;
}

// https://github.com/TheRealMJP/BakingLab/blob/master/BakingLab/ACES.hlsl
vec3 RRTAndODTFit(vec3 v) {
    vec3 a = v * (v + 0.0245786) - 0.000090537;
    vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
    return a / b;
}
vec3 ACESFittedTonemap(vec3 rgb) {
    const mat3 ACESInputMat = mtxFromCols(
        vec3(0.59719, 0.35458, 0.04823),
        vec3(0.07600, 0.90834, 0.01566),
        vec3(0.02840, 0.13383, 0.83777)
    );
    const mat3 ACESOutputMat = mtxFromCols(
        vec3(1.60475, - 0.53108, - 0.07367),
        vec3(- 0.10208, 1.10813, - 0.00605),
        vec3(- 0.00327, - 0.07276, 1.07602)
    );
    rgb = mul(rgb, ACESInputMat);
    rgb = RRTAndODTFit(rgb);
    rgb = mul(rgb, ACESOutputMat);
    rgb = clamp(rgb, 0.0, 1.0);
    return rgb;
}

// 0: Default, 1: Golden, 2: Punchy
#define AGX_LOOK 2

// Mean error^2: 3.6705141e-06
vec3 agxDefaultContrastApprox(vec3 x) {
    vec3 x2 = x * x;
    vec3 x4 = x2 * x2;

    return  15.5   * x4 * x2
          - 40.14  * x4 * x
          + 31.96  * x4
          - 6.868  * x2 * x
          + 0.4298 * x2
          + 0.1191 * x
          - 0.00232;
}

vec3 agx(vec3 val) {
    const mat3 agxMat = mat3(
        0.842479062253094, 0.0784335999999992, 0.0792237451477643,
        0.0423282422610123, 0.878468636469772,  0.0791661274605434,
        0.0423756549057051, 0.0784336,          0.879142973793104
    );

    const float minEV = -12.47393;
    const float maxEV = 4.026069;

    // Match the original HLSL transform order exactly.
    val = mul(agxMat, val);

    val = clamp(log2(max(val, vec3(1e-10, 1e-10, 1e-10))), minEV, maxEV);
    val = (val - minEV) / (maxEV - minEV);

    return agxDefaultContrastApprox(val);
}

vec3 agxEotf(vec3 val) {
    const mat3 agxMatInv = mat3(
         1.19687900512017,   -0.0980208811401368, -0.0990297440797205,
        -0.0528968517574562,  1.15190312990417,   -0.0989611768448433,
        -0.0529716355144438, -0.0980434501171241,  1.15107367264116
    );

    val = mul(agxMatInv, val);

    // Remove this conversion if writing to an sRGB framebuffer.
    return pow(max(val, vec3(0.0, 0.0, 0.0)), vec3(2.2, 2.2, 2.2));
}

vec3 agxLook(vec3 val) {
    vec3 offset = vec3(0.0, 0.0, 0.0);
    vec3 slope  = vec3(1.0, 1.0, 1.0);
    vec3 power  = vec3(1.0, 1.0, 1.0);
    float sat   = 1.15;

#if AGX_LOOK == 1
    // Golden
    slope = vec3(1.0, 0.95, 0.9);
    power = vec3(0.8, 0.8, 0.8);
    sat = 0.8;
#elif AGX_LOOK == 2
    // Punchy
    power = vec3(1.25, 1.25, 1.25);
#endif

    val = pow(max(val * slope + offset, vec3(0.0, 0.0, 0.0)), power);

    const vec3 lumaWeights = vec3(0.2126, 0.7152, 0.0722);
    float luma = dot(val, lumaWeights);

    return vec3(luma, luma, luma) + sat * (val - vec3(luma, luma, luma));
}

vec3 tonemapAgX(vec3 color) {
    color = agx(color);
    color = agxLook(color);
    return agxEotf(color);
}