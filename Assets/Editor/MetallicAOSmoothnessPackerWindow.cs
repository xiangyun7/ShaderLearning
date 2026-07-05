using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEngine;

public sealed class MetallicAOSmoothnessPackerWindow : EditorWindow
{
    private const string WindowTitle = "AOSmoothness Packer";
    private const string TextureRootPath = "Assets/Texture";
    private const string OutputSuffix = "AOSmoothness.png";

    [SerializeField] private Texture2D metallicTexture;
    [SerializeField] private Texture2D aoTexture;
    [SerializeField] private Texture2D roughnessTexture;

    private Vector2 scrollPosition;

    [MenuItem("Tools/Texture/Pack Metallic AO Smoothness")]
    private static void OpenWindow()
    {
        MetallicAOSmoothnessPackerWindow window = GetWindow<MetallicAOSmoothnessPackerWindow>(false, WindowTitle);
        window.minSize = new Vector2(420f, 210f);
        window.Show();
    }

    private void OnGUI()
    {
        using (EditorGUILayout.ScrollViewScope scope = new EditorGUILayout.ScrollViewScope(scrollPosition))
        {
            scrollPosition = scope.scrollPosition;

            EditorGUILayout.Space(8f);
            EditorGUIUtility.labelWidth = 140f;

            metallicTexture = (Texture2D)EditorGUILayout.ObjectField(
                new GUIContent("Metallic Texture", "Required. Red channel is written to output R."),
                metallicTexture,
                typeof(Texture2D),
                false);

            aoTexture = (Texture2D)EditorGUILayout.ObjectField(
                new GUIContent("AO Texture", "Optional. Red channel is written to output G. Empty writes 1."),
                aoTexture,
                typeof(Texture2D),
                false);

            roughnessTexture = (Texture2D)EditorGUILayout.ObjectField(
                new GUIContent("Roughness Texture", "Optional. Red channel is inverted and written to output A."),
                roughnessTexture,
                typeof(Texture2D),
                false);

            EditorGUILayout.Space(8f);
            EditorGUILayout.HelpBox("Output: R=Metallic, G=AO, B=0, A=1-Roughness. Target folder is found under Assets/Texture by the Metallic filename prefix before the first underscore.", MessageType.Info);

            EditorGUILayout.Space(8f);
            using (new EditorGUI.DisabledScope(metallicTexture == null))
            {
                if (GUILayout.Button("Pack RGBA PNG", GUILayout.Height(32f)))
                {
                    PackTextures();
                }
            }
        }
    }

    private void PackTextures()
    {
        if (!TryBuildOutputPaths(out string outputAssetPath, out string outputFullPath))
        {
            return;
        }

        if (File.Exists(outputFullPath) && !EditorUtility.DisplayDialog(
                "Overwrite Texture",
                $"The output texture already exists:\n{outputAssetPath}\n\nOverwrite it?",
                "Overwrite",
                "Cancel"))
        {
            return;
        }

        List<ReadableTextureState> readableStates = new List<ReadableTextureState>();

        try
        {
            EditorUtility.DisplayProgressBar(WindowTitle, "Reading source textures...", 0.25f);

            Color32[] metallicPixels = GetPixelsWithTemporaryReadWrite(metallicTexture, readableStates);
            Color32[] aoPixels = aoTexture != null ? GetPixelsWithTemporaryReadWrite(aoTexture, readableStates) : null;
            Color32[] roughnessPixels = roughnessTexture != null ? GetPixelsWithTemporaryReadWrite(roughnessTexture, readableStates) : null;

            EditorUtility.DisplayProgressBar(WindowTitle, "Packing channels...", 0.55f);
            byte[] pngBytes = BuildPackedPng(metallicTexture.width, metallicTexture.height, metallicPixels, aoPixels, roughnessPixels);

            EditorUtility.DisplayProgressBar(WindowTitle, "Writing PNG...", 0.75f);
            File.WriteAllBytes(outputFullPath, pngBytes);
        }
        catch (Exception exception)
        {
            Debug.LogException(exception);
            EditorUtility.DisplayDialog("Pack Failed", exception.Message, "OK");
            return;
        }
        finally
        {
            RestoreReadWriteSettings(readableStates);
            EditorUtility.ClearProgressBar();
        }

        ImportAndSelectOutput(outputAssetPath);
    }

    private bool TryBuildOutputPaths(out string outputAssetPath, out string outputFullPath)
    {
        outputAssetPath = string.Empty;
        outputFullPath = string.Empty;

        if (!TryValidateInputTextures(out string validationError))
        {
            EditorUtility.DisplayDialog("Invalid Input", validationError, "OK");
            return false;
        }

        string metallicPath = AssetDatabase.GetAssetPath(metallicTexture);
        string metallicFileName = Path.GetFileNameWithoutExtension(metallicPath);

        if (!TryExtractAssetPrefix(metallicFileName, out string assetPrefix, out string prefixError))
        {
            EditorUtility.DisplayDialog("Invalid Metallic Name", prefixError, "OK");
            return false;
        }

        if (!TryFindTargetFolder(assetPrefix, out string targetFolder, out string folderError))
        {
            EditorUtility.DisplayDialog("Target Folder Not Found", folderError, "OK");
            return false;
        }

        outputAssetPath = NormalizeAssetPath(Path.Combine(targetFolder, metallicFileName + OutputSuffix));
        outputFullPath = GetProjectRelativeFullPath(outputAssetPath);
        return true;
    }

    private bool TryValidateInputTextures(out string error)
    {
        error = string.Empty;

        if (metallicTexture == null)
        {
            error = "Metallic Texture is required.";
            return false;
        }

        if (!TryValidateTextureAsset(metallicTexture, "Metallic Texture", out error))
        {
            return false;
        }

        if (aoTexture != null && !TryValidateTextureAsset(aoTexture, "AO Texture", out error))
        {
            return false;
        }

        if (roughnessTexture != null && !TryValidateTextureAsset(roughnessTexture, "Roughness Texture", out error))
        {
            return false;
        }

        if (aoTexture != null && !HasSameSize(metallicTexture, aoTexture))
        {
            error = $"AO Texture size ({aoTexture.width}x{aoTexture.height}) must match Metallic Texture size ({metallicTexture.width}x{metallicTexture.height}).";
            return false;
        }

        if (roughnessTexture != null && !HasSameSize(metallicTexture, roughnessTexture))
        {
            error = $"Roughness Texture size ({roughnessTexture.width}x{roughnessTexture.height}) must match Metallic Texture size ({metallicTexture.width}x{metallicTexture.height}).";
            return false;
        }

        return true;
    }

    private static bool TryValidateTextureAsset(Texture2D texture, string label, out string error)
    {
        error = string.Empty;

        string path = AssetDatabase.GetAssetPath(texture);
        if (string.IsNullOrEmpty(path))
        {
            error = $"{label} must be a texture asset from the Project window.";
            return false;
        }

        if (AssetImporter.GetAtPath(path) is not TextureImporter)
        {
            error = $"{label} is not imported by TextureImporter: {path}";
            return false;
        }

        return true;
    }

    private static bool TryExtractAssetPrefix(string metallicFileName, out string assetPrefix, out string error)
    {
        assetPrefix = string.Empty;
        error = string.Empty;

        int underscoreIndex = metallicFileName.IndexOf('_');
        if (underscoreIndex <= 0)
        {
            error = $"Metallic filename must contain an underscore with a non-empty prefix before it: {metallicFileName}";
            return false;
        }

        assetPrefix = metallicFileName.Substring(0, underscoreIndex);
        return true;
    }

    private static bool TryFindTargetFolder(string assetPrefix, out string targetFolder, out string error)
    {
        targetFolder = string.Empty;
        error = string.Empty;

        if (!AssetDatabase.IsValidFolder(TextureRootPath))
        {
            error = $"Texture root folder does not exist: {TextureRootPath}";
            return false;
        }

        string[] folderGuids = AssetDatabase.FindAssets("t:Folder", new[] { TextureRootPath });
        string[] matchingFolders = folderGuids
            .Select(AssetDatabase.GUIDToAssetPath)
            .Where(path => string.Equals(Path.GetFileName(path), assetPrefix, StringComparison.OrdinalIgnoreCase))
            .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
            .ToArray();

        if (matchingFolders.Length == 0)
        {
            error = $"No folder named '{assetPrefix}' was found under {TextureRootPath}.";
            return false;
        }

        targetFolder = matchingFolders[0];

        if (matchingFolders.Length > 1)
        {
            Debug.LogWarning($"Found {matchingFolders.Length} folders named '{assetPrefix}' under {TextureRootPath}. Using: {targetFolder}\nAll matches:\n{string.Join("\n", matchingFolders)}");
        }

        return true;
    }

    private static Color32[] GetPixelsWithTemporaryReadWrite(Texture2D texture, List<ReadableTextureState> readableStates)
    {
        string path = AssetDatabase.GetAssetPath(texture);
        TextureImporter importer = (TextureImporter)AssetImporter.GetAtPath(path);

        if (!importer.isReadable && !readableStates.Any(state => state.AssetPath == path))
        {
            readableStates.Add(new ReadableTextureState(path, importer.isReadable));
            importer.isReadable = true;
            importer.SaveAndReimport();
            texture = AssetDatabase.LoadAssetAtPath<Texture2D>(path);
        }

        return texture.GetPixels32();
    }

    private static byte[] BuildPackedPng(int width, int height, Color32[] metallicPixels, Color32[] aoPixels, Color32[] roughnessPixels)
    {
        int pixelCount = width * height;
        Color32[] packedPixels = new Color32[pixelCount];

        for (int i = 0; i < pixelCount; i++)
        {
            byte metallic = metallicPixels[i].r;
            byte ao = aoPixels != null ? aoPixels[i].r : byte.MaxValue;
            byte smoothness = roughnessPixels != null ? (byte)(byte.MaxValue - roughnessPixels[i].r) : byte.MaxValue;

            packedPixels[i] = new Color32(metallic, ao, 0, smoothness);
        }

        Texture2D outputTexture = new Texture2D(width, height, TextureFormat.RGBA32, false, true);
        try
        {
            outputTexture.SetPixels32(packedPixels);
            outputTexture.Apply(false, false);

            byte[] pngBytes = outputTexture.EncodeToPNG();
            if (pngBytes == null || pngBytes.Length == 0)
            {
                throw new InvalidOperationException("Unity failed to encode the packed texture as PNG.");
            }

            return pngBytes;
        }
        finally
        {
            DestroyImmediate(outputTexture);
        }
    }

    private static void RestoreReadWriteSettings(IEnumerable<ReadableTextureState> readableStates)
    {
        foreach (ReadableTextureState state in readableStates)
        {
            try
            {
                TextureImporter importer = AssetImporter.GetAtPath(state.AssetPath) as TextureImporter;
                if (importer == null || importer.isReadable == state.WasReadable)
                {
                    continue;
                }

                importer.isReadable = state.WasReadable;
                importer.SaveAndReimport();
            }
            catch (Exception exception)
            {
                Debug.LogError($"Failed to restore Read/Write setting for texture: {state.AssetPath}\n{exception}");
            }
        }
    }

    private static void ImportAndSelectOutput(string outputAssetPath)
    {
        AssetDatabase.ImportAsset(outputAssetPath, ImportAssetOptions.ForceSynchronousImport | ImportAssetOptions.ForceUpdate);

        TextureImporter outputImporter = AssetImporter.GetAtPath(outputAssetPath) as TextureImporter;
        if (outputImporter != null && outputImporter.sRGBTexture)
        {
            outputImporter.sRGBTexture = false;
            outputImporter.SaveAndReimport();
        }

        AssetDatabase.Refresh();

        Texture2D outputTexture = AssetDatabase.LoadAssetAtPath<Texture2D>(outputAssetPath);
        if (outputTexture != null)
        {
            Selection.activeObject = outputTexture;
            EditorGUIUtility.PingObject(outputTexture);
        }

        Debug.Log($"Packed texture saved: {outputAssetPath}");
        EditorUtility.DisplayDialog("Pack Complete", $"Saved to:\n{outputAssetPath}", "OK");
    }

    private static bool HasSameSize(Texture2D a, Texture2D b)
    {
        return a.width == b.width && a.height == b.height;
    }

    private static string NormalizeAssetPath(string path)
    {
        return path.Replace('\\', '/');
    }

    private static string GetProjectRelativeFullPath(string assetPath)
    {
        string projectRoot = Directory.GetParent(Application.dataPath).FullName;
        return Path.GetFullPath(Path.Combine(projectRoot, assetPath));
    }

    private readonly struct ReadableTextureState
    {
        public readonly string AssetPath;
        public readonly bool WasReadable;

        public ReadableTextureState(string assetPath, bool wasReadable)
        {
            AssetPath = assetPath;
            WasReadable = wasReadable;
        }
    }
}
