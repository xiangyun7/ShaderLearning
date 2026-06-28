using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class SSAORenderFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class SSAOSettings
    {
        // SSAO 用到的 Shader。Shader 名字要和 SSAO.shader 顶部的 Shader "SSAO/SSAO" 对上。
        [Tooltip("SSAO.shader，留空则自动查找 SSAO/SSAO")]
        public Shader ssaoShader;

        [Header("AO Quality")]
        // AO 强度。值越大，遮蔽区域越黑；值太大容易脏。
        [Range(0f, 2f)]
        public float intensity = 1f;

        // 采样半径。半径越大，会参考更远的几何体；太大会产生大块阴影或漏光。
        [Range(0.01f, 1.5f)]
        public float radius = 0.3f;

        // 每个像素周围采多少个点来估算遮蔽。越高越稳定，但越耗性能。
        [Range(4, 128)]
        public int sampleCount = 16;

        // 降采样：AO 可以用低分辨率算，再模糊放大，通常性价比更高。
        [Tooltip("0=全分辨率 1=1/2 2=1/4")]
        [Range(0, 2)]
        public int downsample = 1;

        [Header("Debug")]
        // 开启后只显示灰度 AO 图，方便检查 SSAO 是否算对。
        public bool showAOOnly = false;
    }
    public SSAOSettings settings = new SSAOSettings();
    SSAORenderPass m_SSAOPass;
    /// <inheritdoc/>
    public override void Create()
    {
        if (settings.ssaoShader == null) settings.ssaoShader = Shader.Find("Tutorial/SSAO");
        if (settings.ssaoShader != null)
            m_SSAOPass = new SSAORenderPass(settings);
    }

    // Here you can inject one or multiple render passes in the renderer.
    // This method is called when setting up the renderer once per-camera.
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (m_SSAOPass == null) return;
        CameraType camType = renderingData.cameraData.cameraType;//只对主摄像机和后处理摄像机addpass
        if (camType != CameraType.Game && camType != CameraType.Reflection) return;
        if (settings.ssaoShader == null) return;

        renderer.EnqueuePass(m_SSAOPass);
    }

    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        if (m_SSAOPass == null)
            return;

        CameraType camType = renderingData.cameraData.cameraType;
        if (camType != CameraType.Game && camType != CameraType.Reflection)
            return;

        if (settings == null || settings.ssaoShader == null)
            return;

        m_SSAOPass.Setup(renderer.cameraColorTargetHandle);
    }

    protected override void Dispose(bool disposing)
    {
        m_SSAOPass?.Dispose();
    }
}


