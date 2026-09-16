#include "Include/Generated/Signature.hlsl"
#include "Include/Util.hlsl"
#include "Include/settings.hlsl"
#include "Include/BloomCompute.hlsl"

// Bloom compute chain, stage 1/3 (this pass is otherwise unused): Karis-averaged 2x2 downsample
// of the final color, equivalent to the old RTXPostFX.Bloom BloomDownscaleUniformPass.
[numthreads(16, 16, 1)]
void CheckerboardInterleave(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex, 
    uint3 groupID : SV_GroupID
    )
{
    // Note that g_rootConstant0 from FinalCombine pass is accessible here
    uint2 fullRes = uint2(g_view.displayResolution);
    uint2 mip0Res = max(fullRes / 2, uint2(1, 1));
    uint2 pixelPos = dispatchThreadID.xy;
    if (any(pixelPos >= mip0Res)) return;

    float2 uv = (float2(pixelPos) + 0.5f) / float2(mip0Res);
    outputBufferPreInterleave[pixelPos] = float4(Downsample13TapKaris(outputBufferFinal, uv, fullRes, 1.0f), 1.0f);
}