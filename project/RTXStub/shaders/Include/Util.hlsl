/* MIT License
 * 
 * Copyright (c) 2025 veka0
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#ifndef __UTIL_HLSL__
#define __UTIL_HLSL__

#include "Generated/Signature.hlsl"
#include "Constants.hlsl"
#include "settings.hlsl"


// blueNoiseTexture is available as a Texture2DArray<float4> bound at t58.
// The engine exposes it as a 256x256 array with 128 layers.
static const uint kBlueNoiseTextureSize = 256;
static const uint kBlueNoiseLayerCount = 128;

// 32-bit PCG Hash function to completely decorrelate neighbor pixel random sequences
uint PCG_Hash(uint3 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
    v ^= v >> 16u;
    v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
    return v.x;
}

// Convert an unsigned integer hash smoothly into a pseudo-random float [0, 1)
float HashToFloat(uint hash) {
    return float(hash & 0x00ffffffu) / float(0x01000000u);
}

struct PathRNG
{
    uint state;
};

uint Hash(uint x)
{
    x ^= x >> 16;
    x *= 0x7feb352d;
    x ^= x >> 15;
    x *= 0x846ca68b;
    x ^= x >> 16;
    return x;
}


float RandomFloat(uint seed)
{
    return (Hash(seed) & 0x00FFFFFF) / 16777216.0;
}

float NextFloat(inout PathRNG rng)
{
    rng.state = Hash(rng.state);
    return (rng.state & 0x00FFFFFF) / 16777216.0;
}

float2 NextFloat2(inout PathRNG rng)
{
    return float2(
        NextFloat(rng),
        NextFloat(rng));
}

float4 SampleBlueNoise(uint2 pixelCoord, uint layerIndex) {
    layerIndex %= kBlueNoiseLayerCount;
    float2 uv = (pixelCoord + 0.5) / float2(kBlueNoiseTextureSize, kBlueNoiseTextureSize);
    return blueNoiseTexture.Sample(defaultSampler, float3(uv, layerIndex));
}

float4 LoadBlueNoise(uint2 texelCoord, uint layerIndex) {
    uint2 wrappedCoord = texelCoord % uint2(kBlueNoiseTextureSize, kBlueNoiseTextureSize);
    uint temporalLayer = (g_view.frameCount + layerIndex) % kBlueNoiseLayerCount;
    uint3 noiseCoord = uint3(wrappedCoord, temporalLayer);
    return blueNoiseTexture.Load(uint4(noiseCoord, 0));
}

float2 SampleSTBN2(uint2 pixelCoord, uint bounceIndex, uint sampleIndex) {
    float4 noise = LoadBlueNoise(pixelCoord, bounceIndex + sampleIndex);
    float2 value = float2(noise.x, noise.y);
    float2 offset = float2(
        0.61803398875f * float(sampleIndex + 1u),
        0.38196601125f * float(sampleIndex + 1u));
    return frac(value + offset);
}

float SampleSTBN1(uint2 pixelCoord, uint bounceIndex, uint sampleIndex) {
    float4 noise = LoadBlueNoise(pixelCoord, bounceIndex + sampleIndex);
    return frac(noise.w + 0.61803398875f * float(sampleIndex + 1u));
}

uint3 getDispatchDimensions() {
    return uint3(
        (g_dispatchDimensions >> 0*10) & 1023, 
        (g_dispatchDimensions >> 1*10) & 1023,
        g_dispatchDimensions >> 2*10
    );
}

float2 computeMotionVector(float3 steveSpacePositon, float3 steveSpaceMotion) {
    float4 clipPos = mul(float4(steveSpacePositon, 1), g_view.viewProj);
    float2 ndcPos = clipPos.xy / clipPos.w;

    float3 prevHitPos = steveSpacePositon - steveSpaceMotion;
    float4 prevClipPos = mul(float4(prevHitPos, 1), g_view.prevViewProj);
    float2 prevNdcPos = prevClipPos.xy / prevClipPos.w;

    return (prevNdcPos - ndcPos) * float2(0.5, -0.5); // Offset in UV space.
}

float3 rayDirFromNDC(float2 ndc) {
    // Note: as far as I can tell, view origin is always 0, hence it's not necessary to subtract it or even 
    // divide resulting vector by W. But I'm keeping the code here in case view origin becomes something else in the future.
    const float NDC_Z_Offset = 0.5;
    #if 0
    // Slightly faster but less precise.
    float3 rayDir = mad(ndc.x, g_view.posNdcToDirection[0].xyz, g_view.posNdcToDirection[2].xyz);
    rayDir = mad(ndc.y, g_view.posNdcToDirection[1].xyz, rayDir);
    return normalize(rayDir/mad(g_view.invViewProj._m23, NDC_Z_Offset, g_view.invViewProj._m33) - g_view.viewOriginSteveSpace);
    #else
    float4 steveSpacePos = mul(float4(ndc, NDC_Z_Offset, 1), g_view.invViewProj);
    steveSpacePos.xyz /= steveSpacePos.w;
    return normalize(steveSpacePos.xyz - g_view.viewOriginSteveSpace);
    #endif
}

// Returns true both for upscaling (e.g. DLSS) and anti-aliasing (e.g. DLAA)
bool isUpscalingEnabled() {
    return !g_view.enableTAA;
}

float2 getCameraJitter(uint2 pixelCoord) {
    float2 sample = SampleSTBN2(pixelCoord, g_view.frameCount, 8u);
    return sample - 0.5f;
}

float2 getNDCjittered(uint2 pixelCoord) {
    float2 subpixelOffset = isUpscalingEnabled() ? g_view.subPixelJitter : getCameraJitter(pixelCoord);
    float2 ndc = g_view.recipRenderResolution * (pixelCoord + 0.5 + subpixelOffset);
    return mad(ndc, float2(2, -2), float2(-1, 1));
}

float3 safeNormalize(float3 v, float3 fallback) {
    float lenSq = dot(v, v);
    return lenSq > 1.0e-12 ? v * rsqrt(lenSq) : fallback;
}

float4 unpackNormal(uint packedNormal) {
    return float4(
        (int)((packedNormal << 8*3) & 0xff000000) >> 24, 
        (int)((packedNormal << 8*2) & 0xff000000) >> 24, 
        (int)((packedNormal << 8*1) & 0xff000000) >> 24, 
        (int)((packedNormal << 8*0) & 0xff000000) >> 24
    ) / 127.0;
}

uint packNormal(float4 normal) {
    int4 normalInt = int4(round(normal*127));
    return (
        ((uint)(normalInt.x << 24) >> 8*3) | 
        ((uint)(normalInt.y << 24) >> 8*2) | 
        ((uint)(normalInt.z << 24) >> 8*1) | 
        ((uint)(normalInt.w << 24) >> 8*0)
    );
}

float4 unpackVertexColor(uint packedColor) {
    return float4(
        (packedColor >> 8 * 0) & 0xff, 
        (packedColor >> 8 * 1) & 0xff, 
        (packedColor >> 8 * 2) & 0xff, 
        (packedColor >> 8 * 3) & 0xff
    ) / 255.0;
}

float4 unpackObjectInstanceTintColor(uint packedColor) {
    return float4(
        (packedColor >> 8 * 3) & 0xff, 
        (packedColor >> 8 * 2) & 0xff, 
        (packedColor >> 8 * 1) & 0xff, 
        (packedColor >> 8 * 0) & 0xff
    ) / 255.0;
}

float2 unpackVertexUV(uint packedUV, bool packedUvIncludesBias = false) {
    const float uvScale = 1.0 / 65535.0; // 1.0/0xffff
    const float biasScale = 1.0 / 32768.0;

    if (packedUvIncludesBias) {
        float2 uv = float2(packedUV << 1u & 0xfffeu, packedUV >> 15u & 0xfffeu) * uvScale;
        float2 bias = (float2(packedUV >> 15u & 1u, packedUV >> 31u) * 2.0 - 1.0) * biasScale;

        return uv + bias;
    } else {
        float2 uv = float2(packedUV & 0xffff, packedUV >> 16) * uvScale;

        // Quantize UVs according to largest possible texture size (32k on NVidia), fixes visible texture seams on certain objects.
        uv = round(uv * 32768) * (1.0 / 32768.0);

        return uv;
    }
}

// Determine whether g_view.directionToSun is actually direction to moon.
bool isMoonPrimaryLight() {
    float angle1 = g_view.sunAzimuth - PI;
    float angle2 = atan2(g_view.directionToSun.z, g_view.directionToSun.x);
    float angleDiff = abs(angle1-angle2);
    return min(angleDiff, (2*PI)-angleDiff) > 0.001;
}

float3 rotateBySunAngle(float3 dir, bool inverse = false)
{
	float a = inverse ? -SUN_ZENITH : SUN_ZENITH;
	float b = inverse ? -SUN_AZIMUTH : SUN_AZIMUTH;
	float3x3 zenith = {
		1.0, 0.0,     0.0,
		0.0, cos(a), -sin(a),
		0.0, sin(a),  cos(a),
	};
	float3x3 azimuth = {
		 cos(b), 0.0,  sin(b),
		 0.0,    1.0,  0.0,
		-sin(b), 0.0,  cos(b),
	};
	return inverse ? mul(zenith, mul(azimuth, dir)) : mul(azimuth, mul(zenith, dir));
}

float3 getTrueDirectionToSun() {
    return isMoonPrimaryLight() ?  rotateBySunAngle(-g_view.directionToSun) : rotateBySunAngle(g_view.directionToSun);
}

float3 getTrueDirectionToMoon() {
    return isMoonPrimaryLight() ?  rotateBySunAngle(g_view.directionToSun):  rotateBySunAngle(-g_view.directionToSun);
}

float getTime() {
    float3 directionToSun = getTrueDirectionToSun();
    float time = 0.5 * atan2(directionToSun.x, directionToSun.y) / PI;
    return time < 0 ? time + 1 : time;
}

float3 CosineHemisphereSampling(float2 u, float3 n) {
    float r = sqrt(u.x);
    float theta = 2.0 * PI * u.y;

    float3 p = float3(r * cos(theta), r * sin(theta), sqrt(max(0.0, 1.0 - u.x)));
    n = safeNormalize(n, float3(0, 1, 0));

    float3 up = abs(n.z) < 0.999 ? float3(0,0,1) : float3(1,0,0);
    float3 t = safeNormalize(cross(up, n), float3(1, 0, 0));
    float3 b = cross(n, t);

    return safeNormalize(p.x * t + p.y * b + p.z * n, n);
}

void buildOrthonormalBasis(float3 v, out float3 b1, out float3 b2) {
    float sign = v.z >= 0.0 ? 1.0 : -1.0;
    float a = -1.0 / (sign + v.z);
    float b = v.x * v.y * a;
    b1 = float3(1.0 + sign * v.x * v.x * a, sign * b, -sign * v.x);
    b2 = float3(b, sign + v.y * v.y * a, -v.y);
}

float3 randConeJitter(float3 dir, float radius, float2 jitter) {
    float z = 1.0 - jitter.y * (1.0 - cos(radius));

    float sinTheta = sqrt(1.0 - z * z);
    float phi = 2.0 * PI * jitter.x;

    float3 localDir = float3(cos(phi) * sinTheta, sin(phi) * sinTheta, z);

    float3 tan, biTan;
    buildOrthonormalBasis(dir, tan, biTan);

    return normalize(
    tan * localDir.x +
    biTan * localDir.y +
    dir * localDir.z);
}


float3 FixShadingNormal(float3 Ng, float3 Ns)
{
    if (dot(Ng, Ns) < 0)
    {
        Ns = normalize(Ns - 2.0 * dot(Ns, Ng) * Ng);
    }

    return Ns;
}
float PDF_SunCone()
{
    float cosThetaMax = cos(SUN_RADIUS);

    return 1.0 /
        (2.0 * PI * (1.0 - cosThetaMax));
}

float3 getDirectionToSun()
{
   

    if (SUN_AZIMUTH == 0.0 && SUN_ZENITH == 0.0)
    {
        return g_view.directionToSun;
    }
    return rotateBySunAngle(g_view.directionToSun);

}
float3 getUnderwaterDirectionToSun()
{
   

    if (SUN_AZIMUTH == 0.0 && SUN_ZENITH == 0.0)
    {
        return g_view.underwaterDirectionToSun;
    }
    return rotateBySunAngle(g_view.underwaterDirectionToSun);

}

float4 getMediaExtinction(int medium) {

    return g_view.mediaExtinction[medium];
}

float3 getScattering()
{
    return g_view.primaryMediaScattering;
}

float3 getMediaAbsorption()
{
    return g_view.primaryMediaAbsorption;
}

float3 getMediaPrimaryExtinction()
{
    return g_view.primaryMediaExtinction;
}
float3 calcTransmittance(float distance, float3 extinction)
{
	return exp(-extinction * distance);
}
float calcDensityModifier(in float3 position)
{
	float densityModifier = 1;
	if (!g_view.cameraIsUnderWater)
	{
        // We only use height fog when the camera is in the air
        densityModifier = saturate(mad(position.y, g_view.heightToFogScale, g_view.heightToFogBias));
		
	}
	return densityModifier;
}

float3 offset_ray(const float3 p, const float3 n)
{
    static const float origin = 1.0f / 32.0f;
    static const float float_scale = 1.0f / 65536.0f;
    static const float int_scale = 256.0f;

    int3 of_i = int3(int_scale * n.x, int_scale * n.y, int_scale * n.z);

    float3 p_i = float3(
        asfloat(asint(p.x) + ((p.x < 0) ? -of_i.x : of_i.x)),
        asfloat(asint(p.y) + ((p.y < 0) ? -of_i.y : of_i.y)),
        asfloat(asint(p.z) + ((p.z < 0) ? -of_i.z : of_i.z)));

    return float3(abs(p.x) < origin ? p.x + float_scale * n.x : p_i.x,
        abs(p.y) < origin ? p.y + float_scale * n.y : p_i.y,
        abs(p.z) < origin ? p.z + float_scale * n.z : p_i.z);

}

uint readAccumulationFrameIdx() { return outputBufferToneMappingHistogram[uint2(0,0)]; }
void storeAccumulationFrameIdx(uint frameIdx) { outputBufferToneMappingHistogram[uint2(0,0)] = frameIdx; }

// FPS
float readAverageFps() { return outputBufferToneCurve[uint2(1,0)]; }
void storeAverageFps(float fps) { outputBufferToneCurve[uint2(1,0)] = fps; }

// Last Frame Timestamp
float readLastFrameTimestamp() { return outputBufferToneCurve[0..xx]; }
void storeLastFrameTimestamp(float timestamp) { outputBufferToneCurve[0..xx] = timestamp; }

// Accumulation Start Timestamp
float readAccumulationStartTimestamp() { return outputBufferToneCurve[uint2(2,0)]; }
void storeAccumulationStartTimestamp(float timestamp) { outputBufferToneCurve[uint2(2,0)] = timestamp; }

#endif