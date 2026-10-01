#include "Include/Generated/Signature.hlsl"
#include "Include/Util.hlsl"
#include "Include/settings.hlsl"

static const uint HISTOGRAM_FIRST_BIN = 1;
static const uint HISTOGRAM_BIN_COUNT = 255;

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
        float targetLogLuminance = log2(TARGET_EXPOSURE_EV);
        float targetExposureEV = clamp(
            targetLogLuminance - measuredLogLuminance,
            EXPOSURE_MIN,
            EXPOSURE_MAX);

        outputBufferToneCurve[uint2(4, 0)] = measuredLogLuminance;
        outputBufferToneCurve[uint2(3, 0)] =
            lerp(previousExposureEV, targetExposureEV, 0.05);
    }
    else
    {
        outputBufferToneCurve[uint2(3, 0)] = previousExposureEV;
    }

    // Clear bins per frame so temporal data can contribute
    for (uint clearBin = HISTOGRAM_FIRST_BIN;
         clearBin < HISTOGRAM_FIRST_BIN + HISTOGRAM_BIN_COUNT;
         ++clearBin)
    {
        outputBufferToneMappingHistogram[uint2(clearBin, 0)] = 0;
    }
}
