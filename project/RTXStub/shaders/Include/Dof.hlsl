#ifndef DOF_HLSL
#define DOF_HLSL
#include "Generated/Signature.hlsl"
#include "Constants.hlsl"
#include "Util.hlsl"
#include "settings.hlsl"
	
	
#define ANAMORPHIC_STRETCH 8.0;
// From Coding Adventures: Ray Tracing https://youtu.be/Qz0KTGYJtUk?si=w0Hq8sTNKwmuw0zv 
float2 randomPointInCircle(inout PathRNG rngState)
{
	float angle = NextFloat(rngState) * 2 * PI; // 2 * PI
	float2 pointOnCircle = float2(cos(angle), sin(angle));
	return pointOnCircle * sqrt(NextFloat(rngState));
}

//from https://pbr-book.org/3ed-2018/Camera_Models/Projective_Camera_Models
float2 randomPointInRegularPolygon(inout PathRNG rng,uint bladeCount,float rotation)
{
    uint sector = min(uint(NextFloat(rng) * bladeCount), bladeCount - 1);

    float a0 = rotation + (2.0 * PI * sector) / bladeCount;
    float a1 = rotation + (2.0 * PI * (sector + 1)) / bladeCount;

    float2 v0 = float2(cos(a0), sin(a0));
    float2 v1 = float2(cos(a1), sin(a1));

    // Uniform point in triangle: center, v0, v1.
    float r = sqrt(NextFloat(rng));
    float t = NextFloat(rng);
    return r * lerp(v0, v1, t);
}

float2 rotateVector(float2 v, float angle)
{
    float c = cos(angle);
    float s = sin(angle);
    return float2(v.x * c - v.y * s, v.x * s + v.y * c);
}

void computeDOFRay(uint2 pixelCoord, float3 rayOrigin, float3 rayDir, in PathRNG rngState, out float3 outOrigin, out float3 outDirection)
{
    #if ENABLE_DOF
    uint baseSeed = uint(pixelCoord.x) + uint(pixelCoord.y) * g_view.renderResolution.x;
    baseSeed ^= g_view.frameCount * 0x9E3779B9u;
    baseSeed ^= uint(1) * 0x85EBCA6Bu;
    rngState.state = PCG_Hash(uint3(baseSeed, g_view.frameCount, uint(1)));

    float3 focalPoint = rayOrigin + rayDir * DOF_FOCAL_DISTANCE;

    float3 rightVector = normalize(cross(rayDir, float3(0.0, 1.0, 0.0)));
    if (length(rightVector) < 0.001) rightVector = normalize(cross(rayDir, float3(0.0, 0.0, 1.0)));
    float3 upVector = cross(rightVector, rayDir);

    // 1. Sample standard uniform disk bokeh
    float2 apertureSample;
	#if DOF_APERTURE_SHAPE == 0
	apertureSample = randomPointInCircle(rngState);
	#else
	apertureSample = apertureSample = randomPointInRegularPolygon(rngState,DOF_BLADES, DOF_APERTURE_ROTATION);
	#endif

    apertureSample *= DOF_BLUR_STRENGTH / g_view.renderResolution.x;
    
    outOrigin = rayOrigin + rightVector * apertureSample.x + upVector * apertureSample.y;
    outDirection = normalize(focalPoint - outOrigin);
    #else
    outDirection = rayDir;
    outOrigin = rayOrigin;
    #endif
}
	
	


#endif