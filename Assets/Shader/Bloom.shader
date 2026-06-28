Shader "Tutorial/Bloom"
{
    Properties
    {
        _MainTex ("Source Texture", 2D) = "white" {}
        //_BloomTex ("Bloom", 2D) = "black" {}
        _Threshold ("Bloom Threshold", Range(0, 1)) = 0.75//模糊阈值
        _Intensity ("Bloom Intensity", Range(0, 10)) = 1.0//模糊亮度
        _BlurSize ("Blur Size", Range(0.5, 4)) = 1.0//模糊程度
    }



    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" }
        LOD 100
        Cull Off ZWrite Off ZTest Always//后处理不需要剔除，深度写入。深度测试永远通过


        Pass
        {
            Name "BloomPrefilter"
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_MainTex);SAMPLER(sampler_MainTex);
            float _Threshold;float _Intensity;
            
            struct appdata
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            v2f vert(appdata input)
            {
                v2f output;
                VertexPositionInputs vertexPosition = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = vertexPosition.positionCS;
                output.uv = input.uv;
                return output;
            }
            
            half4 frag(v2f input) : SV_Target
            {
                half4 clr = SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex,input.uv);

                //简单Bloom(提亮度)
                half3 brightness = max(clr.rgb - _Threshold, 0.0);

                return half4(brightness,1.0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "BloomHorizontalBlur"
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            
            struct appdata
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            TEXTURE2D(_MainTex);SAMPLER(sampler_MainTex);
            float4 _MainTex_TexelSize;
            float _BlurSize;

            v2f vert(appdata input)
            {
                v2f output;
                VertexPositionInputs vertexPosition = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = vertexPosition.positionCS;
                output.uv = input.uv;
                return output;
            }
            
            half4 frag(v2f i) : SV_Target
            {
                float2 offset = _MainTex_TexelSize.xy * float2(_BlurSize, 0.0);//让横向的像素变模糊
                //高斯横向模糊
                half3 c0 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).rgb * 0.227027;
                half3 c1 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv + offset * 1.0).rgb * 0.1945946;
                half3 c2 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv - offset * 1.0).rgb * 0.1945946;
                half3 c3 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv + offset * 2.0).rgb * 0.1216216;
                half3 c4 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv - offset * 2.0).rgb * 0.1216216;
                half3 c5 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv + offset * 3.0).rgb * 0.054054;
                half3 c6 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv - offset * 3.0).rgb * 0.054054;
                half3 c7 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv + offset * 4.0).rgb * 0.016216;
                half3 c8 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv - offset * 4.0).rgb * 0.016216;


                return half4(c0 + c1 + c2 + c3 + c4 + c5 + c6 + c7 + c8, 1.0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "BloomVerticalBlur"
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            
            struct appdata
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            TEXTURE2D(_MainTex);SAMPLER(sampler_MainTex);
            float4 _MainTex_TexelSize;
            float _BlurSize;

            v2f vert(appdata input)
            {
                v2f output;
                VertexPositionInputs vertexPosition = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = vertexPosition.positionCS;
                output.uv = input.uv;
                return output;
            }
            
            half4 frag(v2f i) : SV_Target
            {
                float2 offset = _MainTex_TexelSize.xy * float2(0.0, _BlurSize);
                half3 c0 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).rgb * 0.227027;
                half3 c1 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv + offset * 1.0).rgb * 0.1945946;
                half3 c2 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv - offset * 1.0).rgb * 0.1945946;
                half3 c3 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv + offset * 2.0).rgb * 0.1216216;
                half3 c4 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv - offset * 2.0).rgb * 0.1216216;
                half3 c5 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv + offset * 3.0).rgb * 0.054054;
                half3 c6 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv - offset * 3.0).rgb * 0.054054;
                half3 c7 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv + offset * 4.0).rgb * 0.016216;
                half3 c8 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv - offset * 4.0).rgb * 0.016216;

                return half4(c0 + c1 + c2 + c3 + c4 + c5 + c6 + c7 + c8, 1.0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "BloomComposite"
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            
            struct appdata
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            TEXTURE2D(_MainTex);SAMPLER(sampler_MainTex);
            TEXTURE2D(_BloomTex);SAMPLER(sampler_BloomTex);
            float _Intensity;

            v2f vert(appdata input)
            {
                v2f output;
                VertexPositionInputs vertexPosition = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = vertexPosition.positionCS;
                output.uv = input.uv;
                return output;
            }
            
            half4 frag(v2f i) : SV_Target
            {
                half3 original = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).rgb;
                half3 bloom = SAMPLE_TEXTURE2D(_BloomTex, sampler_BloomTex, i.uv).rgb;
                return half4(original + bloom * _Intensity, 1.0);
            }
            ENDHLSL
        }

    }
}