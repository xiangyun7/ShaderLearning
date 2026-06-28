using UnityEngine;

[RequireComponent(typeof(Collider))] // 🔹 确保物体有碰撞体（鼠标射线检测必需）
public class DraggableWindow : MonoBehaviour
{
    [Header("拖拽设置")]
    [Tooltip("拖拽时，物体沿哪个平面移动？推荐与摄像机朝向垂直")]
    public Vector3 dragPlaneNormal = Vector3.forward; // 默认沿 XY 平面拖拽

    [Tooltip("拖拽灵敏度：1 = 1:1 移动，>1 更快，<1 更慢")]
    public float dragSensitivity = 1f;

    [Header("调试信息")]
    public bool isDragging = false;

    // 内部变量
    private Camera _mainCamera;
    private Vector3 _dragStartWorldPos;      // 拖拽开始时物体的世界位置
    private Vector3 _dragStartMouseWorldPos; // 拖拽开始时鼠标对应的世界位置
    private Plane _dragPlane;                // 拖拽平面（用于坐标转换）

    void Start()
    {
        _mainCamera = Camera.main;

        // 🔹 自动设置拖拽平面：垂直于摄像机朝向（更自然）
        if (dragPlaneNormal == Vector3.forward)
        {
            dragPlaneNormal = _mainCamera.transform.forward;
        }

        // 🔹 确保有 Collider（没有的话自动加一个盒状碰撞体）
        if (GetComponent<Collider>() == null)
        {
            var box = gameObject.AddComponent<BoxCollider>();
            box.isTrigger = true; // 设为触发器，不影响物理
            Debug.LogWarning($"[DraggableWindow] {name} 自动添加了 BoxCollider（Trigger）");
        }
    }

    void Update()
    {
        // 🔹 鼠标按下：开始拖拽
        if (Input.GetMouseButtonDown(0)) // 左键
        {
            if (IsMouseOverObject())
            {
                StartDrag();
            }
        }

        // 🔹 鼠标拖动：更新位置
        if (isDragging && Input.GetMouseButton(0))
        {
            UpdateDrag();
        }

        // 🔹 鼠标松开：结束拖拽
        if (Input.GetMouseButtonUp(0))
        {
            StopDrag();
        }
    }

    /// <summary>
    /// 检测鼠标是否悬停在当前物体上
    /// </summary>
    bool IsMouseOverObject()
    {
        Ray ray = _mainCamera.ScreenPointToRay(Input.mousePosition);

        // 🔹 射线检测：只检测当前物体（避免误拖其他物体）
        if (Physics.Raycast(ray, out RaycastHit hit, 100f))
        {
            return hit.collider == GetComponent<Collider>();
        }
        return false;
    }

    /// <summary>
    /// 开始拖拽：记录初始状态
    /// </summary>
    void StartDrag()
    {
        isDragging = true;
        _dragStartWorldPos = transform.position;

        // 🔹 计算鼠标点击位置对应的世界坐标（在拖拽平面上）
        _dragPlane = new Plane(dragPlaneNormal, transform.position);
        Ray ray = _mainCamera.ScreenPointToRay(Input.mousePosition);

        if (_dragPlane.Raycast(ray, out float enter))
        {
            _dragStartMouseWorldPos = ray.GetPoint(enter);
        }

        Debug.Log($"[Drag] Start dragging {name}");
    }

    /// <summary>
    /// 更新拖拽：根据鼠标移动更新物体位置
    /// </summary>
    void UpdateDrag()
    {
        Ray ray = _mainCamera.ScreenPointToRay(Input.mousePosition);

        if (_dragPlane.Raycast(ray, out float enter))
        {
            Vector3 currentMouseWorldPos = ray.GetPoint(enter);
            Vector3 mouseDelta = currentMouseWorldPos - _dragStartMouseWorldPos;

            // 🔹 应用灵敏度 + 更新位置
            transform.position = _dragStartWorldPos + mouseDelta * dragSensitivity;
        }
    }

    /// <summary>
    /// 结束拖拽
    /// </summary>
    void StopDrag()
    {
        if (isDragging)
        {
            isDragging = false;
            Debug.Log($"[Drag] Stopped dragging {name}");
        }
    }

    // 🔹 可选：Editor 中可视化拖拽平面（方便调试）
    void OnDrawGizmosSelected()
    {
        if (!isDragging) return;

        Gizmos.color = Color.yellow;
        Gizmos.DrawWireSphere(transform.position, 0.1f);

        // 绘制拖拽平面（简化为一个大正方形）
        Vector3 right = Vector3.Cross(dragPlaneNormal, Vector3.up).normalized;
        Vector3 up = Vector3.Cross(right, dragPlaneNormal).normalized;

        Vector3 center = transform.position;
        float size = 10f;

        Gizmos.DrawLine(center - right * size - up * size, center + right * size - up * size);
        Gizmos.DrawLine(center + right * size - up * size, center + right * size + up * size);
        Gizmos.DrawLine(center + right * size + up * size, center - right * size + up * size);
        Gizmos.DrawLine(center - right * size + up * size, center - right * size - up * size);
    }
}