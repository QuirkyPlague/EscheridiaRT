#ifndef GI_HLSL
#define GI_HLSL

#include "Generated/Signature.hlsl"
#include "Material.hlsl"
#include "settings.hlsl"
#include "Util.hlsl"
#include "shadows.hlsl"
#include "brdf.hlsl"
#include "tonemapping.hlsl"

struct GiHitPayload {

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

void TraceGIBounce(in RayDesc ray, out GiHitPayload payload, bool isSecondary) {
    RayQuery<RAY_FLAG_NONE> query;
    
    if(!isSecondary)
    {
        query.TraceRayInline(SceneBVH, RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES, 0xff, ray);
    }
    else
    {
        query.TraceRayInline(SceneBVH, RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH, 0xff, ray);
    }
    

    payload.hit = false;
    float3 transmission = 1.0;
    while(query.Proceed()) {
        
        HitInfo hitInfo = GetCandidateHitInfo(query);
        ObjectInstance object = objectInstances[hitInfo.objectInstanceIndex];
        if (object.flags & (kObjectInstanceFlagSun | kObjectInstanceFlagMoon)) {
            payload.color = 0.0;
            break;
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
        payload.direction = ray.Direction;
        payload.color = hitSurface.color;
        payload.emission = hitSurface.emissive;
        payload.roughness = hitSurface.roughness;
        payload.metalness = hitSurface.metalness;
        payload.alpha = hitSurface.alpha;
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


#endif