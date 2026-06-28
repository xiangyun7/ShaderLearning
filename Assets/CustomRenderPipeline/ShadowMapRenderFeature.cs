using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class ShadowMapRenderFeature : ScriptableRendererFeature
{
    public Shader resolveShader;
    [Range(0.0f, 0.2f)]
    public float bias = 0.0005f;
    Material material;
    ShadowMapPass pass;
    Camera lightCamera;

    public override void Create()
    {
        if(resolveShader != null)
            material = CoreUtils.CreateEngineMaterial(resolveShader);
        pass = new ShadowMapPass();

    }
    Camera GetLightCamera()
    {
        if (lightCamera != null)
            return lightCamera;

        GameObject go = GameObject.Find("LightCamera");
        if (go == null)
            return null;

        lightCamera = go.GetComponent<Camera>();
        return lightCamera;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        Camera cam = GetLightCamera();
        if (material == null || cam == null || cam.targetTexture == null)
            return;
        if (renderingData.cameraData.cameraType != CameraType.Game)
            return;
        if (renderingData.cameraData.camera == cam)
            return;

        renderer.EnqueuePass(pass);
    }

    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        Camera cam = GetLightCamera();
        if (material == null || cam == null || cam.targetTexture == null)
            return;
        if (renderingData.cameraData.cameraType != CameraType.Game)
            return;
        if (renderingData.cameraData.camera == cam)
            return;
        // 这里不要读取 renderer.cameraColorTargetHandle。
        // URP 会在具体 ScriptableRenderPass 执行期间创建/管理相机颜色目标，
        // 在 RendererFeature 里直接访问会触发 “cameraColorTargetHandle 只能在 Pass 作用域内调用” 的警告。
        // 所以这里只传光源相机、光源深度图和材质，主相机颜色目标放到 ShadowMapPass.Execute 里获取。
        pass.Setup(
            cam,                      // 光源相机
            cam.targetTexture,        // 光源相机 depth RT
            material,
            bias);


    }
    protected override void Dispose(bool disposing)
    {
        pass?.Dispose();
        CoreUtils.Destroy(material);
    }
}


