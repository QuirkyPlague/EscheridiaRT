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
            sssSigmaS = 0;
            sssSigmaT = 0;
            scattered = false;
        }
    };

    void RenderSky(inout RayState rayState, in RayDesc ray, inout PathRNG rng)
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
        float sunLuminance = luminance(sunColor.rgb * sunColor.a * SUN_INTENSITY) * skyLuminanceMult;
        mainLightDir = inEnd ? END_SUN_DIRECTION : mainLightDir;
        // The atmosphere function adds the planet radius internally; pass the
        // existing 1000-meter offset converted to kilometers.
        const float minSunIntensity = 0.448;
        sunLuminance = max(sunLuminance, minSunIntensity); // This allows for the sun to have an effect on the sky even after sunset
        float3 worldPos = float3(0,500,0);
        float3 rayOriginKm = worldPos * 0.001;
        
        float3 finalColor = RenderHillaireAnalytical(
        rayOriginKm,
        rayState.rayDesc.Direction,
        mainLightDir,
        sunLuminance,
        rng,true);
        
        

        #if WHITE_FURNACE == 1
            finalColor = float3(1.0, 1.0, 1.0);
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
            float3 N = surfaceInfo.normal;
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

            float3 effectiveH = normalize(lerp(N, N + V, surfaceInfo.roughness * surfaceInfo.roughness));
            float3 kS = fresnelSchlick(max(dot(V,effectiveH), 0.001), surfaceInfo.F0);
            

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
                nextDirection = CosineHemisphereSampling(XiDiffuse, N); 
                float3 diffWeight = diffuseBRDFLambert(N, nextDirection, V, surfaceInfo.color, surfaceInfo.metalness, surfaceInfo.roughness, surfaceInfo.F0, specularProbability); 
                
                rayState.throughput *= diffWeight;
                rayState.rayDesc.Direction = nextDirection;
            }

            // 4. Trace the ray onward
            rayState.rayDesc.Origin = offset_ray(surfaceInfo.position, ng);
            rayState.distance += hitInfo.rayT;
            rayState.motion += surfaceInfo.position - surfaceInfo.prevPosition;
        #else
            bool inWater = g_view.cameraIsUnderWater;

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
            if (hitInfo.materialType == MATERIAL_TYPE_WATER) 
            {
                WaterMaterial waterMat;
                waterMat.SetUp(surfaceInfo, geometryInfo, direction, bounceCount, firstHitDist, parallaxHeight, ray);
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

            // Volumetric SSS: model the material as a dielectric boundary around a participating
            // medium. RenderRay's delta-tracking marcher performs full physical random-walk
            // transport inside both solid blocks and alpha-test geometry.
            const float SSS_IOR = 1.4;
            bool isAlphaTest = hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST;
            float mfp = isAlphaTest ? 0.05 : 0.18; // Mean free path in voxels
            bool isSSSVolume = surfaceInfo.subsurface > 0.0 && !isCloud && !isTransparentSurface && (hitInfo.materialType == MATERIAL_TYPE_OPAQUE || hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST);
            float3 sssShadowSigmaT = isSSSVolume ? 1.0 / max(mfp * surfaceInfo.subsurface, 1e-3) : 0.0;

            // Split non-specular energy between volumetric SSS and standard diffuse reflection.
            // For thin alpha-test geometry (leaves, grass), cap SSS branching probability so rays
            // consistently diffuse-bounce and gather indirect ambient skylight in shadows.
            
            float sssMaxProb =  saturate(surfaceInfo.subsurface * 0.65);
            float sssProbability = isSSSVolume ? (1.0 - specularProbability) * sssMaxProb : 0.0;
            float diffuseProbability = isTransparentSurface ? 0.0f : max((1.0 - specularProbability - sssProbability), 0.0);
            float directDiffuseWeight = isTransparentSurface ? (1.0f - specularProbability) * ( surfaceInfo.alpha) :  1 - specularProbability;
            if (isTransparentSurface && !isCloud) {
                // Determine incident and transmitted media indices of refraction (IOR)
                float surfaceIOR = isWater ? 1.333f : 1.5f;

                // For water, the current path medium determines the IOR transition.
                // eta is etaIncident / etaTransmitted for refract().
                float eta = isWater
                ? (rayState.hitWater ? (1.333f / 1.0f) : (1.0f / 1.333f))
                : (hitInfo.frontFacing ? (1.0f / surfaceIOR) : (surfaceIOR / 1.0f));

                // Sample microfacet normal with GGX VNDF
                float alpha = max(roughness, 0.0001f);
                float3 microfacetNormalTS = SampleVNDFGGX(tangentView, alpha, XiSpec);
                float3 microfacetNormal = normalize(microfacetNormalTS.x * T + microfacetNormalTS.y * B + microfacetNormalTS.z * N);

                // Exact physical dielectric Fresnel (air <-> dielectric in both directions, with exact TIR)
                float cosThetaI = max(dot(V, microfacetNormal), 0.0f);
                float cosThetaT;
                float F_diel = max(DielectricFresnel(cosThetaI, eta, cosThetaT), 0.0);

                // Pure dielectric split: specular reflection (F) vs specular/microfacet transmission (1 - F)
                specularProbability = clamp(F_diel, surfaceInfo.F0.x, 1.0f);
                float transmitToDiffuseScale = 1.0 - surfaceInfo.alpha;
                float transmissionProbability = (1.0f - specularProbability) * transmitToDiffuseScale;
                

                // Full transparent bsdf 
                if (Xi.x < specularProbability) { 
                    float3 reflDir = reflect(-V, microfacetNormal);
                    if (dot(N, reflDir) <= 0.0f)
                    {
                        reflDir = normalize(reflDir - 2.0f * dot(N, reflDir) * N);
                    }
                    nextDirection = reflDir;
                    
                    // Exact analytical VNDF reflection weight: cancels D and 4*NdotV*NdotL
                    float NdotL = max(dot(N, nextDirection), 0.0001f);
                    float G1_L = G1_SmithGGX(NdotL, surfaceInfo.roughness);
                    float3 weight = (F_diel / specularProbability) * G1_L;
                    rayColor *= weight;
                }
                else if (Xi.x < specularProbability + transmissionProbability)
                { 
                    float3 wi = refract(direction, microfacetNormal, eta);

                    // If total internal reflection on the microfacet (or numerical failure):
                    if (dot(wi, wi) < 1e-6f)
                    {
                        // Reflect off the microfacet with roughness preserved
                        float3 reflDir = reflect(-V, microfacetNormal);
                        if (dot(N, reflDir) <= 0.0f)
                        {
                            reflDir = normalize(reflDir - 2.0f * dot(N, reflDir) * N);
                        }
                        nextDirection = reflDir;
                    }
                    else
                    {
                        // If the microfacet refracted ray points into the upper hemisphere:
                        if (dot(N, wi) >= 0.0f)
                        {
                            wi = normalize(wi - 2.0f * dot(N, wi) * N);
                        }
                        nextDirection = normalize(wi);
                        
                        

                        // A successful water refraction crosses the air/water boundary.
                        // Reflection and total internal reflection leave the medium unchanged.
                        if (isWater)
                        {
                            rayState.hitWater = !rayState.hitWater;
                        }
                    }

                    float NdotI = max(abs(dot(N, nextDirection)), 0.0001f);
                    float G1_wi = G1_SmithGGX(NdotI, surfaceInfo.roughness);

                    // Water absorption is accumulated along the path in RenderRay(),
                    // not applied as a tint at the water interface.
                    float3 transmissionTint = isWater ? 1.0.xxx : GetAlphaBlendTransmissionTint(surfaceInfo.color);

                    // Exact analytical VNDF transmission weight: cancels D, Jacobian, and geometric factors
                    float3 weight = ((1.0f - F_diel) / max(transmissionProbability, 1e-4f)) * transmissionTint * G1_wi;


                    rayColor *= weight;
                }
                else
                {
                    // render transparents using lambert. while this would be a mismatch they are separately handled and dont need/have a detailed diffuse necessity
                    nextDirection = CosineHemisphereSampling(XiDiffuse, N); 
                    rayColor *= diffuseBRDFLambert(N, nextDirection, V, surfaceInfo.color, surfaceInfo.metalness,surfaceInfo.roughness, surfaceInfo.F0, specularProbability); 
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
            else if (Xi.x < specularProbability + sssProbability && !inWater)
            {
                // Subsurface transmission into/through the medium.
                // Uses rayState.inSSSMedium rather than hitInfo.frontFacing so two-sided alpha-test
                // geometry (leaves) always enters with 1/1.4 and exits with 1.4/1 without inverted refraction.
                bool entering = !rayState.inSSSMedium;
                float eta = entering ? 1.0 / SSS_IOR : SSS_IOR;
                float3 refractionNormal = entering ? N : -N;
                float3 refracted = refract(direction, refractionNormal, eta);

                if (length(refracted) < 1e-5)
                {
                    nextDirection = reflect(direction, N);
                    rayColor *= (1.0 / max(sssProbability, 1e-4));
                }
                else
                {
                    nextDirection = refracted;
                    float3 F_smooth = fresnelSchlick(max(dot(N, V), 0.0), F0);
                    rayColor *= ((1.0 - F_smooth) * surfaceInfo.color) / max(sssProbability, 1e-4);
                    rayState.inSSSMedium = entering;

                    if (entering)
                    {
                        float3 sigma_t = 1.0 / max(mfp, 1e-3);
                        rayState.sssSigmaT = sigma_t;
                        rayState.sssSigmaS = sigma_t * max(surfaceInfo.color * surfaceInfo.subsurface, saturate(1 - surfaceInfo.subsurface));
                        rayState.sssMediumThickness = isAlphaTest ? 0.1 : 1.0;
                    }
                }
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
                    float3 F = fresnelSchlick(LdotH, 0.04);
                    float3 diffuseBRDF = (1.0 - F) * f_EON(rho, surfaceInfo.roughness, wi_local, wo_local, USE_ACCURATE_DIFFUSE_BRDF); 
                    
                    float3 weight_d = ((diffuseBRDF * NdotL_d) / (localDiffusePdf * max(diffuseProbability, 1e-4))); 

                    rayColor *= weight_d; 
                #elif DIFFUSE_METHOD == 2
                    nextDirection = CosineHemisphereSampling(XiDiffuse, N); 
                    rayColor *= diffuseBRDFHammonConserving(N, nextDirection, V, surfaceInfo.color, surfaceInfo.metalness,surfaceInfo.roughness, surfaceInfo.F0, specularProbability); 
                #else
                    // Default to Lambertian if no method is specified
                    nextDirection = CosineHemisphereSampling(XiDiffuse, N); 
                    rayColor *= diffuseBRDFLambert(N, nextDirection, V, surfaceInfo.color, surfaceInfo.metalness,surfaceInfo.roughness, surfaceInfo.F0, specularProbability); 
                #endif  
                
            }

            float sunRadius = inEnd ? END_SUN_RADIUS : SUN_RADIUS;
            float4 sunColor = inEnd ? float4(END_SUN_COLOR, END_SUN_INTENSITY) : getSunColor(float4(0.0, 0.0, 0.0, 0.0));
            float sunIntensity = inEnd ? END_SUN_INTENSITY : SUN_INTENSITY;
            float sunEv = 1.0 * exp2(sunColor.a * sunIntensity);
            DirectLight light = sampleDirectLightData(mainLightDir, sunColor.rgb, sunEv, sunRadius, true, surfaceInfo, N, ng, V, directDiffuseWeight, rng, rayState.hitWater);
            
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


            if (any(isnan(rayState.throughput)) || any(isinf(rayState.throughput)))
            return;

            if (any(isnan(surfaceInfo.position)) || any(isinf(surfaceInfo.position)))
            return;

            if (any(isnan(surfaceInfo.normal)) || any(isinf(surfaceInfo.normal)))
            return;

            if (any(isnan(nextDirection)) || any(isinf(nextDirection)))
            return;
            
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
            
            float volumeStart = rayState.rayDesc.TMin;
            float volumeExit = rayState.rayDesc.TMax;
            float3 sigmaS3;
            float3 sigmaT3;
            float waterDropletSize = WATER_DROPLET_SIZE;
            if (rayState.inSSSMedium)
            {
                // Bounded by the object thickness or the next surface hit.
                sigmaS3 = rayState.sssSigmaS;
                sigmaT3 = rayState.sssSigmaT;
                volumeExit = min(volumeExit, min(surface, rayState.sssMediumThickness));
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
                // Use the medium occupied by this ray segment, not the camera's
                // initial medium. Rays can refract into or out of water after a bounce.
                sigmaT3 =
                inEnd ?
                getMediaPrimaryExtinction() * END_FOG_EXTINCTION_INTENSITY :
                g_view.cameraIsUnderWater ? getMediaPrimaryExtinction() * 0.0 : getMediaPrimaryExtinction();

                sigmaT3 = lerp(
                sigmaT3,
                float3(0.0125, 0.0125, 0.0125),
                getBiomeAdjustedRainLevel());
                if(rayState.hitWater)
                {
                    sigmaT3 = getMediaExtinction(MEDIA_TYPE_WATER).rgb;
                    sigmaS3 = float3(0.01, 0.05, 0.085) * 1.5;
                    waterDropletSize = 16;
                }
            }
             if(g_view.cameraIsUnderWater && rayState.hitWater)
            {
                sigmaT3 = getMediaExtinction(MEDIA_TYPE_WATER).rgb * 0.33;
                sigmaS3 = float3(0.01, 0.05, 0.085) * 1.5;
                waterDropletSize = 16;
            }

            float tEnd = min(surface, volumeExit);
            // Construct the homogenous medium
            // https://la.disneyresearch.com/wp-content/uploads/Monte-Carlo-Methods-for-Volumetric-Light-Transport-Simulation-Paper.pdf
            // Construct the homogenous medium

            // Majorant for delta tracking.
            float medium = tEnd;
            float densityModifier = 0.0f;
            bool mediumScattered = false;

            if (volumeStart < tEnd)
            {
                float majorant = max(sigmaT3.x, max(sigmaT3.y, sigmaT3.z));
                majorant = max(majorant, 1e-6f);

                float t = volumeStart;

                while (true)
                {
                    float xi = max(NextFloat(rng), 1e-6f);
                    t += -log(xi) / majorant;

                    if (t >= tEnd)
                    break;

                    float3 candidatePos =
                    rayState.rayDesc.Origin +
                    rayState.rayDesc.Direction * t;

                    densityModifier = rayState.inSSSMedium
                    ? 1.0f
                    : calcDensityModifier(candidatePos);

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
            
            /*
            // Beer-Lambert absorption for the portion of this path segment
            // traveled inside water. Apply it to throughput so it affects the
            // next surface, further bounces, and paths that scatter in the medium.
            if (rayState.hitWater )
            {
                float3 transmittance = 1.0;
                float waterSegmentDistance = mediumScattered ? medium - volumeStart : (hitSurface ? surface : rayState.rayDesc.TMax) - volumeStart;

                if (waterSegmentDistance > 0.0)
                {   
                    transmittance *= max(calcTransmittance(waterSegmentDistance,getMediaExtinction(MEDIA_TYPE_WATER).rgb), 0.001) ;
                    rayState.throughput *= transmittance;
                }
            }
            */
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

                float3 scatterWeight =
                sigmaS / max(sigmaT, 1e-6);

                float sunRadius = inEnd ? END_SUN_RADIUS : SUN_RADIUS;
                
                float4 sunColor = getSunColor(float4(0.0, 0.0, 0.0, 0.0));
                float sunEv = rayState.inSSSMedium ?  2.0 * exp2(sunColor.a * SUN_INTENSITY) : 0.3 * exp2(sunColor.a * SUN_INTENSITY) ;
                DirectLight light = sampleVolumetricDirectLightData(mainLightDir, sunColor.rgb, sunEv, sunRadius, true, scatterPos, rayState.rayDesc.Direction, rng, rayState.hitWater);

                bool inWater = g_view.cameraIsUnderWater;
                float VdotL = dot(rayState.rayDesc.Direction, mainLightDir);
                const float SSS_PHASE_ANISOTROPY = 0.815; // Roughly isotropic once inside organic/solid media.
                float g = rayState.inSSSMedium ? SSS_PHASE_ANISOTROPY : (inEnd ? END_FOG_ANISOTROPY : 0.635);
                float ambientG = rayState.inSSSMedium ?  0.535 : (inEnd ? END_FOG_INDIRECT_ANISOTROPY : 0.535);
                
                float gHG, gD, alpha, draineWeight;
                GetApproximateMieParameters(waterDropletSize, gHG, gD, alpha, draineWeight);
                

                float cosThetaSun = VdotL;

                float sunPhase = PhaseApproximateMie(cosThetaSun,gHG,gD,alpha,draineWeight);

                float3 directScatter = rayState.throughput * scatterWeight * (light.radiance * sunPhase);
                
                rayState.color += directScatter;
                float phasePdf;
                float3 nextDirection;
                float sampledPhase;
                if (rayState.inSSSMedium)
                {
                    // Keep the existing SSS behavior.
                    nextDirection = SampleDraine(
                    rayState.rayDesc.Direction,
                    gD,
                    alpha,
                    NextFloat2(rng),
                    rng,
                    phasePdf);

                    sampledPhase = PhaseDraine(
                    dot(rayState.rayDesc.Direction, nextDirection),
                    gD,
                    DRAINE_ALPHA);
                }
                else
                {
                    float cosTheta;
                    nextDirection = SampleApproximateMie(rayState.rayDesc.Direction,gHG,gD,alpha,draineWeight,rng,phasePdf, cosTheta);

                    sampledPhase = PhaseApproximateMie(cosTheta,gHG,gD,alpha,draineWeight);
                }

                rayState.throughput *= scatterWeight *
                ((sampledPhase) / max(phasePdf, 1e-6));

                rayState.rayDesc.Direction = nextDirection;
                rayState.rayDesc.Origin =
                offset_ray(scatterPos, rayState.rayDesc.Direction);
                


            }
            else if (hitSurface)
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
            }
            else
            {
                RenderSky(rayState, rayDesc, rng);
                break;
            }
            
            if (i > 0)
            {
                float p = max(max(rayState.throughput.x, rayState.throughput.y), rayState.throughput.z);
                if (NextFloat(rng) > p) break;
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
        return rayState.color;
    }
#endif
