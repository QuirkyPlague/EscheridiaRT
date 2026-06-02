#include "Include/Generated/Signature.hlsl"

[numthreads(32, 1, 1)]
void UpdateFaceIrradianceCacheInline(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex, 
    uint3 groupID : SV_GroupID
    )
{
    const uint kFacesPerCacheUpdateChunk = 16;

    uint faceIndex = dispatchThreadID.x;
    
    FaceIrradianceCacheUpdateChunk updateChunk = faceIrradianceCacheUpdateChunks[faceIndex / kFacesPerCacheUpdateChunk];
    uint chunkRelativeFaceIndex = faceIndex % kFacesPerCacheUpdateChunk;

    uint objectInstanceIndex = updateChunk.objectInstanceIdxAndNumFaces & 0xffff;
    uint numFacesInChunk = updateChunk.objectInstanceIdxAndNumFaces >> 16;

    if(chunkRelativeFaceIndex >= numFacesInChunk) return;
    faceIndex = updateChunk.firstFaceIdx + chunkRelativeFaceIndex;
}