using UnityEngine;
using UnityEngine.Rendering;

[ExecuteAlways]
[DisallowMultipleComponent]
[RequireComponent(typeof(MeshFilter), typeof(MeshRenderer))]
public sealed class WaterBaseGrid : MonoBehaviour
{
    [Min(1f)]
    public float size = 500f;

    // 这是基础网格分辨率，不是最终显示面数。
    // 如果 shader 里做 tessellation，通常 16-64 就够起步。
    [Range(1, 256)]
    public int patchResolution = 32;

    [Min(1f)]
    public float tessEdgeLength = 12f;

    [Min(1f)]
    public float boundsHeight = 80f;

    private MeshFilter meshFilter;
    private MeshRenderer meshRenderer;
    private Mesh mesh;
    private MaterialPropertyBlock propertyBlock;

    private bool rebuildRequested;

    private float lastSize;
    private int lastPatchResolution;

    private static readonly int TessEdgeLengthId = Shader.PropertyToID("_TessEdgeLength");
    private static readonly int WaterSizeId = Shader.PropertyToID("_WaterSize");
    private static readonly int PatchResolutionId = Shader.PropertyToID("_PatchResolution");

    private void OnEnable()
    {
        CacheComponents();
        RequestRebuild();
    }

    private void OnValidate()
    {
        size = Mathf.Max(1f, size);
        patchResolution = Mathf.Clamp(patchResolution, 1, 256);
        tessEdgeLength = Mathf.Max(1f, tessEdgeLength);
        boundsHeight = Mathf.Max(1f, boundsHeight);

        RequestRebuild();
    }

    private void Update()
    {
        CacheComponents();

        if (rebuildRequested ||
            !Mathf.Approximately(lastSize, size) ||
            lastPatchResolution != patchResolution)
        {
            rebuildRequested = false;
            RebuildMesh();
        }

        PushMaterialParams();
    }

    private void OnDestroy()
    {
        if (mesh == null)
        {
            return;
        }

        if (Application.isPlaying)
        {
            Destroy(mesh);
        }
        else
        {
            DestroyImmediate(mesh);
        }

        mesh = null;
    }
    //——————function mode——————————————————-
    private void RequestRebuild()
    {
        rebuildRequested = true;
    }
    private void CacheComponents()
    {
        if (meshFilter == null)
        {
            meshFilter = GetComponent<MeshFilter>();
        }

        if (meshRenderer == null)
        {
            meshRenderer = GetComponent<MeshRenderer>();
        }

        propertyBlock ??= new MaterialPropertyBlock();
    }

    private void RebuildMesh()
    {
        if (mesh != null)
        {
            if (Application.isPlaying)
            {
                Destroy(mesh);
            }
            else
            {
                DestroyImmediate(mesh);
            }
        }

        mesh = BuildGrid(size, patchResolution);
        mesh.name = $"Water Base Grid {patchResolution}x{patchResolution}";
        mesh.hideFlags = HideFlags.DontSave;

        meshFilter.sharedMesh = mesh;

        lastSize = size;
        lastPatchResolution = patchResolution;
    }

    private Mesh BuildGrid(float gridSize, int resolution)
    {
        int verticesPerSide = resolution + 1;
        int vertexCount = verticesPerSide * verticesPerSide;

        Vector3[] vertices = new Vector3[vertexCount];
        Vector2[] uvs = new Vector2[vertexCount];
        Vector3[] normals = new Vector3[vertexCount];
        Vector4[] tangents = new Vector4[vertexCount];
        int[] triangles = new int[resolution * resolution * 6];

        float halfSize = gridSize * 0.5f;

        int vertexIndex = 0;

        for (int z = 0; z < verticesPerSide; z++)
        {
            float v = z / (float)resolution;
            float localZ = Mathf.Lerp(-halfSize, halfSize, v);

            for (int x = 0; x < verticesPerSide; x++)
            {
                float u = x / (float)resolution;
                float localX = Mathf.Lerp(-halfSize, halfSize, u);

                vertices[vertexIndex] = new Vector3(localX, 0f, localZ);
                uvs[vertexIndex] = new Vector2(u, v);
                normals[vertexIndex] = Vector3.up;
                tangents[vertexIndex] = new Vector4(1f, 0f, 0f, 1f);
                vertexIndex++;
            }
        }

        int triangleIndex = 0;

        for (int z = 0; z < resolution; z++)
        {
            for (int x = 0; x < resolution; x++)
            {
                int i0 = z * verticesPerSide + x;
                int i1 = i0 + 1;
                int i2 = i0 + verticesPerSide;
                int i3 = i2 + 1;

                triangles[triangleIndex++] = i0;
                triangles[triangleIndex++] = i2;
                triangles[triangleIndex++] = i1;

                triangles[triangleIndex++] = i1;
                triangles[triangleIndex++] = i2;
                triangles[triangleIndex++] = i3;
            }
        }

        Mesh result = new Mesh();
        result.indexFormat = vertexCount > 65535 ? IndexFormat.UInt32 : IndexFormat.UInt16;
        result.vertices = vertices;
        result.uv = uvs;
        result.normals = normals;
        result.tangents = tangents;
        result.triangles = triangles;

        result.bounds = new Bounds(Vector3.zero, new Vector3(gridSize, boundsHeight, gridSize));

        return result;
    }

    private void PushMaterialParams()
    {
        if (meshRenderer == null)
        {
            return;
        }

        meshRenderer.GetPropertyBlock(propertyBlock);
        propertyBlock.SetFloat(TessEdgeLengthId, tessEdgeLength);
        propertyBlock.SetFloat(WaterSizeId, size);
        propertyBlock.SetFloat(PatchResolutionId, patchResolution);
        meshRenderer.SetPropertyBlock(propertyBlock);
    }
}