using UnityEditor;
using UnityEngine;

public sealed class WaterDebugModeDrawer : MaterialPropertyDrawer
{
    private enum WaterDebugMode
    {
        Original = 0,
        Refraction = 1,
        Reflection = 2,
        Scattering = 3,
        Specular = 4,
        Foam = 5,
        ShorelineU = 6,
        ShorelineV = 7
    }

    public override void OnGUI(
        Rect position,
        MaterialProperty property,
        string label,
        MaterialEditor editor)
    {
        EditorGUI.showMixedValue = property.hasMixedValue;

        WaterDebugMode currentMode =
            (WaterDebugMode)Mathf.RoundToInt(property.floatValue);

        EditorGUI.BeginChangeCheck();
        WaterDebugMode selectedMode =
            (WaterDebugMode)EditorGUI.EnumPopup(
                position,
                new GUIContent(label),
                currentMode);

        if (EditorGUI.EndChangeCheck())
        {
            property.floatValue = (float)selectedMode;
        }

        EditorGUI.showMixedValue = false;
    }
}
