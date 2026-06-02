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
#endif //TONEMAPPING_HLSL