Shader "Tutorial/VolumeCloud"
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
            #pragma fragment CloudMapFrag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            //参数声明
            //包围盒参数
            float3 _CloudBoundsMin,_CloudBoundsMax;
            //raymarching参数
            float _RayStep,_DensityMultiplier;
            //噪声密度采样参数
            TEXTURE3D(_CloudNoiseMap); SAMPLER(sampler_CloudNoiseMap);//云噪声
            float3 _CloudScale;
            float _NoiseTileSize;
            float _DensityThreshold, _DensityContrast;
            float _DetailStrength;
            TEXTURE2D(_BlueNoiseMap); SAMPLER(sampler_BlueNoiseMap);//蓝噪声
            float4 _BlueNoiseMap_TexelSize;
            //边缘递减距离
            float _EdgeFadeDistance;
            //光照模型参数
            float _LightAbsorptionThroughCloud;
            float3 _LightTowardSunColor, _LightThroughCloudColor;
            float _LightAbsorptionTowardSun;
            float _DarknessThreshold;
            float _AmbientAbsorptionTowardTop, _AmbientStrength;
            float4 _PhaseParams;//相函数参数
            float _PhaseBlend;
            static const float CLOUD_PI = 3.14159265359;

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
                float edgeFadeDistance = max(_EdgeFadeDistance, 0.001);
                float distToEdgeX = min(rayPos.x - _CloudBoundsMin.x, _CloudBoundsMax.x - rayPos.x);
                float distToEdgeZ = min(rayPos.z - _CloudBoundsMin.z, _CloudBoundsMax.z - rayPos.z);
                float edgeFade = saturate(min(distToEdgeX, distToEdgeZ) / edgeFadeDistance);
                edgeFade = smoothstep(0.0, 1.0, edgeFade);



                float3 noiseUVW = (rayPos - _CloudBoundsMin) / _NoiseTileSize;
                float4 noiseData = SAMPLE_TEXTURE3D(_CloudNoiseMap, sampler_CloudNoiseMap, noiseUVW * _CloudScale);
                float baseShape = noiseData.r;//柏林噪声标记云的主体
                float detailNoise = noiseData.g;//细胞噪声侵蚀云的边缘增加细节

                float density = max(0.0, baseShape - _DensityThreshold) * _DensityContrast;
                float detailMask = 1.0 - saturate(density);
                detailMask = detailMask * detailMask * detailMask;

                density = max(0.0, density - detailNoise * _DetailStrength * detailMask);

                return density * heightFade * edgeFade * _DensityMultiplier;
                //return density * _DensityMultiplier;
            }
            //相函数计算
            float HGFunction(float cosTheta, float g)
            {
                float g2 = g * g;
                float denominator = pow(max(1.0 + g2 - 2.0 * g * cosTheta, 0.0001), 1.5);
                return (1.0 - g2) / (4.0 * CLOUD_PI * denominator);
            }
            float GetPhase(float cosTheta)
            {
                float forwardPhase = HGFunction(cosTheta, _PhaseParams.x);
                float backwardPhase = HGFunction(cosTheta, _PhaseParams.y);
                float phase = lerp(backwardPhase, forwardPhase, _PhaseBlend);

                return _PhaseParams.z + phase * _PhaseParams.w;
            }
            //光源方向raymarching函数
            float MarchToLight(float3 currPos)
            {
                Light mainLight = GetMainLight();
                float3 lightDir = normalize(mainLight.direction);

                float lightRayLength = RayBoxIntersection(currPos, lightDir).y;
                if (lightRayLength <= 0.0)
                    return 1.0;

                float lightStep = lightRayLength / 8.0;
                float totalDensity = 0.0;

                [loop]
                for (int i = 0; i < 8; i++)
                {
                    float3 samplePos = currPos + lightDir * (lightStep * (i + 0.5));
                    totalDensity += SampleDensity(samplePos) * lightStep;
                }

                float lightTransmittance = exp(-totalDensity * _LightAbsorptionTowardSun);
                return _DarknessThreshold + lightTransmittance * (1.0 - _DarknessThreshold);
            }
            //环境光采样
            float MarchAmbient(float3 currPos)
            {
                float ambientRayLength = max(0.0, _CloudBoundsMax.y - currPos.y);
                if (ambientRayLength <= 0.0)
                    return 1.0;

                float stepSize = ambientRayLength / 4.0;
                float totalDensity = 0.0;

                [loop]
                for (int i = 0; i < 4; i++)
                {
                    float3 samplePos = currPos + float3(0.0, 1.0, 0.0) * (stepSize * (i + 0.5));
                    totalDensity += SampleDensity(samplePos) * stepSize;
                }

                return exp(-totalDensity * _AmbientAbsorptionTowardTop);
            }


            //相机方向raymarching函数
            void RayMarching(float3 rayStart, float3 rayDir, float rayLength, float rayOffset, out float3 scattering, out float transmittance)
            {
                Light mainLight = GetMainLight();

                float cosTheta = dot(rayDir, normalize(mainLight.direction));
                float phase = GetPhase(cosTheta);

                scattering = 0.0;
                transmittance = 1.0;

                rayOffset = clamp(rayOffset, 0.0, _RayStep);

                [loop]
                for (float rayDis = rayOffset; rayDis < rayLength; rayDis += _RayStep)
                {
                    float stepSize = min(_RayStep, rayLength - rayDis);
                    float3 currPos = rayStart + rayDir * (rayDis + stepSize * 0.5);

                    float density = SampleDensity(currPos);
                    if (density <= 0.0)
                        continue;

                    float stepTransmittance = exp(-density * stepSize * _LightAbsorptionThroughCloud);
                    float stepAlpha = 1.0 - stepTransmittance;

                    float lightTransmittance = MarchToLight(currPos);
                    float ambientTransmittance = MarchAmbient(currPos);

                    float height01 = saturate((currPos.y - _CloudBoundsMin.y) / (_CloudBoundsMax.y - _CloudBoundsMin.y));
                    float topLight = lerp(0.5, 1.0, height01);

                    float3 directLight = mainLight.color * _LightTowardSunColor * phase * lightTransmittance;//光源方向采样
                    float3 ambientLight = mainLight.color * ambientTransmittance * topLight * _AmbientStrength;//环境光方向采样

                    scattering += transmittance * stepAlpha * (directLight + ambientLight);

                    transmittance *= stepTransmittance;

                    if (transmittance < 0.01)
                        break;
                }
            }

            //————————Shader mode————————————————————————————

            float4 CloudMapFrag(Varyings input) : SV_TARGET
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
                float rayLength = min(hitInfo.y, max(0.0, sceneDistance - hitInfo.x));

                if (rayLength <= 0.0)
                    return float4(0.0, 0.0, 0.0, 1.0);

                float3 rayStart = rayOrigin + rayDir * hitInfo.x;
                float3 scattering;
                float transmittance;

                float blueNoise = SampleBlueNoise(input.positionCS.xy);
                float rayOffset = blueNoise * _RayStep;
                RayMarching(rayStart, rayDir, rayLength, rayOffset, scattering, transmittance);

                float3 cloudScattering = scattering * _LightThroughCloudColor;

                return float4(cloudScattering, transmittance);
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

            TEXTURE2D_X(_VolumeCloudMap);

            float4 CompositeFrag(Varyings input) : SV_TARGET
            {
                float2 uv = input.texcoord;

                float3 sourceColor = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb;
                float4 cloudData = SAMPLE_TEXTURE2D_X(_VolumeCloudMap, sampler_LinearClamp, uv);

                float3 finalColor = sourceColor * cloudData.a + cloudData.rgb;

                return float4(finalColor, 1.0);
            }

            ENDHLSL
        }
    }
}
