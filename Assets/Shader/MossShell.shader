Shader "Tutorial/Moss Shell"
{
    Properties
    {
        _BaseColor ("Root Color", Color) = (0.04, 0.16, 0.04, 1)
        _TipColor ("Tip Color", Color) = (0.45, 0.65, 0.18, 1)
        _ShellT ("Shell T", Range(0, 1)) = 0
        _ShellHeight ("Shell Height", Float) = 0.06
        _AlphaCutoff ("Alpha Cutoff", Range(0, 1)) = 0.05

        _DensityNoise ("Density Noise", 2D) = "white" {}
        _NoiseScale ("Noise Scale", Float) = 4
        _TipCutoff ("Tip Cutoff", Range(0, 1)) = 0.65

        _HeightMask ("Height Mask", 2D) = "white" {}
        _HeightInfluence ("Height Influence", Range(0, 1)) = 0.8
        _HeightPower ("Height Power", Range(0.25, 4)) = 1
        _HeightSoftness ("Height Softness", Range(0.001, 0.3)) = 0.08
        _NoiseStrength ("Noise Strength", Range(0, 1)) = 1

        _MossBaseMap("Moss Base Map", 2D) = "white" {}
        _MossMaskMap("Moss Mask Map", 2D) = "white" {}
        _AOInfluence("AO Influence", Range(0, 1)) = 0.5
        _BaseTextureStrength("Base Texture Strength", Range(0, 1)) = 1
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "AlphaTest"
            "RenderType" = "TransparentCutout"
        }

        Pass
        {
            Name "Forward"
            Tags { "LightMode" = "UniversalForward" }

            Cull Back
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv0 : TEXCOORD0;
                float2 uv1 : TEXCOORD1;
                float4 color : COLOR;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float4 color : COLOR;
                float shellT : TEXCOORD0;
                float2 mossUV : TEXCOORD1;
            };

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor,_TipColor;
                float _ShellT,_ShellHeight;
                float _AlphaCutoff;
                float _NoiseScale,_TipCutoff;
                float _HeightInfluence,_HeightPower,_HeightSoftness;
                float _NoiseStrength;
                float _AOInfluence;
                float _BaseTextureStrength;
            CBUFFER_END
            TEXTURE2D(_DensityNoise);SAMPLER(sampler_DensityNoise);
            TEXTURE2D(_HeightMask);SAMPLER(sampler_HeightMask);
            TEXTURE2D(_MossBaseMap);SAMPLER(sampler_MossBaseMap);
            TEXTURE2D(_MossMaskMap);SAMPLER(sampler_MossMaskMap);

            Varyings Vert(Attributes input)
            {
                Varyings output;

                float shellT = saturate(_ShellT);
                float edgeFade = saturate(input.color.g);

                float3 normalOS = normalize(input.normalOS);
                float3 positionOS = input.positionOS.xyz;
                positionOS += normalOS * _ShellHeight * shellT * edgeFade;

                output.positionHCS = TransformObjectToHClip(positionOS);
                output.color = input.color;
                output.shellT = shellT;
                output.mossUV = input.uv1;

                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                half mossWeight = saturate(input.color.r);
                half edgeFade = saturate(input.color.g);
                half visibility = mossWeight * edgeFade;

                half heightMask = SAMPLE_TEXTURE2D(
                    _HeightMask,
                    sampler_HeightMask,
                    input.mossUV
                ).r;

                heightMask = pow(saturate(heightMask), _HeightPower);

                half heightLimit = lerp(1.0h, heightMask, _HeightInfluence);
                half heightLayerFade = smoothstep(
                    input.shellT - _HeightSoftness,
                    input.shellT + _HeightSoftness,
                    heightLimit
                );

                float2 shellNoiseOffset = float2(input.shellT * 17.13, input.shellT * 31.71);

                half noise = SAMPLE_TEXTURE2D(
                    _DensityNoise,
                    sampler_DensityNoise,
                    input.mossUV * _NoiseScale + shellNoiseOffset
                ).r;

                half noisyDensity = lerp(1.0h, noise, _NoiseStrength);
                half cutoff = lerp(_AlphaCutoff, _TipCutoff, input.shellT);

                half alpha = visibility * heightLayerFade * noisyDensity;

                clip(alpha - cutoff);

                half3 mossBase = SAMPLE_TEXTURE2D(_MossBaseMap, sampler_MossBaseMap, input.mossUV).rgb;
                half4 mossMask = SAMPLE_TEXTURE2D(_MossMaskMap, sampler_MossMaskMap, input.mossUV);

                half ao = mossMask.g;

                half3 color = mossBase;

                half aoByLayer = _AOInfluence * (1.0h - input.shellT * 0.5h);
                color *= lerp(1.0h, ao, aoByLayer);
                return half4(color, 1);
            }
            ENDHLSL
        }
    }
}