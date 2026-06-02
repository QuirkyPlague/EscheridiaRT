#include "Include/Generated/Signature.hlsl"

[numthreads(4, 8, 1)]
void AdaptiveDenoiserCalculateGradientsInline(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex, 
    uint3 groupID : SV_GroupID
    )
{
    uint denoisingBufferIndex = g_rootConstant0 & 0xff; // use when selecting buffer from denoisingOutputs[] or denoisingInputs[] array
}