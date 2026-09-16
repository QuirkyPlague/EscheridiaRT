#include "Include/Generated/Signature.hlsl"
#include "Include/Util.hlsl"
#include "Include/settings.hlsl"
#include "Include/BloomCompute.hlsl"

// Bloom compute chain, stage 2/3 (this pass is skipped when DLSS replaces TAA, in which case
// the composite stage just falls back to mip0): wide tent downsample of mip0, equivalent to
// the old RTXPostFX.Bloom BloomDownscaleGaussianPass.
[numthreads(16, 16, 1)]
void TAA(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex, 
    uint3 groupID : SV_GroupID
    )
{
    // Note that g_rootConstant0 from FinalCombine pass is accessible here
    if (isUpscalingEnabled()) return;

    uint2 mip0Res = max(uint2(g_view.displayResolution) / 2, uint2(1, 1));
    uint2 mip1Res = max(mip0Res / 2, uint2(1, 1));
    uint2 pixelPos = dispatchThreadID.xy;
    if (any(pixelPos >= mip1Res)) return;

    float2 uv = (float2(pixelPos) + 0.5f) / float2(mip1Res);
    // texelScale > 1 widens mip1's footprint to make up for the extra downscale octaves
    // the old raster bloom had that we don't have spare passes for.
    outputBufferRayDirection[pixelPos] = float4(Downsample13TapWeighted(outputBufferPreInterleave, uv, mip0Res, 2.5f), 1.0f);
}