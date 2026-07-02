Shader "Tutorial/BilateralFilter"
{
    Properties
    {
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100
        ZTest Always
        ZWrite Off
        Cull Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            //参数

            int _FilterRadius;
            float _FilterSigma, _FilterRangeSigma, _FilterStrength;


            //————function mode——————————————
            //高斯滤波
            float GaussianWeight2D(float x, float y, float sigma)
            {
                float sigma2 = max(sigma * sigma, 0.0001);
                float dist2 = x * x + y * y;
                return exp(-dist2 / (2.0 * sigma2));
            }
            //相似度过滤函数
            float GaussianWeight1D(float value, float sigma)
            {
                float sigma2 = max(sigma * sigma, 0.0001);
                return exp(-(value * value) / (2.0 * sigma2));
            }
            float CloudGuide(float4 cloudData)
            {
                float luminance = dot(cloudData.rgb, float3(0.2126, 0.7152, 0.0722));
                // 把很弱的云散射亮度放大成可用的 guide。
                return saturate(luminance * 5.0);
            }


            //——————shader mode——————————————————
            float4 Frag(Varyings input) : SV_TARGET
            {
                float2 uv = input.texcoord;

                int radius = clamp(_FilterRadius, 0, 6);
                float sigma = max(_FilterSigma, 0.001);
                float rangeSigma = max(_FilterRangeSigma, 0.001);

                if (radius <= 0)
                {
                    return SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv);
                }

                float2 texelSize = rcp(max(_BlitTextureSize, float2(1.0, 1.0)));

                float4 centerCloud = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv);
                float centerGuide = CloudGuide(centerCloud);

                float weightSum = 0.0;
                float4 colorSum = 0.0;

                [loop]
                for (int y = -radius; y <= radius; y++)
                {
                    [loop]
                    for (int x = -radius; x <= radius; x++)
                    {
                        float2 sampleUV = uv + texelSize * float2(x, y);
                        float4 sampleCloud = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, sampleUV);

                        float spatialWeight = GaussianWeight2D((float)x, (float)y, sigma);

                        float sampleGuide = CloudGuide(sampleCloud);
                        float guideDiff = centerGuide - sampleGuide;
                        float rangeWeight = GaussianWeight1D(guideDiff, rangeSigma);

                        float weight = spatialWeight * rangeWeight;

                        colorSum += sampleCloud * weight;
                        weightSum += weight;
                    }
                }

                float4 filteredCloud = colorSum / max(weightSum, 0.0001);
                return lerp(centerCloud, filteredCloud, saturate(_FilterStrength));
            }
            

            ENDHLSL
        }
    }
}
