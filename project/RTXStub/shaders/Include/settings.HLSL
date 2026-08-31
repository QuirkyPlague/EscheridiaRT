#ifndef SETTINGS_HLSL
#define SETTINGS_HLSL


// White furnace test
#define WHITE_FURNACE 0

// This will enable an HDR color space to use with your HDR monitor
// This WILL require an external plugin like Reshade or Special K
// Nonfunctional for the time being
#define ENABLE_HDR 0

//Tune to your monitor
#define HDR_PEAK_LUMINANCE 750

// What color space your output will use
// 0 SRGB 
// 1 Rec 709
// 2 Rec 2020
// 3 Display P3
// IT IS HIGHLY RECOMMENDED YOU USE Rec 2020 OR Display P3 IF HDR IS ENABLED
#define COLOR_SPACE 3

// This disables objects that are not raytraced (sign text, particles stars). This will disable the menu panorama 
// Use this if you want those to not appear in front of DOF for renders
#define DISABLE_RASTER_OBJECTS 0

// Lighting Parameters
#define SUN_AZIMUTH               (0)                   // Vanilla: 0.0

// The sun's zenith angle in radians
#define SUN_ZENITH                (0)                   // Vanilla: 0.0, BetterRTX: PI / 4


#define CHROMATIC_ABERRATION_INTENSITY 0.01

#define ENABLE_DOF 0
// Approximate distances for the type of shot you want
// 0.0-5.0 = close range shots
// 6.0 - 15.0 midrange shot
// 16.0+ = long range shot
#define DOF_FOCAL_DISTANCE 21.25f


// Blur does not scale with focal distance
// Longer focal distance needs more blur if you want a very focused shot
#define DOF_BLUR_STRENGTH 76.725f 


// 0 = circular 
// 1 = polygonal
// with polygonal the shape is dependent on the blade count
#define DOF_APERTURE_SHAPE 1
#define DOF_BLADES 8

#define DOF_APERTURE_ROTATION 180.0


// Increasing this will make shadows softer
// Also makes sunlight brighter or darker
// If radius is made larger sun is more intense
// Recommended to reduce sunlight intensity if increased
#define SUN_RADIUS   0.00465f 
#define SUN_INTENSITY 1.25
#define CLOUD_SHADOW_OPACITY 0.616
#define ENABLE_SUNLIGHT 1

//Allows reading of resource pack fog values to determine shadow opacity
#define DO_RP_CLOUD_OPACITY 0


#define POINT_LIGHT_SHADOW_SAMPLES 1
#define EMISSION_STENGTH  300


#define VL_FOG_STEPS 16
#define MAX_FOG_DISTANCE  256

// Vertical bounds of the path-traced fog layer in world space.
#define PATH_TRACED_FOG_BOTTOM_Y 32.0
#define PATH_TRACED_FOG_TOP_Y 96.0

//Sun colors alpha stores intensity
#define DAY_SUN_COLOR float4(1.0,0.7925,0.515, 1.8)
#define NOON_SUN_COLOR float4(1.0,0.95,0.85, 1.65)
#define SUNRISE_SUN_COLOR float4(1.0,0.3137,0.0275, 1.6)
#define MOON_COLOR float4(0.0624, 0.1196, 0.2745, 0.043)

//sky intensity multipliers

#define RAYLEIGH_MULT                  7.55 //brightness of the sky
#define NIGHT_INTENSITY                0.1 //brightness of the night sky
#define NIGHT_INDIRECT_INTENSITY       0.35  //brightness of the night sky light without affecting actual intensity

//sky zenith colors
#define DAY_SKY_COL                    float3(0.225, 0.512, 1.185)
#define NOON_SKY_COL                   float3(0.225, 0.512, 1.185)
#define SUNRISE_SKY_COL                float3(0.3292, 0.6353, 1.0)
#define SUNSET_SKY_COL                 float3(0.2322, 0.4529, 0.8265)
#define NIGHT_SKY_COL                  float3(0.035, 0.0745, 0.2724)

//sky horizon colors
#define DAY_HORIZON_COL                float3(0.6453, 0.8176, 1.0)
#define NOON_HORIZON_COL               float3(0.6453, 0.8176, 1.0)
#define SUNRISE_HORIZON_COL            float3(1.1827, 0.5302, 0.2541)
#define SUNSET_HORIZON_COL             float3(1.1784, 0.5451, 0.1359)
#define NIGHT_HORIZON_COL              float3(0.0559, 0.1169, 0.2114)

//sky ground colors
#define DAY_GROUND_COL                 float3(0.2147, 0.3451, 0.6353)
#define NOON_GROUND_COL                float3(0.2147, 0.3451, 0.6353)
#define SUNRISE_GROUND_COL             float3(0.2549, 0.3922, 0.6118)
#define SUNSET_GROUND_COL              float3(0.2118, 0.2706, 0.6118)
#define NIGHT_GROUND_COL               float3(0.0196, 0.0275, 0.1294)

//MIE Scattering Values
//Alpha value determines the lobe shape 
//Larger == more tightly packed
#define DAY_MIE_COL                    float4(0.8333, 0.5922, 0.3922, 0.735)         
#define NOON_MIE_COL                   float4(0.7569, 0.6588, 0.5255, 0.845)
#define SUNRISE_MIE_COL                float4(1.0, 0.7137, 0.4275, 0.763)
#define SUNSET_MIE_COL                 float4(0.811, 0.4437, 0.2775, 0.78)
#define NIGHT_MIE_COL                  float4(0.2824, 0.1196, 0.0745, 0.75)

//Sky blending points
#define ZENITH_BLEND                    0.47             
#define HORIZON_BLEND                   4.5  
#define GROUND_BLEND                    0.55


#define WAVE_FADE_START 24.0
#define WAVE_FADE_END   500.0

#define WAVE_SMOOTHING                                      (0.0513)
#define WAVE_INTENSITY                                      (0.0652)
#define WAVE_FREQUENCY                                      (1.24)
#define WAVE_OCTAVES                                        (21)
#define WAVE_SPEED                                          (3.0)
#define WAVE_RANDOMNESS                                     (0.15)
#define WAVE_OCTAVE_FREQUENCY                               (1.24)
#define WAVE_OCTAVE_SPEED                                   (1.13)
#define WAVE_OCTAVE_MIX_WEIGHT                              (0.326)
#define WAVE_PULL                                           (0.34235)

#define WAVE_STEEPNESS 0.25
#define WAVE_HEIGHT  0.5

#define AGX_MIN_EV -11.4561
#define AGX_MAX_EV  5.526069
#endif // SETTINGS_HLSL
