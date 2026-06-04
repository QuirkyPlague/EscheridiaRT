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


float4 getSunColor(float4 sunColor)
{
     const float4 colors[7] =
	{
		NOON_SUN_COLOR,
        DAY_SUN_COLOR,
        DAY_SUN_COLOR,
        SUNRISE_SUN_COLOR,
        SUNRISE_SUN_COLOR * 0.06,
        SUNRISE_SUN_COLOR * 0.025,
        MOON_COLOR
	};

    const float times[7] =
	{
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
    [unroll] for (int i = 1; i < 7; i++)
	{
		if (g_view.skyTextureW >= times[i - 1] && g_view.skyTextureW < times[i])
		{
			float w = (g_view.skyTextureW - times[i - 1]) / (times[i] - times[i - 1]);
            sunColor = lerp(colors[i - 1], colors[i], w);
            break;
        }
    }
return sunColor;
}


float3 skyCompute(float3 pos)
{
    
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

    const float3 colors[7] =
	{
		NOON_SKY_COL,
        DAY_SKY_COL,
        DAY_SKY_COL,
        SUNRISE_SKY_COL,
        SUNSET_SKY_COL * 0.06,
        SUNSET_SKY_COL * 0.025,
        NIGHT_SKY_COL * NIGHT_INTENSITY
	};
	const float times[7] =
	{
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
		
	[unroll] for (int i = 1; i < 7; i++)
	{
		if (g_view.skyTextureW >= times[i - 1] && g_view.skyTextureW < times[i])
		{
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

float3 skyScattering1(float3 pos)
{
    
    float3 dir = pos;

	float3 sunDir = getTrueDirectionToSun();

    float VoL = dot(dir, sunDir);
    float rayleigh = Rayleigh(VoL) * 17;

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

    const float3 colors[7] =
	{
		NOON_SKY_COL,
        DAY_SKY_COL,
        DAY_SKY_COL,
        SUNRISE_SKY_COL,
        SUNSET_SKY_COL * 0.06,
        SUNSET_SKY_COL * 0.025,
        NIGHT_SKY_COL * NIGHT_INTENSITY
	};
	const float times[7] =
	{
		0.0000000000, // 6000
		0.1920399368, // 3000
		0.3466664553, // 1000
		0.4309642911, // 0
		0.4746705294, // 23500
		0.5193186402, // 23000
		0.5621
	};

	const float weatherIntensity[7] = 
	{
		0.35,
    	0.35,
    	0.15,
    	0.1,
    	0.2,
    	0.1,
    	0.015
	};
   
    const float3 horizonColors[7] = {
      	NOON_HORIZON_COL,
        DAY_HORIZON_COL * 1.2,
        DAY_HORIZON_COL * 1.2,
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
		
	[unroll] for (int i = 1; i < 7; i++)
	{
		if (g_view.skyTextureW >= times[i - 1] && g_view.skyTextureW < times[i])
		{
			float w = (g_view.skyTextureW - times[i - 1]) / (times[i] - times[i - 1]);
			
			zenithCol = lerp(colors[i - 1], colors[i], w);
			horizonCol = lerp(horizonColors[i - 1], horizonColors[i], w);
			groundCol = lerp(groundColors[i - 1], groundColors[i], w);
			mieScat = lerp(mieColor[i - 1].rgb, mieColor[i].rgb, w);
			mieScale = lerp(mieColor[i - 1].a, mieColor[i].a, w);
			dawnDuskMieFactor = smoothstep(-0.035, 0.035, dir.y);
  			dawnDuskTimeFactor = smoothstep(0.00, 0.05, w) * smoothstep(0.1, 0.35, w);
			
			break;
		}
	}

	

    float zenithBlend = saturate(pow(upPos, ZENITH_BLEND));
    float horizonBlend = saturate(pow(negatedMidPos, HORIZON_BLEND));
    float groundBlend = saturate(pow(negatedDownPos, GROUND_BLEND));

    zenithCol *= rayleigh * zenithBlend;
    horizonCol *= rayleigh * horizonBlend;
    groundCol *= rayleigh * groundBlend;

    float3 sky = zenithCol + horizonCol + groundCol;
	
    float4 sunColor = getSunColor(float4(0.0, 0.0, 0.0, 0.0)) ;
    ;

    float3 moonMieScatterColor = float3(0.00341, 0.00441, 0.01796) * sunColor.rgb;
     float sVoL = dot(dir, sunDir);
    float mVoL = dot(dir, -sunDir);

    float miePhase = HG(sVoL, mieScale);

    float3 mieColors = mieScat * miePhase * 0.7;

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

	float3 color = sky + finalMie;
	float skyLuminance = dot(color, 1.0);
	color = pow(color, 1.5);
	color *= skyLuminance / dot(color, 1.0);
    return color;
}

#endif // SKY_HLSL