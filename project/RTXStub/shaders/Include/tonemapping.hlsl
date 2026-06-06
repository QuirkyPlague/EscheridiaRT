#ifndef TONEMAPPING_HLSL
#define TONEMAPPING_HLSL


float luminance(float3 color) {
  return dot(color, float3(0.2126, 0.7152, 0.0722));
}

float3 change_luminance(float3 c_in, float l_out)
{
    float l_in = luminance(c_in);
    return c_in * (l_out / l_in);
}

float3 reinhard_extended(float3 v, float max_white)
{
    float3 numerator = v * (1.0f + (v / float3(max_white * max_white, max_white * max_white, max_white * max_white)));
    return numerator / (1.0f + v);
}

float3 LottesTonemap(float3 x)
{
    x *= 0.4;


    const float3 a = float3(1.6, 1.6, 1.6);
    const float3 d = float3(0.977, 0.977, 0.977);
    const float3 hdrMax = float3(8.0, 8.0, 8.0);
    const float3 midIn = float3(0.18, 0.18, 0.18);
    const float3 midOut = float3(0.267, 0.267, 0.267);

    float3 b = (-pow(midIn, a) + pow(hdrMax, a) * midOut) /
               ((pow(hdrMax, a * d) - pow(midIn, a * d)) * midOut);

    float3 c = (pow(hdrMax, a * d) * pow(midIn, a) -
                pow(hdrMax, a) * pow(midIn, a * d) * midOut) /
               ((pow(hdrMax, a * d) - pow(midIn, a * d)) * midOut);

	
	
    return (pow(x, a) / (pow(x, a * d) * b + c));
}

float3 RRTAndODTFit(float3 v)
            {
                float3 a = v * (v + 0.0245786) - 0.000090537;
                float3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
                return a / b;
            }

            float3 ACESFitted(float3 color)
            {
                float3x3 ACESInputMat = float3x3(
                0.59719, 0.35458, 0.04823,
                0.07600, 0.90834, 0.01566,
                0.02840, 0.13383, 0.83777
                );

                float3x3 ACESOutputMat = float3x3(
                1.60475, -0.53108, -0.07367,
                -0.10208, 1.10813, -0.00605,
                -0.00327, -0.07276, 1.07602
                );

                color = mul(ACESInputMat, color);
                color = RRTAndODTFit(color);
                color = mul(ACESOutputMat, color);

                return saturate(color);
            }
            float3 TonemapACES(float3 rgb) { return ACESFitted(rgb); }






// MIT License
//
// Copyright (c) 2024 Missing Deadlines (Benjamin Wrensch)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// 0: Default, 1: Golden, 2: Punchy
#define AGX_LOOK 2

// Mean error^2: 3.6705141e-06
float3 agxDefaultContrastApprox(float3 x)
{
    float3 x2 = x * x;
    float3 x4 = x2 * x2;

    return +15.5 * x4 * x2
            - 40.14 * x4 * x
            + 31.96 * x4
            - 6.868 * x2 * x
            + 0.4298 * x2
            + 0.1191 * x
            - 0.00232;
}
float3 agx(float3 val)
{
    static const float3x3 agx_mat = float3x3(
    0.842479062253094, 0.0784335999999992, 0.0792237451477643,
    0.0423282422610123, 0.878468636469772, 0.0791661274605434,
    0.0423756549057051, 0.0784336, 0.879142973793104);

    static const float min_ev = -8.47393f;
    static const float max_ev = 8.026069f;

    // Input transform (inset)
    val = mul(agx_mat, val);

    // Log2 space encoding
    val = clamp(log2(val), min_ev, max_ev);
    val = (val - min_ev) / (max_ev - min_ev);

    // Apply sigmoid function approximation
    val = agxDefaultContrastApprox(val);
    return val;
}

float3 agxEotf(float3 val)
{
    static const float3x3 agx_mat_inv = float3x3(
    1.19687900512017, -0.0980208811401368, -0.0990297440797205,
   -0.0528968517574562, 1.15190312990417, -0.0989611768448433,
   -0.0529716355144438, -0.0980434501171241, 1.15107367264116);

    // Inverse input transform (outset)
    val = mul(agx_mat_inv, val);

    // sRGB IEC 61966-2-1 2.2 Exponent Reference EOTF Display
    // NOTE: We're linearizing the output here. Comment/adjust when
    // *not* using a sRGB render target
    val = pow(val, float3(2.2, 2.2, 2.2));
    return val;
}

float3 agxLook(float3 val)
{
    // Default
    float3 offset = float3(0.0, 0.0, 0.0);
    float3 slope = float3(1.0, 1.0, 1.0);
    float3 power = float3(1.0, 1.0, 1.0);
    float sat = 1.15;

#if AGX_LOOK == 1
    // Golden
    slope = float3(1.0, 0.95, 0.9);
    power = float3(0.8, 0.8, 0.8);
    sat = 0.8;
#elif AGX_LOOK == 2
    // Punchy
    slope = float3(1.0, 1.0, 1.0);
    power = float3(1.35, 1.35, 1.35);
    sat = 1.45;
#endif

    // ASC CDL
    val = pow(val * slope + offset, power);
    static const float3 lw = float3(0.2126, 0.7152, 0.0722);
    float luma = dot(val, lw);
    return luma + sat * (val - luma);
}

    float3 tonemapAgX(float3 color)
{
    color = agx(color);
    color = agxLook(color);
    color = agxEotf(color);
    return color;
}
#endif //TONEMAPPING_HLSL