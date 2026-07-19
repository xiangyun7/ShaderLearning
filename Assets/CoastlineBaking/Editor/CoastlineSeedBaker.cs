using ShaderLearning.Coastline;
using UnityEditor;
using UnityEngine;

namespace ShaderLearning.Coastline.Editor
{
    internal static class CoastlineSeedBaker
    {
        private const string ShaderPath =
            "Assets/CoastlineBaking/Shaders/CoastlineSeed.compute";
        private const string MaskPath =
            "Assets/CoastlineBaking/Texture/LandMask.asset";
        private const string OutputPath =
            "Assets/CoastlineBaking/Texture/SeedMap.asset";

        public static void Bake(CoastlineBakeAsset bakeAsset)
        {
            ComputeShader shader =
                AssetDatabase.LoadAssetAtPath<ComputeShader>(ShaderPath);
            Texture2D mask =
                AssetDatabase.LoadAssetAtPath<Texture2D>(MaskPath);

            if (shader == null || mask == null ||
                bakeAsset.GroundHeightMap == null)
            {
                Debug.LogError(
                    "GroundHeightMap, LandMask or seed shader is missing.");
                return;
            }

            int resolution = bakeAsset.Resolution;

            var seedRT = new RenderTexture(
                resolution, resolution, 0,
                RenderTextureFormat.RGFloat,
                RenderTextureReadWrite.Linear)
            {
                enableRandomWrite = true,
                useMipMap = false,
                filterMode = FilterMode.Point,
                wrapMode = TextureWrapMode.Clamp
            };
            seedRT.Create();

            int kernel = shader.FindKernel("ExtractSeeds");
            shader.SetTexture(
                kernel, "_GroundHeightMap",
                bakeAsset.GroundHeightMap);
            shader.SetTexture(kernel, "_LandMask", mask);
            shader.SetTexture(kernel, "_SeedMap", seedRT);
            shader.SetInts(
                "_Resolution", resolution, resolution);
            shader.SetFloat(
                "_WaterLevel", bakeAsset.WaterLevel);
            shader.SetVector(
                "_WorldSizeXZ",
                new Vector4(
                    bakeAsset.Bounds.size.x,
                    bakeAsset.Bounds.size.z, 0f, 0f));

            int groups = Mathf.CeilToInt(resolution / 8f);
            shader.Dispatch(kernel, groups, groups, 1);

            Texture2D seedMap =
                AssetDatabase.LoadAssetAtPath<Texture2D>(OutputPath);
            bool isNew = seedMap == null;

            if (isNew)
            {
                seedMap = new Texture2D(
                    resolution, resolution,
                    TextureFormat.RGFloat, false, true);
                seedMap.name = "SeedMap";
            }
            else
            {
                seedMap.Reinitialize(
                    resolution, resolution,
                    TextureFormat.RGFloat, false);
            }

            RenderTexture previous = RenderTexture.active;
            RenderTexture.active = seedRT;
            seedMap.ReadPixels(
                new Rect(0, 0, resolution, resolution),
                0, 0, false);
            seedMap.Apply(false, false);
            RenderTexture.active = previous;

            seedRT.Release();
            Object.DestroyImmediate(seedRT);

            seedMap.filterMode = FilterMode.Point;
            seedMap.wrapMode = TextureWrapMode.Clamp;

            if (isNew)
                AssetDatabase.CreateAsset(seedMap, OutputPath);

            EditorUtility.SetDirty(seedMap);
            AssetDatabase.SaveAssets();

            var seeds = seedMap.GetPixelData<Vector2>(0);
            int validCount = 0;

            for (int i = 0; i < seeds.Length; i++)
                if (seeds[i].x >= 0f)
                    validCount++;

            Debug.Log(
                $"SeedMap baked. Valid seed pixels: {validCount}");
        }
    }
}