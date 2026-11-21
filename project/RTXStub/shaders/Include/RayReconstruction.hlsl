// DLSS Ray Reconstruction (RR) support for the RTXBoost mod. See RR-SUPPORT.md in the repo root.
//
// The pack never runs RR itself. It only offers it to RTXBoost, which replaces the game's
// DLSS Super Resolution with DLSS RR when its user turns RR on. Without RTXBoost (or with RR
// off, or on a GPU without RR) nothing here changes the image.
//
// Contract with RTXBoost, all inside the guard band of outputBufferFinal (a DISPLAY-size
// texture whose render-size top-left part is the DLSS colour input):
//   marker (W-1, H-1)  FinalCombine, every DLSS frame: (1729, version, rrActive, carried ack)
//   ack    (W-2, H-1)  RTXBoost, after its RR evaluate: (1741, version, history cap, 0).
//                      CopyToFinal overwrites outputBufferFinal right after, so it first
//                      carries the ack into slot kRRAckSlot of the IncidentLight buffer
//                      in a reserved slot, stamped with the frame number. The next frame
//                      is in RR mode only if that stamp is the previous frame's.
//   guides (rw + x, y) for render pixel (x, y): normal, roughness and albedos of the
//                      primary surface, packed bit-exactly into the four 16-bit floats.
// RR mode needs room for the guide rect: 2 * renderWidth <= displayWidth and
// renderHeight < displayHeight, i.e. DLSS Performance or Ultra Performance.
//
// What RR mode changes in this pack:
//   * DLSS RR gets the current filtered sample rather than the progressive accumulation.
//   * The colour is pre-exposed with the pack's auto exposure before DLSS RR and the exposure
//     is taken out again in CopyToFinal: RR denoises best near display brightness, while the
//     pack's raw radiance is up to 64x darker (the exposure is applied in the tonemapper).
//   * Depth and motion can describe the surface behind a primary fog scatter without
//     replacing the fog pixel's color guide with the surface material.

#ifndef __RAY_RECONSTRUCTION_HLSL__
#define __RAY_RECONSTRUCTION_HLSL__

#include "Generated/Signature.hlsl"
#include "Util.hlsl"
#include "settings.hlsl"

static const float kRRMarker = 1729.0f; // exact in fp16 (< 2048)
static const float kRRAck = 1741.0f;
static const float kRRVersion = 1.0f;
static const uint kRRAckSlot = 279;     // IncidentLight slot: RTXBoost's ack, carried to the next frame
static const uint kRRFrameSlot = 278;   // IncidentLight slot: this frame's RR state for CopyToFinal

// DLSS upscaling with room for the guide rect next to the image.
bool rrHandshakeAvailable()
{
    uint2 renderRes = uint2(g_view.renderResolution);
    uint2 displayRes = uint2(g_view.displayResolution);
    return isUpscalingEnabled() && renderRes.x * 2u <= displayRes.x && renderRes.y < displayRes.y;
}

uint2 rrMarkerPos() { return uint2(g_view.displayResolution) - uint2(1, 1); }
uint2 rrAckPos() { return uint2(g_view.displayResolution) - uint2(2, 1); }

// RR mode for this frame: RTXBoost acknowledged the previous frame.
bool rrIsActive()
{
#if ENABLE_RAY_RECONSTRUCTION
    if (!rrHandshakeAvailable()) return false;
    float4 carried = inputIncidentLight[kRRAckSlot];
    return carried.x == kRRAck && carried.y == float((g_view.frameCount - 1u) & 65535u);
#else
    return false;
#endif
}

// The tonemapper's exposure (ToneCurve.hlsl stores its EV in outputBufferToneCurve[3]).
float rrExposure()
{
    float exposureEV = outputBufferToneCurve[uint2(3, 0)];
    return exp2(isfinite(exposureEV) ? clamp(exposureEV, EXPOSURE_MIN, EXPOSURE_MAX) : 0.0f);
}

// FinalCombine, one thread: the marker for RTXBoost, and this frame's RR state and
// exposure for CopyToFinal (which cannot read the ack slot: it rewrites it).
void rrBeginFrame(bool active)
{
#if ENABLE_RAY_RECONSTRUCTION
    if (!rrHandshakeAvailable()) return;
    outputBufferFinal[rrMarkerPos()] = float4(kRRMarker, kRRVersion, active ? 1.0f : 0.0f, inputIncidentLight[kRRAckSlot].x);
    bufferIncidentLight[kRRFrameSlot] = float4(active ? 1.0f : 0.0f, rrExposure(), float(g_view.frameCount & 65535u), 0.0f);
#endif
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

// FinalCombine must not overwrite the marker or, in RR mode, the guide rect.
bool rrIsReservedTexel(uint2 pixel, bool active)
{
#if ENABLE_RAY_RECONSTRUCTION
    if (!rrHandshakeAvailable()) return false;
    uint2 renderRes = uint2(g_view.renderResolution);
    bool inGuideRect = pixel.x >= renderRes.x && pixel.x < 2u * renderRes.x && pixel.y < renderRes.y;
    return all(pixel == rrMarkerPos()) || (active && inGuideRect);
#else
    return false;
#endif
}

// CopyToFinal, before it writes this pixel: carry RTXBoost's ack into the next frame.
void rrCarryAck(uint2 displayPixel)
{
#if ENABLE_RAY_RECONSTRUCTION
    if (any(displayPixel != rrAckPos())) return;
    float4 ack = outputBufferFinal[displayPixel];
    bool ok = rrHandshakeAvailable() && ack.x == kRRAck && ack.y == kRRVersion;
    bufferIncidentLight[kRRAckSlot] = float4(ok ? kRRAck : 0.0f, float(g_view.frameCount & 65535u), ok ? ack.z : 0.0f, 0.0f);
#endif
}

// ---- guides ------------------------------------------------------------------------
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

// The ray generation pass sets these once per pixel; RenderVanilla writes the guide.
static bool g_rrActive = false;
static uint2 g_rrPixel = 0;

void rrWriteGuide(float4 packedGuide)
{
    outputBufferFinal[uint2(g_rrPixel.x + uint(g_view.renderResolution.x), g_rrPixel.y)] = packedGuide;
}

// Ray generation, before RenderRay: sky guide (up normal, rough, black albedos) unless
// the primary ray hits a surface.
void rrBeginPixel(uint2 pixel)
{
#if ENABLE_RAY_RECONSTRUCTION
    g_rrActive = rrIsActive();
    g_rrPixel = pixel;
    if (g_rrActive) rrWriteGuide(rrPackGuide(float3(0, 1, 0), 1.0f, 0.0f, 0.0f));
#endif
}

// RenderVanilla, primary hit only. roughness is the perceptual (texture) roughness.
void rrWritePrimarySurfaceGuide(float3 N, float3 V, float roughness, float3 albedo, float metalness, float3 F0)
{
#if ENABLE_RAY_RECONSTRUCTION
    [branch] if (!g_rrActive) return;
    float3 specularAlbedo = rrSpecularAlbedo(F0, roughness, saturate(dot(N, V)));
    rrWriteGuide(rrPackGuide(N, roughness, albedo * (1.0f - metalness), specularAlbedo));
#endif
}

// ---- primary surface behind fog (needs the material code, so only with Renderer.hlsl) ----
#ifdef __RENDERER_HLSL__
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
    primaryDistance = clamp(hitInfo.rayT + parallaxHeight, 0.0f, 65504.0f);
    primaryMotion = surfaceInfo.position - surfaceInfo.prevPosition;
}
#endif // __RENDERER_HLSL__

#endif // __RAY_RECONSTRUCTION_HLSL__
