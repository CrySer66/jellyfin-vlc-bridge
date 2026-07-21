using System.Text.Json;

namespace JellyfinVlcBridge.Core;

public sealed record ExtensionHeartbeatState(string ExtensionId, string Version, DateTimeOffset LastSeenUtc);

public static class ExtensionHeartbeat
{
    public static readonly TimeSpan ActiveWindow = TimeSpan.FromSeconds(50);

    public static string FilePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "JellyfinVlcBridge", "extension-heartbeat.json");

    public static void Record(string extensionId, string? version)
    {
        if (!BridgeLinks.AllowedExtensionIds.Contains(extensionId))
            throw new InvalidDataException("Identifiant d'extension non autorisé.");
        var safeVersion = string.IsNullOrWhiteSpace(version) || version.Length > 32 ? "inconnue" : version.Trim();
        try
        {
            var state = new ExtensionHeartbeatState(extensionId, safeVersion, DateTimeOffset.UtcNow);
            var directory = Path.GetDirectoryName(FilePath)!;
            Directory.CreateDirectory(directory);
            var temporary = FilePath + ".tmp-" + Guid.NewGuid().ToString("N");
            File.WriteAllText(temporary, JsonSerializer.Serialize(state));
            File.Move(temporary, FilePath, true);
        }
        catch (IOException exception)
        {
            BridgeLog.Warning("Impossible d'enregistrer le signal de l'extension : " + exception.Message);
        }
        catch (UnauthorizedAccessException exception)
        {
            BridgeLog.Warning("Impossible d'enregistrer le signal de l'extension : " + exception.Message);
        }
    }

    public static ExtensionHeartbeatState? Read()
    {
        try
        {
            if (!File.Exists(FilePath)) return null;
            return JsonSerializer.Deserialize<ExtensionHeartbeatState>(File.ReadAllText(FilePath));
        }
        catch { return null; }
    }

    public static bool IsActive(ExtensionHeartbeatState? state, DateTimeOffset? now = null) =>
        state is not null &&
        BridgeLinks.AllowedExtensionIds.Contains(state.ExtensionId) &&
        (now ?? DateTimeOffset.UtcNow) - state.LastSeenUtc <= ActiveWindow &&
        state.LastSeenUtc <= (now ?? DateTimeOffset.UtcNow) + TimeSpan.FromSeconds(5);
}
