#ifndef GI_HLSL
#define GI_HLSL

#include "Generated/Signature.hlsl"
#include "Material.hlsl"
#include "settings.hlsl"
#include "Util.hlsl"
#include "shadows.hlsl"



struct GiHitPayload
{
    bool hit;

    float3 position;
    float3 normal;
    float3 albedo;
};

void TraceGiBounce(in RayDesc ray, out GiHitPayload payload)
{
    payload.hit = false;

    RayQuery<RAY_FLAG_NONE> q;

    const uint INSTANCE_MASK_SHADOW = INSTANCE_MASK_OPAQUE_OR_ALPHA_TEST_SECONDARY | INSTANCE_MASK_ALPHA_BLEND_SECONDARY | INSTANCE_MASK_WATER;
    q.TraceRayInline(SceneBVH, RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH, INSTANCE_MASK_SHADOW, ray);

    while(q.Proceed())
    {
        HitInfo hitInfo = GetCandidateHitInfo(q);

        if(hitInfo.materialType == MATERIAL_TYPE_ALPHA_TEST)
        {
            if(AlphaTestHitLogic(hitInfo))
            {
                q.CommitNonOpaqueTriangleHit();
            }
        }
        else
        {
            q.CommitNonOpaqueTriangleHit();
        }
    }

    if(q.CommittedStatus() != COMMITTED_NOTHING)
    {
        HitInfo hitInfo = GetCommittedHitInfo(q);

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
        payload.position = hitSurface.position;
        payload.normal = hitSurface.normal;
        payload.albedo = hitSurface.color;
    }
}



void sunLightGi(SurfaceInfo surfaceInfo, float3 direction, float2 noise, inout float3 radiance)
{
    
    const uint giSamples = 2;
    GiHitPayload payload;
  float3 giRadiance = 0;

for(uint i = 0; i < giSamples; i++)
{
    float2 Xi = frac(
        noise +
        float2(
            i * 0.61803398875,
            i * 0.38196601125));

    float3 sampleDir =
        CosineHemisphereSampling(
            Xi,
            surfaceInfo.normal);

    RayDesc bounceRay;

    bounceRay.Origin =
        surfaceInfo.position +
        surfaceInfo.normal * 1e-4;

    bounceRay.Direction = sampleDir;
    bounceRay.TMin = 0.0;
    bounceRay.TMax = 10000.0;

    GiHitPayload payload;

    TraceGiBounce(
        bounceRay,
        payload);

    if(payload.hit)
    {
        SurfaceInfo bounceSurface;

        bounceSurface.position = payload.position;
        bounceSurface.normal = payload.normal;

        float3 shadowTransmission;

        getShadow(
            bounceSurface,
            direction,
            noise,
            shadowTransmission);

        float ndotl =
            saturate(
                dot(payload.normal,
                    direction));

        giRadiance +=
            payload.albedo *
            shadowTransmission *
            ndotl;
    }
}
radiance +=
    (giRadiance / giSamples);
}
    
    


#endif