Shader "Tutorial/Water"
{
    Properties
    {
        [Header(Debug Views)]
        [WaterDebugMode]
        _DebugMode ("Debug Mode", Float) = 0

        [Header(Water Color and Depth)]
        _ShallowColor ("Shallow Color", Color) = (0.25, 0.75, 0.8, 1)
        _DeepColor ("Deep Color", Color) = (0.02, 0.12, 0.25, 1)
        _DepthLevel ("Depth Level", Range(0, 5)) = 1
        _DepthPower ("Depth Power", Range(0.1, 5)) = 1
        _DistanceFadeDepthAttenuation ("Distance Depth Attenuation", Range(0.1, 20)) = 4

        [Header(Surface Lighting)]
        _Roughness ("Water Roughness", Range(0.02, 1)) = 0.1

        // [Header(Sun Glint)]
        // _SunGlintFadeStart ("Sun Glint Fade Start", Range(0, 1)) = 0.15
        // _SunGlintFadeEnd ("Sun Glint Fade End", Range(0, 1)) = 0.45

        [Header(Wave Scattering)]
        _ScatterColor ("Scatter Color", Color) = (0, 0.517, 1, 1)
        _ScatterPeakColor ("Scatter Peak Color", Color) = (0.192, 0.742, 1, 1)
        _HeightStrength ("Height Scatter Strength", Range(0, 5)) = 1
        _ScatterStrength ("View Scatter Strength", Range(0, 2)) = 0.05
        _WavePeakScatterStrength ("Wave Peak Scatter Strength", Range(0, 10)) = 2
        _AmbientDensity ("Reflection Ambient Density", Range(0, 1)) = 0.02

        [Header(FFT Runtime Data)]
        [HideInInspector] _OceanLengthScales ("Ocean Length Scales", Vector) = (200, 1000, 100, 10)
        [HideInInspector] _OceanFoamStrengths ("Ocean Foam Strengths", Vector) = (1, 1, 1, 1)

        [Header(Tessellation)]
        _TessDistancePower ("Tess Distance Power", Range(1, 3.0)) = 1.8
        _TessMinFactor ("Tess Min Factor", Range(1, 8)) = 1
        _TessMaxFactor ("Tess Max Factor", Range(1, 256)) = 16
        _TessNearDistance ("Tess Near Distance", Float) = 20
        _TessFarDistance ("Tess Far Distance", Float) = 120
        _TessFarMultiplier ("Tess Far Multiplier", Range(0.01, 1)) = 0.15
        _CoastTessDistance ("Coast Tess Distance", Float) = 12
        _CoastTessFade ("Coast Tess Fade", Float) = 8
        _CoastTessFactor ("Coast Tess Factor", Range(4, 128)) = 128

        [Header(Coastline Runtime Data)]
        [HideInInspector] _CoastlineMap ("Coastline Map", 2D) = "black" {}
        [HideInInspector] _GroundHeightMap ("Ground Height Map", 2D) = "black" {}
        [HideInInspector] _CoastMapMinSize ("Coast Map Min Size", Vector) = (0, 0, 1, 1)
        [HideInInspector] _MaxCoastDistance ("Max Coast Distance", Float) = 60
        [HideInInspector] _GroundHeightDecodeRange ("Ground Height Decode Range", Vector) = (0, 1, 0, 0)

        [Header(Coastline Blend and Direction)]
        _ShoreWaveWidth ("Shore Wave Width", Float) = -0.09
        // 将 FF2 默认的 -9cm 海岸层偏移换算为 Unity 工程使用的 -0.09m。
        _ShoreWaveScale ("Shore Wave Scale", Float) = 0.016667
        // 让线性海岸层混合在当前 SDF 边界处恢复完整 FFT。
        _CoastDirectionGradientRadius ("Coast Direction Gradient Radius", Range(1, 4)) = 2
        // 控制从 CoastlineMap.R 重建朝岸方向时的纹素采样半径。
        _CoastDirectionGradientBlend ("Coast Direction Gradient Blend", Range(0, 1)) = 1
        // 控制 GB 方向跳变区域使用 R 通道距离梯度替代原方向的强度。

        [Header(Shoreline Wave Profile)]
        _WaveProfileMap ("Wave Profile Map", 2D) = "black" {}
        _WaveProfileDecode ("Wave Profile Decode", Vector) = (-0.330324, 0, 0.470531, 0.124962)
        _WaveProfileWidth ("Wave Profile Width", Float) = 5
        _WaveProfileDistance ("Wave Profile Distance", Float) = 2.25
        _WaveProfileSpeed ("Wave Profile Speed", Float) = 0.9
        _WaveProfileAnimationSpeed ("Wave Profile Animation Speed", Float) = 0.75
        _WaveProfileOffsetStrength ("Wave Profile Offset Strength", Range(0, 2)) = 1
        _WaveProfileHeightStrength ("Wave Profile Height Strength", Range(0, 6)) = 2.5
        // 只放大 Profile 垂直位移，不增加水平推进距离。
        _WaveProfileForwardStrength ("Wave Profile Forward Strength", Range(0, 4)) = 1
        // 只调节 Profile 水平推进；数值 1 完全保持当前位移结果。
        _WaveMaxShorewardDistance ("Max Shoreward Travel", Range(0.25, 5)) = 2.5
        // 对朝岸位移峰值施加柔性上限，离岸回退距离不受影响。
        _WaveForwardTweak ("Wave Forward Tweak", Range(0, 2)) = 1

        [Header(Shoreline Terrain Following)]
        _WaveGroundPrediction ("Wave Ground Prediction", Float) = 2
        // 将 FF2 默认的 200cm 地形预测距离换算为 Unity 工程使用的 2m。
        _CoastlineNormalRange ("Coastline Normal Range", Float) = 0.14
        // 将 FF2 默认的 14cm 三点法线采样间距换算为 Unity 工程使用的 0.14m。

        [Header(Wave Timing)]
        [Toggle] _IsNeedTime ("Use Wave Time", Float) = 1
        _TimeOffset ("Wave Time Offset", Float) = 0
        _WaveTimeStrength ("Alongshore Time Strength", Range(0, 2)) = 0.1

        [Header(Wave Shape Variation)]
        [Toggle] _IsNeedDetail ("Use Wave Detail", Float) = 1
        _WaveSinStrength ("Wave Sin Strength", Range(0, 50)) = 1
        _WaveCosStrength ("Wave Cos Strength", Range(0, 50)) = 1
        _WaveSinFrequency ("Wave Sin Frequency", Range(0.1, 5)) = 1
        _WaveCosFrequency ("Wave Cos Frequency", Range(0.1, 5)) = 1
        _WaveDetailSinStrength ("Detail Sin Strength", Range(0, 30)) = 1
        _WaveDetailCosStrength ("Detail Cos Strength", Range(0, 30)) = 1
        _WaveDetailSinFrequency ("Detail Sin Frequency", Range(0.1, 5)) = 1
        _WaveDetailCosFrequency ("Detail Cos Frequency", Range(0.1, 5)) = 1

        [Header(Wave Noise)]
        [Toggle] _IsNeedNoise ("Use Wave Noise", Float) = 0
        _SmoothNoiseMap ("Smooth Noise Map", 2D) = "gray" {}
        _NoiseTime ("Wave Noise Time", Range(0, 2)) = 0
        _NoiseScale ("Wave Noise Scale", Range(0, 2)) = 0
        _NoiseMapSampleScale ("Noise Map Sample Scale", Float) = 1

        [Header(Foam Appearance)]
        _FoamColor ("Foam Color", Color) = (0.77, 0.973, 1, 1)
        _FoamRoughness ("Foam Roughness Addition", Range(0, 1)) = 0.2
        _FoamOpacityStrength ("Foam Opacity Strength", Range(0, 2)) = 1
        // 控制所有泡沫层组合后的最终覆盖强度。
        _FoamOpacityPower ("Foam Opacity Power", Range(0.1, 4)) = 1.35
        // 调节泡沫由主体到透明边缘的消退曲线。

        [Header(Shoreline Foam Masks)]
        _ShorelineFoamStrength ("Shoreline Foam Strength", Range(0, 4)) = 1
        _ShorelineFoamNormalStrength ("Shoreline Foam Normal Strength", Range(0, 2)) = 0.35
        // 控制 NSH RG 通道对近岸泡沫区域微表面法线的影响。
        _CoastlineFoamDistance ("Coastline Foam Distance", Float) = 2.5
        _CoastlineFoamStrength ("Coastline Foam Strength", Range(0, 4)) = 0.35
        _ShorelineShallowFoamDepth ("Shoreline Shallow Foam Depth", Float) = 1.2
        // 控制浅水残留泡沫从岸边向深水消退的水深范围。
        _ShorelineShallowFoamStrength ("Shoreline Shallow Foam Strength", Range(0, 2)) = 0.55
        // 控制不依赖当前 Profile 浪峰的浅水残留泡沫强度。
        _ShorelineShallowFoamPower ("Shoreline Shallow Foam Power", Range(0.1, 8)) = 1.5
        // 调节 NSH 高度纹理形成的残留泡沫斑块边缘。

        [Header(Foam Texture and Advection)]
        [NoScaleOffset] _FoamNormalSoftHeightMap ("Foam Normal Soft Height Map", 2D) = "black" {}
        // 使用 FF3 的 NSH 打包纹理：RG 法线、B 柔软泡沫、A 泡沫高度。
        _FoamUVAdvectionOffset ("Foam UV Advection Offset", Float) = -0.5
        // 为三组平流相位施加统一时间偏移。
        _FoamUVAdvectionVelocity ("Foam UV Advection Velocity", Float) = 7
        // 缩放由近岸速度驱动的泡沫纹理平流距离。
        _FoamUVRandomization ("Foam UV Randomization", Range(0, 1)) = 1
        // 控制第二、第三组 UV 的固定随机偏移，减少重复图案。
        _FoamUVScale ("Foam UV Scale", Float) = 0.09
        // 将 FF3 的每厘米 0.0009 换算成 Unity 每米 0.09。
        _FoamUVSpeed ("Foam UV Speed", Float) = 1.1
        // 控制三相泡沫纹理交叉循环的播放速度。
        _CoastlineVelocityScale ("Coastline Velocity Scale", Float) = 0.0006
        // 使用 FF3 的 Coastline Velocity Scale，将 Profile 水平位移转换为泡沫平流速度。
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Transparent"
            "RenderType" = "Transparent"
        }

        Pass
        {
            Tags { "LightMode" = "UniversalForward" }
            ZWrite On
            ZTest LEqual
            Cull Back

            HLSLPROGRAM
            #pragma target 5.0
            #pragma vertex vert
            #pragma hull hull
            #pragma domain domain
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "ShorelineWave.hlsl"


            TEXTURE2D(_PlanarReflectionTex);SAMPLER(sampler_PlanarReflectionTex);//反射相机纹理
            TEXTURE2D(_CameraDepthTexture);SAMPLER(sampler_CameraDepthTexture);//相机深度
            TEXTURE2D(_CameraOpaqueTexture);SAMPLER(sampler_CameraOpaqueTexture);//不透明物体纹理(看水下做折射纹理)
            
            TEXTURE2D_ARRAY(_DisplacementTexture);
            SAMPLER(sampler_DisplacementTexture);
            TEXTURE2D_ARRAY(_SlopeTexture);
            SAMPLER(sampler_SlopeTexture);

            float4 _OceanLengthScales;
            float4 _OceanFoamStrengths;
            float _CoastlineNormalRange;
            // 控制 FF2 三点位移法线在 Unity 世界空间中的采样间距。
            // //高光参数
            // float _SpecularStrength,_SpecularPower,_SunGlintPower,_SunGlintStrength;
            //散射参数
            float _HeightStrength,_ScatterStrength,_WavePeakScatterStrength,_AmbientDensity;
            float4 _ScatterPeakColor,_ScatterColor;
            //泡沫参数
            float4 _FoamColor;
            float _ShorelineFoamStrength;
            float _ShorelineFoamNormalStrength;
            // 为最终法线提供独立的近岸泡沫微表面强度。
            float _CoastlineFoamDistance;
            float _ShorelineShallowFoamDepth;
            float _ShorelineShallowFoamStrength;
            float _ShorelineShallowFoamPower;
            float _FoamOpacityStrength;
            float _FoamOpacityPower;
            // 保存最终泡沫覆盖率的强度和边缘消退曲线。
            // 保存浅水残留泡沫的深度、强度和纹理形状控制。
            float _CoastlineFoamStrength;
            //粗糙度
            float _Roughness,_FoamRoughness;
            //距离衰减
            float _DistanceFadeDepthAttenuation;
            //曲面细分着色器参数
            float _TessEdgeLength;
            float _TessDistancePower,_TessMinFactor,_TessMaxFactor;
            float _TessNearDistance,_TessFarDistance;
            float _TessFarMultiplier;
            float _CoastTessDistance;
            float _CoastTessFade;
            float _CoastTessFactor;


            half _DepthLevel,_DepthPower;
            half4 _ShallowColor,_DeepColor;
            float _DebugMode;

            //水面雾混合
            float _BaseDensity;
            float _Extinction;
            float _ScatteringAlbedo;
            float4 _AmbientScatteringColor;
            float _AmbientScatteringStrength;
            float _FogStartDistance;
            float _FogFullDensityDistance;




            struct TessellationFactors
            {
                float edge[3] : SV_TessFactor;
                float inside : SV_InsideTessFactor;
            };
            struct Tessdata
            {
                float4 positionOS : INTERNALTESSPOS;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
            };
            struct appdata
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
            };

            struct v2f
            {
                float4 positionHCS : SV_POSITION;
                float4 screenPos : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float2 oceanXZ : TEXCOORD2;
                float clipDepth : TEXCOORD3;
                float3 shorelineNormalWS : TEXCOORD4;
                float shorelineFoam : TEXCOORD5;
                float2 shorelineFoamVelocity : TEXCOORD6;
            };

            //————————function mode——————————————————
            float3 FresnelSchlick(float cosTheta, float3 F0)
            {
                return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5);
            }
            float DotClamped(float3 a, float3 b) {
                return saturate(dot(a, b));
            }
            //不明来历的物理公式，主要计算粗糙度
            float Beckmann (float nDoth, float Roughness)
            {
                float exp_arg = (nDoth * nDoth - 1) / (Roughness * Roughness * nDoth * nDoth);
                return exp(exp_arg) / (PI * Roughness * Roughness * nDoth * nDoth * nDoth * nDoth);
            }
            float SmithMaskBeckmann (float3 halfDir, float3 otherDir, float roughness)
            {
                float hDoto = max(0.001f, DotClamped(halfDir, otherDir));
                float a = hDoto / (roughness * sqrt(1 - hDoto * hDoto));

                float a2 = a * a;
                return a < 1.6f ? (1.0f - 1.259f * a + 0.396f * a2) / (3.535f * a + 2.181 * a2) : 0.0f;
            }
            
            

            //细分函数
            float CoastTessellationMask(float3 positionWS)
            {
                ShorelineData shoreline = EvaluateShorelineData(positionWS.xz);

                float distanceToCoast = abs(shoreline.waterDistance);
                float fadeEnd = _CoastTessDistance + max(_CoastTessFade, 0.001);
                float coastMask = 1.0 - smoothstep(_CoastTessDistance, fadeEnd, distanceToCoast);

                return coastMask * shoreline.insideMap;
            }
            float TessellationHeuristic(float3 p0WS, float3 p1WS)
            {
                float edgeLength = distance(p0WS, p1WS);
                float3 edgeCenter = (p0WS + p1WS) * 0.5;
                float viewDistance = distance(edgeCenter, _WorldSpaceCameraPos);

                float tess = edgeLength * _ScreenParams.y /
                             (_TessEdgeLength * pow(max(viewDistance * 0.5, 1.0), _TessDistancePower));
                float lod01 = saturate((viewDistance - _TessNearDistance) / max(_TessFarDistance - _TessNearDistance, 0.001));

                tess *= lerp(1.0, _TessFarMultiplier, lod01);

                float coastMask0 = CoastTessellationMask(p0WS);
                float coastMask1 = CoastTessellationMask(p1WS);
                float coastMaskCenter = CoastTessellationMask(edgeCenter);

                float coastMask = max(max(coastMask0, coastMask1), coastMaskCenter);
                float coastTess = lerp(_TessMinFactor, _CoastTessFactor, coastMask);

                tess = max(tess, coastTess);

                return clamp(tess, _TessMinFactor, _TessMaxFactor);
            }
            TessellationFactors PatchFunction(InputPatch<Tessdata, 3> patch)
            {
                TessellationFactors f;

                float3 p0 = TransformObjectToWorld(patch[0].positionOS.xyz);
                float3 p1 = TransformObjectToWorld(patch[1].positionOS.xyz);
                float3 p2 = TransformObjectToWorld(patch[2].positionOS.xyz);

                f.edge[0] = TessellationHeuristic(p1, p2);
                f.edge[1] = TessellationHeuristic(p2, p0);
                f.edge[2] = TessellationHeuristic(p0, p1);
                f.inside = (f.edge[0] + f.edge[1] + f.edge[2]) / 3.0;

                return f;
            }
            float2 GetSpectrumUV(float2 worldXZ, int layerIndex)
            {
                return frac(worldXZ / max(_OceanLengthScales[layerIndex], 0.001));
            }

            float4 SampleOceanDisplacement(float2 worldXZ)
            {
                float4 displacement = 0.0;

                [unroll]
                for (int layerIndex = 0; layerIndex < 4; layerIndex++)
                {
                    float4 layerDisplacement = SAMPLE_TEXTURE2D_ARRAY_LOD(_DisplacementTexture, sampler_DisplacementTexture, GetSpectrumUV(worldXZ, layerIndex), layerIndex, 0);
                    layerDisplacement.a *= _OceanFoamStrengths[layerIndex];
                    displacement += layerDisplacement;
                }

                return displacement;
            }

            float2 SampleOceanSlope(float2 worldXZ)
            {
                float2 slope = 0.0;

                [unroll]
                for (int layerIndex = 0; layerIndex < 4; layerIndex++)
                {
                    slope += SAMPLE_TEXTURE2D_ARRAY_LOD(_SlopeTexture, sampler_SlopeTexture, GetSpectrumUV(worldXZ, layerIndex), layerIndex, 0).rg;
                }

                return slope;
            }

            //处理顶点着色器到曲面细分着色器到顶点着色器的数据流类型
            v2f VertexAfterTess(appdata input)
            {
                v2f output;

                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float4 positionHCS = TransformWorldToHClip(positionWS);

                float rawClipDepth = positionHCS.z / positionHCS.w;
                float clipDepth = 1.0 - Linear01Depth(rawClipDepth, _ZBufferParams);
                clipDepth = saturate(clipDepth);
                float distanceFade = pow(clipDepth, _DistanceFadeDepthAttenuation);


                float2 oceanXZ = positionWS.xz;
                // 保存未位移的世界空间 XZ，保证 FFT、SDF 和 Profile 使用同一采样基准。
                float3 fftDisplacement = SampleOceanDisplacement(oceanXZ).rgb * distanceFade;
                // 读取当前顶点的完整远洋 FFT 位移，作为远近海混合的远洋端。

                ShorelineData shoreline = EvaluateShorelineData(oceanXZ);
                // 从 CoastlineMap 解码当前顶点的离岸距离、朝岸方向和过渡权重。
                float3 shorelineNormalWS = ComputeShorelineTriangleNormal(
                    shoreline,
                    positionWS,
                    _CoastlineNormalRange);
                // 使用 FF2 三点位移采样重建近岸 Profile 的世界空间几何法线。
                Coastline coastline = GetCoastline(shoreline);
                // 将工程的海岸数据转换为 FF2 Profile 动画使用的精简数据。
                float2 profileUV = GetProfileUV(positionWS, coastline);
                // 按照 FF2 的距离、时间和沿岸 Detail 公式生成 WaveProfileMap UV。

                float shorelineFoam;
                // 接收 Profile B 通道的泡沫数据，稍后传入片元阶段参与最终泡沫组合。
                float2 forwardUpward = SampleProfileMap(profileUV, shorelineFoam);
                // 从 Profile RG 通道解码朝岸水平位移和垂直位移。
                float3 shorelineDisplacement = GetFluxSlopeOffset(
                    forwardUpward,
                    coastline,
                    oceanXZ);
                // 使用当前 Profile 推进距离预测实际落点坡度，并保持源点相对地形的净空高度。
                shorelineDisplacement *= shoreline.waveScale;
                // 按 FF2 的 Coastline Scale 数据约束 Profile 位移，远水和陆地不再残留近岸浪。
                shorelineDisplacement *= _WaveProfileOffsetStrength;
                // 使用独立强度参数整体调整近岸 Profile 位移幅度。

                float2 shorelineFoamVelocity =
                    ComputeShorelineFoamVelocity(
                        shoreline,
                        shorelineDisplacement);
                // 在 Edge Correction 之前使用 Profile 原始水平位移生成 FF3 近岸泡沫速度。
                ShoreEdgeCorrection edgeCorrection = ComputeShoreEdgeCorrection(
                    shoreline,
                    positionWS,
                    shorelineDisplacement);
                // 对坡度处理后的近岸位移执行 FF2 地形边缘修正，远洋分支不参与。
                shorelineDisplacement = edgeCorrection.displacement;
                // 使用修正后的近岸位移参与混合，避免拍岸位移穿入沙滩地形。

                float3 finalDisplacement = lerp(
                    shorelineDisplacement,
                    fftDisplacement,
                    shoreline.fftWeight);
                // 按有符号离岸距离在完整近岸位移与完整 FFT 位移之间只混合一次。

                finalDisplacement = lerp(
                    fftDisplacement,
                    finalDisplacement,
                    shoreline.insideMap);
                // CoastlineMap 烘焙范围外强制恢复完整 FFT，避免采样贴图边缘。

                positionWS += finalDisplacement;
                // 将最终混合位移写入顶点世界坐标，完成本帧水面动画。

                output.positionWS = positionWS;
                output.positionHCS = TransformWorldToHClip(positionWS);
                output.screenPos = ComputeScreenPos(output.positionHCS);
                output.oceanXZ = oceanXZ;
                output.clipDepth = clipDepth;
                output.shorelineNormalWS = shorelineNormalWS;
                // 将顶点阶段重建的近岸几何法线传入片元阶段，避免继续借用 FFT 坡度。
                output.shorelineFoam = shorelineFoam;
                output.shorelineFoamVelocity = shorelineFoamVelocity;
                // 将 FF3 近岸速度传入片元阶段，用来驱动三相泡沫纹理平流。
                // 将 Profile B 通道原始泡沫传入片元阶段，使泡沫与当前浪峰保持相同动画相位。
                return output;
            }

            //体积雾混合颜色
            float IntegrateWaterFogDensity(float viewDistance)
            {
                float startDistance = max(_FogStartDistance, 0.0);
                float fullDistance = max(_FogFullDensityDistance, startDistance + 0.001);
                float rampLength = fullDistance - startDistance;

                if (viewDistance <= startDistance)
                    return 0.0;

                if (viewDistance < fullDistance)
                {
                    float u = saturate((viewDistance - startDistance) / rampLength);
                    float integratedRamp = u * u * u - 0.5 * u * u * u * u;
                    return max(_BaseDensity, 0.0) * rampLength * integratedRamp;
                }

                return max(_BaseDensity, 0.0) * (0.5 * rampLength + viewDistance - fullDistance);
            }

            half3 ApplyDistanceFogToWater(half3 waterColor, float3 positionWS)
            {
                float viewDistance = distance(_WorldSpaceCameraPos, positionWS);
                float integratedDensity = IntegrateWaterFogDensity(viewDistance);
                float opticalDepth = integratedDensity * max(_Extinction, 0.0);
                float transmittance = exp(-opticalDepth);
                half3 fogColor = _AmbientScatteringColor.rgb * _AmbientScatteringStrength * _ScatteringAlbedo;
                return waterColor * transmittance + fogColor * (1.0 - transmittance);
            }
            //————————shader mode—————————————————————
            Tessdata vert(appdata input)
            {
                Tessdata output;
                output.positionOS = input.positionOS;
                output.uv = input.uv;
                output.normalOS = input.normalOS;
                return output;
            }

            [domain("tri")]
            [outputcontrolpoints(3)]
            [outputtopology("triangle_cw")]
            [partitioning("integer")]
            [patchconstantfunc("PatchFunction")]
            Tessdata hull(InputPatch<Tessdata, 3> patch, uint id : SV_OutputControlPointID)
            {
                return patch[id];
            }

            [domain("tri")]
            v2f domain(
                TessellationFactors factors,
                OutputPatch<Tessdata, 3> patch,
                float3 bary : SV_DomainLocation)
            {
                appdata input;

                input.positionOS =
                    patch[0].positionOS * bary.x +
                    patch[1].positionOS * bary.y +
                    patch[2].positionOS * bary.z;

                input.uv =
                    patch[0].uv * bary.x +
                    patch[1].uv * bary.y +
                    patch[2].uv * bary.z;

                input.normalOS =
                    patch[0].normalOS * bary.x +
                    patch[1].normalOS * bary.y +
                    patch[2].normalOS * bary.z;

                return VertexAfterTess(input);
            }


            half4 frag(v2f input) : SV_Target
            {
                //lod衰减
                float clipDepth = saturate(input.clipDepth);
                float distanceFade = pow(clipDepth, _DistanceFadeDepthAttenuation);
                ShorelineData shoreline = EvaluateShorelineData(input.oceanXZ);

                //计算法线
                float2 slope = SampleOceanSlope(input.oceanXZ);
                float3 fftNormalWS = normalize(float3(-slope.x, 1.0, -slope.y));
                // 从 FFT 坡度纹理重建远洋世界空间法线。
                float3 macroNormal = float3(0.0, 1.0, 0.0);
                float3 distanceFadedFFTNormalWS = normalize(lerp(
                    macroNormal,
                    fftNormalWS,
                    distanceFade));
                // 保留原有的 FFT 法线距离衰减，避免远处高频高光闪烁。
                float3 distanceFadedShorelineNormalWS = normalize(lerp(
                    macroNormal,
                    input.shorelineNormalWS,
                    distanceFade));
                // 对三点重建的近岸几何法线应用相同距离衰减。
                float3 normalWS = normalize(lerp(
                    distanceFadedShorelineNormalWS,
                    distanceFadedFFTNormalWS,
                    shoreline.fftWeight));
                // 使用与顶点位移一致的 FF2 海岸权重在近岸几何法线和 FFT 法线之间混合。
                normalWS = normalize(lerp(
                    distanceFadedFFTNormalWS,
                    normalWS,
                    shoreline.insideMap));
                // CoastlineMap 范围外强制恢复 FFT 法线，避免贴图边缘影响远洋着色。

                //读取泡沫
                float4 displacement = SampleOceanDisplacement(input.oceanXZ);
                float rawFFTFoam = saturate(displacement.a);
                float fftFoam = smoothstep(0.25, 0.75, rawFFTFoam);
                fftFoam *= shoreline.fftWeight;
                // 使用与顶点位移相同的权重衰减 FFT 泡沫，避免平坦近岸仍残留远洋白沫。

                float profileFoamSource =
                    input.shorelineFoam * shoreline.waveScale;
                // 将 WaveProfileMap B 通道乘 Coastline Scale，恢复 FF3 的 W0.Foam 数据。
                float waterSideMask =
                    step(0.0, shoreline.waterDistance);
                // 只允许 Coastline 基础泡沫出现在 SDF 的水域一侧。
                float coastFoamDistance =
                    max(_CoastlineFoamDistance, 0.001);
                // 防止 Coastline Foam Distance 为零时产生除零错误。
                float coastFoamSource =
                    _CoastlineFoamStrength *
                    (1.0 - saturate(
                        shoreline.waterDistance /
                        coastFoamDistance));
                // 复现 FF3 按离岸距离生成的 Coastline 基础泡沫源。
                coastFoamSource *= waterSideMask;
                // 清除陆地一侧由有符号距离产生的错误泡沫。
                float shorelineFoamSource =
                    coastFoamSource +
                    max(profileFoamSource * 1.3 - 0.5, -0.1);
                // 按 FF3 的 1.3、-0.5 和 -0.1 规则组合 Coastline 与 Profile 泡沫源。
                shorelineFoamSource =
                    saturate(shorelineFoamSource);
                // 将组合后的 Surface Flux 泡沫限制在零到一范围。
                shorelineFoamSource *=
                    shoreline.insideMap *
                    (1.0 - shoreline.fftWeight);
                // 使用与近岸位移一致的地图和远近海权重限制泡沫源。

                ShorelineFoamTextureSample shorelineFoamTexture =
                    SampleShorelineFoamTexture(
                        input.oceanXZ,
                        input.shorelineFoamVelocity);
                // 使用未位移世界 XZ 和插值后的近岸速度执行 FF3 三相 NSH 采样。
                float shorelineFoamHeight =
                    shorelineFoamTexture.height *
                    shorelineFoamSource *
                    1.6;
                // 使用 NSH A 通道形成较硬的泡沫主体，并保留仓库的 1.6 高度系数。
                float shorelineFoamSoft =
                    shorelineFoamTexture.soft *
                    shorelineFoamSource;
                // 使用 NSH B 通道形成浪花边缘较柔软、破碎的泡沫区域。
                float shorelineFoam = saturate(max(
                    saturate(shorelineFoamHeight),
                    saturate(shorelineFoamSoft)));
                // 合并硬泡沫与柔软泡沫，替代直接显示 Profile B 的连续白色浪带。
                shorelineFoam *= _ShorelineFoamStrength;
                // 保留当前材质的近岸泡沫整体强度控制。
                normalWS = ApplyShorelineFoamNormal(
                    normalWS,
                    shorelineFoamTexture,
                    shorelineFoam * distanceFade,
                    _ShorelineFoamNormalStrength);
                // 仅在实际近岸泡沫覆盖区域叠加 NSH 微表面法线，并随观察距离同步衰减。

                float foam = 1.0 -
                    (1.0 - saturate(fftFoam)) *
                    (1.0 - saturate(shorelineFoam));
                // 使用透明层 Over 规则合并远洋和拍岸泡沫，避免 max 造成硬切换。
                foam *= distanceFade;
                // 保留当前工程原有的泡沫距离衰减，避免远处高频白点闪烁。



                Light mainLight = GetMainLight();
                float3 lightDirWS = normalize(mainLight.direction);
                float3 viewDirWS = normalize(_WorldSpaceCameraPos.xyz - input.positionWS);
                float3 halfDir = normalize(lightDirWS+viewDirWS);

                float nDotl = max(0.001f, DotClamped(normalWS, lightDirWS));
                float nDoth = max(0.001f, DotClamped(normalWS, halfDir));

                float2 screenUV = input.screenPos.xy / input.screenPos.w;
                float2 reflectionUV = clamp(screenUV + normalWS.xz * 0.002*distanceFade, 0.001, 0.999);
                float2 refractUV = clamp(screenUV + normalWS.xz * 0.006*distanceFade, 0.001, 0.999);
                //水的菲涅尔项
                float NoV = saturate(dot(normalWS, viewDirWS));
                float3 F0 = float3(0.02, 0.02, 0.02);
                float3 Fresnel = FresnelSchlick(NoV, F0);

                half3 refractSceneColor = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, refractUV).rgb;

                float rawDepth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, screenUV).r;
                float sceneDepth = LinearEyeDepth(rawDepth, _ZBufferParams);
                float waterDepth = input.screenPos.w;
                float depthDiff = max(0.0, sceneDepth - waterDepth);
                float depthWeight = pow(saturate(depthDiff * _DepthLevel), _DepthPower);

                float shallowFoamDepth =
                    max(_ShorelineShallowFoamDepth, 0.001);
                // 为浅水泡沫深度范围设置安全下限，避免 smoothstep 边界重合。
                float shallowDepthMask =
                    1.0 - smoothstep(
                        0.0,
                        shallowFoamDepth,
                        depthDiff);
                // 使用场景水深生成由岸边向深水连续消退的残留泡沫遮罩。
                float shallowFoamPattern = pow(
                    saturate(shorelineFoamTexture.height),
                    max(_ShorelineShallowFoamPower, 0.1));
                // 使用 NSH A 通道打碎浅水泡沫边缘，避免形成整齐的白色岸线。
                float shallowFoam =
                    shallowFoamPattern *
                    shallowDepthMask *
                    waterSideMask *
                    shoreline.insideMap *
                    (1.0 - shoreline.fftWeight) *
                    _ShorelineShallowFoamStrength;
                // 让残留泡沫独立于当前 Profile 浪峰，并限制在有效近岸水域。
                foam = 1.0 - (1.0 - foam) * (1.0 - saturate(shallowFoam));
                // 使用同一透明层规则叠加浅水残留泡沫，保留各层柔软边缘。
                float foamOpacity = saturate(
                    pow(max(foam, 0.0001), _FoamOpacityPower) *
                    _FoamOpacityStrength);
                // 将组合覆盖率转换为最终泡沫透明度，使残留泡沫能够柔和消退。

                half3 waterColor = lerp(_ShallowColor.rgb, _DeepColor.rgb, depthWeight);
                half3 refractColor = lerp(refractSceneColor, waterColor, depthWeight);

                half3 reflectionColor = SAMPLE_TEXTURE2D(
                    _PlanarReflectionTex,
                    sampler_PlanarReflectionTex,
                    reflectionUV
                ).rgb;

                
                float3 foamColor = _FoamColor.rgb * mainLight.color.rgb;
                //粗糙度
                float roughness = max(0.02, _Roughness + foamOpacity * _FoamRoughness);
                float viewMask = SmithMaskBeckmann(halfDir, viewDirWS, roughness);
				float lightMask = SmithMaskBeckmann(halfDir, lightDirWS, roughness);
                float geometryMask = rcp(1 + viewMask + lightMask);

                /*//经验水面高光
                float sunHeight = saturate(dot(lightDirWS, float3(0.0, 1.0, 0.0)));
                float lowSunMask = 1.0 - smoothstep(
                    _SunGlintFadeStart,
                    _SunGlintFadeEnd,
                    sunHeight
                );
                float3 spacularColor = float3(1,1,1);
                float specularMask = pow(nDoth, _SpecularPower) * nDotl;
                specularMask *= lowSunMask;
                float3 specular = _SpecularStrength*spacularColor*specularMask;
                //太阳波光
                float3 reflectDir = reflect(-viewDirWS, normalWS);
                float sunGlint = saturate(dot(reflectDir, lightDirWS));
                sunGlint = pow(sunGlint, _SunGlintPower)*nDotl;
                sunGlint *= lowSunMask;
                float3 sunSpecular = mainLight.color.rgb*_SunGlintStrength * sunGlint;*/

                //brdf水面高光
                float3 specular = mainLight.color.rgb * Fresnel * geometryMask * Beckmann(nDoth, roughness);
                specular /= 4.0f * max(0.001f, DotClamped(macroNormal, lightDirWS));
                specular *= DotClamped(normalWS, lightDirWS);
                



                //散射参数
                float var_H = max(0.0f, displacement.y) * _HeightStrength;
                float k1 = _WavePeakScatterStrength * var_H * pow(DotClamped(lightDirWS, -viewDirWS), 4.0f) * pow(saturate(0.5f - 0.5f * dot(lightDirWS, normalWS)), 3.0f);
                k1 *= distanceFade;
                float k2 = _ScatterStrength * pow(DotClamped(viewDirWS, normalWS), 2.0f);
                float k4 = _AmbientDensity;
                //散射光
                float3 scatter = (k1 * _ScatterPeakColor + k2 * _ScatterColor) * mainLight.color.rgb;
                scatter += k4 * reflectionColor;


                half3 finalColor = reflectionColor * Fresnel + (refractColor+scatter) * (1.0 - Fresnel)+specular;
                finalColor = lerp(finalColor, foamColor, foamOpacity);
                // 使用最终泡沫透明度覆盖水面颜色，而不是直接使用未经整形的原始遮罩。
                // 1: Refraction before scattering, reflection, specular, and foam.
                if (_DebugMode == 1)
                {
                    return half4(refractColor, 1);
                }

                // 2: Planar reflection contribution.
                if (_DebugMode == 2)
                {
                    return half4(reflectionColor, 1);
                }

                // 3: Water scattering contribution.
                if (_DebugMode == 3)
                {
                    return half4(scatter, 1);
                }

                // 4: BRDF specular contribution.
                if (_DebugMode == 4)
                {
                    return half4(specular, 1);
                }

                // 5: Final combined foam opacity.
                if (_DebugMode == 5)
                {
                    return half4(foamOpacity.xxx, 1);
                }

                // 6: Repeating shoreline WaveProfile U coordinate.
                if (_DebugMode == 6)
                {
                    if (shoreline.insideMap < 0.5)
                    {
                        return half4(1, 0, 1, 1);
                    }

                    float2 profileUV = ComputeShoreWaveProfileUV(
                        shoreline,
                        input.oceanXZ);
                    float sampledU = frac(profileUV.x);
                    return half4(sampledU.xxx, 1);
                }

                // 7: Shoreline WaveProfile V coordinate.
                if (_DebugMode == 7)
                {
                    if (shoreline.insideMap < 0.5)
                    {
                        return half4(1, 0, 1, 1);
                    }

                    float2 profileUV = ComputeShoreWaveProfileUV(
                        shoreline,
                        input.oceanXZ);
                    float sampledV = saturate(profileUV.y);
                    return half4(sampledV.xxx, 1);
                }

                finalColor = ApplyDistanceFogToWater(finalColor, input.positionWS);
                return half4(finalColor, 1);
            }
            ENDHLSL
        }
    }
}
