#ifndef RESAMPLING_HLSL
#define RESAMPLING_HLSL

#include "Material.hlsl"

// Weighted reservoir for Resampled Importance Sampling (RIS / WRS, Talbot et al. 2005).
// Stores a candidate index (e.g. into a light buffer) rather than the sample data itself,
// since candidates are cheap to reconstruct from an index but samples must stay unbiased.
struct Reservoir
{
    uint  sampleIndex; // Index of the currently selected candidate
    float weightSum;   // Running sum of RIS weights (p_hat(x_i) / sourcePdf(x_i)) streamed so far
    float M;           // Number of candidates streamed so far
    float W;           // Unbiased contribution weight of the selected sample; valid after FinalizeReservoir()
};

void InitReservoir(out Reservoir reservoir)
{
    reservoir.sampleIndex = 0;
    reservoir.weightSum = 0.0;
    reservoir.M = 0.0;
    reservoir.W = 0.0;
}

// Streams one candidate into the reservoir using weighted reservoir sampling.
// `risWeight` must be p_hat(candidate) / sourcePdf(candidate), where p_hat is the (cheap,
// unnormalized) target function being resampled against, e.g. an unshadowed radiance estimate.
// Returns true if `candidate` became the newly selected sample.
bool UpdateReservoir(inout Reservoir reservoir, uint candidate, float risWeight, inout PathRNG rng)
{
    reservoir.weightSum += risWeight;
    reservoir.M += 1.0;

    bool accept = risWeight > 0.0 && NextFloat(rng) * reservoir.weightSum < risWeight;
    if (accept)
    {
        reservoir.sampleIndex = candidate;
    }
    return accept;
}

// Merges an already-populated reservoir `other` into `reservoir`, preserving unbiasedness.
// `otherTargetPdf` is p_hat (evaluated in the receiving domain) at `other.sampleIndex`; required
// whenever the two reservoirs were built against different target functions (e.g. spatiotemporal reuse).
bool CombineReservoirs(inout Reservoir reservoir, Reservoir other, float otherTargetPdf, inout PathRNG rng)
{
    float otherRisWeight = otherTargetPdf * other.W * other.M;
    reservoir.M += other.M;

    if (otherRisWeight <= 0.0)
    {
        return false;
    }

    reservoir.weightSum += otherRisWeight;

    bool accept = NextFloat(rng) * reservoir.weightSum < otherRisWeight;
    if (accept)
    {
        reservoir.sampleIndex = other.sampleIndex;
    }
    return accept;
}

// Call once candidate streaming is finished, passing `targetPdf` = p_hat evaluated at the
// selected sample. After this, `reservoir.W` is the unbiased contribution weight to multiply
// the integrand by (i.e. estimator = f(selected) * reservoir.W, with 1/sourcePdf already folded in).
void FinalizeReservoir(inout Reservoir reservoir, float targetPdf)
{
    reservoir.W = (targetPdf > 0.0 && reservoir.M > 0.0)
        ? reservoir.weightSum / (targetPdf * reservoir.M)
        : 0.0;
}

// Same idea as `Reservoir`, but for resampling continuous samples (e.g. bounce directions)
// where there's no buffer index to keep around -- the candidate value itself is stored instead.
struct DirectionReservoir
{
    float3 direction;  // Currently selected candidate direction
    float  sourcePdf;  // Generation pdf of the selected candidate, wrt whichever technique produced it
    float  weightSum;  // Running sum of RIS weights (p_hat(x_i) / sourcePdf(x_i)) streamed so far
    float  M;          // Number of candidates streamed so far
    float  W;          // Unbiased contribution weight of the selected sample; valid after FinalizeDirectionReservoir()
};

void InitDirectionReservoir(out DirectionReservoir reservoir)
{
    reservoir.direction = float3(0, 0, 0);
    reservoir.sourcePdf = 0.0;
    reservoir.weightSum = 0.0;
    reservoir.M = 0.0;
    reservoir.W = 0.0;
}

// Streams one candidate direction into the reservoir. `risWeight` must be p_hat(candidate) /
// sourcePdf(candidate), as in `UpdateReservoir`. Returns true if `candidate` was selected.
bool UpdateDirectionReservoir(inout DirectionReservoir reservoir, float3 candidate, float candidateSourcePdf, float risWeight, inout PathRNG rng)
{
    reservoir.weightSum += risWeight;
    reservoir.M += 1.0;

    bool accept = risWeight > 0.0 && NextFloat(rng) * reservoir.weightSum < risWeight;
    if (accept)
    {
        reservoir.direction = candidate;
        reservoir.sourcePdf = candidateSourcePdf;
    }
    return accept;
}

// See `FinalizeReservoir`; `targetPdf` is p_hat evaluated at the selected direction.
void FinalizeDirectionReservoir(inout DirectionReservoir reservoir, float targetPdf)
{
    reservoir.W = (targetPdf > 0.0 && reservoir.M > 0.0)
        ? reservoir.weightSum / (targetPdf * reservoir.M)
        : 0.0;
}




#endif // RESAMPLING_HLSL