#ifndef SKY_HLSL
#define SKY_HLSL

#include "settings.hlsl"
#include "Util.hlsl"

float Rayleigh(float mu) {
    return 3.0 * (1.0 + mu * mu) / (16.0 * PI);
}

float HG(float mu, float g) {
    return (1.0 - g * g) / ((4.0 + PI) * pow(1.0 + g * g - 2.0 * g * mu, 1.5));
}

float4 getSunColor(float4 sunColor) {
    const float4 colors[8] = {
        NOON_SUN_COLOR,
        DAY_SUN_COLOR,
        DAY_SUN_COLOR,
        SUNRISE_SUN_COLOR,
        SUNRISE_SUN_COLOR * 0.06,
        SUNRISE_SUN_COLOR * 0.025,
        SUNRISE_SUN_COLOR * 0.025,
        MOON_COLOR
    };

    const float times[8] = {
        0.0000000000, // 6000
        0.1920399368, // 3000
        0.3466664553, // 1000
        0.4309642911, // 0
        0.4746705294, // 23500
        0.491301561, // 23000
        0.502156132, // 23000
        0.5303186402
    };

    float time = getTime();

    float timediff = clamp(g_view.skyTextureW - 0.491301561, 0, 0.0253534615);
    timediff *= 1.0 / 0.0253534615;
    sunColor = MOON_COLOR;

    [unroll] for (int i = 1; i < 8; i++) {
        if (g_view.skyTextureW >= times[i - 1] && g_view.skyTextureW < times[i]) {
            float w = (g_view.skyTextureW - times[i - 1]) / (times[i] - times[i - 1]);
            sunColor = lerp(colors[i - 1], colors[i], w);

            break;
        }
    }

    return sunColor;
}

float4 getSunColor1(float4 sunColor) {
    const float4 colors[7] = {
        NOON_SUN_COLOR,
        DAY_SUN_COLOR,
        DAY_SUN_COLOR,
        SUNRISE_SUN_COLOR,
        SUNRISE_SUN_COLOR * 0.06,
        SUNRISE_SUN_COLOR * 0.025,
        MOON_COLOR
    };

    const float times[7] = {
        0.0000000000, // 6000
        0.1920399368, // 3000
        0.3466664553, // 1000
        0.4309642911, // 0
        0.4746705294, // 23500
        0.5193186402, // 23000
        0.5621
    };

    float time = getTime();

    float timediff = clamp(abs(g_view.skyTextureW - 0.51952102785), 0, 0.00879302615);
    timediff *= 1.0 / 0.00879302615;
    sunColor = MOON_COLOR;
    [unroll] for (int i = 1; i < 7; i++) {
        if (g_view.skyTextureW >= times[i - 1] && g_view.skyTextureW < times[i]) {
            float w = (g_view.skyTextureW - times[i - 1]) / (times[i] - times[i - 1]);
            sunColor = lerp(colors[i - 1], colors[i], w);
            break;
        }
    }
    return sunColor;
}

float3 skyCompute(float3 pos) {
    float3 dir = pos;

    float3 sunDir = getTrueDirectionToSun();

    float VoL = dot(dir, sunDir);

    float upPos = saturate(dir.y);
    float downPos = clamp(dir.y, -1.0, 0.0);
    float negatedDownPos = -1.0 * downPos;
    float midPos = upPos + negatedDownPos;
    float negatedMidPos = 1.0 - midPos;
    //rain
    const float3 rainZenCol = float3(0.2902, 0.3608, 0.4784) * 0.25;
    const float3 rainHorCol = float3(0.7059, 0.7569, 0.7961) * 0.25;
    const float3 rainGrndCol = float3(0.1569, 0.1922, 0.2314) * 0.25;

    const int keys = 10;

    const float3 colors[7] = {
        NOON_SKY_COL,
        DAY_SKY_COL,
        DAY_SKY_COL,
        SUNRISE_SKY_COL,
        SUNSET_SKY_COL * 0.06,
        SUNSET_SKY_COL * 0.025,
        NIGHT_SKY_COL * NIGHT_INTENSITY
    };
    const float times[7] = {
        0.0000000000, // 6000
        0.1920399368, // 3000
        0.3466664553, // 1000
        0.4309642911, // 0
        0.4746705294, // 23500
        0.5193186402, // 23000
        0.5621
    };

    const float3 horizonColors[7] = {
        NOON_HORIZON_COL,
        DAY_HORIZON_COL * 1.4,
        DAY_HORIZON_COL * 1.4,
        SUNRISE_HORIZON_COL * 1.15,
        SUNSET_HORIZON_COL * 0.1,
        SUNSET_HORIZON_COL * 0.025,
        NIGHT_HORIZON_COL * NIGHT_INTENSITY
    };
    const float3 groundColors[7] = {
        NOON_GROUND_COL,
        DAY_GROUND_COL,
        DAY_GROUND_COL,
        SUNRISE_GROUND_COL,
        SUNSET_GROUND_COL * 0.1,
        SUNSET_GROUND_COL * 0.01,
        NIGHT_GROUND_COL * NIGHT_INTENSITY
    };

    float time = getTime();

    float timediff = clamp(abs(g_view.skyTextureW - 0.51952102785), 0, 0.00879302615);
    timediff *= 1.0 / 0.00879302615;
    float3 zenithCol = NIGHT_SKY_COL * NIGHT_INTENSITY;
    float3 horizonCol = NIGHT_HORIZON_COL * NIGHT_INTENSITY;
    float3 groundCol = NIGHT_GROUND_COL * NIGHT_INTENSITY;
    float mieScale = 0.0;
    float3 mieScat = float3(0.0,0.0,0.0);
    float dawnDuskMieFactor = 0.0;
    float dawnDuskTimeFactor = 0.0;
    float rainIntensityShift = 0.01;

    [unroll] for (int i = 1; i < 7; i++) {
        if (g_view.skyTextureW >= times[i - 1] && g_view.skyTextureW < times[i]) {
            float w = (g_view.skyTextureW - times[i - 1]) / (times[i] - times[i - 1]);

            zenithCol = lerp(colors[i - 1], colors[i], w);
            horizonCol = lerp(horizonColors[i - 1], horizonColors[i], w);
            groundCol = lerp(groundColors[i - 1], groundColors[i], w);

            break;
        }
    }

   


    float zenithBlend = saturate(pow(upPos, ZENITH_BLEND));
    float horizonBlend = saturate(pow(negatedMidPos, HORIZON_BLEND));
    float groundBlend = saturate(pow(negatedDownPos, GROUND_BLEND));

    zenithCol *=  zenithBlend;
    horizonCol *=  horizonBlend;
    groundCol *= groundBlend;

    float3 sky = zenithCol + horizonCol + groundCol;

    float3 color = sky;
    float skyLuminance = dot(color, 1.0);
    color = pow(color, 1.5);
    color *= skyLuminance / dot(color, 1.0);
    return color;
}

float3 getSkyColor(float3 color) {
    const float3 colors[7] = {
        NOON_SKY_COL,
        DAY_SKY_COL,
        DAY_SKY_COL,
        SUNRISE_SKY_COL,
        SUNSET_SKY_COL * 0.06,
        SUNSET_SKY_COL * 0.025,
        NIGHT_SKY_COL * NIGHT_INTENSITY
    };
    const float times[7] = {
        0.0000000000, // 6000
        0.1920399368, // 3000
        0.3466664553, // 1000
        0.4309642911, // 0
        0.4746705294, // 23500
        0.5193186402, // 23000
        0.5621
    };

    float time = getTime();

    float timediff = clamp(abs(g_view.skyTextureW - 0.51952102785), 0, 0.00879302615);
    timediff *= 1.0 / 0.00879302615;
    float3 zenithCol = NIGHT_SKY_COL * NIGHT_INTENSITY;

    [unroll] for (int i = 1; i < 7; i++) {
        if (g_view.skyTextureW >= times[i - 1] && g_view.skyTextureW < times[i]) {
            float w = (g_view.skyTextureW - times[i - 1]) / (times[i] - times[i - 1]);

            zenithCol = lerp(colors[i - 1], colors[i], w);
            break;
        }
    }

    color = zenithCol;
    float skyLuminance = dot(color, 1.0);
    color = pow(color, 1.5);
    color *= skyLuminance / dot(color, 1.0);
    return color;
}

float3 getSun(float3 dir) {
    float3 sunDir = inEnd ? END_SUN_DIRECTION : getTrueDirectionToSun();
    float3 moonDir = getTrueDirectionToMoon();
    float cosThetaSun = dot(dir, sunDir);
    float mDotL = dot(dir, moonDir);

    float upPos = clamp(dir.y, 0, 1);
    float downPos = clamp(dir.y, -1, 0);
    float negatedDownPos = -1.0 * downPos;
    float midPos = upPos + negatedDownPos;
    float negatedMidPos = 1.0 - midPos;
    float zenithBlend = clamp(pow(upPos, 0.35), 0, 1);
    float horizonBlend = clamp(pow(negatedMidPos, 4.5), 0, 1);
    float groundBlend = clamp(pow(negatedDownPos, 0.25), 0, 1);

    float invCos = 1.0 - cosThetaSun;
    float invCos1 = 1.0 - mDotL;
    float angularDist = clamp(invCos, -1.0, 1.0);
    float angularDist1 = clamp(invCos1, -1.0, 1.0);
    float sunHeightFactor = smoothstep(groundBlend, groundBlend + 0.28, dir.y);
    float sunRadius = inEnd ? END_SUN_DISC_SIZE : 0.013 * 1.0;

    
    float theta = acos(clamp(cosThetaSun, -1.0, 1.0));
    float radial = theta / sunRadius;
    float sun = 1.0 - smoothstep(0.9, 1.0, radial);
    float mu = sqrt(clamp(4.0 - radial * radial, 0.0, 4.0));
    float limbDarkening = 1.0 - 0.6 * (1.0 - mu);
    // Explicit special handling for the end sun disc 
    // Will calculate the edge of the cirlce and also find the distance from the center
    if(inEnd)
    {
        // 1. Sharp Outer Edge Mask
        // Cuts off instantly at radial = 1.0. 
        // step(radial, 1.0) returns 1.0 inside the circle, and 0.0 outside.
        float sharpMask = step(radial, 1.0);

        // 2. Fade Towards Middle
        // 'radial' goes from 0.0 (center) to 1.0 (edge). 
        // Using it directly means the edge is brightest, fading to 0 at the center.
        float centerFade = radial;

        // Optional: Control the fade curve
        centerFade = pow(centerFade, 23.0); // Makes the center darker faster
        centerFade = sqrt(centerFade);    // Keeps the center brighter longer

        // 3. Combine Mask and Gradient
        sun = centerFade * sharpMask;
    }

   
    float3 sunColor = inEnd ? END_SUN_COLOR * END_SUN_DISC_INTENSITY : getSunColor1(0..xxxx).rgb;
    float3 twinSunDisc = 0.0;
    #if USE_END_TWIN_SUNS
    if(inEnd) {
        float3 twinSunDir = END_TWIN_SUN_DIRECTION;
        float cosThetaTwinSun = dot(dir, twinSunDir);
        float invCosTwinSun = 1.0 - cosThetaTwinSun;
        float angularDistTwinSun = clamp(invCosTwinSun, -1.0, 1.0);
        float thetaTwinSun = acos(clamp(cosThetaTwinSun, -1.0, 1.0));
        float radialTwinSun = thetaTwinSun / END_TWIN_SUN_DISC_SIZE;
        float twinSun = 1.0 - smoothstep(0.9, 1.0, radialTwinSun);
        twinSunDisc = twinSun * END_TWIN_SUN_COLOR * END_TWIN_SUN_DISC_INTENSITY;
    }
    #endif

    float3 fullSun = inEnd ? sun * limbDarkening * sunColor * 2.0 + twinSunDisc : sun * limbDarkening * sunColor * 450.0 * sunHeightFactor;
    
    float moon = smoothstep(
        0.0002 * 0.86,
        0.0001 * 0.86 * 0.03,
        angularDist1);

    float3 moonColor =  float3(0.12, 0.321,0.65);
    float3 fullmoon = inEnd ? 0.0 : moon * moonColor * 30 * sunHeightFactor;

    float3 celestial = fullSun + fullmoon;

    return celestial;
}

// Maps a 3D vector to 2D UV coordinates on an unwrapped cross/box layout
float2 CubeToUV(float3 r, float2 uvScale)
{
    float3 absR = abs(r);
    float2 uv = float2(0, 0);
    int faceIndex = 0;
    float scale;
    // Find the dominant axis to determine the cube face
    if (absR.x >= absR.y && absR.x >= absR.z)
    {
        // X-dominant (Left/Right faces)
        faceIndex = r.x > 0 ? 0 : 1;
        scale = 0.5f / absR.x;
        uv.x = r.x > 0 ? -r.z : r.z;
        uv.y = -r.y;
        uv /= absR.x;
    }
    else if (absR.y >= absR.x && absR.y >= absR.z)
    {
        // Y-dominant (Top/Bottom faces)
        faceIndex = r.y > 0 ? 2 : 3;
        scale = 0.5f / absR.y;
        uv.x = r.x;
        uv.y = r.y > 0 ? r.z : -r.z;
        uv /= absR.y;
    }
    else
    {
        // Z-dominant (Front/Back faces)
        faceIndex = r.z > 0 ? 4 : 5;
        scale = 0.5f / absR.z;
        uv.x = r.z > 0 ? r.x : -r.x;
        uv.y = -r.y;
        uv /= absR.z;
    }
    
   return frac(mad(uv, float2(scale, scale), float2(0.5f, 0.5f)) * uvScale);
}

float3 endSkyColor(float3 dir)
{
     Texture2D skyTexture = textures[g_view.skyTextureIdx];
    float3 staticSkyTex = skyTexture.SampleLevel(linearSampler, CubeToUV(dir, g_view.skyTextureUVScale), 0).rgb;
    return staticSkyTex;
}

float3 skyScattering1(float3 pos) {
#if WHITE_FURNACE == 1
    return 1.0;
#else
   
    float3 dir = normalize(pos);
     float3 sunDir = inEnd ? END_SUN_DIRECTION : getTrueDirectionToSun();
    float3 moonDir = getTrueDirectionToMoon();

    float3 endTwinSunDir = END_TWIN_SUN_DIRECTION;

    float VoL = dot(dir, sunDir);
    float rayleigh = inEnd ? Rayleigh(VoL) * END_RAYLEIGH_MULT  : Rayleigh(VoL) * RAYLEIGH_MULT * 13;


    float upPos = saturate(dir.y);
    float downPos = clamp(dir.y, -1.0, 0.0);
    float negatedDownPos = -1.0 * downPos;
    float midPos = upPos + negatedDownPos;
    float negatedMidPos = 1.0 - midPos;
    //rain
    const float3 rainZenCol = float3(0.4784, 0.4784, 0.4784) * 4;
    const float3 rainHorCol = float3(0.7059, 0.7569, 0.7961) * 4;
    const float3 rainGrndCol = float3(0.1569, 0.1922, 0.2314) *4;

    const int keys = 10;

    const float3 colors[7] = {
        NOON_SKY_COL,
        DAY_SKY_COL,
        DAY_SKY_COL,
        SUNRISE_SKY_COL,
        SUNSET_SKY_COL * 0.06,
        SUNSET_SKY_COL * 0.025,
        NIGHT_SKY_COL * NIGHT_INTENSITY
    };
    const float times[7] = {
        0.0000000000, // 6000
        0.1920399368, // 3000
        0.3466664553, // 1000
        0.4309642911, // 0
        0.4746705294, // 23500
        0.5193186402, // 23000
        0.5621
    };

    const float weatherIntensity[7] = {
        0.35,
        0.35,
        0.15,
        0.1,
        0.02,
        0.01,
        0.0015
    };

    const float3 horizonColors[7] = {
        NOON_HORIZON_COL,
        DAY_HORIZON_COL * 2.2,
        DAY_HORIZON_COL * 2.2,
        SUNRISE_HORIZON_COL * 2.15,
        SUNSET_HORIZON_COL * 0.1,
        SUNSET_HORIZON_COL * 0.025,
        NIGHT_HORIZON_COL * NIGHT_INTENSITY
    };
    const float3 groundColors[7] = {
        NOON_GROUND_COL,
        DAY_GROUND_COL,
        DAY_GROUND_COL,
        SUNRISE_GROUND_COL,
        SUNSET_GROUND_COL * 0.1,
        SUNSET_GROUND_COL * 0.01,
        NIGHT_GROUND_COL * NIGHT_INTENSITY
    };
    const float4 mieColor[7] = {
        NOON_MIE_COL,
        DAY_MIE_COL,
        DAY_MIE_COL,
        SUNRISE_MIE_COL,
        SUNSET_MIE_COL * 0.86,
        SUNSET_MIE_COL * 0.86,
        NIGHT_MIE_COL
    };

    float time = getTime();

    float timediff = clamp(abs(g_view.skyTextureW - 0.51952102785), 0, 0.00879302615);
    timediff *= 1.0 / 0.00879302615;
    float3 zenithCol = NIGHT_SKY_COL * NIGHT_INTENSITY;
    float3 horizonCol = NIGHT_HORIZON_COL * NIGHT_INTENSITY;
    float3 groundCol = NIGHT_GROUND_COL * NIGHT_INTENSITY;
    float mieScale = 0.0;
    float3 mieScat = float3(0.0,0.0,0.0);
    float dawnDuskMieFactor = 0.0;
    float dawnDuskTimeFactor = 0.0;
    float rainIntensityShift = 0.01;

    [unroll] for (int i = 1; i < 7; i++) {
        if (g_view.skyTextureW >= times[i - 1] && g_view.skyTextureW < times[i]) {
            float w = (g_view.skyTextureW - times[i - 1]) / (times[i] - times[i - 1]);

            zenithCol = lerp(colors[i - 1], colors[i], w);
            horizonCol = lerp(horizonColors[i - 1], horizonColors[i], w);
            groundCol = lerp(groundColors[i - 1], groundColors[i], w);
            mieScat = lerp(mieColor[i - 1].rgb, mieColor[i].rgb, w);
            mieScale = lerp(mieColor[i - 1].a, mieColor[i].a, w);
            dawnDuskMieFactor = smoothstep(-0.035, 0.035, dir.y);
            dawnDuskTimeFactor = smoothstep(0.00, 0.05, w) * smoothstep(0.1, 0.35, w);
            rainIntensityShift = lerp(weatherIntensity[i - 1], weatherIntensity[i], w);
            break;
        }
    }
    
    float zenithBlend = saturate(pow(upPos, inEnd ? END_ZENITH_BLEND : ZENITH_BLEND));
    float horizonBlend = saturate(pow(negatedMidPos, inEnd ? END_HORIZON_BLEND : HORIZON_BLEND));
    float groundBlend = saturate(pow(negatedDownPos, inEnd ? END_GROUND_BLEND : GROUND_BLEND));

    zenithCol = lerp(zenithCol, rainZenCol * rainIntensityShift, g_view.rainLevel);
	horizonCol = lerp(horizonCol, rainHorCol * rainIntensityShift,  g_view.rainLevel);
	groundCol = lerp(groundCol, rainGrndCol * rainIntensityShift,  g_view.rainLevel);

     zenithCol = inEnd ? END_ZENITH_COLOR : zenithCol;
    horizonCol = inEnd ? END_HORIZON_COLOR : horizonCol;
    groundCol = inEnd ? END_GROUND_COLOR : groundCol;

    zenithCol *= rayleigh * zenithBlend;
    horizonCol *= rayleigh * horizonBlend;
    groundCol *= rayleigh * groundBlend;

    float3 sky = zenithCol + horizonCol + groundCol;

    float4 sunColor = getSunColor(float4(0.0, 0.0, 0.0, 0.0)) ;

    float3 moonMieScatterColor = float3(0.00341, 0.00441, 0.01796);
    float sVoL = dot(dir, sunDir);
    float mVoL = dot(dir, moonDir);

    float twinVol = dot(dir, endTwinSunDir);

    float miePhase = HG(sVoL, inEnd ? END_MIE_COLOR.a : mieScale);
    float twinMiePhase = HG(twinVol, 0.85);
    mieScat = inEnd ? END_MIE_COLOR.rgb : mieScat;
    float3 mieColors = sunColor.rgb * mieScat * miePhase * 0.7;
    float3 twinMieColors = END_TWIN_SUN_COLOR * float3(0.3, 0.5, 0.8)  * twinMiePhase;
    float moonPhase = HG(mVoL, 0.931);
    float3 mieNight = moonMieScatterColor * moonPhase * 0.017;

    float3 finalMie = mieColors + mieNight;
   
    
    float sunElev = sunDir.y;
    float sunAboveMask = smoothstep(-0.08, 0.2, sunElev);

    float viewElev = dir.y;
    float viewAboveMask = smoothstep(-0.065, 0.035, viewElev);
    float sVoL_clamped = max(sVoL, 0.0);

    float miePhase_clamped = HG(sVoL_clamped, mieScale);

    float dawnDuskMix = lerp(1.0, dawnDuskMieFactor, dawnDuskTimeFactor);

    float mieVisibility = sunAboveMask;

    mieColors = mieScat * miePhase_clamped * 0.85;
    finalMie = (mieColors * mieVisibility * dawnDuskMix) + mieNight;

     #if USE_END_TWIN_SUNS
    if(inEnd) {
        finalMie +=twinMieColors;
    }
    #endif

    float3 sun = getSun(dir);

    float3 color = sky + finalMie;
    color = inEnd ? lerp(color, endSkyColor(dir), 0.25)  : color;
    return color + sun;
    #endif
}


#endif // SKY_HLSL