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

    /*
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

            shadowPayload payload;
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
    */


    bool IntersectHeightSlab(
    float3 rayOrigin,
    float3 rayDir,
    float bottomY,
    float topY,
    out float tEnter,
    out float tExit)
    {
        // A nearly horizontal ray either stays in the slab or never enters it.
        if (abs(rayDir.y) < 1e-5)
        {
            if (rayOrigin.y < bottomY || rayOrigin.y > topY)
            {
                tEnter = 0.0;
                tExit = 0.0;
                return false;
            }

            tEnter = 0.0;
            tExit = MAX_FOG_DISTANCE;
            return true;
        }

        float t0 = (bottomY - rayOrigin.y) / rayDir.y;
        float t1 = (topY    - rayOrigin.y) / rayDir.y;

        tEnter = max(0.0, min(t0, t1));
        tExit  = max(0.0, max(t0, t1));

        return tExit > tEnter;
    }
    

    // Ok im gonna keep it a buck 50 here, this shit was ai generated
    // This also goes for SampleHeightDensity() below it
    // I have no clue how it works aside from the provided comments 
    // From what it told me its basically like a binary search to get proper height intersection from the resource pack values
    // Probably gonna remove this to do height based on delta tracking and pass in resource pack values for that instead
    float IntegrateHeightDensity(
    float3 origin,
    float3 direction,
    float t0,
    float t1)
{
    float scale = g_view.heightToFogScale;
    float bias  = g_view.heightToFogBias;

    // Height fog disabled for underwater camera.
    if (g_view.cameraIsUnderWater)
        return t1 - t0;

    float dy = direction.y;

    // Horizontal ray: density is constant.
    if (abs(scale * dy) < 1e-6)
    {
        float density = saturate(origin.y * scale + bias);
        return (t1 - t0) * density;
    }

    // Density at t is:
    //
    // d(t) = saturate(a*t + b)
    //
    float a = scale * dy;
    float b = origin.y * scale + bias;

    // Integral of saturate(a*t + b).
    //
    // F(t) is the antiderivative.
   

    // This nested-function form may not be accepted by your shader compiler,
    // so the implementation below is the compiler-safe version.
    float x0 = a * t0 + b;
    float x1 = a * t1 + b;

    // If both endpoints are in the same clamped region,
    // we can handle it directly.
    if (x0 <= 0.0 && x1 <= 0.0)
        return 0.0;

    if (x0 >= 1.0 && x1 >= 1.0)
        return t1 - t0;

    // Split the interval at density transitions.
    float result = 0.0;

    float ta = t0;
    float tb = t1;

    // Collect transition points.
    float tZero = -b / a;
    float tOne  = (1.0 - b) / a;

    float cuts[4];
    int count = 0;

    cuts[count++] = t0;

    if (tZero > t0 && tZero < t1)
        cuts[count++] = tZero;

    if (tOne > t0 && tOne < t1)
        cuts[count++] = tOne;

    cuts[count++] = t1;

    // Sort transition points.
    for (int i = 1; i < count; ++i)
    {
        float v = cuts[i];
        int j = i - 1;

        while (j >= 0 && cuts[j] > v)
        {
            cuts[j + 1] = cuts[j];
            --j;
        }

        cuts[j + 1] = v;
    }

    for (int i = 0; i < count - 1; ++i)
    {
        float l = cuts[i];
        float r = cuts[i + 1];

        float mid = 0.5 * (l + r);
        float density = saturate(a * mid + b);

        if (density <= 0.0)
            continue;

        if (density >= 1.0)
        {
            result += r - l;
        }
        else
        {
            result +=
                0.5 * a * (r * r - l * l) +
                b * (r - l);
        }
    }

    return result;
}
float SampleHeightFogDistance(
    float3 origin,
    float3 direction,
    float tEnd,
    float sigmaT,
    float random)
{
    float target =
        -log(max(1.0 - random, 1e-6));

    float totalOpticalDepth =
        sigmaT *
        IntegrateHeightDensity(
            origin,
            direction,
            0.0,
            tEnd);

    // No interaction before tEnd.
    if (target >= totalOpticalDepth)
        return tEnd + 1.0;

    float lo = 0.0;
    float hi = tEnd;

    // Invert integrated optical depth.
    for (int i = 0; i < 10; ++i)
    {
        float mid = 0.5 * (lo + hi);

        float opticalDepth =
            sigmaT *
            IntegrateHeightDensity(
                origin,
                direction,
                0.0,
                mid);

        if (opticalDepth < target)
            lo = mid;
        else
            hi = mid;
    }

    return 0.5 * (lo + hi);
}
    

    float PhaseHG(float cosTheta, float g)
    {
        float denom = 1.0 + g * g - 2.0 * g * cosTheta;
        return (1.0 - g * g) /
        (4.0 * PI * pow(max(denom, 1e-6), 1.5));
    }

    // Builds a sample around the HG phase 
    // Ngl if you want realism HG Draine is probably better
    // Although, ive mainly seen that for clouds
    float3 SampleHG(float3 forward,float g,float2 xi,out float pdf)
    {
        float cosTheta;

        if (abs(g) < 1e-3)
        {
            cosTheta = 1.0 - 2.0 * xi.x;
        }
        else
        {
            float s = (1.0 - g * g) /
            (1.0 - g + 2.0 * g * xi.x);

            cosTheta = (1.0 + g * g - s * s) / (2.0 * g);
        }

        float sinTheta = sqrt(max(0.0, 1.0 - cosTheta * cosTheta));
        float phi = 2.0 * PI * xi.y;

        float3 tangent, bitangent;
        buildOrthonormalBasis(normalize(forward), tangent, bitangent);

        float3 nextDirection =
        tangent   * (cos(phi) * sinTheta) +
        bitangent * (sin(phi) * sinTheta) +
        forward   * cosTheta;

        pdf = PhaseHG(cosTheta, g);
        return normalize(nextDirection);
    }
    float3 SampleUniformSphere(float2 xi)
    {
        float z = 1.0 - 2.0 * xi.x;
        float r = sqrt(max(0.0, 1.0 - z * z));
        float phi = 2.0 * PI * xi.y;
        return float3(r * cos(phi), r * sin(phi), z);
    }


    float3 rayMarchFog(float3 pos, float3 dir, float3 color, float maxDist, float2 pixelPos)
    {
        PathRNG rng;
        float3 sunDir =  getDirectionToSun();
        float3 moonDir = -sunDir;

        float sunFade = saturate(sunDir.y);
        float moonFade = saturate(moonDir.y);

        float3 mainLightDir = sunFade > 0.0 ? sunDir : moonDir;

        const int volumetricSteps = VL_FOG_STEPS;
        dir = normalize(dir);
        float dist = min(maxDist, MAX_FOG_DISTANCE);

        float stepLength = dist / (float)volumetricSteps;

        float4 sunlightColor =  getSunColor(float4(0.0, 0.0, 0.0, 0.0)) * 550 * SUN_INTENSITY;
        sunlightColor.rgb *= sunlightColor.a;
        float pdfSun = max(PDF_SunCone(), 1e-4); 
        sunlightColor.rgb /= pdfSun;
        float3 ambientColor =  getSkyColor(0..xxx) * 2.15;

        float3 scattering = getScattering() * 155.5;
        float3 absorption = getMediaAbsorption();
        float3 extinction = getMediaPrimaryExtinction();

        bool inWater = g_view.cameraIsUnderWater;
        float3 mediaExtintion = inWater ?  getMediaExtinction(MEDIA_TYPE_WATER).rgb * 6 : getMediaExtinction(MEDIA_TYPE_AIR).rgb * 5; 
        extinction = (mediaExtintion);

        float3 totalScattering = 0;
        float3 transmittance = 1.0;
        float VdotL = (dot(dir, mainLightDir));
        float phase = inWater ? waterPhase(VdotL)  : CS(0.65, VdotL) +  0.5 * CS(-0.12, VdotL);
        float uniformPhase = 1.0 / (4 * PI);
        float density = inWater ? 0.08 : 0.02;

        for(int i = 0; i < volumetricSteps; i++)
        {   
            // Set up PCG Hash for dithering
            uint baseSeed = uint(pixelPos.x) + uint(pixelPos.y) * g_view.renderResolution.x;
            baseSeed ^= g_view.frameCount * 0x9E3779B9u;
            baseSeed ^= uint(i) * 0x85EBCA6Bu;
            rng.state = PCG_Hash(uint3(baseSeed, g_view.frameCount, uint(i)));
            float2 Xi = NextFloat2(rng);

            // Construct ray march ray
            float u = (i + NextFloat(rng)) / volumetricSteps;
            float t = u * u * min(maxDist, MAX_FOG_DISTANCE);
            float previousT = (i == 0)
            ? 0.0
            : pow((i - 1 + NextFloat(rng)) / volumetricSteps, 2.0)
            * min(maxDist, MAX_FOG_DISTANCE);

            float stepLength = t - previousT;
            float3 rayPos = pos + dir * t;

            // Establish Sun shadow raytrace from the rayPos
            shadowPayload payload; 
            RayDesc shadowRay; 
            shadowRay.Direction = randConeJitter(mainLightDir, SUN_RADIUS, Xi);
            shadowRay.Origin = offset_ray(rayPos, shadowRay.Direction) ;
            shadowRay.TMin = 0.0; 
            shadowRay.TMax = 10000; 
            TraceShadowRay(shadowRay, payload); 
            float3 shadow = payload.transmission;

            float fMS = (1.0 - exp(-15.0 * density * (float)extinction)) * 1.0 / (float)extinction;
            fMS = lerp(fMS, fMS * 0.99, smoothstep(0.99, 1.0, fMS)); // this part by luna
            float3 directLight = ((sunlightColor.rgb * scattering)) * phase * shadow;
            float3 ambientLight = ((ambientColor)) * uniformPhase;
            float3 singleScattering = (directLight  + ambientLight)  * fMS;
            float3 sampleTransmittance = calcTransmittance(stepLength, extinction * density);
            float3  inscatter = transmittance * (singleScattering * (1.0 - clamp(sampleTransmittance,0,1))  / extinction);
            totalScattering += inscatter;
            transmittance *= sampleTransmittance;
        }
        color = color * transmittance + totalScattering;

        return color;
    }

#endif //FOG_HLSL

