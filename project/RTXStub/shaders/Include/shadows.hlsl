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
                    continue; 
                } 
                
                if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST) { 
                    if (AlphaTestHitLogic(hitInfo)) { 

                        q.CommitNonOpaqueTriangleHit(); 
                    } 

                } 
                else if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND) { 
                    GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, object); 
                    SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, object); 
                    
                    // Attenuate light passing through alpha blended surface
                    transmission *= lerp(surfaceInfo.color, 0.0f.xxx, surfaceInfo.alpha); 
                    
                    continue; 
                } 
                else if (hitInfo.materialType == MATERIAL_TYPE_WATER) { 
                    GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, object); 
                    
                    // Get depth from shadow ray origin to water intersection point
                    float3 waterExtinction = calcTransmittance(q.CandidateTriangleRayT(), getMediaExtinction(MEDIA_TYPE_WATER).rgb); 
                    transmission *= waterExtinction; 
                    
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
            q.TraceRayInline(SceneBVH, RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES, INSTANCE_MASK_SHADOW, segmentRay);

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
                          GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, object); 
                    SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, object); 
                    
                    // Attenuate light passing through alpha blended surface
                    transmission *= lerp(surfaceInfo.color, 0.0f.xxx, surfaceInfo.alpha); 
                    
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





#endif //SHADOWS_HLSL