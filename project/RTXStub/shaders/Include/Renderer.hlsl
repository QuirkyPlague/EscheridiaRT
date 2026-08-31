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
        bool hitWater;

        void Init()
        {
            color = 0;
            throughput = 1;
            distance = 0;
            motion = 0;
            instanceMask = 0xff & ~INSTANCE_MASK_SUN_OR_MOON;
            hitWater = false;
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



    void RenderVanilla(HitInfo hitInfo, inout RayState rayState, inout PathRNG rng, in float3 totalRadiance, in float3 directLight, in float3 rayColor, inout float firstHitDist, int bounceCount)
    {
        
        ObjectInstance objectInstance = objectInstances[hitInfo.objectInstanceIndex];
        GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, objectInstance);
        SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, objectInstance);
        
        //surfaceInfo.color = pow(surfaceInfo.color, 2.2);
        
        #if WHITE_FURNACE == 1
            
            surfaceInfo.alpha = 1;
            surfaceInfo.emissive = 0;
            surfaceInfo.metalness = 0;
            surfaceInfo.roughness = 1;
            surfaceInfo.color = 1.0;
            float3 Wo = -normalize(rayState.rayDesc.Direction);
            bool inWater = g_view.cameraIsUnderWater;
            float2 Xi = NextFloat2(rng);
            float2 XiSpec = NextFloat2(rng);
            float2 XiDiffuse = NextFloat2(rng);
            float2 XiShadow = NextFloat2(rng);
            float rr = NextFloat(rng);
            float3 sunDir =  getDirectionToSun();
            float3 moonDir = -sunDir;

            float sunFade = saturate(sunDir.y);
            float moonFade = saturate(moonDir.y);

            float3 mainLightDir = sunFade > 0.0 ? sunDir : moonDir;
            
            

            bool isCloud = objectInstance.flags & kObjectInstanceFlagClouds;
            if (hitInfo.materialType == MATERIAL_TYPE_OPAQUE || hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST) surfaceInfo.alpha = 1;
            
            
            float3 worldPos = surfaceInfo.position - g_view.waveWorksOriginInSteveSpace;
            worldPos = worldPos - floor(worldPos / 1024) * 1024; // Bedrock may reset position every 1024 blocks, so we can only reliably calculate world position within 1024 blocks chunk.

            float NdotL = max(dot(surfaceInfo.normal, mainLightDir),0.0001);

            rayState.rayDesc.TMin = 0.00;
            bool didReflect = false;
            float3 direction = normalize(rayState.rayDesc.Direction);
            float3 nextDirection;
            float3 N = geometryInfo.geometryNormal;
            float3 V = -direction;
            
            
            float3x3 tbn = tbnMatrix(N);
            float3 tangentView = float3(
            dot(-direction, tbn[0]),
            dot(-direction, tbn[1]),
            dot(-direction, tbn[2]));

            float roughness = max(surfaceInfo.roughness * surfaceInfo.roughness, 0.0);
            bool isWater = hitInfo.materialType == MATERIAL_TYPE_WATER;
            float3 F0 = isWater ? 0.02.xxx : lerp(float3(0.04, 0.04, 0.04), surfaceInfo.color, surfaceInfo.metalness); 
            float NdotV1 = max(dot(surfaceInfo.normal, V), 0.0001);


            float3 effectiveH = normalize(lerp(surfaceInfo.normal, surfaceInfo.normal + V, surfaceInfo.roughness * surfaceInfo.roughness));
            float3 F_specular_estimate = fresnelSchlick(max(dot(V, N),0.001), F0); 
            float3 kS = fresnelSchlick(max(dot(V,N), 0.001), F0);

            
            // --- STAGE 1: FILTER TRANSPARENT PASS-THROUGH FIRST ---
            
            nextDirection = CosineHemisphereSampling(XiDiffuse, surfaceInfo.normal); 
            float3 correctedN = CorrectShadingNormal(V,nextDirection,geometryInfo.geometryNormal,surfaceInfo.normal);
            float NdotL_d = max(dot(correctedN, nextDirection), 0.0001); 
            float NdotV_d = max(dot(correctedN, V), 0.0001); 
            float3 H = normalize(V + nextDirection); 
            float VdotH_d = max(dot(V, H), 0.0001); 
            float LdotH = max(dot(nextDirection,H), 0.001);
            float3 F = fresnelSchlick(VdotH_d, F0); 
            
            float diffMultiplier = DisneyDiffuse(NdotL_d, NdotV_d, LdotH, surfaceInfo.roughness) ; 
            float3 kD = (1.0 - F) ;
            float3 diffuseBRDF = surfaceInfo.color * (diffMultiplier); 
            
            float localDiffusePdf = max(PDF_CosineHemisphere(NdotL_d), 1e-4); 
            //float diffuseProbability = 1.0 - specularProbability; 
            
            float3 weight_d = ((diffuseBRDF * NdotL_d) / (localDiffusePdf )); 

            rayColor *= weight_d; 
            


            

            if (objectInstance.flags & kObjectInstanceFlagClouds)
            {
                // Clouds have vanilla shading baked into vertex color.
                surfaceInfo.alpha = 0.7;        // Match vanilla clouds alpha
            }

            // Apply emissive lighting.
            
            float3 emission = surfaceInfo.color * surfaceInfo.emissive * 100;

            

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
            
            else if(hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND && !isWater) {
                // Use alphablend for alpha-blended surfaces only and tint transmitted light.
                float transmitAmount = 1.0 - surfaceInfo.alpha;
                float3 glassTransmittance = lerp(surfaceInfo.color, 0.0, surfaceInfo.alpha);
                
                transmission *= glassTransmittance;
            }
            
            float3 Ng = geometryInfo.geometryNormal;

            if (dot(nextDirection, Ng) < 0.0)
            Ng = -Ng;




            // Glint
            if (objectInstance.flags & kObjectInstanceFlagGlint)
            totalRadiance += (sin(3.0 * g_view.time) * 0.5 + 0.5) * (float3(077, 23, 255) / 255.0);

            // Accumulate surface emission and throughput
            
            rayState.color += totalRadiance * rayState.throughput;
            rayState.throughput *= rayColor  * transmission;
            float d = dot(nextDirection, geometryInfo.geometryNormal);
            rayState.rayDesc.Direction = nextDirection; 
            rayState.rayDesc.Origin = offset_ray(surfaceInfo.position, nextDirection);

            
            

            // Update other ray properties
            rayState.distance += hitInfo.rayT;
            rayState.motion += surfaceInfo.position - surfaceInfo.prevPosition;
        #else
            bool inWater = g_view.cameraIsUnderWater;
            float2 Xi = NextFloat2(rng);
            float2 XiSpec = NextFloat2(rng);
            float2 XiDiffuse = NextFloat2(rng);
            float2 XiShadow = NextFloat2(rng);
            float3 sunDir =  getDirectionToSun();
            float3 moonDir = -sunDir;

            float sunFade = saturate(sunDir.y);
            float moonFade = saturate(moonDir.y);

            float3 mainLightDir = sunFade > 0.0 ? sunDir : moonDir;

            
            if (hitInfo.materialType == MATERIAL_TYPE_WATER) {
                surfaceInfo.roughness = 0.035;
                const float waveSmoothness = WAVE_SMOOTHING;
                const float waveStrength = WAVE_INTENSITY;
                float3 worldPos = surfaceInfo.position - g_view.waveWorksOriginInSteveSpace;
                // Calculate distance BEFORE wrapping the position
                float2 playerXZ = g_view.viewOriginSteveSpace.xz;
                float2 waterXZ = surfaceInfo.position.xz;

                float distanceFromPlayer = length(waterXZ - playerXZ);
                // Bedrock may reset position every 1024 blocks
                worldPos = worldPos - floor(worldPos / 1024.0) * 1024.0;
                float waveFade = 1.0 - smoothstep(WAVE_FADE_START, WAVE_FADE_END, distanceFromPlayer);
                
                float3 flatNormal = geometryInfo.geometryNormal;
                float3 waveNorm = waveNormal(worldPos.xz,waveSmoothness,waveStrength);
                // Fade waves out with distance
                float fade = 1.15 - exp(-distanceFromPlayer / 32);
                surfaceInfo.normal = normalize(lerp(flatNormal,waveNorm, waveFade));
                surfaceInfo.roughness = lerp(0.235,surfaceInfo.roughness,        waveFade);
            }

            bool isCloud = objectInstance.flags & kObjectInstanceFlagClouds;
            if (hitInfo.materialType == MATERIAL_TYPE_OPAQUE || hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST) surfaceInfo.alpha = 1;


            float NdotL = max(dot(surfaceInfo.normal, mainLightDir),0.0001);

            bool didReflect = false;
            float3 direction = normalize(rayState.rayDesc.Direction);
            float3 nextDirection;
            float3 N = surfaceInfo.normal;
            float3 V = -direction;
            float3 ng = geometryInfo.geometryNormal;
            if(dot(ng,V) < 0.0)
            {
                ng = -ng;
            }
            if(dot(N,V) < 0.0)
            {
                N = -N;
            }
            float3 T;
            float3 B;
            //N = lerp(N,ng, 0.55);
            N = FixShadingNormal(ng,N);
            BuildOrthonormalBasis(N, T, B);
            float3 tangentView = float3(dot(V, T),dot(V, B),dot(V, N));
            //surfaceInfo.roughness = lerp(surfaceInfo.roughness, surfaceInfo.roughness * 0.3, g_view.rainLevel);
            float roughness = max(surfaceInfo.roughness * surfaceInfo.roughness, 0.0);
            
            bool isWater = hitInfo.materialType == MATERIAL_TYPE_WATER;
            float3 F0 = isWater ? 0.02.xxx : lerp(float3(0.04, 0.04, 0.04), surfaceInfo.color, surfaceInfo.metalness); 


            float3 effectiveH = normalize(lerp(N, N + V, surfaceInfo.roughness * surfaceInfo.roughness));
            float3 kS = fresnelSchlick(max(dot(V,effectiveH), 0.001), F0);
            

            float specularProbability = saturate(luminance(kS));

            specularProbability = max(specularProbability, 0.04);

            specularProbability = min(specularProbability, 1.0);
            specularProbability = lerp(specularProbability, 1.0, surfaceInfo.metalness);

            float3 throughput = 1.0; 
            bool isTransparentSurface = hitInfo.materialType == MATERIAL_TYPE_WATER || hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND; 
            bool rayRefractedGoesInside = false;
            
            if (isTransparentSurface && !isCloud) { 
                
                if (Xi.x < specularProbability) {
                    
                    float3 microfacetNormal = SampleVNDFGGX(tangentView, roughness, XiSpec); 
                    float3 tangentReflDir = reflect(-tangentView, microfacetNormal); 
                    nextDirection = normalize(tangentReflDir.x * T +tangentReflDir.y * B +tangentReflDir.z * N);
                    float3 H = normalize(microfacetNormal.x * T + microfacetNormal.y * B + microfacetNormal.z * N);
                    float NdotL = max(dot(N, nextDirection), 0.0001); 
                    float NdotV = max(dot(N, V), 0.0001); 
                    float NdotH = max(dot(N, H), 0.0001);
                    float VdotH = max(dot(V, H), 0.0001); 
                    float LdotH = max(dot(nextDirection,H), 0.001);

                    float3 F = fresnelSchlick(VdotH, F0); 
                    float D = D_GGX(NdotH, surfaceInfo.roughness);
                    float G = G_Smith(NdotV, NdotL, surfaceInfo.roughness); 
                    float3 specWeight = (F * D * G) / (4.0 * NdotV * NdotL);
                    
                    float pdf_r = PDF_GGX_Reflection(NdotV, NdotH, VdotH, surfaceInfo.roughness); 
                    float combinedPdf = max(pdf_r, 1e-6); 
                    
                    rayColor *= (specWeight * NdotL) /
                    (combinedPdf * specularProbability);
                } 
                else { 
                    float IOR = isWater ? 1.333 : 1.5; 
                    float3 refractionNormal = N; 
                    float eta = 1.0 / IOR; 

                    if (!hitInfo.frontFacing) { 
                        eta = IOR / 1.0; 
                    } 

                    float3 refracted = refract(direction, refractionNormal, eta); 

                    if (length(refracted) == 0.0f) { 
                        // Fallback to internal reflection if total internal reflection triggers 
                        nextDirection = reflect(direction, refractionNormal); 
                        } else { 
                        nextDirection = (refracted); 
                        rayRefractedGoesInside = true; 
                    } 

                    // 1. Calculate true Fresnel matching the ray intersection angle
                    float3 F_smooth = fresnelSchlick(max(dot(N, -direction), 0.0), F0); 
                    float F_lum = clamp(luminance(F_smooth), 0.02, 0.98); 

                    // 2. Set structural probabilities
                    float specularProbability = F_lum; 
                    float transmissionProbability = 1.0 - specularProbability; 

                    // 3. Media absorption for volumetric interiors
                    if(isWater) {
                        rayColor *= calcTransmittance(hitInfo.rayT, getMediaExtinction(MEDIA_TYPE_WATER).rgb * 0.3); 
                    }

                    // 4. Radiance scaling factor across the IOR boundary interface
                    

                    // 5. CORRECT MONTE CARLO WEIGHTING
                    // Component (1.0 - F_lum) divided by Selection Probability (transmissionProbability)
                    // Since they are equal, this evaluates to 1.0, keeping your throughput completely stable!
                    float3 transmissionWeight = (1.0 - F_smooth) ;
                    rayColor *= (transmissionWeight / max(transmissionProbability, 1e-4));
                } 
                
            } 
            else if(Xi.x < specularProbability)
            {
                float3 microfacetNormal = SampleVNDFGGX(tangentView, roughness, XiSpec); 
                float3 tangentReflDir = reflect(-tangentView, microfacetNormal); 
                nextDirection = normalize(tangentReflDir.x * T +tangentReflDir.y * B +tangentReflDir.z * N);
                float3 H = normalize(microfacetNormal.x * T + microfacetNormal.y * B + microfacetNormal.z * N);
                float NdotL = max(dot(N, nextDirection), 0.0001); 
                float NdotV = max(dot(N, V), 0.0001); 
                float NdotH = max(dot(N, H), 0.0001);
                float VdotH = max(dot(V, H), 0.0001); 
                float LdotH = max(dot(nextDirection,H), 0.001);

                float3 F = fresnelSchlick(VdotH, F0); 
                float D = D_GGX(NdotH, surfaceInfo.roughness);
                float G = G_Smith(NdotV, NdotL, surfaceInfo.roughness); 
                float3 specWeight = (F * D * G) / (4.0 * NdotV * NdotL);
                
                float pdf_r = PDF_GGX_Reflection(NdotV, NdotH, VdotH, surfaceInfo.roughness); 
                float combinedPdf = max(pdf_r, 1e-6); 
                
                rayColor *= (specWeight * NdotL) /
                (combinedPdf * specularProbability);
            }
            else{ 
                float3 T, B;
                BuildOrthonormalBasis(N, T, B);
                float3 wo_local = float3(dot(V, T),dot(V, B),dot(V, N));

                float4 EONSample = sample_EON(wo_local,surfaceInfo.roughness,XiDiffuse.x,XiDiffuse.y);
                float3 wi_local = EONSample.xyz;
                float localDiffusePdf = max(EONSample.w, 1e-4);
                nextDirection =T * wi_local.x + B * wi_local.y + N * wi_local.z;

                nextDirection = normalize(nextDirection);

                float NdotL_d = max(dot(N, nextDirection), 0.0001); 
                float NdotV_d = max(dot(N, V), 0.0001); 
                float3 H = normalize(V + nextDirection); 
                float VdotH_d = max(dot(V, N), 0.0001); 
                float LdotH = max(dot(nextDirection,H), 0.001);
                float3 F = fresnelSchlick(VdotH_d, F0); 
                float3 rho = surfaceInfo.color * (1.0 - surfaceInfo.metalness);
                float3 transmission = (1.0 - kS);
                float3 diffuseBRDF  = transmission  * f_EON(rho,surfaceInfo.roughness,wi_local,wo_local,true); 
                
                float diffuseProbability = 1.0 - specularProbability; 
                
                float3 weight_d = ((diffuseBRDF * NdotL_d) / (localDiffusePdf * diffuseProbability)); 

                rayColor *= weight_d; 
            }
            

            
            shadowPayload payload;
            RayDesc shadowRay;
            shadowRay.Origin = offset_ray(surfaceInfo.position, ng);
            shadowRay.Direction = randConeJitter(mainLightDir, SUN_RADIUS, XiShadow);
            shadowRay.TMin = 0.0;
            shadowRay.TMax = 10000;
            TraceShadowRay(shadowRay, payload);

            float3 L = normalize(shadowRay.Direction);
            float3 H1 = normalize(L + V);

            float NdotL1 = max(dot(N, L), 0.0001);
            float NdotV = max(dot(N, V), 0.0001);
            float NdotH = max(dot(N, H1), 0.0001);
            float VdotH1 = max(dot(V, H1), 0.0001);
            float LdotH = max(dot(L, H1), 0.001);

            float3 F = fresnelSchlick(VdotH1, F0);
            float3 V_local =float3(dot(V,T), dot(V,B), dot(V,N));
            float3 L_local =float3(dot(L,T), dot(L,B), dot(L,N));

            float D = D_GGX(NdotH, surfaceInfo.roughness);
            float G = G_Smith(NdotV, NdotL1, surfaceInfo.roughness); 
            float3 specular = (F * D * G) / (4.0 * NdotV * NdotL1);
            float3 rho = surfaceInfo.color * (1.0f - surfaceInfo.metalness);
            float3 eonBRDF = f_EON(rho, surfaceInfo.roughness, L_local, V_local, true);
            float3 diffuse = (1.0f - kS) * eonBRDF;
            float3 brdf = isTransparentSurface ? specular : diffuse + specular;
            float diffuseProbability = 1.0 - specularProbability;
            float4 sunlightColor = getSunColor(float4(0.0, 0.0, 0.0, 0.0)) * 580 * SUN_INTENSITY;
            sunlightColor = lerp(sunlightColor, sunlightColor * 0.15, g_view.rainLevel);
            if(inNether) sunlightColor = 0;
            sunlightColor.rgb *= sunlightColor.a;
            float pdfSun = max(PDF_SunCone(), 1e-4);
            float3 sunContribution = sunlightColor.rgb * brdf * saturate(NdotL1) * payload.transmission * throughput / pdfSun;
            // Replace standard cosine hemisphere PDF with the exact EON PDF matching your sampler
            float pdfDiffuse = max(pdf_EON(V_local, L_local, surfaceInfo.roughness), 1e-4);
            
            float pdfSpec = PDF_GGX_Reflection(NdotV, NdotH, VdotH1, surfaceInfo.roughness);
            float pdfBRDF = specularProbability * pdfSpec + diffuseProbability * pdfDiffuse;
            float w = MISWeight(pdfSun, pdfBRDF);

            #if ENABLE_SUNLIGHT == 0
                sunContribution = 0;
            #endif

            
            totalRadiance += sunContribution;

            // Apply emissive lighting.
            float3 emission = surfaceInfo.color * surfaceInfo.emissive * EMISSION_STENGTH;
            totalRadiance += emission;

            uint mediaType = objectInstance.offsetPack5 >> 8; // See MEDIA_TYPE macros in Constants.hlsl.
            const bool isBlockBreakingOverlay = objectInstance.flags == (kObjectInstanceFlagAlphaTestThresholdHalf | kObjectInstanceFlagTextureAlphaControlsVertexColor);
            float3 transmission = 1.0;
            if (isBlockBreakingOverlay) {
                // Use multiplicative blending for block breaking overlay geometry
                transmission = surfaceInfo.color;
                totalRadiance = 0;
            }
            
            else if(hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND && !isCloud && !isWater) {

                transmission *= surfaceInfo.color;
            }
            

            if (dot(nextDirection, ng) < 0.0 && isTransparentSurface) ng = -ng;

            // Enchantment Glint (unlit effect)
            if (objectInstance.flags & kObjectInstanceFlagGlint)
            totalRadiance += (sin(3.0 * g_view.time) * 0.5 + 0.5) * (float3(077, 23, 255) / 255.0);

            
            rayState.color += totalRadiance * rayState.throughput;
            rayState.throughput *= rayColor  * transmission;
            rayState.rayDesc.Direction = nextDirection; 
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

        
        for (int i = 0; i < 16; i++)
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
            float volumeExit = min(rayDesc.TMax, MAX_FOG_DISTANCE);
            float tEnd = min(surface, volumeExit);

            // Construct the homogenous medium
            // https://la.disneyresearch.com/wp-content/uploads/Monte-Carlo-Methods-for-Volumetric-Light-Transport-Simulation-Paper.pdf
            float3 sigmaT3 = getMediaPrimaryExtinction();
            float3 sigmaS3 = getScattering();
            float3 sigmaA3 = getMediaAbsorption();

            float sigmaT =max(sigmaT3.x, max(sigmaT3.y, sigmaT3.z));

            sigmaT = max(sigmaT, 1e-6);

            float dither = NextFloat(rng);

            float medium =
            SampleHeightFogDistance(
            rayState.rayDesc.Origin,
            rayState.rayDesc.Direction,
            tEnd,
            sigmaT,
            dither);
            
            float3 totalScatter = 0.0;
            float targetOpticalDepth = -log(max(1.0 - dither, 1e-6));
            
            if (medium < tEnd)
            {
                float3 scatterPos = rayState.rayDesc.Origin + rayState.rayDesc.Direction * medium;
                
                float densityModifier =
                calcDensityModifier(scatterPos);

                float3 sigmaS =
                sigmaS3 * densityModifier;

                float3 sigmaT =
                sigmaT3 * densityModifier;
                
                float3 scatterWeight = sigmaS / max(sigmaT, 1e-6);

                float4 sunlightColor = getSunColor(float4(0.0, 0.0, 0.0, 0.0)) * 650 * SUN_INTENSITY; 
                sunlightColor.rgb *= sunlightColor.a;
                if(inNether) sunlightColor =0;
                float pdfSun = max(PDF_SunCone(), 1e-4);
                
                float3 sunContribution = sunlightColor.rgb;
                
                sunContribution /= pdfSun;
                shadowPayload payload; 
                RayDesc shadowRay; 
                
                shadowRay.Direction = randConeJitter(mainLightDir, SUN_RADIUS, NextFloat2(rng)); 
                shadowRay.Origin = offset_ray(scatterPos, shadowRay.Direction); 
                shadowRay.TMin = 0.0; 
                shadowRay.TMax = MAX_FOG_DISTANCE; 
                TraceShadowRay(shadowRay, payload); 

                
                bool inWater = g_view.cameraIsUnderWater;
                float VdotL = dot(rayState.rayDesc.Direction, shadowRay.Direction);
                float g = 0.835; // Forward-scattering fog.
                float ambientG = 0.435;
                float sunPhase = inWater ? waterPhase(VdotL) : PhaseHG(VdotL, g);
                

                

                

                float3 directScatter = rayState.throughput *scatterWeight *sunContribution *payload.transmission *sunPhase;


                rayState.color += directScatter;
                float phasePdf;
                float3 nextDirection = SampleHG(
                rayState.rayDesc.Direction,
                ambientG,
                NextFloat2(rng),
                phasePdf);
                float sampledPhase = PhaseHG(
                dot(rayState.rayDesc.Direction, nextDirection),
                ambientG);

                rayState.throughput *= scatterWeight * (sampledPhase / max(phasePdf, 1e-6));
                
                if (i > 1) {
                    // 1. Use perceived luminance instead of raw max component
                    float p = min(1, max(rayState.throughput.x, max(rayState.throughput.y, rayState.throughput.z)));
                    float rr = NextFloat(rng);
                    if (rr >= p) {
                        break;
                    }
                    // 3. Safe division (p is guaranteed >= 0.05f here)
                    rayState.throughput /= p;

                }
                
                rayState.rayDesc.Direction = nextDirection;
                rayState.rayDesc.Origin = offset_ray(scatterPos, rayState.rayDesc.Direction);

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
                i);

                if (i > 1) {
                    // 1. Use perceived luminance instead of raw max component
                    float p = max(rayState.throughput.x, max(rayState.throughput.y, rayState.throughput.z));
                    float rr = NextFloat(rng);
                    if (rr >= p) {
                        break;
                    }
                    // 3. Safe division (p is guaranteed >= 0.05f here)
                    rayState.throughput /= p;

                }
                
                continue;
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
            firstHitDist = min(firstHitDist, maxDistance);
            outputMotion = rayState.motion;
            } else {
            // Eventually hit sky
            outputDistance = maxDistance;
            firstHitDist = maxDistance;
            outputMotion = 0;
        }

        //RenderSky(rayState);
        
        

        //rayState.color = rayMarchFog(rayDesc.Origin, rayDesc.Direction,rayState.color, fogDistance, pixelPos);
        return rayState.color;
    }

#endif