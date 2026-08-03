#ifndef DOF_HLSL
#define DOF_HLSL
#include "Generated/Signature.hlsl"
#include "Constants.hlsl"
#include "Util.hlsl"

#ifndef DOF_FOCAL_DISTANCE
#define DOF_FOCAL_DISTANCE 21.0f
#endif

#ifndef DOF_APERTURE_SIZE
#define DOF_APERTURE_SIZE 0.2f // set > 0.0f to enable DOF
#endif

#ifndef DOF_APERTURE_TYPE
#define DOF_APERTURE_TYPE 0
#endif

float2 randomPointInCircle(inout PathRNG rngState)
{
    float angle = NextFloat(rngState) * 2 * PI; // 2 * PI
    float2 pointOnCircle = float2(cos(angle), sin(angle));
    return pointOnCircle * sqrt(NextFloat(rngState));
}

void computeDOFRay(uint2 pixelCoord, float3 rayOrigin, float3 rayDir, in PathRNG rngState, out float3 outOrigin, out float3 outDirection)
{
	
	rayOrigin = rayDirFromNDC(getNDCjittered(pixelCoord.xy));
    rayOrigin = g_view.viewOriginSteveSpace;
	float3 focalPoint = rayOrigin + rayDir * DOF_FOCAL_DISTANCE;

	float3 forwardVector =  rayDirFromNDC((pixelCoord.xy));
	float3 rightVector = float3(0, 1, 0);
	float3 upVector = cross(forwardVector, rightVector);
	rightVector = cross(upVector, forwardVector);

	float2 apertureSample = randomPointInCircle(rngState) * DOF_APERTURE_SIZE / pixelCoord.x;

	float2 jitter =  randomPointInCircle(rngState) * DOF_FOCAL_DISTANCE / pixelCoord.x;
	float3 jitteredDir = rayDirFromNDC(pixelCoord) + rightVector * jitter.x + upVector * jitter.y;
	outOrigin = rayOrigin + rightVector * apertureSample.x + upVector * apertureSample.y;
	outDirection = normalize(jitteredDir - outOrigin);
	}
  	
	


#endif