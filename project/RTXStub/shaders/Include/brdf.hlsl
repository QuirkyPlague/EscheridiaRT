#ifndef BRDF_HLSL
#define BRDF_HLSL

#include "sky.hlsl"
#include "shadows.hlsl"
//Basic cook torrance

float DistributionGGX(float3 N, float3 H, float roughness) {
  float a = roughness * roughness;
  float a2 = a * a;
  float NdotH = max(dot(N, H), 1e-6);
  float NdotH2 = NdotH * NdotH;

  float num = a2;
  float denom = NdotH2 * (a2 - 1.0) + 1.0;
  denom = PI * denom * denom;

  return num / denom;
}

float GeometrySchlickGGX(float NdotV, float roughness) {
  float r = roughness + 1.0;
  float k = r * r / 8.0;

  float num = NdotV;
  float denom = NdotV * (1.0 - k) + k;

  return num / denom;
}
float GeometrySmith(float3 N, float3 V, float3 L, float roughness) {
  float NdotV = max(dot(N, V), 1e-6);
  float NdotL = max(dot(N, L), 1e-6);
  float ggx2 = GeometrySchlickGGX(NdotV, roughness);
  float ggx1 = GeometrySchlickGGX(NdotL, roughness);

  return ggx1 * ggx2;
}

float3 fresnelSchlick(float cosTheta, float3 F0) {
  float f = pow(1.0 - cosTheta, 5.0);
  return f + F0 * (1.0 - f);
}

float BurleyFrostbite(float roughness, float n_dot_l, float n_dot_v, float v_dot_h)
{
    float energyBias = 0.5 * roughness;
    float energyFactor = lerp(1.0, 1.0 / 1.51, roughness);

    float FD90MinusOne = energyBias + 2.0 * v_dot_h * v_dot_h * roughness - 1.0f;
    float FDL = 1.0f + (FD90MinusOne * pow(1.0f - n_dot_l, 5.0f));
    float FDV = 1.0f + (FD90MinusOne * pow(1.0f - n_dot_v, 5.0f));

    return FDL * FDV * energyFactor;
}


float3 BRDF(float3 N, float3 V, float3 L, float3 sunColor, float3 indirect, float3 reflectedColor, SurfaceInfo surfaceInfo, float3 shadow, float3 GIRadiance) {
    float3 Lo = float3(0.0,0.0,0.0);
    float3 H = normalize(V + L);
    float dist = length(L);
    float attenuation = 1.0 / (dist * dist);
      float NdotL = max(dot(N, L), 0.0001);
    float NdotV = max(dot(N, V), 0.0001);
    float NdotH = max(dot(N, H),0.0001);
    float VdotH = max(dot(V, H),0.0001);
    float VdotL = max(dot(V,L),0.0001);

    
    float3 radiance = sunColor * attenuation * shadow;
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), surfaceInfo.color, surfaceInfo.metalness);
    
    float3 F = fresnelSchlick(max(dot(H, V), 0.0001), F0);
    float NDF = DistributionGGX(N, H, surfaceInfo.roughness);
    float G = GeometrySmith(N, V, L, surfaceInfo.roughness);

    float3 numerator = NDF * G * F ;
  float denominator = 4.0 * NdotV * NdotL + 0.0001;
    float3 specular = numerator / denominator;
  specular *= radiance;
  specular *= 6;
 

    float diff = BurleyFrostbite(surfaceInfo.roughness, NdotL,NdotV, VdotH);

    float3 kS = F;
    float3 kD = float3(1.0,1.0,1.0) - kS;
    kD *= (1.0 - surfaceInfo.metalness);
    
   // add to outgoing radiance Lo
  indirect *= ((1.0 - surfaceInfo.metalness) * surfaceInfo.color / PI) ;
  //GIRadiance *=  ((1.0 - surfaceInfo.metalness) * surfaceInfo.color / PI) ;
  float3 emission = surfaceInfo.color * (surfaceInfo.emissive * EMISSION_STENGTH);
  
  Lo = (kD * surfaceInfo.color ) * diff  * (radiance * NdotL)   ;
   Lo += emission;
  Lo = lerp(Lo, specular, F)  ;
    Lo = lerp(Lo, specular, surfaceInfo.metalness);

   
   
  
  return Lo;
}

float3 BRDF1(float3 N, float3 V, float3 L, float3 sunColor, float3 indirect, float3 color, float roughness, float metalness, float emissive, float3 shadow, float3 GIRadiance) {
    float3 Lo = float3(0.0,0.0,0.0);
    float3 H = normalize(V + L);
    float dist = length(L);
    float attenuation = 1.0 / (dist * dist);
      float NdotL = max(dot(N, L), 0.0001);
    float NdotV = max(dot(N, V), 0.0001);
    float NdotH = max(dot(N, H),0.0001);
    float VdotH = max(dot(V, H),0.0001);
    float VdotL = max(dot(V,L),0.0001);

    
    float3 radiance = sunColor * attenuation * shadow;
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), color, metalness);
    
    float3 F = fresnelSchlick(max(dot(H, V), 0.0001), F0);
    float NDF = DistributionGGX(N, H, roughness);
    float G = GeometrySmith(N, V, L, roughness);

    float3 numerator = NDF * G * F ;
  float denominator = 4.0 * NdotV * NdotL + 0.0001;
    float3 specular = numerator / denominator;
  specular *= radiance;
  specular *= 6;
 

    float diff = BurleyFrostbite(roughness, NdotL,NdotV, VdotH);

    float3 kS = F;
    float3 kD = float3(1.0,1.0,1.0) - kS;
    kD *= (1.0 - metalness);
    
   // add to outgoing radiance Lo
  indirect *= ((1.0 - metalness) * color / PI) ;
  //GIRadiance *=  ((1.0 - surfaceInfo.metalness) * surfaceInfo.color / PI) ;
  float3 emission = color* (emissive * EMISSION_STENGTH);
  
  Lo = (kD * color ) * diff  * (radiance * NdotL)   ;
   Lo += emission;
  Lo = lerp(Lo, specular, F) + indirect + GIRadiance ;
    Lo = lerp(Lo, specular, metalness);

   
   
  
  return Lo;
}

//from Zombye
float3 SampleVNDFGGX(
    float3 viewerDirection, // Direction towards viewer, +Z = surface normal
    float2 alpha,           // Roughness along X and Y
    float2 xy               // Uniform random numbers in [0,1)
)
{
    // Transform view direction into hemisphere configuration
    viewerDirection = normalize(
        float3(
            alpha.x * viewerDirection.x,
            alpha.y * viewerDirection.y,
            viewerDirection.z
        )
    );

    const float TAU = 6.28318530718f;

    // Sample a reflection direction on the hemisphere
    float phi = TAU * xy.x;

    float cosTheta =
        (1.0f - xy.y) * (1.0f + viewerDirection.z)
        - viewerDirection.z;

    float sinTheta = sqrt(saturate(1.0f - cosTheta * cosTheta));

    float3 reflected = float3(
        cos(phi) * sinTheta,
        sin(phi) * sinTheta,
        cosTheta
    );

    // Half-vector in hemisphere space
    float3 halfway = reflected + viewerDirection;

    // Transform back to ellipsoid configuration
    return normalize(
        float3(
            alpha.x * halfway.x,
            alpha.y * halfway.y,
            halfway.z
        )
    );
}

float3x3 tbnMatrix(float3 N) {
  float3 up = abs(N.z) < 0.999 ? float3(0.0, 0.0, 1.0) : float3(1.0, 0.0, 0.0);
  float3 T = normalize(cross(up, N));
  float3 B = cross(N, T);
  return float3x3(T, B, N);
}

float3 skyReflection(float3 dir, float3 normal, SurfaceInfo surfaceInfo, float3 noise)
{
  float3x3 tbn = tbnMatrix(normal);

  //view direction in tangent space
  float3 tangentView = mul((-dir), (tbn));

   float3 accumulated = float3(0.0,0.0,0.0);
  float3 skyDir = float3(0,0,0);
  for (uint i = 0u; i < uint(4); i++) {
float alpha = max(surfaceInfo.roughness * surfaceInfo.roughness, 0.001);

    float3 microFacit = SampleVNDFGGX(tangentView, float2(alpha, alpha), noise.xy);

    float3 tangentReflDir = reflect(-tangentView, microFacit);

    skyDir = normalize(mul(tangentReflDir, tbn));

    float3 skyCol = skyScattering1(skyDir);
   
    accumulated += skyCol ;

  }
  float3 sky = accumulated / float(4);

  float3 reflectDir = reflect(-dir, normal);
  float3 skyColor = sky;
  float3 F0 = lerp(float3(0.04, 0.04, 0.04), surfaceInfo.color, surfaceInfo.metalness);
  float3 F = fresnelSchlick(max(dot(-dir, normal), 0.0001), F0);
  float roughMask = step(0.0, surfaceInfo.roughness);
  skyColor *= lerp(1.0, max(exp(8.32 * (0.141 - surfaceInfo.roughness)), 0.0), roughMask);
  skyColor *= F;
  
  return skyColor;

}



float3 BRDFPoint(float3 N, float3 V, float3 L, float3 lightColor, SurfaceInfo surfaceInfo, float attenuation) {
  float3 Lo = float3(0.0,0.0,0.0);
    float3 H = normalize(V + L);

  
     float NdotL = max(dot(N, L), 0.0001);
    float NdotV = max(dot(N, V), 0.0001);
    float NdotH = max(dot(N, H),0.0001);
    float VdotH = max(dot(V, H),0.0001);
    float VdotL = max(dot(V,L),0.0001);

    
    float3 radiance = lightColor * attenuation;
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), surfaceInfo.color, surfaceInfo.metalness);
    
    float3 F = fresnelSchlick(max(dot(H, V), 0.0001), F0);
    float NDF = DistributionGGX(N, H, surfaceInfo.roughness);
    float G = GeometrySmith(N, V, L, surfaceInfo.roughness);

    float3 numerator = NDF * G * F ;
  float denominator = 4.0 * NdotV * NdotL + 0.0001;
    float3 specular = numerator / denominator;
  specular *= radiance * 6;
 

    float diff = BurleyFrostbite(surfaceInfo.roughness, NdotL,NdotV, VdotH);

    float3 kS = F;
    float3 kD = 1.0 - kS;
    kD *= (1.0 - surfaceInfo.metalness);

    //indirect *= kD;
   // add to outgoing radiance Lo
 
 
  Lo = (kD * surfaceInfo.color ) * diff * radiance * NdotL;
  Lo = lerp(Lo, specular, F);
    Lo = lerp(Lo, specular, surfaceInfo.metalness);
  
  return Lo;
}

float3 BRDFPoint1(float3 N, float3 V, float3 L, float3 lightColor, float roughness, float metalness, float attenuation, float3 color) {
  float3 Lo = float3(0.0,0.0,0.0);
    float3 H = normalize(V + L);

  
     float NdotL = max(dot(N, L), 0.0001);
    float NdotV = max(dot(N, V), 0.0001);
    float NdotH = max(dot(N, H),0.0001);
    float VdotH = max(dot(V, H),0.0001);
    float VdotL = max(dot(V,L),0.0001);

    
    float3 radiance = lightColor * attenuation;
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), color, metalness);
    
    float3 F = fresnelSchlick(max(dot(H, V), 0.0001), F0);
    float NDF = DistributionGGX(N, H, roughness);
    float G = GeometrySmith(N, V, L, roughness);

    float3 numerator = NDF * G * F ;
  float denominator = 4.0 * NdotV * NdotL + 0.0001;
    float3 specular = numerator / denominator;
  specular *= radiance * 6;
 

    float diff = BurleyFrostbite(roughness, NdotL,NdotV, VdotH);

    float3 kS = F;
    float3 kD = 1.0 - kS;
    kD *= (1.0 - metalness);

    //indirect *= kD;
   // add to outgoing radiance Lo
 
 
  Lo = (kD * color ) * diff * radiance * NdotL;
  Lo = lerp(Lo, specular, F);
    Lo = lerp(Lo, specular, metalness);
  
  return Lo;
}

float D_GGX(float NdotH, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH2 = NdotH * NdotH;
    float num = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;
    return num / max(denom, 0.0000001);
}

float G_SchlickGGX(float NdotV, float roughness) {
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;
    float num = NdotV;
    float denom = NdotV * (1.0 - k) + k;
    return num / denom;
}

// PDF for GGX VNDF sampling of the half vector
float PDF_GGXVNDF(float NdotV, float NdotH, float VdotH, float roughness) {
    float D = D_GGX(NdotH, roughness);
    float G1 = G_SchlickGGX(NdotV, roughness);

    return (D * G1 * max(0.0, VdotH)) / max(NdotV, 0.00001);
}

// PDF for standard GGX reflection
float PDF_GGX_Reflection(float NdotV, float NdotH, float VdotH, float roughness) {
    // The PDF of the visible half vector is: D * G1 * max(0, VdotH) / NdotV
    // To convert this to the PDF of the reflected direction, we divide by (4 * VdotH)
    return PDF_GGXVNDF(NdotV, NdotH, VdotH, roughness) / (4.0 * max(VdotH, 0.0001));
}

float PDF_CosineHemisphere(float NdotL) {
    return max(0.0, NdotL) / PI;
}

float3 FdezAgueraMultipleScattering(float NdotV, float NdotL, float roughness, float3 F0) {
    float a = roughness * roughness;

    // Analytical directional albedo E(x) approximations
    float E_v = saturate(1.0 - a * (1.0 - NdotV));
    float E_l = saturate(1.0 - a * (1.0 - NdotL));
    float E_avg = saturate(1.0 - a * 0.5);

    // Directional average of Fresnel
    float3 F_avg = F0 + (1.0 - F0) / 21.0;

    // Evaluate multiple scattering term
    float3 Fms = (F_avg * (1.0 - E_v) * (1.0 - E_l)) / (PI * (1.0 - F_avg * (1.0 - E_avg)) + 1e-5);

    return Fms;
}

float G_Smith(float NdotV, float NdotL, float roughness) {
    float ggx2 = G_SchlickGGX(NdotV, roughness);
    float ggx1 = G_SchlickGGX(NdotL, roughness);
    return ggx1 * ggx2;
}

#endif //BRDF_HLSL