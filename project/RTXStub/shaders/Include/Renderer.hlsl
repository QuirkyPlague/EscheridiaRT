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
#include "brdf.hlsl"
#include "shadows.hlsl"
#include "sky.hlsl"
#include "settings.hlsl"
#include "water.hlsl"
#include "GI.hlsl"
#include "tonemapping.hlsl" 
#include "fog.hlsl"

static const uint kBlueNoiseLayerMask = kBlueNoiseLayerCount - 1;

uint GetBlueNoiseLayerIndex(uint2 pixelCoord, uint frameSeed) {
    return (pixelCoord.x + pixelCoord.y + frameSeed) & kBlueNoiseLayerMask;
}

float4 GetBlueNoiseValue(uint2 pixelCoord) {
    uint layerIndex = GetBlueNoiseLayerIndex(pixelCoord, g_view.frameCount);
    return LoadBlueNoise(pixelCoord, layerIndex);
}

struct LightData {
    float3 color;
    float intensity;
    bool isLarge;
};

LightData UnpackLight(uint packedData) {
    LightData lightData;
    lightData.isLarge = (packedData >> 24) & 0x80;
    lightData.color = float3(
        (float)((packedData >> 24) & 0x7f) / 127.0,
        (float)((packedData >> 16) & 0xff) / 255.0,
        (float)((packedData >> 8) & 0xff) / 255.0);
    lightData.intensity = (float)((packedData >> 0) & 0xff) / 255.0;
    return lightData;
}

static const uint PRIMARY_TRACE_MASK =
    INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_PRIMARY |
    INSTANCE_MASK_ALPHA_BLEND_PRIMARY |
    INSTANCE_MASK_WATER |
    INSTANCE_MASK_SUN_OR_MOON;

struct RayState {
    RayDesc rayDesc;

    float3 color;
    float3 throughput;

    float distance;
    float3 motion;
    float3 indirectDiffuse;
    float3 specular;

    uint instanceMask; // 8 bits, see INSTANCE_MASK macros in Constants.hlsl

    void Init() {
        color = 0;
        indirectDiffuse = 0;
        throughput = 1;
        distance = 0;
        motion = 0;
        instanceMask = PRIMARY_TRACE_MASK;
    }
};

// Set to false by default
#ifndef CULL_GLASS_BACK_FACES
#define CULL_GLASS_BACK_FACES 0
#endif

bool AlphaTestHitLogic1(HitInfo hitInfo) {
#if CULL_GLASS_BACK_FACES
    if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND && !hitInfo.frontFacing)
    return false;
#endif
    // If this logic runs for non-alphatested things, always register a hit.
    if (hitInfo.materialType != MATERIAL_TYPE_ALPHA_TEST)
    return true;

    // Tip: instead of calculating material every time, you can calculate UVs during CalculateFaceData pass and cache them in faceUvBuffers.
    // Then during alpha testing, cached UVs can be used to sample texture(s) instead of using expensive material and geometry computations.
    ObjectInstance obj = objectInstances[hitInfo.objectInstanceIndex];
    GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, obj);
    SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, obj);

    return !surfaceInfo.shouldDiscard;
}

void skyCol(inout RayState rayState) {
    if (all(rayState.throughput == 0)) return;
    rayState.color += rayState.throughput * skyScattering1(rayState.rayDesc.Direction);
}

float3 computeSkylight(float3 n) {
    float3 up = float3(0.0, 1.0, 0.0);

    float3 result = float3(0.0,0.0,0.0);
    float totalWeight = 0.0;
    float3 bentNormal = float3(0.0,0.0,0.0);

    // Fixed sky directions - consistent hemisphere regardless of surface orientation
    float3 skyDirs[9] = {
        float3(1.0, 1.0, 1.0),               // zenith (heavily weighted)
        normalize(float3(1.0, -0.2, 0.15)),
        normalize(float3(-1.0, 0.35, 0.0)),
        normalize(float3(0.0, 0.35, 1.0)),
        normalize(float3(0.0, 0.3, -1.0)),
        normalize(float3(0.707, 0.21, 0.707)),
        normalize(float3(-0.707, 0.21, 0.707)),
        normalize(float3(3.0, 3.0, 3.0)),     // extra zenith sample
        normalize(float3(0.0, -0.04, 0.0))   // downward - ground bounce (dimmed)
    };

    for(int i = 0; i < 9; i++) {
        float contribution = max(dot(n, skyDirs[i]), 0.0);
        float NdotL = max(dot(n, getTrueDirectionToSun()), 0.0);

        if(i >= 8) contribution *= 0.345;  // downward samples (ground bounce) are weaker

        result += skyCompute(normalize(skyDirs[i])) * contribution;
        totalWeight += contribution;

        // Accumulate bent normal from unoccluded samples
        bentNormal += skyDirs[i] * contribution;
    }

    // Compute bent normal - represents average unoccluded direction
    bentNormal = normalize(bentNormal + n * 0.8);

    // Apply visibility correction: blend between normal and bent normal for occluded areas
    // Areas with high occlusion (bent normal deviates strongly) get brightened
    float visibility = lerp(1.0, length(bentNormal) * 0.7, 0.5);

    return result / max(totalWeight, 0.01);
}

float3 RenderRay(RayDesc rayDesc, uint2 pixelCoord, out float outputDistance, out float3 outputMotion, out float3 indirectDiffuse) {
    RayQuery<RAY_FLAG_NONE> q;

    RayState rayState;
    rayState.Init();
    rayState.rayDesc = rayDesc;

    float4 blueNoise = GetBlueNoiseValue(pixelCoord);
    bool inWater = g_view.cameraIsUnderWater;
    float3 sunDir = inWater ? getUnderwaterDirectionToSun() : getDirectionToSun();
    float3 moonDir = -sunDir;

    float sunFade = saturate(sunDir.y);
    float moonFade = saturate(moonDir.y);

    float3 mainLightDir = sunFade > 0.0 ? sunDir : moonDir;

    for (int i = 0; i < 100; i++) {
        q.TraceRayInline(SceneBVH, RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES, rayState.instanceMask, rayState.rayDesc);
        while (q.Proceed()) {
            HitInfo hitInfo = GetCandidateHitInfo(q);
            if (AlphaTestHitLogic1(hitInfo)) {
                q.CommitNonOpaqueTriangleHit();
            }
            
        }

    if (q.CommittedStatus() == COMMITTED_TRIANGLE_HIT) {
        HitInfo hitInfo = GetCommittedHitInfo(q);

            ObjectInstance obj = objectInstances[hitInfo.objectInstanceIndex];
            GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, obj);
            SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, obj);
            if (obj.flags & (kObjectInstanceFlagSun | kObjectInstanceFlagMoon)) rayState.color = float3(0.0, 0.0, 0.0);
                    
            surfaceInfo.color = max(surfaceInfo.color, 0.001);
            surfaceInfo.color = pow(surfaceInfo.color, 2.2);

            float3 emissive = float3(0.0,0.0,0.0);
            bool  isCloud = obj.flags & kObjectInstanceFlagClouds;
            // Force alphatest and opaque materials to have full alpha.
            if (hitInfo.materialType == MATERIAL_TYPE_OPAQUE || hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST) surfaceInfo.alpha = 1;

            float4 sunlightColor =  getSunColor(float4(0.0, 0.0, 0.0, 0.0)) * SUN_INTENSITY;

            float sunIntensity = sunlightColor.a;
            sunlightColor.rgb *= luminance(sunlightColor.rgb * sunIntensity);
            float3 skylight = 0.0;
            skylight = CSB(skylight,1.0,0.85,1.0);

            bool isAlphaBlendSurface = hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND;
            bool isWaterSurface = hitInfo.materialType == MATERIAL_TYPE_WATER;

            RayDesc transmissionRay;
            transmissionRay.Origin = surfaceInfo.position + 1e-4 * surfaceInfo.normal;
            transmissionRay.Direction = rayDesc.Direction;
            transmissionRay.TMin = 0.0;
            transmissionRay.TMax = 10000.0;

            TransmissionPayload payload4;
            castTransmissionRay(transmissionRay, payload4);

            float3 black = float3(0.0,0.0,0.0);
            float3 lighting = float3(0.0,0.0,0.0);
            float3 diffuseGI = float3(0.0,0.0,0.0);
            float3 sunShadow = float3(1.0,1.0,1.0);
            float3 skyShadows = float3(1.0,1.0,1.0);
            getShadow(surfaceInfo, mainLightDir, blueNoise.xy, sunShadow);
        
            float NdotL = max(dot(surfaceInfo.normal, mainLightDir), 0.001);

            float sss = surfaceInfo.subsurface;

            float3 reflection = 0.0;
            float3 emissions = 0.0;
            diffuseGI *=  GI_BRIGHTNESS;
            if(hitInfo.materialType == MATERIAL_TYPE_WATER) {
                surfaceInfo.roughness = 0.0;
                surfaceInfo.color = 0;
                const float waveSmoothness = WAVE_SMOOTHING;
                const float waveStrength = WAVE_INTENSITY;
                float3 worldPos = surfaceInfo.position - g_view.waveWorksOriginInSteveSpace;
                worldPos = worldPos - floor(worldPos / 1024) * 1024; // Bedrock may reset position every 1024 blocks, so we can only reliably calculate world position within 1024 blocks chunk.

                float3 waveNorm = surfaceInfo.normal;

                waveNorm = waveNormal(worldPos.xz, waveSmoothness, waveStrength);
                surfaceInfo.normal = waveNorm;
            }

            float3 direction = normalize(rayDesc.Direction);
            float3x3 tbn = tbnMatrix(surfaceInfo.normal);

            //view direction in tangent space
            float3 tangentView = mul(tbn, -direction);

            float3 accumulated = float3(0.0,0.0,0.0);
            float3 skyDir = float3(0,0,0);
            for (uint i = 0u; i < uint(1); i++) {
                float alpha = max(surfaceInfo.roughness * surfaceInfo.roughness, 0.001);

                float3 microFacit = SampleVNDFGGX(tangentView, float2(alpha, alpha), blueNoise.xy);

                float3 tangentReflDir = reflect(-tangentView, microFacit);

                skyDir = normalize(mul(tangentReflDir, tbn));
            }

            bool isWater = hitInfo.materialType == MATERIAL_TYPE_WATER;
            float3 specular = float3(0.0, 0.0, 0.0);
            for(uint s = 0; s < uint(SPECULAR_SAMPLES); s++)
            {
            RayDesc reflections;
            reflections.Origin = surfaceInfo.position + 1e-4 * surfaceInfo.normal ;
            reflections.Direction = skyDir ;
            reflections.TMin = 0.0f;
            reflections.TMax = 10000;

            reflectionRay payload;
            traceReflectionRay(reflections, payload, false);

            if(payload.hit) {
                payload.color = pow(payload.color, 2.2);

       

                float3 sunGi = 0.0;
             

                const uint shadowSteps = 1;

                float3 T = normalize(cross(
                        abs(mainLightDir.z) < 0.999 ?
                        float3(0,0,1) :
                        float3(1,0,0),
                        mainLightDir));

                float3 B = cross(mainLightDir, T);

                const float sunRadius = SUN_RADIUS; 
                float3 shadowTransmission = 0;
                for(uint y = 0; y < shadowSteps; y++) {
                    float2 Xi = frac(blueNoise.xy + float2(
                            y * 0.61803398875,
                            y * 0.38196601125));

                    float r = sunRadius * sqrt(Xi.x);
                    float theta = 2.0 * PI * Xi.y;

                    float2 disk = r * float2(
                        cos(theta),
                        sin(theta));

                    float3 sampleDir = normalize(
                        mainLightDir +
                        disk.x * T +
                        disk.y * B);

                    RayDesc shadowRay;
                    shadowRay.Origin =
                    payload.position +
                    1.0e-4 * payload.normal;

                    shadowRay.Direction = sampleDir;
                    shadowRay.TMin = 0.0;
                    shadowRay.TMax = 10000.0;

                    ShadowPayload payload;
                    TraceShadowRay(shadowRay, payload);

                    shadowTransmission += payload.transmission;
                }

                shadowTransmission =
                shadowTransmission / float(shadowSteps);

                float3 F0 = isWater ? float3(0.02, 0.02, 0.02) : lerp(float3(0.04, 0.04, 0.04), surfaceInfo.color, surfaceInfo.metalness);
                float3 dir = rayDesc.Direction;
                float3 F = fresnelSchlick(max(dot(-dir, surfaceInfo.normal), 0.0001), F0);
             
                float3 reflectedLighting = BRDF1(payload.normal, normalize(-payload.position), mainLightDir, sunlightColor.rgb, skylight, payload.color, payload.roughness, payload.metalness, payload.emission, shadowTransmission, sunGi);
                float roughMask = step(0.0, payload.roughness);
                //pointlights
                for (int j = 0; j < min(MAX_POINT_LIGHTS, g_view.cpuLightsCount); j++) {
                    LightInfo lightInfo = inputLightsBuffer[j];
                    LightData lightData = UnpackLight(lightInfo.packedData);

                    float3 lDir = lightInfo.position - payload.position;
                    float lDist = length(lDir);
                    lDir /= lDist;

                    float attenuation = max(0, dot(payload.normal, lDir)) / (lDist * lDist);
                    float3 light = 0.0;
                    float3 lightColor = lightData.intensity * lightData.color;
                    float3 T = normalize(cross(
                            abs(lDir.z) < 0.999 ?
                            float3(0,0,1) :
                            float3(1,0,0),
                            lDir));

                    float3 B = cross(lDir, T);
                    const float sunRadius = POINT_LIGHT_SHADOW_RADIUS; 
                    float3 shadowTransmission1 = 0.0;
                    for(int t = 0; t < 1; t++) {
                        float2 Xi = frac(blueNoise.xy + float2(
                                t * 0.61803398875,
                                t * 0.38196601125));

                        float r = sunRadius * sqrt(Xi.x);
                        float theta = 2.0 * PI * Xi.y;

                        float2 disk = r * float2(
                            cos(theta),
                            sin(theta));

                        float3 sampleDir = normalize(
                            lDir +
                            disk.x * T +
                            disk.y * B);

                        RayDesc shadowRay;
                        shadowRay.Origin = payload.position + 1.0e-4 * payload.normal;
                        shadowRay.Direction = sampleDir;
                        shadowRay.TMin = 0.0;
                        shadowRay.TMax = max(lDist - 0.55, 0.0);

                        ShadowPayload payload;
                        TraceShadowRay(shadowRay, payload);
                        shadowTransmission1 = payload.transmission;
                    }
                    lightColor *= shadowTransmission1;
                    light = BRDFPoint1(payload.normal, normalize(-payload.position), lDir, lightColor, payload.roughness, payload.metalness, attenuation, payload.color) * 700;
                    reflectedLighting += light;
                }
                
            float3 indirect = 0.0;
            float3 indirectLight = 0.0;
            for(uint de = 0; de < uint(INDIRECT_SAMPLES); de++)
            {
                
                float3 primaryIndirect = 0.0;
                float2 Xi = frac(blueNoise.xy + float2(
                            de * 0.61803398875,
                           de * 0.38196601125));

            float3 sampleDir1 = CosineHemisphereSampling(Xi, payload.normal);
            RayDesc bounce;
            bounce.Origin = payload.position + 1e-4 * payload.normal ;
            bounce.Direction = sampleDir1 ;
            bounce.TMin = 0.0f;
            bounce.TMax = 10000;

            GiHitPayload payload3;
            TraceGIBounce(bounce, payload3, false);

            if(payload3.hit) 
                {
                    payload3.color = pow(payload3.color, 2.2);
                    const uint skySample = 1;
                skyShadowPayload payload1;
                float3 transmission = 0;
                float3 skyShading = float3(0.0, 0.0, 0.0);

                float3 sunGi = 0.0;
             

                const uint shadowSteps = 1;

                float3 T = normalize(cross(
                        abs(mainLightDir.z) < 0.999 ?
                        float3(0,0,1) :
                        float3(1,0,0),
                        mainLightDir));

                float3 B = cross(mainLightDir, T);

                const float sunRadius = SUN_RADIUS; 
                float3 shadowTransmission = 0;
                for(uint y = 0; y < shadowSteps; y++) {
                    float2 Xi = frac(blueNoise.xy + float2(
                            y * 0.61803398875,
                            y * 0.38196601125));

                    float r = sunRadius * sqrt(Xi.x);
                    float theta = 2.0 * PI * Xi.y;

                    float2 disk = r * float2(
                        cos(theta),
                        sin(theta));

                    float3 sampleDir = normalize(
                        mainLightDir +
                        disk.x * T +
                        disk.y * B);

                    RayDesc shadowRay;
                    shadowRay.Origin =
                    payload3.position +
                    1.0e-4 * payload3.normal;

                    shadowRay.Direction = sampleDir;
                    shadowRay.TMin = 0.0;
                    shadowRay.TMax = 10000.0;

                    ShadowPayload payload;
                    TraceShadowRay(shadowRay, payload);

                    shadowTransmission += payload.transmission;
                 }

                shadowTransmission =
                shadowTransmission / float(shadowSteps);
                     indirectLight += BRDF1(payload3.normal, normalize(-payload3.position), mainLightDir, sunlightColor.rgb, skylight, payload3.color, payload3.roughness, payload3.metalness, payload3.emission, shadowTransmission, sunGi) * payload3.transmission;
                       float3 H_r = normalize(-payload.direction + payload3.direction);
                         float NdotL_r = max(dot(payload.normal,  payload3.direction), 0.001);
                
                     float NdotV = max(dot(payload.normal, -dir), 0.000);
            float NdotL_rc = max(NdotL_r, 0.0001);
            float NdotH_r = max(dot(payload.normal, H_r), 0.0);
            float VdotH_r = max(dot(-dir, H_r), 0.0);

            float3 F_r = fresnelSchlick(VdotH_r, F0);
                 float3 kS =F_r;
                    float3 kD = float3(1.0,1.0,1.0) - kS;
                        float diff = BurleyFrostbite(payload.roughness, NdotL_rc,NdotV, VdotH_r);

                    kD *= (1.0 - payload.metalness);
                 indirect += (kD * payload.color * diff) * indirectLight * payload3.transmission ;
                 }
                 else
                 {
                    float3 H_r = normalize(-payload.direction + payload3.direction);
                         float NdotL_r = max(dot(payload.normal,  payload3.direction), 0.001);
                
                     float NdotV = max(dot(payload.normal, -dir), 0.000);
            float NdotL_rc = max(NdotL_r, 0.0001);
            float NdotH_r = max(dot(payload.normal, H_r), 0.0);
            float VdotH_r = max(dot(-dir, H_r), 0.0);

            float3 F_r = fresnelSchlick(VdotH_r, F0);
                 float3 kS =F_r;
                    float3 kD = float3(1.0,1.0,1.0) - kS;
                        float diff = BurleyFrostbite(payload.roughness, NdotL_rc,NdotV, VdotH_r);
                     float3 sky = skyScattering1(payload3.direction);
                     sky *= 4.45;
                    kD *= (1.0 - payload.metalness);
                 indirect += (kD * payload.color * diff) * sky *payload3.transmission ;
                 }
            }
            indirect /= float(INDIRECT_SAMPLES);
                
                reflection = reflectedLighting + indirect;
                  float3 H_r = normalize(-dir + skyDir);
                     float NdotL_r = max(dot(surfaceInfo.normal, skyDir), 0.001);
                     if(NdotL_r > 0.0001)
                     {
                        float NdotV = max(dot(surfaceInfo.normal, -dir), 0.000);
            float NdotL_rc = max(NdotL_r, 0.0001);
            float NdotH_r = max(dot(surfaceInfo.normal, H_r), 0.0);
            float VdotH_r = max(dot(-dir, H_r), 0.0);

            float3 F_r = fresnelSchlick(VdotH_r, F0);
            float D_r = D_GGX(NdotH_r, surfaceInfo.roughness);
            float G_r = G_Smith(NdotV, NdotL_rc, surfaceInfo.roughness);
            float3 specWeight = ((F_r * D_r * G_r) / (4.0 * NdotV * NdotL_rc))
                              + FdezAgueraMultipleScattering(NdotV, NdotL_rc, surfaceInfo.roughness, F0);
            float pdf_r = PDF_GGX_Reflection(NdotV, NdotH_r, VdotH_r, surfaceInfo.roughness);
                  if (pdf_r > 0.0001) {
                float3 weight_r = (specWeight * NdotL_rc) / pdf_r;

                
              
                reflection *= weight_r;
                specular += reflection * payload.transmission  ;
                     }
                        else
                  {
                    if(isWater)
                    {
                        reflection *= F_r;
                         specular += reflection * payload.transmission ;
                    }
                  }
                     
            }
            }
            else {
                float3 F0 = isWater ? float3(0.02, 0.02, 0.02) : lerp(float3(0.04, 0.04, 0.04), surfaceInfo.color, surfaceInfo.metalness);
                float3 dir = rayDesc.Direction;
                float3 F = fresnelSchlick(max(dot(-dir, surfaceInfo.normal), 0.0001), F0);
                reflection = skyScattering1(payload.direction);
                float roughMask = step(0.0, payload.roughness);

                             float3 H_r = normalize(-dir + skyDir);
                         float NdotL_r = max(dot(surfaceInfo.normal, skyDir), 0.001);
                     if(NdotL_r > 0.000)
                     {
                     float NdotV = max(dot(surfaceInfo.normal, -dir), 0.000);
            float NdotL_rc = max(NdotL_r, 0.0001);
            float NdotH_r = max(dot(surfaceInfo.normal, H_r), 0.0);
            float VdotH_r = max(dot(-dir, H_r), 0.0);

            float3 F_r = fresnelSchlick(VdotH_r, F0);
            float D_r = D_GGX(NdotH_r, surfaceInfo.roughness);
            float G_r = G_Smith(NdotV, NdotL_rc, surfaceInfo.roughness);
            float3 specWeight = ((F_r * D_r * G_r) / (4.0 * NdotV * NdotL_rc))
                              + FdezAgueraMultipleScattering(NdotV, NdotL_rc, surfaceInfo.roughness, F0);
            float pdf_r = PDF_GGX_Reflection(NdotV, NdotH_r, VdotH_r, surfaceInfo.roughness);
                  if (pdf_r > 0.0001) {
                float3 weight_r = (specWeight * NdotL_rc) / pdf_r;

                
              
                reflection *= weight_r;
                specular += reflection * payload.transmission;
                  }
                  else
                  {
                    if(isWater)
                    {
                        reflection *= F_r;
                         specular += reflection  *payload.transmission;
                    }
                  }
            }
            }
            }
            
            float3 indirect = 0.0;
            
            for(uint de = 0; de < uint(INDIRECT_SAMPLES); de++)
            {
                float2 Xi = frac(blueNoise.xy + float2(
                            de * 0.61803398875,
                           de * 0.38196601125));

            float3 sampleDir1 = CosineHemisphereSampling(Xi, surfaceInfo.normal);
            RayDesc bounce;
            bounce.Origin = surfaceInfo.position + 1e-4 * surfaceInfo.normal ;
            bounce.Direction = sampleDir1 ;
            bounce.TMin = 0.0f;
            bounce.TMax = 10000;

            GiHitPayload payload3;
            TraceGIBounce(bounce, payload3, false);
            float3 bounceTransmission = 1.0;
            if(payload3.hit) 
                {
                    payload3.color = pow(payload3.color, 2.2);
                    const uint skySample = 1;
                skyShadowPayload payload1;
                float3 transmission = 0;
                float3 skyShading = float3(0.0, 0.0, 0.0);

                float3 sunGi = 0.0;
             

                const uint shadowSteps = 1;

                float3 T = normalize(cross(
                        abs(mainLightDir.z) < 0.999 ?
                        float3(0,0,1) :
                        float3(1,0,0),
                        mainLightDir));

                float3 B = cross(mainLightDir, T);

                const float sunRadius = SUN_RADIUS; 
                float3 shadowTransmission = 0;
                for(uint y = 0; y < shadowSteps; y++) {
                    float2 Xi = frac(blueNoise.xy + float2(
                            y * 0.61803398875,
                            y * 0.38196601125));

                    float r = sunRadius * sqrt(Xi.x);
                    float theta = 2.0 * PI * Xi.y;

                    float2 disk = r * float2(
                        cos(theta),
                        sin(theta));

                    float3 sampleDir = normalize(
                        mainLightDir +
                        disk.x * T +
                        disk.y * B);

                    RayDesc shadowRay;
                    shadowRay.Origin =
                    payload3.position +
                    1.0e-4 * payload3.normal;

                    shadowRay.Direction = sampleDir;
                    shadowRay.TMin = 0.0;
                    shadowRay.TMax = 10000.0;

                    ShadowPayload payload;
                    TraceShadowRay(shadowRay, payload);

                    shadowTransmission += payload.transmission;
                 }

                shadowTransmission =
                shadowTransmission / float(shadowSteps);
                    float3 F0 = isWater ? float3(0.02, 0.02, 0.02) : lerp(float3(0.04, 0.04, 0.04), surfaceInfo.color, surfaceInfo.metalness);
                float3 dir = rayDesc.Direction;
             
            
                float3 reflectedLighting = BRDF1(payload3.normal, normalize(-payload3.position), mainLightDir, sunlightColor.rgb, skylight, payload3.color, payload3.roughness, payload3.metalness, payload3.emission, shadowTransmission, sunGi) * payload3.transmission;
                float3 H_r = normalize(-dir + payload3.direction);
                         float NdotL_r = max(dot(surfaceInfo.normal,  payload3.direction), 0.001);
                
                     float NdotV = max(dot(surfaceInfo.normal, -dir), 0.000);
            float NdotL_rc = max(NdotL_r, 0.0001);
            float NdotH_r = max(dot(surfaceInfo.normal, H_r), 0.0);
            float VdotH_r = max(dot(-dir, H_r), 0.0);

            float3 F_r = fresnelSchlick(VdotH_r, F0);
                 float3 kS =F_r;
                    float3 kD = float3(1.0,1.0,1.0) - kS;
                        float diff = BurleyFrostbite(surfaceInfo.roughness, NdotL_rc,NdotV, VdotH_r);

                    kD *= (1.0 - surfaceInfo.metalness);
                 indirect += (kD * surfaceInfo.color * diff)  * reflectedLighting * payload3.transmission * NdotL_rc ;
                 for(uint bounces = 0; bounces < uint(GI_BOUNCES); bounces++)
                 {
                    float2 Xi = frac(blueNoise.xy + float2(
                            bounces * 0.61803398875,
                           bounces * 0.38196601125));

                    float3 sampleDir2 = CosineHemisphereSampling(Xi, payload3.normal);
            RayDesc bounce2;
            bounce2.Origin = payload3.position + 1e-4 * payload3.normal ;
            bounce2.Direction = sampleDir2 ;
            bounce2.TMin = 0.0f;
            bounce2.TMax = 10000;

            GiHitPayload payload5;
            TraceGIBounce(bounce2, payload5, false);
            if(payload5.hit)
            {
                payload5.color = pow(payload5.color, 2.2);
                    const uint skySample = 1;
                skyShadowPayload payload1;
                float3 transmission = 0;
                float3 skyShading = float3(0.0, 0.0, 0.0);

                float3 sunGi = 0.0;
             

                const uint shadowSteps = 1;

                float3 T = normalize(cross(
                        abs(mainLightDir.z) < 0.999 ?
                        float3(0,0,1) :
                        float3(1,0,0),
                        mainLightDir));

                float3 B = cross(mainLightDir, T);

                const float sunRadius = SUN_RADIUS; 
                float3 shadowTransmission = 0;
                for(uint y = 0; y < shadowSteps; y++) {
                    float2 Xi = frac(blueNoise.xy + float2(
                            y * 0.61803398875,
                            y * 0.38196601125));

                    float r = sunRadius * sqrt(Xi.x);
                    float theta = 2.0 * PI * Xi.y;

                    float2 disk = r * float2(
                        cos(theta),
                        sin(theta));

                    float3 sampleDir = normalize(
                        mainLightDir +
                        disk.x * T +
                        disk.y * B);

                    RayDesc shadowRay;
                    shadowRay.Origin =
                    payload5.position +
                    1.0e-4 * payload5.normal;

                    shadowRay.Direction = sampleDir;
                    shadowRay.TMin = 0.0;
                    shadowRay.TMax = 10000.0;

                    ShadowPayload payload;
                    TraceShadowRay(shadowRay, payload);

                    shadowTransmission += payload.transmission;
                 }

                shadowTransmission =
                shadowTransmission / float(shadowSteps);
                    float3 F0 = isWater ? float3(0.02, 0.02, 0.02) : lerp(float3(0.04, 0.04, 0.04), surfaceInfo.color, surfaceInfo.metalness);
                float3 dir = payload3.direction;
             
            
                float3 reflectedLighting = BRDF1(payload5.normal, normalize(-payload5.position), mainLightDir, sunlightColor.rgb, skylight, payload5.color, payload5.roughness, payload5.metalness, payload5.emission, shadowTransmission, sunGi) * payload5.transmission;
                float3 H_r = normalize(-dir + payload5.direction);
                         float NdotL_r = max(dot(payload3.normal,  payload5.direction), 0.001);
                
                     float NdotV = max(dot(payload3.normal, -dir), 0.000);
            float NdotL_rc = max(NdotL_r, 0.0001);
            float NdotH_r = max(dot(payload3.normal, H_r), 0.0);
            float VdotH_r = max(dot(-dir, H_r), 0.0);

            float3 F_r = fresnelSchlick(VdotH_r, F0);
                 float3 kS =F_r;
                    float3 kD = float3(1.0,1.0,1.0) - kS;
                        float diff = BurleyFrostbite(surfaceInfo.roughness, NdotL_rc,NdotV, VdotH_r);

                    kD *= (1.0 - surfaceInfo.metalness);
                 indirect += (kD * surfaceInfo.color * diff)  * reflectedLighting * payload5.transmission * NdotL_rc * bounceTransmission;
                 bounceTransmission = (payload3.color * diff * NdotL_rc)  / PI;
            }
            else{
                float3 dir = payload3.direction;
                    float3 sky = skyScattering1(payload5.direction);
                    float3 H_r = normalize(-dir + payload5.direction);
                         float NdotL_r = max(dot(payload3.normal,  payload5.direction), 0.001);
                
                     float NdotV = max(dot(payload3.normal, -dir), 0.000);
            float NdotL_rc = max(NdotL_r, 0.0001);
            float NdotH_r = max(dot(payload3.normal, H_r), 0.0);
            float VdotH_r = max(dot(-dir, H_r), 0.0);

            float3 F_r = fresnelSchlick(VdotH_r, F0);
                 float3 kS =F_r;
                    float3 kD = float3(1.0,1.0,1.0) - kS;
                        float diff = BurleyFrostbite(surfaceInfo.roughness, NdotL_rc,NdotV, VdotH_r);
            
                    kD *= (1.0 - surfaceInfo.metalness);
                    
                      sky *= SKYLIGHT_INTENSITY ;
                    indirect += (kD * surfaceInfo.color * diff)  * sky * payload5.transmission * NdotL_rc * bounceTransmission;
                    bounceTransmission = (payload3.color * diff * NdotL_rc)  / PI;
            }
                }
                }
                else
                {
                    float3 dir = rayDesc.Direction;
                    float3 sky = skyScattering1(payload3.direction);
                    float3 H_r = normalize(-dir + payload3.direction);
                         float NdotL_r = max(dot(surfaceInfo.normal,  payload3.direction), 0.001);
                
                     float NdotV = max(dot(surfaceInfo.normal, -dir), 0.000);
            float NdotL_rc = max(NdotL_r, 0.0001);
            float NdotH_r = max(dot(surfaceInfo.normal, H_r), 0.0);
            float VdotH_r = max(dot(-dir, H_r), 0.0);
            float3 F0 = isWater ? float3(0.02, 0.02, 0.02) : lerp(float3(0.04, 0.04, 0.04), surfaceInfo.color, surfaceInfo.metalness);
            float3 F_r = fresnelSchlick(VdotH_r, F0);
                 float3 kS =F_r;
                    float3 kD = float3(1.0,1.0,1.0) - kS;
                    kD *= (1.0 - surfaceInfo.metalness);
                      float diff = BurleyFrostbite(surfaceInfo.roughness, NdotL_rc,NdotV, VdotH_r);
                      sky *= SKYLIGHT_INTENSITY;
                    indirect += (kD * surfaceInfo.color * diff)  * sky * payload3.transmission * NdotL_rc;
                }
            }
            //indirect /= float(GI_BOUNCES);
            indirect /= float(INDIRECT_SAMPLES);
            specular /= float(SPECULAR_SAMPLES);
            float3 combinedLighting = indirect+specular;
            combinedLighting = lerp(combinedLighting, specular, surfaceInfo.metalness);
          
           
         
            

            
            lighting = BRDF(surfaceInfo.normal, normalize(-surfaceInfo.position), mainLightDir, sunlightColor.rgb, skylight, reflection, surfaceInfo, sunShadow, diffuseGI) ;

            //pointlights
            for (int i = 0; i < min(MAX_POINT_LIGHTS, g_view.cpuLightsCount); i++) {
                LightInfo lightInfo = inputLightsBuffer[i];
                LightData lightData = UnpackLight(lightInfo.packedData);

                float3 lDir = lightInfo.position - surfaceInfo.position;
                float lDist = length(lDir);
                lDir /= lDist;

                float attenuation = max(0, dot(surfaceInfo.normal, lDir)) / (lDist * lDist);
                float3 light = 0.0;
                float3 lightColor = lightData.intensity * lightData.color;
                float3 T = normalize(cross(
                        abs(lDir.z) < 0.999 ?
                        float3(0,0,1) :
                        float3(1,0,0),
                        lDir));

                float3 B = cross(lDir, T);
                const float sunRadius = POINT_LIGHT_SHADOW_RADIUS; 
                float3 shadowTransmission = float3(0.0, 0.0, 0.0);
                for(int i = 0; i < POINT_LIGHT_SHADOW_SAMPLES; i++) {
                    float2 Xi = frac(blueNoise.xy + float2(
                            i * 0.61803398875,
                            i * 0.38196601125));

                    float r = sunRadius * sqrt(Xi.x);
                    float theta = 2.0 * PI * Xi.y;

                    float2 disk = r * float2(
                        cos(theta),
                        sin(theta));

                    float3 sampleDir = normalize(
                        lDir +
                        disk.x * T +
                        disk.y * B);

                    RayDesc shadowRay;
                    shadowRay.Origin = surfaceInfo.position + 1.0e-4 * surfaceInfo.normal;
                    shadowRay.Direction = sampleDir;
                    shadowRay.TMin = 0.0;
                    shadowRay.TMax = max(lDist - 0.55, 0.0);

                    ShadowPayload payload;
                    TraceShadowRay(shadowRay, payload);
                    shadowTransmission = payload.transmission;
                }
                lightColor *= shadowTransmission;
                light = BRDFPoint(surfaceInfo.normal, normalize(-surfaceInfo.position), lDir, lightColor, surfaceInfo, attenuation) * 700;
                lighting += light;
            }
            float3 throughput;
            float3 emission;
            const bool isBlockBreakingOverlay = obj.flags == (kObjectInstanceFlagAlphaTestThresholdHalf | kObjectInstanceFlagTextureAlphaControlsVertexColor);

             if (obj.flags & (kObjectInstanceFlagSun | kObjectInstanceFlagMoon))
            {
                // Use additive blending for sun and moon
                throughput = 0;
                emission = 0;
                combinedLighting = 0;
                indirect = 0;
                break;
            }
            else if (isBlockBreakingOverlay) {
                // Use multiplicative blending for block breaking overlay geometry
                throughput = surfaceInfo.color;
                emission = 0;
                combinedLighting = 0;
                indirect = 0;
            }
            else {
                // Use alphablend for everything else
                throughput = 1 - surfaceInfo.alpha;

                emission =  lighting;
                combinedLighting =  combinedLighting;
                indirect *= surfaceInfo.alpha;
                
            }
            // Glint
            if (obj.flags & kObjectInstanceFlagGlint) {
                emission += (sin(3.0 * g_view.time) * 0.5 + 0.5) * (float3(77.0, 23.0, 255.0) / 255.0);
            }

            // Advance ray forward
            rayState.rayDesc.TMin = hitInfo.rayT ;

            // Accumulate surface emission and throughput
            rayState.color += (emission) * rayState.throughput;
            rayState.indirectDiffuse = indirect * rayState.throughput;

            rayState.throughput *=  throughput * payload4.transmission ;

            // Update other ray properties
            rayState.distance = hitInfo.rayT;
            rayState.motion = surfaceInfo.position - surfaceInfo.prevPosition;
            
        }
        else {
            break;
        }

        // Terminate rays that can't contribute anymore.
        if (max(rayState.throughput.r, max(rayState.throughput.g, rayState.throughput.b)) < 1e-4)
            break;
    }

    const float maxDistance = 65504; // Maximum value depth buffer can contain.
    if (max(rayState.throughput.r, max(rayState.throughput.g, rayState.throughput.b)) < 1e-4) {
        // Eventually hit solid object
        outputDistance = min(rayState.distance, maxDistance);
        outputMotion = rayState.motion;
    } else {
        // Eventually hit sky
        outputDistance = maxDistance;
        outputMotion = 0;
    }

    indirectDiffuse = rayState.indirectDiffuse;
    skyCol(rayState);
    VL_FOG(rayState.rayDesc.Origin, rayState.rayDesc.Direction, blueNoise.xyz, outputDistance, mainLightDir, rayState.color);

    return rayState.color;
}

#endif