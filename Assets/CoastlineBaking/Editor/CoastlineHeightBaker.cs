using ShaderLearning.Coastline;
using UnityEditor;
using UnityEngine;

namespace ShaderLearning.Coastline.Editor
{
    internal static class CoastlineHeightBaker
    {
        private const string OutputPath =
            "Assets/CoastlineBaking/Texture/GroundHeightMap.asset";

        public static void Bake(
            Terrain terrain,
            CoastlineBakeAsset bakeAsset)
        {
            TerrainData data = terrain.terrainData;
            int resolution = bakeAsset.Resolution;
            int sourceResolution = data.heightmapResolution;

            float[,] source = data.GetHeights(
                0, 0, sourceResolution, sourceResolution);

            float[] worldHeights =
                new float[resolution * resolution];

            float minHeight = float.PositiveInfinity;
            float maxHeight = float.NegativeInfinity;
            float heightScale =
                data.size.y * terrain.transform.lossyScale.y;
            float heightOffset = terrain.transform.position.y;

            for (int y = 0; y < resolution; y++)
            {
                float v = (y + 0.5f) / resolution;
                float sourceZ = v * (sourceResolution - 1);
                int z0 = Mathf.FloorToInt(sourceZ);
                int z1 = Mathf.Min(z0 + 1, sourceResolution - 1);
                float tz = sourceZ - z0;

                for (int x = 0; x < resolution; x++)
                {
                    float u = (x + 0.5f) / resolution;
                    float sourceX = u * (sourceResolution - 1);
                    int x0 = Mathf.FloorToInt(sourceX);
                    int x1 = Mathf.Min(x0 + 1, sourceResolution - 1);
                    float tx = sourceX - x0;

                    float bottom = Mathf.Lerp(
                        source[z0, x0], source[z0, x1], tx);
                    float top = Mathf.Lerp(
                        source[z1, x0], source[z1, x1], tx);

                    float worldY =
                        heightOffset +
                        Mathf.Lerp(bottom, top, tz) * heightScale;

                    worldHeights[y * resolution + x] = worldY;
                    minHeight = Mathf.Min(minHeight, worldY);
                    maxHeight = Mathf.Max(maxHeight, worldY);
                }
            }

            Texture2D texture =
                AssetDatabase.LoadAssetAtPath<Texture2D>(OutputPath);

            if (texture == null)
            {
                texture = new Texture2D(
                    resolution, resolution,
                    TextureFormat.RFloat, false, true);

                texture.name = "GroundHeightMap";
                AssetDatabase.CreateAsset(texture, OutputPath);
            }
            else
            {
                texture.Reinitialize(
                    resolution, resolution,
                    TextureFormat.RFloat, false);
            }

            texture.SetPixelData(worldHeights, 0);
            texture.wrapMode = TextureWrapMode.Clamp;
            texture.filterMode = FilterMode.Bilinear;
            texture.Apply(false, false);

            bakeAsset.GroundHeightMap = texture;
            bakeAsset.HeightDecodeRange =
                new Vector2(minHeight, maxHeight);

            EditorUtility.SetDirty(texture);
            EditorUtility.SetDirty(bakeAsset);
            AssetDatabase.SaveAssets();

            Debug.Log(
                $"GroundHeightMap baked: {resolution}x{resolution}, " +
                $"world Y [{minHeight:F2}, {maxHeight:F2}]");
        }
    }
}