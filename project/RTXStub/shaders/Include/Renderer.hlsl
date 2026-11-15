// This is from the MCRTX Shader template project https://github.com/veka0/mcrtx-shader-template?tab=readme-ov-file 
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
    #include "Resampling.hlsl"
    #include "sky.hlsl"
    #include "tonemapping.hlsl"
    #include "brdf.hlsl"
    #include "water.hlsl"
    #include "fog.hlsl"
    #include "DirectLighting.hlsl"
    
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
        bool hitWater;
        bool inSSSMedium;
        float sssMediumThickness;
        float3 sssSlabOrigin;
        float3 sssSlabNormal;
        uint sssSlabInstance;
        uint sssSlabQuad;
        float3 sssSigmaS;
        float3 sssSigmaT;
        bool scattered;

        void Init()
        {
            color = 0;
            throughput = 1;
            distance = 0;
            motion = 0;
            instanceMask = 0xff & ~INSTANCE_MASK_SUN_OR_MOON;
            hitWater = false;
            inSSSMedium = false;
            sssMediumThickness = 0;
            sssSlabOrigin = 0;
            sssSlabNormal = 0;
            sssSlabInstance = 0;
            sssSlabQuad = 0;
            sssSigmaS = 0;
            sssSigmaT = 0;
            scattered = false;
        }
    };

    void RenderSky(inout RayState rayState, in RayDesc ray, inout PathRNG rng, bool isPrimaryRay)
    {
        if (all(rayState.throughput == 0)) return;
        
        //float3 finalColor = skyScattering1(rayState.rayDesc.Direction);
        
        float3 sunDir =  getTrueDirectionToSun();
        float3 moonDir = getTrueDirectionToMoon();

        float sunFade = saturate(sunDir.y);
        float moonFade = saturate(moonDir.y);

        float3 mainLightDir = sunDir;

        float4 sunColor = inEnd ? float4(END_SUN_COLOR, END_SUN_INTENSITY) : getSunColor(float4(0.xxxx));
        
        float sunEv = 1.0 * exp2(sunColor.a * SUN_INTENSITY);
        float skyLuminanceMult = inEnd ? END_RAYLEIGH_MULT : RAYLEIGH_MULT;
        float3 sunLuminance = 0.00045 * exp2( sunColor.a * SUN_INTENSITY);
        float sunStrength = luminance( sunColor.rgb * sunLuminance);
        mainLightDir = inEnd ? END_SUN_DIRECTION : mainLightDir;
        // The atmosphere function adds the planet radius internally; pass the
        // existing 1000-meter offset converted to kilometers.
        const float minSunIntensity = 3.448;
        sunStrength = max(sunStrength, minSunIntensity); // This allows for the sun to have an effect on the sky even after sunset
        float3 worldPos = float3(0,500,0);
        float3 rayOriginKm = worldPos * 0.001;
        
        float3 finalColor = RenderHillaireAnalytical(
        rayOriginKm,
        rayState.rayDesc.Direction,
        mainLightDir,
        sunStrength,
        rng,true,isPrimaryRay);
        
        
        

        #if WHITE_FURNACE == 1
            finalColor = float3(1.0.xxx);
        #endif
        
        rayState.color += rayState.throughput * finalColor;
    }

    void RenderVanilla(HitInfo hitInfo, inout RayState rayState, inout PathRNG rng, in float3 totalRadiance, in float3 directLight, in float3 rayColor, inout float firstHitDist, int bounceCount, in RayDesc ray)
    {
        
        ObjectInstance objectInstance = objectInstances[hitInfo.objectInstanceIndex];
        GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, objectInstance);
        SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, objectInstance);
        
        #if WHITE_FURNACE == 1
            float3 direction = normalize(rayState.rayDesc.Direction);
            float3 V = -direction;
            float3 N =  surfaceInfo.normal;
            float3 ng = geometryInfo.geometryNormal;
            // normal flipping 
            if(dot(ng,V) < 0.0)
            {
                ng = -ng;
            }
            if(dot(N,V) < 0.0)
            {
                N = -N;
            }
            float3 effectiveH = normalize(lerp(N, N + V, surfaceInfo.roughness * surfaceInfo.roughness));
            float3 kS = fresnelSchlick(max(dot(V,N), 0.001), surfaceInfo.F0);
            float3 T; float3 B;
            BuildOrthonormalBasis(N, T, B);
            float3 tangentView = float3(dot(V, T),dot(V, B),dot(V, N));

            
            

            float specularProbability = saturate(luminance(kS));

            float diffuseWeight = luminance(surfaceInfo.color);
            float specularWeight = specularProbability;
            float diffuseContribution =
            (1.0 - specularProbability) * diffuseWeight;

            specularProbability =
            specularWeight /
            max(specularWeight + diffuseContribution, 1e-5);

            specularProbability = clamp(specularProbability, 0.04, 0.96);
            specularProbability = lerp(
            specularProbability,
            1.0,
            surfaceInfo.metalness
            );

            float xi_lobe = NextFloat(rng);
            float3 nextDirection;
            if (xi_lobe < specularProbability)
            {
                // --- EVALUATE SPECULAR PATH ---
                float2 XiSpecular = NextFloat2(rng);
                float3 microfacetNormal = SampleVNDFGGX(tangentView, surfaceInfo.roughness * surfaceInfo.roughness, XiSpecular); 
                float3 tangentReflDir = reflect(-tangentView, microfacetNormal); 
                nextDirection = normalize(tangentReflDir.x * T +tangentReflDir.y * B +tangentReflDir.z * N);
                float3 H = normalize(microfacetNormal.x * T + microfacetNormal.y * B + microfacetNormal.z * N); 
                
                if (dot(N, nextDirection) > 0.0)
                {
                    float3 specWeight = specularBRDFGGX(N, nextDirection, V, surfaceInfo.F0, H, surfaceInfo.roughness, specularProbability);
                    rayState.throughput *= specWeight;
                    rayState.rayDesc.Direction = nextDirection;
                }
                else
                {
                    rayState.throughput = float3(0.0, 0.0, 0.0); // Absorbed/invalid ray
                }
            }
            else
            {
                float2 XiDiffuse = NextFloat2(rng);
                #if DIFFUSE_METHOD == 1
                    float3 T, B;
                    BuildOrthonormalBasis(N, T, B);
                    float3 wo_local = float3(dot(V, T),dot(V, B),dot(V, N));

                    float4 EONSample = sample_EON(wo_local,surfaceInfo.roughness,XiDiffuse.x,XiDiffuse.y);
                    float3 wi_local = EONSample.xyz;
                    float localDiffusePdf = max(EONSample.w, 1e-4);
                    nextDirection =T * wi_local.x + B * wi_local.y + N * wi_local.z;

                    nextDirection = normalize(nextDirection);
                    float rawNdotL = dot(N, nextDirection);
                    if (rawNdotL <= 0.0)
                    {
                        rayState.throughput = 0;
                    }
                    float NdotL_d = max(dot(N, nextDirection), 0.0001); 
                    float NdotV_d = max(dot(N, V), 0.0001); 
                    float3 H = normalize(V + nextDirection); 
                    float VdotH_d = max(dot(V, H), 0.0001);
                    float LdotH = max(dot(nextDirection,H), 0.001);
                    float3 rho = surfaceInfo.color * (1.0 - surfaceInfo.metalness);
                    float3 F = fresnelSchlick(LdotH, surfaceInfo.F0);
                    float3 diffuseBRDF = (1.0 - F) * f_EON(rho, surfaceInfo.roughness, wi_local, wo_local, USE_ACCURATE_DIFFUSE_BRDF); 
                    
                    float3 weight_d = ((diffuseBRDF * NdotL_d) / (localDiffusePdf * max(1.0 - specularProbability, 1e-4))); 
                    rayState.rayDesc.Direction = nextDirection;
                    rayState.throughput *= weight_d; 
                #elif DIFFUSE_METHOD == 2
                    nextDirection = CosineHemisphereSampling(XiDiffuse, N); 
                    rayState.throughputr *= diffuseBRDFHammonConserving(N, nextDirection, V, surfaceInfo.color, surfaceInfo.metalness,surfaceInfo.roughness, surfaceInfo.F0, specularProbability); 
                    rayState.rayDesc.Direction = nextDirection;
                #else
                    // Default to Lambertian if no method is specified
                    nextDirection = CosineHemisphereSampling(XiDiffuse, N); 
                    rayState.rayDesc.Direction = nextDirection;
                    rayState.throughput *= diffuseBRDFLambert(N, nextDirection, V, surfaceInfo.color, surfaceInfo.metalness,surfaceInfo.roughness, surfaceInfo.F0, specularProbability); 
                #endif  
            }

            // 4. Trace the ray onward
            rayState.rayDesc.Origin = offset_ray(surfaceInfo.position, ng);
            rayState.distance += hitInfo.rayT;
            rayState.motion += surfaceInfo.position - surfaceInfo.prevPosition;
        #else
            bool inWater = rayState.hitWater;

            float2 Xi = NextFloat2(rng);
            float2 XiSpec = NextFloat2(rng);
            float2 XiDiffuse = NextFloat2(rng);
            float3 sunDir =  getDirectionToSun();
            float3 moonDir = -sunDir;

            float sunFade = saturate(sunDir.y);
            float moonFade = saturate(moonDir.y);

            float3 mainLightDir = sunFade > 0.0 ? sunDir : moonDir;
            mainLightDir = inEnd ? END_SUN_DIRECTION : mainLightDir;
            float3 endTwinSunDir = END_TWIN_SUN_DIRECTION;
            float3 direction = normalize(rayState.rayDesc.Direction);
            float flatPlaneY = surfaceInfo.position.y;

            float parallaxHeight = 0.0f;
            float waterIOR = 1.333f;
            if (hitInfo.materialType == MATERIAL_TYPE_WATER) 
            {
                WaterMaterial waterMat;
                waterMat.SetUp(surfaceInfo, geometryInfo, direction, bounceCount, firstHitDist, parallaxHeight, ray);
                waterIOR = waterMat.IOR.x;
                // ensure the value cannot go negative so the ray always starts at the surface
                parallaxHeight = max(1e-4, parallaxHeight);
            }
            bool isCloud = objectInstance.flags & kObjectInstanceFlagClouds;
            if (hitInfo.materialType == MATERIAL_TYPE_OPAQUE || hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST) surfaceInfo.alpha = 1;

            float NdotL = max(dot(surfaceInfo.normal, mainLightDir),0.0001);

            float3 nextDirection;
            float3 N = surfaceInfo.normal;
            float3 V = -direction;
            float3 ng = geometryInfo.geometryNormal;
            // normal flipping 
            if(dot(ng,V) < 0.0)
            {
                ng = -ng;
            }
            if(dot(N,V) < 0.0)
            {
                N = -N;
            }
            N = FixShadingNormal(ng, N);
            float3 T; float3 B;
            BuildOrthonormalBasis(N, T, B);
            float3 tangentView = float3(dot(V, T),dot(V, B),dot(V, N));

            bool isWater = hitInfo.materialType == MATERIAL_TYPE_WATER; 
            float3 F0 = surfaceInfo.F0; 
            
            /*
            #if DO_RAIN_WETNESS
                float rainLevel = getBiomeAdjustedRainLevel();
                if(bounceCount == 0 && rainLevel > 0)
                {
                    // Sample a random direction around the surface normal intersection. 
                    // We need to do cast a shadow ray to determine whether or not we hit a sky pixel 
                    float2 xi = NextFloat2(rng);

                    float phi = 6.2831853 * xi.x;
                    float cosTheta = lerp(1.0, cos(0.35), xi.y);
                    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);

                    float3 rainSampleDir = normalize(float3(cos(phi) * sinTheta,cosTheta,sin(phi) * sinTheta));
                    // Set up the ray
                    shadowPayload rainOcclusion;
                    RayDesc rainSampleRay;
                    rainSampleRay.Origin = offset_ray(surfaceInfo.position, ng);
                    rainSampleRay.Direction = rainSampleDir;
                    rainSampleRay.TMin = 0.0;
                    rainSampleRay.TMax = 1000;

                    TraceShadowRay(rainSampleRay, rainOcclusion);

                    surfaceInfo.roughness = lerp(surfaceInfo.roughness, 0.0, rainLevel *  (float)rainOcclusion.transmission);
                    N = lerp(N, ng, rainLevel * (float)rainOcclusion.transmission);
                } 
            #endif
            */
            
            float roughness = max(surfaceInfo.roughness * surfaceInfo.roughness, 0.0);
            float3 effectiveH = normalize(lerp(N, N + V, surfaceInfo.roughness * surfaceInfo.roughness));
            float3 kS = fresnelSchlick(max(dot(V,effectiveH), 0.001), F0);
            
            float specularProbability = saturate(luminance(kS));

            float diffuseWeight = luminance(surfaceInfo.color);
            float specularWeight = specularProbability;
            float diffuseContribution = (1.0 - specularProbability) * diffuseWeight;

            specularProbability = specularWeight /max(specularWeight + diffuseContribution, 1e-5);

            specularProbability = clamp(specularProbability, 0.04, 0.96);
            specularProbability = lerp(specularProbability,1.0,surfaceInfo.metalness);

            float alphaBlendOpacity = (surfaceInfo.alpha);
            bool isFullyOpaqueAlphaBlend = hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND && surfaceInfo.alpha >= 0.9999f;
            bool isTransparentSurface = hitInfo.materialType == MATERIAL_TYPE_WATER || (hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND && !isFullyOpaqueAlphaBlend);
            
            bool rayRefractedGoesInside = false;

            // A diffuse interface leads into a chromatic random-walk medium.
            bool isAlphaTest = hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST;
            float sssDistance = isAlphaTest ? 0.15 : 0.35;
            bool isSSSVolume = surfaceInfo.subsurface > 0.0 && !isCloud && !isTransparentSurface && !inWater && (hitInfo.materialType == MATERIAL_TYPE_OPAQUE || hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST);

            // Split non-specular energy between volumetric SSS and standard diffuse reflection.
            
            float sssMaxProb =  saturate(surfaceInfo.subsurface * 0.65);
            float sssProbability = isSSSVolume ? (1.0 - specularProbability) * sssMaxProb : 0.0;
            float diffuseProbability = isTransparentSurface ? 0.0f : max((1.0 - specularProbability - sssProbability), 1e-4);
            float sssEnergyFraction = isSSSVolume ? sssMaxProb : 0.0;
            float diffuseEnergyScale = 1.0 - sssEnergyFraction;
            float directDiffuseWeight = isTransparentSurface
            ? max((1.0f - specularProbability) * surfaceInfo.alpha, 1e-4)
            : diffuseEnergyScale;
            if (isTransparentSurface && !isCloud)
            {
                float eta = isWater
                    ? (inWater ? waterIOR : 1.0f / waterIOR)
                    : (hitInfo.frontFacing ? (1.0f / 1.5f) : 1.5f);
                float alpha = max(roughness, 0.0001f);
                float3 microfacetNormalTS = SampleVNDFGGX(tangentView, alpha, XiSpec);
                float3 microfacetNormal = normalize(microfacetNormalTS.x * T + microfacetNormalTS.y * B + microfacetNormalTS.z * N);

                float cosThetaT;
                float F_diel = DielectricFresnel(max(dot(V, microfacetNormal), 0.0f), eta, cosThetaT);
                float opacity = saturate(surfaceInfo.alpha);
                float transmissionProbability = (1.0f - F_diel) * (1.0f - opacity);

                if (Xi.x < F_diel)
                {
                    nextDirection = reflect(direction, microfacetNormal);
                    if (dot(N, nextDirection) <= 0.0f || dot(ng, nextDirection) <= 0.0f)
                    {
                        rayColor = 0.0;
                    }
                    else
                    {
                        rayColor *= G1_SmithGGX(dot(N, nextDirection), surfaceInfo.roughness);
                    }
                }
                else if (Xi.x < F_diel + transmissionProbability)
                {
                    nextDirection = refract(direction, microfacetNormal, eta);
                    if (dot(nextDirection, nextDirection) < 1e-6f ||
                        dot(N, nextDirection) >= 0.0f || dot(ng, nextDirection) >= 0.0f)
                    {
                        rayColor = 0.0;
                    }
                    else
                    {
                        float masking = G1_SmithGGX(-dot(N, nextDirection), surfaceInfo.roughness);
                        // Radiance transport scales by (etaIncident / etaTransmitted)^2.
                        float3 transmissionTint = isWater ? 1.0.xxx : GetAlphaBlendTransmissionTint(surfaceInfo.color);
                        rayColor *= transmissionTint * masking * eta * eta;
                        if (isWater)
                        {
                            rayState.hitWater = !inWater;
                        }
                    }
                }
                else
                {
                    nextDirection = CosineHemisphereSampling(XiDiffuse, N);
                    if (dot(ng, nextDirection) <= 0.0f)
                    {
                        rayColor = 0.0;
                    }
                    else
                    {
                        rayColor *= diffuseBRDFLambert(N, nextDirection, V, surfaceInfo.color, surfaceInfo.metalness, surfaceInfo.roughness, surfaceInfo.F0, 0.0f) / (1.0f - F_diel);
                    }
                }
            }
            else if (Xi.x < specularProbability)
            {
                float3 microfacetNormal = SampleVNDFGGX(tangentView, roughness, XiSpec); 
                float3 tangentReflDir = reflect(-tangentView, microfacetNormal); 
                nextDirection = normalize(tangentReflDir.x * T +tangentReflDir.y * B +tangentReflDir.z * N);
                float3 H = normalize(microfacetNormal.x * T + microfacetNormal.y * B + microfacetNormal.z * N); 
                rayColor *= specularBRDFGGX(N, nextDirection, V, F0,H, surfaceInfo.roughness, specularProbability);
            }
            else if (Xi.x < specularProbability + sssProbability)
            {
                // Use a diffuse boundary transition instead of Snell refraction.
                // The cosine factor cancels the cosine-hemisphere directional PDF.
                nextDirection = CosineHemisphereSampling(NextFloat2(rng), -ng);
                float3 sssBoundaryWeight = (1.0 - kS) * (1.0 - surfaceInfo.metalness) * sssEnergyFraction;
                rayColor *= sssBoundaryWeight / sssProbability;
                rayState.inSSSMedium = true;

                // Chiang et al. (2016) fit for apparent to single-scattering albedo.
                float3 apparentColor = saturate(surfaceInfo.color);
                float3 singleScatteringAlbedo = 1.0 - exp(-5.09406 * apparentColor+ 2.61188 * apparentColor * apparentColor- 4.31805 * apparentColor * apparentColor * apparentColor);
                // Near-constant scattering with stronger absorption in dark channels.
                rayState.sssSigmaT = 1.0 / (sssDistance * max(singleScatteringAlbedo, 0.05));
                rayState.sssSigmaS = rayState.sssSigmaT * singleScatteringAlbedo;
                rayState.sssMediumThickness = isAlphaTest ? 0.1 : 0.0;
                rayState.sssSlabOrigin = surfaceInfo.position;
                rayState.sssSlabNormal = -ng;
                rayState.sssSlabInstance = hitInfo.objectInstanceIndex;
                rayState.sssSlabQuad = hitInfo.primitiveId / 2;
            }
            else
            { 
                #if DIFFUSE_METHOD == 1
                    float3 T, B;
                    BuildOrthonormalBasis(N, T, B);
                    float3 wo_local = float3(dot(V, T),dot(V, B),dot(V, N));

                    float4 EONSample = sample_EON(wo_local,surfaceInfo.roughness,XiDiffuse.x,XiDiffuse.y);
                    float3 wi_local = EONSample.xyz;
                    float localDiffusePdf = max(EONSample.w, 1e-4);
                    nextDirection =T * wi_local.x + B * wi_local.y + N * wi_local.z;

                    nextDirection = normalize(nextDirection);
                    float rawNdotL = dot(N, nextDirection);
                    if (rawNdotL <= 0.0)
                    {
                        rayColor = 0.0;
                    }
                    float NdotL_d = max(dot(N, nextDirection), 0.0001); 
                    float NdotV_d = max(dot(N, V), 0.0001); 
                    float3 H = normalize(V + nextDirection); 
                    float VdotH_d = max(dot(V, H), 0.0001);
                    float LdotH = max(dot(nextDirection,H), 0.001);
                    float3 rho = surfaceInfo.color * (1.0 - surfaceInfo.metalness);
                    float3 F = fresnelSchlick(LdotH, surfaceInfo.F0);
                    float3 diffuseBRDF = (1.0 - F) * f_EON(rho, surfaceInfo.roughness, wi_local, wo_local, USE_ACCURATE_DIFFUSE_BRDF) * diffuseEnergyScale; 
                    
                    float3 weight_d = ((diffuseBRDF * NdotL_d) / (localDiffusePdf * max(diffuseProbability, 1e-4))); 

                    rayColor *= weight_d; 
                #elif DIFFUSE_METHOD == 2
                    nextDirection = CosineHemisphereSampling(XiDiffuse, N); 
                    float3 diffuseWeight = diffuseBRDFHammonConserving(N, nextDirection, V, surfaceInfo.color, surfaceInfo.metalness,surfaceInfo.roughness, surfaceInfo.F0, 1.0 - diffuseProbability);
                    diffuseWeight *= diffuseEnergyScale;
                    rayColor *= diffuseWeight;
                #else
                    // Default to Lambertian if no method is specified
                    nextDirection = CosineHemisphereSampling(XiDiffuse, N); 
                    float3 diffuseWeight = diffuseBRDFLambert(N, nextDirection, V, surfaceInfo.color, surfaceInfo.metalness,surfaceInfo.roughness, surfaceInfo.F0, 1.0 - diffuseProbability);
                    diffuseWeight *= diffuseEnergyScale;
                    rayColor *= diffuseWeight;
                #endif  
                
            }

            float sunRadius = inEnd ? END_SUN_RADIUS : SUN_RADIUS;
            float4 sunColor = inEnd ? float4(END_SUN_COLOR, END_SUN_INTENSITY) : getSunColor(float4(0.0, 0.0, 0.0, 0.0));
            float sunIntensity = inEnd ? END_SUN_INTENSITY : SUN_INTENSITY;
            float sunEv = 1.0 * exp2(sunColor.a * sunIntensity);
            DirectLight light = sampleDirectLightData(mainLightDir, sunColor.rgb, sunEv, sunRadius, true, surfaceInfo, N, ng, V, directDiffuseWeight, rng, inWater);
            
            totalRadiance +=  light.radiance;
            
            // Apply emissive lighting.
            // TODO, move this to surface Info later
            float3 emissiveColor = surfaceInfo.color;
            float emissionEV = 1.0 * exp2(EMISSION_STENGTH);
            float3 emission = emissiveColor * surfaceInfo.emissive * emissionEV;
            totalRadiance += emission;

            uint mediaType = objectInstance.offsetPack5 >> 8; // See MEDIA_TYPE macros in Constants.hlsl.
            const bool isBlockBreakingOverlay = objectInstance.flags == (kObjectInstanceFlagAlphaTestThresholdHalf | kObjectInstanceFlagTextureAlphaControlsVertexColor);
            float3 transmission = 1.0;
            if (isBlockBreakingOverlay) {
                // Use multiplicative blending for block breaking overlay geometry
                transmission = surfaceInfo.color;
                totalRadiance = 0;
            }

            if (dot(nextDirection, ng) < 0.0 && (isTransparentSurface || isSSSVolume)) ng = -ng;

            // Enchantment Glint (unlit effect)
            if (objectInstance.flags & kObjectInstanceFlagGlint)
            totalRadiance += (sin(3.0 * g_view.time) * 0.5 + 0.5) * (float3(077, 23, 255) / 255.0);


            
            #if ENABLE_WATER_PARALLAX
                if (hitInfo.materialType == MATERIAL_TYPE_WATER)
                {
                    if (dot(nextDirection, geometryInfo.geometryNormal) > 0.0f)
                    {
                        surfaceInfo.position.y = max(surfaceInfo.position.y, flatPlaneY);
                    }
                    else
                    {
                        surfaceInfo.position.y = min(surfaceInfo.position.y, flatPlaneY);
                    }
                }
            #endif
            
            rayState.color += totalRadiance * rayState.throughput;
            rayState.throughput *= rayColor  * transmission;
            rayState.rayDesc.Direction = nextDirection; 
            if (dot(nextDirection, ng) < 0.0 && isTransparentSurface) ng = -ng;
            rayState.rayDesc.Origin = offset_ray(surfaceInfo.position, ng);

            // Update other ray properties
            rayState.distance += hitInfo.rayT;
            rayState.motion += surfaceInfo.position - surfaceInfo.prevPosition;
        #endif
    }

    float3 RenderRay(RayDesc rayDesc, out float outputDistance, out float3 outputMotion, in float2 pixelPos, inout float firstHitDist)
    {
        RayQuery<RAY_FLAG_NONE> q;
        RayState rayState;
        rayState.Init();
        rayState.hitWater = g_view.cameraIsUnderWater;
        rayState.rayDesc = rayDesc;
        PathRNG rng;

        float3 totalRadiance = 0;
        float3 directLight = 0;
        float3 rayColor = 1.0;
        float fogDistance = rayDesc.TMax;
        const float maxDistance = 65504;
        float primaryDistance = maxDistance;
        float3 primaryMotion = 0.0;

        float3 sunDir =  getDirectionToSun();
        float3 moonDir = -sunDir;

        float sunFade = saturate(sunDir.y);
        float moonFade = saturate(moonDir.y);

        float3 mainLightDir = sunFade > 0.0 ? sunDir : moonDir;
        mainLightDir = inEnd ? END_SUN_DIRECTION : mainLightDir;
        float3 endTwinSunDir = END_TWIN_SUN_DIRECTION;

        for (int i = 0; i < MAX_BOUNCES; i++)
        {
            uint baseSeed = uint(pixelPos.x) + uint(pixelPos.y) * g_view.renderResolution.x;
            baseSeed ^= g_view.frameCount * 0x9E3779B9u;
            baseSeed ^= uint(i) * 0x85EBCA6Bu;
            rng.state = PCG_Hash(uint3(baseSeed, g_view.frameCount, uint(i)));
            q.TraceRayInline(SceneBVH, RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES, rayState.instanceMask, rayState.rayDesc);
            while (q.Proceed())
            {
                HitInfo hitInfo = GetCandidateHitInfo(q);
                if (AlphaTestHitLogic(hitInfo))
                {
                    q.CommitNonOpaqueTriangleHit();
                }
            }

            bool hitSurface = q.CommittedStatus() == COMMITTED_TRIANGLE_HIT;
            float surface = rayDesc.TMax;
            if (hitSurface)
            {
                HitInfo hitInfo = GetCommittedHitInfo(q);
                surface = hitInfo.rayT;
            }

            if (rayState.inSSSMedium)
            {
                float slabExit = rayState.rayDesc.TMax;
                float3 slabExitNormal = 0.0;
                if (rayState.sssMediumThickness > 0.0)
                {
                    float depth = dot(rayState.rayDesc.Origin - rayState.sssSlabOrigin, rayState.sssSlabNormal);
                    float depthRate = dot(rayState.rayDesc.Direction, rayState.sssSlabNormal);
                    if (depthRate > 1e-6)
                    {
                        slabExit = max((rayState.sssMediumThickness - depth) / depthRate, 0.0);
                        slabExitNormal = rayState.sssSlabNormal;
                    }
                    else if (depthRate < -1e-6)
                    {
                        slabExit = max(-depth / depthRate, 0.0);
                        slabExitNormal = -rayState.sssSlabNormal;
                    }
                }

                float end = min(surface, min(slabExit, rayState.rayDesc.TMax));
                float start = rayState.rayDesc.TMin;
                float3 albedo = rayState.sssSigmaS / rayState.sssSigmaT;
                // Include a small throughput term so unscattered paths remain sampleable
                // even in channels with zero scattering albedo.
                float3 channelWeight = max(rayState.throughput, 0.0) * (albedo + 0.05);
                float weightSum = channelWeight.x + channelWeight.y + channelWeight.z;
                if (weightSum <= 0.0) break;
                float3 channelProbability = channelWeight / weightSum;
                float channelSample = NextFloat(rng);
                uint channel = channelSample < channelProbability.x ? 0
                    : (channelSample < channelProbability.x + channelProbability.y ? 1 : 2);
                float distance = -log(max(1.0 - NextFloat(rng), 1e-7)) / rayState.sssSigmaT[channel];
                float segmentLength = max(end - start, 0.0);
                bool scattered = distance < segmentLength;
                float traveled = scattered ? distance : segmentLength;
                float3 transmittance = exp(-rayState.sssSigmaT * traveled);
                float3 distanceDensity = scattered ? transmittance * rayState.sssSigmaT : transmittance;
                float distancePdf = dot(channelProbability, distanceDensity);
                if (distancePdf <= 0.0) break;

                if (scattered)
                {
                    rayState.throughput *= transmittance * rayState.sssSigmaS / distancePdf;
                    float3 scatterPos = rayState.rayDesc.Origin + rayState.rayDesc.Direction * (start + distance);
                    rayState.rayDesc.Direction = SampleUniformSphere(NextFloat2(rng));
                    rayState.rayDesc.Origin = offset_ray(scatterPos, rayState.rayDesc.Direction);
                    rayState.rayDesc.TMin = 0.0;
                    rayState.scattered = true;
                }
                else
                {
                    rayState.throughput *= transmittance / distancePdf;
                    bool slabBoundary = slabExit < rayState.rayDesc.TMax
                        && (!hitSurface || slabExit < surface - 1e-4f);
                    if (!slabBoundary && hitSurface && rayState.sssMediumThickness > 0.0)
                    {
                        HitInfo slabHit = GetCommittedHitInfo(q);
                        slabBoundary = slabHit.objectInstanceIndex == rayState.sssSlabInstance
                            && slabHit.primitiveId / 2 == rayState.sssSlabQuad
                            && abs(slabExit - surface) < 1e-4f;
                    }
                    if (!slabBoundary && !hitSurface) break;

                    float3 exitPos = rayState.rayDesc.Origin + rayState.rayDesc.Direction * end;
                    float3 exitNormal = slabExitNormal;
                    if (rayState.sssMediumThickness > 0.0)
                    {
                        // The slab is virtual; resume lighting and transport at the
                        // actual alpha-tested surface, not 0.1 m behind it.
                        if (!slabBoundary) break;
                        float depth = dot(exitPos - rayState.sssSlabOrigin, rayState.sssSlabNormal);
                        float3 surfaceExitPos = exitPos - depth * rayState.sssSlabNormal;
                        float3 connection = surfaceExitPos - exitPos;
                        float connectionLength = length(connection);
                        if (connectionLength > 1e-5f)
                        {
                            float3 connectionDirection = connection / connectionLength;
                            RayDesc connectionRay;
                            connectionRay.Origin = offset_ray(exitPos, connectionDirection);
                            float3 connectionEnd = offset_ray(surfaceExitPos, -connectionDirection);
                            connectionRay.Direction = connectionDirection;
                            connectionRay.TMin = 0.0f;
                            connectionRay.TMax = max(dot(connectionEnd - connectionRay.Origin, connectionDirection), 0.0f);
                            if (connectionRay.TMax > 0.0f)
                            {
                                shadowPayload connectionShadow;
                                TraceShadowRay(connectionRay, connectionShadow);
                                if (all(connectionShadow.transmission == 0.0f)) break;
                            }
                        }
                        exitPos = surfaceExitPos;
                    }
                    else
                    {
                        HitInfo exitHit = GetCommittedHitInfo(q);
                        if (exitHit.frontFacing || exitHit.materialType != MATERIAL_TYPE_OPAQUE) break;
                        ObjectInstance exitObject = objectInstances[exitHit.objectInstanceIndex];
                        GeometryInfo exitGeometry = GetGeometryInfo(exitHit, exitObject);
                        SurfaceInfo exitSurface = MaterialVanilla(exitHit, exitGeometry, exitObject);
                        if (exitSurface.subsurface <= 0.0f) break;
                        exitNormal = exitGeometry.geometryNormal;
                        if (dot(exitNormal, rayState.rayDesc.Direction) < 0.0) exitNormal = -exitNormal;
                    }

                    float sunRadius = inEnd ? END_SUN_RADIUS : SUN_RADIUS;
                    float4 sunColor = inEnd ? float4(END_SUN_COLOR, END_SUN_INTENSITY) : getSunColor(float4(0.0, 0.0, 0.0, 0.0));
                    float sunIntensity = inEnd ? END_SUN_INTENSITY : SUN_INTENSITY;
                    float sunEv = exp2(sunColor.a * sunIntensity);
                    DirectLight exitLight = sampleVolumetricDirectLightData(mainLightDir, sunColor.rgb, sunEv, sunRadius, true, exitPos, exitNormal, rng, rayState.hitWater, false, 0.0);
                    rayState.color += rayState.throughput * exitLight.radiance * (max(dot(exitNormal, exitLight.direction), 0.0) / PI);
                    rayState.inSSSMedium = false;
                    rayState.sssMediumThickness = 0.0;
                    rayState.sssSigmaT = 0.0;
                    rayState.sssSigmaS = 0.0;
                    rayState.rayDesc.Direction = CosineHemisphereSampling(NextFloat2(rng), exitNormal);
                    rayState.rayDesc.Origin = offset_ray(exitPos, exitNormal);
                    rayState.rayDesc.TMin = 0.0;
                }

                if (i > 1)
                {
                    float p = min(max(rayState.throughput.x, max(rayState.throughput.y, rayState.throughput.z)), 0.95f);
                    if (p <= 0.0 || NextFloat(rng) >= p) break;
                    rayState.throughput /= p;
                }
                if (all(rayState.throughput == 0)) break;
                continue;
            }

            float volumeStart = rayState.rayDesc.TMin;
            float volumeExit = rayState.rayDesc.TMax;
            float3 sigmaS3;
            float3 sigmaT3;
            float waterDropletSize = WATER_DROPLET_SIZE;
            if (rayState.hitWater)
            {
                sigmaT3 = max(getMediaExtinction(MEDIA_TYPE_WATER).rgb, 0.0);
                sigmaS3 = min(float3(0.01, 0.04, 0.065), sigmaT3);
                waterDropletSize = 16;
            }
            else
            {
                float atmosphereT0;
                float atmosphereT1;
                float ATMOSPHERE_RADIUS = 550.0f;

                if (RaySphereIntersect(rayState.rayDesc.Origin,rayState.rayDesc.Direction,ATMOSPHERE_RADIUS,atmosphereT0,atmosphereT1))
                {
                    volumeStart = max(volumeStart, atmosphereT0);
                    volumeExit = min(volumeExit, atmosphereT1);
                }
                else
                {
                    volumeStart = volumeExit;
                }

                #if OVERRIDE_END_FOG_SCATTERING
                    sigmaS3 = END_FOG_SCATTERING_COLOR * END_FOG_SCATTERING_INTENSITY;
                #else
                    sigmaS3 = getScattering();
                #endif
                sigmaT3 =
                inEnd ?
                getMediaPrimaryExtinction() * END_FOG_EXTINCTION_INTENSITY :
                g_view.cameraIsUnderWater ? getMediaExtinction(MEDIA_TYPE_AIR).rgb : getMediaPrimaryExtinction();

                sigmaT3 = lerp(
                sigmaT3,
                float3(0.0125, 0.0125, 0.0125),
                getBiomeAdjustedRainLevel());
            }

            float tEnd = min(surface, volumeExit);
            // Construct the homogenous medium
            // https://la.disneyresearch.com/wp-content/uploads/Monte-Carlo-Methods-for-Volumetric-Light-Transport-Simulation-Paper.pdf
            // Construct the homogenous medium

            // Majorant for delta tracking.
            float medium = tEnd;
            float densityModifier = 0.0f;
            bool mediumScattered = false;
            float3 waterSegmentWeight = 1.0;

            #if !WHITE_FURNACE
                if (rayState.hitWater && volumeStart < tEnd)
                {
                    uint channel = min((uint)(NextFloat(rng) * 3.0f), 2u);
                    float sampledSigmaT = sigmaT3[channel];
                    float segmentLength = tEnd - volumeStart;
                    float distance = sampledSigmaT > 0.0f
                        ? -log(max(1.0f - NextFloat(rng), 1e-7f)) / sampledSigmaT
                        : segmentLength;
                    mediumScattered = distance < segmentLength;
                    float traveled = mediumScattered ? distance : segmentLength;
                    float3 transmittance = exp(-sigmaT3 * traveled);
                    float3 distanceDensity = mediumScattered ? transmittance * sigmaT3 : transmittance;
                    float distancePdf = (distanceDensity.x + distanceDensity.y + distanceDensity.z) / 3.0f;
                    if (distancePdf <= 0.0f) break;
                    waterSegmentWeight = mediumScattered
                        ? transmittance * sigmaS3 / distancePdf
                        : transmittance / distancePdf;
                    if (mediumScattered)
                    {
                        medium = volumeStart + distance;
                        densityModifier = 1.0f;
                        rayState.scattered = true;
                    }
                }
                else if (volumeStart < tEnd)
                {
                    float majorant = max(sigmaT3.x, max(sigmaT3.y, sigmaT3.z));
                    majorant = max(majorant, 1e-6f);

                    float t = volumeStart;
                    // limit to 100 delta tracking steps. less accuracy but more performant than unlimited esp if we are going forward with 20+ bounces
                    for(int i = 0; i < 100; i++)
                    {
                        float xi = max(NextFloat(rng), 1e-6f);
                        t += -log(xi) / majorant;

                        if (t >= tEnd)
                        break;

                        float3 candidatePos =
                        rayState.rayDesc.Origin +
                        rayState.rayDesc.Direction * t;
                        
                        densityModifier = calcDensityModifier(candidatePos);

                        float3 localSigmaT3 = sigmaT3 * densityModifier;
                        float localSigmaT =
                        max(localSigmaT3.x, max(localSigmaT3.y, localSigmaT3.z));

                        if (NextFloat(rng) < localSigmaT / majorant)
                        {
                            medium = t;
                            mediumScattered = true;
                            rayState.scattered = true;
                            break;
                        }
                    }
                }
            #endif
            rayState.throughput *= waterSegmentWeight;
            
            float3 totalScatter = 0.0;

            if (mediumScattered)
            {
                float3 scatterPos =
                rayState.rayDesc.Origin +
                rayState.rayDesc.Direction * medium;

                float3 sigmaS =
                sigmaS3 * densityModifier;

                float3 sigmaT =
                sigmaT3 * densityModifier;

                float3 scatterWeight = rayState.hitWater ? 1.0.xxx : sigmaS / max(sigmaT, 1e-6);

                float sunRadius = inEnd ? END_SUN_RADIUS : SUN_RADIUS;
                
                float4 sunColor = getSunColor(float4(0.0, 0.0, 0.0, 0.0));
                float sunEv = 0.3 * exp2(sunColor.a * SUN_INTENSITY);
                DirectLight light = sampleVolumetricDirectLightData(mainLightDir, sunColor.rgb, sunEv, sunRadius, true, scatterPos, rayState.rayDesc.Direction, rng, rayState.hitWater, false, sigmaT);

                float VdotL = dot(rayState.rayDesc.Direction, light.direction);
                float gHG, gD, alpha, draineWeight;
                GetApproximateMieParameters(waterDropletSize, gHG, gD, alpha, draineWeight);
                

                float cosThetaSun = VdotL;

                float sunPhase = PhaseApproximateMie(cosThetaSun, gHG, gD, alpha, draineWeight);

                float3 directScatter = rayState.throughput * scatterWeight * (light.radiance * sunPhase);
                
                rayState.color += directScatter;
                float phasePdf;
                float cosTheta;
                float3 nextDirection = SampleApproximateMie(rayState.rayDesc.Direction,gHG,gD,alpha,draineWeight,rng,phasePdf, cosTheta);
                float sampledPhase = PhaseApproximateMie(cosTheta,gHG,gD,alpha,draineWeight);

                rayState.throughput *= scatterWeight *
                ((sampledPhase) / max(phasePdf, 1e-6));

                rayState.rayDesc.Direction = nextDirection;
                rayState.rayDesc.Origin =
                offset_ray(scatterPos, rayState.rayDesc.Direction);
                


            }
            else
            {
                if (hitSurface)
                {
                    HitInfo hitInfo = GetCommittedHitInfo(q);

                    RenderVanilla(
                    hitInfo,
                    rayState,
                    rng,
                    totalRadiance,
                    directLight,
                    rayColor,
                    fogDistance,
                    i, rayDesc);
                    if (i == 0)
                    {
                        primaryDistance = min(hitInfo.rayT, maxDistance);
                        primaryMotion = rayState.motion;
                    }
                }
                else
                {
                    RenderSky(rayState, rayDesc, rng, i == 0);
                    break;
                }
            }
            
            
            if (i > 1)
            {
                float p = max(max(rayState.throughput.x, rayState.throughput.y), rayState.throughput.z);
                p = min(p, 0.95f);

                if (p <= 0.0f) break;
                if (NextFloat(rng) >= p) break;

                rayState.throughput /= p;
            }
            
            
            // Terminate rays that can't contribute anymore.
            if (all(rayState.throughput == 0))
            break;
        }

        outputDistance = primaryDistance;
        firstHitDist = primaryDistance;
        outputMotion = primaryMotion;
        return rayState.color;
    }
#endif
