#include "Include/Generated/Signature.hlsl"

[numthreads(16, 16, 1)]
void Reproject(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex, 
    uint3 groupID : SV_GroupID
    )
{
   
    uint diffuseOutputIndex = (g_rootConstant0 >> 8) & 0xff;
    uint specularOutputIndex = (g_rootConstant0 >> 16) & 0xff;

    uint2 pixelPos = dispatchThreadID.xy;
    uint2 renderResUint = uint2(g_view.renderResolution.x, g_view.renderResolution.y);
    if (pixelPos.x >= renderResUint.x || pixelPos.y >= renderResUint.y)
        return;


    float4 currDiffuse  = outputBufferIndirectDiffuse[pixelPos];
    // float4 currSpecular = outputBufferIndirectSpecular[pixelPos]; 

    uint currentFrame = g_view.frameCount + 1; 

    // Handle background / infinite sky distance 
    float currPathLength = inputBufferPrimaryPathLength[pixelPos];
    const float kMaxDistance = 65504.0;
    if (currPathLength >= kMaxDistance)
    {
        outputBufferIndirectDiffuse[pixelPos] = currDiffuse;
        return;
    }

    if (g_view.frameCount == 0)
{
   
    outputBufferIndirectDiffuse[pixelPos] = currDiffuse;
}
else
{

    float4 prevDiffuse = previousDiffuseBuffer[pixelPos];


    float blendWeight = 1.0f / (float)currentFrame;
    float3 blendedDiffuse = lerp(prevDiffuse.rgb, currDiffuse.rgb, blendWeight);

   
    outputBufferIndirectDiffuse[pixelPos] = float4(blendedDiffuse, 1.0f);
}
}
