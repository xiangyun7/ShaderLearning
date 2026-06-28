Shader "Tutorial/Water"
{
    Properties
    {
        _DistortionStrength ("Distortion Strength", Range(0, 0.03)) = 0.006

        [Header(Depth)]
        _DepthLevel ("Depth Level", Range(0, 5)) = 1
        _DepthPower ("Depth Power", Range(0.1, 5)) = 1

        [Header(WaterPlane)]
        _ShallowColor ("Shallow Color", Color) = (0.25, 0.75, 0.8, 1)
        _DeepColor ("Deep Color", Color) = (0.02, 0.12, 0.25, 1)

        [Header(SSS)]
        _SSSStrength ("SSS Strength", Range(0, 3)) = 0.5
        _sssDistortion ("SSS Distortion", Range(0.01, 2)) = 0.35
        _sssPower ("SSS Power", Range(1, 4)) = 2.0
        [Header(FFT Ocean)]
        _OceanLengthScale ("Ocean Length Scale", Float) = 200
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
            ZWrite Off
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_PlanarReflectionTex);SAMPLER(sampler_PlanarReflectionTex);//反射相机纹理
            TEXTURE2D(_CameraDepthTexture);SAMPLER(sampler_CameraDepthTexture);//相机深度
            TEXTURE2D(_CameraOpaqueTexture);SAMPLER(sampler_CameraOpaqueTexture);//不透明物体纹理(看水下做折射纹理)
            
            TEXTURE2D_ARRAY(_DisplacementTexture);
            SAMPLER(sampler_DisplacementTexture);
            TEXTURE2D_ARRAY(_SlopeTexture);
            SAMPLER(sampler_SlopeTexture);

            float _OceanLengthScale;


            half _DistortionStrength;
            half _DepthLevel,_DepthPower;
            half4 _ShallowColor,_DeepColor;
            half _SSSStrength;
            float _sssDistortion,_sssPower;

            struct appdata
            {
                float4 positionOS : POSITION;
            };

            struct v2f
            {
                float4 positionHCS : SV_POSITION;
                float4 screenPos : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float2 oceanUV : TEXCOORD2;
            };

            //————————function mode——————————————————
            float3 FresnelSchlick(float cosTheta, float3 F0)
            {
                return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5);
            }
            //————————shader mode—————————————————————
            v2f vert(appdata input)
            {
                v2f output;
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float2 oceanUV = positionWS.xz / max(_OceanLengthScale, 0.001);
                float4 displace = SAMPLE_TEXTURE2D_ARRAY_LOD(
                    _DisplacementTexture,
                    sampler_DisplacementTexture,
                    oceanUV,
                    0,0
                );
                positionWS += displace.rgb;

                
                
                output.positionWS = positionWS;
                output.positionHCS = TransformWorldToHClip(positionWS);
                output.screenPos = ComputeScreenPos(output.positionHCS);
                output.oceanUV = oceanUV;
                return output;
            }

            half4 frag(v2f input) : SV_Target
            {
                //计算法线
                float2 slope = SAMPLE_TEXTURE2D_ARRAY(
                    _SlopeTexture,
                    sampler_SlopeTexture,
                    input.oceanUV,
                    0
                ).rg;
                float3 normalWS = normalize(float3(-slope.x,1.0,-slope.y));

                Light mainLight = GetMainLight();
                float3 lightDirWS = normalize(mainLight.direction);
                float3 viewDirWS = normalize(_WorldSpaceCameraPos.xyz - input.positionWS);

                float2 screenUV = input.screenPos.xy / input.screenPos.w;
                float2 offset = normalWS.xz * _DistortionStrength;
                float2 reflectionUV = clamp(screenUV + offset, 0.001, 0.999);
                float2 refractUV = clamp(screenUV + offset, 0.001, 0.999);

                half3 refractSceneColor = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, refractUV).rgb;

                float rawDepth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, screenUV).r;
                float sceneDepth = LinearEyeDepth(rawDepth, _ZBufferParams);
                float waterDepth = input.screenPos.w;
                float depthDiff = max(0.0, sceneDepth - waterDepth);
                float depthWeight = pow(saturate(depthDiff * _DepthLevel), _DepthPower);

                half3 waterColor = lerp(_ShallowColor.rgb, _DeepColor.rgb, depthWeight);
                half3 refractColor = lerp(refractSceneColor, waterColor, depthWeight);

                float3 sssH = normalize(lightDirWS + normalWS * _sssDistortion);
                float sssIntensity = pow(saturate(dot(viewDirWS, -sssH)), _sssPower) * _SSSStrength;
                half3 sssColor = _ShallowColor.rgb * mainLight.color.rgb * sssIntensity;
                refractColor += sssColor;

                half3 reflectionColor = SAMPLE_TEXTURE2D(
                    _PlanarReflectionTex,
                    sampler_PlanarReflectionTex,
                    reflectionUV
                ).rgb;

                float NoV = saturate(dot(normalWS, viewDirWS));
                float3 F0 = float3(0.02, 0.02, 0.02);
                float3 F = FresnelSchlick(NoV, F0);

                half3 finalColor = reflectionColor * F + refractColor * (1.0 - F);
                float foamRaw = SAMPLE_TEXTURE2D_ARRAY(
                    _DisplacementTexture,
                    sampler_DisplacementTexture,
                    input.oceanUV,
                    0
                ).a;
                float foam = smoothstep(0.2, 1.0, saturate(foamRaw));

                half3 foamColor = lerp(_ShallowColor.rgb, half3(1.0, 1.0, 1.0), 0.75);

                float foamLight = saturate(dot(normalWS, lightDirWS) * 0.5 + 0.5);

                finalColor = lerp(finalColor, foamColor * foamLight, foam);

                return half4(finalColor, 1);
            }

            
            ENDHLSL
        }
    }
}
