Shader "Tutorial/Water"
{
    Properties
    {
        _DebugMode ("Debug Mode", Range(0, 18)) = 0
        
        [Header(Depth)]
        _DepthLevel ("Depth Level", Range(0, 5)) = 1
        _DepthPower ("Depth Power", Range(0.1, 5)) = 1

        [Header(WaterPlane)]
        _ShallowColor ("Shallow Color", Color) = (0.25, 0.75, 0.8, 1)
        _DeepColor ("Deep Color", Color) = (0.02, 0.12, 0.25, 1)

        [Header(FFT Ocean)]
        _SpectrumDebugLayer ("Spectrum Debug Layer", Range(-1, 3)) = -1
        _OceanLengthScales ("Ocean Length Scales", Vector) = (200, 1000, 100, 10)
        _OceanFoamStrengths ("Ocean Foam Strengths", Vector) = (1, 1, 1, 1)

        [Header(Tess)]
        _TessDistancePower ("Tess Distance Power", Range(1, 3.0)) = 1.8
        _TessMinFactor ("Tess Min Factor", Range(1, 8)) = 1
        _TessMaxFactor ("Tess Max Factor", Range(1, 256)) = 16
        _TessNearDistance ("Tess Near Distance", Float) = 20
        _TessFarDistance ("Tess Far Distance", Float) = 120
        _TessFarMultiplier ("Tess Far Multiplier", Range(0.01, 1)) = 0.15
        _CoastTessDistance ("Coast Tess Distance", Float) = 12
        _CoastTessFade ("Coast Tess Fade", Float) = 8
        _CoastTessFactor ("Coast Tess Factor", Range(4, 128)) = 128

        [Header(Visual Depth Fade)]
        _DistanceFadeDepthAttenuation ("Distance Depth Attenuation", Range(0.1, 20)) = 4

        // [Header(Sun Glint)]
        // _SunGlintFadeStart ("Sun Glint Fade Start", Range(0, 1)) = 0.15
        // _SunGlintFadeEnd ("Sun Glint Fade End", Range(0, 1)) = 0.45

        [Header(Coastline)]
        [HideInInspector] _CoastlineMap ("Coastline Map", 2D) = "black" {}
        [HideInInspector] _GroundHeightMap ("Ground Height Map", 2D) = "black" {}
        [HideInInspector] _CoastMapMinSize ("Coast Map Min Size", Vector) = (0, 0, 1, 1)
        [HideInInspector] _MaxCoastDistance ("Max Coast Distance", Float) = 60
        [HideInInspector] _GroundHeightDecodeRange ("Ground Height Decode Range", Vector) = (0, 1, 0, 0)
        [HideInInspector] _WaterLevel ("Water Level", Float) = 0
        [HideInInspector] _FFTBlendStart ("FFT Blend Start", Float) = 10
        [HideInInspector] _FFTBlendEnd ("FFT Blend End", Float) = 55
        _ShoreWaveWidth ("Shore Wave Width", Float) = -0.09
        // 将 FF2 默认的 -9cm 海岸层偏移换算为 Unity 工程使用的 -0.09m。
        _ShoreWaveScale ("Shore Wave Scale", Float) = 0.016667
        // 让线性海岸层混合在当前 60m SDF 边界处恢复完整 FFT。

        [Header(Shoreline Wave)]
        _WaveProfileMap ("Wave Profile Map", 2D) = "black" {}
        _WaveProfileDecode ("Wave Profile Decode", Vector) = (-0.330324, 0, 0.470531, 0.124962)
        _WaveProfileWidth ("Wave Profile Width", Float) = 5
        _WaveProfileDistance ("Wave Profile Distance", Float) = 2.25
        _WaveProfileSpeed ("Wave Profile Speed", Float) = 0.9
        _WaveProfileAnimationSpeed ("Wave Profile Animation Speed", Float) = 0.75
        _WaveProfileOffsetStrength ("Wave Profile Offset Strength", Range(0, 2)) = 1
        _WaveForwardTweak ("Wave Forward Tweak", Range(0, 2)) = 1
        _WaveGroundPrediction ("Wave Ground Prediction", Float) = 2
        // 将 FF2 默认的 200cm 地形预测距离换算为 Unity 工程使用的 2m。

        [Toggle] _IsNeedTime ("Use Wave Time", Float) = 1
        _TimeOffset ("Wave Time Offset", Float) = 0
        _WaveTimeStrength ("Alongshore Time Strength", Range(0, 2)) = 0.1

        [Toggle] _IsNeedDetail ("Use Wave Detail", Float) = 1
        _WaveSinStrength ("Wave Sin Strength", Range(0, 50)) = 1
        _WaveCosStrength ("Wave Cos Strength", Range(0, 50)) = 1
        _WaveSinFrequency ("Wave Sin Frequency", Range(0.1, 5)) = 1
        _WaveCosFrequency ("Wave Cos Frequency", Range(0.1, 5)) = 1
        _WaveDetailSinStrength ("Detail Sin Strength", Range(0, 30)) = 1
        _WaveDetailCosStrength ("Detail Cos Strength", Range(0, 30)) = 1
        _WaveDetailSinFrequency ("Detail Sin Frequency", Range(0.1, 5)) = 1
        _WaveDetailCosFrequency ("Detail Cos Frequency", Range(0.1, 5)) = 1

        [Toggle] _IsNeedNoise ("Use Wave Noise", Float) = 0
        _SmoothNoiseMap ("Smooth Noise Map", 2D) = "gray" {}
        _NoiseTime ("Wave Noise Time", Range(0, 2)) = 0
        _NoiseScale ("Wave Noise Scale", Range(0, 2)) = 0
        _NoiseMapSampleScale ("Noise Map Sample Scale", Float) = 1

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
            int _SpectrumDebugLayer;
            // //高光参数
            // float _SpecularStrength,_SpecularPower,_SunGlintPower,_SunGlintStrength;
            //散射参数
            float _HeightStrength,_ScatterStrength,_WavePeakScatterStrength,_AmbientDensity;
            float4 _ScatterPeakColor,_ScatterColor;
            //泡沫参数
            float _EdgeFoamPower;
            float4 _FoamColor;
            //粗糙度
            float _Roughness,_FoamRoughness;
            //距离衰减
            float _DistanceFadeDepthAttenuation;
            //曲面细分着色器参数
            float _TessEdgeLength;
            float _WaterSize;
            float _PatchResolution;
            float _TessDistancePower,_TessMinFactor,_TessMaxFactor;
            float _TessNearDistance,_TessFarDistance;
            float _TessFarMultiplier;
            float _CoastTessDistance;
            float _CoastTessFade;
            float _CoastTessFactor;


            float _SunGlintFadeStart, _SunGlintFadeEnd,_FarSunSpecularWidth;
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
                if (_SpectrumDebugLayer >= 0)
                {
                    int layerIndex = clamp(_SpectrumDebugLayer, 0, 3);
                    float4 displacement = SAMPLE_TEXTURE2D_ARRAY_LOD(_DisplacementTexture, sampler_DisplacementTexture, GetSpectrumUV(worldXZ, layerIndex), layerIndex, 0);
                    displacement.a *= _OceanFoamStrengths[layerIndex];
                    return displacement;
                }

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
                if (_SpectrumDebugLayer >= 0)
                {
                    int layerIndex = clamp(_SpectrumDebugLayer, 0, 3);
                    return SAMPLE_TEXTURE2D_ARRAY_LOD(_SlopeTexture, sampler_SlopeTexture, GetSpectrumUV(worldXZ, layerIndex), layerIndex, 0).rg;
                }

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
                Coastline coastline = GetCoastline(shoreline);
                // 将工程的海岸数据转换为 FF2 Profile 动画使用的精简数据。
                float2 profileUV = GetProfileUV(positionWS, coastline);
                // 按照 FF2 的距离、时间和沿岸 Detail 公式生成 WaveProfileMap UV。

                float shorelineFoam;
                // 接收 Profile B 通道的泡沫数据，当前阶段只保留而不参与着色。
                float2 forwardUpward = SampleProfileMap(profileUV, shorelineFoam);
                // 从 Profile RG 通道解码朝岸水平位移和垂直位移。
                float3 coastSlopeNormal = ComputeCoastSlopeNormal(coastline, oceanXZ);
                // 沿朝岸方向预测地形高度，取得 FF2 用来处理爬坡运动的坡面方向。
                float3 shorelineDisplacement = GetFluxSlopeOffset(
                    forwardUpward,
                    coastline,
                    coastSlopeNormal);
                // 将 Profile 位移沿预测坡面传播，并在离岸后逐渐恢复水平朝岸方向。
                shorelineDisplacement *= shoreline.waveScale;
                // 按 FF2 的 Coastline Scale 数据约束 Profile 位移，远水和陆地不再残留近岸浪。
                shorelineDisplacement *= _WaveProfileOffsetStrength;
                // 使用独立强度参数整体调整近岸 Profile 位移幅度。

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
                float3 normalWS = normalize(float3(-slope.x,1.0,-slope.y));//微观法线
                float3 macroNormal = float3(0.0, 1.0, 0.0);//宏观法线
                normalWS = normalize(lerp(
                    macroNormal,
                    normalWS,
                    distanceFade
                ));//法线随距离衰减


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

                half3 waterColor = lerp(_ShallowColor.rgb, _DeepColor.rgb, depthWeight);
                half3 refractColor = lerp(refractSceneColor, waterColor, depthWeight);

                half3 reflectionColor = SAMPLE_TEXTURE2D(
                    _PlanarReflectionTex,
                    sampler_PlanarReflectionTex,
                    reflectionUV
                ).rgb;

                
                //读取泡沫
                float4 displacement = SampleOceanDisplacement(input.oceanXZ);
                float rawFoam = saturate(displacement.a);
                float foam = smoothstep(0.25, 0.75, rawFoam);
                foam *= distanceFade;
                float3 foamColor = _FoamColor.rgb * mainLight.color.rgb;
                //粗糙度
                float roughness = max(0.02, _Roughness + foam * _FoamRoughness);
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
                finalColor = lerp(finalColor, foamColor, foam);
                // 1. 只看平面反射纹理
                if (_DebugMode == 1)
                {
                    return half4(reflectionColor, 1);
                }

                // 2. 只看 opaque 折射采样
                if (_DebugMode == 2)
                {
                    return half4(refractSceneColor, 1);
                }

                // 3. 只看深度权重
                if (_DebugMode == 3)
                {
                    return half4(depthWeight, depthWeight, depthWeight, 1);
                }

                // 4. 只看 FFT 位移贴图 RGB
                if (_DebugMode == 4)
                {
                    return half4(displacement.rgb * 0.5 + 0.5, 1);
                }

                // 5. 只看泡沫 alpha
                if (_DebugMode == 5)
                {
                    return half4(rawFoam, rawFoam, rawFoam, 1);
                }

                // 6. 只看 slope 贴图
                if (_DebugMode == 6)
                {
                    return half4(slope.x * 0.5 + 0.5, slope.y * 0.5 + 0.5, 0, 1);
                }

                // 7. 只看水面法线
                if (_DebugMode == 7)
                {
                    return half4(normalWS * 0.5 + 0.5, 1);
                }

                // 8. 只看散射项 scatter
                if (_DebugMode == 8)
                {
                    return half4(scatter, 1);
                }

                // 9. 只看 k1 波峰散射强度
                if (_DebugMode == 9)
                {
                    return half4(k1, k1, k1, 1);
                }

                // 10. 只看菲涅尔
                if (_DebugMode == 10)
                {
                    return half4(Fresnel, 1);
                }
                // 11. 只看高光
                if (_DebugMode == 11)
                {
                    return half4(specular, 1);
                }
                
                if (_DebugMode >= 12 && _DebugMode <= 14 && shoreline.insideMap < 0.5)
                {
                    return half4(1, 0, 1, 1);
                }

                if (_DebugMode == 12)
                {
                    return half4(shoreline.encodedCoast.rrr, 1);
                }

                if (_DebugMode == 13)
                {
                    return half4(shoreline.encodedCoast.g, shoreline.encodedCoast.b, 0, 1);
                }

                if (_DebugMode == 14)
                {
                    return half4(shoreline.encodedCoast.aaa, 1);
                }

                if (_DebugMode == 15)
                {
                    float normalizedDistance = saturate(shoreline.waterDistance / max(_MaxCoastDistance, 0.0001) * 0.5 + 0.5);
                    return half4(normalizedDistance.xxx, 1);
                }

                if (_DebugMode == 16)
                {
                    return half4(shoreline.fftWeight.xxx, 1);
                }
                if (_DebugMode == 17)
                {
                    if (shoreline.insideMap < 0.5)
                    {
                        return half4(1, 0, 1, 1);
                    }

                    float2 profileUV = ComputeShoreWaveProfileUV(shoreline, input.oceanXZ);
                    float sampledU = frac(profileUV.x);

                    return half4(sampledU.xxx, 1);
                }

                if (_DebugMode == 18)
                {
                    if (shoreline.insideMap < 0.5)
                    {
                        return half4(1, 0, 1, 1);
                    }

                    float2 profileUV = ComputeShoreWaveProfileUV(shoreline, input.oceanXZ);
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
