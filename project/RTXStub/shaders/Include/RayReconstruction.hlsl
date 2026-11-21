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
//   (rw + x, rh + y)  specular hit distance, specular motion vector (uv)
//   (0, 2*rh)         meta: (1907, frame & 1023, rw & 1023, rh & 1023), so RTXBoost can see the
//                     pack really writes its texture
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

#ifndef __RAY_RECONSTRUCTION_HLSL__
#define __RAY_RECONSTRUCTION_HLSL__

#include "Generated/Signature.hlsl"
#include "Util.hlsl"
#include "settings.hlsl"

static const float kRRMarker = 1729.0f; // exact in fp16 (< 2048)
static const float kRRAck = 1741.0f;
static const float kRRMarker3 = 1801.0f; // version 3 code in the marker's .w (+1 RR mode v3, +2 RR mode packed)
static const float kRRMeta = 1907.0f;    // guide atlas meta texel
static const uint kRRAckSlot = 279;      // IncidentLight slot: RTXBoost's ack, carried to the next frame
static const uint kRRFrameSlot = 278;    // IncidentLight slot: this frame's RR state for CopyToFinal
static const float kRRFar = 65504.0f;    // largest fp16: "no surface" depth and hit distance

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
#endif
}

// RenderVanilla, primary hit only. roughness is the perceptual (texture) roughness.
void rrWritePrimarySurfaceGuide(float3 N, float3 V, float roughness, float3 albedo, float metalness, float3 F0)
{
#if ENABLE_RAY_RECONSTRUCTION
    [branch] if (!g_rrActive) return;
    g_rrSurface = true;
    g_rrNormal = N;
    g_rrRoughness = saturate(roughness);
    g_rrDiffuseAlbedo = saturate(albedo * (1.0f - metalness));
    g_rrSpecularAlbedo = saturate(rrSpecularAlbedo(F0, roughness, saturate(dot(N, V))));
#endif
}

// RenderRay, second segment of the path (the bounce off the primary surface): how far the
// reflected (or refracted, or diffusely bounced) ray went. RR uses it with the camera matrices to
// move reflections with the camera. Only metals and glossy surfaces have a large specular albedo,
// and their bounce is nearly always the specular one, so the other lobes' distances do little harm.
void rrNoteBounceDistance(int bounce, bool hitSurface, float distance)
{
#if ENABLE_RAY_RECONSTRUCTION
    if (!g_rrActive || bounce != 1 || !g_rrSurface) return;
    g_rrHitDistance = hitSurface && isfinite(distance) ? clamp(distance, 0.0f, kRRFar) : kRRFar;
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
    if (g_rrSurface && all(isfinite(g_rrNormal)) && dot(g_rrNormal, g_rrNormal) > 0.25f)
    {
        normal = normalize(g_rrNormal);
        roughness = g_rrRoughness;
        diffuseAlbedo = all(isfinite(g_rrDiffuseAlbedo)) ? g_rrDiffuseAlbedo : 0.5f;
        specularAlbedo = all(isfinite(g_rrSpecularAlbedo)) ? g_rrSpecularAlbedo : 0.0f;
        hitDistance = g_rrHitDistance;
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
    rrGuideAtlas[p + rs] = float4(hitDistance, specularMotion, 0.0f);
    if (all(p == 0u))
        rrGuideAtlas[uint2(0u, rs.y * 2u)] = float4(kRRMeta, float(g_view.frameCount & 1023u), float(rs.x & 1023u), float(rs.y & 1023u));
#endif
}

// ---- guides that need the material code (only with Renderer.hlsl) ----------------------------
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
    [branch] if (!g_rrActive) return;
    float cosThetaT;
    float F = DielectricFresnel(saturate(dot(V, N)), eta, cosThetaT);
    float3 tint = isWater ? 1.0f : GetAlphaBlendTransmissionTint(surfaceColor);
    float3 behindAlbedo = 0.0f;
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
    g_rrDiffuseAlbedo = saturate((1.0f - F) * (opacity * surfaceColor + (1.0f - opacity) * tint * radianceScale * behindAlbedo));
    g_rrSpecularAlbedo = saturate(F).xxx;
#endif
}
#endif // RR_TRANSPARENT_GUIDES
#endif // __RENDERER_HLSL__

#endif // __RAY_RECONSTRUCTION_HLSL__
