#ifndef DOF_HLSL
#define DOF_HLSL
#include "Generated/Signature.hlsl"
#include "Constants.hlsl"
#include "Util.hlsl"
#include "settings.hlsl"
	
	
	
float2 randomPointInCircle(inout PathRNG rngState)
{
	float angle = NextFloat(rngState) * 2 * PI; // 2 * PI
	float2 pointOnCircle = float2(cos(angle), sin(angle));
	return pointOnCircle * sqrt(NextFloat(rngState));
}

void computeDOFRay(uint2 pixelCoord, float3 rayOrigin, float3 rayDir, in PathRNG rngState, out float3 outOrigin, out float3 outDirection)
{
	
		uint baseSeed = uint(pixelCoord.x) + uint(pixelCoord.y) * g_view.renderResolution.x;
		baseSeed ^= g_view.frameCount * 0x9E3779B9u;
		baseSeed ^= uint(1) * 0x85EBCA6Bu;
		rngState.state = PCG_Hash(uint3(baseSeed, g_view.frameCount, uint(1)));

		float3 focalPoint = rayOrigin + rayDir * DOF_FOCAL_DISTANCE;

		float3 forwardVector =  rayDirFromNDC(getNDCjittered(pixelCoord.xy));
		float3 rightVector = float3(0, 1, 0);
		float3 upVector = cross(forwardVector, rightVector);
		rightVector = cross(upVector, forwardVector);

		float2 apertureSample = randomPointInCircle(rngState) * DOF_BLUR_STRENGTH / g_view.renderResolution.x; 
		outOrigin = rayOrigin + rightVector * apertureSample.x + upVector * apertureSample.y;
		outDirection = normalize(focalPoint - outOrigin);
	
}
	
	


#endif