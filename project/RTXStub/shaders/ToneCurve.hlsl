#include "Include/Generated/Signature.hlsl"
#include "Include/Util.hlsl"
#include "Include/settings.hlsl"

static const uint HISTOGRAM_FIRST_BIN = 1;
static const uint HISTOGRAM_BIN_COUNT = 255;

// Sun elevation range over which the exposure cap goes from night to day. Starting below the horizon
// lets exposure begin lifting during twilight; raise DAY_FADE_START to delay, lower to brighten earlier.
static const float DAY_FADE_START = -0.25;
static const float DAY_FADE_END = 0.2;

float getDayFade()
{
    return smoothstep(DAY_FADE_START, DAY_FADE_END, getDirectionToSun().y);
}

[numthreads(256, 1, 1)]
void ToneCurve(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex,
    uint3 groupID : SV_GroupID)
{
    // This pass dispatches one group. A single lane computes exposure from the
    // tile histogram; slot 0 remains available for the accumulation frame index.
    if (dispatchThreadID.x != 0)
        return;

    uint totalWeightedTiles = 0;
    for (uint bin = HISTOGRAM_FIRST_BIN;
         bin < HISTOGRAM_FIRST_BIN + HISTOGRAM_BIN_COUNT;
         ++bin)
    {
        totalWeightedTiles += outputBufferToneMappingHistogram[uint2(bin, 0)];
    }

    float previousExposureEV = outputBufferToneCurve[uint2(3, 0)];
    if (!isfinite(previousExposureEV) ||
        previousExposureEV < EXPOSURE_MIN ||
        previousExposureEV > EXPOSURE_MAX)
    {
        previousExposureEV = 0.0;
    }

    // Use the configured percentile of weighted tile-average luminance. Sky
    // tiles remain in the histogram, while terrain-dominated tiles have more votes.
    if (totalWeightedTiles > 0)
    {
        uint percentileTarget = max(
            1u,
            (uint)ceil((float)totalWeightedTiles * saturate(EXPOSURE_PERCENTILE)));
        uint cumulativeTiles = 0;
        uint exposureBin = HISTOGRAM_FIRST_BIN;

        for (uint bin = HISTOGRAM_FIRST_BIN;
             bin < HISTOGRAM_FIRST_BIN + HISTOGRAM_BIN_COUNT;
             ++bin)
        {
            cumulativeTiles += outputBufferToneMappingHistogram[uint2(bin, 0)];
            if (cumulativeTiles >= percentileTarget)
            {
                exposureBin = bin;
                break;
            }
        }

        float measuredLogLuminance = AUTO_EXPOSURE_MIN +
            ((exposureBin - HISTOGRAM_FIRST_BIN + 0.5) / (float)HISTOGRAM_BIN_COUNT) *
            (AUTO_EXPOSURE_MAX - AUTO_EXPOSURE_MIN);

        // Adaptation luminance floor: prevents the eye/camera from boosting pitch-black
        // cave walls or unlit nights into mid-gray.
        float effectiveLogLuminance = max(measuredLogLuminance, log2(MIN_ADAPTATION_LUMINANCE));

        float targetLogLuminance = log2(TARGET_EXPOSURE_EV);

        // Dynamic exposure bounds based on sun elevation:
        // During the day, allow high exposure (+5 EV) so shaded spots adapt and sunlight looks dazzling.
        // At night, clamp to EXPOSURE_MAX_NIGHT (+0.5 EV) so night stays authentic and dark.
        float sunFade = getDayFade();
        float dynamicMaxEV = (inEnd || inNether) ? EXPOSURE_MAX : lerp(EXPOSURE_MAX_NIGHT, EXPOSURE_MAX_DAY, sunFade);

        float targetExposureEV = clamp(
            targetLogLuminance - effectiveLogLuminance,
            EXPOSURE_MIN,
            dynamicMaxEV);

        outputBufferToneCurve[uint2(4, 0)] = measuredLogLuminance;
        float adaptSpeed = (targetExposureEV < previousExposureEV) ? 0.08 : 0.05;
        outputBufferToneCurve[uint2(3, 0)] =
            lerp(previousExposureEV, targetExposureEV, adaptSpeed);
    }
    else
    {
        // When all tiles are pitch black, smoothly settle at the minimum adaptation target
        // rather than staying indefinitely at an old daytime exposure.
        float sunFade = getDayFade();
        float dynamicMaxEV = (inEnd || inNether) ? EXPOSURE_MAX : lerp(EXPOSURE_MAX_NIGHT, EXPOSURE_MAX_DAY, sunFade);
        float targetLogLuminance = log2(TARGET_EXPOSURE_EV);
        float floorLogLuminance = log2(MIN_ADAPTATION_LUMINANCE);
        float targetExposureEV = clamp(
            targetLogLuminance - floorLogLuminance,
            EXPOSURE_MIN,
            dynamicMaxEV);

        outputBufferToneCurve[uint2(3, 0)] =
            lerp(previousExposureEV, targetExposureEV, 0.05);
    }

    // Clear bins per frame so temporal data can contribute
    for (uint clearBin = HISTOGRAM_FIRST_BIN;
         clearBin < HISTOGRAM_FIRST_BIN + HISTOGRAM_BIN_COUNT;
         ++clearBin)
    {
        outputBufferToneMappingHistogram[uint2(clearBin, 0)] = 0;
    }
}
