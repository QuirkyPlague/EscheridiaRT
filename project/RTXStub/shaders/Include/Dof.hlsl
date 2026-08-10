#ifndef DOF_HLSL
#define DOF_HLSL
#include "Generated/Signature.hlsl"
#include "Constants.hlsl"
#include "Util.hlsl"
#include "settings.hlsl"
	
	
#define ANAMORPHIC_STRETCH 8.0;
float2 randomPointInCircle(inout PathRNG rngState)
{
	float angle = NextFloat(rngState) * 2 * PI; // 2 * PI
	float2 pointOnCircle = float2(cos(angle), sin(angle));
	return pointOnCircle * sqrt(NextFloat(rngState));
}

// Concentric Mapping (http://psgraphics.blogspot.com/2011/01/improved-code-for-concentric-map.html)
float2 mapSquareToDisk(float2 u) {
	float phi, r;
	float a = 2 * u.x - 1;
	float b = 2 * u.y - 1;
	if (a*a > b*b) { // use squares instead of absolute values
		r = a;
		phi = (PI / 4)*(b / a);
	}
	else {
		r = b;
		phi = (PI / 2) - (PI / 4)*(a / b);
	}
	return float2(r*cos(phi), r*sin(phi));
}


float2 lineIntersection(float2 a1, float2 a2, float2 b1, float2 b2) {
	
	float r = ((a1.y - b1.y) * (b2.x - b1.x) - (a1.x - b1.x) * (b2.y - b1.y))
	       	/ ((a2.x - a1.x) * (b2.y - b1.y) - (a2.y - a1.y) * (b2.x - b1.x));

	return a1 + r * (a2 - a1);
}
float2 samplePolygon(int polygonSides, inout PathRNG randSeed) {

	// Sample circle first
	float2 u = float2(NextFloat(randSeed), NextFloat(randSeed));
	float2 result = mapSquareToDisk(u);

	// Check if point is in the polygon
	float polygonInternalAngle = (PI * 2) / polygonSides;

	float testedPointDistance = length(result);
	float testedPointAngle = acos(dot(float2(0, 1), normalize(result)));
	testedPointAngle = fmod(testedPointAngle, polygonInternalAngle);

	float2 polygonPoint = float2(-sin(polygonInternalAngle), cos(polygonInternalAngle));
	float2 testedPoint = float2(-sin(testedPointAngle), cos(testedPointAngle)) * testedPointDistance;

	float2 projectedTestedPoint = lineIntersection(testedPoint, float2(0, 0), polygonPoint, float2(0, 1));
	float projectedTestedPointDistance = length(projectedTestedPoint);


	if (projectedTestedPointDistance < testedPointDistance) {
		// Remap point back into the polygon if it's outside
		float m = 1 - projectedTestedPointDistance;
		float t = testedPointDistance - projectedTestedPointDistance;
		float rescaledDistance = (t / m) * projectedTestedPointDistance;
		return normalize(result) * rescaledDistance;
	} 


	return result;
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
	apertureSample = samplePolygon(DOF_BLADES,rngState);
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