#include "Include/Generated/Signature.hlsl"

[numthreads(16, 8, 1)]
void AtrousSH(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex, 
    uint3 groupID : SV_GroupID
    )
{
    // Use these for indexing denoisingOutputs[] or denoisingChromaAndVarianceOutputs[] arrays
    uint denoisingBufferIndexInput = g_rootConstant0 & 0xff;
    uint denoisingBufferIndexOutput = (g_rootConstant0 >> 8) & 0xff;
    uint iteration = (g_rootConstant0 >> 16) & 0xff; // Goes from 0 to 5.
    bool useVarianceWeight = (g_rootConstant0 >> 26) & 1;
    
    // Index for g_view.denoisingParams[];
    uint denoisingParamsIndex = (g_rootConstant0 >> 24) % 2;
    // Note the modulo. Sometimes game supplies index which goes out of array bounds.
}