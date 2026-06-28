using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteAlways]
public class LightBind : MonoBehaviour
{
    [Tooltip("拖入场景里的 Directional Light")]
    public Light directionalLight;

    [Tooltip("是否同步方向光旋转")]
    public bool syncRotation = true;

    void Reset()
    {
        // 第一次挂脚本时，自动尝试绑定场景 Lighting 里的 Sun。
        directionalLight = RenderSettings.sun;
    }

    void OnValidate()
    {
        SyncToLight();
    }

    void LateUpdate()
    {
        SyncToLight();
    }

    void SyncToLight()
    {
        if (!syncRotation)
            return;

        if (directionalLight == null)
            directionalLight = RenderSettings.sun;

        if (directionalLight == null || directionalLight.type != LightType.Directional)
            return;

        // 让 LightCamera 的世界旋转和方向光一致。
        transform.rotation = directionalLight.transform.rotation;
    }
}