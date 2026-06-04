#ifndef SETTINGS_HLSL
#define SETTINGS_HLSL



// Lighting Parameters
#define SUN_RADIUS   0.025
#define SUN_INTENSITY 2.45
#define SKYLIGHT_INTENSITY 3.24
#define CLOUD_SHADOW_OPACITY 0.586

//Sun colors alpha stores intensity
#define DAY_SUN_COLOR float4(1.0,0.7625,0.545, 0.95)
#define NOON_SUN_COLOR float4(1.0,0.95,0.85, 0.75)
#define SUNRISE_SUN_COLOR float4(1.0,0.3137,0.0275, 0.61)
#define MOON_COLOR float4(0.0624, 0.1196, 0.2745, 0.4)

//sky intensity multipliers

#define RAYLEIGH_MULT                  1.6 //brightness of the sky
#define NIGHT_INTENSITY                0.11 //brightness of the night sky
#define NIGHT_INDIRECT_INTENSITY       0.35  //brightness of the night sky light without affecting actual intensity

//sky zenith colors
#define DAY_SKY_COL                    float3(0.275, 0.512, 1.0)
#define NOON_SKY_COL                   float3(0.275, 0.512, 1.0)
#define SUNRISE_SKY_COL                float3(0.2592, 0.6353, 1.0)
#define SUNSET_SKY_COL                 float3(0.2322, 0.4529, 0.8265)
#define NIGHT_SKY_COL                  float3(0.035, 0.0745, 0.2724)

//sky horizon colors
#define DAY_HORIZON_COL                float3(0.7653, 0.9176, 1.0)
#define NOON_HORIZON_COL               float3(0.8353, 0.9176, 1.0)
#define SUNRISE_HORIZON_COL            float3(0.9827, 0.5302, 0.3941)
#define SUNSET_HORIZON_COL             float3(0.8784, 0.3451, 0.1359)
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
#define ZENITH_BLEND                    0.5              
#define HORIZON_BLEND                   5.5  
#define GROUND_BLEND                    0.55


//Water
#define WAVE_SMOOTHING                                      (0.2313)
#define WAVE_INTENSITY                                      (0.0752)
#define WAVE_FREQUENCY                                      (2.1)
#define WAVE_OCTAVES                                        (14)
#define WAVE_SPEED                                          (3.0)
#define WAVE_RANDOMNESS                                     (0.45)
#define WAVE_OCTAVE_FREQUENCY                               (1.21)
#define WAVE_OCTAVE_SPEED                                   (1.14)
#define WAVE_OCTAVE_MIX_WEIGHT                              (0.332)
#define WAVE_PULL                                           (-0.34235)

#endif // SETTINGS_HLSL