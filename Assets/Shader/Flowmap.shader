Shader "Tutorial/Flowmap"
{
    Properties
    {
        _BaseColor ("BaseColor", Color) = (1,1,1,1)
        _MainTex ("MainTex", 2D) = "white" {}
        _FlowMap ("Flow Map", 2D) = "gray" {}
        _FlowSpeed("FlowSpeed",float) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline"}
        LOD 100

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_MainTex);SAMPLER(sampler_MainTex);
            TEXTURE2D(_FlowMap);SAMPLER(sampler_FlowMap);
            float4 _BaseColor;
            float _FlowSpeed;

            struct appdata
            {
                float4 positionOS:POSITION;
                float2 uv:TEXCOORD0;
            };

            struct v2f
            {
                float4 positionCS:SV_POSITION;
                float2 uv:TEXCOORD0;
            };


            v2f vert (appdata input)
            {
                v2f output;
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS);
                output.positionCS = vertexInput.positionCS;
                output.uv = input.uv;
                return output;
            }

            float4 frag (v2f input) : SV_Target
            {
                float4 clr;

                half2 flowDir = 2.0*SAMPLE_TEXTURE2D(_FlowMap,sampler_FlowMap,input.uv).rg-1.0;
                
                float time1 = frac(_Time.y*_FlowSpeed);
                float time2 = frac(_Time.y*_FlowSpeed+0.5);

                float t = abs((time1-0.5)*2.0);

                float4 clr1 = SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex,input.uv-flowDir*time1);
                float4 clr2 = SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex,input.uv-flowDir*time2);

                clr = lerp(clr1,clr2,t);

                return clr;
            }
            ENDHLSL
        }
    }
}
