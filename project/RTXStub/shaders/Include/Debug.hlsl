/* MIT License
 * 
 * Copyright (c) 2025 veka0
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#ifndef __DEBUG_HLSL__
#define __DEBUG_HLSL__

#include "Generated/Signature.hlsl"

template<typename T>
float SampleBuffer(RWTexture2D<T> tex) { return (float)tex[uint2(0,0)]; }
template<typename T>
float SampleBuffer(RWTexture3D<T> tex) { return (float)tex[uint3(0,0,0)]; }
template<typename T>
float SampleBuffer(Texture2D<T> tex) { return (float)tex[uint2(0,0)]; }
template<typename T>
float SampleBuffer(Texture3D<T> tex) { return (float)tex[uint3(0,0,0)]; }
template<typename T>
float SampleBuffer(StructuredBuffer<T> tex) { return (float)tex[0]; }
template<typename T>
float SampleBuffer(RWStructuredBuffer<T> tex) { return (float)tex[0]; }
template<typename T>
float SampleBuffer(Texture2DArray<T> tex) { return (float)tex[uint3(0,0,0)]; }

// Use this for debugging buffer resolutions and formats with PIX.
void SimulateBufferReads() {
    // Always-true runtime condition.
    if (g_view.time != -1) return;

    float val = 0;

    // TODO: implement a better templating system with embedded scripting, so that this can be generated automatically.
    val += SampleBuffer(outputBufferPrimaryPathLength);
    val += SampleBuffer(outputBufferNormal);
    val += SampleBuffer(outputBufferHistoryLength);
    val += SampleBuffer(outputBufferColourAndMetallic);
    val += SampleBuffer(outputBufferEmissiveAndLinearRoughness);
    val += SampleBuffer(outputBufferIndirectDiffuse);
    val += SampleBuffer(outputBufferIndirectSpecular);
    val += SampleBuffer(outputBufferSurfaceOpacityAndObjectCategory);
    val += SampleBuffer(outputBufferMotionVectors);
    val += SampleBuffer(outputBufferIncomingIrradianceCache);
    val += SampleBuffer(outputBufferFinal);
    val += SampleBuffer(outputBufferDirectLightTransmission);
    val += SampleBuffer(outputBufferDebug);
    val += SampleBuffer(outputBufferReflectionDistance);
    val += SampleBuffer(outputBufferReflectionMotionVectors);
    val += SampleBuffer(outputBufferPreviousLinearRoughness);
    val += SampleBuffer(outputBufferPreInterleave);
    val += SampleBuffer(outputPlaneIdentifier);
    val += SampleBuffer(outputBufferReprojectedPathLength);
    val += SampleBuffer(outputBufferSunLightShadow);
    val += SampleBuffer(outputBufferPreviousSunLightShadow);
    val += SampleBuffer(outputBufferReferencePathTracer);
    val += SampleBuffer(outputBufferRayDirection);
    val += SampleBuffer(outputBufferRayThroughput);
    val += SampleBuffer(outputBufferToneMappingHistogram);
    val += SampleBuffer(outputBufferToneCurve);
    val += SampleBuffer(outputBufferIndirectDiffuseChroma);
    val += SampleBuffer(outputBufferPrimaryPosLowPrecision);
    val += SampleBuffer(outputBufferTAAHistory);
    val += SampleBuffer(outputGeometryNormal);
    val += SampleBuffer(outputVisibleBLASs);
    val += SampleBuffer(outputPrimaryWorldPosition);
    val += SampleBuffer(outputPrimaryViewDirection);
    val += SampleBuffer(outputPrimaryThroughput);
    val += SampleBuffer(outputAdaptiveDenoiserGradients[0]);
    val += SampleBuffer(outputAdaptiveDenoiserGradients[1]);
    val += SampleBuffer(outputAdaptiveDenoiserReference);
    val += SampleBuffer(outputAdaptiveDenoiserPlaneIdentifier);
    val += SampleBuffer(outputBufferDiffuseMoments);
    val += SampleBuffer(outputFinalDiffuseMoments);
    val += SampleBuffer(outputBufferSpecularMoments);
    val += SampleBuffer(outputFinalSpecularMoments);
    val += SampleBuffer(outputTileClassification);
    val += SampleBuffer(outputBufferPreviousMedium);
    val += SampleBuffer(objectInstances);
    val += SampleBuffer(vertexIrradianceCacheUpdateChunks);
    val += SampleBuffer(faceIrradianceCacheUpdateChunks);
    val += SampleBuffer(previousPrimaryPathLengthBuffer);
    val += SampleBuffer(previousPrimaryNormalBuffer);
    val += SampleBuffer(previousHistoryLengthBuffer);
    val += SampleBuffer(previousDiffuseBuffer);
    val += SampleBuffer(previousSpecularBuffer);
    val += SampleBuffer(inputBufferOrFinalDiffuseMoments);
    val += SampleBuffer(inputBufferOrFinalSpecularMoments);
    val += SampleBuffer(volumetricResolvedInscatter);
    val += SampleBuffer(volumetricResolvedTransmission);
    val += SampleBuffer(volumetricInscatterPrevious);
    val += SampleBuffer(inputBufferPrimaryPathLength);
    val += SampleBuffer(inputBufferNormal);
    val += SampleBuffer(inputBufferColourAndMetallic);
    val += SampleBuffer(inputBufferSurfaceOpacityAndObjectCategory);
    val += SampleBuffer(inputBufferIncomingIrradianceCache);
    val += SampleBuffer(inputIncidentLight);
    val += SampleBuffer(inputDirectLightTransmission);
    val += SampleBuffer(inputBufferMotionVectors);
    val += SampleBuffer(inputBufferReflectionMotionVectors);
    val += SampleBuffer(previousReflectionDistanceBuffer);
    val += SampleBuffer(previousLinearRoughnessBuffer);
    val += SampleBuffer(inputBufferPreInterleaveCurrent);
    val += SampleBuffer(inputBufferPreInterleavePrevious);
    val += SampleBuffer(inputPlaneIdentifier);
    val += SampleBuffer(inputBufferReprojectedPathLength);
    val += SampleBuffer(previousSunLightShadowBuffer);
    val += SampleBuffer(referencePathTracerBuffer);
    val += SampleBuffer(pbrTextureDataBuffer);
    val += SampleBuffer(inputBufferToneMappingHistogram);
    val += SampleBuffer(inputBufferToneCurve);
    val += SampleBuffer(volumetricGIResolvedInscatter);
    val += SampleBuffer(volumetricGIInscatterPrevious);
    val += SampleBuffer(inputTAAHistory);
    val += SampleBuffer(inputThisFrameTAAHistory);
    val += SampleBuffer(inputFinalColour);
    val += SampleBuffer(inputGeometryNormal);
    val += SampleBuffer(inputEmissiveAndLinearRoughness);
    val += SampleBuffer(inputPrimaryWorldPosition);
    val += SampleBuffer(inputPrimaryViewDirection);
    val += SampleBuffer(inputPrimaryThroughput);
    val += SampleBuffer(previousDiffuseChromaBuffer);
    val += SampleBuffer(inputPreviousGeometryNormal);
    val += SampleBuffer(inputPrimaryPosLowPrecision);
    val += SampleBuffer(inputAdaptiveDenoiserGradients[0]);
    val += SampleBuffer(inputAdaptiveDenoiserGradients[1]);
    val += SampleBuffer(inputAdaptiveDenoiserReference);
    val += SampleBuffer(inputAdaptiveDenoiserPlaneIdentifier);
    val += SampleBuffer(checkerboardActionsBuffer);
    val += SampleBuffer(refractionIndicesBuffer);
    val += SampleBuffer(inputTileClassification);
    val += SampleBuffer(blueNoiseTexture);
    val += SampleBuffer(skyTexture);
    val += SampleBuffer(causticsTexture);
    val += SampleBuffer(wibblyTexture);
    val += SampleBuffer(waterNormalsTexture);
    val += SampleBuffer(inputBufferPreviousMedium);
    val += SampleBuffer(bufferIncidentLight);
    val += SampleBuffer(volumetricResolvedInscatterRW);
    val += SampleBuffer(volumetricResolvedTransmissionRW);
    val += SampleBuffer(volumetricInscatterRW);
    val += SampleBuffer(volumetricGIResolvedInscatterRW);
    val += SampleBuffer(volumetricGIInscatterRW[0]);
    val += SampleBuffer(volumetricGIInscatterRW[1]);
    val += SampleBuffer(denoisingInputs[0]);
    val += SampleBuffer(denoisingInputs[1]);
    val += SampleBuffer(denoisingInputs[2]);
    val += SampleBuffer(denoisingInputs[3]);
    val += SampleBuffer(denoisingInputs[4]);
    val += SampleBuffer(denoisingInputs[5]);
    val += SampleBuffer(denoisingInputs[6]);
    val += SampleBuffer(denoisingInputs[7]);
    val += SampleBuffer(denoisingChromaAndVarianceInputs[0]);
    val += SampleBuffer(denoisingChromaAndVarianceInputs[1]);
    val += SampleBuffer(denoisingChromaAndVarianceInputs[2]);
    val += SampleBuffer(denoisingChromaAndVarianceInputs[3]);
    val += SampleBuffer(denoisingOutputs[0]);
    val += SampleBuffer(denoisingOutputs[1]);
    val += SampleBuffer(denoisingOutputs[2]);
    val += SampleBuffer(denoisingOutputs[3]);
    val += SampleBuffer(denoisingOutputs[4]);
    val += SampleBuffer(denoisingOutputs[5]);
    val += SampleBuffer(denoisingOutputs[6]);
    val += SampleBuffer(denoisingOutputs[7]);
    val += SampleBuffer(denoisingChromaAndVarianceOutputs[0]);
    val += SampleBuffer(denoisingChromaAndVarianceOutputs[1]);
    val += SampleBuffer(denoisingChromaAndVarianceOutputs[2]);
    val += SampleBuffer(denoisingChromaAndVarianceOutputs[3]);
    val += SampleBuffer(inputBufferDiffuseMoments);
    val += SampleBuffer(inputFinalDiffuseMoments);
    val += SampleBuffer(inputBufferSpecularMoments);
    val += SampleBuffer(inputFinalSpecularMoments);
    val += SampleBuffer(shadowDenoisingInputs[0]);
    val += SampleBuffer(shadowDenoisingInputs[1]);
    val += SampleBuffer(shadowDenoisingOutputs[0]);
    val += SampleBuffer(shadowDenoisingOutputs[1]);
    val += SampleBuffer(outputLightsBuffer);
    val += SampleBuffer(outputReducedLightsBuffer);
    val += SampleBuffer(inputLightsBuffer);
    val += SampleBuffer(inputReducedLightsBuffer);
    val += SampleBuffer(inputTemporallyStableLights);

    // This actually never runs.
    outputBufferFinal[uint2(0,0)] = val;
}
#endif