using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

class SSAORenderPass : ScriptableRenderPass
{
    readonly SSAORenderFeature.SSAOSettings m_Settings;
    Material m_Material;

    RTHandle m_AOHandle;
    RTHandle m_BlurTempHandle;
    RTHandle m_CameraColorTarget;
    RTHandle m_ColorTempHandle;

    // Shader.PropertyToID 可以避免每帧用字符串查找 Shader 属性，属于常见性能小优化。
    static readonly int s_Intensity = Shader.PropertyToID("_Intensity");
    static readonly int s_Radius = Shader.PropertyToID("_Radius");
    static readonly int s_SampleCount = Shader.PropertyToID("_SampleCount");
    static readonly int s_ShowAOOnly = Shader.PropertyToID("_ShowAOOnly");
    static readonly int s_SSAOTexture = Shader.PropertyToID("_SSAOTexture");

    const string k_AOTextureName = "_SSAOTexture";
    const string k_BlurTempName = "_SSAOBlurTemp";

    public SSAORenderPass(SSAORenderFeature.SSAOSettings settings)
    {
        m_Settings = settings;
        renderPassEvent = RenderPassEvent.BeforeRenderingTransparents;
        //读取法线和深度纹理
        ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);
        //创建材质
        if (settings.ssaoShader != null)
            m_Material = CoreUtils.CreateEngineMaterial(settings.ssaoShader);
    }

    public void Setup(RTHandle cameraColorTarget)
    {
        m_CameraColorTarget = cameraColorTarget;
    }

    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        if (m_Material == null) return;
        PushMaterialProperties();// 把 Inspector 参数推到 Shader，确保运行时调参能立刻生效。

        RenderTextureDescriptor desc = renderingData.cameraData.cameraTargetDescriptor;
        desc.depthBufferBits = 0;
        desc.msaaSamples = 1;
        desc.colorFormat = RenderTextureFormat.R8; // R8 = 单通道 8 bit，存 AO 足够省。
        // downsample=1 时 div=2，宽高各除以 2。进行降采样
        int div = 1 << Mathf.Clamp(m_Settings.downsample, 0, 2);
        desc.width = Mathf.Max(1, desc.width / div);
        desc.height = Mathf.Max(1, desc.height / div);
        // ReAllocateIfNeeded 会在尺寸或格式变化时重建 RT，否则复用旧 RT，避免每帧重复申请。
        RenderingUtils.ReAllocateIfNeeded(
            ref m_AOHandle, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: k_AOTextureName);

        RenderingUtils.ReAllocateIfNeeded(
            ref m_BlurTempHandle, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: k_BlurTempName);
        RenderTextureDescriptor colorDesc = renderingData.cameraData.cameraTargetDescriptor;
        colorDesc.depthBufferBits = 0;
        colorDesc.msaaSamples = 1;
        RenderingUtils.ReAllocateIfNeeded(
            ref m_ColorTempHandle,
            colorDesc,
            FilterMode.Bilinear,
            TextureWrapMode.Clamp,
            name: "_SSAOCameraColorTemp");
        //看不懂的优化部分
    }
    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        if (m_Material == null || m_AOHandle == null || m_CameraColorTarget == null)
            return;

        CommandBuffer cmd = CommandBufferPool.Get("SSAO");
        //pass0 从相机源图像计算ao写入ao纹理
        Blitter.BlitCameraTexture(cmd, m_CameraColorTarget, m_AOHandle, m_Material, 0);

        // Pass 1：横向双边模糊。
        // 双边模糊会参考深度差，让 AO 不容易跨过物体边缘糊到背景上。
        Blitter.BlitCameraTexture(cmd, m_AOHandle, m_BlurTempHandle, m_Material, 1);

        // Pass 2：纵向双边模糊。
        // 横向 + 纵向分两次做，比一次二维大核模糊更省。
        Blitter.BlitCameraTexture(cmd, m_BlurTempHandle, m_AOHandle, m_Material, 2);

        // Pass 3：把模糊后的 AO 贴图传给合成 pass，然后把颜色乘上 AO。
        Blitter.BlitCameraTexture(cmd, m_CameraColorTarget, m_ColorTempHandle);//中转颜色纹理避免指代冲突
        m_Material.SetTexture(s_SSAOTexture, m_AOHandle);
        Blitter.BlitCameraTexture(cmd, m_ColorTempHandle, m_CameraColorTarget, m_Material, 3);

        // 执行并释放 CommandBuffer。CommandBufferPool 可以减少 GC 和临时对象开销。
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }
    public void Dispose()
    {
        m_AOHandle?.Release();
        m_BlurTempHandle?.Release();
        CoreUtils.Destroy(m_Material);
    }

    void PushMaterialProperties()
    {
        m_Material.SetFloat(s_Intensity, m_Settings.intensity);
        m_Material.SetFloat(s_Radius, m_Settings.radius);
        m_Material.SetFloat(s_SampleCount, m_Settings.sampleCount);
        m_Material.SetFloat(s_ShowAOOnly, m_Settings.showAOOnly ? 1f : 0f);
    }
}