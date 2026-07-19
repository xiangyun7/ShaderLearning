using ShaderLearning.Coastline;
using UnityEditor;
using UnityEngine;

namespace ShaderLearning.Coastline.Editor
{
    internal static class CoastlineJumpFloodBaker
    {
        private const string ShaderPath =
            "Assets/CoastlineBaking/Shaders/CoastlineJumpFlood.compute";
        private const string SeedPath =
            "Assets/CoastlineBaking/Texture/SeedMap.asset";
        private const string OutputPath =
            "Assets/CoastlineBaking/Texture/NearestSeedMap.asset";

        public static void Bake(CoastlineBakeAsset bakeAsset)
        {
            ComputeShader shader =
                AssetDatabase.LoadAssetAtPath<ComputeShader>(ShaderPath);
            Texture2D seedMap =
                AssetDatabase.LoadAssetAtPath<Texture2D>(SeedPath);

            if (shader == null || seedMap == null)
            {
                Debug.LogError("Jump Flood shader or SeedMap is missing.");
                return;
            }

            int resolution = bakeAsset.Resolution;

            RenderTexture CreateRT()
            {
                var rt = new RenderTexture(
                    resolution, resolution, 0,
                    RenderTextureFormat.RGFloat,
                    RenderTextureReadWrite.Linear)
                {
                    enableRandomWrite = true,
                    useMipMap = false,
                    filterMode = FilterMode.Point,
                    wrapMode = TextureWrapMode.Clamp
                };
                rt.Create();
                return rt;
            }

            RenderTexture read = CreateRT();
            RenderTexture write = CreateRT();
            Graphics.CopyTexture(seedMap, read);

            int kernel = shader.FindKernel("JumpFlood");
            int groups = Mathf.CeilToInt(resolution / 8f);
            int passCount = 0;

            shader.SetInts(
                "_Resolution", resolution, resolution);
            shader.SetVector(
                "_WorldSizeXZ",
                new Vector4(
                    bakeAsset.Bounds.size.x,
                    bakeAsset.Bounds.size.z, 0f, 0f));

            void RunPass(int step)
            {
                shader.SetInt("_Step", step);
                shader.SetTexture(kernel, "_InputSeeds", read);
                shader.SetTexture(kernel, "_OutputSeeds", write);
                shader.Dispatch(kernel, groups, groups, 1);

                RenderTexture temporary = read;
                read = write;
                write = temporary;
                passCount++;
            }

            for (int step = resolution / 2;
                 step >= 1;
                 step /= 2)
            {
                RunPass(step);
            }

            // 两次额外的步长 1 精修。
            RunPass(1);
            RunPass(1);

            Texture2D result =
                AssetDatabase.LoadAssetAtPath<Texture2D>(OutputPath);
            bool isNew = result == null;

            if (isNew)
            {
                result = new Texture2D(
                    resolution, resolution,
                    TextureFormat.RGFloat, false, true);
                result.name = "NearestSeedMap";
            }
            else
            {
                result.Reinitialize(
                    resolution, resolution,
                    TextureFormat.RGFloat, false);
            }

            RenderTexture previous = RenderTexture.active;
            RenderTexture.active = read;
            result.ReadPixels(
                new Rect(0, 0, resolution, resolution),
                0, 0, false);
            result.Apply(false, false);
            RenderTexture.active = previous;

            result.filterMode = FilterMode.Point;
            result.wrapMode = TextureWrapMode.Clamp;

            if (isNew)
                AssetDatabase.CreateAsset(result, OutputPath);

            EditorUtility.SetDirty(result);
            AssetDatabase.SaveAssets();

            read.Release();
            write.Release();
            Object.DestroyImmediate(read);
            Object.DestroyImmediate(write);

            Debug.Log(
                $"Jump Flood completed with {passCount} passes.");
        }
    }
}