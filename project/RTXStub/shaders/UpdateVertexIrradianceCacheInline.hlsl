#include "Include/Generated/Signature.hlsl"

[numthreads(32, 1, 1)]
void UpdateVertexIrradianceCacheInline(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex, 
    uint3 groupID : SV_GroupID
    )
{
    const uint kVertsPerCacheUpdateChunk = 16;

    uint randomSeed = g_rootConstant0;
    uint vertexIndex = dispatchThreadID.x;
    
    VertexIrradianceCacheUpdateChunk updateChunk = vertexIrradianceCacheUpdateChunks[vertexIndex / kVertsPerCacheUpdateChunk];
    uint chunkRelativeVertexIndex = vertexIndex % kVertsPerCacheUpdateChunk;

    uint objectInstanceIndex = updateChunk.objectInstanceIdxAndNumVertices & 0xffff;
    uint numVerticesInChunk = updateChunk.objectInstanceIdxAndNumVertices >> 16;

    if(chunkRelativeVertexIndex >= numVerticesInChunk) return;
    vertexIndex = updateChunk.firstVertexIdx + chunkRelativeVertexIndex;
}