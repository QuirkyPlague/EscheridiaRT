#ifndef WATER_HLSL
#define WATER_HLSL

#include "settings.hlsl"
#include "Util.hlsl"

// Calculates wave value and its derivative,
// for the wave direction, position in space, wave frequency and time
float2 wavedx(float2 position, float2 direction, float frequency, float timeshift)
{
    float x = dot(direction, position) * frequency + timeshift;
    float wave = exp(sin(x) - 1.0f);
    float dx = wave * cos(x);
    return float2(wave, -dx);
}

// Calculates waves by summing octaves of various waves with various parameters
float getwaves(float2 position, int iterations, float frameTimeCounter)
{
    float wavePhaseShift = length(position) * WAVE_RANDOMNESS; // avoid identical phase each octave
    float iter = 0.0f; // helps generate well-distributed wave directions
    float frequency = WAVE_FREQUENCY; // base frequency (modified per octave)
    float timeMultiplier = WAVE_SPEED; // base time multiplier (modified per octave)
    float weight = 0.85f; // base weight (modified per octave)
    float sumOfValues = 0.0f;
    float sumOfWeights = 0.0f;

    for (int i = 0; i < iterations; ++i)
    {
        // generate some wave direction that looks kind of random
        float2 p = float2(sin(iter), cos(iter));

        // calculate wave data
        float2 res = wavedx(position, p, frequency, g_view.time * timeMultiplier + wavePhaseShift);

        // shift position around according to wave drag and derivative of the wave
        position += p * res.y * weight * WAVE_PULL;

        // add the results to sums
        sumOfValues += res.x * weight;
        sumOfWeights += weight;

        // modify next octave
        weight = lerp(weight, 0.0f, WAVE_OCTAVE_MIX_WEIGHT);
        frequency *= WAVE_OCTAVE_FREQUENCY;
        timeMultiplier *= WAVE_OCTAVE_SPEED;

        // add some kind of random value to make next wave look random too
        iter += 1232.399963f;
    }

    // final normalized sum
    return sumOfValues / sumOfWeights;
}

// Calculate normal at point by calculating the height at pos and 2 additional nearby points
float3 waveNormal(float2 pos, float e, float depth)
{   
    
    float2 ex = float2(e, 0.0f);

    float H = getwaves(pos, WAVE_OCTAVES, g_view.time) * depth;
    float3 a = float3(pos.x, H, pos.y);

    float hL = getwaves(pos - ex, WAVE_OCTAVES, g_view.time) * depth;         
    float hR = getwaves(pos + ex.xy, WAVE_OCTAVES, g_view.time) * depth;     

    float3 v1 = a - float3(pos.x - e, hL, pos.y);
    float3 v2 = a - float3(pos.x, hR, pos.y + e);

    return normalize(cross(v1, v2));
}


float calcWaterCaustics(float3 position, float rayLength) {
    //
    // Old-school animated texture lookup
    //
    float2 wibblyUV = mad(position.xz, g_view.steveToWibblyScale, g_view.steveToWibblyBias);
    float2 wibble = wibblyTexture.SampleLevel(linearWrapSampler, wibblyUV, 0) - 0.5;

    float2 causticsUV = float2(mad(position.xz, g_view.steveToCausticsScale, g_view.steveToCausticsBias));
    causticsUV += wibble * 0.6;

    const int causticsWNum = 64;

    float index = g_view.causticsWCoord * (causticsWNum - 1);
    int causticsW1 = floor(index);
    int causticsW2 = (causticsW1 + 1) % causticsWNum;
    float caustic1 = causticsTexture.SampleLevel(linearWrapSampler, float3(causticsUV, causticsW1), 0);
    float caustic2 = causticsTexture.SampleLevel(linearWrapSampler, float3(causticsUV, causticsW2), 0);

    float caustics = lerp(caustic1, caustic2, frac(index)) * 7;

    caustics *= 3.0;
    caustics += 0.4f; // Normalisation offset (texture isn't great)
    // Reduce the effects with depth.  TODO: Add mipmaps
    caustics = lerp(1, caustics, exp2(-rayLength * 0.001));
    return max(caustics, 0.0);
}

#endif //WATER_HLSL