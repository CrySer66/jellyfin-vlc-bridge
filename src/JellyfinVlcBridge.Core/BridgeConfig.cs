using System.Text.Json;

namespace JellyfinVlcBridge.Core;

public sealed record PathMapping(string ServerPrefix, string ClientPrefix);

public sealed record BridgeConfig
{
    public string ServerUrl { get; init; } = "";
    public string UserId { get; init; } = "";
    public string DeviceId { get; init; } = "";
    public string? VlcPath { get; init; }
    public string PlaybackMode { get; init; } = "http";
    public List<PathMapping> PathMappings { get; init; } = [];
    public bool ProgressSyncEnabled { get; init; } = true;

    public static string DefaultPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "JellyfinVlcBridge", "config.json");

    public static BridgeConfig Load(string? path = null)
    {
        path ??= DefaultPath;
        if (!File.Exists(path))
            throw new FileNotFoundException("Configuration absente. Lancez d'abord la commande configure.", path);
        return JsonSerializer.Deserialize<BridgeConfig>(File.ReadAllText(path), JsonOptions)
            ?? throw new InvalidDataException("Configuration invalide.");
    }

    public void Save(string? path = null)
    {
        path ??= DefaultPath;
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, JsonSerializer.Serialize(this, JsonOptions));
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true
    };
}
