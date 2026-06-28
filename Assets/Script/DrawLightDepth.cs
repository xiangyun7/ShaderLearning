using UnityEngine;

[ExecuteAlways]
public class DrawLightDepth : MonoBehaviour
{
    public Camera lightCamera;
    public int shadowSize = 2048;

    RenderTexture depthRT;
    public Shader lightDepthShader;
    void OnEnable()
    {
        EnsureDepthTexture();
    }

    void OnValidate()
    {
        EnsureDepthTexture();
    }

    void Update()
    {
        EnsureDepthTexture();
    }

    void OnDisable()
    {
        if (lightCamera != null && lightCamera.targetTexture == depthRT)
            lightCamera.targetTexture = null;

        if (depthRT != null)
        {
            depthRT.Release();
            DestroyImmediate(depthRT);
            depthRT = null;
        }
    }

    void EnsureDepthTexture()
    {
        if (lightCamera == null)
            lightCamera = GetComponent<Camera>();

        if (lightCamera == null)
            return;

        int size = Mathf.Max(1, shadowSize);

        if (depthRT == null || depthRT.width != size || depthRT.height != size)
        {
            if (depthRT != null)
            {
                depthRT.Release();
                DestroyImmediate(depthRT);
            }

            depthRT = new RenderTexture(size, size, 24, RenderTextureFormat.Depth);
            depthRT.name = "_LightCameraDepthTexture";
            depthRT.filterMode = FilterMode.Point;
            depthRT.wrapMode = TextureWrapMode.Clamp;
            depthRT.Create();
        }

        lightCamera.targetTexture = depthRT;
        lightCamera.orthographic = true;
        lightCamera.depth = -10;
        lightCamera.enabled = true;
    }
}