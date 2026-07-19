using ShaderLearning.Coastline;
using UnityEditor;
using UnityEngine;

namespace ShaderLearning.Coastline.Editor
{
    internal static class CoastlineFinalizeBaker
    {
        private const string ShaderPath =
            "Assets/CoastlineBaking/Shaders/CoastlineFinalize.compute";
        private const string NearestSeedPath =
            "Assets/CoastlineBaking/Texture/NearestSeedMap.asset";
        private const string MaskPath =
            "Assets/CoastlineBaking/Texture/LandMask.asset";
        private const string OutputPath =
            "Assets/CoastlineBaking/Texture/CoastlineMap.asset";

        public static void Bake(CoastlineBakeAsset bakeAsset)
        {
            ComputeShader shader =
                AssetDatabase.LoadAssetAtPath<ComputeShader>(ShaderPath);
            Texture2D nearestSeedMap =
                AssetDatabase.LoadAssetAtPath<Texture2D>(NearestSeedPath);
            Texture2D landMask =
                AssetDatabase.LoadAssetAtPath<Texture2D>(MaskPath);

            if (shader == null ||
                nearestSeedMap == null ||
                landMask == null)
            {
                Debug.LogError(
                    "Finalize shader, NearestSeedMap or LandMask is missing.");
                return;
            }

            int resolution = bakeAsset.Resolution;

            var outputRT = new RenderTexture(
                resolution, resolution, 0,
                RenderTextureFormat.ARGBHalf,
                RenderTextureReadWrite.Linear)
            {
                enableRandomWrite = true,
                useMipMap = false,
                filterMode = FilterMode.Bilinear,
                wrapMode = TextureWrapMode.Clamp
            };
            outputRT.Create();

            int kernel = shader.FindKernel("BuildCoastlineMap");

            shader.SetTexture(
                kernel, "_NearestSeedMap", nearestSeedMap);
            shader.SetTexture(
                kernel, "_LandMask", landMask);
            shader.SetTexture(
                kernel, "_CoastlineMap", outputRT);

            shader.SetInts(
                "_Resolution", resolution, resolution);
            shader.SetVector(
                "_WorldSizeXZ",
                new Vector4(
                    bakeAsset.Bounds.size.x,
                    bakeAsset.Bounds.size.z, 0f, 0f));
            shader.SetFloat(
                "_MaxCoastDistance",
                bakeAsset.MaxCoastDistance);

            int groups = Mathf.CeilToInt(resolution / 8f);
            shader.Dispatch(kernel, groups, groups, 1);

            Texture2D coastlineMap =
                AssetDatabase.LoadAssetAtPath<Texture2D>(OutputPath);
            bool isNew = coastlineMap == null;

            if (isNew)
            {
                coastlineMap = new Texture2D(
                    resolution, resolution,
                    TextureFormat.RGBAHalf, false, true);
                coastlineMap.name = "CoastlineMap";
            }
            else
            {
                coastlineMap.Reinitialize(
                    resolution, resolution,
                    TextureFormat.RGBAHalf, false);
            }

            RenderTexture previous = RenderTexture.active;
            RenderTexture.active = outputRT;
            coastlineMap.ReadPixels(
                new Rect(0, 0, resolution, resolution),
                0, 0, false);
            coastlineMap.Apply(false, false);
            RenderTexture.active = previous;

            coastlineMap.wrapMode = TextureWrapMode.Clamp;
            coastlineMap.filterMode = FilterMode.Bilinear;

            if (isNew)
                AssetDatabase.CreateAsset(coastlineMap, OutputPath);

            bakeAsset.CoastlineMap = coastlineMap;
            bakeAsset.Version = CoastlineBakeAsset.CurrentVersion;

            EditorUtility.SetDirty(coastlineMap);
            EditorUtility.SetDirty(bakeAsset);
            AssetDatabase.SaveAssets();

            outputRT.Release();
            Object.DestroyImmediate(outputRT);

            Debug.Log(
                $"CoastlineMap baked: {resolution}x{resolution}, " +
                $"max distance {bakeAsset.MaxCoastDistance:F1}m.");
        }
    }
}
