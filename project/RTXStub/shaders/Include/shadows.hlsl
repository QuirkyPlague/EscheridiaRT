#ifndef SHADOWS_HLSL
#define SHADOWS_HLSL

#include "Generated/Signature.hlsl"
#include "Material.hlsl"
#include "settings.hlsl"
#include "water.hlsl"
#include "Util.hlsl" 

// Set to true for alpha blend backface culling on shadow and secondary rays.
#define CULL_GLASS_BACK_FACES 0
static const uint SECONDARY_TRACE_MASK =
    INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_SECONDARY |
    INSTANCE_MASK_WATER;

bool AlphaTestHitLogic(HitInfo hitInfo) {
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

struct ShadowPayload {
    float3 transmission;
};
void TraceShadowRay(in RayDesc ray, out ShadowPayload payload) {
    RayQuery<RAY_FLAG_NONE> q;
     const uint INSTANCE_MASK_SHADOW = INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_PRIMARY | INSTANCE_MASK_ALPHA_BLEND_PRIMARY | INSTANCE_MASK_WATER;

    q.TraceRayInline(SceneBVH, RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH, INSTANCE_MASK_SHADOW, ray);

    float3 transmission = 1;

    while (q.Proceed()) {
        HitInfo hitInfo = GetCandidateHitInfo(q);
        ObjectInstance object = objectInstances[hitInfo.objectInstanceIndex];
        bool isCloud = object.flags & kObjectInstanceFlagClouds;

        if (isCloud) {
            // Simple cloud shadow approximation
            transmission *= saturate(1.0 - CLOUD_SHADOW_OPACITY);
            continue;
        };

        if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST) {
            if (AlphaTestHitLogic(hitInfo)) {
                q.CommitNonOpaqueTriangleHit();
            }
        }
        else if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND && !isCloud) {
            GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, object);
            SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, object);


            transmission *= lerp(surfaceInfo.color, 0..xxx, surfaceInfo.alpha);

            if (!any(transmission))
            q.CommitNonOpaqueTriangleHit();
        }
        else if (hitInfo.materialType == MATERIAL_TYPE_WATER) {
            GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, object);
            SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, object);
            float3 waterExtinction = calcTransmittance(hitInfo.rayT, getMediaExtinction(MEDIA_TYPE_WATER).rgb);
            float3 caustics = 1..xxx;
#if USE_TEXTURE_CAUSTICS == 0
            caustics = calcWaterCaustics(mad(getUnderwaterDirectionToSun(), hitInfo.rayT, ray.Origin), hitInfo.rayT);
#else
            //caustics approximation based off surface normal and waves
            //From thallium
            float3 geoNormal = geometryInfo.geometryNormal;
            const float waveSmoothness = WAVE_SMOOTHING;
            const float waveStrength = WAVE_INTENSITY;
            float3 worldPos = surfaceInfo.position - g_view.waveWorksOriginInSteveSpace;
            worldPos = worldPos - floor(worldPos / 1024) * 1024; // Bedrock may reset position every 1024 blocks, so we can only reliably calculate world position within 1024 blocks chunk.

            float3 waveNorm = surfaceInfo.normal;

            waveNorm = waveNormal(worldPos.xz, waveSmoothness, waveStrength);
            float geoNdotL = max(dot(geoNormal, ray.Direction), 0.0);
            float waveNdotL = max(dot(waveNorm, ray.Direction), 0.0);

            //prevents caustics on the surface
            caustics = pow(waveNdotL / geoNdotL, 32.0) ;
            caustics = clamp(caustics, 0.13, 3.0);

#endif
            transmission *= waterExtinction * caustics;

            if (!any(transmission))
            q.CommitNonOpaqueTriangleHit();
        }
        else {
            q.CommitNonOpaqueTriangleHit();
        }
    }

    payload.transmission = q.CommittedStatus() == COMMITTED_NOTHING ? transmission : 0;
}

void getShadow(SurfaceInfo surfaceInfo, float3 lightDir, float2 noise, inout float3 shadowTransmission) {
    const uint shadowSteps = SUN_SHADOW_SAMPLES;

    float3 T = normalize(cross(
            abs(lightDir.z) < 0.999 ?
            float3(0,0,1) :
            float3(1,0,0),
            lightDir));

    float3 B = cross(lightDir, T);

    const float sunRadius = SUN_RADIUS; 
    float3 transmission = 0;
    for(uint i = 0; i < shadowSteps; i++) {
        float2 Xi = frac(noise + float2(
                i * 0.61803398875,
                i * 0.38196601125));

        float r = sunRadius * sqrt(Xi.x);
        float theta = 2.0 * PI * Xi.y;

        float2 disk = r * float2(
            cos(theta),
            sin(theta));

        float3 sampleDir = normalize(
            lightDir +
            disk.x * T +
            disk.y * B);

        RayDesc shadowRay;
        shadowRay.Origin =
        surfaceInfo.position +
        1.0e-4 * surfaceInfo.normal;

        shadowRay.Direction = sampleDir;
        shadowRay.TMin = 0.0;
        shadowRay.TMax = MAX_TRACE_DISTANCE;

        ShadowPayload payload;
        TraceShadowRay(shadowRay, payload);

        transmission += payload.transmission;
    }

    shadowTransmission =
    transmission / float(shadowSteps);
}

struct skyShadowPayload {
    float3 transmission;
};

void TraceSkyShadowRay(in RayDesc ray, out skyShadowPayload payload) {
    RayQuery<RAY_FLAG_NONE> q;
    q.TraceRayInline(SceneBVH,  RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES, SECONDARY_TRACE_MASK, ray);

    float3 transmission = 1;

    while (q.Proceed()) {
        HitInfo hitInfo = GetCandidateHitInfo(q);
        ObjectInstance object = objectInstances[hitInfo.objectInstanceIndex];
        bool isCloud = object.flags & kObjectInstanceFlagClouds;

        if (isCloud) {
            continue;
        };

        if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST) {
            if (AlphaTestHitLogic(hitInfo)) {
                q.CommitNonOpaqueTriangleHit();
            }
        }
        else if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND && !isCloud) {
            GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, object);
            SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, object);
            transmission *= (1.0 - surfaceInfo.alpha) * surfaceInfo.color;

            if (!any(transmission))
            q.CommitNonOpaqueTriangleHit();
        }
        else if (hitInfo.materialType == MATERIAL_TYPE_WATER) {
            // Simple water transmission approximation
            transmission *= calcTransmittance(hitInfo.rayT, getMediaExtinction(MEDIA_TYPE_WATER).rgb);

            if (!any(transmission))
            q.CommitNonOpaqueTriangleHit();
        }
        else {
            //transmission *= calcTransmittance(hitInfo.rayT, getMediaExtinction(MEDIA_TYPE_AIR).rgb);
            q.CommitNonOpaqueTriangleHit();
        }
    }

    payload.transmission = q.CommittedStatus() == COMMITTED_NOTHING ? transmission : 0;
}

void skyShadow(SurfaceInfo surfaceInfo, float2 noise, inout float3 shadowTransmission) {
    const uint skySample = SKY_OCCLUSION_SAMPLES;
    skyShadowPayload payload;
    float3 transmission = 0;
    for(uint i = 0; i < skySample; i++) {
        float2 Xi = frac(noise + float2(
                i * 0.61803398875,
                i * 0.38196601125));

        float3 sampleDir = CosineHemisphereSampling(Xi, surfaceInfo.normal);

        RayDesc shadowRay;
        shadowRay.Origin =
        surfaceInfo.position +
        1.0e-4 * surfaceInfo.normal;

        shadowRay.Direction = sampleDir;
        shadowRay.TMin = 0.001f;
        shadowRay.TMax = MAX_TRACE_DISTANCE;

        TraceSkyShadowRay(shadowRay, payload);

        transmission += payload.transmission;
    }

    shadowTransmission =
    transmission / float(skySample);
}

struct reflectionRay {
    float3 position;
    float3 direction;
    float3 color;
    float3 normal;
    float roughness;
    float metalness;
    float emission;
    float alpha;
    float3 transmission;
    bool hit;
};

void traceReflectionRay(in RayDesc ray, out reflectionRay payload, bool isSecondary) {
    RayQuery<RAY_FLAG_NONE> query;
       const uint INSTANCE_MASK_SHADOW = INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_SECONDARY | INSTANCE_MASK_ALPHA_BLEND_SECONDARY | INSTANCE_MASK_WATER;
       if(!isSecondary)
       {
           query.TraceRayInline(SceneBVH, RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES, INSTANCE_MASK_SHADOW, ray);
       }
       else
       {
           query.TraceRayInline(SceneBVH, RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH, INSTANCE_MASK_SHADOW, ray);
       }
 

    payload.hit = false;
    float3 transmission = 1.0;
    while(query.Proceed()) {
        
        HitInfo hitInfo = GetCandidateHitInfo(query);
        ObjectInstance object = objectInstances[hitInfo.objectInstanceIndex];
        if (object.flags & (kObjectInstanceFlagSun | kObjectInstanceFlagMoon)) {
            payload.color = 0.0;
        }

        if(hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST) {
            if(AlphaTestHitLogic(hitInfo)) {
                query.CommitNonOpaqueTriangleHit();
                break;
            }
            continue;
        }
        else if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND) {
            GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, object);
            SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, object);


            transmission *= lerp(surfaceInfo.color, 0..xxx, surfaceInfo.alpha);

            if (!any(transmission))
            query.CommitNonOpaqueTriangleHit();
        }
        else {
            query.CommitNonOpaqueTriangleHit();
        }
    }

    if(query.CommittedStatus() != COMMITTED_NOTHING) {
        HitInfo hitInfo = GetCommittedHitInfo(query);

        ObjectInstance object =
        objectInstances[hitInfo.objectInstanceIndex];

        GeometryInfo geometryInfo =
        GetGeometryInfo(hitInfo, object);

        SurfaceInfo hitSurface =
        MaterialVanilla(
            hitInfo,
            geometryInfo,
            object);

        payload.hit = true;
       if (object.flags & (kObjectInstanceFlagSun | kObjectInstanceFlagMoon)) {
                payload.color = 0;
                payload.hit = false;
            }
    

        payload.position = hitSurface.position;
        float3 direction = normalize(hitSurface.position);
        payload.normal = normalize(hitSurface.normal);
        payload.direction = reflect(-direction, payload.normal);
        payload.color = hitSurface.color;
        payload.emission = hitSurface.emissive;
        payload.roughness = hitSurface.roughness;
        payload.metalness = hitSurface.metalness;
        payload.alpha = hitSurface.alpha;
        payload.color *= payload.alpha;
        payload.transmission = transmission;
    }
    else {


  

        payload.hit = false;
    
        payload.position = 0;
  
        payload.normal =0;
        payload.direction = ray.Direction;
        payload.color = 0.0;
        payload.emission = 0.0;
        payload.roughness = 0.0;
        payload.metalness = 0.0;
        payload.alpha = 0.0;
        payload.transmission = transmission;
    }
}

struct TransmissionPayload
{
    float3 transmission;
};

void castTransmissionRay(in RayDesc ray, out TransmissionPayload payload) {
    float3 emissive = 0..xxx;
    RayQuery<RAY_FLAG_NONE> query;

   const uint INSTANCE_MASK_SHADOW = INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_SECONDARY | INSTANCE_MASK_ALPHA_BLEND_SECONDARY | INSTANCE_MASK_WATER;
      
    query.TraceRayInline(SceneBVH, RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES, INSTANCE_MASK_SHADOW, ray);
    float3 transmission = 1.0;
    while(query.Proceed()) {
        HitInfo hitInfo = GetCandidateHitInfo(query);
        
    
        ObjectInstance object = objectInstances[hitInfo.objectInstanceIndex];
        bool isCloud = object.flags & kObjectInstanceFlagClouds;

        if (isCloud) {
            // Simple cloud shadow approximation
            transmission *= saturate(1.0 - CLOUD_SHADOW_OPACITY);
            continue;
        };

         if (object.flags & (kObjectInstanceFlagSun | kObjectInstanceFlagMoon)) {
            continue;
        }

        if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST) {
            if (AlphaTestHitLogic(hitInfo)) {
                query.CommitNonOpaqueTriangleHit();
            }
        }
        else if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND && !isCloud) {
            GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, object);
            SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, object);

            float alphablend = 1 - surfaceInfo.alpha;
            transmission *= lerp(surfaceInfo.color, 0..xxx, surfaceInfo.alpha) * alphablend;
          

            if (!any(transmission))
            {
                 query.CommitNonOpaqueTriangleHit();
                
            }
           
        }
        else
        {
             query.CommitNonOpaqueTriangleHit();
        }
        // Terminate rays that can't contribute anymore.
    }
      if(query.CommittedStatus() != COMMITTED_NOTHING) {
         HitInfo hitInfo = GetCommittedHitInfo(query);

        ObjectInstance object =
        objectInstances[hitInfo.objectInstanceIndex];

        GeometryInfo geometryInfo =
        GetGeometryInfo(hitInfo, object);

        SurfaceInfo hitSurface =
        MaterialVanilla(
            hitInfo,
            geometryInfo,
            object);
            //transmission = hitSurface.color * hitSurface.alpha * transmission;
      }
     payload.transmission =  transmission;
}
#endif // SHADOWS_HLSL