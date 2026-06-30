using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[System.Serializable]
public class VolumeCloudParams
{
    [Header("渲染资源")]
    public Material cloudMaterial;
    [Header("包围盒")]
    public Vector3 cloudBoundsPos = new Vector3(0f, 150f, 0f);
    public Vector3 cloudBoundsSize = new Vector3(1000f, 100f, 1000f);
    public Vector3 cloudBoundsMin;
    public Vector3 cloudBoundsMax;
    [Header("Ray Marching 调试")]
    [Range(1.0f, 50.0f)]
    public float rayStep = 10.0f;
    [Range(0.0f, 0.02f)]
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


}
public class CloudRenderFeature : ScriptableRendererFeature
{
    CloudRenderPass CloudRenderPass;
    public VolumeCloudParams settings = new VolumeCloudParams();

    public override void Create()
    {
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
    }
    //———————function mode—————————————

}


