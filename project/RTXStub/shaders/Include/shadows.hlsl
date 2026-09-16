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

    // Fast-path alpha test: only load UV coordinates and test alpha, avoiding expensive
    // tangent-space matrix solvers, PBR descriptor loads, and heightmap gathers during traversal.
    ObjectInstance objectInstance = objectInstances[hitInfo.objectInstanceIndex];
    uint uv0ByteOffset = objectInstance.offsetPack2 >> 8;
    ByteAddressBuffer vertexBuffer = vertexBuffers[objectInstance.vbIdx];

    uint firstVertexOffsetInQuad = (hitInfo.primitiveId / 2) * 4;
    uint3 vertices = firstVertexOffsetInQuad + (hitInfo.primitiveId & 1 ? uint3(2, 3, 0) : uint3(0, 1, 2));
    float3 bary = float3(1.0 - hitInfo.barycentric2.x - hitInfo.barycentric2.y, hitInfo.barycentric2.xy);

    bool usesUvBias = (objectInstance.flags & kObjectInstanceFlagUsesUvBiasPacking) != 0;
    float2 uv = bary.x * unpackVertexUV(vertexBuffer.Load((vertices[0] + objectInstance.vertexOffsetInBaseVertices) * objectInstance.vertexStride + uv0ByteOffset), usesUvBias)
              + bary.y * unpackVertexUV(vertexBuffer.Load((vertices[1] + objectInstance.vertexOffsetInBaseVertices) * objectInstance.vertexStride + uv0ByteOffset), usesUvBias)
              + bary.z * unpackVertexUV(vertexBuffer.Load((vertices[2] + objectInstance.vertexOffsetInBaseVertices) * objectInstance.vertexStride + uv0ByteOffset), usesUvBias);

    Texture2D colorTex = textures[objectInstance.colourTextureIdx != 0xffff ? objectInstance.colourTextureIdx : g_view.missingTextureIndex];
    float alpha = colorTex.SampleLevel(pointSampler, uv, 0).a;

    float threshold = (objectInstance.flags & (kObjectInstanceFlagAlphaTestThresholdHalf | kObjectInstanceFlagChunk)) ? 0.5 : 0.001;
    return alpha >= threshold;
}

struct shadowPayload { 
    float3 transmission; 
}; 

void TraceShadowRay(in RayDesc ray, out shadowPayload payload) { 
    RayQuery<RAY_FLAG_NONE> q; 
    const uint INSTANCE_MASK_SHADOW = INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_PRIMARY | INSTANCE_MASK_ALPHA_BLEND_PRIMARY | INSTANCE_MASK_WATER; 
    q.TraceRayInline(SceneBVH, RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH, INSTANCE_MASK_SHADOW, ray); 
    
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
                // Fast alpha-blend transmission: avoid full MaterialVanilla evaluation on candidate triangles.
                transmission *= lerp(0.8f.xxx, 0.0f.xxx, object.tintColour0 != 0 ? unpackObjectInstanceTintColor(object.tintColour0).a : 0.2f); 
                
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

// Like TraceShadowRay, but a hit on more subsurface-tagged geometry is treated as
// continuing through the same medium (Beer's-law attenuated) instead of a hard occluder.
// Needed for NEE from *inside* a volumetric SSS medium, where an ordinary shadow ray
// would just immediately self-occlude against the medium's own walls.
void TraceSSSShadowRay(in RayDesc ray, in float3 sigmaT, out shadowPayload payload) {
    float3 transmission = 1.0f.xxx;
    RayDesc segmentRay = ray;
    const int kMaxSSSShadowSegments = 2;

    [loop]
    for (int seg = 0; seg < kMaxSSSShadowSegments; seg++) {
        RayQuery<RAY_FLAG_NONE> q;
        const uint INSTANCE_MASK_SHADOW = INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_PRIMARY | INSTANCE_MASK_ALPHA_BLEND_PRIMARY | INSTANCE_MASK_WATER;
        q.TraceRayInline(SceneBVH, RAY_FLAG_NONE, INSTANCE_MASK_SHADOW, segmentRay);

        while (q.Proceed()) {
            if (q.CandidateType() == CANDIDATE_NON_OPAQUE_TRIANGLE) {
                HitInfo hitInfo = GetCandidateHitInfo(q);
                ObjectInstance object = objectInstances[hitInfo.objectInstanceIndex];

                bool isCloud = object.flags & kObjectInstanceFlagClouds;
                if (isCloud) {
                    transmission *= saturate(1.0f - CLOUD_SHADOW_OPACITY);
                    continue;
                }

                if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST) {
                    if (AlphaTestHitLogic(hitInfo)) {
                        q.CommitNonOpaqueTriangleHit();
                    }
                }
                else if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND) {
                    transmission *= lerp(0.8f.xxx, 0.0f.xxx, object.tintColour0 != 0 ? unpackObjectInstanceTintColor(object.tintColour0).a : 0.2f);
                    continue;
                }
                else if (hitInfo.materialType == MATERIAL_TYPE_WATER) {
                    float3 waterExtinction = calcTransmittance(q.CandidateTriangleRayT(), getMediaExtinction(MEDIA_TYPE_WATER).rgb);
                    transmission *= waterExtinction;
                    continue;
                }
            }
        }

        if (q.CommittedStatus() != COMMITTED_TRIANGLE_HIT) {
            // Reached open sky/space unobstructed.
            payload.transmission = transmission;
            return;
        }

        HitInfo hitInfo = GetCommittedHitInfo(q);
        ObjectInstance object = objectInstances[hitInfo.objectInstanceIndex];
        GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, object);
        SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, object);

        if (surfaceInfo.subsurface <= 0.0f) {
            // A genuine opaque occluder, not more of the same medium.
            payload.transmission = 0.0f.xxx;
            return;
        }

        // Passed into/through more of the same (or another) subsurface medium: attenuate
        // by Beer's law over this segment and keep marching from just past the wall.
        transmission *= calcTransmittance(hitInfo.rayT, sigmaT);
        float3 hitPos = segmentRay.Origin + segmentRay.Direction * hitInfo.rayT;
        segmentRay.Origin = offset_ray(hitPos, segmentRay.Direction);
        segmentRay.TMin = 0.0f;
    }

    // Ran out of segment budget (e.g. deep inside dense/overlapping foliage) — treat as occluded.
    payload.transmission = 0.0f.xxx;
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