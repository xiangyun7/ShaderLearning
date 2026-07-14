using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class VolumeFogRenderPass : ScriptableRenderPass
{
    public VolumeFogParams settings;
    private RTHandle tempColorTarget;
    private RTHandle volumeFogTarget;

    private const string TempColorName = "_TempVolumeFogColor"; 
    private const string VolumeFogName = "_VolumeFogMap";

    //shader属性
    private static readonly int FogBoundsMinId = Shader.PropertyToID("_FogBoundsMin");
    private static readonly int FogBoundsMaxId = Shader.PropertyToID("_FogBoundsMax");
    private static readonly int RayStepId = Shader.PropertyToID("_RayStep");
    private static readonly int VolumeFogMapId = Shader.PropertyToID("_VolumeFogMap");
    private static readonly int BlueNoiseMapId = Shader.PropertyToID("_BlueNoiseMap");

    private static readonly int BaseDensityId = Shader.PropertyToID("_BaseDensity");
    private static readonly int ExtinctionId = Shader.PropertyToID("_Extinction");
    private static readonly int ScatteringAlbedoId = Shader.PropertyToID("_ScatteringAlbedo");
    private static readonly int AmbientScatteringColorId = Shader.PropertyToID("_AmbientScatteringColor");
    private static readonly int AmbientScatteringStrengthId = Shader.PropertyToID("_AmbientScatteringStrength");
    private static readonly int TransmittanceCutoffId = Shader.PropertyToID("_TransmittanceCutoff");

    private static readonly int FogStartDistanceId = Shader.PropertyToID("_FogStartDistance");
    private static readonly int FogFullDensityDistanceId = Shader.PropertyToID("_FogFullDensityDistance");
    private static readonly int FogFullDensityHeightId = Shader.PropertyToID("_FogFullDensityHeight");
    private static readonly int FogTopHeightId = Shader.PropertyToID("_FogTopHeight");

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

        RenderTextureDescriptor fogDesc = colorDesc;

        int downsample = Mathf.Max(1, (int)settings.downsample);
        fogDesc.width = Mathf.Max(1, Mathf.CeilToInt(colorDesc.width / (float)downsample));
        fogDesc.height = Mathf.Max(1, Mathf.CeilToInt(colorDesc.height / (float)downsample));

        RenderingUtils.ReAllocateIfNeeded(
            ref volumeFogTarget,
            fogDesc,
            FilterMode.Bilinear,
            TextureWrapMode.Clamp,
            name: VolumeFogName);
    }
    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        Camera camera = renderingData.cameraData.camera;

        if (camera == null || renderingData.cameraData.cameraType != CameraType.Game)
            return;

        if (!camera.CompareTag("MainCamera"))
            return;

        if (settings == null || settings.fogMaterial == null)
            return;

        RTHandle cameraColorTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;

        if (tempColorTarget == null || volumeFogTarget == null)
            return;

        setMaterial();

        CommandBuffer cmd = CommandBufferPool.Get("VolumeFogRenderPass");
        //全局参数用于水面雾
        cmd.SetGlobalFloat(BaseDensityId, settings.fogMaterial.GetFloat(BaseDensityId));
        cmd.SetGlobalFloat(ExtinctionId, settings.fogMaterial.GetFloat(ExtinctionId));
        cmd.SetGlobalFloat(ScatteringAlbedoId, settings.fogMaterial.GetFloat(ScatteringAlbedoId));
        cmd.SetGlobalColor(AmbientScatteringColorId, settings.fogMaterial.GetColor(AmbientScatteringColorId));
        cmd.SetGlobalFloat(AmbientScatteringStrengthId, settings.fogMaterial.GetFloat(AmbientScatteringStrengthId));
        cmd.SetGlobalFloat(FogStartDistanceId, settings.fogMaterial.GetFloat(FogStartDistanceId));
        cmd.SetGlobalFloat(FogFullDensityDistanceId, settings.fogMaterial.GetFloat(FogFullDensityDistanceId));

        // Pass 0: 只计算体积云，输出 volumeCloudTarget
        Blitter.BlitCameraTexture(cmd, cameraColorTarget, volumeFogTarget, settings.fogMaterial, 0);


        // Pass 1: 读取相机颜色 + cloudMapForComposite，合成到 tempColorTarget
        cmd.SetGlobalTexture(VolumeFogMapId, volumeFogTarget.nameID);
        Blitter.BlitCameraTexture(cmd, cameraColorTarget, tempColorTarget, settings.fogMaterial, 1);

        // 写回相机颜色
        Blitter.BlitCameraTexture(cmd, tempColorTarget, cameraColorTarget);

        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }
    public void Dispose()
    {
        tempColorTarget?.Release();
        tempColorTarget = null;

        volumeFogTarget?.Release();
        volumeFogTarget = null;
    }
    //———————function mode—————————————
    public VolumeFogRenderPass(VolumeFogParams settings)
    {
        this.settings  = settings;
        settings.fogBoundsMin = settings.fogBoundsPos - settings.fogBoundsSize * 0.5f;
        settings.fogBoundsMax = settings.fogBoundsPos + settings.fogBoundsSize * 0.5f;

        //this.renderPassEvent = RenderPassEvent.AfterRenderingSkybox;
        this.renderPassEvent = RenderPassEvent.BeforeRenderingTransparents;
        ConfigureInput(ScriptableRenderPassInput.Depth);
    }
    public void setMaterial()
    {
        if (settings.blueNoiseMap != null)
            settings.fogMaterial.SetTexture(BlueNoiseMapId, settings.blueNoiseMap);

        settings.fogBoundsMin = settings.fogBoundsPos - settings.fogBoundsSize * 0.5f;
        settings.fogBoundsMax = settings.fogBoundsPos + settings.fogBoundsSize * 0.5f;

        float fogStartDistance = Mathf.Max(0.0f, settings.fogStartDistance);
        float fogFullDensityDistance = Mathf.Max(fogStartDistance + 0.001f, settings.fogFullDensityDistance);
        float fogFullDensityHeight = settings.fogFullDensityHeight;
        float fogTopHeight = Mathf.Max(fogFullDensityHeight + 0.001f, settings.fogTopHeight);

        settings.fogMaterial.SetVector(FogBoundsMinId, settings.fogBoundsMin);
        settings.fogMaterial.SetVector(FogBoundsMaxId, settings.fogBoundsMax);
        settings.fogMaterial.SetFloat(RayStepId, Mathf.Max(0.001f, settings.rayStep));
        settings.fogMaterial.SetFloat(BaseDensityId, Mathf.Max(0.0f, settings.baseDensity));
        settings.fogMaterial.SetFloat(ExtinctionId, Mathf.Max(0.0f, settings.extinction));
        settings.fogMaterial.SetFloat(ScatteringAlbedoId, Mathf.Clamp01(settings.scatteringAlbedo));
        settings.fogMaterial.SetColor(AmbientScatteringColorId, settings.ambientScatteringColor);
        settings.fogMaterial.SetFloat(AmbientScatteringStrengthId, Mathf.Max(0.0f, settings.ambientScatteringStrength));
        settings.fogMaterial.SetFloat(TransmittanceCutoffId, Mathf.Clamp(settings.transmittanceCutoff, 0.0001f, 0.1f));
        settings.fogMaterial.SetFloat(FogStartDistanceId, fogStartDistance);
        settings.fogMaterial.SetFloat(FogFullDensityDistanceId, fogFullDensityDistance);
        settings.fogMaterial.SetFloat(FogFullDensityHeightId, fogFullDensityHeight);
        settings.fogMaterial.SetFloat(FogTopHeightId, fogTopHeight);


    }
}
