#ifndef SHADOWS_HLSL
#define SHADOWS_HLSL

#include "Generated/Signature.hlsl"
#include "Material.hlsl"
#include "settings.hlsl"

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

struct ShadowPayload
{
    float3 transmission;
};
void TraceShadowRay(in RayDesc ray, out ShadowPayload payload)
{
    RayQuery<RAY_FLAG_NONE> q;
    const uint INSTANCE_MASK_SHADOW = INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_SECONDARY | INSTANCE_MASK_ALPHA_BLEND_SECONDARY | INSTANCE_MASK_WATER;
    q.TraceRayInline(SceneBVH, RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES, INSTANCE_MASK_SHADOW, ray);

    float3 transmission = 1;

    while (q.Proceed())
    {
        HitInfo hitInfo = GetCandidateHitInfo(q);
        ObjectInstance object = objectInstances[hitInfo.objectInstanceIndex];
        bool isCloud = object.flags & kObjectInstanceFlagClouds;
        
        if (isCloud)
        {
            // Simple cloud shadow approximation
            transmission *= 0.7;
            continue;
        };

        if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST)
        {
            if (AlphaTestHitLogic(hitInfo))
            {
                q.CommitNonOpaqueTriangleHit();
            }
        }
        else if (hitInfo.materialType == MATERIAL_TYPE_ALPHA_BLEND && !isCloud)
        {
            GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, object);
            SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, object);
            transmission *= (1.0 - surfaceInfo.alpha) * surfaceInfo.color;
            
            if (!any(transmission))
                q.CommitNonOpaqueTriangleHit();
        }
        else if (hitInfo.materialType == MATERIAL_TYPE_WATER)
        {
            // Simple water transmission approximation
            transmission *= float3(0.2, 0.5, 0.8);
            if (!any(transmission))
                q.CommitNonOpaqueTriangleHit();
        }
        else
        {
            q.CommitNonOpaqueTriangleHit();
        }
    }

    payload.transmission = q.CommittedStatus() == COMMITTED_NOTHING ? transmission : 0;
}

void getShadow(SurfaceInfo surfaceInfo, float3 lightDir, float2 noise, inout float3 shadowTransmission)
{   
    const uint shadowSteps = 4;

    float3 T = normalize(cross(
        abs(lightDir.z) < 0.999 ?
        float3(0,0,1) :
        float3(1,0,0),
        lightDir));

    float3 B = cross(lightDir, T);

    const float sunRadius = SUN_RADIUS; 
    float3 transmission = 0;
    for(uint i = 0; i < shadowSteps; i++)
    {
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
        shadowRay.TMax = 10000.0;

        ShadowPayload payload;
        TraceShadowRay(shadowRay, payload);

        transmission += payload.transmission;
    }

    shadowTransmission =
        transmission / float(shadowSteps);
}




#endif // SHADOWS_HLSL