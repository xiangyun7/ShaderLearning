Shader "Tutorial/VolumeCloud"
{
    Properties
    {
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            //参数声明
            //包围盒参数
            float3 _CloudBoundsMin,_CloudBoundsMax;
            //raymarching参数
            float _RayStep,_DensityMultiplier;
            //噪声密度采样参数
            TEXTURE3D(_CloudNoiseMap); SAMPLER(sampler_CloudNoiseMap);
            float3 _CloudScale;
            float _NoiseTileSize;
            float _DensityThreshold, _DensityContrast;

            //——————————function mode—————————————————————
            //深度图重建世界坐标
            float3 ReconstructWorldPosition(float2 uv)
            {
                float rawDepth = SampleSceneDepth(uv);

            #if UNITY_REVERSED_Z
                float deviceDepth = rawDepth;
            #else
                float deviceDepth = lerp(UNITY_NEAR_CLIP_VALUE, 1.0, rawDepth);
            #endif

                return ComputeWorldSpacePosition(uv, deviceDepth, UNITY_MATRIX_I_VP);
            }
            //包围盒求交函数
            float2 RayBoxIntersection(float3 rayOrigin, float3 rayDir)
            {
                float3 t0 = (_CloudBoundsMin - rayOrigin) / rayDir;
                float3 t1 = (_CloudBoundsMax - rayOrigin) / rayDir;

                float3 tMin = min(t0, t1);
                float3 tMax = max(t0, t1);

                float tEnter = max(max(tMin.x, tMin.y), tMin.z);
                float tExit = min(min(tMax.x, tMax.y), tMax.z);

                if (tExit < 0.0 || tEnter > tExit)
                    return float2(-1.0, -1.0);

                tEnter = max(tEnter, 0.0);
                return float2(tEnter, tExit - tEnter);
            }
            //密度采样函数
            float SampleDensity(float3 rayPos)
            {
                float3 boundsSize = _CloudBoundsMax - _CloudBoundsMin;
                float3 uvw = (rayPos - _CloudBoundsMin) / boundsSize;

                if (any(uvw < 0.0) || any(uvw > 1.0))
                    return 0.0;

                float heightFade =
                    smoothstep(0.0, 0.15, uvw.y) *
                    (1.0 - smoothstep(0.75, 1.0, uvw.y));

                float3 noiseUVW = (rayPos - _CloudBoundsMin) / _NoiseTileSize;
                float noise = SAMPLE_TEXTURE3D(_CloudNoiseMap, sampler_CloudNoiseMap, noiseUVW * _CloudScale).r;
                float density = max(0.0, noise - _DensityThreshold) * _DensityContrast;

                return density * heightFade * _DensityMultiplier;
            }


            //ray marching步进函数
            float RayMarching(float3 rayStart, float3 rayDir, float rayLength)
            {
                float transmittance = 1.0;

                [loop]
                for (float rayDis = 0.0; rayDis < rayLength; rayDis += _RayStep)
                {
                    float stepSize = min(_RayStep, rayLength - rayDis);
                    float3 currPos = rayStart + rayDir * (rayDis + stepSize * 0.5);

                    float density = SampleDensity(currPos);
                    transmittance *= exp(-density * stepSize);

                    if (transmittance < 0.01)
                        break;
                }

                return 1.0 - transmittance;
            }

            //————————Shader mode————————————————————————————

            float4 frag(Varyings input) : SV_TARGET
            {
                float2 uv = input.texcoord;
                float3 sourceColor = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb;

                float3 worldPos = ReconstructWorldPosition(uv);
                float3 rayOrigin = _WorldSpaceCameraPos;
                float3 rayDir = normalize(worldPos - rayOrigin);

                float2 hitInfo = RayBoxIntersection(rayOrigin, rayDir);

                if (hitInfo.y <= 0.0)
                {
                    return float4(sourceColor, 1.0);
                }

                float sceneDistance = length(worldPos - rayOrigin);
                float rayLength = min(hitInfo.y, max(0.0, sceneDistance - hitInfo.x));

                if (rayLength <= 0.0)
                    return float4(sourceColor, 1.0);

                float3 rayStart = rayOrigin + rayDir * hitInfo.x;
                float cloudAlpha = RayMarching(rayStart, rayDir, rayLength);

                float3 cloudColor = float3(1, 1, 1);
                float3 finalColor = lerp(sourceColor, cloudColor, cloudAlpha);

                return float4(finalColor, 1.0);

            }
            ENDHLSL
        }
    }
}
