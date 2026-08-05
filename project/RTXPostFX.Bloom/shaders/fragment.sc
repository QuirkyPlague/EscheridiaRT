/*
* Available Macros:
*
* Passes:
* - BLOOM_DOWNSCALE_GAUSSIAN_PASS
* - BLOOM_DOWNSCALE_UNIFORM_PASS
* - BLOOM_FINAL_PASS
* - BLOOM_UPSCALE_PASS
*/

$input v_texcoord0

#include "../../include/bgfx_shader.sh"
#include "../../include/common.sc"

uniform vec4 RenderMode;
uniform vec4 ScreenSize;
uniform vec4 gBloomMultiplier;
uniform vec4 gViewportScale;
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

SAMPLER2D_AUTOREG(s_RasterColor); // Previous mip level.
SAMPLER2D_AUTOREG(s_gBloomOriginalInput); // Full-scale original input.

// MCRTX bloom pipeline passes:

// - BloomDownscaleUniformPass

// - BloomDownscaleGaussianPass
// - BloomDownscaleGaussianPass
// - BloomDownscaleGaussianPass
// - BloomDownscaleGaussianPass

// - BloomUpscalePass
// - BloomUpscalePass
// - BloomUpscalePass
// - BloomUpscalePass

// TonemapPass does the final upscaling

// Note: BloomFinalPass is not used in the game

// Bloom implementation is based on: https://learnopengl.com/Guest-Articles/2022/Phys.-Based-Bloom
vec3 downscaleBloomFiltered(vec2 texCoord) {
    vec2 inputTexelSize = 1.0 / textureSize(s_RasterColor, 0);
    float x = inputTexelSize.x;
    float y = inputTexelSize.y;
    
    // Take 13 samples around current texel:
    // a - b - c
    // - j - k -
    // d - e - f
    // - l - m -
    // g - h - i
    // === ('e' is the current texel) ===
    vec3 a = texture2D(s_RasterColor, vec2(texCoord.x - 2*x, texCoord.y + 2*y)).rgb;
    vec3 b = texture2D(s_RasterColor, vec2(texCoord.x, texCoord.y + 2*y)).rgb;
    vec3 c = texture2D(s_RasterColor, vec2(texCoord.x + 2*x, texCoord.y + 2*y)).rgb;
    
    vec3 d = texture2D(s_RasterColor, vec2(texCoord.x - 2*x, texCoord.y)).rgb;
    vec3 e = texture2D(s_RasterColor, vec2(texCoord.x, texCoord.y)).rgb;
    vec3 f = texture2D(s_RasterColor, vec2(texCoord.x + 2*x, texCoord.y)).rgb;
    
    vec3 g = texture2D(s_RasterColor, vec2(texCoord.x - 2*x, texCoord.y - 2*y)).rgb;
    vec3 h = texture2D(s_RasterColor, vec2(texCoord.x, texCoord.y - 2*y)).rgb;
    vec3 i = texture2D(s_RasterColor, vec2(texCoord.x + 2*x, texCoord.y - 2*y)).rgb;
    
    vec3 j = texture2D(s_RasterColor, vec2(texCoord.x - x, texCoord.y + y)).rgb;
    vec3 k = texture2D(s_RasterColor, vec2(texCoord.x + x, texCoord.y + y)).rgb;
    vec3 l = texture2D(s_RasterColor, vec2(texCoord.x - x, texCoord.y - y)).rgb;
    vec3 m = texture2D(s_RasterColor, vec2(texCoord.x + x, texCoord.y - y)).rgb;
    
    // Apply Karis average on each block of 4 samples during the first downsample (uniform pass).
    #ifdef BLOOM_DOWNSCALE_UNIFORM_PASS
    // We are writing to mip 0, so we need to apply Karis average to each block
    // of 4 samples to prevent fireflies (very bright subpixels, leads to pulsating
    // artifacts).
    vec3 groups[5];
    groups[0] = (a + b+d + e) * (0.125f / 4.0f);
    groups[1] = (b + c+e + f) * (0.125f / 4.0f);
    groups[2] = (d + e+g + h) * (0.125f / 4.0f);
    groups[3] = (e + f+h + i) * (0.125f / 4.0f);
    groups[4] = (j + k+l + m) * (0.5f / 4.0f);
    groups[0] *= KarisAverage(groups[0]);
    groups[1] *= KarisAverage(groups[1]);
    groups[2] *= KarisAverage(groups[2]);
    groups[3] *= KarisAverage(groups[3]);
    groups[4] *= KarisAverage(groups[4]);
    vec3 downsample = groups[0] + groups[1] + groups[2] + groups[3] + groups[4];
    
    #else
    
    // Apply weighted distribution:
    // 0.5 + 0.125 + 0.125 + 0.125 + 0.125 = 1
    // a,b,d,e * 0.125
    // b,c,e,f * 0.125
    // d,e,g,h * 0.125
    // e,f,h,i * 0.125
    // j,k,l,m * 0.5
    // This shows 5 square areas that are being sampled. But some of them overlap,
    // so to have an energy preserving downsample we need to make some adjustments.
    // The weights are the distributed, so that the sum of j,k,l,m (e.g.)
    // contribute 0.5 to the final color output. The code below is written
    // to effectively yield this sum. We get:
    // 0.125*5 + 0.03125*4 + 0.0625*4 = 1
    vec3 downsample = e*0.125;
    downsample += (a + c+g + i) * 0.03125;
    downsample += (b + d+f + h) * 0.0625;
    downsample += (j + k+l + m) * 0.125;
    #endif
    return downsample;
}

void Frag(FragmentInput fragInput, inout FragmentOutput fragOutput) {
    // BloomFinalPass is not used in MCRTX
    #ifndef BLOOM_FINAL_PASS
    
    #ifdef BLOOM_UPSCALE_PASS
    vec2 windowRes = textureSize(s_gBloomOriginalInput, 0); // Game output window resolution.
    vec3 hdr = upscaleBloomFiltered(fragInput.texcoord0, s_RasterColor, windowRes);
    #else // BLOOM_DOWNSCALE_UNIFORM_PASS or BLOOM_DOWNSCALE_GAUSSIAN_PASS
    vec3 hdr = downscaleBloomFiltered(fragInput.texcoord0);
    #endif
    
    fragOutput.Color0.rgb = hdr;
    #endif // BLOOM_FINAL_PASS
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

