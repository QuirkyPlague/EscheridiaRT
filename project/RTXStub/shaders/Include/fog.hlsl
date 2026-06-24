#ifndef FOG_HLSL
#define FOG_HLSL

#include "sky.hlsl"
#include "shadows.hlsl"
#include "tonemapping.hlsl"

float CS(float g, float costh) {
    return 3.0 *
    (1.0 - g * g) *
    (1.0 + costh * costh) /
    (4.0 *
        PI *
        2.0 *
        (2.0 + g * g) *
        pow(1.0 + g * g - 2.0 * g * costh, 3.0 / 2.0));
}

float phasefunc_CornetteShanks(float cosTheta, float g) {
    float k = 3.0 / (8.0 * PI) * (1.0 - g * g) / (2.0 + g * g);
    return k * (1.0 + pow(cosTheta, 2.0)) / pow(1.0 + g * g - 2.0 * g * cosTheta, 1.5);
}

float phasefunc_KleinNishinaE(float cosTheta, float e) {
    return e / (2.0 * PI * (e * (1.0 - cosTheta) + 1.0) * log(2.0 * e + 1.0));
}

float waterPhase(float cosTheta) {
    const float wKn = 0.99;
    const float gE = 20000.0;
    const float gCS = -0.6;
    return lerp(
        phasefunc_CornetteShanks(cosTheta, gCS),
        phasefunc_KleinNishinaE(cosTheta, gE),
        wKn);
}

void VL_FOG(float3 pos, float3 dir, float3 noise, float hitDist, float3 lightDir,  inout float3 color) {
    //calculate steps and distance
    const int volumetricSteps = VL_FOG_STEPS;
    float maxDist = min(hitDist, MAX_FOG_DISTANCE);

    float stepSize = maxDist / (float)volumetricSteps;

    float4 sunlightColor =  getSunColor(float4(0.0, 0.0, 0.0, 0.0)) * SUN_INTENSITY;
    sunlightColor.rgb *= luminance(sunlightColor.rgb * sunlightColor.a);
    float3 ambientColor =  getSkyColor(0..xxx) * 0.645;

    float3 scattering = getScattering() * 164.5;
    float3 absorption = getMediaAbsorption();
    float3 extinction = getMediaPrimaryExtinction();

    bool inWater = g_view.cameraIsUnderWater;
    float3 mediaExtintion = inWater ?  getMediaExtinction(MEDIA_TYPE_WATER).rgb : getMediaExtinction(MEDIA_TYPE_AIR).rgb * 17; 
    extinction = (mediaExtintion);

    float3 totalScattering = 0;
    float3 transmittance = 1.0;

    float3 T = normalize(cross(
            abs(lightDir.z) < 0.999 ?
            float3(0,0,1) :
            float3(1,0,0),
            lightDir));

    float3 B = cross(lightDir, T);

    const float sunRadius = SUN_RADIUS; 
    float VdotL = dot(dir, lightDir);
    float phase = inWater ? waterPhase(VdotL)  : CS(0.65, VdotL) +  0.5 * CS(-0.12, VdotL);
    float uniformPhase = 1.0 / (4 * PI);
    float density = inWater ? 0.07 : 0.023;
    for(int i = 0; i < volumetricSteps; i++) {
        float increment = (float(i) + noise.x) * stepSize;
        float3 rayPos = pos + dir * increment;
        float2 Xi = frac(noise.xy + float2(
                i * 0.61803398875,
                i * 0.38196601125));

        float r = sunRadius * sqrt(Xi.x);
        float theta = 2.0 * PI * Xi.y;

        float2 disk = r * float2(
            cos(theta),
            sin(theta));

        float3 sampleDir = normalize(
            lightDir +
            disk.x * T +
            disk.y * B);

        RayDesc shadowRay;
        shadowRay.Origin = rayPos + 1.0e-3 * float3(0,1,0);

        shadowRay.Direction = sampleDir;
        shadowRay.TMin = 0.0;
        shadowRay.TMax = 10000.0;

        ShadowPayload payload;
        TraceShadowRay(shadowRay, payload);

        float3 shadow = payload.transmission;

        float fMS = (1.0 - exp(-15.0 * density * (float)extinction)) * 1.0 / (float)extinction;
        fMS = lerp(fMS, fMS * 0.99, smoothstep(0.99, 1.0, fMS)); // this part by luna
        float3 directLight = ((sunlightColor.rgb * scattering)) * phase * shadow;
        float3 ambientLight = ((ambientColor)) * uniformPhase;
        float3 singleScattering = (directLight  + ambientLight)  * fMS;
        float3 sampleTransmittance = calcTransmittance(stepSize, extinction * density);
        float3  inscatter = transmittance * (singleScattering * (1.0 - clamp(sampleTransmittance,0,1))  / extinction);
        totalScattering += inscatter;
        transmittance *= sampleTransmittance;
    }
    color = color * transmittance + totalScattering;
}

#endif //FOG_HLSL

