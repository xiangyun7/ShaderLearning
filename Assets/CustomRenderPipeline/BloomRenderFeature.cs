using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class BloomRenderFeature : ScriptableRendererFeature
{
    [Serializable]
    public class BloomSettings
    {
        public RenderPassEvent passEvent = RenderPassEvent.AfterRenderingTransparents;
        public Material bloomMaterial;
        public float bloomIntensity = 1.0f;
    }
    public BloomSettings settings = new BloomSettings();
    private BloomRenderPass bloomPass;


    public override void Create()
    {
        bloomPass = new BloomRenderPass(settings.passEvent);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (settings.bloomMaterial == null) return;
        // 不要对 Scene / 预览 / 反射探针 等相机跑 Bloom
        if (renderingData.cameraData.isSceneViewCamera) return;
        if (renderingData.cameraData.isPreviewCamera) return;

        bloomPass.Setup(renderer, settings.bloomMaterial, settings.bloomIntensity);
        renderer.EnqueuePass(bloomPass);
    }
}


