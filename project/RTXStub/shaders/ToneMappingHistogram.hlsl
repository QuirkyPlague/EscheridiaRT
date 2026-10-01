#include "Include/Generated/Signature.hlsl"
#include "Include/Util.hlsl"
#include "Include/settings.hlsl"

static const uint HISTOGRAM_FIRST_BIN = 1;
static const uint HISTOGRAM_BIN_COUNT = 255;
static const float HISTOGRAM_LUMA_FLOOR = 1e-4;
static const float SKY_PATH_LENGTH_THRESHOLD = 60000.0;
static const uint SKY_EXPOSURE_WEIGHT = 1;
static const uint TERRAIN_EXPOSURE_WEIGHT = 4;

groupshared float tileLuminanceSums[256];
groupshared uint tileWeightSums[256];
groupshared uint tilePixelCounts[256];

[numthreads(16, 16, 1)]
void ToneMappingHistogram(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex,
    uint3 groupID : SV_GroupID)
{
    uint2 fullRes = uint2(g_view.displayResolution);
    uint2 pixelPos = dispatchThreadID.xy;

    // Each 16x16 thread group corresponds to one screen tile. Every tile gets
    // one histogram vote, regardless of how many pixels it contains.
    float pixelLuminance = 0.0;
    uint pixelWeight = 0;
    uint pixelCount = 0;
    if (all(pixelPos < fullRes))
    {
        // The final color is at display resolution, while the path-length
        // buffer is at render resolution. Map the display pixel to its nearest
        // current-frame render pixel before deciding whether it hit the sky.
        uint2 renderRes = uint2(g_view.renderResolution);
        uint2 renderPos = min(
            (pixelPos * renderRes) / max(fullRes, uint2(1, 1)),
            max(renderRes, uint2(1, 1)) - 1);
        float pathLength = outputBufferReprojectedPathLength[renderPos];

        // Sky still contributes, but terrain pixels receive more influence.
        // RenderRay writes 65504 for sky misses.
        bool isTerrain = isfinite(pathLength) && pathLength < SKY_PATH_LENGTH_THRESHOLD;
        pixelWeight = isTerrain ? TERRAIN_EXPOSURE_WEIGHT : SKY_EXPOSURE_WEIGHT;
        float3 sceneColor = outputBufferFinal[pixelPos].rgb;
        pixelLuminance = max(dot(sceneColor, float3(0.2126, 0.7152, 0.0722)), 0.0);
        pixelCount = 1;
    }

    tileLuminanceSums[groupIndex] = pixelLuminance * pixelWeight;
    tileWeightSums[groupIndex] = pixelWeight;
    tilePixelCounts[groupIndex] = pixelCount;
    GroupMemoryBarrierWithGroupSync();

    // Reduce the tile's luminance sum and valid-pixel count.
    for (uint stride = 128; stride > 0; stride >>= 1)
    {
        if (groupIndex < stride)
        {
            tileLuminanceSums[groupIndex] += tileLuminanceSums[groupIndex + stride];
            tileWeightSums[groupIndex] += tileWeightSums[groupIndex + stride];
            tilePixelCounts[groupIndex] += tilePixelCounts[groupIndex + stride];
        }
        GroupMemoryBarrierWithGroupSync();
    }

    if (groupIndex == 0 && tilePixelCounts[0] > 0 && tileWeightSums[0] > 0)
    {
        float tileAverageLuminance = tileLuminanceSums[0] / tileWeightSums[0];
        float logLuminance = log2(max(tileAverageLuminance, HISTOGRAM_LUMA_FLOOR));

        float normalized = saturate(
            (logLuminance - AUTO_EXPOSURE_MIN) /
            (AUTO_EXPOSURE_MAX - AUTO_EXPOSURE_MIN));
        uint bin = HISTOGRAM_FIRST_BIN +
            min((uint)(normalized * HISTOGRAM_BIN_COUNT), HISTOGRAM_BIN_COUNT - 1);

        // Terrain-dominated tiles receive more votes; all-sky tiles still vote.
        uint tileVoteWeight = max(
            1u,
            (tileWeightSums[0] + tilePixelCounts[0] / 2) / tilePixelCounts[0]);
        InterlockedAdd(outputBufferToneMappingHistogram[uint2(bin, 0)], tileVoteWeight);
    }
}
