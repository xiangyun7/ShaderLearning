using ShaderLearning.Coastline;
using UnityEditor;
using UnityEngine;

namespace ShaderLearning.Coastline.Editor
{
    public sealed class CoastlineBakerWindow : EditorWindow
    {
        private Terrain terrain;
        private CoastlineBakeAsset bakeAsset;

        [MenuItem("Tools/Coastline Baking/Baker")]
        private static void Open()
        {
            GetWindow<CoastlineBakerWindow>("Coastline Baker");
        }

        private void OnGUI()
        {
            terrain = (Terrain)EditorGUILayout.ObjectField(
                "Terrain", terrain, typeof(Terrain), true);

            bakeAsset = (CoastlineBakeAsset)EditorGUILayout.ObjectField(
                "Bake Asset", bakeAsset,
                typeof(CoastlineBakeAsset), false);

            bool ready = terrain != null && bakeAsset != null;

            using (new EditorGUI.DisabledScope(!ready))
            {
                if (GUILayout.Button("Prepare Bake Domain"))
                    PrepareBakeDomain();
                if (GUILayout.Button("Bake Ground Height Map"))
                    CoastlineHeightBaker.Bake(terrain, bakeAsset);
                if (GUILayout.Button("Bake Land/Sea Mask"))
                    CoastlineMaskBaker.Bake(bakeAsset);
                if (GUILayout.Button("Extract Coastline Seeds"))
                    CoastlineSeedBaker.Bake(bakeAsset);
                if (GUILayout.Button("Run Jump Flood"))
                    CoastlineJumpFloodBaker.Bake(bakeAsset);
                if (GUILayout.Button("Build Final Coastline Map"))
                    CoastlineFinalizeBaker.Bake(bakeAsset);
            }
        }

        private void PrepareBakeDomain()
        {
            if (!Mathf.IsPowerOfTwo(bakeAsset.Resolution))
            {
                Debug.LogError("Resolution must be a power of two.");
                return;
            }

            Bounds localBounds = terrain.terrainData.bounds;

            bakeAsset.Bounds = new Bounds(
                terrain.transform.TransformPoint(localBounds.center),
                Vector3.Scale(
                    localBounds.size,
                    terrain.transform.lossyScale));

            EditorUtility.SetDirty(bakeAsset);
            AssetDatabase.SaveAssets();

            Debug.Log($"Coastline domain prepared: {bakeAsset.Bounds}");
        }
    }
}
