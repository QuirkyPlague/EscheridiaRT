#include "Include/Generated/Signature.hlsl"

[numthreads(128, 1, 1)]
void BlurGradients(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex, 
    uint3 groupID : SV_GroupID
    )
{
    bool isVertical = (g_rootConstant0 >> 24) & 1;
    uint iteration = (g_rootConstant0 >> 16) & 0xff; // draw call index, 0-3

    // Use these values to index inputAdaptiveDenoiserGradients[] or outputAdaptiveDenoiserGradients[] arrays
    uint adaptiveDenoiserGradientsBufferFrom = g_rootConstant0 & 0xff;
    uint adaptiveDenoiserGradientsBufferTo = (g_rootConstant0 >> 8) & 0xff;
}