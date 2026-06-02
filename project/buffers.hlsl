// Note: this file contains ONLY BUFFERS USED BY VANILLA BRTX, for reference purposes.
// If you want to access all buffers, include Signature.hlsl instead.

// Samplers
SamplerState defaultSampler : register(s0);
SamplerState linearSampler : register(s1);
SamplerState linearWrapSampler : register(s2);

// Constant buffers
cbuffer LightMeterDataCB : register(b3) {
    LightMeterData g_lightMeterSamples; // 0
};
cbuffer PreBlasSkinningCB : register(b0, space99) {
    MeshSkinningData g_meshSkinningData; // 0
};
cbuffer RootConstants : register(b2) {
    uint g_rootConstant0; // 0
    uint g_rootConstant1; // 4
    uint g_dispatchDimensions; // 8
};
cbuffer ViewCB : register(b0) {
    View g_view; // 0
};

// Shader resource views
RaytracingAccelerationStructure SceneBVH : register(t0);
Texture2DArray<float4> blueNoiseTexture : register(t58);
Texture2DArray<float> causticsTexture : register(t60);
StructuredBuffer<CheckerboardActions> checkerboardActionsBuffer : register(t55);
StructuredBuffer<FaceIrradianceCacheUpdateChunk> faceIrradianceCacheUpdateChunks : register(t3);
Texture2D<float2> inputAdaptiveDenoiserGradients[2] : register(t51);
Texture2D<int> inputAdaptiveDenoiserPlaneIdentifier : register(t54);
Texture2D<float2> inputAdaptiveDenoiserReference : register(t53);
Texture2D<float4> inputBufferColourAndMetallic : register(t16);
Texture2D<float4> inputBufferIncomingIrradianceCache : register(t18);
Texture2D<float2> inputBufferMotionVectors : register(t21);
Texture2D<float2> inputBufferNormal : register(t15);
Texture2D<float4> inputBufferPreInterleaveCurrent : register(t25);
Texture2D<float4> inputBufferPreInterleavePrevious : register(t26);
Texture2D<int> inputBufferPreviousMedium : register(t63);
Texture2D<float> inputBufferPrimaryPathLength : register(t14);
Texture2D<float2> inputBufferReflectionMotionVectors : register(t22);
Texture2D<float> inputBufferReprojectedPathLength : register(t29);
Texture2D<float2> inputBufferSurfaceOpacityAndObjectCategory : register(t17);
Texture2D<float4> inputEmissiveAndLinearRoughness : register(t44);
Texture2D<float4> inputFinalColour : register(t42);
Texture2D<float2> inputFinalDiffuseMoments : register(t1, space9);
Texture2D<float2> inputFinalSpecularMoments : register(t3, space9);
Texture2D<float2> inputGeometryNormal : register(t43);
StructuredBuffer<float4> inputIncidentLight : register(t19);
StructuredBuffer<LightInfo> inputLightsBuffer : register(t0, space13);
Texture2D<int> inputPlaneIdentifier : register(t27);
Texture2D<float2> inputPreviousGeometryNormal : register(t49);
Texture2D<float4> inputPrimaryPosLowPrecision : register(t50);
Texture2D<float4> inputPrimaryThroughput : register(t47);
Texture2D<float4> inputPrimaryViewDirection : register(t46);
Texture2D<float4> inputPrimaryWorldPosition : register(t45);
StructuredBuffer<LightInfo> inputReducedLightsBuffer : register(t1, space13);
Texture2D<float4> inputTAAHistory : register(t40);
StructuredBuffer<AdaptiveDenoiserLightInfo> inputTemporallyStableLights : register(t2, space13);
Texture2D<float4> inputThisFrameTAAHistory : register(t41);
Texture2D<int> inputTileClassification : register(t57);
StructuredBuffer<ObjectInstance> objectInstances : register(t1);
StructuredBuffer<PBRTextureData> pbrTextureDataBuffer : register(t35);
Texture2D<float4> previousDiffuseBuffer : register(t7);
Texture2D<float3> previousDiffuseChromaBuffer : register(t48);
Texture2D<float2> previousHistoryLengthBuffer : register(t6);
Texture2D<float> previousLinearRoughnessBuffer : register(t24);
Texture2D<float2> previousPrimaryNormalBuffer : register(t5);
Texture2D<float> previousPrimaryPathLengthBuffer : register(t4);
Texture2D<float> previousReflectionDistanceBuffer : register(t23);
Texture2D<float3> previousSpecularBuffer : register(t8);
Texture2D<float4> previousSunLightShadowBuffer : register(t30);
StructuredBuffer<float> refractionIndicesBuffer : register(t56);
Texture2D<float4> shadowDenoisingInputs[2] : register(t0, space4);
Texture2DArray<float3> skyTexture : register(t59);
Texture2D<float4> textures[4096] : register(t0, space6);
ByteAddressBuffer vertexBuffers[4096] : register(t0, space2);
StructuredBuffer<VertexIrradianceCacheUpdateChunk> vertexIrradianceCacheUpdateChunks : register(t2);
Texture3D<float4> volumetricGIInscatterPrevious : register(t39);
Texture3D<float3> volumetricGIResolvedInscatter : register(t38);
Texture3D<float4> volumetricInscatterPrevious : register(t13);
Texture3D<float3> volumetricResolvedInscatter : register(t11);
Texture3D<float3> volumetricResolvedTransmission : register(t12);
Texture2D<float4> waterNormalsTexture : register(t62);
Texture2D<float2> wibblyTexture : register(t61);

// Unordered access views
RWStructuredBuffer<float4> bufferIncidentLight : register(u0, space14);
RWTexture2D<float4> denoisingChromaAndVarianceOutputs[4] : register(u8, space3);
RWTexture2D<float4> denoisingOutputs[8] : register(u0, space3);
RWStructuredBuffer<FaceData> faceDataBuffersRW[4096] : register(u0, space10);
RWStructuredBuffer<FaceIrradianceCache> faceIrradianceCache[4096] : register(u0, space2);
RWStructuredBuffer<uint4> faceUvBuffersRW[4096] : register(u0, space11);
RWTexture2D<float2> outputAdaptiveDenoiserGradients[2] : register(u36);
RWTexture2D<int> outputAdaptiveDenoiserPlaneIdentifier : register(u39);
RWTexture2D<float2> outputAdaptiveDenoiserReference : register(u38);
RWTexture2D<float4> outputBufferColourAndMetallic : register(u3);
RWTexture2D<float4> outputBufferDebug : register(u14);
RWTexture2D<float2> outputBufferDiffuseMoments : register(u40);
RWTexture2D<float4> outputBufferEmissiveAndLinearRoughness : register(u4);
RWTexture2D<float4> outputBufferFinal : register(u12);
RWTexture2D<float2> outputBufferHistoryLength : register(u2);
RWTexture2D<float4> outputBufferIncomingIrradianceCache : register(u11);
RWTexture2D<float4> outputBufferIndirectDiffuse : register(u5);
RWTexture2D<float3> outputBufferIndirectDiffuseChroma : register(u28);
RWTexture2D<float4> outputBufferIndirectSpecular : register(u6);
RWTexture2D<float2> outputBufferMotionVectors : register(u10);
RWTexture2D<float2> outputBufferNormal : register(u1);
RWTexture2D<float4> outputBufferPreInterleave : register(u18);
RWTexture2D<float> outputBufferPreviousLinearRoughness : register(u17);
RWTexture2D<int> outputBufferPreviousMedium : register(u45);
RWTexture2D<float4> outputBufferPreviousSunLightShadow : register(u22);
RWTexture2D<float> outputBufferPrimaryPathLength : register(u0);
RWTexture2D<float4> outputBufferPrimaryPosLowPrecision : register(u29);
RWTexture2D<float4> outputBufferReferencePathTracer : register(u23);
RWTexture2D<float> outputBufferReflectionDistance : register(u15);
RWTexture2D<float2> outputBufferReflectionMotionVectors : register(u16);
RWTexture2D<float> outputBufferReprojectedPathLength : register(u20);
RWTexture2D<float2> outputBufferSpecularMoments : register(u42);
RWTexture2D<float4> outputBufferSunLightShadow : register(u21);
RWTexture2D<float2> outputBufferSurfaceOpacityAndObjectCategory : register(u7);
RWTexture2D<float4> outputBufferTAAHistory : register(u30);
RWTexture2D<float> outputBufferToneCurve : register(u27);
RWTexture2D<uint> outputBufferToneMappingHistogram : register(u26);
RWTexture2D<float2> outputDenoisingMoments[4] : register(u40);
RWTexture2D<float2> outputGeometryNormal : register(u31);
RWTexture2D<int> outputPlaneIdentifier : register(u19);
RWTexture2D<float4> outputPrimaryThroughput : register(u35);
RWTexture2D<float4> outputPrimaryViewDirection : register(u34);
RWTexture2D<float4> outputPrimaryWorldPosition : register(u33);
RWTexture2D<int> outputTileClassification : register(u44);
RWStructuredBuffer<uint> outputVisibleBLASs : register(u32);
RWTexture2D<float4> shadowDenoisingOutputs[2] : register(u0, space4);
RWByteAddressBuffer vertexBuffersRW[4096] : register(u0, space9);
RWStructuredBuffer<VertexIrradianceCache> vertexIrradianceCache[4096] : register(u0, space1);
RWTexture3D<float4> volumetricGIInscatterRW[2] : register(u64);
RWTexture3D<float3> volumetricGIResolvedInscatterRW : register(u63);
RWTexture3D<float4> volumetricInscatterRW : register(u62);
RWTexture3D<float3> volumetricResolvedInscatterRW : register(u60);
RWTexture3D<float3> volumetricResolvedTransmissionRW : register(u61);