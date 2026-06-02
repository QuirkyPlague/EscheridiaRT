#include "Include/Generated/Signature.hlsl"

[numthreads(16, 16, 1)]
void BlurGIInscatter(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex, 
    uint3 groupID : SV_GroupID
    )
{
    // Used when selecting which buffer to choose from volumetricGIInscatterRW[] array
    uint volumetricGIInscatterBufferIndexFrom = 1-g_rootConstant0;
    uint volumetricGIInscatterBufferIndexTo = g_rootConstant0;
}