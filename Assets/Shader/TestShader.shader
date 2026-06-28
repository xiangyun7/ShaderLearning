Shader "Tutorial/TestShader"
{
    Properties
    {
        // 在材质面板上显示的颜色属性
        _BaseColor ("Base Color", Color) = (1,1,1,1)
    }
    SubShader
    {
        // 告诉 URP 这是一个通用的 Pass
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalRenderPipeline" "Queue"="Geometry+2"}
        LOD 100

        Pass
        {
            Name "ForwardLit"
            // 关键：URP 需要指定 LightMode 才能正确参与渲染管线
            /*
            Stencil{
                Ref 1
                Comp EQUAL
                Pass Keep
                Fail Keep
            }*/



            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // 关键：包含 URP 的核心库，这行代码让 Shader 能在 URP 下工作
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            float4 _BaseColor;

            // 定义输入给顶点着色器的数据结构 (顶点数据)
            struct Attributes
            {
                float4 positionOS : POSITION; // 模型空间坐标
                uint vertexID:SV_VertexID;
            };

            // 定义从顶点着色器传递给片元着色器的数据结构
            struct Varyings
            {
                float4 positionCS : SV_POSITION; // 裁剪空间坐标 (最终屏幕位置)
                float3 clr :   COLOR;//加上nointerpolation不进行插值计算
               // float3 barycentric : TEXCOORD0;
            };

            // 顶点着色器函数
            Varyings vert(Attributes input)
            {
                Varyings output;
                // 使用 URP 提供的函数将物体坐标转换为屏幕坐标
                // 这比传统的 UNITY_MATRIX_MVP 更符合 URP 规范

                // float sinx = input.positionOS.x;
                // float siny = input.positionOS.y+sin(input.positionOS.x*10.0+_Time.y);
                // float sinz = input.positionOS.z;



                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = vertexInput.positionCS;
                
                
                // uint index = input.vertexID%3;
                // float3 bc = float3(index == 0, index == 1, index == 2);
                // output.barycentric = bc;
                output.clr = vertexInput.positionWS.xyz;

                return output;
            }

            // 片元着色器函数

            float4 frag(Varyings input) : SV_TARGET
            {
                //float3 color = input.barycentric;

                //float minEdge = min(min(input.barycentric.x,input.barycentric.y),input.barycentric.z);
                
                //return float4(abs(input.clr),1)*0.5;
                return _BaseColor;
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
}