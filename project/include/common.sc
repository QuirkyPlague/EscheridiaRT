#include "../../RTXStub/shaders/Include/Settings.hlsl"

float luminance(vec3 clr){return dot(clr,vec3(.2126,.7152,.0722));}

// https://en.wikipedia.org/wiki/SRGB#From_CIE_XYZ_to_sRGB
vec3 linearToSRGB(vec3 c){
    // Full linear to sRGB function
    //return max(mix(12.92*c,1.055*pow(c,1./2.4)-.055,greaterThan(c,.0031308)),0);
    
    // Approximation
    return max(pow(c, 1.0 / 2.2), 0);
}

// Bloom implementation is based on: https://learnopengl.com/Guest-Articles/2022/Phys.-Based-Bloom
float KarisAverage(vec3 col){
    // Formula is 1 / (1 + luma)
    // luma = luminance(gamma_correct(hdr))
    float luma=luminance(linearToSRGB(col))*.25;
    return 1./(1.+luma);
}
vec3 upscaleBloomFiltered(vec2 texCoord,mediump sampler2D _sampler,vec2 windowRes){
    // The filter kernel is applied with a radius, specified in pixels
    // of the final game window output.
    const float filterSize=12.;
    vec2 filterOffset=filterSize/windowRes;
    
    float x=filterOffset.x;
    float y=filterOffset.y;
    
    // Take 9 samples around current texel:
    // a - b - c
    // d - e - f
    // g - h - i
    // === ('e' is the current texel) ===
    vec3 a=texture2D(_sampler,vec2(texCoord.x-x,texCoord.y+y)).rgb;
    vec3 b=texture2D(_sampler,vec2(texCoord.x,texCoord.y+y)).rgb;
    vec3 c=texture2D(_sampler,vec2(texCoord.x+x,texCoord.y+y)).rgb;
    
    vec3 d=texture2D(_sampler,vec2(texCoord.x-x,texCoord.y)).rgb;
    vec3 e=texture2D(_sampler,vec2(texCoord.x,texCoord.y)).rgb;
    vec3 f=texture2D(_sampler,vec2(texCoord.x+x,texCoord.y)).rgb;
    
    vec3 g=texture2D(_sampler,vec2(texCoord.x-x,texCoord.y-y)).rgb;
    vec3 h=texture2D(_sampler,vec2(texCoord.x,texCoord.y-y)).rgb;
    vec3 i=texture2D(_sampler,vec2(texCoord.x+x,texCoord.y-y)).rgb;
    
    // Apply weighted distribution, by using a 3x3 tent filter:
    //  1   | 1 2 1 |
    // -- * | 2 4 2 |
    // 16   | 1 2 1 |
    vec3 upsample=e*4.;
    upsample+=(b+d+f+h)*2.;
    upsample+=(a+c+g+i);
    upsample*=1./16.;
    return upsample;
}

// https://github.com/TheRealMJP/BakingLab/blob/master/BakingLab/ACES.hlsl
vec3 RRTAndODTFit(vec3 v){
    vec3 a=v*(v+.0245786)-.000090537;
    vec3 b=v*(.983729*v+.4329510)+.238081;
    return a/b;
}
vec3 ACESFittedTonemap(vec3 rgb){
    const mat3 ACESInputMat=mtxFromCols(
        vec3(.59719,.35458,.04823),
        vec3(.07600,.90834,.01566),
        vec3(.02840,.13383,.83777)
    );
    const mat3 ACESOutputMat=mtxFromCols(
        vec3(1.60475,-.53108,-.07367),
        vec3(-.10208,1.10813,-.00605),
        vec3(-.00327,-.07276,1.07602)
    );
    rgb=mul(rgb,ACESInputMat);
    rgb=RRTAndODTFit(rgb);
    rgb=mul(rgb,ACESOutputMat);
    rgb=clamp(rgb,0.,1.);
    return rgb;
}

vec3 LinearToPQ(vec3 L_in)
{
    const float PQ_MAX_LUMINANCE=10000.;
    const vec3 L=clamp((L_in*HDR_PEAK_LUMINANCE)/PQ_MAX_LUMINANCE,0.,1.);
    
    // PQ constants
    const float m1=2610./16384.;// ≈0.1593
    const float m2=2523./32.;// ≈78.8438
    const float c1=3424./4096.;// ≈0.83594
    const float c2=(2413.*32)/4096;// ≈18.8516
    const float c3=(2392.*32)/4096;// ≈18.6875
    
    vec3 Lm1=pow(L,vec3(m1,m1,m1));
    vec3 num=c1+c2*Lm1;
    vec3 den=1.f+c3*Lm1;
    return pow(num/den,vec3(m2,m2,m2));
}

// 0: Default, 1: Golden, 2: Punchy
#define AGX_LOOK 2

// Mean error^2: 3.6705141e-06
vec3 agxDefaultContrastApprox(vec3 x){
    vec3 x2=x*x;
    vec3 x4=x2*x2;
    
    return 15.5*x4*x2
    -40.14*x4*x
    +31.96*x4
    -6.868*x2*x
    +.4298*x2
    +.1191*x
    -.00232;
}

vec3 agx(vec3 val){
    const mat3 agxMat=mat3(
        .842479062253094,.0784335999999992,.0792237451477643,
        .0423282422610123,.878468636469772,.0791661274605434,
        .0423756549057051,.0784336,.879142973793104
    );
    
    const float minEV=-12.47393;
    const float maxEV=4.026069;
    
    // Match the original HLSL transform order exactly.
    val=mul(agxMat,val);
    
    val=clamp(log2(max(val,vec3(1e-10,1e-10,1e-10))),minEV,maxEV);
    val=(val-minEV)/(maxEV-minEV);
    
    return agxDefaultContrastApprox(val);
}

vec3 agxEotf(vec3 val){
    const mat3 matrix_rec709_to_xyz=transpose(mat3(.412390917540,.357584357262,.180480793118,.212639078498,.715168714523,.072192311287,.019330825657,.119194783270,.950532138348));
    const mat3 matrix_xyz_to_p3d65=transpose(mat3(2.49349691194,-.931383617919,-.402710784451,-.829488969562,1.76266406032,.023624685842,.035845830244,-.076172389268,.956884524008));
    const mat3 matrix_xyz_to_rec2020=transpose(mat3(1.71665118797,-.355670783776,-.253366281374,-.666684351832,1.61648123664,.015768545814,.017639857445,-.042770613258,.942103121235));
    
    const mat3 agxMatInv=mat3(
        1.19687900512017,-.0980208811401368,-.0990297440797205,
        -.0528968517574562,1.15190312990417,-.0989611768448433,
        -.0529716355144438,-.0980434501171241,1.15107367264116
    );
    
    val=mul(agxMatInv,val);
    
    // Remove this conversion if NOT writing to an sRGB framebuffer.
    #if ENABLE_HDR
    val=pow(val,vec3(2.2,2.2,2.2));
    val=mul(mul(val,matrix_rec709_to_xyz),matrix_xyz_to_p3d65);
    #else
    val=pow(val,vec3(2.2,2.2,2.2));
    #endif
    //val = mul(mul(val, matrix_rec709_to_xyz), matrix_xyz_to_rec2020);
    
    return val;
}

vec3 reinhard_jodie(vec3 v){
    float l=luminance(v);
    vec3 tv=v/(1.f+v);
    return(mix(v/(1.f+l),tv,tv));
}

vec3 agxLook(vec3 val){
    vec3 offset=vec3(0.,0.,0.);
    vec3 slope=vec3(1.,1.,1.);
    vec3 power=vec3(1.,1.,1.);
    float sat=1.35;
    
    #if AGX_LOOK==1
    // Golden
    slope=vec3(1.,.95,.9);
    power=vec3(.8,.8,.8);
    sat=.8;
    #elif AGX_LOOK==2
    // Punchy
    power=vec3(1.3,1.3,1.3);
    #endif
    
    val=pow(max(val*slope+offset,vec3(0.,0.,0.)),power);
    
    const vec3 lumaWeights=vec3(.2126,.7152,.0722);
    float luma=dot(val,lumaWeights);
    
    return vec3(luma.xxx)+sat*(val-vec3(luma.xxx));
}

vec3 tonemapAgX(vec3 color){
    color=agx(color);
    color=agxLook(color);
    return agxEotf(color);
}

vec3 chromaticAberration(vec2 uv,sampler2D bufferSampler)
{
    vec2 center=vec2(.5,.5);
    vec2 offset=(uv-center)*CHROMATIC_ABERRATION_INTENSITY;
    
    // Find how much room we have before hitting the screen edge
    vec2 maxOffset=min(uv,vec2(1.,1.)-uv);
    
    // Prevent the offset from extending beyond the screen
    float scale=min(
        1.,
        min(
            abs(maxOffset.x/max(abs(offset.x),1e-6)),
            abs(maxOffset.y/max(abs(offset.y),1e-6))
        )
    );
    
    offset*=scale;
    
    float r=texture2D(bufferSampler,uv+offset).r;
    float g=texture2D(bufferSampler,uv).g;
    float b=texture2D(bufferSampler,uv-offset).b;
    
    return vec3(r,g,b);
}

float random(float x)
{
    return fract(sin(x)*43758.5453);
}
// original vhs filter https://gamedev.center/how-to-make-a-retro-vhs-effect-shader-in-unity/
// some changes were made 
vec3 vhsFilter(vec2 uv,sampler2D bufferSampler,float time,vec2 resolution)
{
    // Constants
    const float scanlineCount=256.;
    const float scanlineIntensity= 1.2;
    const float scanlineSpeed=2.;
    const float jitterSpeed=12.;
    const float segmentCount=32.;
    const float colorBleed=.86;
    const float noiseIntensty=.05;
    const float distortion=.3;
    const float wobbleFrequency=20.;
    const float wobbleSpeed=.2;
    const float chromaticIntensity=.6;
    
    const float PI=3.14159265;
    
    vec2 distortedUV=uv;
    vec3 color=texture2D(bufferSampler,distortedUV).rgb;
    
    // Add VHS scanlines
    float lineIndex=floor(uv.y*scanlineCount);
    float lineJitter=random(lineIndex+floor(time*jitterSpeed));
    lineJitter=(lineJitter-.5)*.15;
    float scanline=sin((uv.y*scanlineCount+time*scanlineSpeed+lineJitter)*2.*PI);
    float scanlineMask=mix(1.,1.-scanlineIntensity,scanline*.5+.5);
    //Break up scanlines
    float segmentIndex=floor(uv.x*segmentCount);
    float segmentNoise=random(lineIndex*17.+segmentIndex*31.+floor(time*8.)*43.);
    float breakup=step(.85,segmentNoise);
    
    scanlineMask=mix(scanlineMask,1.,breakup*.7);
    color*=scanlineMask;
    
    // Apply a simple color grade
    float gray=dot(color,vec3(.3,.59,.11));
    color=mix(color,vec3(gray.xxx),.15);
    color=mix(color,vec3(.9,.95,1.1),.08);
    
    // Color bleeding
  
    float brightness=dot(color,vec3(.3,.59,.11));
    float blendAmount=colorBleed*smoothstep(.05,.2,brightness);
    vec2 offset=vec2(colorBleed/resolution.x,0.);
    float r=texture2D(bufferSampler,distortedUV+offset).r;
    float g=color.g;
    float b=texture2D(bufferSampler,distortedUV-offset).b;
    vec3 aberrated=vec3(r,g,b);
    color=mix(color,aberrated,blendAmount);
    
    // Separate Chromatic Pass
    vec2 center = vec2(0.5,0.5);
    vec2 dist = uv - center;
    vec2 chromaticOffset =dist * CHROMATIC_ABERRATION_INTENSITY;
    float caR = texture2D(bufferSampler,distortedUV + chromaticOffset).r;
    float caG = texture2D(bufferSampler,distortedUV).g;
    float caB = texture2D(bufferSampler,distortedUV - chromaticOffset).b;
    vec3 chromaticAberrated = vec3(caR,caG,caB);
    color = mix(color,chromaticAberrated,chromaticIntensity);

    // Add noise
       float noise=fract(sin(dot(uv* time,vec2(12.9898,78.233)))*43758.5453);
    
    noise = noise*2.-1.;
    
    color+= noise *  noiseIntensty;
    
    return color;
    
    /*
    vec2 distortedUv=uv;
    // --------------------------------------------------
    // Horizontal tape wobble
    // --------------------------------------------------
    
    vec2 distortedUv = uv;
    
    float line = floor(uv.y * resolution.y);
    
    // Slow tape wobble
    float wobble =
    sin(uv.y * 15.0 + time * 1.5) *
    0.0015;
    
    // Faster per-line distortion
    float lineDistortion =
    sin(line * 0.15 + time * 8.0) *
    0.001;
    
    distortedUv.x += wobble + lineDistortion;
    // --------------------------------------------------
    // RGB separation
    // --------------------------------------------------
    
    float chromaOffset=.003;
    
    float r=texture2D(
        bufferSampler,
        distortedUv+vec2(chromaOffset,0.)
    ).r;
    
    float g=texture2D(
        bufferSampler,
        distortedUv
    ).g;
    
    float b=texture2D(
        bufferSampler,
        distortedUv-vec2(chromaOffset,0.)
    ).b;
    
    vec3 color=vec3(r,g,b);
    
    // --------------------------------------------------
    // Scanlines
    // --------------------------------------------------
    
    float scanline=sin(uv.y*resolution.y*1.5)*.08;
    
    color-=scanline;
    
    // --------------------------------------------------
    // Noise
    // --------------------------------------------------
    
    float noise=fract(sin(dot(uv* time,vec2(12.9898,78.233)))*43758.5453);
    
    noise = noise*2.-1.;
    
    color+= noise * .03;
    
    // --------------------------------------------------
    // Slight desaturation
    // --------------------------------------------------
    
    float luminance=dot(color,vec3(.299,.587,.114));
    
    color=mix(vec3(luminance.xxx),color,.85);
    
    return color;
    */
}

