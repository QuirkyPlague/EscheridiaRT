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
        float sunRadius = inEnd ? END_SUN_DISC_SIZE : SUN_DISC_RADIUS;

        float theta = acos(clamp(cosThetaSun, -1.0, 1.0));
        float radial = theta / max(sunRadius, 1e-5);
        float edgeWidth = inEnd ? 0.08 : SUN_DISC_EDGE_SOFTNESS;
        float sun = 1.0 - smoothstep(1.0 - edgeWidth, 1.0, radial);
        float discRadius = saturate(radial);
        float discMu = sqrt(saturate(1.0 - discRadius * discRadius));
        float limbDarkening = lerp(
            1.0 - (inEnd ? 0.6 : SUN_DISC_LIMB_DARKENING),
            1.0,
            discMu);
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

        float3 fullSun = inEnd ? sun * limbDarkening * sunColor * 15.0 + twinSunDisc : sun * limbDarkening * sunColor * SUN_DISC_INTENSITY * sunHeightFactor;
        
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
            float rayleigh = inEnd ? Rayleigh(VoL) * END_RAYLEIGH_MULT  : Rayleigh(VoL) * RAYLEIGH_MULT;


            float upPos = saturate(dir.y);
            float downPos = clamp(dir.y, -1.0, 0.0);
            float negatedDownPos = -1.0 * downPos;
            float midPos = upPos + negatedDownPos;
            float negatedMidPos = 1.0 - midPos;
            //rain
            const float3 rainZenCol = float3(0.4784, 0.4784, 0.4784) * 15;
            const float3 rainHorCol = float3(0.7059, 0.7569, 0.7961) * 15;
            const float3 rainGrndCol = float3(0.1569, 0.1922, 0.2314) * 15;

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
                0.95,
                0.95,
                0.45,
                0.3,
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

            zenithCol = lerp(zenithCol, rainZenCol * rainIntensityShift, getBiomeAdjustedRainLevel());
            horizonCol = lerp(horizonCol, rainHorCol * rainIntensityShift,  getBiomeAdjustedRainLevel());
            groundCol = lerp(groundCol, rainGrndCol * rainIntensityShift,  getBiomeAdjustedRainLevel());

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
            float3 mieColors = sunColor.rgb * mieScat * miePhase * 0.7 * SKY_MIE_SCATTERING_STRENGTH;
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
            float skyLuminance = dot(sky, 1.0);
            /*
            sky = pow(sky, 1.5);
            sky *= skyLuminance / dot(sky, 1.0);
            */
            float3 color =  sky + finalMie;
            color = inEnd ? lerp(color, endSkyColor(dir) * ORIGINAL_END_SKY_INTENSITY, 0.25)  : color;
            
            return color + sun;
        #endif
    }


    static const float3x3 matrix_xyz_to_rec2020 = transpose(float3x3(1.71665118797, -0.355670783776, -0.253366281374, -0.666684351832, 1.61648123664, 0.015768545814, 0.017639857445, -0.042770613258, 0.942103121235));
    static const float  EARTH_RADIUS = 6360.0f;
    static const float  ATM_RADIUS   = 6420.0f;
    static const float  H_RAYLEIGH   = 8.0f;
    static const float  H_MIE        = 1.2f;

    // Scattering coefficients

    static const float3 BETA_RAYLEIGH = float3(5.202f, 13.558f, 33.100f) * 1e-3f;
    static const float3 END_RAYLEIGH = float3(4.32, 0.931, 9.56) * 1e-4;

    static const float  BETA_MIE_S    = 15.996f * 1e-3f;
    static const float  BETA_MIE_E    = 22.440f * 1e-3f;

    // Ozone absorption (Chappuis band) - essential to Hillaire's realistic coloration
    static const float3 BETA_OZONE_ABSORPTION = (float3(0.850f, 1.881f, 0.085f)) * 1e-3;

    bool RaySphereIntersect(float3 rayOrig, float3 rayDir, float sphereRad, out float t0, out float t1)
    {
        t0 = 0.0f; t1 = 0.0f;
        float b = dot(rayOrig, rayDir);
        float c = dot(rayOrig, rayOrig) - (sphereRad * sphereRad);
        float d = b * b - c;
        if (d < 0.0f) return false;
        float sqrtD = sqrt(max(d, 0.0f));
        t0 = -b - sqrtD;
        t1 = -b + sqrtD;
        return true;
    }

    // Evaluates atmospheric layers at given altitude
    void GetLayerDensities(float3 pos, out float dRayleigh, out float dMie, out float dOzone)
    {
        float alt = max(length(pos) - EARTH_RADIUS, 0.0f);
        
        dRayleigh = exp(-alt / H_RAYLEIGH);
        dMie      = exp(-alt / H_MIE);
        
        // Ozone sits in a tent-layer centered around 25 km altitude
        dOzone    = max(0.0001f, 1.0f - abs(alt - 25.0f) / 15.0f);
    }

    // Extinction coefficient at point x
    float3 GetExtinction(float dR, float dM, float dO)
    {
        return ((inEnd? END_RAYLEIGH : BETA_RAYLEIGH) * dR) + (BETA_MIE_E * dM) + (BETA_OZONE_ABSORPTION * dO);
    }

    // Low-sample direct transmittance (replaces Hillaire's Transmittance LUT)
    float3 EvaluateAnalyticTransmittance(float3 pos, float3 sunDir, float perPixelNoise)
    {
        sunDir = safeNormalize(sunDir, float3(0.0f, 1.0f, 0.0f));
        perPixelNoise = saturate(perPixelNoise);

        float t0, t1;
        if (!RaySphereIntersect(pos, sunDir, ATM_RADIUS, t0, t1) || t1 <= 0.0f)
        return float3(1, 1, 1);

        float groundT0, groundT1;
        if (RaySphereIntersect(pos, sunDir, EARTH_RADIUS, groundT0, groundT1) && groundT0 > 0.0f)
        {
            t1 = min(t1, groundT0);
        }
        if (t1 <= 0.0f) return float3(1, 1, 1);
        
        const int SUN_STEPS = 4; 
        float stepLen = t1 / (float)SUN_STEPS;
        float3 accumOpticalDepth = float3(0, 0, 0);
        
        for (int i = 0; i < SUN_STEPS; ++i)
        {
            // Use the perPixelNoise to jitter the light ray sample points as well
            float stepFraction = (float)i + perPixelNoise;
            float3 sPos = pos + sunDir * (stepLen * stepFraction);
            
            float dR, dM, dO;
            GetLayerDensities(sPos, dR, dM, dO);
            accumOpticalDepth += GetExtinction(dR, dM, dO) * stepLen;
        }
        return exp(-accumOpticalDepth);
    }

    // Phase Functions
    float RayleighPhase(float cosTheta)
    {
        return (3.0f / (16.0f * 3.14159265f)) * (1.0f + cosTheta * cosTheta);
    }

    float CornetteShanksMiePhase(float cosTheta, float g = 0.8f)
    {
        float g2 = g * g;
        float num = 3.0f * (1.0f - g2) * (1.0f + cosTheta * cosTheta);
        float mieBase = 1.0f + g2 - 2.0f * g * cosTheta;
        float denom = 8.0f * 3.14159265f * (2.0f + g2) * pow(max(mieBase, 1e-6f), 1.5f);
        return num / denom;
    }

    float3 ProceduralStars(float3 rayDir, float nightFactor)
    {
        if (rayDir.y <= 0.0f || nightFactor <= 0.0f) return 0.0f;

        const float STAR_LONGITUDE_CELLS = 756.0f;
        const float STAR_LATITUDE_CELLS = 256.0f;
        float3 dir = normalize(rayDir);
        float2 sphericalUv = float2(
            atan2(dir.z, dir.x) * (0.5f / PI) + 0.5f,
            asin(clamp(dir.y, -1.0f, 1.0f)) / PI + 0.5f);
        float2 cellPosition = sphericalUv * float2(STAR_LONGITUDE_CELLS, STAR_LATITUDE_CELLS);
        uint2 cell = uint2(floor(cellPosition));
        float2 cellUv = frac(cellPosition) - 0.5f;
        uint seed = PCG_Hash(uint3(cell, 0x51A7u));
        float starChance = HashToFloat(seed);

        if (starChance > 0.075f) return 0.0f;

        float2 starOffset = float2(
            HashToFloat(PCG_Hash(uint3(seed, 0x13u, 0x71u))) - 0.5f,
            HashToFloat(PCG_Hash(uint3(seed, 0x37u, 0xB3u))) - 0.5f);
        float distanceFromStar = length(cellUv - starOffset);
        float size = lerp(0.012f, 0.075f, HashToFloat(PCG_Hash(uint3(seed, 0x55u, 0x91u))));
        float star = 1.0f - smoothstep(size * 0.3f, size, distanceFromStar);
        float brightness = lerp(0.25f, 1.0f, HashToFloat(PCG_Hash(uint3(seed, 0xA1u, 0xC7u))));
        float colorMix = HashToFloat(PCG_Hash(uint3(seed, 0xD3u, 0xE9u)));
        float3 starColor = colorMix < 0.5f
            ? lerp(float3(1.0f, 0.78f, 0.58f), float3(1.0f, 0.95f, 0.82f), colorMix * 2.0f)
            : lerp(float3(1.0f, 0.95f, 0.82f), float3(0.68f, 0.78f, 1.0f), (colorMix - 0.5f) * 2.0f);

        return starColor * star * brightness * nightFactor * 2.0f;
    }


    float3 RenderHillaireAtmosphereLUTless(
    float3 cameraPosKm, 
    float3 rayDir, 
    float3 sunDir, 
    float  sunIntensity,
    PathRNG rng)
    {
        if (any(cameraPosKm != cameraPosKm) ||
            any(rayDir != rayDir) ||
            any(sunDir != sunDir) ||
            any(abs(cameraPosKm) > 1000000.0f) ||
            any(abs(rayDir) > 1000000.0f) ||
            any(abs(sunDir) > 1000000.0f) ||
            sunIntensity != sunIntensity ||
            abs(sunIntensity) > 1000000.0f)
        {
            return float3(0.0f, 0.0f, 0.0f);
        }


        float3 rayOrig = cameraPosKm + float3(0.0f, EARTH_RADIUS + 0.001f, 0.0f);
        
        float t0, t1;
        if (!RaySphereIntersect(rayOrig, rayDir, ATM_RADIUS, t0, t1) || t1 <= 0.0f)
        return float3(0.0, 0.0, 0.0);

        t0 = max(t0, 0.0f);

        float g0, g1;
        bool hitGround = (RaySphereIntersect(rayOrig, rayDir, EARTH_RADIUS, g0, g1) && g0 > 0.0f);
        if (hitGround)
        {
            t1 = min(t1, g0);
        }

        const int SAMPLE_STEPS = 8;
        float rayDistance = t1 - t0;
        if (rayDistance <= 0.0001f)
        {
            return float3(0.0f, 0.0f, 0.0f);
        }

        float stepLen = rayDistance / (float)SAMPLE_STEPS;
     
        float3 totalLuminance = float3(0, 0, 0);
        float3 throughput = float3(1, 1, 1);
        
        float3 rayleighColor =  inEnd ? END_RAYLEIGH : BETA_RAYLEIGH;

        
        float cosTheta = dot(rayDir, sunDir);
        float pR = RayleighPhase(cosTheta) * (inEnd ? END_RAYLEIGH_MULT : RAYLEIGH_MULT);
        float pM = CornetteShanksMiePhase(cosTheta, SKY_MIE_FORWARD_G);
        float3 mieSunColor = inEnd
            ? END_SUN_COLOR
            : getSunColor(float4(0.0f, 0.0f, 0.0f, 0.0f)).rgb;
        float3 multiscatterFactor = (rayleighColor * 1.2f) * 0.35f;

        const float3 horizonColors[7] = {
            NOON_HORIZON_COL,
            DAY_HORIZON_COL,
            DAY_HORIZON_COL,
            SUNRISE_HORIZON_COL,
            SUNSET_HORIZON_COL * 0.1f,
            SUNSET_HORIZON_COL * 0.025f,
            NIGHT_HORIZON_COL * NIGHT_INTENSITY
        };
        const float3 groundColors[7] = {
            NOON_GROUND_COL,
            DAY_GROUND_COL,
            DAY_GROUND_COL,
            SUNRISE_GROUND_COL,
            SUNSET_GROUND_COL * 0.1f,
            SUNSET_GROUND_COL * 0.01f,
            NIGHT_GROUND_COL * NIGHT_INTENSITY
        };
        const float skyTimes[7] = {
            0.0000000000,
            0.1920399368,
            0.3466664553,
            0.4309642911,
            0.4746705294,
            0.5193186402,
            0.5621
        };

        float3 horizonColor = NIGHT_HORIZON_COL * NIGHT_INTENSITY;
        float3 groundColor = NIGHT_GROUND_COL * NIGHT_INTENSITY;
        if (inEnd)
        {
            horizonColor = END_HORIZON_COLOR;
            groundColor = END_GROUND_COLOR;
        }
        else
        {
            [unroll] for (int i = 1; i < 7; ++i)
            {
                if (g_view.skyTextureW >= skyTimes[i - 1] && g_view.skyTextureW < skyTimes[i])
                {
                    float w = (g_view.skyTextureW - skyTimes[i - 1]) / (skyTimes[i] - skyTimes[i - 1]);
                    horizonColor = lerp(horizonColors[i - 1], horizonColors[i], w);
                    groundColor = lerp(groundColors[i - 1], groundColors[i], w);
                    break;
                }
            }
        }

        float dither = NextFloat(rng);

        for (int i = 0; i < SAMPLE_STEPS; ++i)
        {
            
            float stepFraction = (float)i + NextFloat(rng);
            
            float3 samplePos = rayOrig + rayDir * (t0 + stepLen * stepFraction);
            
            
            float dR, dM, dO;
            GetLayerDensities(samplePos, dR, dM, dO);
            
            float3 extinction = GetExtinction(dR, dM, dO);
            float3 stepTransmittance = exp(-extinction * stepLen);
            
            // Soft horizon shadow math
            float3 lightRayOrig = samplePos;
            float3 lightRayDir  = sunDir;
            float tClosest = max(0.0f, -dot(lightRayOrig, lightRayDir));
            float3 closestPoint = lightRayOrig + lightRayDir * tClosest;
            float rayCenterDist = length(closestPoint);

            float shadowFactor = 1.0f;
            if (dot(samplePos, sunDir) < 0.0f) 
            {
                float horizonThicknessKm = 15.0f; 
                shadowFactor = saturate((rayCenterDist - (EARTH_RADIUS - horizonThicknessKm)) / horizonThicknessKm);
                shadowFactor *= shadowFactor; 
            }

            float3 sunTransmittance = EvaluateAnalyticTransmittance(samplePos, sunDir, dither) * shadowFactor;
            
            // Lighting logic
            float3 mieScattering =
                dM * BETA_MIE_S * pM * SKY_MIE_SCATTERING_STRENGTH * mieSunColor;
            float3 directScattering = (
                dR * rayleighColor * pR +
                mieScattering) * sunTransmittance;
            float3 multiScattering = multiscatterFactor * (dR + dM) * saturate(sunTransmittance + 0.25f);
            float3 stepLuminance = (directScattering + multiScattering) * sunIntensity;
            
            float3 safeExtinction = max(extinction, float3(1e-4f, 1e-4f, 1e-4f));
            float3 integScattering = (stepLuminance - stepLuminance * stepTransmittance) / safeExtinction;
            totalLuminance += throughput * integScattering;
            
            throughput *= stepTransmittance;
        }
        
    

        float horizonMask = exp(-abs(rayDir.y) * SKY_HORIZON_WIDTH);
        totalLuminance += horizonColor * horizonMask * max(sunIntensity, 0.05f) * SKY_HORIZON_STRENGTH * 0.05f;

        float skyLuminance = dot(totalLuminance, float3(0.2126f, 0.7152f, 0.0722f));
        totalLuminance = lerp(skyLuminance.xxx, totalLuminance, SKY_SATURATION);
    //totalLuminance = inEnd ? lerp(totalLuminance, endSkyColor(rayDir) * ORIGINAL_END_SKY_INTENSITY, 0.25)  : totalLuminance;
        float3 trueSunDir = getTrueDirectionToSun();
        float nightFactor = smoothstep(0.12f, -0.08f, trueSunDir.y);
        totalLuminance += ProceduralStars(rayDir, nightFactor);
        float3 sun = getSun(rayDir);
        return totalLuminance + sun;
    }




#endif // SKY_HLSL