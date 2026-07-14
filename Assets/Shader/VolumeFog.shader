Shader "Tutorial/VolumeFog"
{
    Properties
    {
        _BlueNoiseMap("Blue Noise Map", 2D) = "gray" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FogMapFrag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            
            //参数声明
            //包围盒参数
            float3 _FogBoundsMin,_FogBoundsMax;
            //raymarching参数
            float _RayStep;
            // 体积雾介质
            float _BaseDensity;
            float _Extinction;
            float _ScatteringAlbedo;
            float4 _AmbientScatteringColor;
            float _AmbientScatteringStrength;
            float _TransmittanceCutoff;
            float _FogStartDistance,_FogFullDensityDistance;
            float _FogFullDensityHeight,_FogTopHeight;
            //蓝噪声参数
            TEXTURE2D(_BlueNoiseMap); SAMPLER(sampler_BlueNoiseMap);//蓝噪声
            float4 _BlueNoiseMap_TexelSize;
            //——————————function mode—————————————————————
            //蓝噪声采样偏移函数
            float SampleBlueNoise(float2 pixelCoord)
            {
                float2 noiseUV = frac(pixelCoord / 256.0);
                return SAMPLE_TEXTURE2D(_BlueNoiseMap, sampler_BlueNoiseMap, noiseUV).a;
            }
            
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
                float3 t0 = (_FogBoundsMin - rayOrigin) / rayDir;
                float3 t1 = (_FogBoundsMax - rayOrigin) / rayDir;

                float3 tMin = min(t0, t1);
                float3 tMax = max(t0, t1);

                float tEnter = max(max(tMin.x, tMin.y), tMin.z);
                float tExit = min(min(tMax.x, tMax.y), tMax.z);

                if (tExit < 0.0 || tEnter > tExit)
                    return float2(-1.0, -1.0);

                tEnter = max(tEnter, 0.0);
                return float2(tEnter, tExit - tEnter);
            }
            //体积雾密度采样函数
            float SampleFogDensity(float3 worldPos)
            {
                if (any(worldPos < _FogBoundsMin) || any(worldPos > _FogBoundsMax))
                {
                    return 0.0;
                }

                float fogStartDistance = max(_FogStartDistance, 0.0);
                float fogFullDensityDistance = max( _FogFullDensityDistance, fogStartDistance + 0.001);
                
                float distanceToCamera = distance(_WorldSpaceCameraPos, worldPos);
                float distanceWeight = smoothstep( fogStartDistance, fogFullDensityDistance, distanceToCamera);
                float fogTopHeight = max(_FogTopHeight, _FogFullDensityHeight + 0.001);
                float heightWeight = 1.0 - smoothstep(_FogFullDensityHeight, fogTopHeight, worldPos.y);

                return max(_BaseDensity, 0.0) * distanceWeight * heightWeight;
            }
            //相机方向raymarching函数
            void RayMarching(float3 rayStart,float3 rayDir, float rayLength, out float3 scattering, out float transmittance)
            {
                scattering = 0.0;
                transmittance = 1.0;

                float safeRayStep = max(_RayStep, 0.001);
                float cutoff = clamp( _TransmittanceCutoff, 0.0001, 0.1);

                float3 incidentLight =
                    max(_AmbientScatteringColor.rgb, 0.0)
                    * max(_AmbientScatteringStrength, 0.0);

                [loop]
                for (float rayDistance = 0.0; rayDistance < rayLength; rayDistance += safeRayStep)
                {
                    float stepSize = min(safeRayStep, rayLength - rayDistance);

                    float3 samplePos = rayStart+ rayDir * (rayDistance + stepSize * 0.5);

                    float density = SampleFogDensity(samplePos);

                    if (density <= 0.0)
                        continue;

                    float extinctionDensity = density * max(_Extinction, 0.0);

                    float stepTransmittance = exp(-extinctionDensity * stepSize);

                    float stepAlpha = 1.0 - stepTransmittance;

                    scattering +=
                        transmittance
                        * stepAlpha
                        * incidentLight
                        * saturate(_ScatteringAlbedo);

                    transmittance *= stepTransmittance;
                    if (transmittance <= cutoff)
                        break;
                }
                transmittance = saturate(transmittance);
            }

            //————————Shader mode————————————————————————————

            float4 FogMapFrag(Varyings input) : SV_TARGET
            {
                float2 uv = input.texcoord;
                
                float3 worldPos = ReconstructWorldPosition(uv);
                float3 rayOrigin = _WorldSpaceCameraPos;
                float3 rayDir = normalize(worldPos - rayOrigin);

                float2 hitInfo = RayBoxIntersection(rayOrigin, rayDir);

                if (hitInfo.y <= 0.0)
                {
                    return float4(0.0, 0.0, 0.0, 1.0);
                }

                float sceneDistance = length(worldPos - rayOrigin);

                float boxEnter = hitInfo.x;
                float boxExit = hitInfo.x + hitInfo.y;
                float fogStartDistance = max(_FogStartDistance, 0.0);

                float marchStart = max(boxEnter, fogStartDistance);
                float marchEnd = min(boxExit, sceneDistance);
                float marchLength = marchEnd - marchStart;

                if (marchLength <= 0.0)
                    return float4(0.0, 0.0, 0.0, 1.0);
                float3 rayStart = rayOrigin + rayDir * marchStart;

                float3 scattering;
                float transmittance;

                RayMarching(rayStart, rayDir, marchLength, scattering, transmittance);

                return float4(scattering, transmittance);
            }
            ENDHLSL
        }
        Pass
        {
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment CompositeFrag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D_X(_VolumeFogMap);

            float4 CompositeFrag(Varyings input) : SV_TARGET
            {
                float2 uv = input.texcoord;

                float3 sourceColor = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb;
                float4 fogData = SAMPLE_TEXTURE2D_X(_VolumeFogMap,sampler_LinearClamp,uv);

                float3 finalColor = sourceColor * fogData.a + fogData.rgb;

                return float4(finalColor, 1.0);
            }

            ENDHLSL
        }
    }
}
