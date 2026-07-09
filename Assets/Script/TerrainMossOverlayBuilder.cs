using UnityEngine;
using System.Collections.Generic;

[ExecuteAlways]
public class TerrainMossOverlayBuilder : MonoBehaviour
{
    [Header("Terrain Source")]
    [SerializeField] private Terrain terrain;
    [SerializeField] private int mossLayerIndex = 2;

    [Header("Moss Overlay")]
    [UnityEngine.Serialization.FormerlySerializedAs("debugOverlayMaterial")]
    [SerializeField] private Material mossShellMaterial;
    [SerializeField] private float chunkSize = 16f;
    [UnityEngine.Serialization.FormerlySerializedAs("debugChunkX")]
    [SerializeField] private int centerChunkX = 0;
    [UnityEngine.Serialization.FormerlySerializedAs("debugChunkZ")]
    [SerializeField] private int centerChunkZ = 0;
    [UnityEngine.Serialization.FormerlySerializedAs("debugChunkRadius")]
    [SerializeField] private int chunkRadius = 1;
    [SerializeField] private float chunkSkipThreshold = 0.02f;

    [Header("Mesh Sampling")]
    [SerializeField] private float meshSpacing = 1f;
    [SerializeField] private float surfaceOffset = 0.015f;
    [SerializeField, Range(0f, 1f)] private float mossTriangleThreshold = 0.15f;
    [SerializeField, Range(0f, 1f)] private float mossFullWeight = 0.4f;

    [Header("Shell Rendering")]
    [UnityEngine.Serialization.FormerlySerializedAs("debugShellCount")]
    [SerializeField, Range(1, 32)] private int shellCount = 8;

    private const string OverlayRootName = "Moss_OverlayChunks";
    private const string LegacyDebugRootName = "Moss_DebugPatch";
    private const string ChunkNamePrefix = "MossChunk_";

    private static readonly int ShellTId = Shader.PropertyToID("_ShellT");
    private static readonly int MossBaseMapId = Shader.PropertyToID("_MossBaseMap");
    private static readonly int MossMaskMapId = Shader.PropertyToID("_MossMaskMap");

    private MaterialPropertyBlock shellPropertyBlock;

    private struct TerrainMossSample
    {
        public Vector2 terrainUV;
        public Vector2 mossUV;
        public Vector3 surfacePosition;
        public Vector3 normal;
        public float mossWeight;
        public float edgeFade;
    }

    private void OnEnable()
    {
        ApplyShellTToExistingShells();
    }

    private void OnValidate()
    {
        chunkSize = Mathf.Max(0.1f, chunkSize);
        meshSpacing = Mathf.Max(0.01f, meshSpacing);
        surfaceOffset = Mathf.Max(0f, surfaceOffset);
        chunkRadius = Mathf.Max(0, chunkRadius);
        chunkSkipThreshold = Mathf.Clamp01(chunkSkipThreshold);
        mossFullWeight = Mathf.Max(mossTriangleThreshold + 0.001f, mossFullWeight);

        ApplyShellTToExistingShells();
    }

    [ContextMenu("Build Moss Overlay")]
    private void BuildMossOverlay()
    {
        if (!TryGetTerrainData(out TerrainData data))
        {
            return;
        }

        if (mossShellMaterial == null)
        {
            Debug.LogError("Moss shell material is missing.");
            return;
        }

        BindTerrainMossLayerTextures(data);
        ClearExistingOverlay();

        GameObject overlayRoot = new GameObject(OverlayRootName);
        overlayRoot.transform.SetParent(transform, false);

        int builtChunks = 0;
        int skippedChunks = 0;

        int radius = Mathf.Max(0, chunkRadius);
        for (int z = centerChunkZ - radius; z <= centerChunkZ + radius; z++)
        {
            for (int x = centerChunkX - radius; x <= centerChunkX + radius; x++)
            {
                if (!ChunkHasEnoughMoss(data, x, z))
                {
                    skippedChunks++;
                    continue;
                }

                Vector3 center = terrain.transform.TransformPoint(new Vector3(
                    (x + 0.5f) * chunkSize,
                    0f,
                    (z + 0.5f) * chunkSize
                ));

                GameObject chunkRoot = BuildOverlayChunk(center, chunkSize, $"{ChunkNamePrefix}{x}_{z}", overlayRoot.transform);
                if (chunkRoot != null)
                {
                    builtChunks++;
                }
                else
                {
                    skippedChunks++;
                }
            }
        }

        if (builtChunks == 0)
        {
            DestroyGeneratedObject(overlayRoot);
        }

        Debug.Log($"Built moss overlay. Built chunks: {builtChunks}, skipped chunks: {skippedChunks}");
    }

    [ContextMenu("Clear Moss Overlay")]
    private void ClearExistingOverlay()
    {
        for (int i = transform.childCount - 1; i >= 0; i--)
        {
            Transform child = transform.GetChild(i);
            bool shouldDelete = child.name == OverlayRootName
                || child.name == LegacyDebugRootName
                || child.name.StartsWith(ChunkNamePrefix);

            if (shouldDelete)
            {
                DestroyGeneratedObject(child.gameObject);
            }
        }
    }

    private bool TryGetTerrainData(out TerrainData data)
    {
        data = null;

        if (terrain == null)
        {
            Debug.LogError("Terrain reference is missing.");
            return false;
        }

        data = terrain.terrainData;
        if (data == null)
        {
            Debug.LogError("TerrainData is missing.");
            return false;
        }

        if (mossLayerIndex < 0 || mossLayerIndex >= data.terrainLayers.Length)
        {
            Debug.LogError($"Invalid moss layer index: {mossLayerIndex}");
            return false;
        }

        return true;
    }

    private void BindTerrainMossLayerTextures(TerrainData data)
    {
        TerrainLayer mossLayer = data.terrainLayers[mossLayerIndex];
        mossShellMaterial.SetTexture(MossBaseMapId, mossLayer.diffuseTexture);
        mossShellMaterial.SetTexture(MossMaskMapId, mossLayer.maskMapTexture);
    }

    private bool ChunkHasEnoughMoss(TerrainData data, int chunkX, int chunkZ)
    {
        float startX = chunkX * chunkSize;
        float startZ = chunkZ * chunkSize;
        float endX = startX + chunkSize;
        float endZ = startZ + chunkSize;

        if (endX < 0f || endZ < 0f || startX > data.size.x || startZ > data.size.z)
        {
            return false;
        }

        const int sampleCount = 4;
        float totalWeight = 0f;
        int validSamples = 0;

        for (int z = 0; z < sampleCount; z++)
        {
            for (int x = 0; x < sampleCount; x++)
            {
                float localX = (chunkX + (x + 0.5f) / sampleCount) * chunkSize;
                float localZ = (chunkZ + (z + 0.5f) / sampleCount) * chunkSize;
                Vector3 world = terrain.transform.TransformPoint(new Vector3(localX, 0f, localZ));

                if (TrySampleTerrainMoss(world, out TerrainMossSample sample))
                {
                    totalWeight += sample.mossWeight;
                    validSamples++;
                }
            }
        }

        if (validSamples == 0)
        {
            return false;
        }

        return totalWeight / validSamples >= chunkSkipThreshold;
    }

    private GameObject BuildOverlayChunk(Vector3 center, float patchSize, string chunkName, Transform parent)
    {
        float safeSpacing = Mathf.Max(0.001f, meshSpacing);
        int steps = Mathf.Max(1, Mathf.RoundToInt(patchSize / safeSpacing));
        float spacing = patchSize / steps;
        Vector3 origin = new Vector3(center.x, 0f, center.z);

        List<Vector3> vertices = new();
        List<Vector3> normals = new();
        List<Vector2> uvs = new();
        List<Vector2> mossUvs = new();
        List<Color> colors = new();
        List<int> triangles = new();

        for (int z = 0; z <= steps; z++)
        {
            for (int x = 0; x <= steps; x++)
            {
                float localX = x * spacing - patchSize * 0.5f;
                float localZ = z * spacing - patchSize * 0.5f;
                Vector3 sampleWorldPosition = new Vector3(origin.x + localX, 0f, origin.z + localZ);

                if (!TrySampleTerrainMoss(sampleWorldPosition, out TerrainMossSample sample))
                {
                    return null;
                }

                Vector3 liftedPosition = sample.surfacePosition + sample.normal * surfaceOffset;
                vertices.Add(liftedPosition - origin);
                normals.Add(sample.normal);
                uvs.Add(sample.terrainUV);
                mossUvs.Add(sample.mossUV);
                colors.Add(new Color(sample.mossWeight, sample.edgeFade, 0f, 1f));
            }
        }

        int row = steps + 1;
        for (int z = 0; z < steps; z++)
        {
            for (int x = 0; x < steps; x++)
            {
                int i0 = z * row + x;
                int i1 = i0 + 1;
                int i2 = i0 + row;
                int i3 = i2 + 1;

                if (ShouldKeepTriangle(colors[i0], colors[i2], colors[i1]))
                {
                    triangles.Add(i0);
                    triangles.Add(i2);
                    triangles.Add(i1);
                }

                if (ShouldKeepTriangle(colors[i1], colors[i2], colors[i3]))
                {
                    triangles.Add(i1);
                    triangles.Add(i2);
                    triangles.Add(i3);
                }
            }
        }

        if (triangles.Count == 0)
        {
            return null;
        }

        Mesh mesh = new Mesh
        {
            name = chunkName
        };

        if (vertices.Count > 65535)
        {
            mesh.indexFormat = UnityEngine.Rendering.IndexFormat.UInt32;
        }

        mesh.SetVertices(vertices);
        mesh.SetNormals(normals);
        mesh.SetUVs(0, uvs);
        mesh.SetUVs(1, mossUvs);
        mesh.SetColors(colors);
        mesh.SetTriangles(triangles, 0);
        mesh.RecalculateBounds();

        GameObject chunkRoot = new GameObject(chunkName);
        chunkRoot.transform.SetParent(parent, true);
        chunkRoot.transform.position = origin;

        BuildShellStack(mesh, chunkRoot.transform);
        return chunkRoot;
    }

    private bool TrySampleTerrainMoss(Vector3 worldPosition, out TerrainMossSample sample)
    {
        sample = default;

        if (!TryGetTerrainData(out TerrainData data))
        {
            return false;
        }

        Vector3 local = terrain.transform.InverseTransformPoint(worldPosition);
        float u = local.x / data.size.x;
        float v = local.z / data.size.z;

        if (u < 0f || u > 1f || v < 0f || v > 1f)
        {
            return false;
        }

        float height = data.GetInterpolatedHeight(u, v);
        Vector3 localSurface = new Vector3(local.x, height, local.z);
        Vector3 surfacePosition = terrain.transform.TransformPoint(localSurface);

        Vector3 localNormal = data.GetInterpolatedNormal(u, v);
        Vector3 normal = terrain.transform.TransformDirection(localNormal).normalized;

        int alphaX = Mathf.RoundToInt(u * (data.alphamapWidth - 1));
        int alphaY = Mathf.RoundToInt(v * (data.alphamapHeight - 1));
        float[,,] alpha = data.GetAlphamaps(alphaX, alphaY, 1, 1);
        float mossWeight = alpha[0, 0, mossLayerIndex];

        TerrainLayer mossLayer = data.terrainLayers[mossLayerIndex];
        Vector2 localXZ = new Vector2(local.x, local.z);
        Vector2 tileSize = mossLayer.tileSize;
        Vector2 tileOffset = mossLayer.tileOffset;

        float mossU = (localXZ.x - tileOffset.x) / Mathf.Max(0.0001f, tileSize.x);
        float mossV = (localXZ.y - tileOffset.y) / Mathf.Max(0.0001f, tileSize.y);
        float edgeFade = Mathf.InverseLerp(mossTriangleThreshold, mossFullWeight, mossWeight);

        sample.terrainUV = new Vector2(u, v);
        sample.mossUV = new Vector2(mossU, mossV);
        sample.surfacePosition = surfacePosition;
        sample.normal = normal;
        sample.mossWeight = mossWeight;
        sample.edgeFade = edgeFade;

        return true;
    }

    private void BuildShellStack(Mesh mesh, Transform root)
    {
        int count = Mathf.Max(1, shellCount);

        for (int i = 0; i < count; i++)
        {
            float shellT = count <= 1 ? 0f : i / (float)(count - 1);
            GameObject layer = new GameObject($"Shell_{i:00}");
            layer.transform.SetParent(root, false);

            MeshFilter meshFilter = layer.AddComponent<MeshFilter>();
            MeshRenderer meshRenderer = layer.AddComponent<MeshRenderer>();

            meshFilter.sharedMesh = mesh;
            meshRenderer.sharedMaterial = mossShellMaterial;
            meshRenderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            meshRenderer.receiveShadows = false;

            SetShellT(meshRenderer, shellT);
        }
    }

    private void ApplyShellTToExistingShells()
    {
        Transform overlayRoot = FindOverlayRoot();
        if (overlayRoot != null)
        {
            ApplyShellTUnder(overlayRoot);
        }
    }

    private Transform FindOverlayRoot()
    {
        Transform overlayRoot = transform.Find(OverlayRootName);
        if (overlayRoot != null)
        {
            return overlayRoot;
        }

        return transform.Find(LegacyDebugRootName);
    }

    private void ApplyShellTUnder(Transform root)
    {
        List<MeshRenderer> shellRenderers = new();

        for (int i = 0; i < root.childCount; i++)
        {
            MeshRenderer meshRenderer = root.GetChild(i).GetComponent<MeshRenderer>();
            if (meshRenderer != null)
            {
                shellRenderers.Add(meshRenderer);
            }
        }

        if (shellRenderers.Count > 0)
        {
            int count = shellRenderers.Count;
            for (int i = 0; i < count; i++)
            {
                float shellT = count <= 1 ? 0f : i / (float)(count - 1);
                SetShellT(shellRenderers[i], shellT);
            }

            return;
        }

        for (int i = 0; i < root.childCount; i++)
        {
            ApplyShellTUnder(root.GetChild(i));
        }
    }

    private void SetShellT(MeshRenderer meshRenderer, float shellT)
    {
        shellPropertyBlock ??= new MaterialPropertyBlock();
        shellPropertyBlock.Clear();
        meshRenderer.GetPropertyBlock(shellPropertyBlock);
        shellPropertyBlock.SetFloat(ShellTId, shellT);
        meshRenderer.SetPropertyBlock(shellPropertyBlock);
    }

    private bool ShouldKeepTriangle(Color a, Color b, Color c)
    {
        float averageWeight = (a.r + b.r + c.r) / 3f;
        return averageWeight >= mossTriangleThreshold;
    }

    private void DestroyGeneratedObject(GameObject target)
    {
        if (target == null)
        {
            return;
        }

        if (Application.isPlaying)
        {
            Destroy(target);
        }
        else
        {
            DestroyImmediate(target);
        }
    }
}