using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

class BloomRenderPass : ScriptableRenderPass
{
    private Material bloomMaterial;
    private float intensity;
    private ScriptableRenderer renderer;

    private int tempRT1Id;
    private int tempRT2Id;
    private static readonly int BloomTexId = Shader.PropertyToID("_BloomTex");

    const string k_TempRT1 = "_BloomTempRT1";
    const string k_TempRT2 = "_BloomTempRT2";
    public BloomRenderPass(RenderPassEvent evt)
    {
        renderPassEvent = evt;
        tempRT1Id = Shader.PropertyToID(k_TempRT1);
        tempRT2Id = Shader.PropertyToID(k_TempRT2);
    }

    public void Setup(ScriptableRenderer renderer, Material mat, float intensity)
    {
        this.renderer = renderer;
        this.bloomMaterial = mat;
        this.intensity = intensity;
    }
    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        // 声明本 Pass 会读/写相机颜色目标
        ConfigureInput(ScriptableRenderPassInput.Color);
    }
    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        if (bloomMaterial == null || renderer == null) return;
        RTHandle source = renderer.cameraColorTargetHandle;

        CommandBuffer cmd = CommandBufferPool.Get("BloomRenderPass");

        RenderTextureDescriptor desc = renderingData.cameraData.cameraTargetDescriptor;
        desc.depthBufferBits = 0;

        cmd.GetTemporaryRT(tempRT1Id, desc, FilterMode.Bilinear);
        cmd.GetTemporaryRT(tempRT2Id, desc, FilterMode.Bilinear);
        //bloomMaterial.SetFloat("_Intensity", intensity);//和材质中的intensity关联

        cmd.Blit(source.nameID, tempRT1Id, bloomMaterial, 0);//pass0预过滤

        cmd.Blit(tempRT1Id, tempRT2Id, bloomMaterial, 1);//Pass 1：横向模糊 RT1 → RT2

        cmd.Blit(tempRT2Id, tempRT1Id, bloomMaterial, 2);// Pass 2：纵向模糊 RT2 → RT1

        cmd.SetGlobalTexture(BloomTexId, new RenderTargetIdentifier(tempRT1Id));
        cmd.Blit(source.nameID, tempRT2Id, bloomMaterial, 3);// Pass 3：合成：原图 + 光晕 → RT2
        cmd.Blit(tempRT2Id, source.nameID);//写回相机

        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }

    public override void OnCameraCleanup(CommandBuffer cmd)
    {
        cmd.ReleaseTemporaryRT(tempRT1Id);
        cmd.ReleaseTemporaryRT(tempRT2Id);
    }
}