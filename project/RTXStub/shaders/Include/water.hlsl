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
    float2 res = wavedx(position, p, frequency,  wavePhaseShift);

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




// Simple, deterministic hash function to generate wave attributes procedurally
float WaveHash(float seed)
{
    return frac(sin(seed) * 43758.5453123f);
}

// Analytically calculates the exact ocean surface normal for any given position and time
float3 GetAnharmonicWaveNormal(float3 worldPos, float time, uint waveCount)
{
    // Initialize the identity matrix derivatives (Tangent and Bitangent)
    float3 tangent = float3(1.0f, 0.0f, 0.0f);
    float3 bitangent = float3(0.0f, 0.0f, 1.0f);

    // Accumulate waves using the exact same seed generation across threads
    for (uint i = 0; i < waveCount; ++i)
    {
        // Derive unique wave parameters purely from the loop index 'i'
        float seed = float(i) * 12.9898f;

        // Pseudo-random angle for wave direction
        float angle = WaveHash(seed) * 6.2831853f;
        float2 direction = float2(cos(angle), sin(angle));

        // Procedural distribution of amplitudes, wavelengths, and steepness
        float amplitude = 0.05f + (WaveHash(seed + 1.0f) * 0.45f) / float(i + 1);
        float wavelength = 2.0f + WaveHash(seed + 2.0f) * 35.0f * (float(i + 1) / float(waveCount));
        float speed = 0.5f + WaveHash(seed + 3.0f) * 2.5f;
        float steepness = 0.1f + WaveHash(seed + 4.0f) * 0.4f;

        // Core Gerstner Wave Constants
        float k = (2.0f * 3.14159265f) / wavelength;
        float c = speed * sqrt(9.81f / k); // Deep water dispersion relation

        // Phase calculation based on input position and time
        float phase = k * dot(direction, worldPos.xz) - c * time;

        float cosPhase = cos(phase);
        float sinPhase = sin(phase);

        // Sharpness constraint factor to prevent wave self-intersection loops
        float q = steepness / (amplitude * k * (float)waveCount);
        float wa = k * amplitude;

        // Analytical Partial Derivatives (Jacobians)
        tangent.x   -= q * wa * direction.x * direction.x * sinPhase;
        tangent.y   += wa * direction.x * cosPhase;
        tangent.z   -= q * wa * direction.x * direction.y * sinPhase;

        bitangent.x -= q * wa * direction.x * direction.y * sinPhase;
        bitangent.y += wa * direction.y * cosPhase;
        bitangent.z -= q * wa * direction.y * direction.y * sinPhase;
    }

    // The mathematical cross product of the altered surface vectors yields the exact normal
    return normalize(cross(bitangent, tangent));
}


#endif //WATER_HLSL