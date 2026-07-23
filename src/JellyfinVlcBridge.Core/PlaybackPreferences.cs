using System.Text;
using System.Text.Json;

namespace JellyfinVlcBridge.Core;

public sealed record PlaybackPreferences
{
    private static readonly HashSet<string> AllowedItemTypes =
        new(StringComparer.OrdinalIgnoreCase) { "episode", "series", "season", "boxset", "movie", "video" };
    private static readonly HashSet<string> AllowedScopes =
        new(StringComparer.OrdinalIgnoreCase) { "single", "following", "all" };

    public bool RememberChoices { get; init; }
    public string StartMode { get; init; } = "resume";
    public Dictionary<string, string> Scopes { get; init; } = new(StringComparer.OrdinalIgnoreCase);

    public PlaybackPreferences Validate()
    {
        var startMode = StartMode?.Trim().ToLowerInvariant();
        if (startMode is not ("resume" or "restart"))
            throw new InvalidDataException("La préférence de point de départ est invalide.");

        var scopes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var (rawItemType, rawScope) in Scopes ?? [])
        {
            var itemType = NormalizeItemType(rawItemType);
            var scope = rawScope?.Trim().ToLowerInvariant();
            if (scope is null || !AllowedScopes.Contains(scope))
                throw new InvalidDataException("Une préférence d'étendue de lecture est invalide.");
            scopes[itemType] = scope;
        }

        return this with { StartMode = startMode, Scopes = scopes };
    }

    public PlaybackPreferences WithChoice(bool rememberChoices, string? startMode, string? itemType, string? scope)
    {
        if (!rememberChoices) return this with { RememberChoices = false };

        var normalizedType = NormalizeItemType(itemType);
        var normalizedScope = scope?.Trim().ToLowerInvariant();
        if (normalizedScope is null || !AllowedScopes.Contains(normalizedScope))
            throw new InvalidDataException("L'étendue de lecture à mémoriser est invalide.");

        var updatedScopes = new Dictionary<string, string>(Scopes ?? [], StringComparer.OrdinalIgnoreCase)
        {
            [normalizedType] = normalizedScope
        };
        return (this with
        {
            RememberChoices = true,
            StartMode = startMode?.Trim().ToLowerInvariant() ?? "resume",
            Scopes = updatedScopes
        }).Validate();
    }

    private static string NormalizeItemType(string? value)
    {
        var itemType = value?.Trim().ToLowerInvariant();
        if (itemType is null || !AllowedItemTypes.Contains(itemType))
            throw new InvalidDataException("Le type de média à mémoriser est invalide.");
        return itemType;
    }
}

public static class PlaybackPreferencesStore
{
    public static string DefaultPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "JellyfinVlcBridge", "playback-preferences.json");

    public static PlaybackPreferences Load(string? path = null)
    {
        path ??= DefaultPath;
        if (!File.Exists(path)) return new PlaybackPreferences();
        try
        {
            return (JsonSerializer.Deserialize<PlaybackPreferences>(File.ReadAllText(path), JsonOptions)
                ?? throw new InvalidDataException("Préférences de lecture invalides.")).Validate();
        }
        catch (JsonException exception)
        {
            throw new InvalidDataException("Préférences de lecture illisibles.", exception);
        }
    }

    public static PlaybackPreferences LoadOrDefault(string? path = null)
    {
        try { return Load(path); }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or InvalidDataException)
        {
            BridgeLog.Warning("Préférences de lecture ignorées : " + exception.Message);
            return new PlaybackPreferences();
        }
    }

    public static void Save(PlaybackPreferences preferences, string? path = null)
    {
        path ??= DefaultPath;
        var validated = preferences.Validate();
        var fullPath = Path.GetFullPath(path);
        var directory = Path.GetDirectoryName(fullPath)
            ?? throw new InvalidOperationException("Dossier de préférences invalide.");
        Directory.CreateDirectory(directory);
        var temporary = fullPath + ".tmp-" + Guid.NewGuid().ToString("N");
        try
        {
            File.WriteAllText(temporary, JsonSerializer.Serialize(validated, JsonOptions), new UTF8Encoding(false));
            File.Move(temporary, fullPath, true);
        }
        finally
        {
            if (File.Exists(temporary))
            {
                try { File.Delete(temporary); }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
            }
        }
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };
}
