using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

//降采样倍率
public enum VolumeFogDownsample
{
    Full = 1,
    Half = 2,
    Quarter = 4,
    Eighth = 8,
    shiliuth = 16,
    sanshierth = 32
}

[System.Serializable]
public class VolumeFogParams
{
    [Header("渲染资源")]
    public Material fogMaterial;

    [Header("包围盒")]
    public Vector3 fogBoundsPos = new Vector3(0f, -10f, 0f);
    public Vector3 fogBoundsSize = new Vector3(1000f, 50f, 1000f);
    public Vector3 fogBoundsMin;
    public Vector3 fogBoundsMax;

    [Header("体积雾介质")]
    [Min(0.0f)] public float baseDensity = 0.002f;
    [Min(0.0f)] public float extinction = 1.0f;
    [Range(0.0f, 1.0f)] public float scatteringAlbedo = 0.9f;
    [ColorUsage(false, true)] public Color ambientScatteringColor = new Color(0.65f, 0.72f, 0.78f, 1.0f);
    [Min(0.0f)] public float ambientScatteringStrength = 1.0f;

    [Header("距离分布")]
    [Min(0.0f)] public float fogStartDistance = 120.0f;
    [Min(0.0f)] public float fogFullDensityDistance = 350.0f;
    [Header("高度分布")]
    public float fogFullDensityHeight = 5.0f;
    public float fogTopHeight = 40.0f;

    [Header("Ray Marching")]
    [Range(0.1f, 100.0f)] public float rayStep = 10.0f;
    [Range(0.0001f, 0.1f)] public float transmittanceCutoff = 0.01f;
    public VolumeFogDownsample downsample = VolumeFogDownsample.Full;

    [Header("采样抖动")]
    public Texture2D blueNoiseMap;
}
public class VolumeFogRenderFeature : ScriptableRendererFeature
{
    private VolumeFogRenderPass fogRenderPass;
    public VolumeFogParams settings = new VolumeFogParams();

    public override void Create()
    {
        fogRenderPass?.Dispose();
        fogRenderPass = new VolumeFogRenderPass(settings);
    }
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        Camera camera = renderingData.cameraData.camera;
        if (camera == null || renderingData.cameraData.cameraType != CameraType.Game)
            return;
        if (!camera.CompareTag("MainCamera"))
            return;
        if (settings.fogMaterial == null)
            return;
        renderer.EnqueuePass(fogRenderPass);
    }
    protected override void Dispose(bool disposing)
    {
        fogRenderPass?.Dispose();
        fogRenderPass = null;
    }
    //———————function mode—————————————

}


