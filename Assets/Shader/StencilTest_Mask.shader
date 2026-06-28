Shader "Tutorial/StencilTest_Mask"
{
    Properties
    {
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry-1" }
        LOD 100

        /*
        ZWrite Off
            //ColorMask 0
        Stencil{
            Ref 1 
            Comp ALWAYS
            Pass replace
        }*/

        Pass
        {
            


            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"


            struct appdata
            {
                float4 positionOS:POSITION;
            };

            struct v2f
            {
                float4 positionCS:SV_POSITION;
            };


            v2f vert (appdata input)
            {
                v2f output;
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS);
                output.positionCS = vertexInput.positionCS;
                return output;
            }

            float4 frag (v2f input) : SV_Target
            {
                float4 clr = float4(1,1,1,1);
                return clr;
            }
            ENDHLSL
        }
    }
}
