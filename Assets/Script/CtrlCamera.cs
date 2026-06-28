using UnityEngine;

public class CtrlCamera : MonoBehaviour
{
    public float moveSpeed = 6.0f;
    public float fastMultiplier = 3.0f;
    public float mouseSensitivity = 2.0f;
    public bool rotateOnlyWhileRightMouseHeld = true;

    private float yaw;
    private float pitch;

    private void Start()
    {
        Vector3 euler = transform.eulerAngles;
        yaw = euler.y;
        pitch = NormalizePitch(euler.x);
    }

    private void Update()
    {
        UpdateRotation();
        UpdateMovement();
    }

    private void UpdateRotation()
    {
        if (rotateOnlyWhileRightMouseHeld && !Input.GetMouseButton(1))
        {
            return;
        }

        float mouseX = Input.GetAxisRaw("Mouse X");
        float mouseY = Input.GetAxisRaw("Mouse Y");

        yaw += mouseX * mouseSensitivity;
        pitch -= mouseY * mouseSensitivity;
        pitch = Mathf.Clamp(pitch, -89.0f, 89.0f);

        transform.rotation = Quaternion.Euler(pitch, yaw, 0.0f);
    }

    private void UpdateMovement()
    {
        Vector3 move = Vector3.zero;

        if (Input.GetKey(KeyCode.W)) move += transform.forward;
        if (Input.GetKey(KeyCode.S)) move -= transform.forward;
        if (Input.GetKey(KeyCode.D)) move += transform.right;
        if (Input.GetKey(KeyCode.A)) move -= transform.right;
        if (Input.GetKey(KeyCode.Space)) move += Vector3.up;
        if (Input.GetKey(KeyCode.LeftControl) || Input.GetKey(KeyCode.RightControl)) move -= Vector3.up;

        if (move.sqrMagnitude <= 0.0001f)
        {
            return;
        }

        float speed = moveSpeed;
        if (Input.GetKey(KeyCode.LeftShift) || Input.GetKey(KeyCode.RightShift))
        {
            speed *= fastMultiplier;
        }

        transform.position += move.normalized * speed * Time.deltaTime;
    }

    private static float NormalizePitch(float angle)
    {
        if (angle > 180.0f)
        {
            angle -= 360.0f;
        }

        return angle;
    }
}
