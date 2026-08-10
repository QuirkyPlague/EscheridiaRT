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
#include "Include/settings.hlsl"

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

    if (any(dispatchThreadID.xy >= g_view.displayResolution)) return;

    float4 color;
    if (isUpscalingEnabled()) {
        // Pick up upscaled results from inputThisFrameTAAHistory
        color = inputThisFrameTAAHistory[dispatchThreadID.xy];
        static const float3x3 matrix_rec709_to_xyz = transpose(float3x3(0.412390917540, 0.357584357262, 0.180480793118, 0.212639078498, 0.715168714523, 0.072192311287, 0.019330825657, 0.119194783270, 0.950532138348));
        static const float3x3 matrix_xyz_to_p3d65 = transpose(float3x3(2.49349691194, -0.931383617919, -0.402710784451, -0.829488969562, 1.76266406032, 0.023624685842, 0.035845830244, -0.076172389268, 0.956884524008));
        static const float3x3 matrix_xyz_to_rec2020 = transpose(float3x3(1.71665118797, -0.355670783776, -0.253366281374, -0.666684351832, 1.61648123664, 0.015768545814, 0.017639857445, -0.042770613258, 0.942103121235));

        /*
        #if COLOR_SPACE == 0
        // The color is already in linear and prepared for SRGB 
        color = color; 
        #elif COLOR_SPACE == 1
        // Convert from linear color to Rec 709
        color.rgb = mul(color.rgb, matrix_rec709_to_xyz);
        #elif COLOR_SPACE == 2
        // Convert from linear to Rec 2020 
        color.rgb =  mul(mul(color.rgb, matrix_rec709_to_xyz), matrix_xyz_to_rec2020);
        #else 
        // Convert from Linear to Display P3
        color.rgb = mul(mul(color.rgb, matrix_rec709_to_xyz), matrix_xyz_to_p3d65);
        #endif
       */
        outputBufferFinal[dispatchThreadID.xy] = color;
        } else {
        color = outputBufferFinal[dispatchThreadID.xy];
        // Matrices from OpenDRT
        static const float3x3 matrix_rec709_to_xyz = transpose(float3x3(0.412390917540, 0.357584357262, 0.180480793118, 0.212639078498, 0.715168714523, 0.072192311287, 0.019330825657, 0.119194783270, 0.950532138348));
        static const float3x3 matrix_xyz_to_p3d65 = transpose(float3x3(2.49349691194, -0.931383617919, -0.402710784451, -0.829488969562, 1.76266406032, 0.023624685842, 0.035845830244, -0.076172389268, 0.956884524008));
        static const float3x3 matrix_xyz_to_rec2020 = transpose(float3x3(1.71665118797, -0.355670783776, -0.253366281374, -0.666684351832, 1.61648123664, 0.015768545814, 0.017639857445, -0.042770613258, 0.942103121235));
       /*
           #if COLOR_SPACE == 0
        // The color is already in linear and prepared for SRGB 
        color = color; 
        #elif COLOR_SPACE == 1
        // Convert from linear color to Rec 709
        color.rgb = mul(color.rgb, matrix_rec709_to_xyz);
        #elif COLOR_SPACE == 2
        // Convert from linear to Rec 2020 
        color.rgb =  mul(mul(color.rgb, matrix_rec709_to_xyz), matrix_xyz_to_rec2020);
        #else 
        // Convert from Linear to Display P3
        color.rgb = mul(mul(color.rgb, matrix_rec709_to_xyz), matrix_xyz_to_p3d65);
        #endif
        */
        outputBufferFinal[dispatchThreadID.xy] = color;
    }
    
}