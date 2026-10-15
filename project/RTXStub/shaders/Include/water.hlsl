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




#ifndef TWO_PI
#define TWO_PI 6.28318530718f
#endif

#ifndef WAVE_BASE_WAVELENGTH
#define WAVE_BASE_WAVELENGTH 3.8f
#endif

struct GerstnerSample {
    float height;
    float2 horizontalOffset;
    float3 dPdx;
    float3 dPdz;
};

GerstnerSample SampleGerstner(float2 xz, float time)
{
    GerstnerSample wave;
    wave.height = 0.0f;
    wave.horizontalOffset = float2(0.0f, 0.0f);
    wave.dPdx = float3(1.0f, 0.0f, 0.0f);
    wave.dPdz = float3(0.0f, 0.0f, 1.0f);

    const uint numWaves = WAVE_COUNT;
    float baseWavelength = WAVE_BASE_WAVELENGTH;
    float baseAmplitude = WAVE_HEIGHT;
    float totalSteepness = clamp(WAVE_STEEPNESS, 0.0f, 3.95f);

    #if (ENABLE_MICRO_WAVES == 1)
    const float microWavesPerOctave = (float)WAVE_MICRO_WAVES_PER_OCTAVE;
    const float totalWeight = (float)numWaves * (1.0f + microWavesPerOctave * (WAVE_MICRO_STEEPNESS * WAVE_MICRO_AMPLITUDE_MULT));
    float waveWeight = totalSteepness / totalWeight;
    float microWeight = waveWeight * WAVE_MICRO_STEEPNESS;
    #else
    float waveWeight = totalSteepness / (float)numWaves;
    #endif

    for (uint i = 0; i < numWaves; ++i) {
        float angle = (float)i * 2.399963f;
        float2 direction = normalize(float2(cos(angle), sin(angle)));

        float wavelength = baseWavelength * pow(0.78f, (float)i);
        float waveVec = TWO_PI / wavelength;

        float amplitude = baseAmplitude * pow(0.80f, (float)i);

        float choppiness = waveWeight / (amplitude * waveVec);

        float phase = waveVec * dot(direction, xz) - sqrt(9.81f * waveVec) * (time * WAVE_SPEED * 0.25f);

        float sinPhase = sin(phase);
        float cosPhase = cos(phase);

        wave.height += amplitude * sinPhase;
        wave.horizontalOffset += choppiness * amplitude * direction * cosPhase;

        wave.dPdx += float3(-choppiness * direction.x * direction.x * sinPhase, amplitude * waveVec * direction.x * cosPhase,-choppiness * direction.x * direction.y * sinPhase);
        wave.dPdz += float3(-choppiness * direction.x * direction.y * sinPhase,amplitude * waveVec * direction.y * cosPhase,-choppiness * direction.y * direction.y * sinPhase);

        #if (ENABLE_MICRO_WAVES == 1)
        //Adds one small wave between octaves
        {
            float microAngle = angle + WAVE_MICRO_CHOP_ANGLE;
            float2 microDirection = normalize(float2(cos(microAngle), sin(microAngle)));

            float microWavelength = wavelength / WAVE_MICRO_FREQUENCY_MULT;
            float microVec = TWO_PI / microWavelength;

            float microAmplitude = amplitude * WAVE_MICRO_AMPLITUDE_MULT;
            float microChoppiness = choppiness / (microAmplitude * microVec);

            float microPhase = microVec * dot(microDirection, xz) - sqrt(9.81f * microVec) * (time * WAVE_SPEED * 0.25f * WAVE_MICRO_SPEED_MULT);

            float microS = sin(microPhase);
            float microC = cos(microPhase);

            wave.height += microAmplitude * microS;
            wave.horizontalOffset += microChoppiness * microAmplitude * microDirection * microC;

            wave.dPdx += float3(-microChoppiness * microAmplitude * microDirection.x * microDirection.x * microS,microAmplitude * microVec * microDirection.x * microC, -microChoppiness * microAmplitude * microDirection.x * microDirection.y * microS);
            wave.dPdz += float3(-microChoppiness * microAmplitude * microDirection.x * microDirection.y * microS, microAmplitude * microVec * microDirection.y * microC, -microChoppiness * microAmplitude * microDirection.y * microDirection.y * microS);
        }

        #if (WAVE_MICRO_WAVES_PER_OCTAVE > 1)
        // Secondary wave that rolls in a different direction
        {
            float microAngle2 = angle - WAVE_MICRO_CHOP_ANGLE + 0.61803398f;
            float2 microDirection = normalize(float2(cos(microAngle2), sin(microAngle2)));

            float microWavelength = wavelength / (WAVE_MICRO_FREQUENCY_MULT * 1.35f);
            float microVec = TWO_PI / microWavelength;

            float microAmplitude = amplitude * (WAVE_MICRO_AMPLITUDE_MULT * 0.65f);
            float microChoppiness= choppiness / (microAmplitude * microVec);

            float microPhase2 = microVec * dot(microDirection, xz) - sqrt(9.81f * microVec) * (time * WAVE_SPEED * 0.25f * (WAVE_MICRO_SPEED_MULT * 1.1f));

            float microS2 = sin(microPhase2);
            float microC2 = cos(microPhase2);

            wave.height += microAmplitude * microS2;
            wave.horizontalOffset += microChoppiness * microAmplitude * microDirection * microC2;

            wave.dPdx += float3(-microChoppiness * microAmplitude * microDirection.x * microDirection.x * microS2,microAmplitude * microVec * microDirection.x * microC2, -microChoppiness * microAmplitude * microDirection.x * microDirection.y * microS2);
            wave.dPdz += float3(-microChoppiness * microAmplitude * microDirection.x * microDirection.y * microS2,microAmplitude * microVec * microDirection.y * microC2,-microChoppiness * microAmplitude * microDirection.y * microDirection.y * microS2);
        }
        #endif // WAVE_MICRO_WAVES_PER_OCTAVE > 1
        #endif // ENABLE_MICRO_WAVES == 1
    }
    return wave;
}

// Parallax evaluation for water waves using iterative contact refinement.
// Directly solves the ray-surface intersection against the exact Gerstner waves,
// ensuring every visible wave normal pattern has corresponding 3D displacement.
float EvaluateWaterParallax(
    float3 hitPos,
    float3 rayDir,
    float3 geoNormal,
    float2 waveOriginXZ,
    float time,
    float waveFade,
    out float3 displacedHitPos,
    out GerstnerSample outWave)
{
    displacedHitPos = hitPos;

    float2 baseXZ = hitPos.xz - waveOriginXZ;
    baseXZ = baseXZ - floor(baseXZ / 1024.0f) * 1024.0f;

    #if (ENABLE_WATER_PARALLAX == 0)
    outWave = SampleGerstner(baseXZ, time);
    return 0.0f;
    #else
    // Only apply parallax on largely horizontal surfaces (not vertical waterfall walls)
    if (abs(geoNormal.y) < 0.5f || waveFade <= 0.01f) {
        outWave = SampleGerstner(baseXZ, time);
        return 0.0f;
    }

    float safeDy = (abs(rayDir.y) < 0.12f) ? (sign(rayDir.y) * 0.12f) : rayDir.y;
    float maxT = clamp(2.5f * WAVE_HEIGHT / abs(safeDy), 0.2f, WATER_PARALLAX_MAX_DIST);

    float parralaxHeight = 0.0f;
    float2 currXZ = baseXZ;
    GerstnerSample wave;

    [unroll]
    for (uint iter = 0; iter < WATER_PARALLAX_STEPS; ++iter) {
        wave = SampleGerstner(currXZ, time);
        float height = wave.height * waveFade;
        float targetHeight = clamp(height / safeDy, -maxT, maxT);
        parralaxHeight = lerp(parralaxHeight, targetHeight, 0.75f);
        currXZ = baseXZ + parralaxHeight * rayDir.xz;
    }

    wave = SampleGerstner(currXZ, time);
    outWave = wave;

    float finalHeight = wave.height * waveFade;
    float finalParallaxHeight = clamp(finalHeight / safeDy, -maxT, maxT);
    displacedHitPos = hitPos + finalParallaxHeight * rayDir;
    return finalParallaxHeight;
    #endif
}

#endif //WATER_HLSL