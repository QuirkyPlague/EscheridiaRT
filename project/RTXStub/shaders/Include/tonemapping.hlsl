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

#endif //TONEMAPPING_HLSL