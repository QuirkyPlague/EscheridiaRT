#ifndef BLOOM_COMPUTE_HLSL
#define BLOOM_COMPUTE_HLSL

#include "tonemapping.hlsl"

// Same firefly-suppression trick as the old BloomDownscaleUniformPass (fragment.sc KarisAverage).
float KarisWeight(float3 c) { return 1.0f / (1.0f + luminance(c)); }

// Bilinear fetch from a full-size RW scratch buffer that only has valid data in its
// [0, res) sub-rect, since compute UAVs have no SamplerState to filter with.
float3 SampleBilinearRW(RWTexture2D<float4> tex, float2 uv, uint2 res)
{
    float2 pixel = saturate(uv) * res - 0.5f;
    float2 f = frac(pixel);
    int2 p0 = int2(floor(pixel));
    int2 maxIdx = int2(res) - 1;

    int2 p00 = clamp(p0, int2(0, 0), maxIdx);
    int2 p10 = clamp(p0 + int2(1, 0), int2(0, 0), maxIdx);
    int2 p01 = clamp(p0 + int2(0, 1), int2(0, 0), maxIdx);
    int2 p11 = clamp(p0 + int2(1, 1), int2(0, 0), maxIdx);

    float3 top = lerp(tex[uint2(p00)].rgb, tex[uint2(p10)].rgb, f.x);
    float3 bottom = lerp(tex[uint2(p01)].rgb, tex[uint2(p11)].rgb, f.x);
    return lerp(top, bottom, f.y);
}

// Ports BloomDownscaleUniformPass's 13-tap Karis-weighted downsample (fragment.sc
// downscaleBloomFiltered, BLOOM_DOWNSCALE_UNIFORM_PASS branch) so the harsh 2x2 box we had
// before doesn't feed blocky data into the rest of the chain. texelScale widens the tap
// footprint beyond 1 source texel, letting a single downsample stand in for extra octaves.
float3 Downsample13TapKaris(RWTexture2D<float4> src, float2 uv, uint2 srcRes, float texelScale)
{
    float2 texel = texelScale / float2(srcRes);
    float x = texel.x;
    float y = texel.y;

    float3 a = SampleBilinearRW(src, uv + float2(-2.0f * x, 2.0f * y), srcRes);
    float3 b = SampleBilinearRW(src, uv + float2(0.0f, 2.0f * y), srcRes);
    float3 c = SampleBilinearRW(src, uv + float2(2.0f * x, 2.0f * y), srcRes);

    float3 d = SampleBilinearRW(src, uv + float2(-2.0f * x, 0.0f), srcRes);
    float3 e = SampleBilinearRW(src, uv, srcRes);
    float3 f = SampleBilinearRW(src, uv + float2(2.0f * x, 0.0f), srcRes);

    float3 g = SampleBilinearRW(src, uv + float2(-2.0f * x, -2.0f * y), srcRes);
    float3 h = SampleBilinearRW(src, uv + float2(0.0f, -2.0f * y), srcRes);
    float3 i = SampleBilinearRW(src, uv + float2(2.0f * x, -2.0f * y), srcRes);

    float3 j = SampleBilinearRW(src, uv + float2(-x, y), srcRes);
    float3 k = SampleBilinearRW(src, uv + float2(x, y), srcRes);
    float3 l = SampleBilinearRW(src, uv + float2(-x, -y), srcRes);
    float3 m = SampleBilinearRW(src, uv + float2(x, -y), srcRes);

    float3 groups[5];
    groups[0] = (a + b + d + e) * (0.125f / 4.0f);
    groups[1] = (b + c + e + f) * (0.125f / 4.0f);
    groups[2] = (d + e + g + h) * (0.125f / 4.0f);
    groups[3] = (e + f + h + i) * (0.125f / 4.0f);
    groups[4] = (j + k + l + m) * (0.5f / 4.0f);

    groups[0] *= KarisWeight(groups[0]);
    groups[1] *= KarisWeight(groups[1]);
    groups[2] *= KarisWeight(groups[2]);
    groups[3] *= KarisWeight(groups[3]);
    groups[4] *= KarisWeight(groups[4]);

    return groups[0] + groups[1] + groups[2] + groups[3] + groups[4];
}

// Ports the plain (non-Karis) 13-tap weighted downsample used by BloomDownscaleGaussianPass.
// texelScale widens the tap footprint beyond 1 source texel, letting a single downsample
// stand in for extra octaves that we don't have spare passes to compute separately.
float3 Downsample13TapWeighted(RWTexture2D<float4> src, float2 uv, uint2 srcRes, float texelScale)
{
    float2 texel = texelScale / float2(srcRes);
    float x = texel.x;
    float y = texel.y;

    float3 a = SampleBilinearRW(src, uv + float2(-2.0f * x, 2.0f * y), srcRes);
    float3 b = SampleBilinearRW(src, uv + float2(0.0f, 2.0f * y), srcRes);
    float3 c = SampleBilinearRW(src, uv + float2(2.0f * x, 2.0f * y), srcRes);

    float3 d = SampleBilinearRW(src, uv + float2(-2.0f * x, 0.0f), srcRes);
    float3 e = SampleBilinearRW(src, uv, srcRes);
    float3 f = SampleBilinearRW(src, uv + float2(2.0f * x, 0.0f), srcRes);

    float3 g = SampleBilinearRW(src, uv + float2(-2.0f * x, -2.0f * y), srcRes);
    float3 h = SampleBilinearRW(src, uv + float2(0.0f, -2.0f * y), srcRes);
    float3 i = SampleBilinearRW(src, uv + float2(2.0f * x, -2.0f * y), srcRes);

    float3 j = SampleBilinearRW(src, uv + float2(-x, y), srcRes);
    float3 k = SampleBilinearRW(src, uv + float2(x, y), srcRes);
    float3 l = SampleBilinearRW(src, uv + float2(-x, -y), srcRes);
    float3 m = SampleBilinearRW(src, uv + float2(x, -y), srcRes);

    float3 downsample = e * 0.125f;
    downsample += (a + c + g + i) * 0.03125f;
    downsample += (b + d + f + h) * 0.0625f;
    downsample += (j + k + l + m) * 0.125f;
    return downsample;
}

// Ports upscaleBloomFiltered's 3x3 tent upsample, with the filter radius expressed in
// full-resolution screen pixels (like the old pass's fixed filterSize) rather than mip
// texels, so the kernel stays physically wide instead of shrinking away at smaller mips.
// This is the main source of the old bloom's soft, long falloff.
float3 TentUpsamplePixelRadius(RWTexture2D<float4> src, float2 uv, uint2 srcRes, float2 fullRes, float radiusPixels)
{
    float2 o = radiusPixels / fullRes;

    float3 a = SampleBilinearRW(src, uv + float2(-o.x, o.y), srcRes);
    float3 b = SampleBilinearRW(src, uv + float2(0.0f, o.y), srcRes);
    float3 c = SampleBilinearRW(src, uv + float2(o.x, o.y), srcRes);

    float3 d = SampleBilinearRW(src, uv + float2(-o.x, 0.0f), srcRes);
    float3 e = SampleBilinearRW(src, uv, srcRes);
    float3 f = SampleBilinearRW(src, uv + float2(o.x, 0.0f), srcRes);

    float3 g = SampleBilinearRW(src, uv + float2(-o.x, -o.y), srcRes);
    float3 h = SampleBilinearRW(src, uv + float2(0.0f, -o.y), srcRes);
    float3 i = SampleBilinearRW(src, uv + float2(o.x, -o.y), srcRes);

    float3 upsample = e * 4.0f;
    upsample += (b + d + f + h) * 2.0f;
    upsample += (a + c + g + i);
    return upsample * (1.0f / 16.0f);
}

#endif // BLOOM_COMPUTE_HLSL
