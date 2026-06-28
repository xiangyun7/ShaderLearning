Shader "Tutorial/SSAO"
{
    Properties
    {
        [HideInInspector] _MainTex ("", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }
        LOD 100
        ZWrite Off ZTest Always Cull Off

        Pass
        {
            Name "0"
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"

            TEXTURE2D(_MainTex);SAMPLER(sampler_MainTex);
            float _Intensity;
            float _Radius;
            float _SampleCount;
            float _ShowAOOnly;


            struct appdata
            {
                uint vertexID : SV_VertexID;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            v2f vert(appdata input)
            {
                v2f o;
                o.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
                o.uv = GetFullScreenTriangleTexCoord(input.vertexID);
                return o;
            }

            float3 GetViewPosition(float2 uv){
                float rawDepth = SampleSceneDepth(uv);//根据屏幕uv进行深度纹理采样
                #if UNITY_REVERSED_Z
                    float depth = rawDepth;
                #else
                    float depth = lerp(UNITY_NEAR_CLIP_VALUE, 1, rawDepth);
                #endif//不同图形api适配

                //利用深度值、UV和逆视图投影矩阵UNITY_MATRIX_I_VP计算出世界空间坐标worldPos。
                float3 worldPos = ComputeWorldSpacePosition(uv,depth,UNITY_MATRIX_I_VP);
                //通过视图矩阵UNITY_MATRIX_V将世界空间坐标变换到视空间坐标viewPos并返回。
                float3 viewPos = mul(UNITY_MATRIX_V, float4(worldPos, 1.0)).xyz;
                return viewPos;
            }

            // 从 URP 相机法线纹理读取法线，并转换到视空间。
            // SampleSceneNormals 读到的是世界空间法线 normalWS；
            // 当前 SSAO 的 viewPos/samplePos 都在视空间，所以法线也要统一到视空间。
            float3 GetViewNormal(float2 uv)
            {
                float3 normalWS = SampleSceneNormals(uv);
                return normalize(mul((float3x3)UNITY_MATRIX_V, normalWS));
            }

            float3 GetSampleVector(uint index, float2 uv, float3 normal)
            {
                float angle = (index + 1.0) * 2.3999632;
                float2 offset = float2(cos(angle), sin(angle));
                float rand = frac(sin(dot(uv + index * 0.13, float2(12.9898, 78.233))) * 43758.5453);
                // 先在任意方向取 tangent，再投到切平面并归一化(施密特正交化)
                float3 tangent = offset.x * float3(1, 0, 0) + offset.y * float3(0, 1, 0);
                tangent = normalize(tangent - normal * dot(tangent, normal));
                // normal ⟂ tangent 且均为单位向量 → bitangent 自动为单位，无需再 normalize
                float3 bitangent = cross(normal, tangent);
                float3 dir = tangent * offset.x + bitangent * offset.y + normal * rand;
                return normalize(dir);
            }


            float SampleAO(float2 uv, float3 viewPos, float3 normal)
            {
                int count = (int)clamp(_SampleCount, 4, 128);
                float occlusion = 0.0;

                // XY 半径决定屏幕平面周围采多远，Z 半径稍小可以减轻过强的深度方向遮蔽。
                float3 randomScale = float3(_Radius, _Radius, _Radius * 0.5);

                UNITY_LOOP
                for (int i = 0; i < count; i++)
                {
                    // 1. 在当前像素的法线半球内取一个候选采样点。
                    float3 sampleDir = GetSampleVector(i, uv, normal);
                    float3 samplePos = viewPos + sampleDir * randomScale;

                    // 2. 把这个 3D 采样点投影回屏幕，得到它对应的 sampleUV。
                    float4 sampleCS = mul(UNITY_MATRIX_P, float4(samplePos, 1.0));
                    float2 sampleUV = (sampleCS.xy / sampleCS.w) * 0.5 + 0.5;
                    #if UNITY_UV_STARTS_AT_TOP
                    sampleUV.y = 1.0 - sampleUV.y;
                    #endif

                    // 采样点投影到屏幕外时，跳过这次采样。
                    if (sampleUV.x < 0 || sampleUV.x > 1 || sampleUV.y < 0 || sampleUV.y > 1)
                        continue;

                    // 3. 读取 sampleUV 处真实场景深度，并重建真实场景位置。
                    float3 sceneViewPos = GetViewPosition(sampleUV);

                    float centerEyeDepth = -viewPos.z;
                    float sampleEyeDepth = -samplePos.z;
                    float sceneEyeDepth = -sceneViewPos.z;

                    float rangeCheck = smoothstep(0, 1, _Radius / abs(centerEyeDepth - sceneEyeDepth + 1e-4));
                    float occluded = step(sceneEyeDepth, sampleEyeDepth - 0.002) * rangeCheck;
                    occlusion += occluded;
                }

                // 遮蔽次数越多，AO 越小；最后转成 0~1 的亮度系数。
                return 1.0 - (occlusion / count);
            }

            half4 frag (v2f i) : SV_Target
            {
                float2 uv = i.uv;
                float3 viewPos = GetViewPosition(uv);
                float3 normal = GetViewNormal(uv);

                // 计算 AO 并用 intensity 调整强度。
                // pow(ao, intensity)：intensity > 1 会让中间灰更暗。
                float ao = SampleAO(uv, viewPos, normal);
                ao = pow(saturate(ao), _Intensity);

                // Pass 0 输出的是灰度 AO 图，后面会继续模糊和合成。
                return half4(ao, ao, ao, 1);
            }
            ENDHLSL
        }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment BlurFrag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            TEXTURE2D_X(_BlitTexture);SAMPLER(sampler_LinearClamp);

            struct appdata
            {
                uint vertexID : SV_VertexID;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            v2f Vert(appdata input)
            {
                v2f o;
                o.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
                o.uv = GetFullScreenTriangleTexCoord(input.vertexID);
                return o;
            }

            float4 BlurFrag(v2f i) : SV_Target
            {
                 float2 uv = i.uv;

                // 水平模糊：每次只在 x 方向移动一个像素。
                float2 texel = float2(_ScreenParams.z, 0); // 1/width
                float centerDepth = SampleSceneDepth(uv);
                float ao = 0;
                float wSum = 0;
                // 5 tap 模糊核：-2, -1, 0, 1, 2。
                for (int x = -2; x <= 2; x++)
                {
                    float2 u = uv + texel * x;
                    float d = SampleSceneDepth(u);

                    // 深度越接近中心像素，权重越高。
                    // 这就是“深度加权/双边”模糊，能尽量保住物体边缘。
                    float w = exp(-abs(d - centerDepth) * 800.0);
                    ao += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, u).r * w;
                    wSum += w;
                }

                return float4(ao / max(wSum, 1e-4), 0, 0, 1);
            }
            ENDHLSL
        }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment BlurFrag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            TEXTURE2D_X(_BlitTexture);SAMPLER(sampler_LinearClamp);

            struct appdata
            {
                uint vertexID : SV_VertexID;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            v2f Vert(appdata input)
            {
                v2f o;
                o.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
                o.uv = GetFullScreenTriangleTexCoord(input.vertexID);
                return o;
            }
            float4 BlurFrag(v2f input) : SV_Target
            {
                float2 uv = input.uv;

                // 垂直模糊：只在 y 方向移动一个像素。
                float2 texel = float2(0, _ScreenParams.w);
                float centerDepth = SampleSceneDepth(uv);
                float ao = 0;
                float wSum = 0;

                for (int y = -2; y <= 2; y++)
                {
                    float2 u = uv + texel * y;
                    float d = SampleSceneDepth(u);
                    float w = exp(-abs(d - centerDepth) * 800.0);
                    ao += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, u).r * w;
                    wSum += w;
                }

                return float4(ao / max(wSum, 1e-4), 0, 0, 1);
            }
            ENDHLSL
        }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D_X(_BlitTexture);
            SAMPLER(sampler_LinearClamp);
            TEXTURE2D_X(_SSAOTexture);
            SAMPLER(sampler_SSAOTexture);

            float _ShowAOOnly;
            struct appdata
            {
                uint vertexID : SV_VertexID;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            v2f Vert(appdata input)
            {
                v2f o;
                o.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
                o.uv = GetFullScreenTriangleTexCoord(input.vertexID);
                return o;
            }

            half4 frag(v2f i) : SV_Target
            {
                float2 uv = i.uv;
                half3 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb;
                half ao = SAMPLE_TEXTURE2D_X(_SSAOTexture, sampler_SSAOTexture, uv).r;

                // 调试模式：只看 AO 灰度图，方便判断深度/半径/采样是否正常。
                if (_ShowAOOnly > 0.5)
                    return half4(ao, ao, ao, 1);

                // 最简单的合成方式：用 AO 作为乘法因子压暗环境光。
                // 真实项目中也可以只影响间接光/环境光，而不是直接乘最终颜色。
                return half4(color * ao, 1);
                //return half4(ao, ao, ao, 1);
            }
            ENDHLSL


        }

    }
}
