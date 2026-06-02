#ifndef BRDF_HLSL
#define BRDF_HLSL

#include "sky.hlsl"

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


float3 BRDF(float3 N, float3 V, float3 L, float3 sunColor, float3 indirect, float3 reflectedColor, SurfaceInfo surfaceInfo, float3 shadow) {
    float3 Lo = float3(0.0,0.0,0.0);
    float3 H = normalize(V + L);
    float dist = length(L);
    float attenuation = 1.0 / (dist * dist);
     float NdotL = saturate(dot(N, L));
    float NdotV = saturate(dot(N, V));
    float NdotH = saturate(dot(N, H));
    float VdotH = saturate(dot(V, H));
    float VdotL = saturate(dot(V,L));

    
    float3 radiance = sunColor * attenuation * shadow;
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), surfaceInfo.color * 14, surfaceInfo.metalness);
    
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
    float3 kD = 1.0 - kS;
    kD *= (1.0 - surfaceInfo.metalness);
    //indirect *= kD;
   // add to outgoing radiance Lo
  indirect *= surfaceInfo.color * (1.0 - surfaceInfo.metalness);
 
  Lo = (kD * surfaceInfo.color ) * diff * radiance * NdotL;
  Lo = lerp(Lo, specular, F) + indirect;
    Lo = lerp(Lo, specular, surfaceInfo.metalness);
     Lo += reflectedColor;
    Lo += (surfaceInfo.color * (surfaceInfo.emissive * 15.0));
   
  
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

float3 BRDFPoint(float3 N, float3 V, float3 L, float3 sunColor, float3 indirect, SurfaceInfo surfaceInfo) {
  float3 Lo = float3(0.0,0.0,0.0);
    float3 H = normalize(V + L);
    float dist = length(L);
    float attenuation = 1.0 / (dist * dist);
     float NdotL = saturate(dot(N, L));
    float NdotV = saturate(dot(N, V));
    float NdotH = saturate(dot(N, H));
    float VdotH = saturate(dot(V, H));
    float VdotL = saturate(dot(V,L));

    
    float3 radiance = sunColor * attenuation;
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), surfaceInfo.color * 14, surfaceInfo.metalness);
    
    float3 F = fresnelSchlick(max(dot(H, V), 0.0001), F0);
    float NDF = DistributionGGX(N, H, surfaceInfo.roughness);
    float G = GeometrySmith(N, V, L, surfaceInfo.roughness);

    float3 numerator = NDF * G * F ;
  float denominator = 4.0 * NdotV * NdotL + 0.0001;
    float3 specular = numerator / denominator;
  specular *= radiance;
 

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

#endif //BRDF_HLSL