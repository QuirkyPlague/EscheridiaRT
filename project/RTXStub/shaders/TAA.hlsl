#include "Include/Generated/Signature.hlsl"
#include "Include/Util.hlsl"
#include "Include/settings.hlsl"
#include "Include/BloomCompute.hlsl"


[numthreads(16, 16, 1)]
void TAA(
    uint3 dispatchThreadID : SV_DispatchThreadID,
    uint3 groupThreadID : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex, 
    uint3 groupID : SV_GroupID
    )
{
  
}