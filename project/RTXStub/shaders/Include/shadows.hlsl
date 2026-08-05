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

void TraceShadowRay(in RayDesc ray, out shadowPayload payload) {
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
            continue;
            
         
        }
        else if (hitInfo.materialType == MATERIAL_TYPE_WATER) {
            GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, object);
            SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, object);
            float3 waterExtinction = calcTransmittance(hitInfo.rayT, getMediaExtinction(MEDIA_TYPE_WATER).rgb);
            float3 caustics = 1..xxx;

            caustics = calcWaterCaustics(mad(getUnderwaterDirectionToSun(), hitInfo.rayT, ray.Origin), hitInfo.rayT);

            transmission *= waterExtinction * caustics;
           continue;
            
        }
        else {
            q.CommitNonOpaqueTriangleHit();
        }
    }

    payload.transmission = q.CommittedStatus() == COMMITTED_NOTHING ? transmission : 0;
}




#endif //SHADOWS_HLSL