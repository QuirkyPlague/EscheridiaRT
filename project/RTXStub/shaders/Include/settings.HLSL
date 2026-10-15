#ifndef SETTINGS_HLSL
#define SETTINGS_HLSL



// 0 = Lambert
// 1 = EON
// 2 = Hammon diffuse

#define DIFFUSE_METHOD 2

#define USE_SPECTRAL 0

#define DO_SAMPLE_LIMITS 0
#define MAX_ACCUMULATED_SAMPLES 64
#define MAX_BOUNCES 8

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
#define COLOR_SPACE 2

// This disables objects that are not raytraced (sign text, particles stars). This will disable the menu panorama 
// Use this if you want those to not appear in front of DOF for renders
#define DISABLE_RASTER_OBJECTS 1

// Lighting Parameters
#define SUN_AZIMUTH               (0.741)                   // Vanilla: 0.0

// The sun's zenith angle in radians
#define SUN_ZENITH                (PI / 4)                   // Vanilla: 0.0, BetterRTX: PI / 4


#define CHROMATIC_ABERRATION_INTENSITY 0.01

#define ENABLE_DOF 1
// Approximate distances for the type of shot you want
// 0.0-5.0 = close range shots
// 6.0 - 15.0 midrange shot
// 16.0+ = long range shot
#define DOF_FOCAL_DISTANCE 7.25f


// Blur does not scale with focal distance
// Longer focal distance needs more blur if you want a very focused shot
#define DOF_BLUR_STRENGTH 150.725f 


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
#define SUN_DISC_RADIUS 0.00465f 
#define SUN_DISC_EDGE_SOFTNESS 0.08f
#define SUN_DISC_LIMB_DARKENING 0.6f
#define SUN_DISC_INTENSITY 50.0f
#define SUN_INTENSITY 16
#define RAIN_SUN_INTENSITY_MULTIPLIER 0.045
#define RAIN_BLOOM_BOOST 1.6
#define COMPUTE_BLOOM_STRENGTH 0.175f
#define CLOUD_SHADOW_OPACITY 0.616
#define ENABLE_SUNLIGHT 1

//Allows reading of resource pack fog values to determine shadow opacity
#define DO_RP_CLOUD_OPACITY 0


#define POINT_LIGHT_SHADOW_SAMPLES 1
#define POINT_LIGHT_SHADOW_RADIUS 0.0325
#define EMISSION_STENGTH  60

#define POINT_LIGHT_INTENSITY 50.0
// Number of candidate lights streamed through the RIS reservoir before tracing a single shadow ray.
// Only applied on the primary (bounceCount == 0) hit -- see RIS_LIGHT_CANDIDATE_COUNT_INDIRECT below.
#define RIS_LIGHT_CANDIDATE_COUNT 12
// Candidate count used on indirect bounces instead, where the noise reduction matters far less
// (throughput has already attenuated the contribution) but the cost is paid on every bounce/pixel.
#define RIS_LIGHT_CANDIDATE_COUNT_INDIRECT 12
// Number of candidate diffuse GI bounce directions resampled via RIS before continuing the path.
// Also primary-hit only; indirect bounces fall back to a single BRDF sample (no resampling).
#define RIS_GI_CANDIDATE_COUNT 12
#define DRAINE_ALPHA 1.05

// Deterimines whether or not the diffuse BRDF should use the accurate or fast calutlation
// 0 = fast     (Less accurate but higher performing)
// 1 = accurate (The correct shading model but slower)
#define USE_ACCURATE_DIFFUSE_BRDF 1
static const bool useFastBRDFApprox =  USE_ACCURATE_DIFFUSE_BRDF;
#define VL_FOG_STEPS 16
#define MAX_FOG_DISTANCE  128

#define DO_RAIN_WETNESS 1
#define RAIN_NORMAL_REDUCTION 0.45

//Sun colors alpha stores intensity
#define DAY_SUN_COLOR float4(1.0,0.7925,0.475, 1.14)
#define NOON_SUN_COLOR float4(1.0,0.95,0.75, 1.1)
#define SUNRISE_SUN_COLOR float4(1.0,0.4737,0.175, 1.15)
#define MOON_COLOR float4(0.0624, 0.1196, 0.2745, 0.0033)

// End dimension settings
#define ENABLE_END_SUNLIGHT 1
#define END_SUN_COLOR float3(0.658,0.221,0.573)
#define END_SUN_RADIUS 0.135f
#define END_SUN_DIRECTION normalize(float3(0.85, .48, 1.515))
#define END_SUN_INTENSITY 60
#define END_SUN_DISC_SIZE 0.091f // Size of the celestiabl body in the end
#define END_SUN_DISC_INTENSITY 100.0 // Recommended you keep this low as it can screw with indirect lighting 
#define USE_ALTERNATE_END_SUN_DISC_COLOR 0
#define END_SUN_DISC_COLOR float3(1.08,0.421,0.04)

#define USE_END_TWIN_SUNS 1
#define END_TWIN_SUN_RADIUS 0.0165f
#define END_TWIN_SUN_DIRECTION normalize(float3(-0.35, 1.68, 4.4715))
#define END_TWIN_SUN_INTENSITY 1650
#define END_TWIN_SUN_DISC_SIZE 0.021f
#define END_TWIN_SUN_DISC_INTENSITY 45.0
#define END_TWIN_SUN_COLOR float3(0.458,0.521,0.973)
#define DRAW_END_SUN_DISCS 1

#define END_RAYLEIGH_MULT 8.55
#define END_ZENITH_COLOR float3(0.112, 0.0644, 0.215)
#define END_HORIZON_COLOR float3(0.432, 0.2244, 0.515)
#define END_GROUND_COLOR float3(0.052, 0.00144, 0.0115)
#define END_MIE_COLOR float4(0.311, 0.1437, 0.2775, 0.68)
#define ORIGINAL_END_SKY_INTENSITY 0.55

// End fog
#define OVERRIDE_RP_END_SCATTERING 0
#define END_FOG_ANISOTROPY 0.665
#define END_FOG_INDIRECT_ANISOTROPY 0.65
#define END_FOG_SCATTERING_INTENSITY 1.25
#define END_FOG_DIRECT_SCATTER_BOOST 2.0f
#define END_FOG_SCATTERING_COLOR float3(0.0321, 0.0208, 0.0361)
#define END_FOG_EXTINCTION_INTENSITY 1.0


#define END_ZENITH_BLEND 0.67
#define END_HORIZON_BLEND 11.5
#define END_GROUND_BLEND 0.85

#define FOG_FADE_START 32
#define FOG_FADE_END 286
//sky intensity multipliers
#define RAYLEIGH_MULT                  1.1 //brightness of the sky
#define SKY_MIE_SCATTERING_STRENGTH    0.5   // atmospheric Mie brightness multiplier
#define SKY_MIE_FORWARD_G              0.82  // higher values make the Mie lobe more forward-scattering

#define NIGHT_INTENSITY                0.02 //brightness of the night sky
#define NIGHT_INDIRECT_INTENSITY       0.35  //brightness of the night sky light without affecting actual intensity
#define ATMOSPHERE_TURBIDITY           4.0f
    

//sky zenith colors
#define DAY_SKY_COL                    float3(0.225, 0.512, 1.185)
#define NOON_SKY_COL                   float3(0.225, 0.512, 1.185)
#define SUNRISE_SKY_COL                float3(0.3292, 0.6353, 1.0)
#define SUNSET_SKY_COL                 float3(0.2322, 0.4529, 0.8265)
#define NIGHT_SKY_COL                  float3(0.065, 0.1245, 0.2724)

//sky horizon colors
#define DAY_HORIZON_COL                float3(0.4753, 0.8176, 1.0)
#define NOON_HORIZON_COL               float3(0.4753, 0.8176, 1.0)
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
#define HORIZON_BLEND                   9.5  
#define GROUND_BLEND                    0.55


#define WAVE_FADE_START 32.0
#define WAVE_FADE_END   315.0

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

#define WAVE_STEEPNESS 0.09
#define WAVE_HEIGHT  0.0805
#define WAVE_BASE_WAVELENGTH 6.8f
#define WAVE_COUNT 6

// Gerstner Micro Wave Details (Inter-octave ripples and high-frequency capillary texture)
#define ENABLE_MICRO_WAVES          1       // 1 = Enable micro wave details between octaves, 0 = base octaves only
#define WAVE_MICRO_WAVES_PER_OCTAVE 2       // Number of intermediate micro waves between each octave (1 or 2)
#define WAVE_MICRO_AMPLITUDE_MULT   0.35f   // Amplitude scale of micro waves relative to parent octave
#define WAVE_MICRO_FREQUENCY_MULT   2.55f   // Frequency multiplier for the in-between micro waves
#define WAVE_MICRO_STEEPNESS        0.145f   // Sharpness / steepness factor for micro wave crests
#define WAVE_MICRO_CHOP_ANGLE       8.15f   // Directional cross-angle offset (radians) creating 2D surface chop
#define WAVE_MICRO_SPEED_MULT       1.20f   // Capillary phase velocity multiplier

// Water Parallax (POM)
#define ENABLE_WATER_PARALLAX 1
#define WATER_PARALLAX_STEPS 8
#define WATER_PARALLAX_MAX_DIST 24.5f



#define AGX_MIN_EV -12.4561
#define AGX_MAX_EV 5.2152

#define AUTO_EXPOSURE_MIN -12.0
#define AUTO_EXPOSURE_MAX 8.0

#define EXPOSURE_MIN -2.5
#define EXPOSURE_MAX 5.3
#define EXPOSURE_MAX_DAY 8.0
#define EXPOSURE_MAX_NIGHT 2.0

#define TARGET_EXPOSURE_EV 0.7
#define EXPOSURE_PERCENTILE 0.65

// Minimum scene luminance that auto-exposure will adapt down to.
// Keeps naturally dark areas (caves, unlit nights) dark instead of boosting black into mid-gray.
#define MIN_ADAPTATION_LUMINANCE 0.08

// Center-weighted metering bias: increases the importance of tiles near the screen center (player gaze).
#define CENTER_METERING_STRENGTH 2.0

// Minimum tile average luminance to be counted in the histogram. Pitch black tiles are clipped out.
#define BLACK_CLIP_LUMINANCE 0.0005

#define ENABLE_POM 1

#define MINIMUM_ALPHA_BLEND_OPACITY 0.05f
#define ALPHA_BLEND_OPACITY_CURVE 3.0f

#endif // SETTINGS_HLSL
