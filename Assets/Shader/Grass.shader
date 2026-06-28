Shader "Tutorial/Grass"
{
    Properties
    {
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline"}
        LOD 100

        Cull Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma geometry geo
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"


            struct appdata{
                float4 positionOS : POSITION;
            };
            struct geoOut{
                float4 positionCS: SV_POSITION;
            };
            struct v2f{
                float4 positionCS : SV_POSITION;
            };


            appdata vert (appdata input){
                return input;
            }

            [maxvertexcount(3)]
            void geo(triangle float4 IN[3] : POSITION, inout TriangleStream<geoOut> triStream){
                geoOut o;
                o.positionCS = float4(0.5, 0, 0, 1);
                triStream.Append(o);
                o.positionCS = float4(-0.5, 0, 0, 1);
                triStream.Append(o);
                o.positionCS = float4(0, 1, 0, 1);
                triStream.Append(o);
                triStream.RestartStrip();
            }


            float4 frag (geoOut i) : SV_Target{
                return float4(1,0,0,1);
            }
            ENDHLSL
        }
    }
}
