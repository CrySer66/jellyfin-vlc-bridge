using System.Text.Json;
using System.Text;

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
        var config = JsonSerializer.Deserialize<BridgeConfig>(File.ReadAllText(path), JsonOptions)
            ?? throw new InvalidDataException("Configuration invalide.");
        return config.Validate();
    }

    public void Save(string? path = null)
    {
        path ??= DefaultPath;
        var validated = Validate();
        var fullPath = Path.GetFullPath(path);
        var directory = Path.GetDirectoryName(fullPath)
            ?? throw new InvalidOperationException("Dossier de configuration invalide.");
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

    public BridgeConfig Validate()
    {
        var serverUrl = ServerAddress.Normalize(ServerUrl);
        var userId = UserId?.Trim();
        if (string.IsNullOrWhiteSpace(userId))
            throw new InvalidDataException("L'identifiant utilisateur Jellyfin est absent.");

        var playbackMode = PlaybackMode?.Trim().ToLowerInvariant();
        if (playbackMode is not ("http" or "smb"))
            throw new InvalidDataException("Le mode de lecture doit être http ou smb.");

        var mappings = PathMappings ?? [];
        if (playbackMode == "smb" && mappings.Count == 0)
            throw new InvalidDataException("Le mode SMB exige au moins une correspondance de dossiers.");
        if (mappings.Any(mapping => string.IsNullOrWhiteSpace(mapping.ServerPrefix) || string.IsNullOrWhiteSpace(mapping.ClientPrefix)))
            throw new InvalidDataException("Une correspondance SMB contient un chemin vide.");

        return this with
        {
            ServerUrl = serverUrl,
            UserId = userId,
            DeviceId = DeviceId?.Trim() ?? "",
            PlaybackMode = playbackMode,
            VlcPath = string.IsNullOrWhiteSpace(VlcPath) ? null : VlcPath.Trim(),
            PathMappings = mappings
        };
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true
    };
}
