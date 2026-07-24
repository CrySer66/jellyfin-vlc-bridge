using System.Globalization;
using System.Text.Json;

namespace JellyfinVlcBridge.Core;

public static class UiLanguage
{
    public static string PreferencePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "JellyfinVlcBridge",
        "ui-language.json");

    public static string GetPreference()
    {
        try
        {
            if (!File.Exists(PreferencePath)) return "auto";
            using var document = JsonDocument.Parse(File.ReadAllText(PreferencePath));
            var value = document.RootElement.GetProperty("language").GetString();
            return value is "en" or "fr" ? value : "auto";
        }
        catch
        {
            return "auto";
        }
    }

    public static string GetEffectiveLanguage(string? preference = null)
    {
        preference ??= GetPreference();
        if (preference is "en" or "fr") return preference;
        return CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "fr" ? "fr" : "en";
    }

    public static string Text(string english, string french) =>
        GetEffectiveLanguage() == "fr" ? french : english;
}
