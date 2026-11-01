#ifndef COLORS_HLSL
#define COLORS_HLSL

float3 SRGBToLinear(float3 color)
{
    float3 low = color / 12.92;
    float3 high = pow((color + 0.055) / 1.055, 2.4);

    return lerp(
        high,
        low,
        float3(
            color.r <= 0.04045,
            color.g <= 0.04045,
            color.b <= 0.04045
        )
    );
}

#endif
