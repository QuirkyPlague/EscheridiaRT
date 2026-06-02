#include "Include/Generated/Signature.hlsl"

[numthreads(128, 1, 1)]
void ClearFaceIrradianceCache(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex, 
    uint3 groupID : SV_GroupID
    )
{
    uint vertexBufferIndex = g_rootConstant0 & 0xfff; // equal to ObjectInstance.vbIdx
    uint numOfFaces = g_rootConstant0 >> 12;
    uint firstFaceOffset = g_rootConstant1;
    uint faceIndex = dispatchThreadID.x;

    if(faceIndex >= numOfFaces) return;
    faceIndex += firstFaceOffset;
}