/*
vec2 ndcCoord = (fragInput.texcoord0 - vec2(0.0,0.0)) * vec2(2.0,2.0);
vec2 offset = ndcCoord * ndcCoord * sign(ndcCoord) * CHROMATIC_ABERRATION_INTENSITY;
float redAberrated = texture2D(s_RasterColor, clamp(fragInput.texcoord0 - offset, 0.0, 1.0)).r;
float greenAberrated = texture2D(s_RasterColor, clamp(fragInput.texcoord0 - offset * 0.785, 0.0, 1.0)).g;
float blueAberrated = texture2D(s_RasterColor, clamp(fragInput.texcoord0 - offset * 0.677, 0.0, 1.0)).b;
fragOutput.Color0.rgb = float3(redAberrated, greenAberrated, blueAberrated);
*/

/*
* Available Macros:
*
* Passes:
* - TONE_MAPPING_PASS (not used)
*/

$input v_texcoord0

#include "../../include/bgfx_shader.sh"
#include "../../include/common.sc"
#include "../../RTXStub/shaders/Include/Settings.hlsl"
// Bloom strength

#define BLOOM_MULTIPLIER 6.5

// Approximate mesopic/scotopic color shift. These gains reduce long-wavelength
// red sensitivity and increase blue sensitivity as scene adaptation gets darker.
#define PURKINJE_RED_GAIN .58
#define PURKINJE_GREEN_GAIN 1.03
#define PURKINJE_BLUE_GAIN 1.18
#define PURKINJE_DESATURATION .35
#define PURKINJE_DARK_START_EXPOSURE_EV 2.5
#define PURKINJE_DARK_END_EXPOSURE_EV 4.

uniform vec4 gToneMappingDebugMode;
uniform vec4 gToneMappingSaturation;
uniform vec4 gToneMappingShadowContrastEnd;
uniform vec4 gToneMappingShadowContrast;
uniform vec4 RenderMode;
uniform vec4 ScreenSize;
uniform vec4 gBloomMultiplier;
uniform vec4 gColorGradingEnabled;
uniform vec4 gPerformSRGBConversion;
uniform vec4 gToneMappingColorBalance;
uniform vec4 gToneMappingContrast;
uniform vec4 gToneMappingFilmicSaturationCorrection;
uniform vec4 gToneMappingGamma;
uniform vec4 gToneMappingIntensity;
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

struct FragmentInput{
    vec2 texcoord0;
};

struct FragmentOutput{
    vec4 Color0;
};

SAMPLER2D_AUTOREG(s_RasterColor);
SAMPLER2D_AUTOREG(s_gBloomBuffer);
SAMPLER2D_AUTOREG(s_gRasterizedInput);
SAMPLER2D_AUTOREG(s_gToneCurve);// LUT from histogram based tonemapper

void Frag(FragmentInput fragInput,inout FragmentOutput fragOutput){
    const mat3 matrix_rec709_to_xyz=transpose(mat3(.412390917540,.357584357262,.180480793118,.212639078498,.715168714523,.072192311287,.019330825657,.119194783270,.950532138348));
    const mat3 matrix_xyz_to_p3d65=transpose(mat3(2.49349691194,-.931383617919,-.402710784451,-.829488969562,1.76266406032,.023624685842,.035845830244,-.076172389268,.956884524008));
    const mat3 matrix_xyz_to_rec2020=transpose(mat3(1.71665118797,-.355670783776,-.253366281374,-.666684351832,1.61648123664,.015768545814,.017639857445,-.042770613258,.942103121235));
    vec3 hdr=texture2D(s_RasterColor,fragInput.texcoord0).rgb;
    float weather=texture2D(s_RasterColor,ivec2(0.,0.)).a;
    
    float bloomRainIntensity=lerp(1.,RAIN_BLOOM_BOOST,weather);
    float exposureEV=texture2D(s_gToneCurve,vec2(3.5/256.,.5)).r;
    float exposure=exp2(exposureEV);
    
    // hdr = vhsFilter(fragInput.texcoord0, s_RasterColor, time,u_viewRect.zw );
    vec4 raster=texture2D(s_gRasterizedInput,fragInput.texcoord0);
    //raster.rgb = linearToSRGB(ACESFittedTonemap(raster.rgb));
    vec3 bloom=upscaleBloomFiltered(fragInput.texcoord0,s_gBloomBuffer,ScreenSize.xy);
    
    hdr=(hdr+BLOOM_MULTIPLIER*bloomRainIntensity*gBloomMultiplier.x*bloom);
    
    hdr*=exposure;
    
    // Large positive exposure compensation indicates a globally dark scene.
    // Using the smoothed global exposure avoids triggering the shift just
    // because the camera looks into an ordinary local shadow.
    float darkAdapt=smoothstep(
        PURKINJE_DARK_START_EXPOSURE_EV,
        PURKINJE_DARK_END_EXPOSURE_EV,
    exposureEV);
    
    float originalLuminance=dot(hdr,vec3(.2126,.7152,.0722));
    vec3 shifted=hdr*vec3(
        PURKINJE_RED_GAIN,
        PURKINJE_GREEN_GAIN,
    PURKINJE_BLUE_GAIN);
    float shiftedLuminance=dot(shifted,vec3(.2126,.7152,.0722));
    
    // Preserve luminance while changing chromatic response, then reduce
    // saturation slightly as the estimate moves toward scotopic vision.
    shifted*=originalLuminance/max(shiftedLuminance,1e-5);
    shifted=mix(
        vec3(originalLuminance.xxx),
        shifted,
    1.-PURKINJE_DESATURATION*darkAdapt);
   
    
    #if DISABLE_RASTER_OBJECTS==1
    hdr=tonemapAgX(hdr);
    hdr=linearToSRGB(hdr);
    #else
    hdr=ACESFittedTonemap(hdr);
    hdr=linearToSRGB(hdr);
    hdr=mix(hdr,raster.rgb,raster.a);
    #endif

    vec3 outputColorSRGB=hdr;
    fragOutput.Color0.rgb=outputColorSRGB;
}

void main(){
    FragmentInput fragmentInput;
    FragmentOutput fragmentOutput;
    fragmentInput.texcoord0=v_texcoord0;
    fragmentOutput.Color0=vec4(0,0,0,0);
    ViewRect=u_viewRect;
    Proj=u_proj;
    View=u_view;
    ViewTexel=u_viewTexel;
    InvView=u_invView;
    InvProj=u_invProj;
    ViewProj=u_viewProj;
    InvViewProj=u_invViewProj;
    PrevViewProj=u_prevViewProj;
    {
        WorldArray[0]=u_model[0];
        WorldArray[1]=u_model[1];
        WorldArray[2]=u_model[2];
        WorldArray[3]=u_model[3];
    }
    World=u_model[0];
    WorldView=u_modelView;
    WorldViewProj=u_modelViewProj;
    PrevWorldPosOffset=u_prevWorldPosOffset;
    AlphaRef4=u_alphaRef4;
    AlphaRef=u_alphaRef4.x;
    Frag(fragmentInput,fragmentOutput);
    gl_FragColor=fragmentOutput.Color0;
}
