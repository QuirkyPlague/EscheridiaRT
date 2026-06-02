#include "Include/Generated/Signature.hlsl"

[numthreads(16, 16, 1)]
void FilterMoments(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex, 
    uint3 groupID : SV_GroupID
    )
{
    // Indices for denoisingMomentsInputs[] or outputDenoisingMoments[] arrays
    uint denoisingMomentsInputBufferIndex = (g_rootConstant0 >> 16) & 0xff;
    uint denoisingMomentsOutputBufferIndex = (g_rootConstant0 >> 8) & 0xff;
    uint unknown = g_rootConstant0 & 0xff; // TODO: figure out.

    // Index for g_view.denoisingParams[];
    uint denoisingParamsIndex = (g_rootConstant0 >> 24) % 2;
    // Note the modulo. Sometimes game supplies index which goes out of array bounds.
}