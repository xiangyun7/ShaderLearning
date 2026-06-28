using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

class ShadowMapPass : ScriptableRenderPass
{
    static readonly int LightDepthTexId = Shader.PropertyToID("_LightDepthTexture");
    static readonly int LightViewProjId = Shader.PropertyToID("_LightViewProjectionMatrix");
    static readonly int LightDepthParamsId = Shader.PropertyToID("_LightDepthParams");
    public float bias;

    RTHandle tempColor;


    Camera lightCamera;
    Texture lightDepthTexture;
    Material material;


    public ShadowMapPass()
    {
        renderPassEvent = RenderPassEvent.BeforeRenderingTransparents;
        ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Color);
    }

    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        var desc = renderingData.cameraData.cameraTargetDescriptor;
        desc.depthBufferBits = 0;
        desc.msaaSamples = 1;

        RenderingUtils.ReAllocateIfNeeded(
            ref tempColor,
            desc,
            FilterMode.Bilinear,
            TextureWrapMode.Clamp,
            name: "_ShadowMapResolveTemp");
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        if (material == null || lightCamera == null || lightDepthTexture == null)
            return;
        CommandBuffer cmd = CommandBufferPool.Get("Shadow Map Resolve");

        Matrix4x4 lightView = lightCamera.worldToCameraMatrix;
        Matrix4x4 lightProj = GL.GetGPUProjectionMatrix(lightCamera.projectionMatrix, true);
        Matrix4x4 lightViewProj = lightProj * lightView;
        material.SetTexture(LightDepthTexId, lightDepthTexture);
        material.SetMatrix(LightViewProjId, lightViewProj);
        material.SetVector(LightDepthParamsId, new Vector4(lightCamera.nearClipPlane, lightCamera.farClipPlane, bias, 0));

        // cameraColorTargetHandle 只能在 ScriptableRenderPass 的生命周期里访问。
        // 这里处在 Execute 内部，当前相机颜色目标已经由 URP 创建好，访问是安全的。
        RTHandle cameraColorTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;

        Blitter.BlitCameraTexture(cmd, cameraColorTarget, tempColor);
        Blitter.BlitCameraTexture(cmd, tempColor, cameraColorTarget, material, 0);

        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }

    public void Dispose()
    {
        tempColor?.Release();
    }

    public void Setup(Camera lightCamera, Texture lightDepthTexture, Material material,float bias)
    {
        // 不在 Setup 里保存主相机颜色目标，因为 SetupRenderPasses 属于 RendererFeature 阶段，
        // 此时直接读取 cameraColorTargetHandle 会触发 URP 生命周期警告。
        this.lightCamera = lightCamera;
        this.lightDepthTexture = lightDepthTexture;
        this.material = material;
        this.bias = bias;
    }

}
