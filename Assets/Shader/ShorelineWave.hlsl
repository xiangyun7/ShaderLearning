#ifndef SHORELINE_WAVE_INCLUDED
#define SHORELINE_WAVE_INCLUDED

TEXTURE2D(_CoastlineMap);
SAMPLER(sampler_CoastlineMap);
TEXTURE2D(_WaveProfileMap);
SAMPLER(sampler_WaveProfileMap);
TEXTURE2D(_SmoothNoiseMap);
SAMPLER(sampler_SmoothNoiseMap);

float4 _CoastMapMinSize;
float _MaxCoastDistance;
float _FFTBlendStart;
float _FFTBlendEnd;
float4 _WaveProfileDecode;
float _WaveProfileWidth;
float _WaveProfileDistance;
float _WaveProfileSpeed;
float _WaveProfileAnimationSpeed;
float _NoiseTime;
float _NoiseScale;
//海岸线结构数据
struct ShorelineData
{
    float4 encodedCoast;
    float2 coastUV;
    float2 directionToShore;
    float waterDistance;
    float waveScale;
    float fftWeight;
    float insideMap;
    float directionMask;
};
//海浪结构数据
struct ShoreWaveProfile
{
    float4 encodedProfile;
    float2 profileUV;
    float2 forwardUpward;
    float foam;
    float presence;
};
//噪声结构数据
struct ShorelineOffsets
{
    float timeOffset;
    float detailOffset;
};
//世界坐标计算uv
float2 CoastWorldToUV(float2 worldXZ)
{
    float2 coastMinXZ = _CoastMapMinSize.xy;
    float2 coastSizeXZ = max(_CoastMapMinSize.zw, float2(0.0001, 0.0001));
    return (worldXZ - coastMinXZ) / coastSizeXZ;
}
//uv是否在海岸线map以内
float IsInsideCoastMap(float2 coastUV)
{
    float2 aboveMinimum = step(float2(0.0, 0.0), coastUV);
    float2 belowMaximum = step(coastUV, float2(1.0, 1.0));
    return aboveMinimum.x * aboveMinimum.y * belowMaximum.x * belowMaximum.y;
}
//解码海面方向（指向海岸线）
float2 DecodeDirectionToShore(float2 encodedDirection)
{
    float2 direction = encodedDirection * 2.0 - 1.0;
    float lengthSquared = dot(direction, direction);
    float validDirection = step(0.000001, lengthSquared);
    return direction * rsqrt(max(lengthSquared, 0.000001)) * validDirection;
}
//解码海面离海岸线距离
float DecodeWaterDistance(float encodedDistance)
{
    float maxDistance = max(_MaxCoastDistance, 0.0001);
    return (0.5 - encodedDistance) * 2.0 * maxDistance;
}
//近浪远洋过渡过渡
float ComputeFFTWeight(float waterDistance, float directionMask)
{
    float blendStart = max(_FFTBlendStart, 0.0);
    float blendRange = max(_FFTBlendEnd - blendStart, 0.0001);

    float distanceBlend = saturate((waterDistance - blendStart) / blendRange);
    float waterSide = smoothstep(0.0, 1.0, waterDistance);
    float safeDirectionMask = directionMask * waterSide;

    return min(distanceBlend + safeDirectionMask, 1.0);
}
//采样海岸线sdf纹理
float4 SampleEncodedCoast(float2 coastUV)
{
    float2 safeUV = saturate(coastUV);
    return SAMPLE_TEXTURE2D_LOD(_CoastlineMap, sampler_CoastlineMap, safeUV, 0);
}
//采样海岸线sdf纹理
ShorelineData EvaluateShorelineData(float2 worldXZ)
{
    ShorelineData data;
    data.coastUV = CoastWorldToUV(worldXZ);
    data.insideMap = IsInsideCoastMap(data.coastUV);
    data.encodedCoast = SampleEncodedCoast(data.coastUV);

    float decodedDistance = DecodeWaterDistance(data.encodedCoast.r);
    float outsideDistance = max(_MaxCoastDistance, 0.0001);
    
    float2 encodedDirectionOffset = data.encodedCoast.gb - 0.5;
    float encodedDirectionLength = length(encodedDirectionOffset);

    data.directionMask = saturate(encodedDirectionLength * -4.54545 + 2.159091);
    data.directionMask = lerp(1.0, data.directionMask, data.insideMap);

    data.waterDistance = lerp(outsideDistance, decodedDistance, data.insideMap);
    data.directionToShore = DecodeDirectionToShore(data.encodedCoast.gb) * data.insideMap;
    data.waveScale = data.encodedCoast.a * data.insideMap;
    data.fftWeight = lerp(1.0, ComputeFFTWeight(data.waterDistance, data.directionMask), data.insideMap);

    return data;
}
//计算海岸相位:
/*根据顶点的世界位置、离岸距离和朝岸方向，
为WaveProfile生成稳定在海岸线上的时间相位偏移与生命周期细节偏移。*/
ShorelineOffsets ComputeShorelineOffsets(ShorelineData shoreline, float2 worldXZ)
{
    ShorelineOffsets offsets;

    float profileWidth = max(_WaveProfileWidth, 0.0001);
    float scaledDistance = shoreline.waterDistance / profileWidth;
    float2 scaledWorldXZ = worldXZ / profileWidth;

    float smoothNoiseA = SAMPLE_TEXTURE2D_LOD(_SmoothNoiseMap, sampler_SmoothNoiseMap, scaledWorldXZ * 0.5, 0).r - 0.5;
    float smoothNoiseB = SAMPLE_TEXTURE2D_LOD(_SmoothNoiseMap, sampler_SmoothNoiseMap, scaledWorldXZ * 1.5, 0).r - 1.0;

    float shorelineCoordinate = (scaledWorldXZ + scaledDistance * shoreline.directionToShore).y;
    float3 factor = shorelineCoordinate * float3(0.121, 0.242, 0.752);

    float sineFactor = sin(factor.y * 2.0 * PI);
    float cosineFactor = cos(factor.z * 2.0 * PI);

    offsets.timeOffset = factor.x - sineFactor * 0.135 - cosineFactor * 0.038;
    offsets.timeOffset += _NoiseTime * smoothNoiseA * saturate(scaledDistance * 0.35 - 0.05);

    offsets.detailOffset = sineFactor * -0.25 + cosineFactor * 0.15;
    offsets.detailOffset += _NoiseScale * smoothNoiseB;

    return offsets;
}

//计算海浪map的uv
float2 ComputeShoreWaveProfileUV(ShorelineData shoreline, float2 worldXZ)
{
    float profileWidth = max(_WaveProfileWidth, 0.0001);
    ShorelineOffsets offsets = ComputeShorelineOffsets(shoreline, worldXZ);

    float baseU = _WaveProfileDistance - shoreline.waterDistance / profileWidth;
    float detailedU = baseU + offsets.detailOffset;
    float travelPhase = _WaveProfileSpeed * _Time.y + offsets.timeOffset;

    float profileU = baseU - travelPhase;
    float rawLifecycle = detailedU - frac(profileU);
    float profileV = frac(rawLifecycle * _WaveProfileAnimationSpeed);

    return float2(profileU, profileV);
}
//采样海浪纹理
ShoreWaveProfile SampleShoreWaveProfile(ShorelineData shoreline, float2 worldXZ)
{
    ShoreWaveProfile profile;
    profile.profileUV = ComputeShoreWaveProfileUV(shoreline, worldXZ);
    profile.encodedProfile = SAMPLE_TEXTURE2D_LOD(_WaveProfileMap, sampler_WaveProfileMap, profile.profileUV, 0);

    float localU = frac(profile.profileUV.x);
    float localV = profile.profileUV.y;

    float uFadeIn = smoothstep(0.0, 0.04, localU);
    float uFadeOut = 1.0 - smoothstep(0.96, 1.0, localU);
    float vFadeIn = smoothstep(0.0, 0.08, localV);
    float vFadeOut = 1.0 - smoothstep(0.92, 1.0, localV);

    profile.presence = uFadeIn * uFadeOut * vFadeIn * vFadeOut;
    
    float2 displacementScale = _WaveProfileDecode.zw * max(_WaveProfileWidth, 0.0001);

    profile.forwardUpward = (profile.encodedProfile.rg + _WaveProfileDecode.xy) * displacementScale * profile.presence;
    profile.foam = profile.encodedProfile.b * profile.presence;

    return profile;
}

//解码转换为世界空间位移
float3 ComputeShoreWaveDisplacement(ShorelineData shoreline, ShoreWaveProfile profile)
{
    float2 horizontalOffset = shoreline.directionToShore * profile.forwardUpward.x;//xz方向水平位移和y方向垂直位移
    return float3(horizontalOffset.x, profile.forwardUpward.y, horizontalOffset.y);
}

#endif