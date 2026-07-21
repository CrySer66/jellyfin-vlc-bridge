using System.Text.Json;
using Microsoft.Win32;

namespace JellyfinVlcBridge.Core;

public sealed record BridgeHealthStatus(
    string Version,
    string ConfigPath,
    bool Configured,
    string? ServerUrl,
    bool SecretReady,
    bool JellyfinConnected,
    string? JellyfinUser,
    string JellyfinMessage,
    bool VlcReady,
    string? VlcPath,
    string? VlcVersion,
    bool ProtocolReady,
    bool NativeMessagingReady,
    bool ExtensionActive,
    string? ExtensionVersion,
    DateTimeOffset? ExtensionLastSeenUtc,
    string PlaybackMode,
    string LogPath);

public static class BridgeDiagnostics
{
    public static async Task<BridgeHealthStatus> CheckAsync(CancellationToken cancellationToken = default)
    {
        BridgeConfig? config = null;
        try { config = BridgeConfig.Load(); }
        catch (Exception exception)
        {
            return Empty("Configuration absente ou invalide : " + exception.Message);
        }

        var token = new EnvironmentOrWindowsCredentialStore().Read(SecretKeys.ForServer(config.ServerUrl));
        var secretReady = !string.IsNullOrWhiteSpace(token);
        var vlcPath = VlcLauncher.Resolve(config.VlcPath);
        var vlcReady = File.Exists(vlcPath) || !OperatingSystem.IsWindows();
        var vlcVersion = GetVlcVersion(vlcPath);
        var jellyfinConnected = false;
        string? jellyfinUser = null;
        var jellyfinMessage = secretReady ? "Serveur non joignable." : "Connexion Jellyfin absente.";

        if (secretReady)
        {
            try
            {
                using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
                var user = await new JellyfinClient(http, config.ServerUrl, token!, config.DeviceId)
                    .GetCurrentUserAsync(cancellationToken);
                jellyfinConnected = true;
                jellyfinUser = user.Name;
                jellyfinMessage = $"Connecté en tant que {user.Name}.";
            }
            catch (Exception exception) when (exception is HttpRequestException or TaskCanceledException)
            {
                jellyfinMessage = "Serveur injoignable : " + exception.Message;
            }
            catch (Exception exception)
            {
                jellyfinMessage = "Connexion refusée : " + exception.Message;
            }
        }

        var protocolReady = false;
        var nativeMessagingReady = false;
        var heartbeat = ExtensionHeartbeat.Read();
        var extensionActive = ExtensionHeartbeat.IsActive(heartbeat);
        if (OperatingSystem.IsWindows())
        {
            using (var protocol = Registry.CurrentUser.OpenSubKey(@"Software\Classes\jellyfin-vlc\shell\open\command"))
                protocolReady = !string.IsNullOrWhiteSpace(protocol?.GetValue(null)?.ToString());

            using var host = Registry.CurrentUser.OpenSubKey(
                @"Software\Google\Chrome\NativeMessagingHosts\local.jellyfin_vlc_bridge");
            var manifestPath = host?.GetValue(null)?.ToString();
            nativeMessagingReady = IsValidNativeManifest(manifestPath);
        }

        return new BridgeHealthStatus(
            BridgeVersion.Current, BridgeConfig.DefaultPath, true, config.ServerUrl, secretReady,
            jellyfinConnected, jellyfinUser, jellyfinMessage, vlcReady, vlcPath, vlcVersion,
            protocolReady, nativeMessagingReady, extensionActive, heartbeat?.Version,
            heartbeat?.LastSeenUtc, config.PlaybackMode, BridgeLog.FilePath);
    }

    private static bool IsValidNativeManifest(string? path)
    {
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path)) return false;
        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(path));
            var root = document.RootElement;
            var executable = root.GetProperty("path").GetString();
            var origins = root.GetProperty("allowed_origins").EnumerateArray()
                .Select(value => value.GetString()).Where(value => value is not null).ToHashSet();
            return !string.IsNullOrWhiteSpace(executable) && File.Exists(executable) &&
                BridgeLinks.AllowedExtensionIds.All(id => origins.Contains($"chrome-extension://{id}/"));
        }
        catch { return false; }
    }

    private static string? GetVlcVersion(string? path)
    {
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path)) return null;
        try
        {
            var info = System.Diagnostics.FileVersionInfo.GetVersionInfo(path);
            return string.IsNullOrWhiteSpace(info.ProductVersion) ? info.FileVersion : info.ProductVersion;
        }
        catch { return null; }
    }

    private static BridgeHealthStatus Empty(string message) => new(
        BridgeVersion.Current, BridgeConfig.DefaultPath, false, null, false, false, null,
        message, false, null, null, false, false, false, null, null, "http", BridgeLog.FilePath);
}
