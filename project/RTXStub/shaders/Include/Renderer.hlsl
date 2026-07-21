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

#ifndef __RENDERER_HLSL__
#define __RENDERER_HLSL__

#include "Generated/Signature.hlsl"
#include "Material.hlsl"
#include "Util.hlsl"
#include "shadows.hlsl"
#include "sky.hlsl"
#include "tonemapping.hlsl"


static const uint kBlueNoiseLayerMask = kBlueNoiseLayerCount - 1;

uint GetBlueNoiseLayerIndex(uint2 pixelCoord, uint frameSeed) {
    return (pixelCoord.x + pixelCoord.y + frameSeed) & kBlueNoiseLayerMask;
}

float4 GetBlueNoiseValue(uint2 pixelCoord) {
    uint layerIndex = GetBlueNoiseLayerIndex(pixelCoord, g_view.frameCount);
    return LoadBlueNoise(pixelCoord, layerIndex);
}

float BurleyFrostbite(float roughness, float n_dot_l, float n_dot_v, float v_dot_h)
{
    float energyBias = 0.5 * roughness;
    float energyFactor = lerp(1.0, 1.0 / 1.51, roughness);

    float FD90MinusOne = energyBias + 2.0 * v_dot_h * v_dot_h * roughness - 1.0f;
    float FDL = 1.0f + (FD90MinusOne * pow(1.0f - n_dot_l, 5.0f));
    float FDV = 1.0f + (FD90MinusOne * pow(1.0f - n_dot_v, 5.0f));

    return FDL * FDV * energyFactor;
}


struct LightData
{
    float3 color;
    float intensity;
    bool isLarge;
};

LightData UnpackLight(uint packedData)
{
    LightData lightData;
    lightData.isLarge = (packedData >> 24) & 0x80;
    lightData.color = float3(
        (float)((packedData >> 24) & 0x7f) / 127.0,
        (float)((packedData >> 16) & 0xff) / 255.0,
        (float)((packedData >> 8) & 0xff) / 255.0);
    lightData.intensity = (float)((packedData >> 0) & 0xff) / 255.0;
    return lightData;
}

struct RayState
{
    RayDesc rayDesc;

    float3 color;
    float3 throughput;

    float distance;
    float3 motion;

    uint instanceMask; // 8 bits, see INSTANCE_MASK macros in Constants.hlsl

    void Init()
    {
        color = 0;
        throughput = 1;
        distance = 0;
        motion = 0;
        instanceMask = 0xff;
    }
};

void RenderSky(inout RayState rayState)
{
    if (all(rayState.throughput == 0)) return;

    const float3 skyColor = float3(170, 209, 254) / 255;
    const float3 gradientColor = float3(121, 167, 255) / 255;
    
    const float3 nightSkyColor = float3(10, 12, 22) / 255;
    const float3 nightGradientColor = float3(1, 1, 2) / 255;
    
    float gradientLerp = max(0.0, lerp(-0.15, 1.0, rayState.rayDesc.Direction.y));
    gradientLerp = pow(gradientLerp, 0.5);

    const float nightThreshold = -0.3;
    const float dayThreshold = 0.2;
    float timeOfDayLerp = saturate((getTrueDirectionToSun().y - nightThreshold) / (dayThreshold - nightThreshold));

    float3 dayColor = lerp(skyColor, gradientColor, gradientLerp);
    float3 nightColor = lerp(nightSkyColor, nightGradientColor, gradientLerp);

    float3 finalColor = skyScattering1(rayState.rayDesc.Direction);
    
    rayState.color += rayState.throughput * finalColor;
}

float3 fresnelSchlick(float cosTheta, float3 F0) {
  float f = pow(1.0 - cosTheta, 5.0);
  return f + F0 * (1.0 - f);
}

void RenderVanilla(HitInfo hitInfo, inout RayState rayState, in float4 noise, in float3 totalRadiance, in float3 rayColor, int bounceCount)
{
    
    ObjectInstance objectInstance = objectInstances[hitInfo.objectInstanceIndex];
    GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, objectInstance);
    SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, objectInstance);


    float2 Xi = frac(noise.xy + float2(bounceCount * 0.61803398875,bounceCount * 0.38196601125));
    surfaceInfo.color = pow(surfaceInfo.color, 2.2);
        float3 sunDir =  getDirectionToSun();
    float3 moonDir = -sunDir;

    float sunFade = saturate(sunDir.y);
    float moonFade = saturate(moonDir.y);

    float3 mainLightDir = sunFade > 0.0 ? sunDir : moonDir;

     if(hitInfo.materialType == MATERIAL_TYPE_WATER) {
                surfaceInfo.roughness =  surfaceInfo.alpha * 0.5 ;
                
            }

    //surfaceInfo.color = pow(surfaceInfo.color, 2.2);
    float3 worldPos = surfaceInfo.position - g_view.waveWorksOriginInSteveSpace;
    worldPos = worldPos - floor(worldPos / 1024) * 1024; // Bedrock may reset position every 1024 blocks, so we can only reliably calculate world position within 1024 blocks chunk.

    float NdotL = max(dot(surfaceInfo.normal, mainLightDir),0.0001);
    float3 sunColor = float3(1.0,0.85,0.85) * 7;
    rayState.rayDesc.TMin = 0.001;
    rayState.rayDesc.Origin = surfaceInfo.position;
    float3 diffuseDir = CosineHemisphereSampling(Xi, surfaceInfo.normal);
    float3 specularDir = reflect(rayState.rayDesc.Direction, surfaceInfo.normal);
  
      float3 H_r = normalize(-rayState.rayDesc.Direction  + normalize(surfaceInfo.position));
                         float NdotL_r = max(dot(surfaceInfo.normal,  diffuseDir), 0.001);
                
                     float NdotV = max(dot(surfaceInfo.normal, -rayState.rayDesc.Direction), 0.000);
            float NdotL_rc = max(NdotL_r, 0.0001);
            float NdotH_r = max(dot(surfaceInfo.normal, H_r), 0.0);
            float VdotH_r = max(dot(-rayState.rayDesc.Direction, H_r), 0.0);

    float3 F0 = lerp(0.04, surfaceInfo.color,surfaceInfo.metalness );
    float3 F = fresnelSchlick(VdotH_r, F0);
    float3 kS =  F;
    float3 kD = float3(1.0,1.0,1.0) - kS;
    kD *= (1.0 - surfaceInfo.metalness);

    rayState.rayDesc.Direction = lerp(specularDir, diffuseDir, surfaceInfo.roughness);
    shadowPayload payload;
    RayDesc shadowRay;
    shadowRay.Origin = offset_ray(surfaceInfo.position, surfaceInfo.normal);
    shadowRay.Direction = CosineHemisphereSamplingSun(Xi,mainLightDir);
    shadowRay.TMin = 0.0;
    shadowRay.TMax = 10000;

    TraceShadowRay(shadowRay, payload);
    // Vanilla-like shading
   float4 sunlightColor = getSunColor(0.xxxx);
     float sunIntensity = sunlightColor.a;
            sunlightColor.rgb *= luminance(sunlightColor.rgb * sunIntensity);

    float3 light = surfaceInfo.color * sunlightColor.rgb * NdotL * payload.transmission;

   
    

    // Force alphatest and opaque materials to have full alpha.
    if (hitInfo.materialType == MATERIAL_TYPE_OPAQUE || hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST) surfaceInfo.alpha = 1;

    if (objectInstance.flags & kObjectInstanceFlagClouds)
    {
        light = geometryInfo.color.rgb; // Clouds have vanilla shading baked into vertex color.
        surfaceInfo.alpha = 0.7;        // Match vanilla clouds alpha
    }
    
          
    // Apply emissive lighting.
    float3 emission = ( surfaceInfo.color) * surfaceInfo.emissive * 6000;
    totalRadiance += emission;
    totalRadiance += light;
    float3 BRDF = ( surfaceInfo.color / PI) ;
    float SurfNdotL = max(dot(normalize(rayState.rayDesc.Origin), surfaceInfo.normal),0.0001);
    float PDF = PDF_CosineHemisphere(SurfNdotL);

     //float diff = BurleyFrostbite(surfaceInfo.roughness, SurfNdotL,NdotV, VdotH_r);
    rayColor *= BRDF * SurfNdotL / PDF;
    uint mediaType = objectInstance.offsetPack5 >> 8; // See MEDIA_TYPE macros in Constants.hlsl.

    // Advance ray forward
    //rayState.rayDesc.TMin = hitInfo.rayT;

    

    
   
 
    
    
    const bool isBlockBreakingOverlay = objectInstance.flags == (kObjectInstanceFlagAlphaTestThresholdHalf | kObjectInstanceFlagTextureAlphaControlsVertexColor);

    float3 throughput;
    float3 emissions;
    
          RayDesc transmissionRay;
            transmissionRay.Origin = offset_ray(surfaceInfo.position, surfaceInfo.normal);
            transmissionRay.Direction = rayState.rayDesc.Direction;
            transmissionRay.TMin = 0.0;
            transmissionRay.TMax = 10000.0;
            TransmissionPayload payload2;
            castTransmissionRay(transmissionRay, payload2);

            rayColor *= payload2.transmission;
    
    totalRadiance *= surfaceInfo.alpha;

    // Glint
    if (objectInstance.flags & kObjectInstanceFlagGlint)
        totalRadiance += (sin(3.0 * g_view.time) * 0.5 + 0.5) * (float3(077, 23, 255) / 255.0);

    // Accumulate surface emission and throughput
    rayState.color += totalRadiance * rayState.throughput;
    rayState.throughput *= rayColor;

    // Update other ray properties
    rayState.distance = hitInfo.rayT;
    rayState.motion = surfaceInfo.position - surfaceInfo.prevPosition;
    
}


float3 RenderRay(RayDesc rayDesc, out float outputDistance, out float3 outputMotion, in float2 pixelPos)
{
   
    
   
    RayQuery<RAY_FLAG_NONE> q;
    RayState rayState;
    rayState.Init();
    rayState.rayDesc = rayDesc;

    float4 blueNoise = GetBlueNoiseValue(pixelPos);
    float3 totalRadiance = 0;
    float3 rayColor = 1.0;
    // Limit to 100 overlapping translucent surfaces.
    for (int i = 0; i < 4; i++)
    {
         
        q.TraceRayInline(SceneBVH, RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES, rayState.instanceMask, rayState.rayDesc);
        while (q.Proceed())
        {
            HitInfo hitInfo = GetCandidateHitInfo(q);
            if (AlphaTestHitLogic(hitInfo))
            {
                q.CommitNonOpaqueTriangleHit();
            }
        }

        if (q.CommittedStatus() == COMMITTED_TRIANGLE_HIT)
        {
            HitInfo hitInfo = GetCommittedHitInfo(q);
             ObjectInstance objectInstance = objectInstances[hitInfo.objectInstanceIndex];
  
            if (objectInstance.flags & (kObjectInstanceFlagSun | kObjectInstanceFlagMoon))
            {
                // Use additive blending for sun and moon
                rayColor = 0;
                totalRadiance = 0;
        
                break;
            }
            RenderVanilla(hitInfo, rayState, blueNoise, totalRadiance, rayColor, i);
        }
        else
        {
            RenderSky(rayState);
            break;
        }

        // Terminate rays that can't contribute anymore.
        if (all(rayState.throughput == 0))
            break;
    }

    const float maxDistance = 65504; // Maximum value depth buffer can contain.
    if (all(rayState.throughput == 0)) {
        // Eventually hit solid object
        outputDistance = min(rayState.distance, maxDistance);
        outputMotion = rayState.motion;
    } else {
        // Eventually hit sky
        outputDistance = maxDistance;
        outputMotion = 0;
    }

    //RenderSky(rayState);
    return rayState.color;
}

#endif