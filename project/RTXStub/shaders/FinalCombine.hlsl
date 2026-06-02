#include "Include/Generated/Signature.hlsl"

[numthreads(16, 16, 1)]
void FinalCombine(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex, 
    uint3 groupID : SV_GroupID
    )
{
    // Use these for indexing denoisingOutputs[] (diffuse or specular) or denoisingChromaAndVarianceOutputs[] (only diffuse) arrays
    uint diffuseDenoisingBufferIndex = g_rootConstant0 & 0xff;
    uint specularDenoisingBufferIndex = (g_rootConstant0 >> 8) & 0xff;

    // Use for indexing shadowDenoisingInputs[] or shadowDenoisingOutputs[] arrays
    uint shadowDenoisingBufferIndex = (g_rootConstant0 >> 16) & 0xff;
}