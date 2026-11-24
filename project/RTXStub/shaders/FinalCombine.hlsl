#include "Include/Generated/Signature.hlsl"
#include "Include/Util.hlsl"
#include "Include/settings.hlsl"
#include "Include/RayReconstruction.hlsl"


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

    uint2 pixelPos = dispatchThreadID.xy;

    // DLSS Ray Reconstruction (RayReconstruction.hlsl): handshake texels in the guard band.
    uint mode = rrMode();
    bool rrActive = mode != 0u; 
    if (all(pixelPos == 0)) {
        rrBeginFrame(mode);
        bufferIncidentLight[kWaterHistorySlot] = float4(
            g_view.time, g_view.waveWorksOriginInSteveSpace.xz,
            float(g_view.frameCount & 65535u));
    }
    if (rrIsReservedTexel(pixelPos, mode)) return;


    // The combined path-traced image is filtered into the selected denoising
    // output by SpecularFireflyFilter; accumulate that result, not its raw input.
    
    float3 currentSample = denoisingOutputs[specularDenoisingBufferIndex][pixelPos].rgb;


    //float3 currentSample = outputBufferIndirectDiffuse[pixelPos].rgb;
    float3 historyColor = 0.0;

    float finalAlpha = 0;
    if (pixelPos.x == 0) finalAlpha = g_view.rainLevel;


    // do not write to history color if offline rendering is disabled
    // this may be a potential optimization idk
    if (!rrActive)
    {   
        historyColor = outputBufferReferencePathTracer[pixelPos].rgb;
        uint historyLength = readAccumulationFrameIdx();

    #if DO_SAMPLE_LIMITS
    if (historyLength < MAX_ACCUMULATED_SAMPLES) {
        if (historyLength) {
            historyColor = lerp(historyColor, currentSample, 1./(historyLength+1));
        } else {
            // This doesn't let the NaNs and INFs persist between accumulations.
            historyColor = currentSample;
        }
    }
    #else
     if (historyLength) {
            historyColor = lerp(historyColor, currentSample, 1./(historyLength+1));
        } else {
            // This doesn't let the NaNs and INFs persist between accumulations.
            historyColor = currentSample;
        }
    #endif 

     outputBufferReferencePathTracer[pixelPos] = float4(historyColor, finalAlpha);
    }
      
    
        

    
 
	

   
    // if rr is active do not use the offline path tracing output. just use the current sample
    // At DLAA the RR marker is an image pixel: its alpha carries the code (RayReconstruction.hlsl).
    outputBufferFinal[pixelPos] = float4(rrActive ? rrPreExpose(currentSample) : historyColor, rrMarkerAlpha(pixelPos, mode, finalAlpha));
}
