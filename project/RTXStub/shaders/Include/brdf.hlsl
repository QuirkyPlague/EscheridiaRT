#ifndef BRDF_HLSL
    #define BRDF_HLSL

    #include "sky.hlsl"
    #include "shadows.hlsl"

    #define BRDF_PI radians(180.0)
    #define BRDF_FIX 1e-10

    struct ShadingFrame
    {
        float3 T;
        float3 B;
        float3 Ng;
        float3 Ns;
    };

    #define BRDF_Pow5(x) pow(saturate(1.0 - x), 5.0)

    float BRDF_Luminance(float3 linearColor)
    {
        return dot(linearColor, float3(0.3, 0.59, 0.11));
    }

    // UE4: anything less than 2% is physically impossible and is instead considered to be shadowing
    float BRDF_F_Shadowing(float3 Rf0)
    {
        return saturate(50.0 * BRDF_Luminance(Rf0));
    }

    float3 fresnelSchlick(float cosTheta, float3 F0) {
        float f = BRDF_F_Shadowing(F0);

        return F0 + (f - F0) * BRDF_Pow5(cosTheta);
    }



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

    
    

    float G_Smith(float NdotV, float NdotL, float roughness) {
        float ggx2 = G1_SmithGGX(NdotV, roughness);
        float ggx1 = G1_SmithGGX(NdotL, roughness);
        return ggx1 * ggx2;
    }


    // General thesis from https://jo.dreggn.org/home/2017_normalmap.pdf 
    // Unused and likely incomplete
    float G1_TangentFacet(float3 wi,float3 wm,float3 wg,float3 wp,float3 wt)
    {
        float H = step(0.0, dot(wi, wm));
        float pDotG = max(dot(wp, wg), 1e-5);
        float tangentLength = sqrt(max(1.0 - pDotG * pDotG, 0.0));
        float ap = max(dot(wi, wp), 0.0) / pDotG;
        float at = max(dot(wi, wt), 0.0) / max(tangentLength, 1e-5);
        float projectedArea = ap + at;
        float visibility =min(1.0,max(dot(wi, wg), 0.0) / max(projectedArea, 1e-5));
        return H * visibility;
    }

    // Also from https://jo.dreggn.org/home/2017_normalmap.pdf 
    float3 EvaluateFacetBRDF(float3 wi,float3 wo,float3 wm,float3 F0,float roughness)
    {
        float NoL = max(dot(wm, wi), 0.0001);
        float NoV = max(dot(wm, wo), 0.0001);

        float3 H = safeNormalize(wi + wo, wm);

        float NoH = max(dot(wm, H), 0.0001);
        float VoH = max(dot(wo, H), 0.0001);

        float3 F = fresnelSchlick(VoH, F0);
        float D = D_GGX(NoH, roughness);
        float G = G_Smith(NoV, NoL, roughness);

        return (F * D * G) /
        max(4.0 * NoV * NoL, 1e-6);
    }

    float PDF_GGXVNDF(float NdotV, float NdotH, float VdotH, float roughness) {
        float D = D_GGX(NdotH, roughness);
        float G1 = G1_SmithGGX(NdotV, roughness);

        return (D * G1 * max(0.0, VdotH)) / max(NdotV, 0.00001);
    }

    float PDF_GGX_Reflection(float NdotV, float NdotH, float VdotH, float roughness) {
        return PDF_GGXVNDF(NdotV, NdotH, VdotH, roughness) / (4.0 * max(VdotH, 0.0001));
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



    // the following code is taken from https://arxiv.org/pdf/2410.18026 
    // EON: A practical energy-preserving rough diffuse BRDF
    static const float rcppi = 1.0f / PI;
    static const float constant1_FON = 0.5f - 2.0f / (3.0f * PI);
    static const float constant2_FON = 2.0f / 3.0f - 28.0f / (15.0f * PI);

    float E_FON_exact(float mu, float r)
    {
        float AF = 1.0f / (1.0f + constant1_FON * r); // FON A coefficient
        float BF = r * AF; // FON B coefficient
        float Si = sqrt(1.0f - (mu * mu));
        float G = Si * (acos(mu) - Si * mu)
        + (2.0f / 3.0f) * ((Si / mu) * (1.0f - (Si * Si * Si)) - Si);
        return AF + (BF * rcppi) * G;
    }
    float E_FON_approx(float mu, float r)
    {
        float mucomp = 1.0f - mu;
        const float g1 = 0.0571085289f;
        const float g2 = 0.491881867f;
        const float g3 = -0.332181442f;
        const float g4 = 0.0714429953f;
        float GoverPi = mucomp * (g1 + mucomp * (g2 + mucomp * (g3 + mucomp * g4)));
        return (1.0f + r * GoverPi) / (1.0f + constant1_FON * r);
    }
    // Evaluates EON BRDF value, given inputs:
    // rho = single-scattering albedo parameter
    // r = roughness in [0, 1]
    // exact = flag to select exact or fast approx. version
    // Note that this implementation assumes throughout that the directions are
    // specified in a local space where the z-direction aligns with the surface normal.
    float3 f_EON(float3 rho, float r, float3 wi_local, float3 wo_local, bool exact)
    {
        float mu_i = wi_local.z; // Input angle cos
        float mu_o = wo_local.z; // Output angle cos
        float s = dot(wi_local, wo_local) - mu_i * mu_o; // QON s term
        float sovertF = s > 0.0f ? s / max(mu_i, mu_o) : s; // FON s/t
        float AF = 1.0f / (1.0f + constant1_FON * r); // FON A coefficient
        float3 f_ss = (rho * rcppi) * AF * (1.0f + r * sovertF); // Single-scatter lobe
        float EFo = exact ? E_FON_exact(mu_o, r): // FON wo albedo (exact)
        E_FON_approx(mu_o, r); // FON wo albedo (approx)
        float EFi = exact ? E_FON_exact(mu_i, r): // FON wi albedo (exact)
        E_FON_approx(mu_i, r); // FON wi albedo (approx)
        float avgEF = AF * (1.0f + constant2_FON * r); // Average albedo
        float3 rho_ms = (rho * rho) * avgEF / (float3(1.0f.xxx) - rho * (1.0f - avgEF));
        const float eps = 1.0e-7f;
        float3 f_ms = (rho_ms * rcppi) * max(eps, 1.0f - EFo) // Multi-scatter lobe
        * max(eps, 1.0f - EFi)
        / max(eps, 1.0f - avgEF);
        return f_ss + f_ms;
    }
    // Computes EON directional albedo:
    float3 E_EON(float3 rho, float r, float3 wi_local, bool exact)
    {
        float mu_i = wi_local.z; // Input angle cos
        float AF = 1.0f / (1.0f + constant1_FON * r); // FON A coefficient
        float EF = exact ? E_FON_exact(mu_i, r): // FON wi albedo (exact)
        E_FON_approx(mu_i, r); // FON wi albedo (approx)
        float avgEF = AF * (1.0f + constant2_FON * r); // Average albedo
        float3 rho_ms = (rho * rho) * avgEF / (float3(1.0f.xxx) - rho * (1.0f - avgEF));
        return rho * EF + rho_ms * (1.0f - EF);
    }

    void ltc_coeffs(float mu, float r,
    out float a, out float b, out float c, out float d)
    {
        a = 1.0f + r*(0.303392f + (-0.518982f + 0.111709f*mu)*mu + (-0.276266f + 0.335918f*mu)*r);
        b = r*(-1.16407f + 1.15859f*mu + (0.150815f - 0.150105f*mu)*r)/(mu*mu*mu - 1.43545f);
        c = 1.0f + r*(0.20013f + (-0.506373f + 0.261777f*mu)*mu);
        d = r*(0.540852f + (-1.01625f + 0.475392f*mu)*mu)/(-1.0743f + (0.0725628f + mu)*mu);
    }
    float3x3 orthonormal_basis_ltc(float3 w)
    {
        float lenSqr = dot(w.xy, w.xy);

        float3 X = lenSqr > 0.0f ? float3(w.x, w.y, 0.0f) * rsqrt(lenSqr) : float3(1.0f, 0.0f, 0.0f);

        float3 Y = float3(-X.y, X.x, 0.0f);

        return float3x3(X, Y, float3(0.0f, 0.0f, 1.0f));
    }
    float4 cltc_sample(float3 wo_local, float r, float u1, float u2)
    {
        float a, b, c, d;
        ltc_coeffs(wo_local.z, r, a, b, c, d);

        float R = sqrt(u1);
        float phi = 2.0f * PI * u2;

        float x = R * cos(phi);
        float y = R * sin(phi);

        float vz = 1.0f / sqrt(d * d + 1.0f);
        float s = 0.5f * (1.0f + vz);

        x = -lerp(sqrt(1.0f - y * y), x, s);

        float3 wh = float3(x, y, sqrt(max(1.0f - (x * x + y * y), 0.0f)));

        float pdf_wh = wh.z / (PI * s);

        float3 wi = float3(a * wh.x + b * wh.z, c * wh.y, d * wh.x + wh.z);

        float len = length(wi);
        float detM = c * (a - b * d);

        float pdf_wi = pdf_wh * len * len * len / detM;

        float3x3 fromLTC = orthonormal_basis_ltc(wo_local);

        // Matches: fromLTC * wi
        wi = normalize(mul(fromLTC, wi));

        return float4(wi, pdf_wi);
    }
    float cltc_pdf(float3 wo_local,float3 wi_local, float r)
    {
        float3x3 toLTC = transpose(orthonormal_basis_ltc(wo_local));

        // Matches: toLTC * wi_local
        float3 wi = mul(toLTC, wi_local);

        float a, b, c, d;
        ltc_coeffs(wo_local.z, r, a, b, c, d);

        float detM = c * (a - b * d);

        float3 wh = float3(c * (wi.x - b * wi.z), (a - b * d) * wi.y, -c * (d * wi.x - a * wi.z));

        float lenSqr = dot(wh, wh);

        float vz = 1.0f / sqrt(d * d + 1.0f);
        float s = 0.5f * (1.0f + vz);

        float pdf = detM * detM /(lenSqr * lenSqr) *max(wh.z, 0.0f) /(PI * s);

        return pdf;
    }

    float3 uniform_lobe_sample(float u1, float u2)
    {
        float sinTheta = sqrt(1.0f - u1*u1); float phi = 2.0f * PI * u2;
        return float3(sinTheta * cos(phi), sinTheta * sin(phi), u1);
    }
    // Samples (via CLTC) from EON BRDF, given inputs:
    // rho = single-scattering albedo parameter
    // wo_local = direction of outgoing ray (directed away from vertex)
    // r = roughness in [0, 1]
    // u1, u2 = IID uniform random numbers in [0,1]
    // Returns vec4(vec3(wi_local), pdf)
    float4 sample_EON(float3 wo_local, float r, float u1, float u2)
    {
        float mu = wo_local.z;
        float P_u = pow(r, 0.1f) * (0.162925f + (-0.372058f + (0.538233f - 0.290822f*mu)*mu)*mu);
        float P_c = 1.0f - P_u; // Probability of CLTC sample
        float4 wi; float pdf_c;
        if (u1 <= P_u) {
            u1 = u1 / P_u;
            wi.rgb = uniform_lobe_sample(u1, u2); // Sample wi from uniform lobe
        pdf_c = cltc_pdf(wo_local, wi.xyz, r); } // Evaluate CLTC PDF at wi
        else {
            u1 = (u1 - P_u) / P_c;
            wi = cltc_sample(wo_local, r, u1, u2); // Sample wi from CLTC lobe
        pdf_c = wi.w; }
        const float pdf_u = 1.0f / (2.0f * PI);
        wi.w = P_u*pdf_u + P_c*pdf_c; // MIS PDF of wi
        return wi;
    }
    // PDF corresponding to the above sampling routine
    float pdf_EON(float3 wo_local, float3 wi_local, float r)
    {
        float mu = wo_local.z;
        float P_u = pow(r, 0.1f) * (0.162925f + (-0.372058f + (0.538233f - 0.290822f*mu)*mu)*mu);
        float P_c = 1.0f - P_u;
        float pdf_c = cltc_pdf(wo_local, wi_local, r);
        const float pdf_u = 1.0f / (2.0f * PI);
        return P_u*pdf_u + P_c*pdf_c;
    }



#endif //BRDF_HLSL