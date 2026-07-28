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

    void RenderSky(inout RayState rayState)
    {
        if (all(rayState.throughput == 0)) return;

        float3 finalColor = skyScattering1(rayState.rayDesc.Direction);
        
        rayState.color += rayState.throughput * finalColor;
    }



    void RenderVanilla(HitInfo hitInfo, inout RayState rayState, in float4 noise, in float3 totalRadiance, in float3 directLight, in float3 rayColor, inout float firstHitDist, int bounceCount)
    {
        
        ObjectInstance objectInstance = objectInstances[hitInfo.objectInstanceIndex];
        GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, objectInstance);
        SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, objectInstance);
        firstHitDist = hitInfo.rayT;
        //surfaceInfo.color = pow(surfaceInfo.color, 2.2);
        
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
            //surfaceInfo.alpha = 0.f;
            surfaceInfo.color = 0;
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
        bool didReflect = false;
        float3 direction = rayState.rayDesc.Direction;
        float3 nextDirection;
        float3 N = surfaceInfo.normal;
        float3 V = -direction;
        float3 H = normalize(V + nextDirection);
        float VdotH = max(dot(H, V), 0.001);
        float3x3 tbn = tbnMatrix(N);
        float3 tangentView = mul(tbn, -direction);

        float roughness = max(surfaceInfo.roughness * surfaceInfo.roughness, 0.0);
        bool isWater = hitInfo.materialType == MATERIAL_TYPE_WATER;
        float3 F0 = isWater ? 0.02.xxx : lerp(float3(0.04, 0.04, 0.04), surfaceInfo.color, surfaceInfo.metalness); 
    float NdotV1 = max(dot(surfaceInfo.normal, V), 0.0001);

    // --- PROBABILITY 1: Macro-Boundary Fresnel (Using N) for Transparency Choice ---
    float3 F_boundary = fresnelSchlick(NdotV1, F0);
    // Use the boundary reflection energy to dictate if we reflect off the shell or pass through
    float transparencyReflectProbability = luminance(F_boundary);

    // --- PROBABILITY 2: Specular Microfacet Heuristic (Using your original math structure) ---
    // This is evaluated ahead of time to determine your standard opaque lobe balance
    float3 F_specular_estimate = fresnelSchlick(VdotH, F0); 
    float3 diffuseColor = surfaceInfo.color * (1.0 - surfaceInfo.metalness); 
    float diffEnergy = luminance(diffuseColor); 
    float specEnergy = luminance(F_specular_estimate); 
    float totalEnergy = diffEnergy + specEnergy; 

    float specularProbability = 1.0f; 
    if (totalEnergy > 0.0001f) { 
        specularProbability = specEnergy / totalEnergy; 
    } 
    //specularProbability = max(specularProbability, 0.25f); 
    specularProbability = lerp(specularProbability, 1.0f, surfaceInfo.metalness); 

    float3 nextThroughput = rayColor; 
    float pdf = 1.0; 
    bool isTransparentSurface = hitInfo.materialType == MATERIAL_TYPE_WATER || hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND; 
    bool rayRefractedGoesInside = false;
    // Apply emissive lighting.
        float3 emission = surfaceInfo.color * surfaceInfo.emissive * 700;

    totalRadiance += emission;
    // --- STAGE 1: FILTER TRANSPARENT PASS-THROUGH FIRST ---
    if (isTransparentSurface && !isCloud) { 
         if (Xi.x < specularProbability) { 
        // Standard Specular Lobe 
        float2 XiSpec = frac(noise.xy + float2(bounceCount * 0.12345, bounceCount * 0.98765)); 
        float3 microfacetNormal = SampleVNDFGGX(tangentView, roughness, XiSpec); 
        float3 tangentReflDir = reflect(-tangentView, microfacetNormal); 
        nextDirection = normalize(mul(tangentReflDir, tbn)); 
        
        float3 H = normalize(V + nextDirection); 
        float NdotL_r = max(dot(N, nextDirection), 0.0001); 
        float NdotV_r = max(dot(N, V), 0.0001); 
        float NdotH_r = max(dot(N, H), 0.0001); 
        float VdotH_r = max(dot(V, H), 0.0001); 
        
        float3 F_r = fresnelSchlick(VdotH_r, F0); 
        float D_r = D_GGX(NdotH_r, surfaceInfo.roughness); 
        float G_r = G_Smith(NdotV_r, NdotL_r, surfaceInfo.roughness); 
        float3 specWeight = ((F_r * D_r * G_r) / (4.0 * NdotV_r * NdotL_r)) + FdezAgueraMultipleScattering(NdotV_r, NdotL_r, surfaceInfo.roughness, F0); 
        
        float pdf_r = PDF_GGXVNDF(NdotV_r, NdotH_r, VdotH_r, surfaceInfo.roughness); 
        float combinedPdf = max(pdf_r, 1e-6); 
        
        rayColor *= (specWeight * NdotL_r) / (combinedPdf * specularProbability); 
    } 
    if (Xi.x > transparencyReflectProbability) {

            
            // Ray passes through into the refraction lobe.
            float IOR = isWater ? 1.333 : 1.5; 
            
            float3 refractionNormal = N;
            float eta = 1.0 / IOR;
            if (!hitInfo.frontFacing) {
               
                eta = IOR / 1.0;
            }

            float3 refracted = refract(direction, refractionNormal, eta); 
            
            if (dot(refracted, refracted) < 1e-8) { 
    // TOTAL INTERNAL REFLECTION (Only possible when leaving == true!)
    nextDirection = reflect(direction, N);
    
    // Crucial: TIR reflects 100% of light. Do not apply transmissionWeight reduction here!
    float TIR_probability = max(specularProbability, 1e-4); 
    rayColor *= 1.0 / TIR_probability; 
        }  else {
                nextDirection = refracted; 
                rayRefractedGoesInside = true;
            }

            // Balanced via the macroscopic transmission probability math cleanly
            float3 transmissionWeight = (1.0f - F_boundary); 
            float transmissionProbability = max(1.0f - transparencyReflectProbability, 1e-4); 
            rayColor *= transmissionWeight / transmissionProbability; 
        } 
    }
    // --- STAGE 2: STANDARD OPAQUE SURFACE LOBE BALANCING (UNTOUCHED) ---
    else if (Xi.x < specularProbability) { 
        // Standard Specular Lobe 
        float2 XiSpec = frac(noise.xy + float2(bounceCount * 0.12345, bounceCount * 0.98765)); 
        float3 microfacetNormal = SampleVNDFGGX(tangentView, roughness, XiSpec); 
        float3 tangentReflDir = reflect(-tangentView, microfacetNormal); 
        nextDirection = normalize(mul(tangentReflDir, tbn)); 
        
        float3 H = normalize(V + nextDirection); 
        float NdotL_r = max(dot(N, nextDirection), 0.0001); 
        float NdotV_r = max(dot(N, V), 0.0001); 
        float NdotH_r = max(dot(N, H), 0.0001); 
        float VdotH_r = max(dot(V, H), 0.0001); 
        
        float3 F_r = fresnelSchlick(VdotH_r, F0); 
        float D_r = D_GGX(NdotH_r, surfaceInfo.roughness); 
        float G_r = G_Smith(NdotV_r, NdotL_r, surfaceInfo.roughness); 
        D_r /= BRDF_PI;
        float3 specWeight = ((F_r * D_r * G_r) / (4.0 * NdotV_r * NdotL_r)) + FdezAgueraMultipleScattering(NdotV_r, NdotL_r, surfaceInfo.roughness, F0); 
        
        float pdf_r = PDF_GGX_Reflection(NdotV_r, NdotH_r, VdotH_r, surfaceInfo.roughness); 
        float combinedPdf = max(pdf_r, 1e-6); 
        
        totalRadiance *= (specWeight * NdotL_r); 
        rayColor = (specWeight * NdotL_r) * (combinedPdf * specularProbability);
    } 
    else { 
        // Standard Diffuse Lobe
        float2 XiDiffuse = frac(float2(Xi.y, noise.z) + float2(bounceCount * 0.23456, bounceCount * 0.65432)); 
        nextDirection = CosineHemisphereSampling(XiDiffuse, surfaceInfo.normal); 
        
        float NdotL_d = max(dot(N, nextDirection), 0.0001); 
        float NdotV_d = max(dot(N, V), 0.0001); 
        float3 H = normalize(V + nextDirection); 
        float VdotH_d = max(dot(V, H), 0.0001); 
        float3 F = fresnelSchlick(VdotH_d, F0); 
        
        float diffMultiplier = BurleyFrostbite(surfaceInfo.roughness, NdotL_d, NdotV_d, VdotH_d); 
        float3 kD = (1.0 - F) * (1.0 - surfaceInfo.metalness); 
        float3 diffuseBRDF = kD * surfaceInfo.color * (diffMultiplier / BRDF_PI); 
        
        float localDiffusePdf = max(PDF_CosineHemisphere(NdotL_d), 1e-4); 
        float diffuseProbability = 1.0 - specularProbability; 
        
        float3 weight_d = (diffuseBRDF * NdotL_d); 
        totalRadiance *= weight_d ; 
        rayColor *=  weight_d / localDiffusePdf;
    }
        

        shadowPayload payload; 
        RayDesc shadowRay; 
        shadowRay.Origin = offset_ray(surfaceInfo.position, surfaceInfo.normal); 
        shadowRay.Direction = SampleSunDirection(Xi, mainLightDir); 
        shadowRay.TMin = 0.0; 
        shadowRay.TMax = 10000; 
        TraceShadowRay(shadowRay, payload); 

        // 1. Calculate lighting vectors
        float3 L = mainLightDir; 
        float3 H1 = normalize(L + V); 

        float NdotL1 = max(dot(N, L), 0.0001); 
        float NdotV  = max(dot(N, V), 0.0001); 
        float NdotH  = max(dot(N, H1), 0.0001); 
        float VdotH1  = max(dot(V, H1), 0.0001); 

        // 2. Specular Component (Unchanged, matches your indirect evaluation)
        float3 F = fresnelSchlick(VdotH1, F0); 
        float D = D_GGX(NdotH, surfaceInfo.roughness); 
        float G = G_Smith(NdotV, NdotL1, surfaceInfo.roughness); 
        float3 specular = ((F * D * G) / max(4.0 * NdotL1 * NdotV, 1e-6)) 
        + FdezAgueraMultipleScattering(NdotV, NdotL1, surfaceInfo.roughness, F0); 

        // 3. Diffuse Component (Tied directly to your indirect math)
        float diffMultiplier = BurleyFrostbite(surfaceInfo.roughness, NdotL1, NdotV, VdotH);
        float3 kD1 = (1.0 - F) * (1.0 - surfaceInfo.metalness);
        float3 diffuse = kD1 * surfaceInfo.color * (diffMultiplier / BRDF_PI); 

        // 4. Combine both components to evaluate full BRDF response for the sun direction
        float3 brdf = diffuse + specular; 

        // 5. Final Integration
        float4 sunlightColor = getSunColor(float4(0.0, 0.0, 0.0, 0.0)) * 700; 
        sunlightColor.rgb *= sunlightColor.a;
        float pdfSun = max(PDF_SunCone(), 1e-4); 

        totalRadiance += sunlightColor.rgb * brdf * NdotL1 * payload.transmission / pdfSun;

        if (objectInstance.flags & kObjectInstanceFlagClouds)
        {
            // Clouds have vanilla shading baked into vertex color.
            surfaceInfo.alpha = 0.7;        // Match vanilla clouds alpha
        }

        

        

        
        uint mediaType = objectInstance.offsetPack5 >> 8; // See MEDIA_TYPE macros in Constants.hlsl.

        // Advance ray forward
      
        
        
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
        else if(isTransparentSurface)
        {
            float totalTransmission = 1 - surfaceInfo.alpha;
            rayColor = lerp(surfaceInfo.color * totalRadiance, surfaceInfo.color, totalTransmission);
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
        uint3 noiseCoord = uint3(
        pixelPos % uint2(256, 256),
        g_view.frameCount % 128);
        float2 rotation =
        blueNoiseTexture.Load(uint4(noiseCoord, 0)).xy;
        float4 blueNoise = blueNoiseTexture.Load(uint4(noiseCoord, 0));
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