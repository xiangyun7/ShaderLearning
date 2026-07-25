Shader "Tutorial/Moss Shell"
{
    Properties
    {
        [Header(clr)]
        _ColorSaturation("Color Saturation", Range(0, 1.5)) = 0.7
        _ColorTint("Color Tint", Color) = (0.55, 0.52, 0.32, 1)
        _ColorTintStrength("Color Tint Strength", Range(0, 1)) = 0.15
        [Header(Shell)]
        _UseInstancedShellT ("Use Instanced Shell T", Float) = 0
        _ActiveShellCount ("Active Shell Count", Float) = 1
        _ShellT ("Shell T", Range(0, 1)) = 0
        _ShellHeight ("Shell Height", Float) = 0.06
        _AlphaCutoff ("Alpha Cutoff", Range(0, 1)) = 0.05
        [Header(Tex)]
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

        [Header(Light)]
        _WrapLighting("Wrap Lighting", Range(0, 2)) = 0.35
        _AmbientStrength("Ambient Strength", Range(0, 2)) = 0.7
        _DirectStrength("Direct Strength", Range(0, 2)) = 0.8
        _TipLighten("Tip Lighten", Range(0, 1)) = 0.15

        [Header(Wind)]
        _WindDirection("Wind Direction", Vector) = (1, 0, 0, 0)
        _WindStrength("Wind Strength", Range(0, 2)) = 0.015
        _WindSpeed("Wind Speed", Range(0, 10)) = 1.5
        _WindShellPower("Wind Shell Power", Range(1, 8)) = 3
        _WindPhaseScale("Wind Phase Scale", Range(0.005, 0.5)) = 0.06
        _WindPhaseStrength("Wind Phase Strength", Range(0, 1)) = 1
        _WindSideStrength("Wind Side Strength", Range(0, 1)) = 0.25
        _WindSideSpeed("Wind Side Speed", Range(0, 3)) = 1.37
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
            #pragma target 3.5
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float _ShellT,_ShellHeight;
                float _UseInstancedShellT, _ActiveShellCount;
                float _AlphaCutoff;
                float _NoiseScale,_TipCutoff;
                float _HeightInfluence,_HeightPower,_HeightSoftness;
                float _NoiseStrength;
                float _AOInfluence;
                float _WrapLighting,_AmbientStrength,_DirectStrength,_TipLighten;
                float _ColorSaturation;
                half4 _ColorTint;
                float _ColorTintStrength;
                float4 _WindDirection;
                float _WindStrength;
                float _WindSpeed;
                float _WindShellPower;
                float _WindPhaseScale,_WindPhaseStrength;
                float _WindSideStrength,_WindSideSpeed;
            CBUFFER_END
            TEXTURE2D(_DensityNoise);SAMPLER(sampler_DensityNoise);
            TEXTURE2D(_HeightMask);SAMPLER(sampler_HeightMask);
            TEXTURE2D(_MossBaseMap);SAMPLER(sampler_MossBaseMap);
            TEXTURE2D(_MossMaskMap);SAMPLER(sampler_MossMaskMap);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv1 : TEXCOORD1;
                float4 color : COLOR;
                uint instanceID : SV_InstanceID;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float4 color : COLOR;
                float shellT : TEXCOORD0;
                float2 mossUV : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
                float3 normalWS : TEXCOORD3;
                float3 viewDirWS : TEXCOORD4;
            };

            

            //-----------------function mode----------------------------------
            //计算shell层数函数
            float GetShellT(uint instanceID)
            {
                float fallbackShellT = saturate(_ShellT);

                float shellCount = max(1.0, _ActiveShellCount);
                float instancedShellT = shellCount <= 1.0
                    ? 0.0
                    : (float)instanceID / (shellCount - 1.0);

                return _UseInstancedShellT > 0.5
                    ? saturate(instancedShellT)
                    : fallbackShellT;
            }
            //调整饱和度函数
            half3 ApplySaturation(half3 color, half saturation)
            {
                half luminance = dot(color, half3(0.2126h, 0.7152h, 0.0722h));
                return lerp(luminance.xxx, color, saturation);
            }
            //调整色调函数
            half3 ShiftTowardTint(half3 color, half3 tint, half strength)
            {
                half value = max(max(color.r, color.g), color.b);
                half3 tintedColor = tint * value;
                return lerp(color, tintedColor, strength);
            }
            //随机风向
            float Hash21(float2 p)
            {
                p = frac(p * float2(123.34, 456.21));
                p += dot(p, p + 45.32);
                return frac(p.x * p.y);
            }

            float SmoothValueNoise(float2 uv)
            {
                float2 i = floor(uv);
                float2 f = frac(uv);
                f = f * f * (3.0 - 2.0 * f);

                float a = Hash21(i);
                float b = Hash21(i + float2(1.0, 0.0));
                float c = Hash21(i + float2(0.0, 1.0));
                float d = Hash21(i + float2(1.0, 1.0));

                return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
            }

            float GetWindPhase(float3 basePositionWS)
            {
                float phaseNoise = SmoothValueNoise(basePositionWS.xz * _WindPhaseScale);
                return phaseNoise * 6.2831853 * _WindPhaseStrength;
            }

            //--------------------shader mode----------------------------------------------
            Varyings Vert(Attributes input)
            {
                Varyings output;

                float shellT = GetShellT(input.instanceID);
                float edgeFade = saturate(input.color.g);

                float3 normalOS = normalize(input.normalOS);
                float3 basePositionOS = input.positionOS.xyz;
                float3 basePositionWS = TransformObjectToWorld(basePositionOS);

                float3 positionOS = basePositionOS;
                positionOS += normalOS * _ShellHeight * shellT * edgeFade;

                float3 positionWS = TransformObjectToWorld(positionOS);
                float3 normalWS = TransformObjectToWorldNormal(normalOS);

                float3 windDirectionWS = normalize(float3(_WindDirection.x, 0.0, _WindDirection.z));
                float3 windSideWS = float3(-windDirectionWS.z, 0.0, windDirectionWS.x);

                float windPhase = GetWindPhase(basePositionWS);
                float windWave = sin(_Time.y * _WindSpeed + windPhase);

                float sidePhase = GetWindPhase(basePositionWS + float3(37.2, 0.0, 19.7));
                float sideWave = sin(_Time.y * _WindSpeed * _WindSideSpeed + sidePhase);

                float windWeight = pow(saturate(shellT), _WindShellPower) * edgeFade;

                float3 windOffsetWS =
                    windDirectionWS * windWave * _WindStrength * windWeight
                    + windSideWS * sideWave * _WindStrength * _WindSideStrength * windWeight;

                positionWS += windOffsetWS;

                output.positionHCS = TransformWorldToHClip(positionWS);
                output.positionWS = positionWS;
                output.normalWS = normalize(normalWS);
                output.viewDirWS = GetWorldSpaceNormalizeViewDir(positionWS);
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

                mossBase = ApplySaturation(mossBase, _ColorSaturation);
                mossBase = ShiftTowardTint(mossBase, _ColorTint.rgb, _ColorTintStrength);

                half ao = mossMask.g;
                half aoByLayer = _AOInfluence * (1.0h - input.shellT * 0.5h);
                half finalAO = lerp(1.0h, ao, aoByLayer);

                float3 normalWS = normalize(input.normalWS);
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);

                half ndotl = saturate(dot(normalWS, mainLight.direction));
                half wrapNdotL = saturate((ndotl + _WrapLighting) / (1.0h + _WrapLighting));

                half3 ambient = SampleSH(normalWS) * _AmbientStrength;
                half3 direct = mainLight.color
                    * wrapNdotL
                    * mainLight.shadowAttenuation
                    * mainLight.distanceAttenuation
                    * _DirectStrength;

                half layerLighten = input.shellT * _TipLighten;
                half3 color = mossBase * (ambient + direct);
                color *= finalAO;
                color += mossBase * layerLighten * 0.15h;

                return half4(color, 1);
            }
            ENDHLSL
        }
    }
}