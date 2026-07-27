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
#include "fog.hlsl"


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
    if (all(rayState.throughput == 0)) return;;

    float3 finalColor = skyScattering1(rayState.rayDesc.Direction);
    
    rayState.color += rayState.throughput * finalColor;
}



void RenderVanilla(HitInfo hitInfo, inout RayState rayState, in float4 noise, in float3 totalRadiance, in float3 directLight, in float3 rayColor, inout float firstHitDist, int bounceCount)
{
    
    ObjectInstance objectInstance = objectInstances[hitInfo.objectInstanceIndex];
    GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, objectInstance);
    SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, objectInstance);
    firstHitDist = hitInfo.rayT;
   
    float3 Wo = -normalize(rayState.rayDesc.Direction);
    bool inWater = g_view.cameraIsUnderWater;
    float2 Xi = frac(noise.xy + float2(bounceCount * 0.61803398875,bounceCount * 0.38196601125));
   
        float3 sunDir =  getDirectionToSun();
    float3 moonDir = -sunDir;

    float sunFade = saturate(sunDir.y);
    float moonFade = saturate(moonDir.y);

    float3 mainLightDir = sunFade > 0.0 ? sunDir : moonDir;

    if (hitInfo.materialType == MATERIAL_TYPE_WATER) {
        surfaceInfo.roughness =  0.0 ;
        //surfaceInfo.alpha = 0.0;
        surfaceInfo.color *= inWater ? 0.0  : 0.4;
        const float waveSmoothness = WAVE_SMOOTHING;
                const float waveStrength = WAVE_INTENSITY;
                float3 worldPos = surfaceInfo.position - g_view.waveWorksOriginInSteveSpace;
                worldPos = worldPos - floor(worldPos / 1024) * 1024; // Bedrock may reset position every 1024 blocks, so we can only reliably calculate world position within 1024 blocks chunk.
        
                float3 waveNorm = surfaceInfo.normal;

                waveNorm = waveNormal(worldPos.xz, waveSmoothness, waveStrength);
                surfaceInfo.normal = inWater ? -waveNorm : waveNorm;
    }

     bool isCloud = objectInstance.flags & kObjectInstanceFlagClouds;
if (hitInfo.materialType == MATERIAL_TYPE_OPAQUE || hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST) surfaceInfo.alpha = 1;

    
    float3 worldPos = surfaceInfo.position - g_view.waveWorksOriginInSteveSpace;
    worldPos = worldPos - floor(worldPos / 1024) * 1024; // Bedrock may reset position every 1024 blocks, so we can only reliably calculate world position within 1024 blocks chunk.

    float NdotL = max(dot(surfaceInfo.normal, mainLightDir),0.0001);

    rayState.rayDesc.TMin = 0.00;
    float3 direction = normalize(rayState.rayDesc.Direction);
    float3 N = surfaceInfo.normal;
    float3 V = -direction;

    
    float3x3 tbn = tbnMatrix(N);
    float3 tangentView = mul(tbn, -direction);

    float roughness = max(surfaceInfo.roughness * surfaceInfo.roughness, 0.0);
    bool isWater = hitInfo.materialType == MATERIAL_TYPE_WATER;
    float3 F0 = isWater ? 0.02.xxx : lerp(float3(0.04, 0.04, 0.04), surfaceInfo.color, surfaceInfo.metalness);
    float3 Fv = fresnelSchlick(max(dot(N, V), 0.0001), F0);
    float3 kD = (1.0 - Fv) * (1.0 - surfaceInfo.metalness);
    float specularProbability;
   
float3 diffuseColor =  surfaceInfo.color * (1.0 - surfaceInfo.metalness);




    float diffEnergy = luminance(diffuseColor);
float specEnergy = luminance(Fv);
float totalEnergy = diffEnergy + specEnergy;

// 4. Determine probability proportional to energy 
 specularProbability = 1.0f; // Fallback for perfectly black materials
if (totalEnergy > 0.0001f) {
    specularProbability = specEnergy / totalEnergy * surfaceInfo.alpha;
}

// 5. Clamp to ensure both paths are always explored slightly (avoids fireflies/dead zones)
//specularProbability = clamp(specularProbability, 0.05f, 0.1f);

//specularProbability = max(specularProbability, 0.65);

// Metals always use the specular lobe.
specularProbability = lerp(specularProbability, 1.0, surfaceInfo.metalness);





    float3 nextDirection;
     float3 nextThroughput = rayColor;
    float pdf = 1.0;
    bool isTransparentSurface = hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND || hitInfo.materialType == MATERIAL_TYPE_WATER ;
    bool didReflect = false;
    
        if (isTransparentSurface  && !isCloud)
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
            float NdotH_r = max(dot(N, H), 0.0001);
            float VdotH_r = max(dot(V, H), 0.0001);
            
            float3 Fh = fresnelSchlick(max(dot(H, V), 0.0001), F0);
            float3 F_r = fresnelSchlick(VdotH_r, F0);
            float D_r = D_GGX(NdotH_r, surfaceInfo.roughness);
            float G_r = G_Smith(NdotV, NdotL_r, surfaceInfo.roughness);
            float3 specWeight = ((F_r * D_r * G_r) / (4.0 * NdotV * NdotL_r))
                              + FdezAgueraMultipleScattering(NdotV, NdotL_r, surfaceInfo.roughness, F0);
           float pdf_r = PDF_GGXVNDF(NdotV, NdotH_r, VdotH_r, surfaceInfo.roughness);

            // Include the probability of choosing the specular lobe.
            float combinedPdf = max(pdf_r, 1e-6);

            float3 weight_r = (specWeight * NdotL_r) / (combinedPdf * specularProbability);

            rayColor *= weight_r;
            didReflect = true;
        }
       else
{
// 1. Assign correct base IORs depending on material type
float etaI = 1.0; // Air
float etaT = 1.0;

if (isWater) {
    etaT = 1.333;
} else { // Handle regular translucent voxels from Image 1
    etaT = 1.5;
}

// 2. Use a stable, raw geometric normal check.
// In Minecraft RTX, geometryNormal points OUT of the solid voxel face.
float cos_theta_i = dot(direction, geometryInfo.geometryNormal);

// If dot product is negative, ray is traveling AGAINST the outward normal (Entering)
// If dot product is positive, ray is traveling WITH the outward normal (Leaving)
bool leaving = cos_theta_i > 0.0;

float eta;
float3 Nrefract;

if (leaving) {
    // Ray is inside the voxel, exiting out into air
    eta = etaT / etaI; 
    
    // Ensure Nrefract points strictly against the ray direction for the API refract() call

    Nrefract =  (dot(direction, N) > 0.0) ? -N : N;
} else {
    // Ray is in the air, entering into the solid voxel
    eta = etaI / etaT; 
    
    // Ensure Nrefract points strictly against the ray direction
    Nrefract = (dot(direction, N) > 0.0) ? -N : N;
}

// 3. Perform the refraction
float3 refracted = refract(direction, Nrefract, eta);

// 4. Handle paths based on TIR success
if (dot(refracted, refracted) < 1e-8) { 
    // TOTAL INTERNAL REFLECTION (Only possible when leaving == true!)
    nextDirection = reflect(direction, N);
    
    // Crucial: TIR reflects 100% of light. Do not apply transmissionWeight reduction here!
    float TIR_probability = max(specularProbability, 1e-4); 
    rayColor *= 1.0 / TIR_probability; 
} 
else { 
    // REGULAR REFRACTION / TRANSMISSION (Glass becomes clear, Water lets you see inside)
    nextDirection = refracted; 
    
    // Compute your standard Fresnel blend for rays that successfully cross the boundary
    float3 transmissionWeight =  1.0 - Fv; 
    float transmissionProbability = max(1.0 - specularProbability, 1e-4); 
    
    rayColor *= transmissionWeight / transmissionProbability; 
}
}
    }
    else if (Xi.x < specularProbability)
    {
        
        float2 XiSpec = frac(noise.xy + float2(bounceCount * 0.12345, bounceCount * 0.98765));
        float3 microfacetNormal = SampleVNDFGGX(tangentView, float2(roughness, roughness), XiSpec);
        float3 tangentReflDir = reflect(-tangentView, microfacetNormal);
        nextDirection = normalize(mul(tangentReflDir, tbn));

        float3 H = (V + nextDirection);
        float NdotL_r = max(dot(N, nextDirection), 0.0001);
        float NdotV = max(dot(N, V), 0.0001);
        float NdotH_r = max(dot(N, H), 0.001);
        float VdotH_r = max(dot(V, H), 0.001);

         float3 Fh = fresnelSchlick(max(dot(N, V), 0.00), F0);
            float3 F_r = fresnelSchlick(NdotV, F0);
            float D_r = D_GGX(NdotH_r, surfaceInfo.roughness);
            float G_r = G_Smith(NdotV, NdotL_r, surfaceInfo.roughness);
            float3 specWeight = ((F_r * D_r * G_r) / (4.0 * NdotV * NdotL_r))
                              + FdezAgueraMultipleScattering(NdotV, NdotL_r, surfaceInfo.roughness, F0);
              float pdf_r = PDF_GGXVNDF(NdotV, NdotH_r, VdotH_r, surfaceInfo.roughness);

            // Include the probability of choosing the specular lobe.
            float combinedPdf = max(pdf_r, 1e-6);

            float3 weight_r = (specWeight * NdotL_r) / (combinedPdf * specularProbability);

            rayColor *= weight_r;
    }
    else
    {
       // Generate a clean noise seed for diffuse sampling
float2 XiDiffuse = frac(float2(Xi.y, noise.z) + float2(bounceCount * 0.23456, bounceCount * 0.65432)); 

// Use the shading normal N for standard sampling alignment

nextDirection = CosineHemisphereSampling(XiDiffuse, N); 

float NdotL_d = max(dot(N, nextDirection), 0.0001);
float NdotV   = max(dot(N, V), 0.0001); // V = -direction

float3 H      = normalize(V + nextDirection);
float NdotH_d = max(dot(N, H), 0.0001);
float VdotH_d = max(dot(V, H), 0.0001);

// 1. Calculate the Burley (Disney) diffuse modification factor
float diffMultiplier = BurleyFrostbite(surfaceInfo.roughness, NdotL_d, NdotV, VdotH_d);

// 2. Properly assemble the diffuse BRDF (dividing by PI exactly once)
float3 diffuseBRDF = kD * surfaceInfo.color * (diffMultiplier / 3.14159265f);

// 3. Compute the analytical Cosine PDF for this specific direction
float localDiffusePdf = max(PDF_CosineHemisphere(NdotL_d), 1e-4);

// 4. Incorporate the selection probability of choosing the diffuse lobe
float diffuseProbability = 1.0 - specularProbability;

// 5. Final Monte Carlo Weight: (BRDF * Cosine) / (Sampling PDF * Choice PDF)
float3 weight_d = (diffuseBRDF * NdotL_d) / (localDiffusePdf * diffuseProbability);

// Multiply the tracking ray throughput by this step's weight
rayColor *= weight_d;

// Optional: If your ray tracking depends on a global PDF property, update it here
pdf = localDiffusePdf * diffuseProbability; 
    }
    

   shadowPayload payload; 
RayDesc shadowRay; 
shadowRay.Origin = offset_ray(surfaceInfo.position, surfaceInfo.normal); 
shadowRay.Direction = SampleSunDirection(Xi, mainLightDir); 
shadowRay.TMin = 0.0; 
shadowRay.TMax = 10000; 
TraceShadowRay(shadowRay, payload); 

// 1. Calculate lighting vectors
float3 L = shadowRay.Direction; 
float3 H = normalize(L + V); 

float NdotL1 = max(dot(N, L), 0.0001); 
float NdotV  = max(dot(N, V), 0.0001); 
float NdotH  = max(dot(N, H), 0.0001); 
float VdotH  = max(dot(V, H), 0.0001); 

// 2. Specular Component (Unchanged, matches your indirect evaluation)
float3 F = fresnelSchlick(VdotH, F0); 
float D = D_GGX(NdotH, surfaceInfo.roughness); 
float G = G_Smith(NdotV, NdotL1, surfaceInfo.roughness); 
float3 specular = ((F * D * G) / max(4.0 * NdotL1 * NdotV, 1e-6)) 
                + FdezAgueraMultipleScattering(NdotV, NdotL1, surfaceInfo.roughness, F0); 

// 3. Diffuse Component (Tied directly to your indirect math)
float diffMultiplier = BurleyFrostbite(surfaceInfo.roughness, NdotL1, NdotV, VdotH);

float3 diffuse = kD * surfaceInfo.color * (diffMultiplier / 3.14159265f); 

// 4. Combine both components to evaluate full BRDF response for the sun direction
float3 brdf = diffuse + specular; 

// 5. Final Integration
float4 sunlightColor = getSunColor(float4(0.0, 0.0, 0.0, 0.0)) * 500; 
sunlightColor.rgb *= sunlightColor.a;
float pdfSun = max(PDF_SunCone(), 1e-4); 

directLight += sunlightColor.rgb * brdf * NdotL1 * payload.transmission / pdfSun;

   if (objectInstance.flags & kObjectInstanceFlagClouds)
    {
        // Clouds have vanilla shading baked into vertex color.
        surfaceInfo.alpha = 0.7;        // Match vanilla clouds alpha
    }

    // Apply emissive lighting.
    float3 emission = surfaceInfo.color * surfaceInfo.emissive * 550;

   
    totalRadiance += directLight;
    

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
    else if(isWater)
    {
        totalRadiance *= surfaceInfo.color * surfaceInfo.alpha;
    }
    else if(hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND && !isCloud && !isWater) {
        // Use alphablend for alpha-blended surfaces only and tint transmitted light.
        float transmitAmount = 1.0 - surfaceInfo.alpha;
        float3 glassTransmittance = lerp(float3(1.0, 1.0, 1.0), surfaceInfo.color, transmitAmount);
        totalRadiance *=   surfaceInfo.alpha;
        transmission = lerp(surfaceInfo.color, 0.xxx, surfaceInfo.alpha);
    }
          

    // Glint
    if (objectInstance.flags & kObjectInstanceFlagGlint)
        totalRadiance += (sin(3.0 * g_view.time) * 0.5 + 0.5) * (float3(077, 23, 255) / 255.0);

    // Accumulate surface emission and throughput
    rayState.color += totalRadiance * rayState.throughput;

    rayState.throughput *= rayColor  * transmission;

    rayState.rayDesc.Direction = nextDirection;
    rayState.rayDesc.Origin = offset_ray(surfaceInfo.position, nextDirection);
    // Update other ray properties
    rayState.distance += hitInfo.rayT;
    rayState.motion += surfaceInfo.position - surfaceInfo.prevPosition;
    
}


float3 RenderRay(RayDesc rayDesc, out float outputDistance, out float3 outputMotion, in float2 pixelPos, inout float firstHitDist)
{
   
    RayQuery<RAY_FLAG_NONE> q;
    RayState rayState;
    rayState.Init();
    rayState.rayDesc = rayDesc;

    float4 blueNoise = GetBlueNoiseValue(pixelPos);
    float3 totalRadiance = 0;
    float3 directLight = 0;
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
  
          
            RenderVanilla(hitInfo, rayState, blueNoise, totalRadiance, directLight, rayColor, firstHitDist, i);
            // Russian Roulette
			
        }
        else
        {
            RenderSky(rayState);
            break;
        }

        if (i > 3) {
				float p = max(rayState.throughput.x, max(rayState.throughput.y, rayState.throughput.z));
				if (blueNoise.x > p) {
					break;
				}

				rayState.throughput /= p;
			}
        // Terminate rays that can't contribute anymore.
        if (all(rayState.throughput == 0))
            break;
    }

    const float maxDistance = 65504; // Maximum value depth buffer can contain.
    if (all(rayState.throughput == 0)) {
        // Eventually hit solid object
        outputDistance = min(rayState.distance, maxDistance);
        firstHitDist = min(firstHitDist, maxDistance);
        outputMotion = rayState.motion;
    } else {
        // Eventually hit sky
        outputDistance = maxDistance;
        firstHitDist = maxDistance;
        outputMotion = 0;
    }

    //RenderSky(rayState);
    
        float3 sunDir =  getDirectionToSun();
    float3 moonDir = -sunDir;

    float sunFade = saturate(sunDir.y);
    float moonFade = saturate(moonDir.y);

    float3 mainLightDir = sunFade > 0.0 ? sunDir : moonDir;

    //VL_FOG(rayState.rayDesc.Origin, rayState.rayDesc.Direction, blueNoise.xyz, outputDistance, mainLightDir, rayState.color);
    return rayState.color;
}

#endif