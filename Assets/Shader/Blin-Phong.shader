Shader "Tutorial/Blin-Phong"
{
    Properties
    {
        _MainTex ("Main Texture", 2D) = "white" {}
    }

    SubShader
    {
        // 【关键】告诉 Unity 这是 URP 管线使用的 Shader
        Tags 
        { 
            "LightMode" = "DepthNormals"
            "RenderType" = "Opaque" 
            "RenderPipeline" = "UniversalPipeline" 
            "Queue"="Geometry+2"
        }

        LOD 100

        /*
        Stencil{
                Ref 1
                Comp EQUAL
                Pass Keep
                Fail Keep
        }*/

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // 【关键】URP 核心库引用
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_MainTex);SAMPLER(sampler_MainTex);

            struct Attributes
            {
                float4 positionOS: POSITION;
                float2 uv:TEXCOORD0;
                float3 norOS:NORMAL;
            };

            struct Varyings
            {
                float4 positionCS: SV_POSITION;
                float2 uv:TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 norWS      : TEXCOORD2;  
            };

            // --- 顶点着色器 ---
            Varyings vert(Attributes input)
            {
                Varyings output;
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = vertexInput.positionCS;
                output.positionWS = vertexInput.positionWS;
                output.uv = input.uv;
                output.norWS = TransformObjectToWorldNormal(input.norOS);
                return output;
            }

            // --- 片段着色器 ---
            float4 frag(Varyings input) : SV_Target
            {
                float3 clr;
                float3 cameraDir = normalize(_WorldSpaceCameraPos-input.positionWS);
                float3 normalWS = normalize(input.norWS);
                Light mainLight = GetMainLight();
                float3 diffuse = 2.0*SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex,input.uv)*max(0,dot(mainLight.direction,normalWS));
                float3 h = normalize(mainLight.direction+cameraDir);//半程向量
                float3 specular = 1.005*max(0,dot(h,normalWS));
                float3 ambient = 0.1*SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex,input.uv);
                clr = ambient+diffuse+pow(specular,200);
                return float4(clr,1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }

            ZWrite On
            Cull Back

            HLSLPROGRAM
            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitDepthNormalsPass.hlsl"
            ENDHLSL
        }
    }
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}