[numthreads(256, 1, 1)]
void ToneCurve(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex, 
    uint3 groupID : SV_GroupID
    )
{
    // *cricket noises*
    // Note that g_rootConstant0 from FinalCombine pass is accessible here
    // This pass only dispatches (1,1,1) groups of 256 threads against the 256x1 tone-curve LUT
    // buffer, so it can't do full-screen per-pixel work (see BloomCompute chain instead).
}