Shader "Tutorial/Tessellation"
{
    Properties
    {
        _SubdivisionNum("SubdivisionNum",range(1,32)) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 4.6
            #pragma hull hull
            #pragma domain domain
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            float _SubdivisionNum;


            struct appdata
            {
                float4 position : POSITION;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
            };

            struct TessFactors{
                float Edge[3] : SV_TessFactor;        // 三角形三条边的细分因子
                float Inside : SV_InsideTessFactor;   // 内部细分因子
            };


            appdata vert (appdata input)
            {
                return input;
            }

            [domain("tri")]
            [outputcontrolpoints(3)]
            [outputtopology("triangle_cw")]
            [partitioning("integer")]
            [patchconstantfunc("subdivisionRule")]
            appdata hull(InputPatch<appdata,3> patch,uint id : SV_OutputControlPointID){
                return patch[id];
            }
            TessFactors subdivisionRule(InputPatch<appdata, 3> patch){
                TessFactors f;
                f.Edge[0] = f.Edge[1] = f.Edge[2] = _SubdivisionNum;  // 三边
                f.Inside = _SubdivisionNum;                            // 内部
                return f;
            }


            [domain("tri")]
            v2f domain(OutputPatch<appdata,3> patch, 
                       float3 bary: SV_DomainLocation, 
                       TessFactors tessFactor){
                appdata newVertex;
                newVertex.position = patch[0].position*bary.x+
                                     patch[1].position*bary.y+
                                     patch[2].position*bary.z;
                
                v2f output;
                output.positionCS = TransformObjectToHClip(newVertex.position);
                return output;
            }


            float4 frag (v2f i) : SV_Target
            {
                float4 col = float4(1,1,1,1);
                return col;
            }
            ENDHLSL
        }
    }
}
