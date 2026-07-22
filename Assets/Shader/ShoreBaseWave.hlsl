#ifndef SHORE_BASE_WAVE_INCLUDED
#define SHORE_BASE_WAVE_INCLUDED

TEXTURE3D(_ShoreBaseWaveVolume);
SAMPLER(sampler_ShoreBaseWaveVolume);

float _ShoreBaseWaveWorldSize;
float _ShoreBaseWaveHeight;
float _ShoreBaseWaveChoppiness;
float _ShoreBaseWaveSpeed;
float _ShoreBaseWaveNormalStrength;
float _ShoreBaseWaveFoamStrength;

struct ShoreBaseWaveSample
{
    float3 volumeUVW;
    float4 encodedWave;
};

struct ShoreBaseWaveDecoded
{
    float3 displacementWS;
    float2 derivative;
    float height01;
    float foam;
};

float3 ComputeShoreBaseWaveUVW(float2 worldXZ)
{
    float worldSize = max(_ShoreBaseWaveWorldSize, 0.0001);
    float2 spatialUV = worldXZ / worldSize;
    float animationUV = frac(_Time.y * _ShoreBaseWaveSpeed);

    return float3(spatialUV, animationUV);
}

ShoreBaseWaveSample SampleShoreBaseWaveRaw(float2 worldXZ)
{
    ShoreBaseWaveSample sample;

    sample.volumeUVW = ComputeShoreBaseWaveUVW(worldXZ);
    sample.encodedWave = SAMPLE_TEXTURE3D_LOD(_ShoreBaseWaveVolume, sampler_ShoreBaseWaveVolume, sample.volumeUVW, 0);

    return sample;
}

ShoreBaseWaveDecoded DecodeShoreBaseWave(ShoreBaseWaveSample sample)
{
    ShoreBaseWaveDecoded decoded;

    float normalCenter = 128.0 / 255.0;
    decoded.derivative = sample.encodedWave.rg - normalCenter;
    decoded.height01 = sample.encodedWave.b;

    float heightWS = (decoded.height01 - 0.5) * _ShoreBaseWaveHeight;
    float2 horizontalWS = decoded.derivative * (1.0 - decoded.height01) * -_ShoreBaseWaveChoppiness;

    decoded.displacementWS = float3(horizontalWS.x, heightWS, horizontalWS.y);
    decoded.foam = saturate(sample.encodedWave.a * _ShoreBaseWaveFoamStrength);

    return decoded;
}

ShoreBaseWaveDecoded SampleShoreBaseWave(float2 worldXZ)
{
    ShoreBaseWaveSample sample = SampleShoreBaseWaveRaw(worldXZ);
    return DecodeShoreBaseWave(sample);
}

#endif