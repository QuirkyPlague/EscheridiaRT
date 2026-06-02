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

#ifndef __SIGNATURE_HLSL__
#define __SIGNATURE_HLSL__

#include "Structs.hlsl"

// The contents of this file were partially generated using process_signature.py
// while manually filling in uninitialized or missing buffers.

// Buffer types and resolutions were manually added from a PIX capture (see Debug.hlsl)

// Note that float3 buffers are often stored as float4
// so you can change their type to get an extra channel for storage.

// For the most part, every single buffer here is accessible in every single pass.
// The only exception is PreBlasSkinningCB buffer which is only accessible in PreBlasSkinning pass
// and that same pass only has access to PreBlasSkinningCB and a single descriptor table
// with the following buffers: indexBuffers, vertexBuffers, faceDataBuffers, faceUvBuffers, 
// vertexIrradianceCache, faceIrradianceCache, faceDataBuffersRW, faceUvBuffersRW, vertexBuffersRW

// 32BIT_CONSTANTS
cbuffer RootConstants : register(b2) {
    uint g_rootConstant0; // 0
    uint g_rootConstant1; // 4
    uint g_dispatchDimensions; // 8
};

// CBV
cbuffer PreBlasSkinningCB : register(b0, space99) {
    MeshSkinningData g_meshSkinningData; // 0
};

// DESCRIPTOR_TABLE [13]
// CBV[1]
cbuffer ViewCB : register(b0) {
    View g_view; // 0
};

// CBV[1]
cbuffer LightMeterDataCB : register(b3) {
    LightMeterData g_lightMeterSamples; // 0
};

// Buffer resolution legend:
// DISPLAY - game window resolution
// RENDER - internal rendering resolution (equal to DISPLAY if upscaling is disabled)
// DENOISER, 1px = 4x4 RENDER pixels
// TILE, 1px = 16x16 RENDER pixels

// UAV[46]
RWTexture2D<float> outputBufferPrimaryPathLength : register(u0); // R32_FLOAT RENDER
RWTexture2D<float2> outputBufferNormal : register(u1); // R16G16_SNORM RENDER
RWTexture2D<float2> outputBufferHistoryLength : register(u2); // R8G8_UNORM RENDER
RWTexture2D<float4> outputBufferColourAndMetallic : register(u3); // R8G8B8A8_UNORM RENDER
RWTexture2D<float4> outputBufferEmissiveAndLinearRoughness : register(u4); // R16G16B16A16_FLOAT RENDER
RWTexture2D<float4> outputBufferIndirectDiffuse : register(u5); // R16G16B16A16_FLOAT RENDER
RWTexture2D<float4> outputBufferIndirectSpecular : register(u6); // R16G16B16A16_FLOAT RENDER
RWTexture2D<float2> outputBufferSurfaceOpacityAndObjectCategory : register(u7); // R8G8_UNORM RENDER
// Uninitialized // {{RTXStub.buffers.u8_space0}}
// Uninitialized // {{RTXStub.buffers.u9_space0}}
RWTexture2D<float2> outputBufferMotionVectors : register(u10); // R16G16_FLOAT RENDER
RWTexture2D<float4> outputBufferIncomingIrradianceCache : register(u11); // R16G16B16A16_FLOAT RENDER
RWTexture2D<float4> outputBufferFinal : register(u12); // R16G16B16A16_FLOAT DISPLAY
RWTexture2D<float3> outputBufferDirectLightTransmission : register(u13); // {{RTXStub.buffers.u13_space0}} // R8G8B8A8_UNORM RENDER
RWTexture2D<float4> outputBufferDebug : register(u14); // R8G8B8A8_UNORM RENDER
RWTexture2D<float> outputBufferReflectionDistance : register(u15); // R16_FLOAT RENDER
RWTexture2D<float2> outputBufferReflectionMotionVectors : register(u16); // R16G16_FLOAT RENDER
RWTexture2D<float> outputBufferPreviousLinearRoughness : register(u17); // R8_UNORM RENDER
RWTexture2D<float4> outputBufferPreInterleave : register(u18); // R16G16B16A16_FLOAT RENDER
RWTexture2D<int> outputPlaneIdentifier : register(u19); // R32_UINT RENDER
RWTexture2D<float> outputBufferReprojectedPathLength : register(u20); // R32_FLOAT RENDER
RWTexture2D<float4> outputBufferSunLightShadow : register(u21); // R16G16B16A16_FLOAT RENDER
RWTexture2D<float4> outputBufferPreviousSunLightShadow : register(u22); // R16G16B16A16_FLOAT RENDER
RWTexture2D<float4> outputBufferReferencePathTracer : register(u23); // R32G32B32A32_FLOAT RENDER
RWTexture2D<float4> outputBufferRayDirection : register(u24); // {{RTXStub.buffers.u24_space0}} // R16G16B16A16_FLOAT RENDER
RWTexture2D<float3> outputBufferRayThroughput : register(u25); // {{RTXStub.buffers.u25_space0}} // R11G11B10_FLOAT RENDER
RWTexture2D<uint> outputBufferToneMappingHistogram : register(u26); // R32_UINT 256⨯1
RWTexture2D<float> outputBufferToneCurve : register(u27); // R32_FLOAT 256⨯1
RWTexture2D<float3> outputBufferIndirectDiffuseChroma : register(u28); // R16G16B16A16_FLOAT RENDER
RWTexture2D<float4> outputBufferPrimaryPosLowPrecision : register(u29); // R16G16B16A16_FLOAT RENDER
RWTexture2D<float4> outputBufferTAAHistory : register(u30); // R16G16B16A16_FLOAT DISPLAY
RWTexture2D<float2> outputGeometryNormal : register(u31); // R8G8_SNORM RENDER
RWStructuredBuffer<uint> outputVisibleBLASs : register(u32); // 32768
RWTexture2D<float4> outputPrimaryWorldPosition : register(u33); // R32G32B32A32_FLOAT RENDER
RWTexture2D<float4> outputPrimaryViewDirection : register(u34); // R16G16B16A16_FLOAT RENDER
RWTexture2D<float4> outputPrimaryThroughput : register(u35); // R16G16B16A16_FLOAT RENDER
RWTexture2D<float2> outputAdaptiveDenoiserGradients[2] : register(u36); // R16G16_FLOAT DENOISER
// outputAdaptiveDenoiserGradients #1 // {{RTXStub.buffers.u37_space0}} // R16G16_FLOAT DENOISER
RWTexture2D<float2> outputAdaptiveDenoiserReference : register(u38); // R16G16_FLOAT DENOISER
RWTexture2D<int> outputAdaptiveDenoiserPlaneIdentifier : register(u39); // R32_UINT DENOISER
RWTexture2D<float2> outputBufferDiffuseMoments : register(u40);RWTexture2D<float2> outputDenoisingMoments[4] : register(u40); // R16G16_FLOAT RENDER
RWTexture2D<float2> outputFinalDiffuseMoments : register(u41); // {{RTXStub.buffers.u41_space0}} // R16G16_FLOAT RENDER
RWTexture2D<float2> outputBufferSpecularMoments : register(u42); // R16G16_FLOAT RENDER
RWTexture2D<float2> outputFinalSpecularMoments : register(u43);  // {{RTXStub.buffers.u43_space0}} // R16G16_FLOAT RENDER
RWTexture2D<int> outputTileClassification : register(u44); // R32_UINT TILE
RWTexture2D<int> outputBufferPreviousMedium : register(u45); // R32_UINT RENDER

// SRV[64]
RaytracingAccelerationStructure SceneBVH : register(t0);
StructuredBuffer<ObjectInstance> objectInstances : register(t1); // 16384
StructuredBuffer<VertexIrradianceCacheUpdateChunk> vertexIrradianceCacheUpdateChunks : register(t2); // 2048
StructuredBuffer<FaceIrradianceCacheUpdateChunk> faceIrradianceCacheUpdateChunks : register(t3); // 2048
Texture2D<float> previousPrimaryPathLengthBuffer : register(t4); // R32_FLOAT RENDER
Texture2D<float2> previousPrimaryNormalBuffer : register(t5); // R16G16_SNORM RENDER
Texture2D<float2> previousHistoryLengthBuffer : register(t6); // R8G8_UNORM RENDER
Texture2D<float4> previousDiffuseBuffer : register(t7); // R16G16B16A16_FLOAT RENDER
Texture2D<float3> previousSpecularBuffer : register(t8); // R16G16B16A16_FLOAT RENDER
Texture2D<float2> inputBufferOrFinalDiffuseMoments : register(t9); // {{RTXStub.buffers.t9_space0}} // R16G16_FLOAT RENDER
Texture2D<float2> inputBufferOrFinalSpecularMoments : register(t10); // {{RTXStub.buffers.t10_space0}} // R16G16_FLOAT RENDER
Texture3D<float3> volumetricResolvedInscatter : register(t11); // R16G16B16A16_FLOAT 256⨯128x64
Texture3D<float3> volumetricResolvedTransmission : register(t12); // R16G16B16A16_FLOAT 256⨯128x64
Texture3D<float4> volumetricInscatterPrevious : register(t13); // R16G16B16A16_FLOAT 256⨯128x64
Texture2D<float> inputBufferPrimaryPathLength : register(t14); // R32_FLOAT RENDER
Texture2D<float2> inputBufferNormal : register(t15); // R16G16_SNORM RENDER
Texture2D<float4> inputBufferColourAndMetallic : register(t16); // R8G8B8A8_UNORM RENDER
Texture2D<float2> inputBufferSurfaceOpacityAndObjectCategory : register(t17); // R8G8_UNORM RENDER
Texture2D<float4> inputBufferIncomingIrradianceCache : register(t18); // R16G16B16A16_FLOAT RENDER
StructuredBuffer<float4> inputIncidentLight : register(t19); // 515
Texture2D<float3> inputDirectLightTransmission : register(t20); // {{RTXStub.buffers.t20_space0}} // R8G8B8A8_UNORM RENDER
Texture2D<float2> inputBufferMotionVectors : register(t21); // R16G16_FLOAT RENDER
Texture2D<float2> inputBufferReflectionMotionVectors : register(t22); // R16G16_FLOAT RENDER
Texture2D<float> previousReflectionDistanceBuffer : register(t23); // R16_FLOAT RENDER
Texture2D<float> previousLinearRoughnessBuffer : register(t24); // R8_UNORM RENDER
Texture2D<float4> inputBufferPreInterleaveCurrent : register(t25); // R16G16B16A16_FLOAT RENDER
Texture2D<float4> inputBufferPreInterleavePrevious : register(t26); // R16G16B16A16_FLOAT RENDER
Texture2D<int> inputPlaneIdentifier : register(t27); // R32_UINT RENDER
// Uninitialized // {{RTXStub.buffers.t28_space0}}
Texture2D<float> inputBufferReprojectedPathLength : register(t29); // R32_FLOAT RENDER
Texture2D<float4> previousSunLightShadowBuffer : register(t30); // R16G16B16A16_FLOAT RENDER
Texture2D<float4> referencePathTracerBuffer : register(t31); // {{RTXStub.buffers.t31_space0}} // R32G32B32A32_FLOAT RENDER
// Uninitialized // {{RTXStub.buffers.t32_space0}}
// Uninitialized // {{RTXStub.buffers.t33_space0}}
// Uninitialized // {{RTXStub.buffers.t34_space0}}
StructuredBuffer<PBRTextureData> pbrTextureDataBuffer : register(t35); // 12288
Texture2D<uint> inputBufferToneMappingHistogram : register(t36); // {{RTXStub.buffers.t36_space0}} // R32_UINT 256⨯1
Texture2D<float> inputBufferToneCurve : register(t37); // {{RTXStub.buffers.t37_space0}} // R32_FLOAT 256⨯1
Texture3D<float3> volumetricGIResolvedInscatter : register(t38); // R16G16B16A16_FLOAT 128⨯64x32
Texture3D<float4> volumetricGIInscatterPrevious : register(t39); // R16G16B16A16_FLOAT 128⨯64x32
Texture2D<float4> inputTAAHistory : register(t40); // R16G16B16A16_FLOAT DISPLAY
Texture2D<float4> inputThisFrameTAAHistory : register(t41); // R16G16B16A16_FLOAT DISPLAY
Texture2D<float4> inputFinalColour : register(t42); // R16G16B16A16_FLOAT DISPLAY
Texture2D<float2> inputGeometryNormal : register(t43); // R8G8_SNORM RENDER
Texture2D<float4> inputEmissiveAndLinearRoughness : register(t44); // R16G16B16A16_FLOAT RENDER
Texture2D<float4> inputPrimaryWorldPosition : register(t45); // R32G32B32A32_FLOAT RENDER
Texture2D<float4> inputPrimaryViewDirection : register(t46); // R16G16B16A16_FLOAT RENDER
Texture2D<float4> inputPrimaryThroughput : register(t47); // R16G16B16A16_FLOAT RENDER
Texture2D<float3> previousDiffuseChromaBuffer : register(t48); // R16G16B16A16_FLOAT RENDER
Texture2D<float2> inputPreviousGeometryNormal : register(t49); // R8G8_SNORM RENDER
Texture2D<float4> inputPrimaryPosLowPrecision : register(t50); // R16G16B16A16_FLOAT RENDER
Texture2D<float2> inputAdaptiveDenoiserGradients[2] : register(t51); // R16G16_FLOAT DENOISER
// inputAdaptiveDenoiserGradients #1 // {{RTXStub.buffers.t52_space0}} // R16G16_FLOAT DENOISER
Texture2D<float2> inputAdaptiveDenoiserReference : register(t53); // R16G16_FLOAT DENOISER
Texture2D<int> inputAdaptiveDenoiserPlaneIdentifier : register(t54); // R32_UINT DENOISER
StructuredBuffer<CheckerboardActions> checkerboardActionsBuffer : register(t55); // 20
StructuredBuffer<float> refractionIndicesBuffer : register(t56); // 5
Texture2D<int> inputTileClassification : register(t57); // R32_UINT TILE
Texture2DArray<float4> blueNoiseTexture : register(t58); // R16G16B16A16_UNORM 256⨯256[128]
Texture2DArray<float3> skyTexture : register(t59); // R8G8B8A8_UNORM 64⨯32[8]
Texture2DArray<float> causticsTexture : register(t60); // R8_UNORM 256⨯256[64]
Texture2D<float2> wibblyTexture : register(t61); // R8G8B8A8_UNORM 128⨯128
Texture2D<float4> waterNormalsTexture : register(t62); // R8G8B8A8_UNORM 256⨯256
Texture2D<int> inputBufferPreviousMedium : register(t63); // R32_UINT RENDER

// UAV[1]
RWStructuredBuffer<float4> bufferIncidentLight : register(u0, space14); // 515

// UAV[6]
RWTexture3D<float3> volumetricResolvedInscatterRW : register(u60); // R16G16B16A16_FLOAT 256⨯128x64
RWTexture3D<float3> volumetricResolvedTransmissionRW : register(u61); // R16G16B16A16_FLOAT 256⨯128x64
RWTexture3D<float4> volumetricInscatterRW : register(u62); // R16G16B16A16_FLOAT 256⨯128x64
RWTexture3D<float3> volumetricGIResolvedInscatterRW : register(u63); // R16G16B16A16_FLOAT 128⨯64x32
RWTexture3D<float4> volumetricGIInscatterRW[2] : register(u64); // R16G16B16A16_FLOAT 128⨯64x32
// volumetricGIInscatterRW #1 // {{RTXStub.buffers.u65_space0}} // R16G16B16A16_FLOAT 128⨯64x32

// SRV[12]
Texture2D<float4> denoisingInputs[8] : register(t0, space8); // {{RTXStub.buffers.t0_space8}} // R16G16B16A16_FLOAT RENDER
// denoisingInputs #1 // {{RTXStub.buffers.t1_space8}} // R16G16B16A16_FLOAT RENDER
// denoisingInputs #2 // {{RTXStub.buffers.t2_space8}} // R16G16B16A16_FLOAT RENDER
// denoisingInputs #3 // {{RTXStub.buffers.t3_space8}} // R16G16B16A16_FLOAT RENDER
// denoisingInputs #4 // {{RTXStub.buffers.t4_space8}} // R16G16B16A16_FLOAT RENDER
// denoisingInputs #5 // {{RTXStub.buffers.t5_space8}} // R16G16B16A16_FLOAT RENDER
// denoisingInputs #6 // {{RTXStub.buffers.t6_space8}} // R16G16B16A16_FLOAT RENDER
// denoisingInputs #7 // {{RTXStub.buffers.t7_space8}} // R16G16B16A16_FLOAT RENDER
Texture2D<float4> denoisingChromaAndVarianceInputs[4] : register(t8, space8); // {{RTXStub.buffers.t8_space8}} // R16G16B16A16_FLOAT RENDER
// denoisingChromaAndVarianceInputs #1 // {{RTXStub.buffers.t9_space8}} // R16G16B16A16_FLOAT RENDER
// denoisingChromaAndVarianceInputs #2 // {{RTXStub.buffers.t10_space8}} // R16G16B16A16_FLOAT RENDER
// denoisingChromaAndVarianceInputs #3 // {{RTXStub.buffers.t11_space8}} // R16G16B16A16_FLOAT RENDER

// UAV[12]
RWTexture2D<float4> denoisingOutputs[8] : register(u0, space3); // R16G16B16A16_FLOAT RENDER
// denoisingOutputs #1 // {{RTXStub.buffers.u1_space3}} // R16G16B16A16_FLOAT RENDER
// denoisingOutputs #2 // {{RTXStub.buffers.u2_space3}} // R16G16B16A16_FLOAT RENDER
// denoisingOutputs #3 // {{RTXStub.buffers.u3_space3}} // R16G16B16A16_FLOAT RENDER
// denoisingOutputs #4 // {{RTXStub.buffers.u4_space3}} // R16G16B16A16_FLOAT RENDER
// denoisingOutputs #5 // {{RTXStub.buffers.u5_space3}} // R16G16B16A16_FLOAT RENDER
// denoisingOutputs #6 // {{RTXStub.buffers.u6_space3}} // R16G16B16A16_FLOAT RENDER
// denoisingOutputs #7 // {{RTXStub.buffers.u7_space3}} // R16G16B16A16_FLOAT RENDER
RWTexture2D<float4> denoisingChromaAndVarianceOutputs[4] : register(u8, space3); // R16G16B16A16_FLOAT RENDER
// denoisingChromaAndVarianceOutputs #1 // {{RTXStub.buffers.u9_space3}} // R16G16B16A16_FLOAT RENDER
// denoisingChromaAndVarianceOutputs #2 // {{RTXStub.buffers.u10_space3}} // R16G16B16A16_FLOAT RENDER
// denoisingChromaAndVarianceOutputs #3 // {{RTXStub.buffers.u11_space3}} // R16G16B16A16_FLOAT RENDER

// SRV[4]
Texture2D<float2> inputBufferDiffuseMoments : register(t0, space9); Texture2D<float2> denoisingMomentsInputs[4] : register(t0, space9); // {{RTXStub.buffers.t0_space9}} // R16G16_FLOAT RENDER
Texture2D<float2> inputFinalDiffuseMoments : register(t1, space9); // R16G16_FLOAT RENDER
Texture2D<float2> inputBufferSpecularMoments : register(t2, space9); // {{RTXStub.buffers.t2_space9}} // R16G16_FLOAT RENDER
Texture2D<float2> inputFinalSpecularMoments : register(t3, space9); // R16G16_FLOAT RENDER

// SRV[2]
Texture2D<float4> shadowDenoisingInputs[2] : register(t0, space4); // R16G16B16A16_FLOAT RENDER
// shadowDenoisingInputs #1 // {{RTXStub.buffers.t1_space4}} // R16G16B16A16_FLOAT RENDER

// UAV[2]
RWTexture2D<float4> shadowDenoisingOutputs[2] : register(u0, space4); // R16G16B16A16_FLOAT RENDER
// shadowDenoisingOutputs #1 {{RTXStub.buffers.u1_space4}} // R16G16B16A16_FLOAT RENDER

// UAV[2]
RWStructuredBuffer<LightInfo> outputLightsBuffer : register(u0, space13); // {{RTXStub.buffers.u0_space13}} // 98304
RWStructuredBuffer<LightInfo> outputReducedLightsBuffer : register(u1, space13); // {{RTXStub.buffers.u1_space13}} // 4096

// SRV[3]
StructuredBuffer<LightInfo> inputLightsBuffer : register(t0, space13); // 98304
StructuredBuffer<LightInfo> inputReducedLightsBuffer : register(t1, space13); // 4096
StructuredBuffer<AdaptiveDenoiserLightInfo> inputTemporallyStableLights : register(t2, space13); // 32

// DESCRIPTOR_TABLE [9]
// SRV[4096]
Buffer<uint16_t> indexBuffers[4096] : register(t0, space1); // {{RTXStub.buffers.t0_space1}} // 4096

// SRV[4096]
ByteAddressBuffer vertexBuffers[4096] : register(t0, space2); // 4096

// SRV[4096]
StructuredBuffer<FaceData> faceDataBuffers[4096] : register(t0, space3); // {{RTXStub.buffers.t0_space3}} // 4096

// SRV[4096]
StructuredBuffer<uint4> faceUvBuffers[4096] : register(t0, space5); // {{RTXStub.buffers.t0_space5}} // 4096

// UAV[4096]
RWStructuredBuffer<VertexIrradianceCache> vertexIrradianceCache[4096] : register(u0, space1); // 4096

// UAV[4096]
RWStructuredBuffer<FaceIrradianceCache> faceIrradianceCache[4096] : register(u0, space2); // 4096

// UAV[4096]
RWStructuredBuffer<FaceData> faceDataBuffersRW[4096] : register(u0, space10); // 4096

// UAV[4096]
RWStructuredBuffer<uint4> faceUvBuffersRW[4096] : register(u0, space11); // 4096

// UAV[4096]
RWByteAddressBuffer vertexBuffersRW[4096] : register(u0, space9); // 4096

// DESCRIPTOR_TABLE [1]
// SRV[4096]
Texture2D<float4> textures[4096] : register(t0, space6); // 4096

// DESCRIPTOR_TABLE [1]
// SAMPLER[4]
SamplerState defaultSampler : register(s0); // Filter MIN_LINEAR_MAG_POINT_MIP_LINEAR AddressU CLAMP AddressV CLAMP AddressW WRAP
SamplerState linearSampler : register(s1); // Filter MIN_MAG_MIP_LINEAR AddressU CLAMP AddressV CLAMP AddressW CLAMP
SamplerState linearWrapSampler : register(s2); // Filter MIN_MAG_MIP_LINEAR AddressU WRAP AddressV WRAP AddressW WRAP
SamplerState pointSampler : register(s3); // {{RTXStub.buffers.s3_space0}} // Filter MIN_MAG_POINT_MIP_LINEAR AddressU CLAMP AddressV CLAMP AddressW WRAP
#endif