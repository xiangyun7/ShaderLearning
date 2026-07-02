using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class CloudRenderPass : ScriptableRenderPass
{
    public VolumeCloudParams settings;
    private RTHandle tempColorTarget;
    private RTHandle volumeCloudTarget;
    private RTHandle filteredCloudTarget;
    

    private const string TempColorName = "_TempVolumeCloudColor";
    private const string VolumeCloudName = "_VolumeCloudMap";
    private const string FilteredCloudName = "_FilteredVolumeCloudMap";

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
    private static readonly int LightTowardSunColorId = Shader.PropertyToID("_LightTowardSunColor");
    private static readonly int LightThroughCloudColorId = Shader.PropertyToID("_LightThroughCloudColor");
    private static readonly int PhaseParamsId = Shader.PropertyToID("_PhaseParams");
    private static readonly int PhaseBlendId = Shader.PropertyToID("_PhaseBlend");
    private static readonly int LightAbsorptionTowardSunId = Shader.PropertyToID("_LightAbsorptionTowardSun");
    private static readonly int DarknessThresholdId = Shader.PropertyToID("_DarknessThreshold");
    private static readonly int AmbientAbsorptionTowardTopId = Shader.PropertyToID("_AmbientAbsorptionTowardTop");
    private static readonly int AmbientStrengthId = Shader.PropertyToID("_AmbientStrength");
    private static readonly int VolumeCloudMapId = Shader.PropertyToID("_VolumeCloudMap");
    private static readonly int BlueNoiseMapId = Shader.PropertyToID("_BlueNoiseMap");
    private static readonly int FilterRadiusId = Shader.PropertyToID("_FilterRadius");
    private static readonly int FilterSigmaId = Shader.PropertyToID("_FilterSigma");
    private static readonly int FilterRangeSigmaId = Shader.PropertyToID("_FilterRangeSigma");
    private static readonly int FilterStrengthId = Shader.PropertyToID("_FilterStrength");


    //—————————生命周期函数——————————————————
    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        RenderTextureDescriptor colorDesc = renderingData.cameraData.cameraTargetDescriptor;
        colorDesc.depthBufferBits = 0;
        colorDesc.msaaSamples = 1;

        RenderingUtils.ReAllocateIfNeeded(
            ref tempColorTarget,
            colorDesc,
            FilterMode.Bilinear,
            TextureWrapMode.Clamp,
            name: TempColorName);

        RenderTextureDescriptor cloudDesc = colorDesc;

        int downsample = Mathf.Max(1, (int)settings.volumeCloudDownsample);
        cloudDesc.width = Mathf.Max(1, Mathf.CeilToInt(colorDesc.width / (float)downsample));
        cloudDesc.height = Mathf.Max(1, Mathf.CeilToInt(colorDesc.height / (float)downsample));

        RenderingUtils.ReAllocateIfNeeded(
            ref volumeCloudTarget,
            cloudDesc,
            FilterMode.Bilinear,
            TextureWrapMode.Clamp,
            name: VolumeCloudName);

        RenderingUtils.ReAllocateIfNeeded(
            ref filteredCloudTarget,
            cloudDesc,
            FilterMode.Bilinear,
            TextureWrapMode.Clamp,
            name: FilteredCloudName);
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

        if (tempColorTarget == null || volumeCloudTarget == null)
            return;

        setMaterial();

        CommandBuffer cmd = CommandBufferPool.Get("CloudRenderPass");

        // Pass 0: 只计算体积云，输出 volumeCloudTarget
        Blitter.BlitCameraTexture(cmd, cameraColorTarget, volumeCloudTarget, settings.cloudMaterial, 0);

        //pass:filter对云贴图进行双边滤波
        RTHandle cloudMapForComposite = volumeCloudTarget;

        if (settings.cloudFilterMaterial != null && filteredCloudTarget != null)
        {
            settings.cloudFilterMaterial.SetInt(FilterRadiusId, settings.filterRadius);
            settings.cloudFilterMaterial.SetFloat(FilterSigmaId, Mathf.Max(0.001f, settings.filterSigma));
            settings.cloudFilterMaterial.SetFloat(FilterRangeSigmaId, Mathf.Max(0.001f, settings.filterRangeSigma));
            settings.cloudFilterMaterial.SetFloat(FilterStrengthId, settings.filterStrength);

            Blitter.BlitCameraTexture(cmd, volumeCloudTarget, filteredCloudTarget, settings.cloudFilterMaterial, 0);
            cloudMapForComposite = filteredCloudTarget;
        }


        // Pass 1: 读取相机颜色 + cloudMapForComposite，合成到 tempColorTarget
        cmd.SetGlobalTexture(VolumeCloudMapId, cloudMapForComposite.nameID);
        Blitter.BlitCameraTexture(cmd, cameraColorTarget, tempColorTarget, settings.cloudMaterial, 1);

        // 写回相机颜色
        Blitter.BlitCameraTexture(cmd, tempColorTarget, cameraColorTarget);

        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }
    public void Dispose()
    {
        tempColorTarget?.Release();
        tempColorTarget = null;

        volumeCloudTarget?.Release();
        volumeCloudTarget = null;

        filteredCloudTarget?.Release();
        filteredCloudTarget = null;
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
        if (settings.blueNoiseMap != null)
            settings.cloudMaterial.SetTexture(BlueNoiseMapId, settings.blueNoiseMap);
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
        settings.cloudMaterial.SetColor(LightTowardSunColorId, settings.lightTowardSunColor);
        settings.cloudMaterial.SetColor(LightThroughCloudColorId, settings.lightThroughCloudColor);
        settings.cloudMaterial.SetFloat(LightAbsorptionTowardSunId, settings.lightAbsorptionTowardSun);
        settings.cloudMaterial.SetFloat(DarknessThresholdId, settings.darknessThreshold);
        settings.cloudMaterial.SetFloat(AmbientAbsorptionTowardTopId, settings.ambientAbsorptionTowardTop);
        settings.cloudMaterial.SetFloat(AmbientStrengthId, settings.ambientStrength);
        settings.cloudMaterial.SetVector(PhaseParamsId, settings.phaseParams);
        settings.cloudMaterial.SetFloat(PhaseBlendId, settings.phaseBlend);
    }
}
