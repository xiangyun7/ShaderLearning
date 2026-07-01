using System.IO;
using Unity.Collections;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

public static class CloudNoiseBaker
{
    private const int TextureSize = 64;
    private const string ComputePath = "Assets/Editor/GenerateNoise.compute";
    private const string SavePath = "Assets/Texture/VolumeCloudNoise.asset";

    private static readonly int CloudTexId = Shader.PropertyToID("_CloudTex");
    private static readonly int TextureSizeId = Shader.PropertyToID("_TextureSize");

    [MenuItem("Tools/Volume Cloud/Bake Noise Texture3D")]
    public static void BakeNoiseTexture3D()
    {
        ComputeShader compute = AssetDatabase.LoadAssetAtPath<ComputeShader>(ComputePath);
        if (compute == null)
        {
            Debug.LogError($"Cannot find compute shader: {ComputePath}");
            return;
        }

        RenderTexture volumeNoise = CreateVolumeRenderTexture();

        int kernel = compute.FindKernel("GenerateCloudNoise");
        compute.SetInt(TextureSizeId, TextureSize);
        compute.SetTexture(kernel, CloudTexId, volumeNoise);

        int groups = Mathf.CeilToInt(TextureSize / 8.0f);
        compute.Dispatch(kernel, groups, groups, groups);

        SaveRenderTextureAsTexture3D(volumeNoise, SavePath);
    }

    private static RenderTexture CreateVolumeRenderTexture()
    {
        RenderTexture rt = new RenderTexture(TextureSize, TextureSize, 0, RenderTextureFormat.ARGB32)
        {
            dimension = TextureDimension.Tex3D,
            volumeDepth = TextureSize,
            enableRandomWrite = true,
            wrapMode = TextureWrapMode.Repeat,
            filterMode = FilterMode.Bilinear,
            name = "VolumeCloudNoiseBakeRT"
        };

        rt.Create();
        return rt;
    }

    private static void SaveRenderTextureAsTexture3D(RenderTexture rt, string savePath)
    {
        int voxelCount = rt.width * rt.height * rt.volumeDepth;
        NativeArray<Color32> data = new NativeArray<Color32>(voxelCount, Allocator.Persistent);

        AsyncGPUReadback.RequestIntoNativeArray(ref data, rt, 0, request =>
        {
            try
            {
                if (request.hasError)
                {
                    Debug.LogError("GPU readback failed when baking volume cloud noise.");
                    return;
                }

                NormalizeRedChannel(data);
                NormalizeGreenChannel(data);

                Texture3D texture = new Texture3D(rt.width, rt.height, rt.volumeDepth, TextureFormat.RGBA32, false)
                {
                    wrapMode = TextureWrapMode.Repeat,
                    filterMode = FilterMode.Bilinear,
                    name = "VolumeCloudNoise"
                };

                texture.SetPixelData(data, 0);
                texture.Apply(false, false);

                SaveTextureAsset(texture, savePath);
                Debug.Log($"Volume cloud noise saved: {savePath}");
            }
            finally
            {
                if (data.IsCreated)
                    data.Dispose();

                rt.Release();
                Object.DestroyImmediate(rt);
            }
        });
    }

    private static void NormalizeRedChannel(NativeArray<Color32> data)
    {
        byte minR = byte.MaxValue;
        byte maxR = byte.MinValue;

        for (int i = 0; i < data.Length; i++)
        {
            byte r = data[i].r;
            if (r < minR) minR = r;
            if (r > maxR) maxR = r;
        }

        if (maxR <= minR)
        {
            Debug.LogWarning($"Cannot normalize red channel. minR={minR}, maxR={maxR}");
            return;
        }

        float range = maxR - minR;

        for (int i = 0; i < data.Length; i++)
        {
            Color32 color = data[i];
            byte normalizedR = (byte)Mathf.RoundToInt((color.r - minR) / range * 255.0f);
            data[i] = new Color32(normalizedR, color.g, color.b, color.a);
        }

        Debug.Log($"Normalize red channel: {minR / 255.0f:F3} - {maxR / 255.0f:F3} -> 0.000 - 1.000");
    }

    private static void NormalizeGreenChannel(NativeArray<Color32> data)
    {
        byte minG = byte.MaxValue;
        byte maxG = byte.MinValue;

        for (int i = 0; i < data.Length; i++)
        {
            byte g = data[i].g;
            if (g < minG) minG = g;
            if (g > maxG) maxG = g;
        }

        if (maxG <= minG)
        {
            Debug.LogWarning($"Cannot normalize green channel. minG={minG}, maxG={maxG}");
            return;
        }

        float range = maxG - minG;

        for (int i = 0; i < data.Length; i++)
        {
            Color32 color = data[i];
            byte normalizedG = (byte)Mathf.RoundToInt((color.g - minG) / range * 255.0f);
            data[i] = new Color32(color.r, normalizedG, color.b, color.a);
        }

        Debug.Log($"Normalize green channel: {minG / 255.0f:F3} - {maxG / 255.0f:F3} -> 0.000 - 1.000");
    }

    private static void SaveTextureAsset(Texture3D texture, string savePath)
    {
        string folder = Path.GetDirectoryName(savePath)?.Replace("\\", "/");
        if (!string.IsNullOrEmpty(folder) && !AssetDatabase.IsValidFolder(folder))
        {
            Directory.CreateDirectory(folder);
            AssetDatabase.Refresh();
        }

        Texture3D existing = AssetDatabase.LoadAssetAtPath<Texture3D>(savePath);
        if (existing == null)
        {
            AssetDatabase.CreateAsset(texture, savePath);
        }
        else
        {
            EditorUtility.CopySerialized(texture, existing);
            Object.DestroyImmediate(texture);
        }

        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();
    }
}