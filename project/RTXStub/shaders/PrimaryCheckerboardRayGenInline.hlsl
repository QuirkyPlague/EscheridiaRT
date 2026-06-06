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

// If enabled, will match vanilla graphics and cull transparent back faces. Refer to Renderer.hlsl to see what it does.
#define CULL_GLASS_BACK_FACES 0

#include "Include/Renderer.hlsl"
#include "Include/Util.hlsl"

[numthreads(4, 8, 1)]
void PrimaryCheckerboardRayGenInline(
    uint3 dispatchThreadID: SV_DispatchThreadID,
    uint3 groupThreadID: SV_GroupThreadID,
    uint groupIndex: SV_GroupIndex,
    uint3 groupID: SV_GroupID)
{
    // *cricket noises*
    // Note that g_rootConstant0 from AdaptiveDenoiserCalculateGradients pass is accessible here
    

    // Below is an implementation of a basic ray traced vanilla-like shader.
    if (any(dispatchThreadID.xy >= g_view.renderResolution)) return;

    RayDesc rayDesc;
    rayDesc.Direction = rayDirFromNDC(getNDCjittered(dispatchThreadID.xy));
    rayDesc.Origin = g_view.viewOriginSteveSpace;
    rayDesc.TMin = 0; rayDesc.TMax = 10000;

    float hitDist; float3 objMotion;
    float3 color = RenderRay(rayDesc, dispatchThreadID.xy, hitDist, objMotion);

    float2 motionVector = computeMotionVector(rayDesc.Origin + rayDesc.Direction * hitDist, objMotion);

    // Basic debug views for NaNs and Infinity
    #if 1
    if (any(isinf(color)) || any(isinf(motionVector)) || isinf(hitDist))
        color = (dispatchThreadID.x / 32 + dispatchThreadID.y / 32) & 1 ? float3(1, 1, 0) : 0;
    if (any(isnan(color)) || any(isnan(motionVector)) || isnan(hitDist))
        color = (dispatchThreadID.x / 32 + dispatchThreadID.y / 32) & 1 ? float3(1, 0, 1) : 0;
    #endif

    // The only 3 buffers necessary for upscaling support (e.g. DLSS)
    outputBufferFinal[dispatchThreadID.xy] = float4(color, 1);
    outputBufferMotionVectors[dispatchThreadID.xy] = motionVector;
    outputBufferReprojectedPathLength[dispatchThreadID.xy] = hitDist;
}
