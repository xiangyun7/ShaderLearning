using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

//降采样倍率
public enum VolumeCloudDownsample
{
    Full = 1,
    Half = 2,
    Quarter = 4,
    Eighth = 8,
    shiliuth = 16,
    sanshierth = 32
}

[System.Serializable]
public class VolumeCloudParams
{
    [Header("渲染资源")]
    public Material cloudMaterial;
    [Header("光照模型")]
    [Range(0.0f, 5.0f)]
    public float lightAbsorptionThroughCloud = 1.0f;//控制云内部散射率
    [Range(0.0f, 5.0f)]
    public float lightAbsorptionTowardSun = 1.0f;//控制光源方向采样散射率
    [Range(0.0f, 5.0f)]
    public float ambientAbsorptionTowardTop = 0.5f;
    [Range(0.0f, 2.0f)]
    public float ambientStrength = 0.35f;
    [Range(0.0f, 1.0f)]
    public float darknessThreshold = 0.2f;
    public Color lightTowardSunColor = Color.white;
    public Color lightThroughCloudColor = Color.white;
    public Vector4 phaseParams = new Vector4(0.6f, -0.2f, 0.35f, 3.0f);
    [Range(0.0f, 1.0f)]
    public float phaseBlend = 0.7f;//相函数混合比例(前向和后向混合)

    [Header("包围盒")]
    public Vector3 cloudBoundsPos = new Vector3(0f, 150f, 0f);
    public Vector3 cloudBoundsSize = new Vector3(1000f, 100f, 1000f);
    public Vector3 cloudBoundsMin;
    public Vector3 cloudBoundsMax;
    [Header("体积云中间图")]
    public VolumeCloudDownsample volumeCloudDownsample = VolumeCloudDownsample.Full;
    [Header("采样抖动")]
    public Texture2D blueNoiseMap;
    [Header("Ray Marching 调试")]
    [Range(0.1f, 100.0f)]
    public float rayStep = 10.0f;
    [Range(0.0f, 0.1f)]
    public float densityMultiplier = 0.004f;
    [Header("噪声密度采样")]
    public Texture3D cloudNoiseMap;
    public Vector3 cloudScale = new Vector3(1.0f, 1.0f, 1.0f);
    [Range(10.0f, 5000.0f)]
    public float noiseTileSize = 500.0f;
    [Range(0.0f, 1.0f)]
    public float densityThreshold = 0.45f;//密度出现云的阈值
    [Range(1.0f, 20.0f)]
    public float densityContrast = 4.0f;
    [Range(0.0f, 10f)]
    public float detailStrength = 0.5f;
    [Header("边缘衰减")]
    [Range(0.0f, 5000.0f)]
    public float edgeFadeDistance = 1000.0f;
    [Header("体积云滤波")]
    public Material cloudFilterMaterial;
    [Range(0, 6)]
    public int filterRadius = 1;
    [Range(0.1f, 10.0f)]
    public float filterSigma = 1.0f;
    [Range(0.01f, 1.0f)]
    public float filterRangeSigma = 0.15f;
    [Range(0.0f, 1.0f)]
    public float filterStrength = 0.5f;

}
public class CloudRenderFeature : ScriptableRendererFeature
{
    CloudRenderPass CloudRenderPass;
    public VolumeCloudParams settings = new VolumeCloudParams();

    public override void Create()
    {
        CloudRenderPass?.Dispose();
        CloudRenderPass = new CloudRenderPass(settings);
    }
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        Camera camera = renderingData.cameraData.camera;
        if (camera == null || renderingData.cameraData.cameraType != CameraType.Game)
            return;
        if (!camera.CompareTag("MainCamera"))
            return;
        if (settings.cloudMaterial == null)
            return;
        renderer.EnqueuePass(CloudRenderPass);
    }
    protected override void Dispose(bool disposing)
    {
        CloudRenderPass?.Dispose();
        CloudRenderPass = null;
    }
    //———————function mode—————————————

}


