using UnityEngine; // 使用 Unity 的基础类型：MonoBehaviour、Camera、RenderTexture、Matrix4x4 等。
using UnityEngine.Rendering; // 使用 SRP 渲染回调：RenderPipelineManager、ScriptableRenderContext。
using UnityEngine.Rendering.Universal; // 使用 URP 的单相机手动渲染接口：UniversalRenderPipeline.RenderSingleCamera。

public class PlanarWaterReflection : MonoBehaviour // 定义一个挂在水面平面上的平面反射脚本。
{
    [Header("Camera")] // 在 Inspector 中给相机相关参数分组。
    public Camera mainCamera; // 主相机槽；把玩家视角相机或当前 Game Camera 拖进来。

    [Header("Reflection Texture")] // 在 Inspector 中给反射纹理相关参数分组。
    public RenderTexture reflectionTexture; // 可选：外部指定反射 RT；不指定时脚本会自动创建。
    [Range(0.1f, 1.0f)] public float textureScale = 0.5f; // 自动创建 RT 时使用的分辨率比例，0.5 表示半分辨率。
    public string globalTextureName = "_PlanarReflectionTex"; // 传给 Shader 的全局纹理名。

    [Header("Culling")] // 在 Inspector 中给剔除相关参数分组。
    public LayerMask reflectionCullingMask = ~0; // 反射相机要渲染哪些层；默认渲染全部层。
    public bool excludeWaterObjectLayer = true; // 是否从反射相机中剔除当前水面物体所在层。

    [Header("Clip Plane")] // 在 Inspector 中给裁剪平面相关参数分组。
    [Range(0.001f, 0.1f)]
    public float clipPlaneOffset = 0.05f; // 裁剪平面沿水面法线轻微偏移，减少水面附近的闪烁。
    public bool flipClipPlane = false; // 如果发现裁剪方向反了，可以勾选这个反转裁剪面方向。

    [Header("Debug")] // 在 Inspector 中给调试相关参数分组。
    public bool disablePixelLights = true; // 渲染反射时可临时关闭像素光，降低第一版性能成本。

    private Camera reflectionCamera; // 脚本内部创建和维护的反射相机。
    private RenderTexture runtimeReflectionTexture; // 脚本内部实际使用的反射 RT。
    private bool ownsRuntimeTexture; // 标记 runtimeReflectionTexture 是否由脚本创建，便于释放。
    private bool isRenderingReflection; // 防止反射渲染递归或重复进入。
    private int globalTextureId; // 缓存 Shader 全局纹理属性 ID，避免每帧字符串查找。

    private void OnEnable() // 组件启用时执行。
    {
        globalTextureId = Shader.PropertyToID(globalTextureName); // 把全局纹理名转换成更高效的整数 ID。
        RenderPipelineManager.beginCameraRendering += OnBeginCameraRendering; // 注册 URP/HDRP 单个相机渲染前回调。
    }

    private void OnDisable() // 组件禁用时执行。
    {
        RenderPipelineManager.beginCameraRendering -= OnBeginCameraRendering; // 取消注册，避免对象销毁后回调空引用。
        ReleaseRuntimeTexture(); // 释放脚本自己创建的反射 RT。
        DestroyReflectionCamera(); // 销毁脚本自己创建的反射相机。
    }

    private void OnValidate() // Inspector 参数变化时执行，仅用于保持参数合理。
    {
        textureScale = Mathf.Clamp(textureScale, 0.1f, 1.0f); // 限制自动 RT 分辨率比例，避免误填无效值。
        clipPlaneOffset = Mathf.Max(0.0f, clipPlaneOffset); // 裁剪偏移不允许小于 0。
    }

    private void OnBeginCameraRendering(ScriptableRenderContext context, Camera currentCamera) // 每个相机开始渲染前被 URP 调用。
    {
        if (!enabled) return; // 如果组件被禁用，直接跳过。
        if (isRenderingReflection) return; // 如果正在渲染反射，跳过，防止递归。
        if (currentCamera == null) return; // 如果传入相机为空，直接跳过。

        Camera sourceCamera = mainCamera != null ? mainCamera : Camera.main; // 优先使用 Inspector 指定主相机，否则尝试 Camera.main。
        if (sourceCamera == null) return; // 没有主相机时无法计算镜像视角，直接跳过。
        if (currentCamera != sourceCamera) return; // 只为指定主相机生成反射，避免 SceneView 或其它相机重复触发。

        EnsureReflectionCamera(); // 确保反射相机已创建。
        EnsureReflectionTexture(sourceCamera); // 确保反射 RT 已创建且尺寸匹配。

        if (reflectionCamera == null) return; // 如果反射相机创建失败，跳过。
        if (runtimeReflectionTexture == null) return; // 如果反射 RT 创建失败，跳过。

        isRenderingReflection = true; // 标记进入反射渲染流程。

        int oldPixelLightCount = QualitySettings.pixelLightCount; // 记录原来的像素光数量。
        bool oldInvertCulling = GL.invertCulling; // 记录原来的全局三角面剔除反转状态。

        if (disablePixelLights) QualitySettings.pixelLightCount = 0; // 第一版反射可关闭像素光，减少反射相机成本。

        GL.invertCulling = !oldInvertCulling; // 镜像矩阵会改变坐标系手性，因此需要反转正反面剔除。

        UpdateReflectionCamera(sourceCamera); // 根据主相机和当前水面更新反射相机的矩阵、裁剪、RT 等。

        // 方案 A：当前代码运行在 beginCameraRendering 回调内部，此时 URP 正在渲染主相机。
        // 在这个回调里调用 SubmitRenderRequest 会触发 SRP 递归渲染错误，因此这里使用教程里的旧接口。
        // RenderSingleCamera 在高版本 URP 中会产生 obsolete warning，这里用 pragma 屏蔽该警告，先保证反射纹理流程跑通。
#pragma warning disable CS0618
        UniversalRenderPipeline.RenderSingleCamera(context, reflectionCamera); // 用当前 SRP 渲染上下文手动渲染反射相机到 reflectionCamera.targetTexture。
#pragma warning restore CS0618

        Shader.SetGlobalTexture(globalTextureId, runtimeReflectionTexture); // 把反射 RT 设置成全局纹理，供水面 Shader 采样。

        GL.invertCulling = oldInvertCulling; // 恢复原来的剔除状态，避免影响主相机正常渲染。

        if (disablePixelLights) QualitySettings.pixelLightCount = oldPixelLightCount; // 恢复原来的像素光数量。

        isRenderingReflection = false; // 标记离开反射渲染流程。
    }

    private void EnsureReflectionCamera() // 确保脚本内部反射相机存在。
    {
        if (reflectionCamera != null) return; // 如果已经创建过，直接返回。

        GameObject cameraObject = new GameObject("Planar Reflection Camera"); // 创建一个新的隐藏相机物体。
        cameraObject.hideFlags = HideFlags.HideAndDontSave;

        reflectionCamera = cameraObject.AddComponent<Camera>();
        reflectionCamera.hideFlags = HideFlags.HideAndDontSave;
        reflectionCamera.enabled = false;
        reflectionCamera.cameraType = CameraType.Reflection;
    }

    private void EnsureReflectionTexture(Camera sourceCamera) // 确保反射 RT 存在并和主相机尺寸匹配。
    {
        if (reflectionTexture != null) // 如果用户在 Inspector 手动指定了 RT。
        {
            runtimeReflectionTexture = reflectionTexture; // 直接使用用户提供的 RT。
            ownsRuntimeTexture = false; // 用户提供的 RT 不由脚本释放。
            return; // 外部 RT 不需要脚本自动创建。
        }

        int width = Mathf.Max(1, Mathf.RoundToInt(sourceCamera.pixelWidth * textureScale)); // 计算自动 RT 宽度。
        int height = Mathf.Max(1, Mathf.RoundToInt(sourceCamera.pixelHeight * textureScale)); // 计算自动 RT 高度。

        if (runtimeReflectionTexture != null && runtimeReflectionTexture.width == width && runtimeReflectionTexture.height == height) return; // 尺寸没变就复用。

        ReleaseRuntimeTexture(); // 尺寸变化或首次创建前，先释放旧 RT。

        runtimeReflectionTexture = new RenderTexture(width, height, 16, RenderTextureFormat.ARGB32); // 创建颜色 RT，深度缓冲 16 位。
        runtimeReflectionTexture.name = "PlanarReflectionRT"; // 设置名称，方便 Frame Debugger 或 Inspector 识别。
        runtimeReflectionTexture.useMipMap = false; // 平面反射第一版不需要 mipmap。
        runtimeReflectionTexture.autoGenerateMips = false; // 禁用 mipmap 自动生成。
        runtimeReflectionTexture.wrapMode = TextureWrapMode.Clamp; // 屏幕空间采样边缘使用 Clamp，减少边缘拉伸错误。
        runtimeReflectionTexture.filterMode = FilterMode.Bilinear; // 使用双线性过滤，让半分辨率反射不太硬。
        runtimeReflectionTexture.Create(); // 在 GPU 上实际创建 RT。

        ownsRuntimeTexture = true; // 标记这个 RT 由脚本创建，需要脚本释放。
    }

    private void UpdateReflectionCamera(Camera sourceCamera) // 根据主相机更新反射相机。
    {
        reflectionCamera.CopyFrom(sourceCamera); // 复制主相机的 FOV、near/far、clear flags、背景色等基础属性。
        reflectionCamera.enabled = false; // CopyFrom 后再次确保反射相机不会自动渲染。
        reflectionCamera.cameraType = CameraType.Reflection; // CopyFrom 后再次确保相机类型为 Reflection。
        reflectionCamera.targetTexture = runtimeReflectionTexture; // 把反射相机输出绑定到反射 RT。
        var reflectionCameraData = reflectionCamera.GetUniversalAdditionalCameraData();
        reflectionCameraData.renderPostProcessing = false;
        reflectionCameraData.renderShadows = false;
        reflectionCameraData.requiresDepthTexture = false;
        reflectionCameraData.requiresColorTexture = false;
        //reflectionCameraData.SetRenderer(0); // 如果 0 是无 SSAO 的轻量 Renderer，才这样设。


        int cullingMask = reflectionCullingMask.value; // 读取反射相机的基础剔除层。
        if (excludeWaterObjectLayer) cullingMask &= ~(1 << gameObject.layer); // 可选：剔除当前水面物体所在层，避免反射中出现水面自身。
        reflectionCamera.cullingMask = cullingMask; // 应用最终 cullingMask。

        Vector3 planePosition = transform.position; // 使用脚本挂载物体的位置作为水面平面上的一点。
        Vector3 planeNormal = transform.up.normalized; // 使用脚本挂载物体的 up 方向作为水面法线。
        Vector3 offsetPosition = planePosition + planeNormal * clipPlaneOffset; // 把裁剪平面沿法线略微抬起，减少 z-fighting。

        float planeDistance = -Vector3.Dot(planeNormal, offsetPosition); // 计算世界空间平面方程 n·p + d = 0 中的 d。
        Vector4 reflectionPlane = new Vector4(planeNormal.x, planeNormal.y, planeNormal.z, planeDistance); // 组装世界空间反射平面。

        Matrix4x4 reflectionMatrix = CalculateReflectionMatrix(reflectionPlane); // 计算关于水面平面对称的矩阵。
        reflectionCamera.worldToCameraMatrix = sourceCamera.worldToCameraMatrix * reflectionMatrix; // 把主相机 view 矩阵变成镜像 view 矩阵。

        float clipSign = flipClipPlane ? -1.0f : 1.0f; // 根据调试开关决定裁剪平面方向。
        Vector4 cameraSpaceClipPlane = CameraSpacePlane(reflectionCamera, offsetPosition, planeNormal, clipSign); // 把水面裁剪平面转换到反射相机空间。
        reflectionCamera.projectionMatrix = sourceCamera.CalculateObliqueMatrix(cameraSpaceClipPlane); // 使用斜近平面投影，裁掉水面下方内容。

        reflectionCamera.transform.position = reflectionMatrix.MultiplyPoint(sourceCamera.transform.position); // 同步 Transform 位置，方便调试观察。
        reflectionCamera.transform.rotation = sourceCamera.transform.rotation; // Transform 旋转不参与最终 view 矩阵，只是保持一个可读状态。
    }

    private static Matrix4x4 CalculateReflectionMatrix(Vector4 plane) // 计算关于任意平面的反射矩阵。
    {
        Matrix4x4 matrix = Matrix4x4.zero; // 创建一个空矩阵，逐项填充。

        matrix.m00 = 1.0f - 2.0f * plane.x * plane.x; // 第一行第一列：x 轴对平面法线 x 分量的反射影响。
        matrix.m01 = -2.0f * plane.x * plane.y; // 第一行第二列：y 对 x 的反射影响。
        matrix.m02 = -2.0f * plane.x * plane.z; // 第一行第三列：z 对 x 的反射影响。
        matrix.m03 = -2.0f * plane.w * plane.x; // 第一行第四列：平面距离对 x 平移的影响。

        matrix.m10 = -2.0f * plane.y * plane.x; // 第二行第一列：x 对 y 的反射影响。
        matrix.m11 = 1.0f - 2.0f * plane.y * plane.y; // 第二行第二列：y 轴对平面法线 y 分量的反射影响。
        matrix.m12 = -2.0f * plane.y * plane.z; // 第二行第三列：z 对 y 的反射影响。
        matrix.m13 = -2.0f * plane.w * plane.y; // 第二行第四列：平面距离对 y 平移的影响。

        matrix.m20 = -2.0f * plane.z * plane.x; // 第三行第一列：x 对 z 的反射影响。
        matrix.m21 = -2.0f * plane.z * plane.y; // 第三行第二列：y 对 z 的反射影响。
        matrix.m22 = 1.0f - 2.0f * plane.z * plane.z; // 第三行第三列：z 轴对平面法线 z 分量的反射影响。
        matrix.m23 = -2.0f * plane.w * plane.z; // 第三行第四列：平面距离对 z 平移的影响。

        matrix.m30 = 0.0f; // 第四行第一列：齐次坐标固定值。
        matrix.m31 = 0.0f; // 第四行第二列：齐次坐标固定值。
        matrix.m32 = 0.0f; // 第四行第三列：齐次坐标固定值。
        matrix.m33 = 1.0f; // 第四行第四列：保持齐次坐标 w 不变。

        return matrix; // 返回完整反射矩阵。
    }

    private static Vector4 CameraSpacePlane(Camera camera, Vector3 position, Vector3 normal, float sideSign) // 把世界空间平面转换到指定相机空间。
    {
        Matrix4x4 worldToCamera = camera.worldToCameraMatrix; // 读取相机的世界到相机空间矩阵。
        Vector3 cameraSpacePosition = worldToCamera.MultiplyPoint(position); // 把平面上的点转换到相机空间。
        Vector3 cameraSpaceNormal = worldToCamera.MultiplyVector(normal).normalized * sideSign; // 把平面法线转换到相机空间，并按需要反向。
        float cameraSpaceDistance = -Vector3.Dot(cameraSpacePosition, cameraSpaceNormal); // 计算相机空间平面方程 n·p + d = 0 的 d。
        return new Vector4(cameraSpaceNormal.x, cameraSpaceNormal.y, cameraSpaceNormal.z, cameraSpaceDistance); // 返回相机空间裁剪平面。
    }

    private void ReleaseRuntimeTexture() // 释放脚本自动创建的 RT。
    {
        if (!ownsRuntimeTexture) return; // 如果 RT 不是脚本创建的，不释放。
        if (runtimeReflectionTexture == null) return; // 如果没有 RT，直接返回。

        runtimeReflectionTexture.Release(); // 释放 GPU 资源。
        DestroyImmediate(runtimeReflectionTexture); // 销毁 Unity 对象。
        runtimeReflectionTexture = null; // 清空引用，避免悬空引用。
        ownsRuntimeTexture = false; // 重置所有权标记。
    }

    private void DestroyReflectionCamera() // 销毁脚本创建的反射相机。
    {
        if (reflectionCamera == null) return; // 如果没有反射相机，直接返回。

        GameObject cameraObject = reflectionCamera.gameObject; // 记录反射相机所在 GameObject。
        reflectionCamera.targetTexture = null; // 解除 RT 绑定，避免销毁顺序问题。
        reflectionCamera = null; // 清空相机引用。

        if (Application.isPlaying) Destroy(cameraObject); // Play 模式用 Destroy。
        else DestroyImmediate(cameraObject); // Editor 非播放模式用 DestroyImmediate。
    }
}
