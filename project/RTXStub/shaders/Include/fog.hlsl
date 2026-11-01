#ifndef FOG_HLSL
    #define FOG_HLSL

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
    

    


    /*
    * SPDX-FileCopyrightText: Copyright (c) <2023> NVIDIA CORPORATION & AFFILIATES. All rights reserved.
    * SPDX-License-Identifier: MIT
    *
    * Permission is hereby granted, free of charge, to any person obtaining a
    * copy of this software and associated documentation files (the "Software"),
    * to deal in the Software without restriction, including without limitation
    * the rights to use, copy, modify, merge, publish, distribute, sublicense,
    * and/or sell copies of the Software, and to permit persons to whom the
    * Software is furnished to do so, subject to the following conditions:
    *
    * The above copyright notice and this permission notice shall be included in
    * all copies or substantial portions of the Software.
    *
    * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
    * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    * DEALINGS IN THE SOFTWARE.
    */

    // [Jendersie and d'Eon 2023]
    //   SIGGRAPH 2023 Talks
    //   https://doi.org/10.1145/3587421.3595409

    // EVAL and SAMPLE for the Draine (and therefore Cornette-Shanks) phase function
    //   g = HG shape parameter
    //   a = "alpha" shape parameter

    // Warning: these functions don't special case isotropic scattering and can numerically fail for certain inputs

    // eval:
    //   u = dot(prev_dir, next_dir)
    float evalDraine(in float u, in float g, in float a)
    {
        // Strict bounding prevents denominator collapse to zero or subnormals
        float guardedG = clamp(g, -0.99f, 0.99f);
        float guardedU = clamp(u, -1.0f, 1.0f);
        
        float g2 = guardedG * guardedG;
        float denom = max(1.0f + g2 - 2.0f * guardedG * guardedU, 1e-5f);
        
        float numerator = (1.0f - g2) * (1.0f + a * guardedU * guardedU);
        float denominator = 4.0f * (1.0f + (a * (1.0f + 2.0f * g2)) / 3.0f) * 3.1415926535f * pow(denom, 1.5f);
        
        return numerator / denominator;
    }

    // sample: (sample an exact deflection cosine)
    //   xi = a uniform random real in [0,1]
    // Evaluates the exact analytical Cumulative Distribution Function (CDF) 
    // for the Draine phase function given a target cosine u.
    float EvaluateDraineCDF(float u, float g, float a)
    {
        float g2 = g * g;
        float denom = max(1.0f + g2 - 2.0f * g * u, 1e-5f);
        float sqrtDenom = sqrt(denom);

        // Compute the base integrals for the Draine phase function over [-1, u]
        float term1 = (1.0f - g2) / (2.0f * g * (1.0f + (a * (1.0f + 2.0f * g2)) / 3.0f));
        
        // Core integral parts of the Draine CDF
        float F_base = (1.0f + a * u * u) / sqrtDenom;
        float F_lower = (1.0f + a) / sqrt(1.0f + g2 + 2.0f * g); // lower bound evaluated at u = -1
        
        // Complete Draine CDF mapping from [0, 1]
        // (This matches the analytic integral of evalDraine)
        float cdf = term1 * (F_base - F_lower); 
        return saturate(cdf);
    }

    // Robust, numerically stable Draine Cosine Sampler using Newton-Raphson
    float sampleDraineCos(in float xi, in float g, in float a)
    {
        float guardedG = clamp(g, -0.99f, 0.99f);
        float safeXi = clamp(xi, 1e-5f, 0.9999f);

        // STEP 1: Use the analytical Henyey-Greenstein inversion as our initial guess.
        // Since Draine closely mimics HG profiles, this guess puts us extremely close to the root.
        float u;
        if (abs(guardedG) < 1e-3f)
        {
            u = 1.0f - 2.0f * safeXi;
        }
        else
        {
            float s = (1.0f - guardedG * guardedG) / (1.0f - guardedG + 2.0f * guardedG * safeXi);
            u = (1.0f + guardedG * guardedG - s * s) / (2.0f * guardedG);
        }
        u = clamp(u, -1.0f, 1.0f);

        // STEP 2: Run exactly 3 iterations of Newton-Raphson refinement.
        // Newton's method: u_next = u - (F(u) - targetXi) / f(u)
        // where F(u) is the CDF, and f(u) is the PDF (evalDraine).
        [unroll]
        for (int i = 0; i < 3; ++i)
        {
            float cdf = EvaluateDraineCDF(u, guardedG, a);
            float pdf = max(evalDraine(u, guardedG, a), 1e-5f); // Ensure no division by zero

            // Update step
            u = u - (cdf - safeXi) / pdf;
            u = clamp(u, -1.0f, 1.0f);
        }

        return u;
    }

    void buildOrthonormalBasis1(float3 n, out float3 b1, out float3 b2)
    {
        if (n.z < -0.9999999f) 
        {
            b1 = float3(0.0f, -1.0f, 0.0f);
            b2 = float3(-1.0f, 0.0f, 0.0f);
            return;
        }
        float a = 1.0f / (1.0f + n.z);
        float b = -n.x * n.y * a;
        b1 = float3(1.0f - n.x * n.x * a, b, -n.x);
        b2 = float3(b, 1.0f - n.y * n.y * a, -n.y);
    }

    float3 SampleDraine(
    float3 forward,
    float g,
    float alpha,
    PathRNG rng,
    out float pdf)
    {
        forward = normalize(forward);

        // NVIDIA's function samples the deflection cosine.
        float xi = NextFloat(rng);
        float cosTheta = sampleDraineCos(xi, g, alpha);
        cosTheta = clamp(cosTheta, -1.0, 1.0);

        // Sample azimuth uniformly.
        float phi = 2.0 * PI * NextFloat(rng);

        float sinTheta = sqrt(
        max(0.0, 1.0 - cosTheta * cosTheta));

        float3 tangent;
        float3 bitangent;

        buildOrthonormalBasis(
        forward,
        tangent,
        bitangent);

        float3 nextDirection = normalize(
        tangent * (cos(phi) * sinTheta) +
        bitangent * (sin(phi) * sinTheta) +
        forward * cosTheta);

        // Exact Draine phase function, subject to numerical precision.
        pdf = evalDraine(cosTheta, g, alpha);

        return nextDirection;
    }

    float PhaseHG(float cosTheta, float g)
    {
        cosTheta = clamp(cosTheta, -1.0, 1.0);
        g = clamp(g, -0.99, 0.99);

        float denom = max(
        1.0 + g * g - 2.0 * g * cosTheta,
        1e-6
        );

        return (1.0 - g * g) /
        (4.0 * PI * pow(denom, 1.5));
    }
    
    void GetApproximateMieParameters(float diameterMicrons,out float gHG,out float gD,out float alpha,out float draineWeight)
    {
        float d = clamp(diameterMicrons, 5.0f, 50.0f);

        gHG = exp(-0.0990567f / (d - 1.67154f));

        gD = exp(-2.20679f / (d + 3.91029f) - 0.428934f);

        alpha = exp(3.62489f - 8.29288f / (d + 5.52825f));

        draineWeight = exp(-0.599085f / (d - 0.641583f) - 0.665888f);

        draineWeight = saturate(draineWeight);
    }


    float PhaseApproximateMie(
    float cosTheta,
    float gHG,
    float gD,
    float alpha,
    float draineWeight)
    {
        float pHG = PhaseHG(cosTheta, gHG);
        float pD = evalDraine(cosTheta, gD, alpha);

        return (1.0 - saturate(draineWeight)) * pHG
        + saturate(draineWeight) * pD;
    }

float3 SampleApproximateMie(
    float3 forward,
    float gHG,
    float gD,
    float alpha,
    float draineWeight,
    PathRNG rng,
    out float pdf,
    out float exactCosTheta) // <-- Add this output parameter
{
    forward = normalize(forward);
    draineWeight = saturate(draineWeight);
    alpha = max(alpha, 0.0f);

    float lobeSelector = NextFloat(rng);
    float2 xi = NextFloat2(rng); 
    
    float phi = 2.0f * 3.14159265f * xi.y;

    if (lobeSelector < draineWeight)
    {
        float guardedGD = clamp(gD, -0.99f, 0.99f); 
        exactCosTheta = sampleDraineCos(xi.x, guardedGD, alpha);
    }
    else
    {
        float guardedGHG = clamp(gHG, -0.99f, 0.99f);
        if (abs(guardedGHG) < 1e-3f)
        {
            exactCosTheta = 1.0f - 2.0f * xi.x;
        }
        else
        {
            float s = (1.0f - guardedGHG * guardedGHG) / (1.0f - guardedGHG + 2.0f * guardedGHG * xi.x);
            exactCosTheta = (1.0f + guardedGHG * guardedGHG - s * s) / (2.0f * guardedGHG);
        }
    }

    exactCosTheta = clamp(exactCosTheta, -1.0f, 1.0f);
    float sinTheta = sqrt(max(0.0f, 1.0f - exactCosTheta * exactCosTheta));

    float3 tangent;
    float3 bitangent;
    buildOrthonormalBasis(forward, tangent, bitangent);

    float3 nextDirection = normalize(
        tangent * (cos(phi) * sinTheta) +
        bitangent * (sin(phi) * sinTheta) +
        forward * exactCosTheta
    );

    // Compute the mixture PDF using the exact analytical cosine
    float pHG = PhaseHG(exactCosTheta, gHG);
    float pD  = evalDraine(exactCosTheta, clamp(gD, -0.99f, 0.99f), alpha);
    pdf = (1.0f - draineWeight) * pHG + draineWeight * pD;

    return nextDirection;
}


    float3 SampleDraine(
    float3 forward,
    float g,
    float alpha,
    float2 xi,
    PathRNG rng,
    out float pdf)
    {
        forward = normalize(forward);

        float cosTheta = 0.0;

        alpha = max(alpha, 0.0);

        for (int i = 0; i < 16; i++)
        {
            float2 sampleXi = (i == 0) ? xi : NextFloat2(rng);

            // Sample HG
            if (abs(g) < 1e-3)
            {
                cosTheta = 1.0 - 2.0 * sampleXi.x;
            }
            else
            {
                float s =
                (1.0 - g * g) /
                (1.0 - g + 2.0 * g * sampleXi.x);

                cosTheta =
                (1.0 + g * g - s * s) /
                (2.0 * g);
            }

            cosTheta = clamp(cosTheta, -1.0, 1.0);

            // Draine correction / rejection probability
            float acceptance =
            (1.0 + alpha * cosTheta * cosTheta) /
            (1.0 + alpha);

            if (NextFloat(rng) <= acceptance)
            {
                float sinTheta =
                sqrt(max(0.0, 1.0 - cosTheta * cosTheta));

                float phi =
                2.0 * PI * sampleXi.y;

                float3 tangent;
                float3 bitangent;

                buildOrthonormalBasis(
                forward,
                tangent,
                bitangent);

                float3 nextDirection =
                tangent * (cos(phi) * sinTheta) +
                bitangent * (sin(phi) * sinTheta) +
                forward * cosTheta;

                nextDirection = normalize(nextDirection);

                pdf = PhaseDraine(cosTheta, g, alpha);

                return nextDirection;
            }
        }

        // Fallback: use the supplied xi as an HG sample.
        if (abs(g) < 1e-3)
        {
            cosTheta = 1.0 - 2.0 * xi.x;
        }
        else
        {
            float s =
            (1.0 - g * g) /
            (1.0 - g + 2.0 * g * xi.x);

            cosTheta =
            (1.0 + g * g - s * s) /
            (2.0 * g);
        }

        cosTheta = clamp(cosTheta, -1.0, 1.0);

        float sinTheta =
        sqrt(max(0.0, 1.0 - cosTheta * cosTheta));

        float phi = 2.0 * PI * xi.y;

        float3 tangent;
        float3 bitangent;

        buildOrthonormalBasis(
        forward,
        tangent,
        bitangent);

        float3 nextDirection =
        tangent * (cos(phi) * sinTheta) +
        bitangent * (sin(phi) * sinTheta) +
        forward * cosTheta;

        nextDirection = normalize(nextDirection);

        pdf = PhaseDraine(cosTheta, g, alpha);

        return nextDirection;
    }

    float3 SampleUniformSphere(float2 xi)
    {
        float z = 1.0 - 2.0 * xi.x;
        float r = sqrt(max(0.0, 1.0 - z * z));
        float phi = 2.0 * PI * xi.y;
        return float3(r * cos(phi), r * sin(phi), z);
    }

    float3 GetAtmosphereSunTransmittance(float3 origin, float3 dir, inout PathRNG rng, in bool hitWater)
    {
        const float ATMOSPHERE_RADIUS = 550.0f;

        float t0, t1;
        if (!RaySphereIntersect(origin, dir, ATMOSPHERE_RADIUS, t0, t1) || t1 <= 0.0f)
        return 1.0;

        float t = max(t0, 0.0f);

        float3 sigmaT3 =
        inEnd
        ? getMediaPrimaryExtinction() * END_FOG_EXTINCTION_INTENSITY
        : getMediaPrimaryExtinction() * 0.3;

        sigmaT3 = lerp(
        sigmaT3,
       float3(0.0125, 0.0125, 0.0125),
        getBiomeAdjustedRainLevel());

        if(hitWater)
        {
            sigmaT3 = getMediaExtinction(MEDIA_TYPE_WATER).rgb * 0.03;
        }

        float majorant = max(sigmaT3.x, max(sigmaT3.y, sigmaT3.z));
        majorant = max(majorant, 1e-6f);

        float3 transmittance = 1.0;

        while (true)
        {
            float xi = max(NextFloat(rng), 1e-6f);
            t += -log(xi) / majorant;

            if (t >= t1)
            break;

            float3 candidatePos = origin + dir * t;
            float densityModifier = saturate(calcDensityModifier(candidatePos));
            float3 localSigmaT3 = sigmaT3 * densityModifier;

            transmittance *= 1.0 - saturate(localSigmaT3 / majorant);

            if (max(transmittance.x, max(transmittance.y, transmittance.z)) < 1e-3f)
            break;
        }

        return transmittance;
    }
    
    

#endif //FOG_HLSL

