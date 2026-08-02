#ifndef BRDF_HLSL
#define BRDF_HLSL

#include "sky.hlsl"
#include "shadows.hlsl"

#define BRDF_PI radians(180.0)


float DistributionGGX(float3 N, float3 H, float roughness) {
  float r = max(roughness, 0.001);
  float a = r * r;
  float a2 = a * a;
  float NdotH = max(dot(N, H), 1e-6);
  float NdotH2 = NdotH * NdotH;

  float num = a2;
  float denom = NdotH2 * (a2 - 1.0) + 1.0;
  denom = PI * denom * denom;

  return num / denom;
}

float GeometrySchlickGGX(float NdotV, float roughness) {
  float r = max(roughness, 0.001) + 1.0;
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



float BurleyFrostbite(float roughness, float n_dot_l, float n_dot_v, float v_dot_h)
{
    float energyBias = 0.5 * roughness;
    float energyFactor = lerp(1.0, 1.0 / 1.51, roughness);

    float FD90MinusOne = energyBias + 2.0 * v_dot_h * v_dot_h * roughness - 1.0f;
    float FDL = 1.0f + (FD90MinusOne * pow(1.0f - n_dot_l, 5.0f));
    float FDV = 1.0f + (FD90MinusOne * pow(1.0f - n_dot_v, 5.0f));

    return FDL * FDV * energyFactor;
}

//from Zombye
float3 SampleVNDFGGX(float3 V, float alpha, float2 u) {
    float3 Vh = safeNormalize(float3(alpha * V.x, alpha * V.y, V.z), float3(0, 0, 1));

    float lengthSq = Vh.x * Vh.x + Vh.y * Vh.y;
    float3 tangent = lengthSq > 0 ? float3(-Vh.y, Vh.x, 0) / sqrt(lengthSq) : float3(1, 0, 0);
    float3 bitangent = cross(Vh, tangent);

    float r = sqrt(u.x);
    float phi = 2.0 * PI * u.y;
    float t1 = r * cos(phi);
    float t2 = r * sin(phi);
    float s = 0.5 * (1.0 + Vh.z);
    t2 = (1.0 - s) * sqrt(max(0.0, 1.0 - t1 * t1)) + s * t2;

    float3 Nh = t1 * tangent
        + t2 * bitangent
        + sqrt(max(0.0, 1.0 - t1 * t1 - t2 * t2)) * Vh;

    return safeNormalize(float3(alpha * Nh.x, alpha * Nh.y, max(0.0, Nh.z)), float3(0, 0, 1));
}

float DisneyDiffuse(float NdotL, float NdotV, float LdotH, float roughness) {
    float energyBias = lerp(0.0, 0.5, roughness);
    float energyFactor = lerp(1.0, 1.0 / 1.51, roughness);
    float fd90 = energyBias + 2.0 * LdotH * LdotH * roughness;
    float lightScatter = 1.0 + (fd90 - 1.0) * pow(clamp(1.0 - NdotL, 0.0, 1.0), 5.0);
    float viewScatter = 1.0 + (fd90 - 1.0) * pow(clamp(1.0 - NdotV, 0.0, 1.0), 5.0);
    return (lightScatter * viewScatter * energyFactor / PI);
}

float3x3 tbnMatrix(float3 N) {
  float3 up = abs(N.z) < 0.999 ? float3(0.0, 0.0, 1.0) : float3(1.0, 0.0, 0.0);
  float3 T = normalize(cross(up, N));
  float3 B = cross(N, T);
  return float3x3(T, B, N);
}







float D_GGX(float NdotH, float roughness) {
    float r = max(roughness, 0.001);
    float a = r * r;
    float a2 = a * a;
    float NdotH2 = NdotH * NdotH;
    float num = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;
    return num / max(denom, 0.0000001);
}

float G_SchlickGGX(float NdotV, float roughness) {
    float r = max(roughness, 0.001) + 1.0;
    float k = (r * r) / 8.0;
    float num = NdotV;
    float denom = NdotV * (1.0 - k) + k;
    return num / denom;
}

float G1_SmithGGX(float NdotV, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotV2 = NdotV * NdotV;
    return (2.0 * NdotV) /
        max(NdotV + sqrt(a2 + (1.0 - a2) * NdotV2), 0.00001);
}

float PDF_GGXVNDF(float NdotV, float NdotH, float VdotH, float roughness) {
    float D = D_GGX(NdotH, roughness);
    float G1 = G1_SmithGGX(NdotV, roughness);

    return (D * G1 * max(0.0, VdotH)) / max(NdotV, 0.00001);
}

float PDF_GGX_Reflection(float NdotV, float NdotH, float VdotH, float roughness) {
    return PDF_GGXVNDF(NdotV, NdotH, VdotH, roughness) / (4.0 * max(VdotH, 0.0001));
}


float BRDF_Luminance(float3 linearColor)
{
    return dot(linearColor, float3(0.3, 0.59, 0.11));
}

#define BRDF_Pow5(x) pow(saturate(1.0 - x), 5.0)

float BRDF_F_Shadowing(float3 Rf0)
{
    return saturate(50.0 * BRDF_Luminance(Rf0));
}

float3 fresnelSchlick(float cosTheta, float3 F0) {
  float f = BRDF_F_Shadowing(F0);

    return F0 + (f - F0) * BRDF_Pow5(cosTheta);
}


float3 CorrectShadingNormal(
    float3 wo,
    float3 wi,
    float3 Ng,
    float3 Ns)
{
    float NoV  = saturate(dot(Ng, wo));
    float NoL  = saturate(dot(Ng, wi));

    float NsV  = saturate(dot(Ns, wo));
    float NsL  = saturate(dot(Ns, wi));

    float scaleV = NoV / max(NsV, 1e-4);
    float scaleL = NoL / max(NsL, 1e-4);

    return Ns * min(scaleV, scaleL);
}

float MISWeight(float pdfA, float pdfB)
{
    pdfA *= pdfA;
    pdfB *= pdfB;

    return pdfA / (pdfA + pdfB);
}

float PDF_CosineHemisphere(float NdotL) {
    return max(0.0, NdotL) / PI;
}

void BuildOrthonormalBasis(float3 N, out float3 T, out float3 B) {
    N = safeNormalize(N, float3(0, 1, 0));
    float3 up = abs(N.z) < 0.999 ? float3(0,0,1) : float3(1,0,0);
    T = safeNormalize(cross(up, N), float3(1, 0, 0));
    B = cross(N, T);
}


float3 SampleGGXMicrofacetNormal(float3 V, float3 N, float roughness, float2 u) {
    float alpha = max(roughness * roughness, 0.001);

    float3 T, B;
    BuildOrthonormalBasis(N, T, B);

    float3 Vlocal = float3(dot(V, T), dot(V, B), dot(V, N));
    float3 Hlocal = SampleVNDFGGX(Vlocal, alpha, u);
    float3 H = safeNormalize(Hlocal.x * T + Hlocal.y * B + Hlocal.z * N, N);
    return dot(H, V) >= 0.0 ? H : -H;
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