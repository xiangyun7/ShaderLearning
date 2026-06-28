Shader "Tutorial/ShadowMap"
{
    Properties
    {
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100
        ZWrite Off ZTest Always Cull Off
        Pass
        {
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D_FLOAT(_LightDepthTexture);SAMPLER(sampler_LightDepthTexture);
            float4x4 _LightViewProjectionMatrix;
            float4 _LightDepthParams; // x near, y far, z bias

            //防止查询到天空盒
            bool IsSkyDepth(float rawDepth)
            {
                #if UNITY_REVERSED_Z
                    return rawDepth <= 0.00001;
                #else
                    return rawDepth >= 0.99999;
                #endif
            }

            //通过深度和uv构建世界空间坐标
            float3 ReconstructWorldPosition(float2 uv, float rawDepth)
            {
                #if UNITY_REVERSED_Z
                    float deviceDepth = rawDepth;
                #else
                    float deviceDepth = lerp(UNITY_NEAR_CLIP_VALUE, 1.0, rawDepth);
                #endif

                return ComputeWorldSpacePosition(uv, deviceDepth, UNITY_MATRIX_I_VP);
            }


            half4 frag (Varyings input) : SV_Target
            {
                float2 uv = input.texcoord.xy;

                // 主相机颜色。来源是 Pass 里第二次 Blit 的 source：tempColor。
                half3 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb;

                // 主相机深度。来源是 ConfigureInput(Depth) 后 URP 准备的 _CameraDepthTexture。
                float rawDepth = SampleSceneDepth(uv);
                if (IsSkyDepth(rawDepth))
                    return half4(color, 1);
                // 主相机屏幕像素 -> 世界坐标。
                float3 positionWS = ReconstructWorldPosition(uv, rawDepth);
                // 世界坐标 -> 光源相机uv。
                float4 lightClip = mul(_LightViewProjectionMatrix, float4(positionWS, 1.0));
                float3 lightNDC = lightClip.xyz / max(lightClip.w, 1e-5);
                float2 lightUV = lightNDC.xy * 0.5 + 0.5;
                // 临时测试：如果加了这句阴影方向立刻对了，说明就是 RT 的 V 方向和你手算 UV 不一致。
                lightUV.y = 1.0 - lightUV.y;
                bool outside =
                    lightUV.x < 0.0 || lightUV.x > 1.0 ||
                    lightUV.y < 0.0 || lightUV.y > 1.0 ||
                    lightNDC.z < 0.0 || lightNDC.z > 1.0;
                if (outside)
                    return half4(color, 1);//超出光源相机的视线外了，无法渲染阴影\

                // 当前世界点在光源相机下的深度。
                float currentLightDepth = lightNDC.z;
                // 光源相机 depth texture 里记录的深度。
                float shadowMapDepth = SAMPLE_TEXTURE2D(_LightDepthTexture,sampler_LightDepthTexture,lightUV).r;

                float bias = _LightDepthParams.z;

                #if UNITY_REVERSED_Z
                    // reversed-Z 中，越靠近相机 depth 越大。
                    float inShadow = currentLightDepth + bias < shadowMapDepth ? 1.0 : 0.0;
                #else
                    // 普通 Z 中，越远 depth 越大。
                    float inShadow = currentLightDepth - bias > shadowMapDepth ? 1.0 : 0.0;
                #endif
                // 最简单的后处理合成：阴影处把颜色压暗。
                float shadowFactor = lerp(1.0, 0.35, inShadow);
                color *= shadowFactor;

                return half4(color, 1);
                //return half4(inShadow.xxx, 1);
                //return float4(1,1,1,1);
            }
            ENDHLSL
        }
    }
}
