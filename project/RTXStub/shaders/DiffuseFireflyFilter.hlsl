#include "Include/Generated/Signature.hlsl"

[numthreads(16, 16, 1)]
void DiffuseFireflyFilter(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex, 
    uint3 groupID : SV_GroupID
    )
{
    // Use these for indexing denoisingOutputs[] or denoisingChromaAndVarianceOutputs[] arrays
    uint denoisingBufferIndexInput = g_rootConstant0 & 0xff;
    uint denoisingBufferIndexOutput = (g_rootConstant0 >> 8) & 0xff;
    uint unknown = (g_rootConstant0 >> 16) & 0xff; // TODO: figure out.

    // Index for g_view.denoisingParams[];
    uint denoisingParamsIndex = (g_rootConstant0 >> 24) % 2;
    // Note the modulo. Sometimes game supplies index which goes out of array bounds.
}