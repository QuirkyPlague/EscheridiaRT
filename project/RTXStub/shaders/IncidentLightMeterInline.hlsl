#include "Include/Generated/Signature.hlsl"

[numthreads(4, 4, 2)]
void IncidentLightMeterInline(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex, 
    uint3 groupID : SV_GroupID
    )
{
    uint threadsDispatchedX = g_rootConstant0 & 0xffff;
    uint threadsDispatchedY = g_rootConstant0 >> 16;

    // 1D index of each thread (not counting Z)
    uint threadId = (threadsDispatchedX * dispatchThreadID.y) + dispatchThreadID.x;
}