#ifndef SHORELINE_WAVE_INCLUDED
#define SHORELINE_WAVE_INCLUDED

TEXTURE2D(_CoastlineMap);
SAMPLER(sampler_CoastlineMap);
TEXTURE2D(_GroundHeightMap);
SAMPLER(sampler_GroundHeightMap);
TEXTURE2D(_WaveProfileMap);
SAMPLER(sampler_WaveProfileMap);
TEXTURE2D(_SmoothNoiseMap);
SAMPLER(sampler_SmoothNoiseMap);

float4 _CoastMapMinSize;
float _MaxCoastDistance;
float4 _GroundHeightDecodeRange;
float _WaterLevel;
float _FFTBlendStart;
float _FFTBlendEnd;
float _ShoreWaveWidth;
float _ShoreWaveScale;

float4 _WaveProfileDecode;
float _WaveProfileWidth;
float _WaveProfileDistance;
float _WaveProfileSpeed;
float _WaveProfileAnimationSpeed;
float _WaveProfileOffsetStrength;
float _WaveForwardTweak;
float _WaveGroundPrediction;

float _TimeOffset;
float _IsNeedTime;
float _WaveTimeStrength;
float _IsNeedDetail;
float _IsNeedNoise;

float _WaveSinStrength;
float _WaveCosStrength;
float _WaveSinFrequency;
float _WaveCosFrequency;
float _WaveDetailSinStrength;
float _WaveDetailCosStrength;
float _WaveDetailSinFrequency;
float _WaveDetailCosFrequency;

float _NoiseTime;
float _NoiseScale;
float _NoiseMapSampleScale;

struct Coastline
{
    float distance;
    float2 direction;
};

struct ShorelineData
{
    float4 encodedCoast;
    float2 coastUV;
    float2 directionToShore;
    float waterDistance;
    float waveScale;
    float fftWeight;
    float insideMap;
};

// 输入：世界空间 XZ 坐标。
// 输出：对应 CoastlineMap 烘焙范围的 UV 坐标。
// 用途：保证所有水面网格使用统一的世界坐标采样海岸数据。
float2 CoastWorldToUV(float2 worldXZ)
{
    float2 coastMinXZ = _CoastMapMinSize.xy;
    float2 coastSizeXZ = max(_CoastMapMinSize.zw, float2(0.0001, 0.0001));
    return (worldXZ - coastMinXZ) / coastSizeXZ;
}

// 输入：待检测的 CoastlineMap UV 坐标。
// 输出：位于 0～1 采样范围内时为 1，否则为 0。
// 用途：阻止烘焙范围外的坐标错误读取贴图边缘数据。
float IsInsideCoastMap(float2 coastUV)
{
    float2 aboveMinimum = step(float2(0.0, 0.0), coastUV);
    float2 belowMaximum = step(coastUV, float2(1.0, 1.0));
    return aboveMinimum.x * aboveMinimum.y * belowMaximum.x * belowMaximum.y;
}

// 输入：GroundHeightMap R 通道中直接存储的世界空间 Y 高度。
// 输出：限制在本次烘焙高度范围内的地形世界空间 Y 高度。
// 用途：遵循当前 RFloat 高度图契约，并用 CoastlineBakeAsset 的范围过滤采样误差。
float DecodeGroundHeight(float storedWorldHeight)
{
    float minimumHeight = min(_GroundHeightDecodeRange.x, _GroundHeightDecodeRange.y);
    float maximumHeight = max(_GroundHeightDecodeRange.x, _GroundHeightDecodeRange.y);
    return clamp(storedWorldHeight, minimumHeight, maximumHeight);
}

// 输入：未发生任何水面位移的世界空间 XZ 坐标。
// 输出：当前位置由 GroundHeightMap 记录的地形世界空间 Y 高度。
// 用途：复用 CoastlineMap 的世界范围，在顶点阶段取得后续拍岸约束所需的地形高度。
float SampleGroundHeight(float2 worldXZ)
{
    float2 groundUV = CoastWorldToUV(worldXZ);
    float storedWorldHeight = SAMPLE_TEXTURE2D_LOD(
        _GroundHeightMap,
        sampler_GroundHeightMap,
        saturate(groundUV),
        0).r;
    return DecodeGroundHeight(storedWorldHeight);
}

// 输入：CoastlineMap GB 通道存储的 0～1 编码方向。
// 输出：归一化后的世界空间 XZ 朝岸方向，无有效方向时返回零向量。
// 用途：将 Profile 的水平位移旋转到局部海岸的拍岸方向。
float2 DecodeDirectionToShore(float2 encodedDirection)
{
    float2 direction = encodedDirection * 2.0 - 1.0;
    float lengthSquared = dot(direction, direction);
    float validDirection = step(0.000001, lengthSquared);
    return direction * rsqrt(max(lengthSquared, 0.000001)) * validDirection;
}

// 输入：CoastlineMap R 通道存储的有符号距离编码。
// 输出：以米为单位的有符号离岸距离，水中为正、陆地为负。
// 用途：恢复 FF2 Profile UV 和远近海过渡所需的真实距离。
float DecodeWaterDistance(float encodedDistance)
{
    return (0.5 - encodedDistance) * 2.0 * max(_MaxCoastDistance, 0.0001);
}

// 输入：以米为单位的离岸距离，以及 CoastlineMap GB 通道的编码方向。
// 输出：仅在 SDF 最远水域且方向失效时为 1 的远水保护遮罩。
// 用途：适配当前烘焙贴图在 60m 外写入中性方向的契约，避免把海岸线中心的中性方向误判为远洋。
float ComputeFarWaterMask(float waterDistance, float2 encodedDirection)
{
    float encodedDirectionLength = length(0.5 - encodedDirection);
    float invalidDirectionMask = saturate(
        encodedDirectionLength * -4.54545 + 2.159091);
    float farDistanceMask = step(
        max(_MaxCoastDistance, 0.0001) * 0.99,
        waterDistance);
    return invalidDirectionMask * farDistanceMask;
}

// 输入：以米为单位的有符号离岸距离和远水保护遮罩。
// 输出：近岸为 0、远洋为 1 的 FFT 混合权重。
// 用途：复现 FF2 的线性海岸层混合，避免旧 smoothstep 在起点前把大范围 FFT 完全压成零。
float ComputeFFTWeight(float waterDistance, float farWaterMask)
{
    float distanceBlend = saturate(
        (waterDistance + _ShoreWaveWidth) *
        max(_ShoreWaveScale, 0.0));
    return min(distanceBlend + farWaterMask, 1.0);
}

// 输入：CoastlineMap UV 坐标。
// 输出：CoastlineMap 的 RGBA 编码数据。
// 用途：以 LOD 0 读取顶点阶段所需的海岸距离、方向和附加权重。
float4 SampleEncodedCoast(float2 coastUV)
{
    return SAMPLE_TEXTURE2D_LOD(_CoastlineMap, sampler_CoastlineMap, saturate(coastUV), 0);
}

// 输入：未发生任何水面位移的世界空间 XZ 坐标。
// 输出：包含贴图数据、离岸距离、朝岸方向和 FFT 权重的 ShorelineData。
// 用途：集中完成 CoastlineMap 的范围检测、采样与解码。
ShorelineData EvaluateShorelineData(float2 worldXZ)
{
    ShorelineData data;
    data.coastUV = CoastWorldToUV(worldXZ);
    data.insideMap = IsInsideCoastMap(data.coastUV);
    data.encodedCoast = SampleEncodedCoast(data.coastUV);

    float outsideDistance = max(_MaxCoastDistance, 0.0001);
    float decodedDistance = DecodeWaterDistance(data.encodedCoast.r);

    data.waterDistance = lerp(outsideDistance, decodedDistance, data.insideMap);
    data.directionToShore = DecodeDirectionToShore(data.encodedCoast.gb) * data.insideMap;
    data.waveScale = lerp(1.0, data.encodedCoast.a, data.insideMap);

    float farWaterMask = ComputeFarWaterMask(
        data.waterDistance,
        data.encodedCoast.gb);
    data.fftWeight = lerp(
        1.0,
        ComputeFFTWeight(data.waterDistance, farWaterMask),
        data.insideMap);
    return data;
}

// 输入：已经完成贴图解码的 ShorelineData。
// 输出：FF2 顶点动画函数使用的精简 Coastline 数据。
// 用途：隔离工程贴图数据契约与仓库 Profile 动画算法的数据契约。
Coastline GetCoastline(ShorelineData shoreline)
{
    Coastline coastline;
    coastline.distance = shoreline.waterDistance;
    coastline.direction = shoreline.directionToShore;
    return coastline;
}

// 输入：离岸距离、朝岸方向和未位移的世界空间 XZ 坐标。
// 输出：沿岸时间相位偏移和 Profile 生命周期细节偏移。
// 用途：通过沿岸坐标、Sin/Cos 和世界空间噪声打破笔直且同步的浪线。
void CoastlineOffsets(
    float distance,
    float2 direction,
    float2 posWS,
    out float timeOffset,
    out float detailOffset)
{
    float Py = posWS.y + direction.y * distance;
    float3 PyOffset = Py * float3(
        0.121,
        0.242 * _WaveSinFrequency,
        0.7517 * _WaveCosFrequency);

    timeOffset = PyOffset.x;
    timeOffset += sin(PyOffset.y) * -0.135 * _WaveSinStrength;
    timeOffset += cos(PyOffset.z) * -0.0375 * _WaveCosStrength;

    float noiseSampleScale = max(abs(_NoiseMapSampleScale), 0.0001);
    float timeNoise = SAMPLE_TEXTURE2D_LOD(
        _SmoothNoiseMap,
        sampler_SmoothNoiseMap,
        posWS * 0.5 * noiseSampleScale,
        0).r - 0.5;

    timeNoise *= saturate(distance * 0.35 - 0.05) * _NoiseTime;
    timeOffset += lerp(0.0, timeNoise, saturate(_IsNeedNoise));

    PyOffset = Py * float3(
        0.121,
        0.242 * _WaveDetailSinFrequency * 0.2,
        0.7517 * _WaveDetailCosFrequency * 0.2);

    detailOffset = sin(PyOffset.y) * -0.25 * _WaveDetailSinStrength;
    detailOffset += cos(PyOffset.z) * 0.15 * _WaveDetailCosStrength;

    float detailNoise = SAMPLE_TEXTURE2D_LOD(
        _SmoothNoiseMap,
        sampler_SmoothNoiseMap,
        posWS * 1.5 / noiseSampleScale,
        0).r;

    detailNoise = (detailNoise * 0.5 - 0.5) * _NoiseScale;
    detailOffset += lerp(0.0, detailNoise, saturate(_IsNeedNoise));
}

// 输入：未位移的世界空间坐标和精简 Coastline 数据。
// 输出：用于采样 WaveProfileMap 的二维 UV。
// 用途：让 U 控制向岸传播与周期重复，让 V 控制每道浪的生命周期动画。
float2 GetProfileUV(float3 posWS, Coastline coastline)
{
    float timeOffset;
    float detailOffset;
    CoastlineOffsets(
        coastline.distance,
        coastline.direction,
        posWS.xz,
        timeOffset,
        detailOffset);

    float profileWidth = max(_WaveProfileWidth, 0.0001);
    float profileU = _WaveProfileDistance - coastline.distance / profileWidth;
    float profileUTime = _Time.y * _WaveProfileSpeed * saturate(_IsNeedTime);
    profileUTime += _TimeOffset + _WaveTimeStrength * timeOffset;

    float finalProfileU = profileU - profileUTime;
    float profileV = profileU + lerp(0.0, detailOffset, saturate(_IsNeedDetail));
    float finalProfileV = (profileV - frac(finalProfileU)) * _WaveProfileAnimationSpeed;
    return float2(finalProfileU, finalProfileV);
}

// 输入：GetProfileUV 生成的 Profile UV。
// 输出：水平向岸位移、垂直位移，并通过 foam 输出 B 通道泡沫数据。
// 用途：按照当前 Profile 纹理的 Decode 契约恢复实际位移幅度。
float2 SampleProfileMap(float2 profileUV, out float foam)
{
    float4 encodedProfile = SAMPLE_TEXTURE2D_LOD(
        _WaveProfileMap,
        sampler_WaveProfileMap,
        profileUV,
        0);

    float2 decodeScale = _WaveProfileDecode.zw * max(_WaveProfileWidth, 0.0001);
    foam = encodedProfile.b;
    return (encodedProfile.rg + _WaveProfileDecode.xy) * decodeScale;
}

// 输入：Profile 的水平与垂直位移，以及局部 Coastline 朝岸方向。
// 输出：Unity 世界空间 XYZ 位移。
// 用途：将一维 Profile 位移转换为沿局部海岸方向传播的三维顶点位移。
float3 GetFluxOffset(float2 forwardUpward, Coastline coastline)
{
    float2 horizontalOffset = coastline.direction * forwardUpward.x * _WaveForwardTweak;
    return float3(horizontalOffset.x, forwardUpward.y, horizontalOffset.y);
}

// 输入：局部 Coastline 数据、未位移的世界空间 XZ 坐标。
// 输出：沿朝岸方向预测地形后得到的 Unity 世界空间坡面法线。
// 用途：复现 FF2 的 MF_SlopeNormal，使近岸浪的前向位移能够沿沙滩坡度运动。
float3 ComputeCoastSlopeNormal(Coastline coastline, float2 worldXZ)
{
    float prediction = max(_WaveGroundPrediction, 0.0001);
    float2 predictionOffset = coastline.direction * prediction;
    float currentGroundHeight = SampleGroundHeight(worldXZ);
    float predictedGroundHeight = SampleGroundHeight(worldXZ + predictionOffset);
    float groundHeightDelta = predictedGroundHeight - currentGroundHeight;
    float3 slopeVector = float3(
        predictionOffset.x,
        groundHeightDelta,
        predictionOffset.y);
    float slopeLengthSquared = dot(slopeVector, slopeVector);
    float validSlope = step(0.000001, slopeLengthSquared);
    return slopeVector *
        rsqrt(max(slopeLengthSquared, 0.000001)) *
        validSlope;
}

// 输入：Profile 水平/垂直位移、局部 Coastline 数据和预测得到的坡面法线。
// 输出：由沙滩坡面方向逐渐过渡到水平朝岸方向的 Unity 世界空间位移。
// 用途：复现 FF2 的 MF_CoastSlope，让浪在贴近岸边时沿坡爬升、离岸后恢复水平传播。
float3 GetFluxSlopeOffset(
    float2 forwardUpward,
    Coastline coastline,
    float3 slopeNormal)
{
    float prediction = max(_WaveGroundPrediction, 0.0001);
    float slopeBlend = saturate((coastline.distance - 0.1) / prediction);
    float3 horizontalDirection = float3(
        coastline.direction.x,
        0.0,
        coastline.direction.y);
    float3 forwardDirection = lerp(
        slopeNormal,
        horizontalDirection,
        slopeBlend);
    float3 forwardOffset = forwardDirection * forwardUpward.x * _WaveForwardTweak;
    return forwardOffset + float3(0.0, forwardUpward.y, 0.0);
}

// 输入：完整 ShorelineData 和未位移的世界空间 XZ 坐标。
// 输出：与 GetProfileUV 相同的二维 Profile UV。
// 用途：为 Water.shader 现有的 U/V 调试视图提供兼容入口。
float2 ComputeShoreWaveProfileUV(ShorelineData shoreline, float2 worldXZ)
{
    float3 positionWS = float3(worldXZ.x, 0.0, worldXZ.y);
    return GetProfileUV(positionWS, GetCoastline(shoreline));
}

#endif
