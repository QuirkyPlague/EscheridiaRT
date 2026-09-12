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

        float lastBsdfPdf;
        float lastSkyPdf;

        float distance;
        float3 motion;

        uint instanceMask; // 8 bits, see INSTANCE_MASK macros in Constants.hlsl
        bool hitWater;

        void Init()
        {
            color = 0;
            throughput = 1;
            lastBsdfPdf = 0;
            lastSkyPdf = 0;
            distance = 0;
            motion = 0;
            instanceMask = 0xff & ~INSTANCE_MASK_SUN_OR_MOON;
            hitWater = false;
        }
    };

    

    void RenderSky(inout RayState rayState, inout PathRNG rng)
    {
        if (all(rayState.throughput == 0)) return;
        
        //float3 finalColor = skyScattering1(rayState.rayDesc.Direction);
        
        float3 sunDir =  getTrueDirectionToSun();
        float3 moonDir = getTrueDirectionToMoon();

        float sunFade = saturate(sunDir.y);
        float moonFade = saturate(moonDir.y);

        float3 mainLightDir = sunDir;

        float4 sunColor = getSunColor(float4(0.xxxx));
        float sunIntensity = 0;
        const float intensity[8] = {
            4 * 0.6,
            4 * 0.4,
            4 * 0.4,
            4 * 0.2,
            3 * 0.25,
            8 * 0.045,
            8 * 0.07,
            2 * 0.085
        };

        const float times[8] = {
            0.0000000000, // 6000
            0.1920399368, // 3000
            0.3466664553, // 1000
            0.4309642911, // 0
            0.4746705294, // 23500
            0.491301561, // 23000
            0.502156132, // 23000
            0.5303186402
        };

        float time = getTime();

        float timediff = clamp(g_view.skyTextureW - 0.491301561, 0, 0.0253534615);
        timediff *= 1.0 / 0.0253534615;
        sunIntensity = 2 * 0.085;
        
        [unroll] for (int i = 1; i < 8; i++) {
            if (g_view.skyTextureW >= times[i - 1] && g_view.skyTextureW < times[i]) {
                float w = (g_view.skyTextureW - times[i - 1]) / (times[i] - times[i - 1]);
                sunIntensity = lerp(intensity[i - 1], intensity[i], w);

                break;
            }
        }
        sunIntensity = inEnd ? 1.2 : sunIntensity;
        mainLightDir = inEnd ? END_SUN_DIRECTION : mainLightDir;
        // The atmosphere function adds the planet radius internally; pass the
        // existing 1000-meter offset converted to kilometers.
        float3 rayOriginKm = float3(0.0f, 1000.0f, 0.0f) * 0.001f;
        float3 finalColor = RenderHillaireAtmosphereLUTless(
        rayOriginKm,
        rayState.rayDesc.Direction,
        mainLightDir,
        sunIntensity,
        rng,true);
        
        
        rayState.color += rayState.throughput * finalColor;
    }



    void RenderVanilla(HitInfo hitInfo, inout RayState rayState, inout PathRNG rng, in float3 totalRadiance, in float3 directLight, in float3 rayColor, inout float firstHitDist, int bounceCount)
    {
        
        ObjectInstance objectInstance = objectInstances[hitInfo.objectInstanceIndex];
        GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, objectInstance);
        SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, objectInstance);
        
        //surfaceInfo.color = pow(surfaceInfo.color, 2.2);
        
        #if WHITE_FURNACE == 1
            float3 direction = normalize(rayState.rayDesc.Direction);
            float3 V = -direction;
            float3 N = geometryInfo.geometryNormal;
            if (dot(N, V) < 0.0) N = -N;
            N = FixShadingNormal(N, N);

            float3 T, B;
            BuildOrthonormalBasis(N, T, B);
            float3 woLocal = float3(dot(V, T), dot(V, B), dot(V, N));
            float2 XiDiffuse = NextFloat2(rng);
            float4 eonSample = sample_EON(woLocal, 1.0, XiDiffuse.x, XiDiffuse.y);
            float3 wiLocal = eonSample.xyz;
            float3 nextDirection = normalize(T * wiLocal.x + B * wiLocal.y + N * wiLocal.z);
            float NdotL = max(dot(N, nextDirection), 0.0);
            float diffusePdf = max(eonSample.w, 1e-4);
            float3 whiteBRDF = f_EON(1.0.xxx, 1.0, wiLocal, woLocal, true);

            rayState.throughput *= whiteBRDF * NdotL / diffusePdf;
            rayState.rayDesc.Direction = nextDirection;
            rayState.rayDesc.Origin = offset_ray(surfaceInfo.position, nextDirection);
            rayState.distance += hitInfo.rayT;
            rayState.motion += surfaceInfo.position - surfaceInfo.prevPosition;
        #else
            bool inWater = g_view.cameraIsUnderWater;

            float2 Xi = NextFloat2(rng);
            float2 XiSpec = NextFloat2(rng);
            float2 XiDiffuse = NextFloat2(rng);
            float2 XiShadow = NextFloat2(rng);
            float2 XiSky = NextFloat2(rng);
            float3 sunDir =  getDirectionToSun();
            float3 moonDir = -sunDir;

            float sunFade = saturate(sunDir.y);
            float moonFade = saturate(moonDir.y);

            float3 mainLightDir = sunFade > 0.0 ? sunDir : moonDir;
            mainLightDir = inEnd ? END_SUN_DIRECTION : mainLightDir;
            float3 endTwinSunDir = END_TWIN_SUN_DIRECTION;
            if (hitInfo.materialType == MATERIAL_TYPE_WATER) {
                surfaceInfo.roughness = 0.035;
                surfaceInfo.metalness = 0.0;
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
            float3 kS = fresnelSchlick(max(dot(V,N), 0.001), F0);
            

            float specularProbability = saturate(luminance(kS));

            specularProbability = max(specularProbability, 0.04);

            specularProbability = min(specularProbability, 1.0);
            specularProbability = lerp(specularProbability, 1.0, surfaceInfo.metalness);

            float3 throughput = 1.0; 
            bool isTransparentSurface = hitInfo.materialType == MATERIAL_TYPE_WATER || hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND; 
            bool rayRefractedGoesInside = false;
            
            if (isTransparentSurface && !isCloud) {
                
                float3 F_smooth = fresnelSchlick(max(dot(N, -direction), 0.0f), F0); 
                float F_lum = clamp(luminance(F_smooth), 0.02f, 0.98f); 

                float specularProbability = F_lum; 
                float transmissionProbability = 1.0f - specularProbability; 

                if (Xi.x < specularProbability) { 
                    
                    float3 microfacetNormal = SampleVNDFGGX(tangentView, roughness, XiSpec); 
                    float3 tangentReflDir = reflect(-tangentView, microfacetNormal); 
                    nextDirection = normalize(tangentReflDir.x * T + tangentReflDir.y * B + tangentReflDir.z * N); 
                    
                    float3 H = normalize(microfacetNormal.x * T + microfacetNormal.y * B + microfacetNormal.z * N); 
                    float NdotL = max(dot(N, nextDirection), 0.0001f); 
                    float NdotV = max(dot(N, V), 0.0001f); 
                    float NdotH = max(dot(N, H), 0.0001f); 
                    float VdotH = max(dot(V, H), 0.0001f); 
                    
                    float3 F = fresnelSchlick(VdotH, F0); 
                    float D = D_GGX(NdotH, surfaceInfo.roughness); 
                    float G = G_Smith(NdotV, NdotL, surfaceInfo.roughness); 
                    float3 specWeight = (F * D * G) / (4.0f * NdotV * NdotL); 
                    
                    float pdf_r = PDF_GGX_Reflection(NdotV, NdotH, VdotH, surfaceInfo.roughness); 
                    float combinedPdf = max(pdf_r, 1e-6f); 
                    
                    
                    rayColor *= (specWeight * NdotL) / (combinedPdf * specularProbability); 

                    } else { 
                    
                    float IOR = isWater ? 1.333f : 1.5f; 
                    float3 refractionNormal = N; 
                    float eta = 1.0f / IOR; 

                    if (!hitInfo.frontFacing) { 
                        eta = IOR / 1.0f; 
                    } 

                    float3 refracted = refract(direction, refractionNormal, eta); 

                    if (length(refracted) == 0.0f) { 
                        nextDirection = reflect(direction, refractionNormal); 
                        
                        rayColor *= (float3(1.0f, 1.0f, 1.0f) / max(transmissionProbability, 1e-4f));

                        } else { 
                        nextDirection = refracted; 
                        float3 transmissionWeight = (1.0f - F_smooth); 
                        float3 tint = transmissionWeight * surfaceInfo.color;
                        rayColor *= (tint / max(transmissionProbability, 1e-4f));
                    }
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
                float VdotH_d = max(dot(V, H), 0.0001);
                float LdotH = max(dot(nextDirection,H), 0.001);
                float3 rho = surfaceInfo.color * (1.0 - surfaceInfo.metalness);
                float3 diffuseBRDF = f_EON(rho, surfaceInfo.roughness, wi_local, wo_local, USE_ACCURATE_DIFFUSE_BRDF); 
                
                float diffuseProbability = 1.0 - specularProbability; 
                
                float3 weight_d = ((diffuseBRDF * NdotL_d) / (localDiffusePdf * diffuseProbability)); 

                rayColor *= weight_d; 
            }

            
            

            float sunRadius = inEnd ? END_SUN_RADIUS : SUN_RADIUS;

            shadowPayload payload;
            RayDesc shadowRay;
            shadowRay.Origin = offset_ray(surfaceInfo.position, ng);
            shadowRay.Direction = randConeJitter(mainLightDir, sunRadius, XiShadow);
            shadowRay.TMin = 0.0;
            shadowRay.TMax = 1000;
            TraceShadowRay(shadowRay, payload);

            float3 twinSunContribution = 0;
            #if USE_END_TWIN_SUNS
                #if ENABLE_END_SUNLIGHT
                    if(inEnd)
                    {
                        shadowPayload payloadTwinSun;
                        RayDesc shadowRayTwinSun;
                        shadowRayTwinSun.Origin = offset_ray(surfaceInfo.position, ng);
                        shadowRayTwinSun.Direction = randConeJitter(endTwinSunDir, END_TWIN_SUN_RADIUS, XiShadow);
                        shadowRayTwinSun.TMin = 0.0;
                        shadowRayTwinSun.TMax = 1000;
                        TraceShadowRay(shadowRayTwinSun, payloadTwinSun);


                        float3 L1 = normalize(shadowRayTwinSun.Direction);
                        float3 H2 = normalize(L1 + V);

                        float NdotL2 = max(dot(N, L1), 0.0001);
                        float NdotV1 = max(dot(N, V), 0.0001);
                        float NdotH1 = max(dot(N, H2), 0.0001);
                        float VdotH2 = max(dot(V, H2), 0.0001);
                        

                        float3 F = fresnelSchlick(VdotH2, F0);
                        float3 V_local =float3(dot(V,T), dot(V,B), dot(V,N));
                        float3 L_local =float3(dot(L1,T), dot(L1,B), dot(L1,N));

                        float D1 = D_GGX(NdotH1, surfaceInfo.roughness);
                        float G1 = G_Smith(NdotV1, NdotL2, surfaceInfo.roughness); 
                        float3 specular = (F * D1 * G1) / (4.0 * NdotV1 * NdotL2);
                        float3 rho1 = surfaceInfo.color * (1.0f - surfaceInfo.metalness);
                        float3 eonBRDF = f_EON(rho1, surfaceInfo.roughness, L_local, V_local, USE_ACCURATE_DIFFUSE_BRDF);
                        float3 diffuse = (1.0f - F) * eonBRDF;
                        float3 brdf = isTransparentSurface ? specular : diffuse + specular;
                        float diffuseProbability = 1.0 - specularProbability;
                        float3 twinSunColor = END_TWIN_SUN_COLOR.rgb * END_TWIN_SUN_INTENSITY;
                        float pdfSun = max(PDF_twinSunCone(), 1e-4);
                        twinSunContribution = twinSunColor.rgb * brdf * saturate(NdotL2) * payloadTwinSun.transmission * throughput / pdfSun;
                        // Replace standard cosine hemisphere PDF with the exact EON PDF matching your sampler
                        float pdfDiffuse = max(pdf_EON(V_local, L_local, surfaceInfo.roughness), 1e-4);
                        
                        float pdfSpec = PDF_GGX_Reflection(NdotV1, NdotH1, VdotH2, surfaceInfo.roughness);
                        float pdfBRDF = specularProbability * pdfSpec + diffuseProbability * pdfDiffuse;
                        float w = MISWeight(pdfSun, pdfBRDF);
                        twinSunContribution *= w;
                    }
                #endif
            #endif

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
            float3 eonBRDF = f_EON(rho, surfaceInfo.roughness, L_local, V_local, USE_ACCURATE_DIFFUSE_BRDF);
            float3 diffuse = (1.0f - F) * eonBRDF;
            float3 brdf = isTransparentSurface ? specular : diffuse + specular;
            float diffuseProbability = 1.0 - specularProbability;
            float4 sunlightColor = getSunColor(float4(0.0, 0.0, 0.0, 0.0)) * 580 * SUN_INTENSITY;
            sunlightColor.rgb *= sunlightColor.a;
            sunlightColor = lerp(sunlightColor, sunlightColor * RAIN_SUN_INTENSITY_MULTIPLIER, getBiomeAdjustedRainLevel());
            if(inEnd) 
            {
                sunlightColor.rgb = END_SUN_COLOR.rgb * END_SUN_INTENSITY;
                #if ENABLE_END_SUNLIGHT == 0
                    sunlightColor.rgb = 0;
                #endif

            }
            
            if(inNether) sunlightColor = 0;
            
            
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

            
            totalRadiance += sunContribution * w;

            if (g_view.cpuLightsCount > 0)
            {
                uint lightCount = min(g_view.cpuLightsCount, 98304u);
                uint lightIndex = min(uint(NextFloat(rng) * lightCount), lightCount - 1u);
                LightInfo lightInfo = inputLightsBuffer[lightIndex];
                LightData lightData = UnpackLight(lightInfo.packedData);

                float3 toLight = lightInfo.position - surfaceInfo.position;
                float lightDistanceSquared = dot(toLight, toLight);
                float lightDistance = sqrt(max(lightDistanceSquared, 1e-6));
                float3 lightDirection = toLight / lightDistance;
                float NdotLight = max(dot(N, lightDirection), 0.0);

                if (NdotLight > 0.0)
                {
                    float NdotView = max(dot(N, V), 0.0001);
                    float3 halfVector = normalize(V + lightDirection);
                    float NdotHalf = max(dot(N, halfVector), 0.0001);
                    float VdotHalf = max(dot(V, halfVector), 0.0001);
                    float3 lightFresnel = fresnelSchlick(VdotHalf, F0);
                    float lightDistribution = D_GGX(NdotHalf, surfaceInfo.roughness);
                    float lightGeometry = G_Smith(NdotView, NdotLight, surfaceInfo.roughness);
                    float3 lightSpecular = (lightFresnel * lightDistribution * lightGeometry) /
                    max(4.0 * NdotView * NdotLight, 1e-6);

                    float3 localLight = float3(
                    dot(lightDirection, T),
                    dot(lightDirection, B),
                    NdotLight);
                    float3 localView = float3(
                    dot(V, T),
                    dot(V, B),
                    NdotView);
                    float3 diffuseColor = surfaceInfo.color * (1.0 - surfaceInfo.metalness);
                    float3 lightDiffuse = (1.0 - lightFresnel) *
                    f_EON(diffuseColor, surfaceInfo.roughness, localLight, localView, USE_ACCURATE_DIFFUSE_BRDF);
                    float3 lightBRDF = isTransparentSurface ? lightSpecular : lightDiffuse + lightSpecular;

                    RayDesc lightShadowRay;
                    float3 lightShadowTransmission = 0.0;
                    float lightShadowRadius =  POINT_LIGHT_SHADOW_RADIUS;
                    
                    lightShadowRay.Origin = offset_ray(surfaceInfo.position, ng);
                    lightShadowRay.Direction = randConeJitter(
                    lightDirection,
                    lightShadowRadius,
                    NextFloat2(rng));
                    lightShadowRay.TMin = 0.0;
                    lightShadowRay.TMax = max(lightDistance - 0.55, 0.0);

                    shadowPayload lightShadow;
                    TraceShadowRay(lightShadowRay, lightShadow);
                    lightShadowTransmission += lightShadow.transmission;
                    
                    lightShadowTransmission /= float(POINT_LIGHT_SHADOW_SAMPLES);

                    float3 lightRadiance = lightData.color * lightData.intensity * 500;
                    lightRadiance *= NdotLight / max(lightDistanceSquared, 1e-4);
                    lightRadiance *= lightShadowTransmission;
                    lightRadiance *= lightBRDF;
                    lightRadiance *= float(lightCount);
                    totalRadiance += lightRadiance;
                }
            }

            

            totalRadiance += twinSunContribution;

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
            

            float atmosphereT0;
            float atmosphereT1;

            float volumeStart = rayState.rayDesc.TMin;
            float volumeExit = rayState.rayDesc.TMax;

            float ATMOSPHERE_RADIUS = 6420.0f;

            if (RaySphereIntersect(
            rayState.rayDesc.Origin,
            rayState.rayDesc.Direction,
            ATMOSPHERE_RADIUS,
            atmosphereT0,
            atmosphereT1))
            {
                volumeStart = max(volumeStart, atmosphereT0);
                volumeExit = min(volumeExit, atmosphereT1);
            }
            else
            {
                volumeStart = volumeExit;
            }

            float tEnd = min(surface, volumeExit);
            // Construct the homogenous medium
            // https://la.disneyresearch.com/wp-content/uploads/Monte-Carlo-Methods-for-Volumetric-Light-Transport-Simulation-Paper.pdf
            // Construct the homogenous medium

            float3 sigmaS3;

            #if OVERRIDE_END_FOG_SCATTERING
                sigmaS3 = END_FOG_SCATTERING_COLOR * END_FOG_SCATTERING_INTENSITY;
            #else
                sigmaS3 = getScattering();
            #endif

            float3 sigmaT3 =
            inEnd ?
            getMediaPrimaryExtinction() * END_FOG_EXTINCTION_INTENSITY :
            getMediaPrimaryExtinction();

            sigmaT3 = lerp(
            sigmaT3,
            float3(0.0125, 0.0125, 0.0125),
            getBiomeAdjustedRainLevel());

            // Majorant for delta tracking.
           float medium = tEnd;
float densityModifier = 0.0f;
bool mediumScattered = false;

if (volumeStart < tEnd)
{
    float majorant =
        max(sigmaT3.x, max(sigmaT3.y, sigmaT3.z));

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

        densityModifier = calcDensityModifier(candidatePos);

        float3 localSigmaT3 =
            sigmaT3 * densityModifier;

        float localSigmaT =
            max(localSigmaT3.x,
                max(localSigmaT3.y, localSigmaT3.z));

        if (NextFloat(rng) < localSigmaT / majorant)
        {
            medium = t;
            mediumScattered = true;
            break;
        }
    }
}

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

                float4 sunlightColor = getSunColor(float4(0.0, 0.0, 0.0, 0.0)) * 650 * SUN_INTENSITY; 
                sunlightColor.rgb *= sunlightColor.a;
                sunlightColor = lerp(sunlightColor, sunlightColor * RAIN_SUN_INTENSITY_MULTIPLIER, getBiomeAdjustedRainLevel());
                if(inEnd) sunlightColor.rgb = END_SUN_COLOR.rgb * END_SUN_INTENSITY;
                if(inNether) sunlightColor =0;
                float pdfSun = max(PDF_SunCone(), 1e-4);
                
                float3 sunContribution = sunlightColor.rgb * END_FOG_DIRECT_SCATTER_BOOST;
                
                sunContribution /= pdfSun;
                float sunRadius = inEnd ? END_SUN_RADIUS : SUN_RADIUS;
                shadowPayload payload; 
                RayDesc shadowRay; 
                
                shadowRay.Direction = randConeJitter(mainLightDir, sunRadius, NextFloat2(rng)); 
                shadowRay.Origin = offset_ray(scatterPos, shadowRay.Direction); 
                shadowRay.TMin = 0.0; 
                shadowRay.TMax = 1000; 
                TraceShadowRay(shadowRay, payload); 

                float3 twinSunContribution = 0;

                #if USE_END_TWIN_SUNS
                    #if ENABLE_END_SUNLIGHT
                        if(inEnd)
                        {
                            float3 sunlightColor = END_TWIN_SUN_COLOR * END_TWIN_SUN_INTENSITY; 
                            float pdfSun = max(PDF_twinSunCone(), 1e-4);
                            
                            float3 sunContribution = sunlightColor.rgb * 3.2;
                            
                            sunContribution /= pdfSun;
                            float sunRadius = END_TWIN_SUN_RADIUS;
                            shadowPayload payload; 
                            RayDesc shadowRay; 
                            
                            shadowRay.Direction = randConeJitter(endTwinSunDir, sunRadius, NextFloat2(rng)); 
                            shadowRay.Origin = offset_ray(scatterPos, shadowRay.Direction); 
                            shadowRay.TMin = 0.0; 
                            shadowRay.TMax = 1000; 
                            TraceShadowRay(shadowRay, payload); 
                            float VdotL = dot(rayState.rayDesc.Direction, shadowRay.Direction);
                            float g =  0.61; // Forward-scattering fog.
                            float sunPhase = PhaseDraine(VdotL, g, DRAINE_ALPHA); 
                            twinSunContribution = rayState.throughput *scatterWeight *sunContribution *payload.transmission * sunPhase;
                            
                        }
                    #endif
                #endif
                
                bool inWater = g_view.cameraIsUnderWater;
                float VdotL = dot(rayState.rayDesc.Direction, shadowRay.Direction);
                float g = inEnd ? END_FOG_ANISOTROPY : 0.735; // Forward-scattering fog.
                float ambientG = inEnd ? END_FOG_INDIRECT_ANISOTROPY : 0.635;
                float sunPhase = inWater ? waterPhase(VdotL) : PhaseDraine(VdotL, g, DRAINE_ALPHA);

                
                
                #if ENABLE_SUNLIGHT == 0
                    sunContribution = 0;
                #endif
                

                

                float3 directScatter = rayState.throughput * scatterWeight *
                (sunContribution * payload.transmission * sunPhase + twinSunContribution);
                

                rayState.color += directScatter;
                float phasePdf;
                float3 nextDirection = SampleDraine(
                rayState.rayDesc.Direction,
                ambientG,
                DRAINE_ALPHA,
                NextFloat2(rng),
                rng,
                phasePdf);

                float sampledPhase = PhaseDraine(
                dot(rayState.rayDesc.Direction, nextDirection),
                ambientG,
                DRAINE_ALPHA);

                rayState.throughput *= scatterWeight * (sampledPhase / max(phasePdf, 1e-6));
                
                
                rayState.rayDesc.Direction = nextDirection;
                rayState.rayDesc.Origin = offset_ray(scatterPos, rayState.rayDesc.Direction);

                float throughputMax = max(
                rayState.throughput.x,
                max(rayState.throughput.y, rayState.throughput.z)
                );

                if (throughputMax < 0.01)
                {
                    float survive = saturate(throughputMax / 0.1);

                    if (NextFloat(rng) > survive)
                    break;

                    rayState.throughput /= survive;
                }


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

                
                
            }
            else
            {
                RenderSky(rayState, rng);
                break;
            }
            
            if (i > 1) {
                float throughputLuminance = luminance(rayState.throughput);
                float p = clamp(throughputLuminance, 0.05, 0.95);

                if (NextFloat(rng) >= p)
                {
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
        
        
        

        //rayState.color = rayMarchFog(rayDesc.Origin, rayDesc.Direction,rayState.color, fogDistance, pixelPos);
        return rayState.color;
    }

#endif