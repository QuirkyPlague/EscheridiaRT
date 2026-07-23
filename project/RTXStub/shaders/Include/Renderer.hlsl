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
#include "brdf.hlsl"
#include "water.hlsl"


static const uint kBlueNoiseLayerMask = kBlueNoiseLayerCount - 1;

uint GetBlueNoiseLayerIndex(uint2 pixelCoord, uint frameSeed) {
    return (pixelCoord.x + pixelCoord.y + frameSeed) & kBlueNoiseLayerMask;
}

float4 GetBlueNoiseValue(uint2 pixelCoord) {
    uint layerIndex = GetBlueNoiseLayerIndex(pixelCoord, g_view.frameCount);
    return LoadBlueNoise(pixelCoord, layerIndex);
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
        instanceMask = 0xff & ~INSTANCE_MASK_SUN_OR_MOON;
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



void RenderVanilla(HitInfo hitInfo, inout RayState rayState, in float4 noise, in float3 totalRadiance, in float3 rayColor, int bounceCount)
{
    
    ObjectInstance objectInstance = objectInstances[hitInfo.objectInstanceIndex];
    GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, objectInstance);
    SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, objectInstance);

    bool inWater = g_view.cameraIsUnderWater;
    float2 Xi = frac(noise.xy + float2(bounceCount * 0.61803398875,bounceCount * 0.38196601125));
   
        float3 sunDir =  getDirectionToSun();
    float3 moonDir = -sunDir;

    float sunFade = saturate(sunDir.y);
    float moonFade = saturate(moonDir.y);

    float3 mainLightDir = sunFade > 0.0 ? sunDir : moonDir;

    if (hitInfo.materialType == MATERIAL_TYPE_WATER) {
        surfaceInfo.roughness = 0;
        //surfaceInfo.alpha = 0.0;
        surfaceInfo.color = inWater ? 0.0  : 0.0;
        const float waveSmoothness = WAVE_SMOOTHING;
                const float waveStrength = WAVE_INTENSITY;
                float3 worldPos = surfaceInfo.position - g_view.waveWorksOriginInSteveSpace;
                worldPos = worldPos - floor(worldPos / 1024) * 1024; // Bedrock may reset position every 1024 blocks, so we can only reliably calculate world position within 1024 blocks chunk.

                float3 waveNorm = surfaceInfo.normal;

                waveNorm = waveNormal(worldPos.xz, waveSmoothness, waveStrength);
                surfaceInfo.normal = inWater ? -waveNorm  : waveNorm;
    }


if (hitInfo.materialType == MATERIAL_TYPE_OPAQUE || hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST) surfaceInfo.alpha = 1;

    //surfaceInfo.color = pow(surfaceInfo.color, 2.2);
    float3 worldPos = surfaceInfo.position - g_view.waveWorksOriginInSteveSpace;
    worldPos = worldPos - floor(worldPos / 1024) * 1024; // Bedrock may reset position every 1024 blocks, so we can only reliably calculate world position within 1024 blocks chunk.

    float NdotL = max(dot(surfaceInfo.normal, mainLightDir),0.0001);

    rayState.rayDesc.TMin = 0.001;
    rayState.rayDesc.Origin = surfaceInfo.position;
    float3 direction = rayState.rayDesc.Direction;
    float3 N = surfaceInfo.normal;
    float3 V = -direction;
    float3x3 tbn = tbnMatrix(N);
    float3 tangentView = mul(tbn, -direction);

    float roughness = max(surfaceInfo.roughness * surfaceInfo.roughness, 0.001);
    bool isWater = hitInfo.materialType == MATERIAL_TYPE_WATER;
    float3 F0 = isWater ? 0.02.xxx : lerp(float3(0.04, 0.04, 0.04), surfaceInfo.color, surfaceInfo.metalness);
    float3 Fv = fresnelSchlick(max(dot(N, V), 0.0), F0);
    float3 kD = (1.0 - Fv) * (1.0 - surfaceInfo.metalness);

    float specularProbability =
    saturate(max(max(Fv.r, Fv.g), Fv.b));

specularProbability = max(specularProbability, 0.04);

// Metals always use the specular lobe.
specularProbability = lerp(specularProbability, 1.0, surfaceInfo.metalness);

    float3 nextDirection;
    float pdf = 1.0;
    bool isTransparentSurface = hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND || hitInfo.materialType == MATERIAL_TYPE_WATER;
    bool didReflect = false;
    
        if (isTransparentSurface)
    {
        if (Xi.x < specularProbability)
        {
            float2 XiSpec = frac(noise.xy + float2(bounceCount * 0.12345, bounceCount * 0.98765));
            float3 microfacetNormal = SampleVNDFGGX(tangentView, float2(roughness, roughness), XiSpec);
            float3 tangentReflDir = reflect(-tangentView, microfacetNormal);
            nextDirection = normalize(mul(tangentReflDir, tbn));

            float3 H = normalize(V + nextDirection);
            float NdotL_r = max(dot(N, nextDirection), 0.0001);
            float NdotV = max(dot(N, V), 0.0001);
            float NdotH_r = max(dot(N, H), 0.000);
            float VdotH_r = max(dot(V, H), 0.0);
            
            float3 Fh = fresnelSchlick(max(dot(H, V), 0.0001), F0);
            float3 F_r = fresnelSchlick(VdotH_r, F0);
            float D_r = D_GGX(NdotH_r, surfaceInfo.roughness);
            float G_r = G_Smith(NdotV, NdotL_r, surfaceInfo.roughness);
            float3 specWeight = ((F_r * D_r * G_r) / (4.0 * NdotV * NdotL_r))
                              + FdezAgueraMultipleScattering(NdotV, NdotL_r, surfaceInfo.roughness, F0);
           float pdf_r = PDF_GGXVNDF(NdotV, NdotH_r, VdotH_r, surfaceInfo.roughness);

// Include the probability of choosing the specular lobe.
float combinedPdf = max(pdf_r * specularProbability, 1e-6);

float3 weight_r = (specWeight * NdotL_r) / combinedPdf;

rayColor *= weight_r;
            didReflect = true;
        }
       else
{
    // Air <-> water IOR
    float etaI = 1.0;
    float etaT = isWater ? 1.333 : 1.5;

    float3 Nrefract = N;
    float eta = etaI / etaT;
    bool entering = dot(direction, geometryInfo.geometryNormal) < 0.0;
    // Leaving water
    if (dot(direction, N) > 0.0)
    {
        eta = etaT / etaI;
        Nrefract = -N;
    }

    float3 refracted = refract(direction, Nrefract, eta);

    // Total internal reflection
    if (dot(refracted, refracted) < 1e-8)
    {
        
        nextDirection = reflect(direction, N);
    }
    else
    {
        nextDirection = refracted;
    }

    float3 transmissionWeight = 1.0 - Fv;
    float transmissionProbability = max(1.0 - specularProbability, 1e-4);

    rayColor *= transmissionWeight / transmissionProbability;
}
    }
    else if (Xi.x < specularProbability)
    {
        float2 XiSpec = frac(noise.xy + float2(bounceCount * 0.12345, bounceCount * 0.98765));
        float3 microfacetNormal = SampleVNDFGGX(tangentView, float2(roughness, roughness), XiSpec);
        float3 tangentReflDir = reflect(-tangentView, microfacetNormal);
        nextDirection = normalize(mul(tangentReflDir, tbn));

        float3 H = normalize(V + nextDirection);
        float NdotL_r = max(dot(N, nextDirection), 0.0001);
        float NdotV = max(dot(N, V), 0.0001);
        float NdotH_r = max(dot(N, H), 0.000);
        float VdotH_r = max(dot(V, H), 0.000);

         float3 Fh = fresnelSchlick(max(dot(H, V), 0.00), F0);
            float3 F_r = fresnelSchlick(VdotH_r, F0);
            float D_r = D_GGX(NdotH_r, surfaceInfo.roughness);
            float G_r = G_Smith(NdotV, NdotL_r, surfaceInfo.roughness);
            float3 specWeight = ((F_r * D_r * G_r) / (4.0 * NdotV * NdotL_r))
                              + FdezAgueraMultipleScattering(NdotV, NdotL_r, surfaceInfo.roughness, F0);
            float pdf_r = PDF_GGXVNDF(NdotV, NdotH_r, VdotH_r, surfaceInfo.roughness);

// Include the probability of choosing the specular lobe.
float combinedPdf = max(pdf_r * specularProbability, 1e-6);

float3 weight_r = (specWeight * NdotL_r) / combinedPdf;

rayColor *= weight_r;
    }
    else
    {
        float2 XiDiffuse = frac(float2(Xi.y, noise.z) + float2(bounceCount * 0.23456, bounceCount * 0.65432));
        nextDirection = CosineHemisphereSampling(XiDiffuse, geometryInfo.geometryNormal);
        float3 H = normalize(direction + nextDirection);
        float NdotL_r = max(dot(N, nextDirection), 0.0001);
        float NdotV = max(dot(N, direction), 0.0001);
        float NdotH_r = max(dot(N, H), 0.0001);
        float VdotH_r = max(dot(direction, H), 0.0001);
        float diff = BurleyFrostbite(surfaceInfo.roughness, NdotL_r,NdotV, VdotH_r);
        float3 diffuseBRDF = (kD * surfaceInfo.color) / PI;
        float diffusePdf = max(PDF_CosineHemisphere(NdotL_r), 1e-4);
        pdf = max(diffusePdf * (1.0 - specularProbability), 1e-4);
        rayColor *= diffuseBRDF * NdotL_r / pdf;
    }
    
    

    rayState.rayDesc.Direction = nextDirection;
    rayState.rayDesc.Origin = offset_ray(surfaceInfo.position, nextDirection);
    

    shadowPayload payload;
    RayDesc shadowRay;
    shadowRay.Origin = offset_ray(surfaceInfo.position, surfaceInfo.normal);
    shadowRay.Direction = CosineHemisphereSamplingSun(Xi, mainLightDir);
    shadowRay.TMin = 0.0;
    shadowRay.TMax = 10000;

    TraceShadowRay(shadowRay, payload);
    // Vanilla-like shading
    float4 sunlightColor =  getSunColor(float4(0.0, 0.0, 0.0, 0.0)) * SUN_INTENSITY;

            float sunIntensity = sunlightColor.a;
            sunlightColor.rgb *= luminance(sunlightColor.rgb * sunIntensity);

    float3 light = sunlightColor.rgb * NdotL * payload.transmission;

   if (objectInstance.flags & kObjectInstanceFlagClouds)
    {
        totalRadiance = geometryInfo.color.rgb; // Clouds have vanilla shading baked into vertex color.
        //surfaceInfo.alpha = 1.0;        // Match vanilla clouds alpha
    }

    // Apply emissive lighting.
    float3 emission = surfaceInfo.color * surfaceInfo.emissive * 6550;

   
    totalRadiance += light * surfaceInfo.color;
    

    totalRadiance += emission;
    uint mediaType = objectInstance.offsetPack5 >> 8; // See MEDIA_TYPE macros in Constants.hlsl.

    // Advance ray forward
    // Total path distance for motion-vector and depth output.
    
    
    const bool isBlockBreakingOverlay = objectInstance.flags == (kObjectInstanceFlagAlphaTestThresholdHalf | kObjectInstanceFlagTextureAlphaControlsVertexColor);

float3 transmission = 1.0;

    if (objectInstance.flags & (kObjectInstanceFlagSun | kObjectInstanceFlagMoon))
    {
        // Use additive blending for sun and moon
        transmission = 0;
        totalRadiance = 0;
    }
    else if (isBlockBreakingOverlay) {
        // Use multiplicative blending for block breaking overlay geometry
        transmission = surfaceInfo.color;
        totalRadiance = 0;
    }
    else if (hitInfo.materialType == MATERIAL_TYPE_WATER) {
        // Use alphablend for alpha-blended surfaces only and tint transmitted light.
        float transmitAmount = 1.0 - surfaceInfo.alpha;
        float3 glassTransmittance = lerp(float3(1.0, 1.0, 1.0), surfaceInfo.color, transmitAmount);
        totalRadiance *= glassTransmittance;
        //transmission =  glassTransmittance;
    }
    else if(hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND) {
        // Use alphablend for alpha-blended surfaces only and tint transmitted light.
        float transmitAmount = 1.0 - surfaceInfo.alpha;
        float3 glassTransmittance = lerp(float3(1.0, 1.0, 1.0), surfaceInfo.color, transmitAmount);
        totalRadiance *= glassTransmittance;
        transmission *= lerp(surfaceInfo.color, 0.xxx, surfaceInfo.alpha);
    }
          

    // Glint
    if (objectInstance.flags & kObjectInstanceFlagGlint)
        totalRadiance += (sin(3.0 * g_view.time) * 0.5 + 0.5) * (float3(077, 23, 255) / 255.0);

    // Accumulate surface emission and throughput
    rayState.color += totalRadiance * rayState.throughput;
    rayState.throughput *= rayColor  * transmission;

    // Update other ray properties
    rayState.distance += hitInfo.rayT;
    rayState.motion += surfaceInfo.position - surfaceInfo.prevPosition;
    
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
    for (int i = 0; i < 8; i++)
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