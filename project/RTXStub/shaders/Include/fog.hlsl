#ifndef FOG_HLSL
#define FOG_HLSL

#include "sky.hlsl"
#include "shadows.hlsl"

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


void VL_FOG(float3 pos, float3 dir, float3 noise, float hitDist, float3 lightDir, inout float3 color )
{
    //calculate steps and distance
    const int volumetricSteps = 4;
    float maxDist = min(hitDist, 115);
    if (maxDist < 0.1) return;

    float stepSize = maxDist / (float)volumetricSteps;

    float4 sunlightColor =  getSunColor(float4(0.0, 0.0, 0.0, 0.0) ) * SUN_INTENSITY * 1.2;
    float3 ambientColor =  getSkyColor(0..xxx) * 1.2;

    float3 scattering = getScattering();
    float3 absorption = getMediaAbsorption();
    float3 extinction = getMediaPrimaryExtinction();
    
    bool inWater = g_view.cameraIsUnderWater;
    float3 mediaExtintion = calcTransmittance(maxDist, getMediaExtinction(MEDIA_TYPE_AIR).rgb); 
    extinction = mediaExtintion * 0.15;
    float3 totalScattering = 0;
    float3 transmittance = 1.0;

     float3 T = normalize(cross(
        abs(lightDir.z) < 0.999 ?
        float3(0,0,1) :
        float3(1,0,0),
        lightDir));

    float3 B = cross(lightDir, T);
  
    const float sunRadius = 0.0001; 
    float VdotL = dot(dir, lightDir);
    float phase = CS(0.65, VdotL) +  0.5 * CS(-0.12, VdotL);
    float uniformPhase = 1.0 / (4 * PI);
    float density = 1;
    for(int i = 0; i < volumetricSteps; i++)
    {
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
        shadowRay.Origin = rayPos + 1.0e-5 * float3(0,1,0);

        shadowRay.Direction = sampleDir;
        shadowRay.TMin = 0.0;
        shadowRay.TMax = 10000.0;

        ShadowPayload payload;
        TraceShadowRay(shadowRay, payload);

        float3 shadow = payload.transmission;
        //density = saturate(mad(rayPos.y, g_view.heightToFogScale, g_view.heightToFogBias));
        density = 0.01;
         float fMS = (1.0 - exp(-15.0 * density * (float)extinction)) * 1.0 / (float)extinction;
          fMS = lerp(fMS, fMS * 0.99, smoothstep(0.99, 1.0, fMS)); // this part by luna
        float3 directLight = sunlightColor.rgb * phase * shadow;
        float3 ambientLight = ambientColor * uniformPhase;
        float3 singleScattering = (directLight  + ambientLight)  * fMS;
        float3 sampleTransmittance = exp(-density * stepSize);
        float3  inscatter = transmittance * (singleScattering * (1.0 - clamp(sampleTransmittance,0,1))  / extinction);
        totalScattering += inscatter;
        transmittance *= sampleTransmittance;
    }
    color = color * transmittance + totalScattering;
  

}

#endif //FOG_HLSL

