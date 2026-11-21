# DLSS Ray Reconstruction (RTXBoost)

EscheridiaRT can hand its noisy path-traced image to DLSS Ray Reconstruction (RR) through the
RTXBoost mod. RTXBoost replaces the game's DLSS Super Resolution with DLSS RR, which denoises and
upscales in one step. The pack itself never runs RR; it only offers it.

## What it does

- Every DLSS frame, FinalCombine writes a marker texel into the unused guard band of
  `outputBufferFinal`, so RTXBoost can see that the pack supports RR.
- When RTXBoost runs RR, it writes an ack back. CopyToFinal carries that ack into the next frame,
  and the next frame switches to RR mode:
  - the primary ray pass writes guides for every pixel next to the image (normal, roughness,
    diffuse albedo, specular albedo of the first surface hit), packed for RTXBoost;
  - FinalCombine hands DLSS RR the current filtered sample rather than the pack's progressive
    accumulation;
  - that colour is pre-exposed with the pack's auto exposure (RR denoises best near display
    brightness) and CopyToFinal takes the exposure out again, so the tonemapper sees the usual values;
  - depth and motion can describe the first surface behind a primary fog scatter without using
    the surface color guide for the fog. Water uses its displaced surface and an approximate
    previous-frame wave position. The fog-scattered pixel retains its default sky guide.
- With no ack (RTXBoost missing, RR off, RR not supported, wrong DLSS mode) the next frame renders
  exactly as before. The only extra work is reading the ack, the marker texel and a one-texel
  ack copy in CopyToFinal. All of it sits in the guard band, outside the image DLSS reads.

Depth and motion vectors are the pack's own (the ones the game already gives DLSS).

## Requirements

- RTXBoost with Ray Reconstruction turned on in its window (F12)
- An NVIDIA RTX GPU and driver that support DLSS RR
- DLSS set to Performance or Ultra Performance (the guides need the space next to the
  render-size image: 2 x render width <= display width)

## Turning it off

Set `#define ENABLE_RAY_RECONSTRUCTION 0` in `project/RTXStub/shaders/Include/settings.HLSL`
and rebuild. That removes all RR code. Turning RR off in RTXBoost also works without a rebuild.

## Files

- `project/RTXStub/shaders/Include/RayReconstruction.hlsl`: everything RR-specific (handshake,
  guide packing, ack carry). The protocol is described at the top of that file.
- `project/RTXStub/shaders/Include/settings.HLSL`: the `ENABLE_RAY_RECONSTRUCTION` switch
- `project/RTXStub/shaders/PrimaryCheckerboardRayGenInline.hlsl`: `rrBeginPixel` before `RenderRay`
- `project/RTXStub/shaders/Include/Renderer.hlsl`: primary-hit guide in `RenderVanilla`, primary
  surface behind fog in `RenderRay`
- `project/RTXStub/shaders/FinalCombine.hlsl`: marker, keeps the guides, pre-exposes the RR input
- `project/RTXStub/shaders/CopyToFinal.hlsl`: carries the ack, removes the pre-exposure

IncidentLight slot 279 carries the ack and slot 278 the frame's RR state and exposure from
FinalCombine to CopyToFinal. Slot 277 stores the previous frame's water time and wave origin for
water motion vectors, independently of RR.

`RR_FOG_DIRECT_SAMPLING` reduces primary air-fog direct-light variance in RR mode by sampling a
scattering point independently of the camera path. It can require an extra shadow ray per pixel;
set it to 0 in `settings.HLSL` to restore the previous sampling. Indirect fog and underwater
scattering are unchanged.

`RR_FOG_BACKGROUND_MOTION` supplies background surface depth and motion for primary fog-scattered
pixels in RR mode without writing the background material guide. Set it to 0 to use the previous
far-depth and sky-motion behavior.


