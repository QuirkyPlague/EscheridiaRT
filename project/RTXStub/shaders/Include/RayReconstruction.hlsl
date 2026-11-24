// DLSS Ray Reconstruction (RR) support for the RTXBoost mod. See RR-SUPPORT.md in the repo root.
//
// The pack never runs RR itself. It only offers it to RTXBoost, which replaces the game's
// DLSS Super Resolution with DLSS RR when its user turns RR on. Without RTXBoost (or with RR
// off, or on a GPU without RR) nothing here changes the image.
//
// Handshake, inside outputBufferFinal (DLSS's colour input: a DISPLAY-size texture whose
// render-size top-left part is the image DLSS reads):
//   marker (W-1, H-1)  FinalCombine, every DLSS frame:
//                      (1729, packed-guide version, rrActive, code). The code in .w offers
//                      version 3: 1801 = offered, 1802 = RR mode with version 3 this frame,
//                      1803 = RR mode with packed guides this frame. x, y, z are only written
//                      where a packed layout fits (older RTXBoost builds read those). At DLAA the
//                      texel is an image pixel, so only its alpha carries the code.
//   ack    (W-2, H-1)  RTXBoost, after its RR evaluate: (1741, version, history cap, switches).
//                      CopyToFinal overwrites outputBufferFinal right after, so it first
//                      carries the ack into IncidentLight slot kRRAckSlot, stamped with the
//                      frame number. The next frame is in RR mode only if that stamp is the
//                      previous frame's. A missing ack means normal rendering on the next frame.
//
// Guides, version 3 (RTXBoost 1.5 and newer): RTXBoost binds a texture of its own to u8, a
// register the engine leaves empty (Signature.hlsl), and acks version 3 only once it is bound.
// The primary ray pass writes the guides flat and at full precision into it
// (2*rw x 2*rh + 8 texels, rw x rh = render size):
//   (x, y)            world normal xyz, roughness (the texture's, alpha = roughness^2)
//   (rw + x, y)       diffuse albedo rgb, linear view depth
//   (x, rh + y)       specular albedo rgb
//   (rw + x, rh + y)  specular hit distance, specular motion vector (uv), diffuse hit distance
//                     (RR_DIFFUSE_HITDIST, else 0)
//   (0, 2*rh)         meta: (1907, frame & 1023, rw & 1023, rh & 1023), so RTXBoost can see the
//                     pack really writes its texture
//   (1, 2*rh)         features: (1913, feature bits, frame & 1023, 0), written with the meta texel.
//                     Bit 1: the diffuse hit distance is there. RTXBoost only uses a feature while
//                     this texel carries the meta texel's frame stamp, so a stale texel (or a pack
//                     that never writes it) means "no features".
// Nothing is stored in outputBufferFinal, so every render size works, DLAA included.
// Never touch u8 without a version 3 ack: without RTXBoost the descriptor is not initialised.
//
// Guides, versions 1 and 2 (older RTXBoost builds): one packed texel per render pixel in the
// free part of outputBufferFinal next to the image (rrPackedGuidePos). Version 1 needs
// 2 * rw <= W (DLSS Performance, Ultra Performance), version 2 fills the L-shaped area around
// the image and fits up to a render scale of about 0.7 (Quality, Balanced). The marker offers
// version 1 where it fits (every RTXBoost build knows it) and version 2 elsewhere.
//
// What RR mode changes in this pack:
//   * DLSS RR gets the current filtered sample rather than the progressive accumulation.
//   * The colour is pre-exposed with the pack's auto exposure before DLSS RR and the exposure
//     is taken out again in CopyToFinal: RR denoises best near display brightness, while the
//     pack's raw radiance is up to 64x darker (the exposure is applied in the tonemapper).
//   * Depth and motion can describe the surface behind a primary fog scatter without
//     replacing the fog pixel's color guide with the surface material.
//   * Mirror-like pixels (polished metal, still water, glass at grazing angles) can hand RR the
//     guides, depth and motion of the surface seen in the mirror instead (primary surface
//     replacement, RR_PSR).

#ifndef __RAY_RECONSTRUCTION_HLSL__
#define __RAY_RECONSTRUCTION_HLSL__

#include "Generated/Signature.hlsl"
#include "Util.hlsl"
#include "settings.hlsl"

static const float kRRMarker = 1729.0f; // exact in fp16 (< 2048)
static const float kRRAck = 1741.0f;
static const float kRRMarker3 = 1801.0f; // version 3 code in the marker's .w (+1 RR mode v3, +2 RR mode packed)
static const float kRRMeta = 1907.0f;    // guide atlas meta texel
static const float kRRFeatures = 1913.0f; // guide atlas feature texel, next to the meta texel
static const uint kRRFeatureDiffuseHitDistance = 1u;
static const uint kRRAckSlot = 279;      // IncidentLight slot: RTXBoost's ack, carried to the next frame
static const uint kRRFrameSlot = 278;    // IncidentLight slot: this frame's RR state for CopyToFinal
static const float kRRFar = 65504.0f;    // largest fp16: "no surface" depth and hit distance

// Mirror-like lobes. Below this perceptual roughness a surface shows a sharp image of what it reflects
// or lets through, and RR only keeps that image sharp when it knows about it.
static const float kRRMirrorRoughness = 0.1f;
// An opaque surface counts as a mirror only where its reflection carries at least this share of its
// albedo: metals, not polished stone with a 4 % reflection over a coloured base.
static const float kRRMirrorMinShare = 0.5f;
// Mirror vertices followed in a row (a mirror seen in a mirror, a pool seen in polished metal).
static const uint kRRMaxMirrorVertices = 3u;

// ---- sizes and layouts ------------------------------------------------------------------
// DLSS (or DLAA) is the upscaler. At render size = display size only RTXBoost's ack tells
// that DLSS runs, which is enough: RR mode needs that ack anyway.
// The sizes are compared as integers: comparing the float sizes directly proved unreliable in game.
bool rrDlssFrame()
{
    uint2 r = uint2(g_view.renderResolution);
    uint2 d = uint2(g_view.displayResolution);
    return isUpscalingEnabled() && r.x <= d.x && r.y <= d.y;
}

// RRV2-MAP-BEGIN (plain uint maths; RTXBoost's unpack shader uses the same formulas)
bool rrV1Fits(uint rw, uint rh, uint dw, uint dh)
{
    return rw > 0u && rh > 0u && rw * 2u <= dw && rh < dh;
}

bool rrV2Fits(uint rw, uint rh, uint dw, uint dh)
{
    if (rw == 0u || rh == 0u || rw + 2u > dw || rh >= dh)
        return false;
    uint rightCount = (dw - rw) * (dh - 1u);
    return rw * rh <= rightCount + rw * (dh - rh);
}

// Version 2: right strip x in [rw, W), y in [0, H - 1) (the last row holds the marker and the
// ack), then the bottom strip x in [0, rw), y in [rh, H); render pixel index i = y * rw + x.
uint2 rrV2GuidePos(uint px, uint py, uint rw, uint rh, uint dw, uint dh)
{
    uint i = py * rw + px;
    uint sw = dw - rw;
    uint rightCount = sw * (dh - 1u);
    if (i < rightCount)
        return uint2(rw + i % sw, i / sw);
    uint j = i - rightCount;
    return uint2(j % rw, rh + j / rw);
}

bool rrV2IsGuideTexel(uint tx, uint ty, uint rw, uint rh, uint dw, uint dh)
{
    uint count = rw * rh;
    uint sw = dw - rw;
    uint rightCount = sw * (dh - 1u);
    if (tx >= rw && tx < dw && ty < dh - 1u)
        return ty * sw + (tx - rw) < count;
    if (tx < rw && ty >= rh && ty < dh)
        return rightCount + (ty - rh) * rw + tx < count;
    return false;
}
// RRV2-MAP-END

// The packed-guide version the marker offers at this size: 1 where it fits (every RTXBoost
// build reads it), else 2, else 0 (only version 3 fits, e.g. at DLAA).
uint rrPackedVersion()
{
    uint2 r = uint2(g_view.renderResolution);
    uint2 d = uint2(g_view.displayResolution);
    if (rrV1Fits(r.x, r.y, d.x, d.y)) return 1u;
    if (rrV2Fits(r.x, r.y, d.x, d.y)) return 2u;
    return 0u;
}

uint2 rrPackedGuidePos(uint2 pixel, uint version)
{
    uint2 r = uint2(g_view.renderResolution);
    uint2 d = uint2(g_view.displayResolution);
    if (version == 1u) return uint2(r.x + pixel.x, pixel.y);
    return rrV2GuidePos(pixel.x, pixel.y, r.x, r.y, d.x, d.y);
}

uint2 rrMarkerPos() { return uint2(g_view.displayResolution) - uint2(1, 1); }
uint2 rrAckPos() { return uint2(g_view.displayResolution) - uint2(2, 1); }

// At DLAA the marker texel is an image pixel (FinalCombine keeps its colour, the code goes in alpha).
bool rrMarkerInImage() { return all(rrMarkerPos() < uint2(g_view.renderResolution)); }

// ---- RR mode -------------------------------------------------------------------------------
// RR mode for this frame: 0 = off, 1 or 2 = packed guides of that version in outputBufferFinal,
// 3 = guides in RTXBoost's atlas. The same answer in every pass of the frame.
uint rrMode()
{
#if ENABLE_RAY_RECONSTRUCTION
    if (!rrDlssFrame()) return 0u;
    float4 carried = inputIncidentLight[kRRAckSlot];
    if (carried.x != kRRAck || carried.y != float((g_view.frameCount - 1u) & 65535u)) return 0u;
    uint version = uint(carried.z);
    if (version == 3u) return 3u;
    // A packed layout is only used while it still fits this frame's size.
    return version != 0u && version == rrPackedVersion() ? version : 0u;
#else
    return 0u;
#endif
}

// The tonemapper's exposure (ToneCurve.hlsl stores its EV in outputBufferToneCurve[3]).
float rrExposure()
{
    float exposureEV = outputBufferToneCurve[uint2(3, 0)];
    return exp2(isfinite(exposureEV) ? clamp(exposureEV, EXPOSURE_MIN, EXPOSURE_MAX) : 0.0f);
}

float rrMarkerCode(uint mode)
{
    return kRRMarker3 + (mode == 3u ? 1.0f : mode != 0u ? 2.0f : 0.0f);
}

// FinalCombine, one thread: the marker for RTXBoost (unless it is an image pixel, see
// rrMarkerInImage), and this frame's RR state and exposure for CopyToFinal (which cannot read
// the ack slot: it rewrites it).
void rrBeginFrame(uint mode)
{
#if ENABLE_RAY_RECONSTRUCTION
    if (!rrDlssFrame()) return;
    if (!rrMarkerInImage())
    {
        uint packed = rrPackedVersion();
        outputBufferFinal[rrMarkerPos()] = packed != 0u
            ? float4(kRRMarker, float(packed), mode != 0u ? 1.0f : 0.0f, rrMarkerCode(mode))
            : float4(0.0f, 0.0f, 0.0f, rrMarkerCode(mode));
    }
    bufferIncidentLight[kRRFrameSlot] = float4(mode != 0u ? 1.0f : 0.0f, rrExposure(), float(g_view.frameCount & 65535u), float(mode));
#endif
}

// FinalCombine, the marker pixel at DLAA: its alpha carries the code.
float rrMarkerAlpha(uint2 pixel, uint mode, float alpha)
{
#if ENABLE_RAY_RECONSTRUCTION
    if (rrDlssFrame() && rrMarkerInImage() && all(pixel == rrMarkerPos())) return rrMarkerCode(mode);
#endif
    return alpha;
}

// FinalCombine, RR mode: the colour DLSS RR gets (pre-exposed, kept inside the fp16 range).
float3 rrPreExpose(float3 color)
{
    return min(color * rrExposure(), 65000.0f);
}

// CopyToFinal, on the DLSS output: takes the pre-exposure out again in RR frames.
float3 rrRemovePreExposure(float3 color)
{
#if ENABLE_RAY_RECONSTRUCTION
    float4 frame = bufferIncidentLight[kRRFrameSlot];
    if (frame.x == 1.0f && frame.z == float(g_view.frameCount & 65535u) && frame.y > 0.0f)
        return color / frame.y;
#endif
    return color;
}

// FinalCombine must not overwrite the marker (outside the image) or, in packed RR modes, the guides.
// The marker texel outside the image is never part of the picture, so it is always kept.
bool rrIsReservedTexel(uint2 pixel, uint mode)
{
#if ENABLE_RAY_RECONSTRUCTION
    if (all(pixel == rrMarkerPos()) && !rrMarkerInImage()) return true;
    if (!rrDlssFrame()) return false;
    uint2 r = uint2(g_view.renderResolution);
    uint2 d = uint2(g_view.displayResolution);
    if (mode == 1u) return pixel.x >= r.x && pixel.x < 2u * r.x && pixel.y < r.y;
    if (mode == 2u) return rrV2IsGuideTexel(pixel.x, pixel.y, r.x, r.y, d.x, d.y);
#endif
    return false;
}

// CopyToFinal, before it writes this pixel: carry RTXBoost's ack into the next frame.
// Slot: (ack, frame stamp, version, 0).
void rrCarryAck(uint2 displayPixel)
{
#if ENABLE_RAY_RECONSTRUCTION
    if (any(displayPixel != rrAckPos())) return;
    float4 ack = outputBufferFinal[displayPixel];
    bool ok = rrDlssFrame() && ack.x == kRRAck &&
        (ack.y == 3.0f || (ack.y >= 1.0f && ack.y == float(rrPackedVersion())));
    bufferIncidentLight[kRRAckSlot] = float4(ok ? kRRAck : 0.0f, float(g_view.frameCount & 65535u), ok ? ack.y : 0.0f, 0.0f);
#endif
}

// ---- packed guides (versions 1 and 2) -------------------------------------------------------
// Each 16-bit float carries an integer v < 61440 as an exact bit pattern (no zero,
// denormal, Inf or NaN pattern), so it survives the fp32 -> fp16 store unchanged.
// RTXBoost's unpack shader inverts it bit for bit.
float rrEncode(uint v)
{
    v = min(v, 61439u);
    uint s = v / 30720u;
    uint r = v - s * 30720u;
    return f16tof32((s << 15) | ((r / 1024u + 1u) << 10) | (r % 1024u));
}

uint rrQuantize(float x, uint levels) { return (uint)round(saturate(x) * float(levels - 1u)); }

float2 rrOctEncode(float3 n)
{
    n /= abs(n.x) + abs(n.y) + abs(n.z);
    float2 signs = float2(n.x >= 0.0f ? 1.0f : -1.0f, n.y >= 0.0f ? 1.0f : -1.0f);
    return n.z >= 0.0f ? n.xy : (1.0f - abs(n.yx)) * signs;
}

// Layout (bits):  x: octX 11 | roughHi 4    y: octY 11 | roughLo 3 | diffGLo 1
//                 z: diffR 8 | diffGHi 7    w: diffB 8 | specLum 7
// Albedos are stored as sqrt (perceptual steps), the specular albedo as luminance.
float4 rrPackGuide(float3 normal, float roughness, float3 diffuseAlbedo, float3 specularAlbedo)
{
    float2 oct = rrOctEncode(normalize(normal)) * 0.5f + 0.5f;
    uint ox = rrQuantize(oct.x, 2048u);
    uint oy = rrQuantize(oct.y, 2048u);
    uint r = rrQuantize(roughness, 128u);
    float3 d = sqrt(saturate(diffuseAlbedo));
    uint dr = rrQuantize(d.r, 256u), dg = rrQuantize(d.g, 256u), db = rrQuantize(d.b, 256u);
    uint sl = rrQuantize(sqrt(saturate(dot(specularAlbedo, float3(0.2126f, 0.7152f, 0.0722f)))), 128u);
    return float4(
        rrEncode(ox * 16u + (r >> 3)),
        rrEncode((oy * 8u + (r & 7u)) * 2u + (dg & 1u)),
        rrEncode(dr * 128u + (dg >> 1)),
        rrEncode(db * 128u + sl));
}

// ---- guides of the pixel ----------------------------------------------------------------------
// Directional albedo of the specular lobe (Karis' analytic fit of the split-sum LUT).
float3 rrSpecularAlbedo(float3 F0, float roughness, float NdotV)
{
    const float4 c0 = float4(-1.0f, -0.0275f, -0.572f, 0.022f);
    const float4 c1 = float4(1.0f, 0.0425f, 1.04f, -0.04f);
    float4 r = roughness * c0 + c1;
    float a004 = min(r.x * r.x, exp2(-9.28f * NdotV)) * r.x + r.y;
    float2 AB = float2(-1.04f, 1.04f) * a004 + r.zw;
    return F0 * AB.x + AB.y;
}

// What the primary ray pass found for this pixel. The ray generation pass resets it, RenderRay /
// RenderVanilla fill it in, rrEndPixel writes it out. Sky (no surface): RR's own defaults.
static uint g_rrMode = 0u;
static bool g_rrActive = false;
static uint2 g_rrPixel = 0;
static bool g_rrSurface = false;
static float3 g_rrNormal = float3(0, 1, 0);
static float g_rrRoughness = 1.0f;
static float3 g_rrDiffuseAlbedo = 0.0f;
static float3 g_rrSpecularAlbedo = 0.0f;
static float g_rrHitDistance = kRRFar;
static uint g_rrHitBounce = 1u;           // path segment whose length starts the specular hit distance
static bool g_rrHitChainOpen = false;     // the hit distance still follows mirror-like bounces
static bool g_rrReplaced = false;         // the guides describe a surface seen in a mirror (RR_PSR)
static float g_rrReplacedDistance = 0.0f; // mirror to that surface, as seen along the primary ray
static float3 g_rrReplacedMotion = 0.0f;  // that surface's motion (position - previous position)
// RR_DIFFUSE_HITDIST: the surface whose diffuse albedo the guides carry (the primary surface, the
// surface seen in a mirror, or the solid surface behind water and glass) and its diffuse bounce.
static float3 g_rrDiffusePoint = 0.0f;
static float3 g_rrDiffuseNormal = float3(0, 1, 0);     // shading normal, facing the ray that found it
static float3 g_rrDiffuseGeomNormal = float3(0, 1, 0);
static float g_rrDiffuseHitDistance = -1.0f;          // < 0: no diffuse bounce off that surface (yet)
static bool g_rrDiffuseNext = false;                   // the last vertex was that surface, diffuse lobe

// Ray generation, before RenderRay.
void rrBeginPixel(uint2 pixel)
{
#if ENABLE_RAY_RECONSTRUCTION
    g_rrMode = rrMode();
    g_rrActive = g_rrMode != 0u;
    g_rrPixel = pixel;
    g_rrSurface = false;
    g_rrNormal = float3(0, 1, 0);
    g_rrRoughness = 1.0f;
    g_rrDiffuseAlbedo = 0.0f;
    g_rrSpecularAlbedo = 0.0f;
    g_rrHitDistance = kRRFar;
    g_rrHitBounce = 1u;
    g_rrHitChainOpen = false;
    g_rrReplaced = false;
    g_rrReplacedDistance = 0.0f;
    g_rrReplacedMotion = 0.0f;
    g_rrDiffusePoint = 0.0f;
    g_rrDiffuseNormal = float3(0, 1, 0);
    g_rrDiffuseGeomNormal = float3(0, 1, 0);
    g_rrDiffuseHitDistance = -1.0f;
    g_rrDiffuseNext = false;
#endif
}

// The surface whose diffuse albedo the guides carry (RR_DIFFUSE_HITDIST measures its diffuse bounce).
void rrSetDiffuseSurface(float3 position, float3 N, float3 ng)
{
    g_rrDiffusePoint = position;
    g_rrDiffuseNormal = N;
    g_rrDiffuseGeomNormal = ng;
}

// RenderRay, every segment of the path: the specular hit distance, which RR uses with the camera
// matrices to move reflections with the camera. It is the length of the segment leaving the surface
// the guides describe (the primary surface, or the surface seen in a mirror with RR_PSR). With
// RR_SPEC_CHAIN_HITDIST it goes on along mirror-like bounces (see rrNoteBounceLobe): a glossy floor
// reflecting a window shows what is behind the window, so that is where its reflection must move to.
// Only metals and glossy surfaces have a large specular albedo, and their bounce is nearly always the
// specular one, so the other lobes' distances do little harm.
void rrNoteBounceDistance(int bounce, bool hitSurface, float distance)
{
#if ENABLE_RAY_RECONSTRUCTION
    if (!g_rrActive || !g_rrSurface) return;
#if RR_DIFFUSE_HITDIST
    if (g_rrDiffuseNext)
    {
        g_rrDiffuseHitDistance = hitSurface && isfinite(distance) ? clamp(distance, 0.0f, kRRFar) : kRRFar;
        g_rrDiffuseNext = false;
    }
#endif
    uint segment = uint(bounce);
    bool first = segment == g_rrHitBounce;
    if (!first && !(g_rrHitChainOpen && segment > g_rrHitBounce)) return;
    if (!hitSurface || !isfinite(distance))
    {
        g_rrHitDistance = kRRFar;
        g_rrHitChainOpen = false;
        return;
    }
    g_rrHitDistance = clamp((first ? 0.0f : g_rrHitDistance) + distance, 0.0f, kRRFar);
    g_rrHitChainOpen = RR_SPEC_CHAIN_HITDIST && segment < g_rrHitBounce + kRRMaxMirrorVertices;
#endif
}

// Two path vertices this close count as the same surface (RR_DIFFUSE_HITDIST). A path through a
// mirror reaches the surface seen in it a little off the guides' mean lobe, so this is not a tight test.
static const float kRRSameSurfaceDistance = 0.25f;

// RenderRay, after each vertex (origin = the vertex, the next ray starts there): a rough lobe ends
// the specular hit distance chain there. With RR_DIFFUSE_HITDIST, a diffuse bounce off the surface
// whose diffuse albedo the guides carry makes the next segment's length the diffuse hit distance. The
// renderer picks one lobe per path, so pixels whose path went another way this frame get a probe ray
// instead (rrFinishDiffuseHitDistance). Lobe roughness 1 outside a medium is the diffuse lobe (and GGX
// at roughness 1, which spreads about as wide); subsurface scattering stays inside the block.
void rrNoteBounceLobe(int bounce, float lobeRoughness, float3 origin, bool inMedium)
{
#if ENABLE_RAY_RECONSTRUCTION
    if (uint(bounce) >= g_rrHitBounce && lobeRoughness >= kRRMirrorRoughness) g_rrHitChainOpen = false;
#if RR_DIFFUSE_HITDIST
    g_rrDiffuseNext = g_rrActive && g_rrSurface && g_rrDiffuseHitDistance < 0.0f && lobeRoughness >= 1.0f &&
        !inMedium && distance(origin, g_rrDiffusePoint) < kRRSameSurfaceDistance;
#endif
#endif
}

// Ray generation, after RenderRay: distance along the primary ray and motion of the point whose depth
// and motion vector DLSS gets. On a replaced mirror pixel (RR_PSR) that is the mirror image of the
// surface the guides describe: camera + primary direction * (distance to the mirror + path length
// behind it). That is exact for flat mirrors and close for still water (rrMirrorLobe scales the
// length behind a refraction), and it keeps depth, motion vectors and guides on one surface, so RR
// moves the reflection with the reflected scene rather than with the mirror. The exposure meter keeps
// reading the real distance (outputBufferReprojectedPathLength) to tell sky from terrain.
void rrGuidePoint(inout float distance, inout float3 motion)
{
#if ENABLE_RAY_RECONSTRUCTION
    if (!g_rrActive || !g_rrReplaced) return;
    distance = min(distance + g_rrReplacedDistance, kRRFar);
    motion = g_rrReplacedMotion;
#endif
}

// Ray generation, after RenderRay: writes the guides where RTXBoost reads them.
// rayOrigin + rayDirection * primaryDistance is the point whose depth and motion DLSS gets.
void rrEndPixel(float3 rayOrigin, float3 rayDirection, float primaryDistance)
{
#if ENABLE_RAY_RECONSTRUCTION
    [branch] if (!g_rrActive) return;
    if (g_rrMode != 3u)
    {
        float4 packed = g_rrSurface
            ? rrPackGuide(g_rrNormal, g_rrRoughness, g_rrDiffuseAlbedo, g_rrSpecularAlbedo)
            : rrPackGuide(float3(0, 1, 0), 1.0f, 0.0f, 0.0f);
        outputBufferFinal[rrPackedGuidePos(g_rrPixel, g_rrMode)] = packed;
        return;
    }

    // Version 3: flat guides at full precision. RR's sky convention: no normal, half grey.
    float3 normal = 0.0f;
    float roughness = 1.0f;
    float3 diffuseAlbedo = 0.5f;
    float3 specularAlbedo = 0.0f;
    float hitDistance = kRRFar;
    float diffuseHitDistance = RR_DIFFUSE_HITDIST ? kRRFar : 0.0f;
    if (g_rrSurface && all(isfinite(g_rrNormal)) && dot(g_rrNormal, g_rrNormal) > 0.25f)
    {
        normal = normalize(g_rrNormal);
        roughness = g_rrRoughness;
        diffuseAlbedo = all(isfinite(g_rrDiffuseAlbedo)) ? g_rrDiffuseAlbedo : 0.5f;
        specularAlbedo = all(isfinite(g_rrSpecularAlbedo)) ? g_rrSpecularAlbedo : 0.0f;
        hitDistance = g_rrHitDistance;
#if RR_DIFFUSE_HITDIST
        if (g_rrDiffuseHitDistance >= 0.0f) diffuseHitDistance = g_rrDiffuseHitDistance;
#endif
    }

    // Linear view depth of the point DLSS's depth and motion describe (fog: the surface behind it).
    float viewDepth = kRRFar;
    float2 specularMotion = 0.0f;
    if (primaryDistance < kRRFar && isfinite(primaryDistance))
    {
        float3 position = rayOrigin + rayDirection * primaryDistance;
        float w = mul(float4(position, 1.0f), g_view.viewProj).w;
        if (isfinite(w) && w > 0.0f) viewDepth = min(w, kRRFar);
        // Only used with RTXBoost's rr_spec 2: the reflected point as seen through a flat mirror.
        if (hitDistance < kRRFar)
        {
            float2 motion = computeMotionVector(rayOrigin + rayDirection * (primaryDistance + hitDistance), 0.0f);
            if (all(isfinite(motion)) && all(abs(motion) < 2.0f)) specularMotion = motion;
        }
    }

    uint2 rs = uint2(g_view.renderResolution);
    uint2 p = g_rrPixel;
    rrGuideAtlas[p] = float4(normal, roughness);
    rrGuideAtlas[p + uint2(rs.x, 0u)] = float4(diffuseAlbedo, viewDepth);
    rrGuideAtlas[p + uint2(0u, rs.y)] = float4(specularAlbedo, 0.0f);
    rrGuideAtlas[p + rs] = float4(hitDistance, specularMotion, diffuseHitDistance);
    if (all(p == 0u))
    {
        rrGuideAtlas[uint2(0u, rs.y * 2u)] = float4(kRRMeta, float(g_view.frameCount & 1023u), float(rs.x & 1023u), float(rs.y & 1023u));
#if RR_DIFFUSE_HITDIST
        rrGuideAtlas[uint2(1u, rs.y * 2u)] = float4(kRRFeatures, float(kRRFeatureDiffuseHitDistance), float(g_view.frameCount & 1023u), 0.0f);
#endif
    }
#endif
}

// ---- guides that need the material code (only with Renderer.hlsl) ----------------------------
#ifdef __RENDERER_HLSL__
// RR divides the specular signal by this guide, so it should hold the energy the pack's specular
// lobe really reflects. brdf.hlsl adds Kulla-Conty multiple scattering to the GGX lobe; over the
// hemisphere that term reflects F_ms * (1 - E(NdotV)) on top of the single-scattering albedo.
float3 rrSpecularAlbedoGuide(float3 F0, float roughness, float NdotV)
{
    float3 albedo = rrSpecularAlbedo(F0, roughness, NdotV);
#if RR_SPEC_ALBEDO_MULTISCATTER
    float directionalAlbedo = ApproxDirectionalAlbedo(NdotV, roughness);
    float averageAlbedo = ApproxAverageAlbedo(roughness);
    float3 averageFresnel = F0 + (1.0f - F0) / 21.0f;
    float3 multipleScattering = averageFresnel * averageFresnel * averageAlbedo /
        max(1.0f - averageFresnel * (1.0f - averageAlbedo), 1e-5f);
    albedo += multipleScattering * (1.0f - directionalAlbedo);
#endif
    return albedo;
}

// RenderVanilla, primary hit only. roughness is the perceptual (texture) roughness.
void rrWritePrimarySurfaceGuide(float3 position, float3 ng, float3 N, float3 V, float roughness, float3 albedo, float metalness, float3 F0)
{
#if ENABLE_RAY_RECONSTRUCTION
    [branch] if (!g_rrActive) return;
    g_rrSurface = true;
    rrSetDiffuseSurface(position, N, ng);
    g_rrNormal = N;
    g_rrRoughness = saturate(roughness);
    g_rrDiffuseAlbedo = saturate(albedo * (1.0f - metalness));
    g_rrSpecularAlbedo = saturate(rrSpecularAlbedoGuide(F0, roughness, saturate(dot(N, V))));
#endif
}

// ---- primary surface replacement (RR_PSR) ----
// A mirror pixel shows another surface, scaled by the mirror's colour. With the mirror's own guides
// (flat normal, plain albedo) RR cannot tell the texture and edges of the reflected scene from noise
// and smears them. So the pixel gets the guides of the first rough surface along the mirror's
// dominant lobe, with the mirror's colour folded into the albedos and the mirror's other lobes added
// (RR's demodulation then still matches the pixel's energy), and depth and motion of its mirror image
// (rrGuidePoint).

struct RRMirrorLobe
{
    float3 direction;  // mean direction of the lobe
    float3 weight;     // share of the light the lobe carries
    float lengthScale; // path length behind the vertex -> apparent distance along the incoming ray
    bool reflected;
    bool crossesWater;
    // What the vertex's other lobes reflect, as albedo: the path still samples them (a water pixel
    // shows the reflection in a fraction F of the frames), and guides that leave them out make RR take
    // that light for noise.
    float3 otherDiffuse;
    float3 otherSpecular;
};

// Relative index of refraction across water or glass, as RenderVanilla uses it.
float rrInterfaceEta(bool isWater, bool frontFacing, bool inWater, float waterIOR)
{
    return isWater ? (inWater ? waterIOR : 1.0f / waterIOR) : (frontFacing ? 1.0f / 1.5f : 1.5f);
}

// The dominant lobe of a surface, if it is a mirror-like one: a reflection, or the refraction into
// still water. False for rough surfaces and where the surface's diffuse colour outweighs the mirror
// lobe. Mean directions only, so guides built from it do not flicker.
bool rrMirrorLobe(uint materialType, SurfaceInfo surface, float3 N, float3 V, float eta, out RRMirrorLobe lobe)
{
    lobe.direction = reflect(-V, N);
    lobe.weight = 0.0f;
    lobe.lengthScale = 1.0f;
    lobe.reflected = true;
    lobe.crossesWater = false;
    lobe.otherDiffuse = 0.0f;
    lobe.otherSpecular = 0.0f;
    if (surface.roughness >= kRRMirrorRoughness) return false;

    float NdotV = saturate(dot(N, V));
    bool isWater = materialType == MATERIAL_TYPE_WATER;
    bool isClear = isWater || (materialType == MATERIAL_TYPE_ALPHA_BLEND && surface.alpha < 0.9999f);
    if (!isClear)
    {
        float3 specular = rrSpecularAlbedoGuide(surface.F0, surface.roughness, NdotV);
        float3 diffuse = surface.color * (1.0f - surface.metalness);
        lobe.weight = specular;
        lobe.otherDiffuse = diffuse;
        return luminance(specular) >= kRRMirrorMinShare * luminance(specular + diffuse);
    }

    // Water and glass split the light three ways, as RenderVanilla does: reflection F, transmission
    // (1 - F)(1 - opacity) and the surface's own diffuse colour (1 - F) opacity. The largest share wins.
    float cosThetaT;
    float F = DielectricFresnel(NdotV, eta, cosThetaT);
    float opacity = saturate(surface.alpha);
    float transmitted = (1.0f - F) * (1.0f - opacity);
    float diffuse = (1.0f - F) * opacity;
    if (F >= transmitted && F >= diffuse)
    {
        lobe.weight = F;
        // The transmitted share is left out: what lies behind is not traced here, and a guessed albedo
        // for it did not help glass in the tests.
        lobe.otherDiffuse = diffuse * surface.color;
        return true;
    }
    // Looking through glass stays with RR_TRANSPARENT_GUIDES: a pane's own reflection moves with the
    // pane, and with depth and motion of the scene behind it RR would drag that reflection along with
    // the scene and smear the glass whenever the camera moves.
    if (diffuse >= transmitted || !isWater) return false;
    // Water is one interface: the ray bends and the radiance scales by eta^2, as in the renderer. Seen
    // through a flat surface, a point at path length s behind it lies on the incoming ray at s * eta.
    lobe.reflected = false;
    lobe.direction = refract(-V, N, eta);
    lobe.weight = transmitted * eta * eta;
    lobe.otherDiffuse = diffuse * surface.color;
    lobe.otherSpecular = F;
    lobe.lengthScale = eta;
    lobe.crossesWater = true;
    return dot(lobe.direction, lobe.direction) > 1e-6f;
}

// A surface hit by the guide chain, with its normals facing the incoming ray as in RenderVanilla.
struct RRChainHit
{
    uint materialType;
    SurfaceInfo surface;
    float3 ng;
    float3 N;
    float eta;
};

RRChainHit rrLoadChainHit(HitInfo hit, float3 direction, bool inWater)
{
    RRChainHit h;
    ObjectInstance object = objectInstances[hit.objectInstanceIndex];
    GeometryInfo geometry = GetGeometryInfo(hit, object);
    h.surface = MaterialVanilla(hit, geometry, object);
    float waterIOR = 1.333f;
    if (hit.materialType == MATERIAL_TYPE_WATER)
    {
        WaterMaterial water;
        float parallaxHeight;
        water.SetUp(h.surface, geometry, direction, 1, parallaxHeight);
        waterIOR = water.IOR.x;
    }
    if (hit.materialType == MATERIAL_TYPE_OPAQUE || hit.materialType == MATERIAL_TYPE_ALPHA_TEST) h.surface.alpha = 1.0f;
    h.materialType = hit.materialType;
    float3 V = -direction;
    h.ng = dot(geometry.geometryNormal, V) < 0.0f ? -geometry.geometryNormal : geometry.geometryNormal;
    h.N = FixShadingNormal(h.ng, dot(h.surface.normal, V) < 0.0f ? -h.surface.normal : h.surface.normal);
    h.eta = rrInterfaceEta(hit.materialType == MATERIAL_TYPE_WATER, hit.frontFacing, inWater, waterIOR);
    return h;
}

// Reflection about the plane with normal n: maps directions behind a mirror into the mirror image.
float3x3 rrMirrorMatrix(float3 n)
{
    return float3x3(1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f) - 2.0f * float3x3(n.x * n, n.y * n, n.z * n);
}

// RenderVanilla, primary hit: if the surface is mirror-like, follows its dominant lobe up to the
// first rough surface and gives the pixel that surface's guides. Normals are mirrored back through
// every reflection so they belong to the mirror image that depth and motion describe. A chain that
// ends in the sky gets RR's sky convention.
void rrReplacePrimarySurface(uint materialType, SurfaceInfo surface, float3 ng, float3 N, float3 V, float eta, bool inWater)
{
#if ENABLE_RAY_RECONSTRUCTION && RR_PSR
    [branch] if (!g_rrActive) return;
    RRMirrorLobe lobe;
    if (!rrMirrorLobe(materialType, surface, N, V, eta, lobe)) return;

    float3 throughput = 1.0f;
    float3 otherDiffuse = 0.0f, otherSpecular = 0.0f; // the mirrors' other lobes, weighted like their vertex
    float3x3 mirror = float3x3(1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f);
    float apparentLength = 0.0f;
    float lengthScale = 1.0f;
    float3 position = surface.position;
    for (uint vertex = 1u; vertex <= kRRMaxMirrorVertices; ++vertex)
    {
        otherDiffuse += throughput * lobe.otherDiffuse;
        otherSpecular += throughput * lobe.otherSpecular;
        throughput *= lobe.weight;
        if (lobe.reflected) mirror = mul(mirror, rrMirrorMatrix(N));
        if (lobe.crossesWater) inWater = !inWater;
        lengthScale *= lobe.lengthScale;

        RayDesc ray;
        ray.Direction = normalize(lobe.direction);
        ray.Origin = offset_ray(position, lobe.reflected ? ng : -ng);
        ray.TMin = 0.0f;
        ray.TMax = 10000.0f;
        RayQuery<RAY_FLAG_NONE> q;
        q.TraceRayInline(SceneBVH, RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES, 0xff & ~INSTANCE_MASK_SUN_OR_MOON, ray);
        while (q.Proceed())
        {
            if (AlphaTestHitLogic(GetCandidateHitInfo(q)))
                q.CommitNonOpaqueTriangleHit();
        }
        g_rrReplaced = true;
        g_rrHitBounce = 1u + vertex;
        if (q.CommittedStatus() != COMMITTED_TRIANGLE_HIT)
        {
            g_rrSurface = false;
            g_rrReplacedDistance = kRRFar;
            g_rrReplacedMotion = 0.0f;
            return;
        }
        HitInfo hit = GetCommittedHitInfo(q);
        apparentLength += hit.rayT * lengthScale;
        RRChainHit h = rrLoadChainHit(hit, ray.Direction, inWater);
        if (vertex < kRRMaxMirrorVertices && rrMirrorLobe(h.materialType, h.surface, h.N, -ray.Direction, h.eta, lobe))
        {
            position = h.surface.position;
            ng = h.ng;
            N = h.N;
            continue;
        }

        float NdotV = saturate(dot(h.N, -ray.Direction));
        g_rrSurface = true;
        g_rrNormal = mul(mirror, h.N);
        g_rrRoughness = saturate(h.surface.roughness);
        g_rrDiffuseAlbedo = saturate(throughput * h.surface.color * (1.0f - h.surface.metalness) + otherDiffuse);
        g_rrSpecularAlbedo = saturate(throughput * rrSpecularAlbedoGuide(h.surface.F0, h.surface.roughness, NdotV) + otherSpecular);
        g_rrReplacedDistance = apparentLength;
        rrSetDiffuseSurface(h.surface.position, h.N, h.ng);
        // The mirror image moves like the surface, mirrored through every reflection on the way.
        g_rrReplacedMotion = mul(mirror, h.surface.position - h.surface.prevPosition);
        return;
    }
#endif
}

// Ray generation, after RenderRay (RR_DIFFUSE_HITDIST): the diffuse hit distance is meant to keep contact
// shadows and corners, where the diffuse light comes from close by, out of RR's wide blur. The path takes
// one lobe per frame, so when it did not bounce diffusely off the guides' surface, one probe ray with the
// same cosine distribution measures the distance instead (only the hit is needed, no shading). Without a
// diffuse albedo RR has no diffuse signal to filter, so those pixels skip the probe.
void rrFinishDiffuseHitDistance(uint2 pixel)
{
#if ENABLE_RAY_RECONSTRUCTION && RR_DIFFUSE_HITDIST
    [branch] if (!g_rrActive || !g_rrSurface || g_rrDiffuseHitDistance >= 0.0f) return;
    if (luminance(g_rrDiffuseAlbedo) < 1e-3f)
    {
        g_rrDiffuseHitDistance = kRRFar;
        return;
    }
    PathRNG rng;
    rng.state = PCG_Hash(uint3(pixel.x + pixel.y * uint(g_view.renderResolution.x), g_view.frameCount, 0x5DEECE66u));
    RayDesc ray;
    ray.Direction = CosineHemisphereSampling(NextFloat2(rng), g_rrDiffuseNormal);
    // A bumpy shading normal can point the sample under the face: mirror it back above.
    if (dot(ray.Direction, g_rrDiffuseGeomNormal) <= 0.0f) ray.Direction = reflect(ray.Direction, g_rrDiffuseGeomNormal);
    ray.Origin = offset_ray(g_rrDiffusePoint, g_rrDiffuseGeomNormal);
    ray.TMin = 0.0f;
    ray.TMax = 10000.0f;
    RayQuery<RAY_FLAG_NONE> q;
    q.TraceRayInline(SceneBVH, RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES, 0xff & ~INSTANCE_MASK_SUN_OR_MOON, ray);
    while (q.Proceed())
    {
        if (AlphaTestHitLogic(GetCandidateHitInfo(q)))
            q.CommitNonOpaqueTriangleHit();
    }
    g_rrDiffuseHitDistance = q.CommittedStatus() == COMMITTED_TRIANGLE_HIT ? min(q.CommittedRayT(), kRRFar) : kRRFar;
#endif
}

// Describe background geometry without changing the guide for fog radiance.
void rrDescribeFoggedPrimarySurface(HitInfo hitInfo, float3 rayDirection, inout float primaryDistance, inout float3 primaryMotion)
{
    [branch] if (!g_rrActive) return;
    ObjectInstance objectInstance = objectInstances[hitInfo.objectInstanceIndex];
    GeometryInfo geometryInfo = GetGeometryInfo(hitInfo, objectInstance);
    SurfaceInfo surfaceInfo = MaterialVanilla(hitInfo, geometryInfo, objectInstance);
    float parallaxHeight = 0.0f;
    if (hitInfo.materialType == MATERIAL_TYPE_WATER)
    {
        WaterMaterial waterMat;
        waterMat.SetUp(surfaceInfo, geometryInfo, normalize(rayDirection), 0, parallaxHeight);
    }
    primaryDistance = clamp(hitInfo.rayT + parallaxHeight, 0.0f, kRRFar);
    primaryMotion = surfaceInfo.position - surfaceInfo.prevPosition;
}

#if RR_TRANSPARENT_GUIDES
// RenderVanilla, primary hit on water or glass. The pixel shows the reflection (the share F)
// and whatever lies behind the surface (the rest). RR splits the colour by the albedo guides, so
// the diffuse guide gets the albedo of what is seen through the surface: one ray along the mean
// refracted direction finds the first solid surface behind it (other panes and water surfaces
// only tint it). Without it RR takes the scene behind for light on a flat surface and smears it.
// Deterministic (no random numbers), so the guides do not flicker from frame to frame.
void rrWriteTransparentPrimaryGuide(float3 position, float3 ng, float3 N, float3 V, float roughness,
    float3 surfaceColor, float opacity, float eta, bool isWater)
{
#if ENABLE_RAY_RECONSTRUCTION
    [branch] if (!g_rrActive || g_rrReplaced) return;
    float cosThetaT;
    float F = DielectricFresnel(saturate(dot(V, N)), eta, cosThetaT);
    float3 tint = isWater ? 1.0f : GetAlphaBlendTransmissionTint(surfaceColor);
    float3 behindAlbedo = 0.0f;
    bool behindFound = false;
    float3 behindPosition = 0.0f, behindN = 0.0f, behindNg = 0.0f;
    float3 direction = refract(-V, N, eta);
    if (F < 1.0f && dot(direction, direction) > 1e-6f)
    {
        RayDesc ray;
        ray.Direction = normalize(direction);
        ray.Origin = offset_ray(position, -ng);
        ray.TMin = 0.0f;
        ray.TMax = 10000.0f;
        behindAlbedo = 0.5f; // nothing behind (sky): RR's sky convention
        for (int layer = 0; layer < 4; ++layer)
        {
            RayQuery<RAY_FLAG_NONE> q;
            q.TraceRayInline(SceneBVH, RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES, 0xff & ~INSTANCE_MASK_SUN_OR_MOON, ray);
            while (q.Proceed())
            {
                if (AlphaTestHitLogic(GetCandidateHitInfo(q)))
                    q.CommitNonOpaqueTriangleHit();
            }
            if (q.CommittedStatus() != COMMITTED_TRIANGLE_HIT) break;
            HitInfo hit = GetCommittedHitInfo(q);
            ObjectInstance hitObject = objectInstances[hit.objectInstanceIndex];
            GeometryInfo hitGeometry = GetGeometryInfo(hit, hitObject);
            SurfaceInfo hitSurface = MaterialVanilla(hit, hitGeometry, hitObject);
            bool clearLayer = hit.materialType == MATERIAL_TYPE_WATER ||
                (hit.materialType == MATERIAL_TYPE_ALPHA_BLEND && hitSurface.alpha < 0.9999f);
            if (!clearLayer)
            {
                behindAlbedo = hitSurface.color;
                behindFound = true;
                behindPosition = hitSurface.position;
                behindNg = dot(hitGeometry.geometryNormal, ray.Direction) > 0.0f ? -hitGeometry.geometryNormal : hitGeometry.geometryNormal;
                behindN = FixShadingNormal(behindNg, dot(hitSurface.normal, ray.Direction) > 0.0f ? -hitSurface.normal : hitSurface.normal);
                break;
            }
            if (hit.materialType != MATERIAL_TYPE_WATER) tint *= GetAlphaBlendTransmissionTint(hitSurface.color);
            ray.Origin = offset_ray(hitSurface.position, dot(hitGeometry.geometryNormal, ray.Direction) > 0.0f
                ? hitGeometry.geometryNormal : -hitGeometry.geometryNormal);
        }
    }
    // A single water surface scales the radiance by eta^2 (the renderer does the same); a pane's
    // two faces cancel.
    float radianceScale = isWater ? eta * eta : 1.0f;
    opacity = saturate(opacity);
    g_rrSurface = true;
    g_rrNormal = N;
    g_rrRoughness = saturate(roughness);
    float3 ownDiffuse = opacity * surfaceColor;
    float3 behindDiffuse = (1.0f - opacity) * tint * radianceScale * behindAlbedo;
    g_rrDiffuseAlbedo = saturate((1.0f - F) * (ownDiffuse + behindDiffuse));
    g_rrSpecularAlbedo = saturate(F).xxx;
    // The diffuse hit distance belongs to whichever of the two carries more of the diffuse guide.
    if (behindFound && luminance(behindDiffuse) > luminance(ownDiffuse)) rrSetDiffuseSurface(behindPosition, behindN, behindNg);
#endif
}
#endif // RR_TRANSPARENT_GUIDES
#endif // __RENDERER_HLSL__

#endif // __RAY_RECONSTRUCTION_HLSL__