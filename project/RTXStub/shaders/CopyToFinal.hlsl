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

#include "Include/Generated/Signature.hlsl"
#include "Include/Util.hlsl"
#include "Include/tonemapping.hlsl"

[numthreads(16, 16, 1)]
void CopyToFinal(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex, 
    uint3 groupID : SV_GroupID
    )
{
    // *cricket noises*
    // Note that g_rootConstant0 from FinalCombine pass is accessible here

    // Below code is part of the example ray tracing shader implementation.
    if (any(dispatchThreadID.xy >= g_view.displayResolution)) return;

    if (isUpscalingEnabled()) {
        // Pick up upscaled results from inputThisFrameTAAHistory
        float4 upscaledColor = inputThisFrameTAAHistory[dispatchThreadID.xy];
        upscaledColor.xyz = reinhard_extended(upscaledColor.xyz, 11.2);
        upscaledColor.xyz = pow(upscaledColor.xyz, 1.0/2.2); // Gamma correction.
        outputBufferFinal[dispatchThreadID.xy] = upscaledColor;
    } 
}