#ifndef DIRECT_LIGHTING_HLSL
    #define DIRECT_LIGHTING_HLSL

    #include "Material.hlsl"
    #include "Util.hlsl"
    #include "shadows.hlsl"
    #include "fog.hlsl"

    struct DirectLight
    {
        float3 direction;
        float3 color;
        float intensity;
        float radius;
        bool isActive;
        float3 shadowTransmittance;
        float3 radiance;
        void setUp(float3 lightDir, float3 lightCol, float lightIntensity, float lightRadius, bool isLightActive)
        {
            direction = lightDir;
            color = lightCol;
            intensity = lightIntensity;
            radius = lightRadius;
            isActive = isLightActive;
            shadowTransmittance = 1.0.xxx;
            radiance = 0.0.xxx;
        }
    };

    DirectLight sampleDirectLightData(in float3 direction, in float3 color, in float intensity, in float radius, in bool isActive, in SurfaceInfo surface, float3 N, in float3 geoNormal, in float3 viewDirection, in float3 diffuseWeight, in PathRNG rng)
    {
        DirectLight light;
        light.setUp(direction, color, intensity, radius, isActive);

        // NEE Time 
        shadowPayload payload;
        RayDesc ray;
        ray.Origin = offset_ray(surface.position, geoNormal);
        ray.Direction = randConeJitter(light.direction, light.radius, NextFloat2(rng));
        ray.TMin = 0.000;
        ray.TMax = 1000;
        TraceShadowRay(ray, payload);
        light.shadowTransmittance = payload.transmission;

        // now we have the ray set up. so now we will get the diffuse and spec contribution and weight them
        float3 L = normalize(ray.Direction);

        float3 V = normalize(viewDirection);
        float3 H = normalize(L + V);

        // Necessary dot products
        float NdotL = max(dot(N, L), 0.0001);
        float NdotV = max(dot(N, V), 0.0001);
        float NdotH = max(dot(N, H), 0.0001);
        float VdotH = max(dot(V, H), 0.0001);
        
        float3 F0 = surface.F0;
        float3 albedo = surface.color * (1.0 - surface.metalness);

        float3 diffuseBRDF = float3(0.0, 0.0, 0.0);

        #if DIFFUSE_METHOD == 2
            // Exact reciprocal shell boundaries for Hammon Conserving
            float3 F_V = fresnelSchlick(NdotV, F0);
            float3 F_L = fresnelSchlick(NdotL, F0);
            float3 transmission = (float3(1.0, 1.0, 1.0) - F_V) * (float3(1.0, 1.0, 1.0) - F_L);

            // Compute Hammon's roughness profile scaling shapes
            float facingFactor = 0.5 + 2.0 * VdotH * VdotH * surface.roughness;
            float3 hammonShape = transmission * (1.0 + (facingFactor - 1.0) * pow(1.0 - NdotV, 5.0)) 
            * (1.0 + (facingFactor - 1.0) * pow(1.0 - NdotL, 5.0));

            float rawNdotL = dot(N, L);
            if (rawNdotL < 0.0)
            {
                diffuseBRDF = 0.0;
            }
            // Incorporate material properties and external script constraints
            diffuseBRDF = (hammonShape * albedo * diffuseWeight) / PI;
            
        #else 
            // Default Baseline: Lambert
            float3 kS = fresnelSchlick(VdotH, F0);
            float3 kD = (1.0 - kS) * (1.0 - surface.metalness); // Ensure metalness constraint matches path tracing
            
            float rawNdotL = dot(N, L);
            if (rawNdotL < 0.0)
            {
                diffuseBRDF = 0.0;
            }
            diffuseBRDF = (kD * albedo / PI) * diffuseWeight;
        #endif

        float D = D_GGX(NdotH, surface.roughness);
        float G = G_Smith(NdotV, NdotL, surface.roughness); 
        float3 specularBRDF = (fresnelSchlick(VdotH, F0) * D * G) / (4.0 * NdotV * NdotL);
        float3 BRDF = diffuseBRDF + specularBRDF;

        float pdfSun = max(PDF_SunCone(), 1e-4);
        float3 fogExtinction = GetAtmosphereSunTransmittance(surface.position, ray.Direction, rng, 4);
        light.color *= light.intensity;
        light.radiance += light.color  * BRDF * NdotL * light.shadowTransmittance / pdfSun; 
        return light;
    }

    DirectLight sampleVolumetricDirectLightData(in float3 direction, in float3 color, in float intensity, in float radius, in bool isActive, in float3 position, in float3 rayDir, in PathRNG rng)
    {
        DirectLight light;
        light.setUp(direction, color, intensity, radius, isActive);

        // NEE Time 
        shadowPayload payload;
        RayDesc ray;
        ray.Origin = offset_ray(position, rayDir);
        ray.Direction = randConeJitter(light.direction, light.radius, NextFloat2(rng));
        ray.TMin = 0.000;
        ray.TMax = 1000;
        TraceShadowRay(ray, payload);
        light.shadowTransmittance = payload.transmission;

        float pdfSun = max(PDF_SunCone(), 1e-4);
        float3 fogExtinction = GetAtmosphereSunTransmittance(position, ray.Direction, rng, 4);
        light.direction = ray.Direction;
        light.color *= light.intensity;
        light.radiance += light.color * light.shadowTransmittance / pdfSun; 
        return light;
    }


    float3 sampleDirectLight(float3 L, float3 N, float3 V, in SurfaceInfo surface )
    {
        // We need to do NEE for sun 
        // Dummy code because idk if i wanna do this in a struct or separate 
        // update i did it as a function in the struct
        // this code is funny and will stay >:)
        // Also using the vertex shader tm* of 0.8
        // We love you vertex shader
        DirectLight dick;
        // set up the struct using the certified 0.8 value
        // order is direction, color, intensity, radius, isActive
        dick.setUp(0.8.xxx, 0.8.xxx, 0.8, 0.8, true);
        float3 balls = 0.8.xxx;
        return balls * dick.direction;
    }

#endif // DIRECT_LIGHTING_HLSL