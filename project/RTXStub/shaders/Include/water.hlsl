#ifndef WATER_HLSL
#define WATER_HLSL

#include "settings.hlsl"
#include "Util.hlsl"

float intersectPlane(float3 origin, float3 direction, float3 pos, float3 normal) { 
  return clamp(dot(pos - origin, normal) / dot(direction, normal), -1.0, 9991999.0); 
}

// Calculates wave value and its derivative,
// for the wave direction, position in space, wave frequency and time
float2 wavedx(float2 position, float2 direction, float frequency, float timeshift) {
  float x = dot(direction, position) * frequency + timeshift;
  x = fmod(x, 2.0*PI);
  float wave = exp(sin(x) - 1.0);
  float dx = wave * cos(x);
  return float2(wave, -dx);
}

// Calculates waves by summing octaves of various waves with various parameters
float getwaves(float2 position, int iterations) {
  float wavePhaseShift = length(position) * WAVE_RANDOMNESS; // this is to avoid every octave having exactly the same phase everywhere
  float iter = 0.0; // this will help generating well distributed wave directions
  float frequency = WAVE_FREQUENCY; // frequency of the wave, this will change every iteration
  float timeMultiplier = WAVE_SPEED; // time multiplier for the wave, this will change every iteration
  float weight = 1.0;// weight in final sum for the wave, this will change every iteration
  float sumOfValues = 0.0; // will store final sum of values
  float sumOfWeights = 0.0; // will store final sum of weights
  for(int i=0; i < iterations; i++) {
    // generate some wave direction that looks kind of random
    float2 p = float2(sin(iter), cos(iter));
    
    // calculate wave data
    float2 res = wavedx(position, p, frequency, wavePhaseShift);

    // shift position around according to wave drag and derivative of the wave
    position += p * res.y * weight * WAVE_PULL;

    // add the results to sums
    sumOfValues += res.x * weight;
    sumOfWeights += weight;

    // modify next octave ;
    weight = lerp(weight, 0.0, WAVE_OCTAVE_MIX_WEIGHT);
    frequency *= WAVE_OCTAVE_FREQUENCY;
    timeMultiplier *= WAVE_OCTAVE_SPEED;

    // add some kind of random value to make next wave look random too
    //iter += 1232.399963;
    iter = fmod(iter + 1232.399963, 2.0*PI);
  }
  // calculate and return
  return sumOfValues / sumOfWeights;
}

float raymarchwater(float3 camera, float3 start, float3 end, float depth) {
  float3 pos = start;
  float3 dir = normalize(end - start);
  for(int i=0; i < 12; i++) {
    // the height is from 0 to -depth
    float height = getwaves(pos.xz, WAVE_OCTAVES) * depth - depth;
    // if the waves height almost nearly matches the ray height, assume its a hit and return the hit distance
    if(height + 0.01 > pos.y) {
      return distance(pos, camera);
    }
    // iterate forwards according to the height mismatch
    pos += dir * (pos.y - height);
  }
  // if hit was not registered, just assume hit the top layer, 
  // this makes the raymarching faster and looks better at higher distances
  return distance(start, camera);
}

// Calculate normal at point by calculating the height at pos and 2 additional nearby points
float3 waveNormal(float2 pos, float e, float depth)
{   
    
    float2 ex = float2(e, 0.0f);

    float H = getwaves(pos, WAVE_OCTAVES) * depth;
    float3 a = float3(pos.x, H, pos.y);

    float hL = getwaves(pos - ex, WAVE_OCTAVES) * depth;         
    float hR = getwaves(pos + ex.xy, WAVE_OCTAVES) * depth;     

    float3 v1 = a - float3(pos.x - e, hL, pos.y);
    float3 v2 = a - float3(pos.x, hR, pos.y + e);

    return normalize(cross(v1, v2));
}




void EvaluateWaveLayer(
    float2 origin, float2 dir, float amplitude, float steepness, float wavelength, float speed, float time, 
    inout float2 guessXZ, inout float3 tangent, inout float3 binormal, inout float totalHeight
) {
    float k = (2.0f * 3.14159265f) / wavelength;
    
    // Safety check: Scale steepness dynamically to prevent self-intersection loops
    // Q_max = 1.0 / (amplitude * k)
    float qMax = 1.0f / max(amplitude * k, 0.0001f);
    float safeQ = min(steepness, qMax * 0.9f); // Keep it strictly below the loop threshold
    
    float c = sqrt(9.81f / k) * speed;
    
    // Smooth, calibrated fixed-point inversion loop
    [unroll]
    for (int i = 0; i < 3; i++) {
        float phase = k * (dot(dir, guessXZ) - c * time);
        guessXZ = origin - (safeQ * amplitude * dir * cos(phase));
    }
    
    float finalPhase = k * (dot(dir, guessXZ) - c * time);
    float sinP = sin(finalPhase);
    float cosP = cos(finalPhase);
    
    // Accumulate actual height
    totalHeight += amplitude * sinP;
    
    // Correct analytical accumulation of partial derivatives
    tangent.x -= safeQ * amplitude * k * dir.x * dir.x * sinP;
    tangent.y += amplitude * k * dir.x * cosP;
    tangent.z -= safeQ * amplitude * k * dir.x * dir.y * sinP;

    binormal.x -= safeQ * amplitude * k * dir.x * dir.y * sinP;
    binormal.y += amplitude * k * dir.y * cosP;
    binormal.z -= safeQ * amplitude * k * dir.y * dir.y * sinP;
}

// 1. THE HEIGHT FUNCTION
float calculateGerstnerHeight(float2 worldXZ, float time, float waveStrength) {
    float2 guessXZ = worldXZ;
    float totalHeight = 0.0f;
    float3 dummyTangent = float3(0,0,0);
    float3 dummyBinormal = float3(0,0,0);
    
    // Wave 1: Primary Swell
    EvaluateWaveLayer(worldXZ, float2(0.8f, 0.6f), 0.5f * waveStrength, 0.4f, 12.0f, 1.5f, time, guessXZ, dummyTangent, dummyBinormal, totalHeight);
    // Wave 2: Secondary Choppy Cross-Swell
    EvaluateWaveLayer(worldXZ, float2(-0.5f, 0.8f), 0.2f * waveStrength, 0.3f, 5.0f, 2.2f, time, guessXZ, dummyTangent, dummyBinormal, totalHeight);
    
    return totalHeight;
}



float3 calculateGerstnerNormal(float2 worldXZ, float time, float waveSmoothness, float waveStrength) {
    float2 guessXZ = worldXZ;
    float dummyHeight = 0.0f;
    
    // MUST initialize as clean base basis vectors before accumulating layer offsets
    float3 tangent  = float3(1.0f, 0.0f, 0.0f);
    float3 binormal = float3(0.0f, 0.0f, 1.0f);
    
    // Scale your wavelengths MUCH larger. 
    // Small values like 5.0 and 12.0 create tiny 5-meter ripples that look like static noise in a block world.
    // Let's use clean scales that merge perfectly with a 1024 grid factor.
    
    // Wave 1: Massive rolling ocean swell (Wavelength 64 blocks)
    EvaluateWaveLayer(worldXZ, float2(0.8f, 0.6f), WAVE_HEIGHT, WAVE_STEEPNESS, 64.0f, 1.2f, time, guessXZ, tangent, binormal, dummyHeight);
    
    // Wave 2: Chop wave traveling cross-direction (Wavelength 32 blocks)
    EvaluateWaveLayer(worldXZ, float2(-0.6f, 0.8f),WAVE_HEIGHT, WAVE_STEEPNESS * 0., 32.0f, 1.8f, time, guessXZ, tangent, binormal, dummyHeight);
    
    // Generate clean geometric normal
    float3 rawNormal = normalize(cross(binormal, tangent));
    
    // Blend with absolute world up vector via smooth mix
    return normalize(lerp(rawNormal, float3(0.0f, 1.0f, 0.0f), waveSmoothness));
}

#endif //WATER_HLSL