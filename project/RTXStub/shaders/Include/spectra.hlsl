#ifndef SPECTRA_HLSL
#define SPECTRA_HLSL



float refractiveIndexWater(float wavelength)
{
    // coefficients
    const float T = 20;
    const float a = -1.97812 * 1e-6;
    const float b = 1.03223 * 1e-7;
    const float c = -8.58125 * 1e-6;
    const float d = -1.54834 * 1e-4;
    const float e = 1.38919;

    // calculate the index from the wavelength
    return a * T * T + b * wavelength * wavelength + c * T + d * wavelength + e;

}


#endif // SPECTRA_HLSL
