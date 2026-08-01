#include "Include/Generated/Signature.hlsl"
#include "Include/Util.hlsl"

[numthreads(16, 16, 1)]
void ReprojectSH(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex,
    uint3 groupID : SV_GroupID
)
{
    uint diffuseOutputIndex = (g_rootConstant0 >> 8) & 0xff;
    uint specularOutputIndex = (g_rootConstant0 >> 16) & 0xff;
    bool useVarianceWeightDiffuse = g_rootConstant0 & 1;
    bool useVarianceWeightSpecular = g_rootConstant0 & 2;

    uint2 pixelPos = dispatchThreadID.xy;
    uint2 renderResUint = uint2(g_view.renderResolution.x, g_view.renderResolution.y);

    if (pixelPos.x >= renderResUint.x || pixelPos.y >= renderResUint.y)
        return;

    float4 currDiffuse = outputBufferIndirectDiffuse[pixelPos];

    float2 motionUv = inputBufferMotionVectors[pixelPos];
    float2 motionPixels = motionUv * float2(g_view.renderResolution);
    float motionMagnitude = length(motionPixels);

    float2 currentPixelCenter = float2(pixelPos) + 0.5f;
    float2 previousPixelPos = currentPixelCenter - motionPixels;
    int2 prevCoord = int2(floor(previousPixelPos));

    float3 prevDiffuse = float3(0.0f, 0.0f, 0.0f);
    float historyLength = 0.0f;
    bool hasValidHistory = false;

    uint accumulationFrameIdx = readAccumulationFrameIdx();
    float frameCount =  float(accumulationFrameIdx + 1u);

    
prevDiffuse = previousDiffuseBuffer[prevCoord].rgb;
   

    float3 blendedDiffuse = currDiffuse.rgb;
  
        float blendWeight = 1.0f / frameCount;
        blendedDiffuse = lerp(prevDiffuse, currDiffuse.rgb, blendWeight);
        historyLength = min(255.0f, frameCount);
 

   
  
}
