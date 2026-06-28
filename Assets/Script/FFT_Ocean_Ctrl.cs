using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using UnityEngine;
using UnityEngine.Rendering;

public class FFT_Ocean_Ctrl : MonoBehaviour
{
    //纹理声明
    public RenderTexture pp_Texture, UpdateTexture; 
    public RenderTexture FourierTexture, _DisplacementTexture, _SlopeTexture;
    public ComputeShader fftOceanCompute;

    //参数声明
    public int resolution = 1024;
    private int threadGroupsX, threadGroupsY;
    public float lengthScale = 200f;
    public float gravity = 9.81f;
    public float depth = 10f;
    private float LowCutOff = 0.0001f;
    private float HighCutOff = 9000.0f;
    public int seed = 28;
    public float _RepeatTime = 200f;
    public float Speed = 0.5f;//波随时间的运动速度
    //波浪泡沫参数声明
    public Vector2 WaveSharp = new Vector2(0.4f, 0.4f);
    [Range(-1.0f, 1.0f)]
    public float FoamBias = 0.2f;
    [Range(-0.0f, 4.0f)]
    public float FoamPower = 1.5f;
    [Range(0.0f, 1.0f)]
    public float FoamAdd = 0.1f;
    [Range(0.0f, 1.0f)]
    public float FoamDecayRate = 0.05f;

    //声明核函数
    private int CS_Pinpu;
    private int CS_GongEPinpu;
    private int CS_Update;
    private int CS_HorizontalIFFT;
    private int CS_VerticalIFFT;
    private int CS_AssembleTextures;



    private struct JONSWAP_ComputeSettings
    {
        public float scale;
        public float angle;
        public float alpha;
        public float peakOmega;
        public float gamma;
    }//jonswap初始频谱给computeshader读的数据

    [System.Serializable]
    public struct JONSWAP_DisplaySettings
    {
        [Range(0, 5)] public float scale;
        public float windSpeed;
        [Range(0, 360)] public float windDirection;
        public float fetch;
        public float peakEnhancement;
    }//jonswap给人调整的参数
    private ComputeBuffer JonswapBuffer;
    [Header("JONSWAP Spectrum")]
    public JONSWAP_DisplaySettings displaySpectrum;
    //水体材质声明
    [Header("Water Material")]
    public Material waterMaterial;
    //[Space(10)]
    //public float _SpecularStrength = 3;
    //public float _SunGlintStrength = 20;
    //public float _SpecularPower = 32;
    //public float _SunGlintPower = 1024;
    [Header("ScatterParams")]
    public Color _ScatterColor = new Color(0.0f, 0.67f, 1.0f, 1.0f);
    public Color _ScatterPeakColor = new Color(0.0f, 0.67f, 1.0f, 1.0f);
    public float _HeightStrength = 1.0f;
    public float _ScatterStrength = 0.1f;
    public float _WavePeakScatterStrength = 2.0f;
    public float _AmbientDensity = 0.2f;
    [Header("FoamParams")]
    public Color _FoamColor = new Color(1, 1, 1, 1);
    public float _EdgeFoamPower = 32;
    [Space(10)]
    public float _FoamRoughness = 0.2f;
    public float _Roughness = 0.1f;
    private static readonly int DisplacementTextureID = Shader.PropertyToID("_DisplacementTexture");
    private static readonly int SlopeTextureID = Shader.PropertyToID("_SlopeTexture");
    private static readonly int OceanLengthScaleID = Shader.PropertyToID("_OceanLengthScale");



    private void Reset()
    {
        displaySpectrum.scale = 0.4f;
        displaySpectrum.windSpeed = 1200.0f;
        displaySpectrum.windDirection = 130.0f;
        displaySpectrum.fetch = 600.0f;
        displaySpectrum.peakEnhancement = 5.0f;
    }
    void OnEnable()
    {
        if (fftOceanCompute == null)
        {
            Debug.LogError("FFT Ocean Compute Shader is missing.", this);
            return;
        }

        threadGroupsX = Mathf.CeilToInt(resolution / 8.0f);
        threadGroupsY = Mathf.CeilToInt(resolution / 8.0f);

        CS_Pinpu = fftOceanCompute.FindKernel("CS_Pinpu");
        CS_GongEPinpu = fftOceanCompute.FindKernel("CS_GongEPinpu");
        CS_Update = fftOceanCompute.FindKernel("CS_Update");
        CS_HorizontalIFFT = fftOceanCompute.FindKernel("CS_HorizontalIFFT");
        CS_VerticalIFFT = fftOceanCompute.FindKernel("CS_VerticalIFFT");
        CS_AssembleTextures = fftOceanCompute.FindKernel("CS_AssembleTextures");

        pp_Texture = CreateRenderTexArray(resolution, resolution, 1,RenderTextureFormat.ARGBFloat, false);
        UpdateTexture = CreateRenderTexArray(resolution, resolution,2, RenderTextureFormat.ARGBFloat, false);
        FourierTexture = CreateRenderTexArray(resolution, resolution,2, RenderTextureFormat.ARGBFloat, false);
        _DisplacementTexture = CreateRenderTexArray(resolution, resolution,1, RenderTextureFormat.ARGBFloat, false);
        _SlopeTexture = CreateRenderTexArray(resolution, resolution,1, RenderTextureFormat.ARGBFloat, false);
        
        SetCompParam();
        CreateJonswapBuffer();
        UploadJonswapBuffer();
        BindWaterMaterialValue();
        

    }

    void Update()
    {
        if (waterMaterial != null)
        {
            waterMaterial.SetFloat(OceanLengthScaleID, lengthScale);
        }
        SetCompParam();
        BindWaterMaterialValue();
        RunKernel();
    }

    void OnDisable()
    {
        if (JonswapBuffer != null)
        {
            JonswapBuffer.Release();
            JonswapBuffer = null;
        }

        ReleaseRT(ref pp_Texture);
        ReleaseRT(ref UpdateTexture);
        ReleaseRT(ref FourierTexture);
        ReleaseRT(ref _DisplacementTexture);
        ReleaseRT(ref _SlopeTexture);

        if (waterMaterial != null)
        {
            waterMaterial.SetTexture(DisplacementTextureID, null);
            waterMaterial.SetTexture(SlopeTextureID, null);
        }
    }

    //————————————function mode————————————————
    private void BindWaterMaterialValue()
    {
        if (waterMaterial == null)
        {
            Debug.LogError("Water material is missing.", this);
            return;
        }
        waterMaterial.SetTexture(DisplacementTextureID, _DisplacementTexture);
        waterMaterial.SetTexture(SlopeTextureID, _SlopeTexture);
        waterMaterial.SetFloat(OceanLengthScaleID, lengthScale);
        //waterMaterial.SetFloat("_SpecularStrength", _SpecularStrength);
        //waterMaterial.SetFloat("_SunGlintStrength", _SunGlintStrength);
        //waterMaterial.SetFloat("_SpecularPower", _SpecularPower);
        //waterMaterial.SetFloat("_SunGlintPower", _SunGlintPower);
        waterMaterial.SetFloat("_EdgeFoamPower", _EdgeFoamPower);
        waterMaterial.SetFloat("_HeightStrength", _HeightStrength);
        waterMaterial.SetFloat("_WavePeakScatterStrength", _WavePeakScatterStrength);
        waterMaterial.SetFloat("_AmbientDensity", _AmbientDensity);
        waterMaterial.SetFloat("_ScatterStrength", _ScatterStrength);
        waterMaterial.SetFloat("_Roughness", _Roughness);
        waterMaterial.SetFloat("_FoamRoughness", _FoamRoughness);
        waterMaterial.SetColor("_ScatterPeakColor", _ScatterPeakColor);
        waterMaterial.SetColor("_ScatterColor", _ScatterColor);
        waterMaterial.SetColor("_FoamColor", _FoamColor);
    }
    RenderTexture CreateRenderTexArray(int width, int height, int depth, RenderTextureFormat format, bool mips)
    {
        RenderTexture rt = new RenderTexture(width, height, 0, format, RenderTextureReadWrite.Linear);
        rt.filterMode = FilterMode.Bilinear;
        rt.wrapMode = TextureWrapMode.Repeat;
        rt.enableRandomWrite = true;
        rt.volumeDepth = depth;
        rt.useMipMap = mips;
        rt.autoGenerateMips = false;
        rt.anisoLevel = 1;
        rt.dimension = TextureDimension.Tex2DArray;
        rt.Create();

        return rt;
    }
    void SetCompParam()
    {
        fftOceanCompute.SetInt("_Resolution", resolution);
        fftOceanCompute.SetFloat("_LengthScale", lengthScale);
        fftOceanCompute.SetFloat("_Gravity", gravity);
        fftOceanCompute.SetFloat("_Depth", depth);
        fftOceanCompute.SetFloat("_LowCutOff", LowCutOff);
        fftOceanCompute.SetFloat("_HighCutOff", HighCutOff);
        fftOceanCompute.SetInt("_Seed", seed);
        fftOceanCompute.SetFloat("_RepeatTime", _RepeatTime);
        fftOceanCompute.SetFloat("_FrameTime", Time.time * Speed);

        fftOceanCompute.SetVector("_WaveSharp", WaveSharp);
        fftOceanCompute.SetFloat("_FoamBias", FoamBias);
        fftOceanCompute.SetFloat("_FoamPower", FoamPower);
        fftOceanCompute.SetFloat("_FoamAdd", FoamAdd);
        fftOceanCompute.SetFloat("_FoamDecayRate", FoamDecayRate);

    }
    private JONSWAP_ComputeSettings CreateJonswapComputeSettings(JONSWAP_DisplaySettings display)
    {
        JONSWAP_ComputeSettings compute = new JONSWAP_ComputeSettings();

        compute.scale = display.scale;
        compute.angle = display.windDirection * Mathf.Deg2Rad;
        compute.alpha = JonswapAlpha(display.fetch, display.windSpeed);
        compute.peakOmega = JonswapPeakFrequency(display.fetch, display.windSpeed);
        compute.gamma = display.peakEnhancement;

        return compute;
    }

    private float JonswapAlpha(float fetchValue, float windSpeedValue)
    {
        float safeWindSpeed = Mathf.Max(0.01f, windSpeedValue);
        float value = gravity * fetchValue / (safeWindSpeed * safeWindSpeed);
        return 0.076f * Mathf.Pow(value, -0.22f);
    }

    private float JonswapPeakFrequency(float fetchValue, float windSpeedValue)
    {
        float safeWindSpeed = Mathf.Max(0.01f, windSpeedValue);
        float value = safeWindSpeed * fetchValue / (gravity * gravity);
        return 22.0f * Mathf.Pow(value, -0.33f);
    }
    private void CreateJonswapBuffer()
    {
        if (JonswapBuffer != null)
        {
            JonswapBuffer.Release();
        }

        int stride = Marshal.SizeOf(typeof(JONSWAP_ComputeSettings));
        JonswapBuffer = new ComputeBuffer(1, stride);
    }
    private void UploadJonswapBuffer()
    {
        JONSWAP_ComputeSettings[] data = new JONSWAP_ComputeSettings[1];
        data[0] = CreateJonswapComputeSettings(displaySpectrum);
        JonswapBuffer.SetData(data);
        fftOceanCompute.SetBuffer(CS_Pinpu, "_JonswapParameters", JonswapBuffer);
    }
    private void RunKernel()
    {
        //初始化频谱
        fftOceanCompute.SetTexture(CS_Pinpu, "pp_Texture", pp_Texture);
        fftOceanCompute.Dispatch(CS_Pinpu, threadGroupsX, threadGroupsY, 1);
        //共轭频谱
        fftOceanCompute.SetTexture(CS_GongEPinpu, "pp_Texture", pp_Texture);
        fftOceanCompute.Dispatch(CS_GongEPinpu, threadGroupsX, threadGroupsY, 1);
        //更新频谱
        fftOceanCompute.SetTexture(CS_Update, "pp_Texture", pp_Texture);
        fftOceanCompute.SetTexture(CS_Update, "UpdateTexture", UpdateTexture);
        fftOceanCompute.Dispatch(CS_Update, threadGroupsX, threadGroupsY, 1);
        //ifft（水平，竖直）
        Graphics.CopyTexture(UpdateTexture, FourierTexture);
        fftOceanCompute.SetTexture(CS_HorizontalIFFT, "FourierTexture", FourierTexture);
        fftOceanCompute.Dispatch(CS_HorizontalIFFT, 1, resolution, 1);
        fftOceanCompute.SetTexture(CS_VerticalIFFT, "FourierTexture", FourierTexture);
        fftOceanCompute.Dispatch(CS_VerticalIFFT, 1, resolution, 1);
        //整理波谱
        fftOceanCompute.SetTexture(CS_AssembleTextures, "FourierTexture", FourierTexture);
        fftOceanCompute.SetTexture(CS_AssembleTextures, "_DisplacementTexture", _DisplacementTexture);
        fftOceanCompute.SetTexture(CS_AssembleTextures, "_SlopeTexture", _SlopeTexture);
        fftOceanCompute.Dispatch(CS_AssembleTextures, threadGroupsX, threadGroupsY, 1);

    }
    private void ReleaseRT(ref RenderTexture rt)
    {
        if (rt == null)
            return;

        rt.Release();
        Destroy(rt);
        rt = null;
    }
}

