$input v_texcoord0

#include "../../include/bgfx_shader.sh"

/*
Macros:
TONE_MAPPING_PASS
*/

uniform vec4 RenderMode;
uniform vec4 ScreenSize;
uniform vec4 gBloomMultiplier;
uniform vec4 gColorGradingEnabled;
uniform vec4 gPerformSRGBConversion;
uniform vec4 gToneMappingColorBalance;
uniform vec4 gToneMappingContrast;
uniform vec4 gToneMappingDebugMode;
uniform vec4 gToneMappingFilmicSaturationCorrection;
uniform vec4 gToneMappingGamma;
uniform vec4 gToneMappingIntensity;
uniform vec4 gToneMappingSaturation;
uniform vec4 gToneMappingShadowContrast;
uniform vec4 gToneMappingShadowContrastEnd;

vec4 ViewRect;
mat4 Proj;
mat4 View;
vec4 ViewTexel;
mat4 InvView;
mat4 InvProj;
mat4 ViewProj;
mat4 InvViewProj;
mat4 PrevViewProj;
mat4 WorldArray[4];
mat4 World;
mat4 WorldView;
mat4 WorldViewProj;
vec4 PrevWorldPosOffset;
vec4 AlphaRef4;
float AlphaRef;

struct FragmentInput {
    vec2 texcoord0;
};

struct FragmentOutput {
    vec4 Color0;
};

SAMPLER2D_AUTOREG(s_RasterColor);
SAMPLER2D_AUTOREG(s_gBloomBuffer);
SAMPLER2D_AUTOREG(s_gRasterizedInput);
SAMPLER2D_AUTOREG(s_gToneCurve);

void Frag(FragmentInput fragInput, inout FragmentOutput fragOutput) {
    vec4 raster = texture2D(s_gRasterizedInput, fragInput.texcoord0);
    vec3 color = texture2D(s_RasterColor, fragInput.texcoord0).rgb;
    color = color * (1.0 - raster.a) + raster.rgb; // Premultiplied blending
    fragOutput.Color0.rgb = color;
}

void main() {
    FragmentInput fragmentInput;
    FragmentOutput fragmentOutput;
    fragmentInput.texcoord0 = v_texcoord0;
    fragmentOutput.Color0 = vec4(0, 0, 0, 0);
    ViewRect = u_viewRect;
    Proj = u_proj;
    View = u_view;
    ViewTexel = u_viewTexel;
    InvView = u_invView;
    InvProj = u_invProj;
    ViewProj = u_viewProj;
    InvViewProj = u_invViewProj;
    PrevViewProj = u_prevViewProj;
    {
        WorldArray[0] = u_model[0];
        WorldArray[1] = u_model[1];
        WorldArray[2] = u_model[2];
        WorldArray[3] = u_model[3];
    }
    World = u_model[0];
    WorldView = u_modelView;
    WorldViewProj = u_modelViewProj;
    PrevWorldPosOffset = u_prevWorldPosOffset;
    AlphaRef4 = u_alphaRef4;
    AlphaRef = u_alphaRef4.x;
    Frag(fragmentInput, fragmentOutput);
    gl_FragColor = fragmentOutput.Color0;
}

