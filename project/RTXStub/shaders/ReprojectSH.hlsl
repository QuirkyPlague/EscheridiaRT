#include "Include/Generated/Signature.hlsl"

[numthreads(16, 16, 1)]
void ReprojectSH(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex,
    uint3 groupID : SV_GroupID
)
{
    uint2 pixelPos = dispatchThreadID.xy;
    uint2 renderResUint = uint2(g_view.renderResolution.x, g_view.renderResolution.y);
    
    if (pixelPos.x >= renderResUint.x || pixelPos.y >= renderResUint.y) 
        return;

    // This is the fresh, noisy sample generated this frame by RayGen
    float4 currDiffuse = outputBufferIndirectDiffuse[pixelPos];
    
    // Handle background / infinite sky distance safely
    float currPathLength = inputBufferPrimaryPathLength[pixelPos];
    const float kMaxDistance = 65504.0;
    if (currPathLength >= kMaxDistance) {
        return; 
    }

    // Read local motion vectors to see if the scene or camera is moving
    float2 motionUv = inputBufferMotionVectors[pixelPos];
    
    // FIX FOR SIGN: Subtract motion vectors to trace backwards into history
    float2 motionPixels = motionUv * float2(g_view.renderResolution);
    float2 currentPixelCenter = float2(pixelPos) + 0.5f;
    float2 previousPixelPos = currentPixelCenter - motionPixels; // Changed to minus (-)
    int2 prevCoord = int2(floor(previousPixelPos));

    // Screen boundary check
    bool isMoving = (length(motionPixels) > 0.01f);
    bool outOfBounds = (prevCoord.x < 0 || prevCoord.y < 0 || prevCoord.x >= (int)renderResUint.x || prevCoord.y >= (int)renderResUint.y);

    // If it's the very first frame, or if things are moving drastically, drop history to avoid black ghosting
    if (g_view.frameCount == 0 || outOfBounds || isMoving) {
        // Do not accumulate; keep the raw frame sample pure
        outputBufferIndirectDiffuse[pixelPos] = currDiffuse;
        return;
    }

    // Safely retrieve the old frame's finalized accumulation image
    float3 prevDiffuse = previousDiffuseBuffer[pixelPos].rgb;

    // Fallback protection: If history completely decayed to zero/black erroneously, 
    // force-revive it with current frame illumination instead of multiplying down to pitch black
    if (dot(prevDiffuse, prevDiffuse) == 0.0f) {
        prevDiffuse = currDiffuse.rgb;
    }

    // Dynamically calculate the blending weight based on the global frame count
    uint accumulationSampleCount = g_view.frameCount + 1;
    float blendWeight = 0.04;

    // Blend the history with our brand new sample
    float3 blendedDiffuse = lerp(prevDiffuse, currDiffuse.rgb, blendWeight);

    // Overwrite the buffer with our pristine, accumulated, noise-reduced result
    outputBufferIndirectDiffuse[pixelPos] = float4(blendedDiffuse, 1.0f);
}
