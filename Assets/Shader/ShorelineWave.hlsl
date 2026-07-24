#ifndef SHORELINE_WAVE_INCLUDED
#define SHORELINE_WAVE_INCLUDED

TEXTURE2D(_CoastlineMap);
SAMPLER(sampler_CoastlineMap);
float4 _CoastlineMap_TexelSize;
TEXTURE2D(_GroundHeightMap);
SAMPLER(sampler_GroundHeightMap);
TEXTURE2D(_WaveProfileMap);
SAMPLER(sampler_WaveProfileMap);
TEXTURE2D(_SmoothNoiseMap);
SAMPLER(sampler_SmoothNoiseMap);

TEXTURE2D(_FoamNormalSoftHeightMap);
SAMPLER(sampler_FoamNormalSoftHeightMap);

float4 _CoastMapMinSize;
float _MaxCoastDistance;
float4 _GroundHeightDecodeRange;
float _ShoreWaveWidth;
float _ShoreWaveScale;

float4 _WaveProfileDecode;
float _WaveProfileWidth;
float _WaveProfileDistance;
float _WaveProfileSpeed;
float _WaveProfileAnimationSpeed;
float _WaveProfileOffsetStrength;
float _WaveProfileHeightStrength;
float _WaveProfileForwardStrength;
float _WaveMaxShorewardDistance;
float _WaveForwardTweak;
float _WaveGroundPrediction;
float _CoastDirectionGradientRadius;
float _CoastDirectionGradientBlend;

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

float _FoamUVAdvectionOffset;
float _FoamUVAdvectionVelocity;
float _FoamUVRandomization;
float _FoamUVScale;
float _FoamUVSpeed;

float _CoastlineVelocityScale;

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
    float directionDiscontinuity;
    float waterDistance;
    float waveScale;
    float fftWeight;
    float insideMap;
};

// 保存 FF2 Edge Correction 输出的修正位移。
struct ShoreEdgeCorrection
{
    float3 displacement;
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

// 输入：CoastlineMap UV，以及以纹素为单位的距离梯度采样半径。
// 输出：由 SDF R 通道重建并在 GB 跳变区域平滑后的朝岸方向，同时输出方向不连续度。
// 用途：在凹岸和最近海岸目标切换处使用较宽的标量距离梯度代替突变的 GB 方向，减少相邻顶点被拉向不同方向。
float2 ResolveCoastDirection(
    float2 coastUV,
    float sampleRadius,
    out float directionDiscontinuity)
{
    float safeRadius = max(sampleRadius, 1.0);
    float2 texelOffset =
        _CoastlineMap_TexelSize.xy * safeRadius;

    float4 encodedLeft = SampleEncodedCoast(
        coastUV - float2(texelOffset.x, 0.0));
    float4 encodedRight = SampleEncodedCoast(
        coastUV + float2(texelOffset.x, 0.0));
    float4 encodedDown = SampleEncodedCoast(
        coastUV - float2(0.0, texelOffset.y));
    float4 encodedUp = SampleEncodedCoast(
        coastUV + float2(0.0, texelOffset.y));
    float4 encodedCenter = SampleEncodedCoast(coastUV);

    float2 centerDirection =
        DecodeDirectionToShore(encodedCenter.gb);
    float2 leftDirection =
        DecodeDirectionToShore(encodedLeft.gb);
    float2 rightDirection =
        DecodeDirectionToShore(encodedRight.gb);
    float2 downDirection =
        DecodeDirectionToShore(encodedDown.gb);
    float2 upDirection =
        DecodeDirectionToShore(encodedUp.gb);

    float leftValid = step(
        0.000001,
        dot(leftDirection, leftDirection));
    float rightValid = step(
        0.000001,
        dot(rightDirection, rightDirection));
    float downValid = step(
        0.000001,
        dot(downDirection, downDirection));
    float upValid = step(
        0.000001,
        dot(upDirection, upDirection));

    float centerWaterSide = step(encodedCenter.r, 0.5);
    float leftWaterSide = step(encodedLeft.r, 0.5);
    float rightWaterSide = step(encodedRight.r, 0.5);
    float downWaterSide = step(encodedDown.r, 0.5);
    float upWaterSide = step(encodedUp.r, 0.5);

    leftValid *= 1.0 - abs(centerWaterSide - leftWaterSide);
    rightValid *= 1.0 - abs(centerWaterSide - rightWaterSide);
    downValid *= 1.0 - abs(centerWaterSide - downWaterSide);
    upValid *= 1.0 - abs(centerWaterSide - upWaterSide);

    float leftAgreement = lerp(
        1.0,
        dot(centerDirection, leftDirection),
        leftValid);
    float rightAgreement = lerp(
        1.0,
        dot(centerDirection, rightDirection),
        rightValid);
    float downAgreement = lerp(
        1.0,
        dot(centerDirection, downDirection),
        downValid);
    float upAgreement = lerp(
        1.0,
        dot(centerDirection, upDirection),
        upValid);

    float minimumAgreement = min(
        min(leftAgreement, rightAgreement),
        min(downAgreement, upAgreement));
    directionDiscontinuity =
        1.0 - saturate(minimumAgreement * 0.5 + 0.5);

    float2 worldStep = max(
        _CoastMapMinSize.zw * texelOffset,
        float2(0.0001, 0.0001));
    float2 distanceGradient = float2(
        (encodedRight.r - encodedLeft.r) / worldStep.x,
        (encodedUp.r - encodedDown.r) / worldStep.y);
    float gradientLengthSquared =
        dot(distanceGradient, distanceGradient);
    float gradientValid =
        step(0.000001, gradientLengthSquared);
    float2 gradientDirection =
        distanceGradient *
        rsqrt(max(gradientLengthSquared, 0.000001));

    float gradientWeight =
        smoothstep(0.08, 0.45, directionDiscontinuity) *
        saturate(_CoastDirectionGradientBlend) *
        gradientValid;
    float2 resolvedDirection = lerp(
        centerDirection,
        gradientDirection,
        gradientWeight);
    float resolvedLengthSquared =
        dot(resolvedDirection, resolvedDirection);
    float resolvedValid =
        step(0.000001, resolvedLengthSquared);

    return resolvedDirection *
        rsqrt(max(resolvedLengthSquared, 0.000001)) *
        resolvedValid;
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
    data.directionToShore = ResolveCoastDirection(
        data.coastUV,
        _CoastDirectionGradientRadius,
        data.directionDiscontinuity);
    data.directionToShore *= data.insideMap;
    data.directionDiscontinuity *= data.insideMap;
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
    finalProfileV = 1 - finalProfileV;
    
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
    // 按 FF3 原始逻辑直接采样 GetProfileUV 输出，不再额外反转 U 方向。

    float2 decodeScale = _WaveProfileDecode.zw * max(_WaveProfileWidth, 0.0001);
    foam = encodedProfile.b;
    float2 decodedProfile =
        (encodedProfile.rg + _WaveProfileDecode.xy) * decodeScale;
    // 按 Profile Decode 契约恢复水平和垂直位移的原始世界尺度。
    decodedProfile.y *= _WaveProfileHeightStrength;
    // 独立放大浪峰高度，保持朝岸水平位移和地形边缘修正范围不变。
    return decodedProfile;
}

// 输入：经过强度缩放的有符号 Profile 前向位移。
// 输出：离岸回退保持不变、朝岸峰值经过柔性阈值压缩的前向位移。
// 用途：只压缩可能造成相邻顶点大跨度拉伸的朝岸位移峰值，同时保留完整的回退动画。
float LimitShorewardTravel(float signedForward)
{
    float maximumDistance =
        max(_WaveMaxShorewardDistance, 0.0001);
    float positiveForward = max(signedForward, 0.0);
    float negativeForward = min(signedForward, 0.0);

    float kneeStart = maximumDistance * 0.75;
    float kneeRange =
        max(maximumDistance - kneeStart, 0.0001);
    float excess =
        max(positiveForward - kneeStart, 0.0);
    float compressedForward =
        kneeStart +
        kneeRange *
        (1.0 - exp(-excess / kneeRange));
    float limitedForward = lerp(
        positiveForward,
        compressedForward,
        step(kneeStart, positiveForward));

    return negativeForward + limitedForward;
}

// 输入：Profile 解码出的前向位移和当前采样点的 Coastline 数据。
// 输出：经过用户强度、SDF 新增位移限制和朝岸柔性阈值处理的前向位移。
// 用途：限制过大的单帧朝岸位移跨度，减少三角形拉伸，同时保持离岸回退不受阈值影响。
float ComputeSafeProfileForward(float decodedForward, Coastline coastline)
{
    float baseForward = decodedForward * _WaveForwardTweak;
    // 保留当前工程已有的 FF2 前向位移作为强度为 1 时的基准结果。

    float requestedForward = baseForward * _WaveProfileForwardStrength;
    // 根据新参数计算用户期望的完整水平推进距离。

    float addedTowardShore = max(requestedForward - baseForward, 0.0);
    // 只提取相对当前状态新增的朝岸位移，原有位移不会被安全限制改变。

    float2 coastTexelWorldSize =
        _CoastMapMinSize.zw * _CoastlineMap_TexelSize.xy;
    // 将 CoastlineMap 单个纹素换算为世界空间尺寸，为低精度 SDF 留出安全余量。

    float shoreClearance =
        max(max(coastTexelWorldSize.x, coastTexelWorldSize.y), 0.05);
    // 至少保留一个 SDF 纹素或 5cm 的岸线间隔，避免插值误差把新增位移送入陆地。

    float availableTowardShore = max(
        coastline.distance - shoreClearance - max(baseForward, 0.0),
        0.0);
    // 从当前水深距离中扣除基准推进与安全余量，得到仍可使用的新增朝岸距离。

    float safeAddedTowardShore =
        min(addedTowardShore, availableTowardShore);
    // 将新增推进限制在剩余水域范围内，离岸回摆不受影响。

    float sdfSafeForward =
        requestedForward -
        addedTowardShore +
        safeAddedTowardShore;

    return LimitShorewardTravel(sdfSafeForward);
}

// 输入：局部 Coastline 数据、未位移世界坐标和经过强度处理的有符号 Profile 推进距离。
// 输出：结合固定预测坡度与本帧实际落点高度得到的 Unity 世界空间朝岸坡面方向。
// 用途：让推进与回退沿各自真实落点的地形坡度运动，避免固定 2m 预测无法跟随弯曲沙滩。
float3 ComputeCoastSlopeNormal(
    Coastline coastline,
    float2 worldXZ,
    float signedForward)
{
    float prediction = max(_WaveGroundPrediction, 0.0001);
    float currentGroundHeight = SampleGroundHeight(worldXZ);

    float2 predictionOffset =
        coastline.direction * prediction;
    float predictedGroundHeight =
        SampleGroundHeight(worldXZ + predictionOffset);
    float3 predictedSlope = float3(
        predictionOffset.x,
        predictedGroundHeight - currentGroundHeight,
        predictionOffset.y);
    float predictedLengthSquared =
        dot(predictedSlope, predictedSlope);
    predictedSlope *=
        rsqrt(max(predictedLengthSquared, 0.000001));

    float2 landingOffset =
        coastline.direction * signedForward;
    float landingGroundHeight =
        SampleGroundHeight(worldXZ + landingOffset);
    float motionSign = lerp(
        -1.0,
        1.0,
        step(0.0, signedForward));
    float3 landingSlope = float3(
        landingOffset.x,
        landingGroundHeight - currentGroundHeight,
        landingOffset.y) * motionSign;
    float landingLengthSquared =
        dot(landingSlope, landingSlope);
    float landingValid =
        step(0.000001, landingLengthSquared);
    landingSlope *=
        rsqrt(max(landingLengthSquared, 0.000001));

    float landingWeight =
        saturate(abs(signedForward) / prediction) *
        landingValid;
    float3 resolvedSlope = lerp(
        predictedSlope,
        landingSlope,
        landingWeight);
    float resolvedLengthSquared =
        dot(resolvedSlope, resolvedSlope);

    return resolvedSlope *
        rsqrt(max(resolvedLengthSquared, 0.000001));
}

// 输入：Profile 水平/垂直位移、局部 Coastline 数据和当前未位移世界空间 XZ。
// 输出：沿自适应沙滩坡度传播，并保持源点地形净空的 Unity 世界空间位移。
// 用途：在保留 Profile 推进和回退周期的同时，根据实际落点修正爬坡高度，减少顶点进入 Terrain。
float3 GetFluxSlopeOffset(
    float2 forwardUpward,
    Coastline coastline,
    float2 worldXZ)
{
    float prediction = max(_WaveGroundPrediction, 0.0001);
    float slopeBlend =
        saturate((coastline.distance - 0.1) / prediction);
    float3 horizontalDirection = float3(
        coastline.direction.x,
        0.0,
        coastline.direction.y);

    float safeForward =
        ComputeSafeProfileForward(forwardUpward.x, coastline);
    float3 slopeDirection = ComputeCoastSlopeNormal(
        coastline,
        worldXZ,
        safeForward);
    float3 forwardDirection = lerp(
        slopeDirection,
        horizontalDirection,
        slopeBlend);
    float3 forwardOffset =
        forwardDirection * safeForward;

    float sourceGroundHeight =
        SampleGroundHeight(worldXZ);
    float landingGroundHeight =
        SampleGroundHeight(worldXZ + forwardOffset.xz);
    float requiredTerrainRise =
        landingGroundHeight - sourceGroundHeight;
    float terrainFollowWeight =
        step(0.0001, safeForward) *
        (1.0 - slopeBlend);
    forwardOffset.y = lerp(
        forwardOffset.y,
        max(forwardOffset.y, requiredTerrainRise),
        terrainFollowWeight);

    return forwardOffset +
        float3(0.0, forwardUpward.y, 0.0);
}

// 输入：相对基础采样点的世界空间 XZ 偏移和基础 Coastline 数据。
// 输出：距离已随偏移修正、方向保持不变的 Coastline 数据。
// 用途：复现 FF2 的 MF_CoastlineTransform，使三个法线采样点保持连续的 Profile 相位。
Coastline GetOffsetCoastline(float2 worldOffsetXZ, Coastline coastline)
{
    Coastline offsetCoastline = coastline;
    // 保留基础点解码出的朝岸方向，避免三个采样点分别读取 SDF 时产生方向跳变。

    offsetCoastline.distance =
        coastline.distance - dot(worldOffsetXZ, coastline.direction);
    // 将世界偏移投影到朝岸方向并修正有符号距离，复现 FF2 的非局部空间距离变换。

    return offsetCoastline;
}

// 输入：基础世界坐标、采样偏移、基础 Coastline 和近岸强度。
// 输出：该偏移采样点经过 Profile 与自适应落点坡度位移后的绝对世界坐标。
// 用途：让三点法线的每个邻点复用正式顶点的落点地形预测，保证法线与实际几何一致。
float3 SampleShorelineDisplacedPoint(
    float3 sourcePositionWS,
    float2 worldOffsetXZ,
    Coastline coastline,
    float waveScale)
{
    Coastline offsetCoastline =
        GetOffsetCoastline(worldOffsetXZ, coastline);

    float3 offsetPositionWS =
        sourcePositionWS +
        float3(worldOffsetXZ.x, 0.0, worldOffsetXZ.y);

    float2 profileUV =
        GetProfileUV(offsetPositionWS, offsetCoastline);

    float unusedFoam;
    float2 forwardUpward =
        SampleProfileMap(profileUV, unusedFoam);

    float3 shorelineDisplacement =
        GetFluxSlopeOffset(
            forwardUpward,
            offsetCoastline,
            offsetPositionWS.xz);

    shorelineDisplacement *= waveScale;
    shorelineDisplacement *= _WaveProfileOffsetStrength;

    return offsetPositionWS + shorelineDisplacement;
}

// 输入：基础海岸数据、未位移世界坐标和世界空间三点采样间距。
// 输出：由三个 Profile 位移后位置重建的 Unity 世界空间向上几何法线。
// 用途：复现 FF2 的三点法线方法，使近岸浪法线来自真实位移而不是远洋 FFT 坡度。
float3 ComputeShorelineTriangleNormal(
    ShorelineData shoreline,
    float3 sourcePositionWS,
    float sampleRange)
{
    float safeSampleRange = max(sampleRange, 0.001);
    // 防止采样点重合导致叉积为零并产生无效法线。

    Coastline coastline = GetCoastline(shoreline);
    // 将基础 SDF 数据转换为 FF2 Profile 采样使用的 Coastline 数据。

    float3 positionCenter = SampleShorelineDisplacedPoint(
        sourcePositionWS,
        float2(0.0, 0.0),
        coastline,
        shoreline.waveScale);
    // 计算基础点经过完整近岸 Profile 位移后的世界坐标。

    float3 positionX = SampleShorelineDisplacedPoint(
        sourcePositionWS,
        float2(safeSampleRange, 0.0),
        coastline,
        shoreline.waveScale);
    // 沿世界 X 正方向采样第二个 Profile 位移后位置。

    float3 positionZ = SampleShorelineDisplacedPoint(
        sourcePositionWS,
        float2(0.0, safeSampleRange),
        coastline,
        shoreline.waveScale);
    // 沿世界 Z 正方向采样第三个 Profile 位移后位置。

    float3 tangentX = positionX - positionCenter;
    // 构建位移后曲面沿世界 X 方向的切线。

    float3 tangentZ = positionZ - positionCenter;
    // 构建位移后曲面沿世界 Z 方向的切线。

    float3 normalVector = cross(tangentZ, tangentX);
    // Unity 使用 Y 轴向上，因此以 Z 切线叉乘 X 切线得到朝上的法线方向。

    float normalLengthSquared = dot(normalVector, normalVector);
    float validNormal = step(0.000001, normalLengthSquared);
    float3 normalizedNormal =
        normalVector * rsqrt(max(normalLengthSquared, 0.000001));
    // 对叉积执行安全归一化，避免退化三角形再次把 NaN 传入顶点流程。

    return lerp(float3(0.0, 1.0, 0.0), normalizedNormal, validNormal);
}

// 输入：海岸数据、未位移世界坐标和经过坡度处理的近岸候选位移。
// 输出：水平分量不变、垂直分量经过地形边缘限制的 ShoreEdgeCorrection。
// 用途：复现 FF2 的 MF_EdgeCorrection，防止水平位移后的浪峰穿入或越过沙滩地形。
ShoreEdgeCorrection ComputeShoreEdgeCorrection(
    ShorelineData shoreline,
    float3 sourcePositionWS,
    float3 shorelineDisplacement)
{
    ShoreEdgeCorrection correction;
    // 创建独立结果，供下一阶段在 Water.shader 中选择性接入。

    float2 displacedXZ =
        sourcePositionWS.xz + shorelineDisplacement.xz;
    // 按 FF2 规则在水平位移后的落点重新查询地形，而不是继续使用原顶点位置。

    float groundWorldHeight = SampleGroundHeight(displacedXZ);
    // 获取候选浪实际将要到达位置的地形世界高度。

    float candidateWorldHeight =
        sourcePositionWS.y + shorelineDisplacement.y;
    // 将 Profile 垂直位移转换为修正前的候选世界高度。

    float shorelineEdgeBlend = saturate(
        shoreline.waterDistance * 2.5 - 0.5);
    // 将 FF2 的 Distance*0.025-0.5 从厘米换算到米，使修正于约 0.2m 到 0.6m 内退出。

    float correctedWorldHeight = lerp(
        groundWorldHeight - 0.05,
        candidateWorldHeight,
        shorelineEdgeBlend);
    // 将 FF2 的 5cm 地形间隙换算为 0.05m，并在最靠岸区域把水面压到地形下方。

    correctedWorldHeight = min(
        correctedWorldHeight,
        candidateWorldHeight);
    // 保留 FF2 的单向限制，只允许压低候选浪高，绝不因为地形修正额外抬升顶点。

    float correctionMask = saturate(
        shoreline.insideMap * shoreline.waveScale);
    // 仅对烘焙范围内的有效水域启用修正，避免陆地和 SDF 范围外再次产生异常位移。

    correctedWorldHeight = lerp(
        candidateWorldHeight,
        correctedWorldHeight,
        correctionMask);
    // 在无有效海岸数据时完整保留输入位移，保证远洋 FFT 分支不受高度图影响。

    correction.displacement = float3(
        shorelineDisplacement.x,
        correctedWorldHeight - sourcePositionWS.y,
        shorelineDisplacement.z);
    // 把修正后的世界高度重新转换为 Water.shader 可以直接累加的世界空间位移。

    return correction;
    // 返回尚未接入正式顶点链的地形边缘修正结果。
}

// 输入：完整 ShorelineData 和未位移的世界空间 XZ 坐标。
// 输出：与 FF3 WaveProfileMap 实际采样完全一致的二维 UV。
// 用途：让 Water.shader 的 U/V 调试视图显示未经过额外翻转的仓库原始 Profile UV。
float2 ComputeShoreWaveProfileUV(ShorelineData shoreline, float2 worldXZ)
{
    float3 positionWS = float3(worldXZ.x, 0.0, worldXZ.y);
    float2 profileUV = GetProfileUV(
        positionWS,
        GetCoastline(shoreline));
    // 直接保留 FF3 的距离、时间、Detail 和生命周期坐标计算结果。
    return profileUV;
}




// 保存 FF3 三相泡沫平流所需的权重与三组世界空间 UV。
struct ShorelineFoamAdvection
{
    float3 weights;
    float2 uv1;
    float2 uv2;
    float2 uv3;
};

// 保存 T_Seafoam_03_NSH 解码后的法线、柔软泡沫和泡沫高度。
struct ShorelineFoamTextureSample
{
    float2 normalXY;
    float3 normalWS;
    float soft;
    float height;
};


// 输入：当前海岸数据，以及尚未经过 Edge Correction 的近岸 Profile 世界空间位移。
// 输出：以 Unity 米制世界空间表示、仅在有效近岸区域存在的二维泡沫速度。
// 用途：复现 FF3 的 Coastline Velocity，让 NSH 泡沫纹理跟随拍岸浪推进和回落。
float2 ComputeShorelineFoamVelocity(
    ShorelineData shoreline,
    float3 profileDisplacement)
{
    float directionVelocityScale =
        (saturate(shoreline.waterDistance * 0.5) - 0.5) * 0.001;
    // 将 FF3 的 Distance*0.005 与 0.1cm 基础速度换算为 Unity 米制。
    float2 velocity =
        shoreline.directionToShore * directionVelocityScale;
    // 沿局部朝岸方向生成靠岸与离岸两侧不同符号的基础流速。
    float displacementVelocityScale =
        (saturate(shoreline.waterDistance * 0.4) - 0.08) *
        _CoastlineVelocityScale;
    // 将 FF3 的 Distance*0.004 换算为米制，并保留原 Coastline Velocity Scale。
    velocity +=
        profileDisplacement.xz * displacementVelocityScale;
    // 使用 Profile 水平位移补充随浪峰变化的局部泡沫速度。
    float validMask =
        shoreline.insideMap *
        (1.0 - shoreline.fftWeight);
    // 只让有效 CoastlineMap 内的近岸层携带泡沫速度，远洋继续由 FFT 管理。
    return velocity * validMask;
}

// 输入：已经乘以 Foam UV Speed 的循环时间。
// 输出：三组相差三分之一周期的偏移和总和稳定的交叉淡化权重。
// 用途：复现 FF3 的 AdvectionData，使泡沫纹理循环时不会突然跳回起点。
void GetShorelineFoamAdvectionData(
    float time,
    out float3 offsets,
    out float3 weights)
{
    offsets = frac(frac(time) + float3(0.0, 1.0, 2.0) / 3.0);
    // 将三组采样时间错开三分之一周期，保证任意时刻都有连续纹理可用。
    weights = float3(0.0, 1.0, 2.0) / 3.0 + frac(time);
    // 为三组时间构造同样错开的余弦权重输入。
    weights = 1.0 - cos(weights * (2.0 * PI));
    // 使用余弦曲线完成平滑交叉淡化，避免线性权重形成可见切换。
    weights *= 1.0 / 3.0;
    // 将三组余弦权重归一到稳定总能量。
}

// 输入：未位移世界空间 XZ，以及后续由近岸 Surface Flux 提供的世界空间速度。
// 输出：三组泡沫纹理 UV 和对应的交叉淡化权重。
// 用途：复现 FF3 的三相世界空间泡沫平流，并保留随机偏移和速度接口。
ShorelineFoamAdvection GetShorelineFoamAdvection(
    float2 worldXZ,
    float2 velocity)
{
    ShorelineFoamAdvection advection;
    float3 offsets;
    GetShorelineFoamAdvectionData(
        frac(_Time.y * _FoamUVSpeed),
        offsets,
        advection.weights);
    // 使用材质速度驱动三相周期，并取得 FF3 的时间偏移与交叉权重。

    float2 baseUV = worldXZ * _FoamUVScale;
    // 始终按未位移世界坐标生成 UV，避免泡沫纹理跟随浪峰网格一起游动。
    float2 advectedVelocity =
        -velocity * _FoamUVScale * _FoamUVAdvectionVelocity;
    // 将近岸速度转换为纹理空间反向平流速度。
    offsets += _FoamUVAdvectionOffset;
    // 对三组时间相位统一施加 FF3 的 Advection Offset。

    advection.uv1 = baseUV + offsets.x * advectedVelocity;
    // 第一组 UV 保持基础世界空间相位。
    advection.uv2 =
        baseUV +
        _FoamUVRandomization * float2(0.124905, 0.836666) +
        offsets.y * advectedVelocity;
    // 第二组 UV 使用 FF3 固定随机偏移，打破重复纹理的空间对齐。
    advection.uv3 =
        baseUV +
        _FoamUVRandomization * float2(0.500952, 0.887143) +
        offsets.z * advectedVelocity;
    // 第三组 UV 使用另一组固定偏移，与前两组形成稳定的三相交叉循环。
    return advection;
}

// 输入：未位移世界空间 XZ，以及后续用于驱动泡沫流向的世界空间速度。
// 输出：由三相采样混合得到的 Unity 世界空间法线、柔软泡沫与泡沫高度。
// 用途：按照 FF3 的 NSH 通道契约采样 T_Seafoam_03_NSH，为泡沫遮罩和泡沫法线提供数据。
ShorelineFoamTextureSample SampleShorelineFoamTexture(
    float2 worldXZ,
    float2 velocity)
{
    ShorelineFoamAdvection advection =
        GetShorelineFoamAdvection(worldXZ, velocity);
    // 先计算三组连续平流 UV 以及对应权重。

    float4 sample1 = SAMPLE_TEXTURE2D_LOD(
        _FoamNormalSoftHeightMap,
        sampler_FoamNormalSoftHeightMap,
        advection.uv1,
        0);
    // 在第一组世界空间 UV 上读取完整 NSH 数据。
    float4 sample2 = SAMPLE_TEXTURE2D_LOD(
        _FoamNormalSoftHeightMap,
        sampler_FoamNormalSoftHeightMap,
        advection.uv2,
        0);
    // 在第二组错相位 UV 上读取完整 NSH 数据。
    float4 sample3 = SAMPLE_TEXTURE2D_LOD(
        _FoamNormalSoftHeightMap,
        sampler_FoamNormalSoftHeightMap,
        advection.uv3,
        0);
    // 在第三组错相位 UV 上读取完整 NSH 数据。

    float4 encodedFoam =
        sample1 * advection.weights.x +
        sample2 * advection.weights.y +
        sample3 * advection.weights.z;
    // 按 FF3 的余弦权重合并三组采样，得到无跳变的连续泡沫纹理。
    ShorelineFoamTextureSample foamSample;
    foamSample.normalXY = encodedFoam.rg * 2.0 - 1.0;
    // 将 RG 从零到一范围恢复为切线平面的有符号法线分量。
    float normalUp = sqrt(
        saturate(1.0 - dot(foamSample.normalXY, foamSample.normalXY)));
    // 根据水平法线长度安全重建 Unity Y-Up 的垂直分量。
    foamSample.normalWS = normalize(float3(
        foamSample.normalXY.x,
        normalUp,
        foamSample.normalXY.y));
    // 将 FF3 的二维法线数据转换为 Unity XZ 水平面的世界空间候选法线。
    foamSample.soft = encodedFoam.b;
    // B 通道保存用于形成湿润、柔软泡沫边缘的遮罩。
    foamSample.height = encodedFoam.a;
    // A 通道保存用于形成硬泡沫主体和浅水泡沫的高度数据。
    return foamSample;
}

// 输入：当前水面世界空间法线、NSH 泡沫采样、泡沫覆盖率和法线强度。
// 输出：叠加泡沫微表面扰动后的 Unity 世界空间法线。
// 用途：将 NSH RG 通道转换为相对当前水面法线的导数扰动，避免泡沫法线覆盖近岸浪的几何坡度。
float3 ApplyShorelineFoamNormal(
    float3 baseNormalWS,
    ShorelineFoamTextureSample foamSample,
    float foamMask,
    float normalStrength)
{
    float safeFoamUp = max(foamSample.normalWS.y, 0.05);
    float2 foamDerivative = foamSample.normalXY / safeFoamUp;
    float3 perturbedNormalWS = normalize(float3(
        baseNormalWS.x + foamDerivative.x * baseNormalWS.y,
        max(baseNormalWS.y, 0.01),
        baseNormalWS.z + foamDerivative.y * baseNormalWS.y));
    float blendWeight =
        saturate(foamMask * normalStrength) *
        saturate(baseNormalWS.y * 8.0);
    return normalize(lerp(baseNormalWS, perturbedNormalWS, blendWeight));
}
#endif
