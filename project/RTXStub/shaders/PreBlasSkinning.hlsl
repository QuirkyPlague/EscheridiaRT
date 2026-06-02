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

[numthreads(64, 1, 1)]
void PreBlasSkinning(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex, 
    uint3 groupID : SV_GroupID
    )
{
    // Below is a basic implementation of skinning, which is necessary to animate geometry as well as to propagate previous position for motion vectors.

    // TODO: explore caching vertex data in array so that we separate buffer reads and writes; 
    // and explore increasing buffer load/store transaction size (e.g. uint4) so that we operate on larger chunks of data.  
    if (dispatchThreadID.x >= g_meshSkinningData.vertexCount) return;

    RWByteAddressBuffer sourceBuffer = vertexBuffersRW[g_meshSkinningData.sourceVBIndex];
    RWByteAddressBuffer destBuffer = vertexBuffersRW[g_meshSkinningData.destVBIndex];

    uint addressFrom = dispatchThreadID.x * g_meshSkinningData.sizeOfVertex + g_meshSkinningData.sourceVBOffset;
    uint addressTo = dispatchThreadID.x * g_meshSkinningData.sizeOfVertex + g_meshSkinningData.destVBOffset;

    float16_t4 prevPos;
    if (g_meshSkinningData.offsetToPrevPos != 0xFFFFFFFF) {
        prevPos = destBuffer.Load<float16_t4>(addressTo + g_meshSkinningData.offsetToPosition); // TODO: do we use addressTo or subtract destVBOffset?
    }

    for (uint i=0; i < g_meshSkinningData.sizeOfVertex; i+=4) destBuffer.Store(addressTo+i, sourceBuffer.Load(addressFrom+i));

    if (g_meshSkinningData.offsetToPrevPos != 0xFFFFFFFF) {
        destBuffer.Store<float16_t4>(addressTo + g_meshSkinningData.offsetToPrevPos, prevPos);
    }
    
    uint boneIndex = sourceBuffer.Load<uint16_t>(addressFrom + g_meshSkinningData.offsetToBoneIndex);
    if (boneIndex > 7) return; // We only have 8 bones.
    
    float4x4 bone = g_meshSkinningData.bones[boneIndex];

    float16_t4 pos = sourceBuffer.Load<float16_t4>(addressFrom + g_meshSkinningData.offsetToPosition);
    pos = (float16_t4)mul(bone, pos);
    destBuffer.Store<float16_t4>(addressTo + g_meshSkinningData.offsetToPosition, pos);

    uint normalPacked = sourceBuffer.Load<uint>(addressFrom + g_meshSkinningData.offsetToNormal);
    float4 normal = unpackNormal(normalPacked);
    normal = mul(bone, normal);
    normal.xyz = normalize(normal.xyz);
    destBuffer.Store(addressTo + g_meshSkinningData.offsetToNormal, packNormal(normal));
}