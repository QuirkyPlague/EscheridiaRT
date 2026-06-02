#include "Include/Generated/Signature.hlsl"

[numthreads(128, 1, 1)]
void CalculateFaceData(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex, 
    uint3 groupID : SV_GroupID
    )
{
    uint faceQuadId = dispatchThreadID.x;
    uint objectInstanceIndex = g_rootConstant0;
    uint numOfQuadsInObject = g_rootConstant1;

    if (faceQuadId >= numOfQuadsInObject) return;
}