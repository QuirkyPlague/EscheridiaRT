// Adapted from Polyphony Digital's SIGGRAPH 2025 sample, version 1.0.
// https://blog.selfshadow.com/publications/s2025-shading-course/pdi/supplemental/gt7_tone_mapping.cpp
// MIT License
// Copyright (c) 2025 Polyphony Digital Inc.
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#ifndef SERAPHIC_GT7_TONE_MAPPING_SH
#define SERAPHIC_GT7_TONE_MAPPING_SH

// Published defaults must be preprocessor constants: global GLSL const values
// become unbound HLSL uniform-buffer fields with this shaderc backend.
// No project-specific look, exposure gain or white anchoring.
#define kGT7ReferenceLuminance 100.0
#define kGT7PaperWhite 250.0
#define kGT7Alpha 0.25
#define kGT7MidPoint 0.538
#define kGT7LinearSection 0.444
#define kGT7ToeStrength 1.280
#define kGT7BlendRatio 0.6
#define kGT7FadeStart 0.98
#define kGT7FadeEnd 1.16

float gt7SmoothStep(float x, float a, float b) {
    float t = clamp((x-a)/(b-a), 0.0, 1.0);
    return t*t*(3.0-2.0*t);
}

float gt7Curve(float x, float peak) {
    if (x < 0.0) return 0.0;
    float k = (kGT7LinearSection-1.0)/(kGT7Alpha-1.0);
    float A = peak*kGT7LinearSection + peak*k;
    float B = -peak*k*exp(kGT7LinearSection/k);
    float C = -1.0/(k*peak);
    if (x < kGT7LinearSection*peak) {
        float w = gt7SmoothStep(x, 0.0, kGT7MidPoint);
        float toe = kGT7MidPoint*pow(x/kGT7MidPoint, kGT7ToeStrength);
        return (1.0-w)*toe + w*x;
    }
    return A+B*exp(x*C);
}

float gt7Eotf(float n) {
    n = clamp(n, 0.0, 1.0);
    const float m1 = 0.1593017578125;
    const float m2 = 78.84375;
    const float c1 = 0.8359375;
    const float c2 = 18.8515625;
    const float c3 = 18.6875;
    float np = pow(n, 1.0/m2);
    float l = max(np-c1, 0.0)/(c2-c3*np);
    return pow(l, 1.0/m1)*10000.0/kGT7ReferenceLuminance;
}

float gt7InverseEotf(float v) {
    const float m1 = 0.1593017578125;
    const float m2 = 78.84375;
    const float c1 = 0.8359375;
    const float c2 = 18.8515625;
    const float c3 = 18.6875;
    float y = v*kGT7ReferenceLuminance/10000.0;
    float ym = pow(y, m1);
    return exp2(m2*(log2(c1+c2*ym)-log2(1.0+c3*ym)));
}

// The sample's default UCS is ICtCp. Inputs here are linear Rec.2020.
vec3 gt7RgbToUcs(vec3 rgb) {
    float l = (rgb.r*1688.0+rgb.g*2146.0+rgb.b*262.0)/4096.0;
    float m = (rgb.r*683.0+rgb.g*2951.0+rgb.b*462.0)/4096.0;
    float s = (rgb.r*99.0+rgb.g*309.0+rgb.b*3688.0)/4096.0;
    float lp = gt7InverseEotf(l);
    float mp = gt7InverseEotf(m);
    float sp = gt7InverseEotf(s);
    return vec3((2048.0*lp+2048.0*mp)/4096.0,
        (6610.0*lp-13613.0*mp+7003.0*sp)/4096.0,
        (17933.0*lp-17390.0*mp-543.0*sp)/4096.0);
}

vec3 gt7UcsToRgb(vec3 ucs) {
    float l = ucs.r+0.00860904*ucs.g+0.11103*ucs.b;
    float m = ucs.r-0.00860904*ucs.g-0.11103*ucs.b;
    float s = ucs.r+0.560031*ucs.g-0.320627*ucs.b;
    float ll = gt7Eotf(l);
    float ml = gt7Eotf(m);
    float sl = gt7Eotf(s);
    return vec3(max(3.43661*ll-2.50645*ml+0.0698454*sl,0.0),
        max(-0.79133*ll+1.9836*ml-0.192271*sl,0.0),
        max(-0.0259499*ll-0.0989137*ml+1.12486*sl,0.0));
}

// Official operator core. SDR = peak 250/100, correction 100/250.
// The parameterized core also admits the published HDR luminance targets;
// this package integrates only SDR, not an HDR swapchain/output mode.
vec3 gt7ReferenceOperator(vec3 rgb, float peak, float correction) {
    vec3 ucs = gt7RgbToUcs(rgb);
    vec3 skewed = vec3(gt7Curve(rgb.r,peak), gt7Curve(rgb.g,peak), gt7Curve(rgb.b,peak));
    vec3 skewedUcs = gt7RgbToUcs(skewed);
    vec3 targetUcs = gt7RgbToUcs(vec3(peak,peak,peak));
    float chroma = 1.0-gt7SmoothStep(ucs.r/targetUcs.r, kGT7FadeStart, kGT7FadeEnd);
    vec3 scaled = gt7UcsToRgb(vec3(skewedUcs.r,ucs.g*chroma,ucs.b*chroma));
    vec3 blended = (1.0-kGT7BlendRatio)*skewed+kGT7BlendRatio*scaled;
    return correction*min(blended,vec3(peak,peak,peak));
}

// D65 linear Rec.709 <-> Rec.2020 integration, outside the operator.
// Minecraft's RGB cannot be interpreted as Rec.2020 without these transforms.
vec3 gt7Rec709To2020(vec3 c) {
    return vec3(dot(c,vec3(0.627403895934699,0.329283038377883,0.043313065687418)),
        dot(c,vec3(0.069097289358232,0.919540395075459,0.011362315566309)),
        dot(c,vec3(0.016391438875150,0.088013307877226,0.895595253247624)));
}

vec3 gt7Rec2020To709(vec3 c) {
    return vec3(dot(c,vec3(1.660491002108435,-0.587641138788550,-0.072849863319885)),
        dot(c,vec3(-0.124550474521591,1.132899897125960,-0.008349422604369)),
        dot(c,vec3(-0.018150763354905,-0.100578898008007,1.118729661362912)));
}

vec3 applyGT7ToneMapping(vec3 color) {
    float peak = kGT7PaperWhite/kGT7ReferenceLuminance;
    vec3 mapped = gt7ReferenceOperator(gt7Rec709To2020(color),peak,1.0/peak);
    // SDR gamut boundary, not another tone curve or saturation look.
    return clamp(gt7Rec2020To709(mapped),vec3(0.0,0.0,0.0),vec3(1.0,1.0,1.0));
}
#endif