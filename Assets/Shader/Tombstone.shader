Shader "Tutorial/Tombstone"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (0.16, 0.42, 0.32, 1)
        _BaseAlpha ("Base Alpha", Range(0, 1)) = 0.25

        [Header(Wide Gold Fresnel)]
        [HDR] _WideFresnelColor ("Wide Color", Color) = (1, 0.45, 0.08, 1)
        _WideFresnelRange ("Wide Range", Range(0.25, 4)) = 1.5
        _WideFresnelPower ("Wide Power", Range(0.25, 8)) = 2
        _WideAlphaStrength ("Wide Alpha Strength", Range(0, 1)) = 0.25
        _WideEmissionStrength ("Wide Emission Strength", Range(0, 10)) = 1.5

        [Header(Narrow Warm White Fresnel)]
        [HDR] _NarrowFresnelColor ("Narrow Color", Color) = (1, 0.85, 0.6, 1)
        _NarrowFresnelPower ("Narrow Power", Range(1, 16)) = 8
        _NarrowAlphaStrength ("Narrow Alpha Strength", Range(0, 1)) = 0.08
        _NarrowEmissionStrength ("Narrow Emission Strength", Range(0, 15)) = 4

        [Header(Height Fade)]
        _FadeStartOS ("Fade Start Object Y", Float) = 0.10
        _FadeEndOS ("Fade End Object Y", Float) = 0.45
        _InvisibleClipThreshold ("Invisible Clip Threshold", Range(0, 0.05)) = 0.001

        [Header(Flowing Dissolve)]
        _NoiseTexture ("Noise Texture", 2D) = "gray" {}
        _NoiseScale ("Noise Scale", Float) = 1.3
        _NoiseFlowDirection ("Noise Flow Direction", Vector) = (0, 1, 0, 0)
        _NoiseSpeed ("Noise Speed", Float) = 0.05
        _NoiseDistortionStrength ("Height Distortion Strength", Range(0, 0.5)) = 0.12

        [Header(Stone Detail Normal)]
        [Normal] _DetailNormalMap ("Detail Normal Map", 2D) = "bump" {}
        _DetailNormalTiling ("Detail Normal Tiling", Vector) = (1, 1, 0, 0)
        _DetailNormalStrength ("Detail Normal Strength", Range(0, 5)) = 0.3

        [Enum(Final,0,WideFresnel,1,NarrowFresnel,2,HeightMask,3,NoiseMask,4,DetailNormalTS,5)]
        _DebugMode ("Debug Mode", Float) = 0
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
            Name "Forward"
            Tags { "LightMode" = "UniversalForward" }

            Blend One OneMinusSrcAlpha
            ZTest LEqual
            ZWrite Off
            Cull Back

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"


            //-----------params mode------------------------------------

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float _BaseAlpha;

                float4 _WideFresnelColor;
                float _WideFresnelRange;
                float _WideFresnelPower;
                float _WideAlphaStrength;
                float _WideEmissionStrength;

                float4 _NarrowFresnelColor;
                float _NarrowFresnelPower;
                float _NarrowAlphaStrength;
                float _NarrowEmissionStrength;

                float _FadeStartOS;
                float _FadeEndOS;
                float _InvisibleClipThreshold;

                float _NoiseScale;
                float4 _NoiseFlowDirection;
                float _NoiseSpeed;
                float _NoiseDistortionStrength;

                float4 _DetailNormalTiling;
                float _DetailNormalStrength;

                float _DebugMode;
            CBUFFER_END
            TEXTURE2D(_NoiseTexture);SAMPLER(sampler_NoiseTexture);
            TEXTURE2D(_DetailNormalMap);SAMPLER(sampler_DetailNormalMap);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                half3 normalWS : TEXCOORD1;
                float heightOS : TEXCOORD2;
                float2 noiseCoordOS : TEXCOORD3;
                float2 detailUV : TEXCOORD4;
                half3 tangentWS : TEXCOORD5;
                half3 bitangentWS : TEXCOORD6;
            };

            //---------------function mode------------------------------------
            //ndotv获取菲涅尔项函数
            half GetBaseFresnel(half3 normalWS, float3 positionWS)
            {
                half3 viewDirWS = GetWorldSpaceNormalizeViewDir(positionWS);
                half ndotv = saturate(dot(normalize(normalWS), viewDirWS));
                return 1.0h - ndotv;
            }
            //获取高度遮罩函数
            half GetHeightMask(float heightOS)
            {
                float fadeStart = min(_FadeStartOS, _FadeEndOS);
                float fadeEnd = max(_FadeStartOS, _FadeEndOS);
                float fadeWidth = max(fadeEnd - fadeStart, 1e-5);

                half heightMask = saturate((heightOS - fadeStart) / fadeWidth);
                return heightMask * heightMask * (3.0h - 2.0h * heightMask);
            }
            half SampleFlowNoise(float2 positionOS)
            {
                float2 flow = _NoiseFlowDirection.xy;
                float2 flowDirection =
                    dot(flow, flow) > 0.000001
                    ? normalize(flow)
                    : float2(0, 1);

                // Subtracting the offset makes the pattern travel along flowDirection.
                float2 noiseUV =
                    positionOS * _NoiseScale
                    - flowDirection * (_Time.y * _NoiseSpeed);

                return SAMPLE_TEXTURE2D(
                    _NoiseTexture,
                    sampler_NoiseTexture,
                    noiseUV
                ).r;
            }

            half3 SampleDetailNormalTS(float2 originalUV)
            {
                float2 detailUV =
                    originalUV * _DetailNormalTiling.xy
                    + _DetailNormalTiling.zw;

                half4 packedNormal = SAMPLE_TEXTURE2D(
                    _DetailNormalMap,
                    sampler_DetailNormalMap,
                    detailUV
                );

                return UnpackNormalScale(
                    packedNormal,
                    _DetailNormalStrength
                );
            }
            half3 GetDetailNormalWS(half3 normalTS,half3 tangentWS,half3 bitangentWS,half3 smoothNormalWS)
            {
                half3 tangent = normalize(tangentWS);
                half3 bitangent = normalize(bitangentWS);
                half3 smoothNormal = normalize(smoothNormalWS);

                half3 detailNormalWS =
                    tangent * normalTS.x
                    + bitangent * normalTS.y
                    + smoothNormal * normalTS.z;

                return normalize(detailNormalWS);
            }


            //---------------Shader mode---------------------------------
            Varyings Vert(Attributes input)
            {
                Varyings output;

                VertexPositionInputs positionInputs = GetVertexPositionInputs(input.positionOS.xyz);

                VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                output.positionHCS = positionInputs.positionCS;
                output.positionWS = positionInputs.positionWS;
                output.normalWS = normalize(normalInputs.normalWS);
                output.heightOS = input.positionOS.y;
                output.noiseCoordOS = input.positionOS.xy;
                output.detailUV = input.uv;
                output.tangentWS = normalize(normalInputs.tangentWS);
                output.bitangentWS = normalize(normalInputs.bitangentWS);

                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                half baseFresnel = GetBaseFresnel(input.normalWS, input.positionWS);
                half3 detailNormalTS = SampleDetailNormalTS(input.detailUV);
                half3 detailNormalWS = GetDetailNormalWS(detailNormalTS,input.tangentWS,input.bitangentWS,input.normalWS);

                half smoothFresnel = GetBaseFresnel(input.normalWS, input.positionWS);

                half detailFresnel = GetBaseFresnel(detailNormalWS, input.positionWS);

                half wideMask = pow(
                    saturate(detailFresnel * _WideFresnelRange),
                    max(_WideFresnelPower, 0.001)
                );

                half narrowMask = pow(
                    smoothFresnel,
                    max(_NarrowFresnelPower, 0.001)
                );

                half noise = SampleFlowNoise(input.noiseCoordOS);
                float noiseOffset =
                    (noise * 2.0h - 1.0h) * _NoiseDistortionStrength;

                half heightMask =
                    GetHeightMask(input.heightOS + noiseOffset);

                if (_DebugMode > 4.5)
                {
                    half3 debugNormalColor = detailNormalTS * 0.5h + 0.5h;
                    return half4(debugNormalColor, 1);
                }
                if (_DebugMode > 3.5)
                    return half4(noise.xxx, 1);

                if (_DebugMode > 2.5)
                    return half4(heightMask.xxx, 1);

                if (_DebugMode > 1.5)
                    return half4(narrowMask.xxx, 1);

                if (_DebugMode > 0.5)
                    return half4(wideMask.xxx, 1);

                clip(heightMask - _InvisibleClipThreshold);

                half fresnelAlpha = saturate(
                    _BaseAlpha
                    + wideMask * _WideAlphaStrength
                    + narrowMask * _NarrowAlphaStrength
                );

                half alpha = fresnelAlpha * heightMask;
                half3 basePremultiplied = _BaseColor.rgb * alpha;

                half3 emission =
                    (   wideMask * _WideFresnelColor.rgb * _WideEmissionStrength
                        + narrowMask * _NarrowFresnelColor.rgb
                          * _NarrowEmissionStrength
                    ) * heightMask;

                return half4(basePremultiplied + emission, alpha);
            }
            ENDHLSL
        }
    }
}