using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class CloudRenderPass : ScriptableRenderPass
{
    public VolumeCloudParams settings;
    private RTHandle tempColorTarget;
    private const string TempColorName = "_TempVolumeCloudColor";

    //shader属性
    private static readonly int CloudBoundsMinId = Shader.PropertyToID("_CloudBoundsMin");
    private static readonly int CloudBoundsMaxId = Shader.PropertyToID("_CloudBoundsMax");
    private static readonly int RayStepId = Shader.PropertyToID("_RayStep");
    private static readonly int DensityMultiplierId = Shader.PropertyToID("_DensityMultiplier");
    private static readonly int CloudNoiseMapId = Shader.PropertyToID("_CloudNoiseMap");
    private static readonly int CloudScaleId = Shader.PropertyToID("_CloudScale");
    private static readonly int NoiseTileSizeId = Shader.PropertyToID("_NoiseTileSize");
    private static readonly int DensityThresholdId = Shader.PropertyToID("_DensityThreshold");
    private static readonly int DensityContrastId = Shader.PropertyToID("_DensityContrast");
    private static readonly int DetailStrengthId = Shader.PropertyToID("_DetailStrength");
    private static readonly int EdgeFadeDistanceId = Shader.PropertyToID("_EdgeFadeDistance");
    private static readonly int LightAbsorptionThroughCloudId = Shader.PropertyToID("_LightAbsorptionThroughCloud");
    private static readonly int LightThroughCloudColorId = Shader.PropertyToID("_LightThroughCloudColor");
    private static readonly int PhaseParamsId = Shader.PropertyToID("_PhaseParams");
    private static readonly int PhaseBlendId = Shader.PropertyToID("_PhaseBlend");
    private static readonly int LightAbsorptionTowardSunId = Shader.PropertyToID("_LightAbsorptionTowardSun");
    private static readonly int DarknessThresholdId = Shader.PropertyToID("_DarknessThreshold");



    //—————————生命周期函数——————————————————
    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        RenderTextureDescriptor desc = renderingData.cameraData.cameraTargetDescriptor;
        desc.depthBufferBits = 0;
        desc.msaaSamples = 1;

        RenderingUtils.ReAllocateIfNeeded(
            ref tempColorTarget,
            desc,
            FilterMode.Bilinear,
            TextureWrapMode.Clamp,
            name: TempColorName);
    }
    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        Camera camera = renderingData.cameraData.camera;

        if (camera == null || renderingData.cameraData.cameraType != CameraType.Game)
            return;

        if (!camera.CompareTag("MainCamera"))
            return;

        if (settings == null || settings.cloudMaterial == null)
            return;

        RTHandle cameraColorTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;

        if (cameraColorTarget == null)
            return;

        setMaterial();

        CommandBuffer cmd = CommandBufferPool.Get("CloudRenderPass");

        Blitter.BlitCameraTexture(cmd, cameraColorTarget, tempColorTarget, settings.cloudMaterial, 0);
        Blitter.BlitCameraTexture(cmd, tempColorTarget, cameraColorTarget);

        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }
    public void Dispose()
    {
        tempColorTarget?.Release();
        tempColorTarget = null;
    }
    //———————function mode—————————————
    public CloudRenderPass(VolumeCloudParams settings)
    {
        this.settings  = settings;
        settings.cloudBoundsMin = settings.cloudBoundsPos - settings.cloudBoundsSize * 0.5f;
        settings.cloudBoundsMax = settings.cloudBoundsPos + settings.cloudBoundsSize * 0.5f;

        this.renderPassEvent = RenderPassEvent.AfterRenderingSkybox;
        ConfigureInput(ScriptableRenderPassInput.Depth);
    }
    public void setMaterial()
    {
        if (settings.cloudNoiseMap != null)
            settings.cloudMaterial.SetTexture(CloudNoiseMapId, settings.cloudNoiseMap);

        settings.cloudMaterial.SetVector(CloudScaleId, settings.cloudScale);
        settings.cloudMaterial.SetFloat(DensityThresholdId, settings.densityThreshold);
        settings.cloudMaterial.SetFloat(DensityContrastId, settings.densityContrast);
        settings.cloudMaterial.SetFloat(DetailStrengthId, settings.detailStrength);
        settings.cloudMaterial.SetFloat(EdgeFadeDistanceId, Mathf.Max(0.001f, settings.edgeFadeDistance));

        settings.cloudBoundsMin = settings.cloudBoundsPos - settings.cloudBoundsSize * 0.5f;
        settings.cloudBoundsMax = settings.cloudBoundsPos + settings.cloudBoundsSize * 0.5f;

        settings.cloudMaterial.SetVector(CloudBoundsMinId, settings.cloudBoundsMin);
        settings.cloudMaterial.SetVector(CloudBoundsMaxId, settings.cloudBoundsMax);
        settings.cloudMaterial.SetFloat(RayStepId, settings.rayStep);
        settings.cloudMaterial.SetFloat(DensityMultiplierId, settings.densityMultiplier);
        settings.cloudMaterial.SetFloat(NoiseTileSizeId, Mathf.Max(0.001f, settings.noiseTileSize));
        settings.cloudMaterial.SetFloat(LightAbsorptionThroughCloudId, settings.lightAbsorptionThroughCloud);
        settings.cloudMaterial.SetColor(LightThroughCloudColorId, settings.lightThroughCloudColor);
        settings.cloudMaterial.SetFloat(LightAbsorptionTowardSunId, settings.lightAbsorptionTowardSun);
        settings.cloudMaterial.SetFloat(DarknessThresholdId, settings.darknessThreshold);
        settings.cloudMaterial.SetVector(PhaseParamsId, settings.phaseParams);
        settings.cloudMaterial.SetFloat(PhaseBlendId, settings.phaseBlend);
    }
}
