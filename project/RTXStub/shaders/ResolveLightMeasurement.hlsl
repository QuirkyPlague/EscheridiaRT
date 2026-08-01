#include "Include/Generated/Signature.hlsl"
#include "Include/Util.hlsl"

[numthreads(1, 1, 1)]
void ResolveLightMeasurement(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex, 
    uint3 groupID : SV_GroupID
    )
{
       // Advance frame counter and compute average fps
    uint historyLength = readAccumulationFrameIdx()+1;
    float fps = 1./(g_view.time-readLastFrameTimestamp());

    bool resetAccumulation = g_view.genericDebugSlider0 || any((float3x3)g_view.viewProj != (float3x3)g_view.prevViewProj) || any(g_view.steveSpaceDelta != 0);
    if (resetAccumulation) {
        historyLength = 0;
        storeAccumulationStartTimestamp(g_view.time);
    } else { 
        fps = lerp(readAverageFps(), fps, 0.01);
    }
    
    storeAverageFps(fps);
    storeLastFrameTimestamp(g_view.time);
    storeAccumulationFrameIdx(historyLength);
}
