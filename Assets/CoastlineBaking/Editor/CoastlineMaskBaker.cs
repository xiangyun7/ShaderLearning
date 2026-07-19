using ShaderLearning.Coastline;
using UnityEditor;
using UnityEngine;

namespace ShaderLearning.Coastline.Editor
{
    internal static class CoastlineMaskBaker
    {
        private const string OutputPath =
            "Assets/CoastlineBaking/Texture/LandMask.asset";

        public static void Bake(CoastlineBakeAsset bakeAsset)
        {
            Texture2D heightMap = bakeAsset.GroundHeightMap;
            int resolution = bakeAsset.Resolution;

            if (heightMap == null ||
                heightMap.width != resolution ||
                heightMap.height != resolution)
            {
                Debug.LogError(
                    "Bake a matching GroundHeightMap first.");
                return;
            }

            var heights = heightMap.GetPixelData<float>(0);
            byte[] mask = new byte[resolution * resolution];
            int landCount = 0;

            for (int i = 0; i < mask.Length; i++)
            {
                // 高度等于水面时仍归类为海水。
                bool isLand = heights[i] > bakeAsset.WaterLevel;
                mask[i] = isLand ? (byte)255 : (byte)0;

                if (isLand)
                    landCount++;
            }

            Texture2D maskTexture =
                AssetDatabase.LoadAssetAtPath<Texture2D>(OutputPath);

            if (maskTexture == null)
            {
                maskTexture = new Texture2D(
                    resolution, resolution,
                    TextureFormat.R8, false, true);

                maskTexture.name = "LandMask";
                AssetDatabase.CreateAsset(maskTexture, OutputPath);
            }
            else
            {
                maskTexture.Reinitialize(
                    resolution, resolution,
                    TextureFormat.R8, false);
            }

            maskTexture.SetPixelData(mask, 0);
            maskTexture.wrapMode = TextureWrapMode.Clamp;
            maskTexture.filterMode = FilterMode.Point;
            maskTexture.Apply(false, false);

            EditorUtility.SetDirty(maskTexture);
            AssetDatabase.SaveAssets();

            float coverage = landCount * 100f / mask.Length;
            Debug.Log($"LandMask baked. Land coverage: {coverage:F1}%");
        }
    }
}