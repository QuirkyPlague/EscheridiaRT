#include "Include/Generated/Signature.hlsl"

[numthreads(16, 16, 1)]
void SpecularFireflyFilter(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex,
    uint3 groupID : SV_GroupID)
{
    uint outputIndex = (g_rootConstant0 >> 8) & 0xff;
    uint denoisingParamsIndex = (g_rootConstant0 >> 24) % 2;

    uint width, height;
    outputBufferIndirectDiffuse.GetDimensions(width, height);
    uint2 pixel = dispatchThreadID.xy;
    if (pixel.x >= width || pixel.y >= height)
        return;

    float4 center = outputBufferIndirectDiffuse[pixel];
    if (!all(isfinite(center)))
    {
        denoisingOutputs[outputIndex][pixel] = 0.0;
        return;
    }

    // Keep real emissive surfaces intact; this pass is meant to remove noisy
    // transport outliers, not dim the light source itself.
    float3 emissive = inputEmissiveAndLinearRoughness[pixel].rgb;
    if (any(emissive > 1e-4))
    {
        denoisingOutputs[outputIndex][pixel] = center;
        return;
    }

    float centerDepth = inputBufferPrimaryPathLength[pixel];
    float neighborLuminances[8];
    uint neighborCount = 0;
    float neighborMaximum = 0.0;

    // Gather a same-surface 3x3 neighborhood, excluding the center. Depth
    // rejection prevents a bright object from being clipped against the wall
    // or sky behind it.
    [unroll]
    for (int y = -1; y <= 1; ++y)
    {
        [unroll]
        for (int x = -1; x <= 1; ++x)
        {
            if (x == 0 && y == 0)
                continue;

            int2 samplePixel = int2(pixel) + int2(x, y);
            if (samplePixel.x < 0 || samplePixel.y < 0 ||
                samplePixel.x >= int(width) || samplePixel.y >= int(height))
                continue;

            uint2 sampleCoord = uint2(samplePixel);
            float sampleDepth = inputBufferPrimaryPathLength[sampleCoord];
            float depthTolerance = max(0.05, abs(centerDepth) * 0.02);
            if (!isfinite(sampleDepth) || abs(sampleDepth - centerDepth) > depthTolerance)
                continue;

            float3 sampleColor = outputBufferIndirectDiffuse[sampleCoord].rgb;
            if (!all(isfinite(sampleColor)))
                continue;

            float sampleLuminance = dot(max(sampleColor, 0.0), float3(0.2126, 0.7152, 0.0722));
            neighborLuminances[neighborCount++] = sampleLuminance;
            neighborMaximum = max(neighborMaximum, sampleLuminance);
        }
    }

    float centerLuminance = dot(max(center.rgb, 0.0), float3(0.2126, 0.7152, 0.0722));
    if (neighborCount >= 4 && centerLuminance > 0.0)
    {
        // Median and median absolute deviation are robust against other bright
        // samples in the neighborhood, unlike a local mean.
        [loop]
        for (uint i = 1; i < neighborCount; ++i)
        {
            float key = neighborLuminances[i];
            int j = int(i) - 1;
            [loop]
            while (j >= 0 && neighborLuminances[j] > key)
            {
                neighborLuminances[j + 1] = neighborLuminances[j];
                --j;
            }
            neighborLuminances[j + 1] = key;
        }

        float localMedian = neighborCount & 1
            ? neighborLuminances[neighborCount / 2]
            : 0.5 * (neighborLuminances[neighborCount / 2 - 1] + neighborLuminances[neighborCount / 2]);

        float deviations[8];
        [loop]
        for (uint i = 0; i < neighborCount; ++i)
            deviations[i] = abs(neighborLuminances[i] - localMedian);

        [loop]
        for (uint i = 1; i < neighborCount; ++i)
        {
            float key = deviations[i];
            int j = int(i) - 1;
            [loop]
            while (j >= 0 && deviations[j] > key)
            {
                deviations[j + 1] = deviations[j];
                --j;
            }
            deviations[j + 1] = key;
        }

        float localMad = neighborCount & 1
            ? deviations[neighborCount / 2]
            : 0.5 * (deviations[neighborCount / 2 - 1] + deviations[neighborCount / 2]);

        // Use a high robust threshold, and never force ordinary low-radiance
        // indirect light down to the near-zero median of a dark neighborhood.
        // Increase epsilon or neighborScale to make filtering gentler.
        float epsilon = clamp(g_view.denoisingParams[denoisingParamsIndex].despeckleFilterRelativeDifferenceEpsilon, 32.0, 145.0);
        const float neighborScale = 12.0;
        const float minimumLuminanceLimit = 32.0;
        float luminanceLimit = max(localMedian * (1.0 + epsilon), localMedian + 8.0 * localMad);
        luminanceLimit = max(luminanceLimit, neighborMaximum * neighborScale);
        luminanceLimit = max(luminanceLimit, minimumLuminanceLimit);

        if (centerLuminance > luminanceLimit)
            center.rgb *= luminanceLimit / centerLuminance;
    }

    denoisingOutputs[outputIndex][pixel] = center;
}
