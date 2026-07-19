using UnityEngine;

namespace ShaderLearning.Coastline
{
    [CreateAssetMenu(
        fileName = "CoastlineBakeAsset",
        menuName = "Coastline Baking/Bake Asset")]
    public sealed class CoastlineBakeAsset : ScriptableObject
    {
        public const int CurrentVersion = 2;

        [Header("Generated Maps")]
        public Texture2D CoastlineMap;
        public Texture2D GroundHeightMap;

        [Header("Bake Domain")]
        public Bounds Bounds =
            new Bounds(Vector3.zero, new Vector3(500f, 100f, 500f));
        public float WaterLevel = -1f;
        [Min(0.01f)] public float MaxCoastDistance = 100f;
        [Min(16)] public int Resolution = 1024;

        [Header("Height Metadata")]
        public Vector2 HeightDecodeRange = new Vector2(0f, 1f);
        [Min(1)] public int Version = CurrentVersion;
    }
}
