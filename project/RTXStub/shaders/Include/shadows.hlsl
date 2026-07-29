#ifndef SHADOWS_HLSL
#define SHADOWS_HLSL

#include "Generated/Signature.hlsl"
#include "Constants.hlsl"
#include "settings.hlsl"
#include "Material.hlsl"
#include "water.hlsl"
#include "brdf.hlsl"

// Set to false by default
#ifndef CULL_GLASS_BACK_FACES
#define CULL_GLASS_BACK_FACES 0
#endif

bool AlphaTestHitLogic(HitInfo hitInfo)
{
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

struct shadowPayload
{
    float3 transmission;
};

void TraceShadowRay(in RayDesc ray, out shadowPayload payload)
{
    RayQuery<RAY_FLAG_NONE> q;
     const uint INSTANCE_MASK_SHADOW = INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_PRIMARY | INSTANCE_MASK_ALPHA_BLEND_PRIMARY | INSTANCE_MASK_WATER;
    float3 transmission = 1;
    for(int i = 0; i < 2; i++)
    {
         q.TraceRayInline(SceneBVH, RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH, INSTANCE_MASK_SHADOW, ray);

    

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
            
           
             float etaI = 1.0;
    float etaT =  1.5;
    float3 N = surfaceInfo.normal;
           float3  direction = ray.Direction;
            float3 F0 = lerp(float3(0.04, 0.04, 0.04), surfaceInfo.color, surfaceInfo.metalness);
    float3 Fv = fresnelSchlick(max(dot(N, -direction), 0.0), F0);

            float3 nextDirection;
    float specularProbability =
    saturate(max(max(Fv.r, Fv.g), Fv.b));

specularProbability = max(specularProbability, 0.04);

// Metals always use the specular lobe.
specularProbability = lerp(specularProbability, 1.0, surfaceInfo.metalness);
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
        
       transmission = 0;
    }
    else
    {
        nextDirection = refracted;
    }

    float3 transmissionWeight = 1.0 - Fv;
    float transmissionProbability = max(1.0 - specularProbability, 1e-4);

    transmission *= transmissionWeight / transmissionProbability;
    ray.Direction = nextDirection;
    ray.Origin = offset_ray(ray.Origin, nextDirection);
    transmission *= lerp(1.0, surfaceInfo.color, 1 - surfaceInfo.alpha);

            if (!any(transmission))
            q.CommitNonOpaqueTriangleHit();
        }
        else if (hitInfo.materialType == MATERIAL_TYPE_WATER) {
            GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, object);
            SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, object);
            float3 waterExtinction = calcTransmittance(hitInfo.rayT, getMediaExtinction(MEDIA_TYPE_WATER).rgb) ;
            float caustics = 1.0;

            caustics = (calcWaterCaustics(mad(getUnderwaterDirectionToSun(), hitInfo.rayT, ray.Origin), hitInfo.rayT));


            transmission = waterExtinction * caustics;

            if (!any(transmission))
                q.CommitNonOpaqueTriangleHit();
        }
        else {
            q.CommitNonOpaqueTriangleHit();
        }
    }

    payload.transmission = q.CommittedStatus() == COMMITTED_NOTHING ? transmission : 0;
    }
   
}




#endif //SHADOWS_HLSL