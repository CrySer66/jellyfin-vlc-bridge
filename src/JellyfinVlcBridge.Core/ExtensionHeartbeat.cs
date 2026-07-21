using System.Security.Cryptography;
using System.Text;
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
        => Record(FilePath, extensionId, version);

    internal static void Record(string filePath, string extensionId, string? version)
    {
        if (!BridgeLinks.AllowedExtensionIds.Contains(extensionId))
            throw new InvalidDataException("Identifiant d'extension non autorise.");

        var safeVersion = string.IsNullOrWhiteSpace(version) || version.Length > 32
            ? "inconnue"
            : version.Trim();
        string? temporary = null;
        var ownsMutex = false;
        using var mutex = new Mutex(false, GetMutexName(filePath));

        try
        {
            try { ownsMutex = mutex.WaitOne(TimeSpan.FromSeconds(2)); }
            catch (AbandonedMutexException) { ownsMutex = true; }
            if (!ownsMutex)
            {
                BridgeLog.Warning("Impossible d'enregistrer le signal de l'extension : fichier momentanement occupe.");
                return;
            }

            var state = new ExtensionHeartbeatState(extensionId, safeVersion, DateTimeOffset.UtcNow);
            var directory = Path.GetDirectoryName(filePath)!;
            Directory.CreateDirectory(directory);
            temporary = filePath + ".tmp-" + Guid.NewGuid().ToString("N");
            File.WriteAllText(temporary, JsonSerializer.Serialize(state));
            File.Move(temporary, filePath, true);
            temporary = null;
            DeleteStaleTemporaryFiles(filePath);
        }
        catch (IOException exception)
        {
            BridgeLog.Warning("Impossible d'enregistrer le signal de l'extension : " + exception.Message);
        }
        catch (UnauthorizedAccessException exception)
        {
            BridgeLog.Warning("Impossible d'enregistrer le signal de l'extension : " + exception.Message);
        }
        finally
        {
            if (temporary is not null)
            {
                try { File.Delete(temporary); }
                catch { }
            }
            if (ownsMutex) mutex.ReleaseMutex();
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

    private static string GetMutexName(string filePath)
    {
        var normalized = Path.GetFullPath(filePath).ToUpperInvariant();
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(normalized)));
        return @"Local\JellyfinVlcBridge.ExtensionHeartbeat." + hash[..16];
    }

    private static void DeleteStaleTemporaryFiles(string filePath)
    {
        var directory = Path.GetDirectoryName(filePath);
        if (string.IsNullOrWhiteSpace(directory) || !Directory.Exists(directory)) return;
        var threshold = DateTime.UtcNow.AddMinutes(-2);
        foreach (var temporary in Directory.EnumerateFiles(directory, Path.GetFileName(filePath) + ".tmp-*"))
        {
            try
            {
                if (File.GetLastWriteTimeUtc(temporary) < threshold) File.Delete(temporary);
            }
            catch { }
        }
    }
}
