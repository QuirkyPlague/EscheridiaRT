#include "Include/Generated/Signature.hlsl"
#include "Include/Util.hlsl"
#include "Include/settings.hlsl"
#include "Include/BloomCompute.hlsl"

// Bloom compute chain, stage 3/3: tent-upsample the mip chain built by CheckerboardInterleave
// (and TAA, when it ran) and add it back, equivalent to the old RTXPostFX.Bloom
// BloomUpscalePass + the bloom add that used to live in RTXPostFX.Tonemapping.
[numthreads(16, 16, 1)]
void ToneMappingHistogram(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex, 
    uint3 groupID : SV_GroupID
    )
{
    // Note that g_rootConstant0 from FinalCombine pass is accessible here
    uint2 fullRes = uint2(g_view.displayResolution);
    uint2 pixelPos = dispatchThreadID.xy;
    if (any(pixelPos >= fullRes)) return;

    uint2 mip0Res = max(fullRes / 2, uint2(1, 1));
    uint2 mip1Res = max(mip0Res / 2, uint2(1, 1));
    float2 uv = (float2(pixelPos) + 0.5f) / float2(fullRes);

    // Graduated radii (small/mid/wide) stand in for the old pass's multi-octave upscale chain,
    // since we only have two stored mips to work with.
    float3 bloomMip0 = TentUpsamplePixelRadius(outputBufferPreInterleave, uv, mip0Res, float2(fullRes), 8.0f);
    float3 bloom = bloomMip0;
    if (!isUpscalingEnabled()) {
        // mip1 is only populated when the TAA-stage downsample ran this frame.
        float3 bloomMip1 = TentUpsamplePixelRadius(outputBufferRayDirection, uv, mip1Res, float2(fullRes), 28.0f);
        // Re-samples mip1 with a much wider radius to fake the long soft tail that would
        // normally come from additional (unavailable) downscale octaves.
        float3 bloomWide = TentUpsamplePixelRadius(outputBufferRayDirection, uv, mip1Res, float2(fullRes), 70.0f);
        bloom = bloomMip0 * 0.4f + bloomMip1 * 0.35f + bloomWide * 0.25f;
    }

    float bloomRainIntensity = lerp(1.0f, RAIN_BLOOM_BOOST, getBiomeAdjustedRainLevel());

    float4 baseColor = outputBufferFinal[pixelPos];
    baseColor.rgb += bloom * COMPUTE_BLOOM_STRENGTH * bloomRainIntensity;
    //outputBufferFinal[pixelPos] = baseColor;
}