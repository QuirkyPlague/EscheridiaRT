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

struct shadowPayload { 
    float3 transmission; 
}; 

void TraceShadowRay(in RayDesc ray, out shadowPayload payload) { 
    RayQuery<RAY_FLAG_NONE> q; 
    const uint INSTANCE_MASK_SHADOW = INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_PRIMARY | INSTANCE_MASK_ALPHA_BLEND_PRIMARY | INSTANCE_MASK_WATER; 
    
    // CRITICAL: Removed RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH.
    // We need the query to traverse through overlapping transparent surfaces.
    q.TraceRayInline(SceneBVH, RAY_FLAG_NONE, INSTANCE_MASK_SHADOW, ray); 
    
    float3 transmission = 1.0f.xxx; 
    
    while (q.Proceed()) { 
        // We are processing a candidate triangle/object interaction
        if (q.CandidateType() == CANDIDATE_NON_OPAQUE_TRIANGLE) {
            HitInfo hitInfo = GetCandidateHitInfo(q); 
            ObjectInstance object = objectInstances[hitInfo.objectInstanceIndex]; 
            
            bool isCloud = object.flags & kObjectInstanceFlagClouds; 
            
            if (isCloud) { 
                // Simple cloud shadow approximation
                transmission *= saturate(1.0f - CLOUD_SHADOW_OPACITY); 
                // DO NOT commit. We want to skip past this cloud and keep looking.
                continue; 
            } 
            
            if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST) { 
                if (AlphaTestHitLogic(hitInfo)) { 
                    // This is an actual cutout block (like leaves/fence). 
                    // It is completely opaque, so we commit it and stop searching.
                    q.CommitNonOpaqueTriangleHit(); 
                } 
                // If AlphaTestHitLogic fails, it's air. We just continue without committing.
            } 
            else if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND) { 
                GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, object); 
                SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, object); 
                
                // Attenuate light passing through alpha blended surface
                transmission *= lerp(surfaceInfo.color, 0.0f.xxx, surfaceInfo.alpha); 
                
                // Crucial step: Do NOT call CommitNonOpaqueTriangleHit(). 
                // If you commit, the ray terminates. We want to pass right through!
                continue; 
            } 
            else if (hitInfo.materialType == MATERIAL_TYPE_WATER) { 
                GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, object); 
                
                // Get depth from shadow ray origin to water intersection point
                float3 waterExtinction = calcTransmittance(q.CandidateTriangleRayT(), getMediaExtinction(MEDIA_TYPE_WATER).rgb); 
                transmission *= waterExtinction; 
                
                // Pass right through the water interface plane to look for ground
                continue; 
            } 
        }
    } 
    
    // FINAL SHADOW CHECK
    // If the loop finished and committed an actual hit (an opaque object or passed alpha-test), 
    // the beam is completely occluded. Otherwise, return the accumulated transmission.
    if (q.CommittedStatus() == COMMITTED_TRIANGLE_HIT) {
        payload.transmission = 0.0f.xxx;
    } else {
        payload.transmission = transmission; 
    }
}

struct TransmissionPayload{
    float3 transmission;
};

void castTransmissionRay(in RayDesc ray, out TransmissionPayload payload) {
    float3 emissive = 0..xxx;
    RayQuery<RAY_FLAG_NONE> query;

   const uint INSTANCE_MASK_SHADOW = INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_SECONDARY | INSTANCE_MASK_ALPHA_BLEND_SECONDARY | INSTANCE_MASK_WATER;
      
    query.TraceRayInline(SceneBVH, RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES, INSTANCE_MASK_WATER, ray);
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
        else if (hitInfo.materialType == MATERIAL_TYPE_WATER) {
            GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, object);
            SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, object);

            float alphablend = 1 - surfaceInfo.alpha;
            float3 waterExtinction = calcTransmittance(hitInfo.rayT, getMediaExtinction(MEDIA_TYPE_WATER).rgb);
            transmission *= waterExtinction;

            if (!any(transmission))
            {
                 query.CommitNonOpaqueTriangleHit();
                
            }
           
        }
        else
        {
             query.CommitNonOpaqueTriangleHit();
        }
     
    }
      
     payload.transmission =  transmission;
}



#endif //SHADOWS_HLSL