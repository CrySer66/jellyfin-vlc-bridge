using System.Text.Json;
using Microsoft.Win32;

namespace JellyfinVlcBridge.Core;

public sealed record BridgeHealthFinding(
    string Component,
    string Code,
    string Severity,
    string Message,
    string Action);

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
    string LogPath,
    bool Ready,
    IReadOnlyList<BridgeHealthFinding> Findings);

public static class BridgeDiagnostics
{
    public static async Task<BridgeHealthStatus> CheckAsync(CancellationToken cancellationToken = default)
    {
        BridgeConfig? config = null;
        try { config = BridgeConfig.Load(); }
        catch (Exception exception)
        {
            return Empty(UiLanguage.Text(
                "Missing or invalid configuration: ",
                "Configuration absente ou invalide : ") + exception.Message);
        }

        var token = new EnvironmentOrWindowsCredentialStore().Read(SecretKeys.ForServer(config.ServerUrl));
        var secretReady = !string.IsNullOrWhiteSpace(token);
        var vlcPath = VlcLauncher.Resolve(config.VlcPath);
        var vlcReady = File.Exists(vlcPath) || !OperatingSystem.IsWindows();
        var vlcVersion = GetVlcVersion(vlcPath);
        var jellyfinConnected = false;
        string? jellyfinUser = null;
        var jellyfinCode = secretReady ? "jellyfin.unreachable" : "jellyfin.connection-missing";
        var jellyfinMessage = secretReady
            ? UiLanguage.Text("Server unreachable.", "Serveur non joignable.")
            : UiLanguage.Text("Jellyfin connection missing.", "Connexion Jellyfin absente.");

        if (secretReady)
        {
            try
            {
                using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
                var user = await new JellyfinClient(http, config.ServerUrl, token!, config.DeviceId)
                    .GetCurrentUserAsync(cancellationToken);
                jellyfinConnected = true;
                jellyfinUser = user.Name;
                jellyfinCode = "jellyfin.ready";
                jellyfinMessage = UiLanguage.Text(
                    $"Connected as {user.Name}.",
                    $"Connecté en tant que {user.Name}.");
            }
            catch (TaskCanceledException exception)
            {
                jellyfinCode = "jellyfin.timeout";
                jellyfinMessage = UiLanguage.Text("Server response timed out: ", "Délai de réponse du serveur dépassé : ") + exception.Message;
            }
            catch (HttpRequestException exception)
            {
                jellyfinCode = "jellyfin.unreachable";
                jellyfinMessage = UiLanguage.Text("Server unreachable: ", "Serveur injoignable : ") + exception.Message;
            }
            catch (Exception exception)
            {
                jellyfinCode = "jellyfin.connection-refused";
                jellyfinMessage = UiLanguage.Text("Connection refused: ", "Connexion refusée : ") + exception.Message;
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

        var findings = new List<BridgeHealthFinding>();
        if (!secretReady)
            findings.Add(Finding(
                "jellyfin", "jellyfin.connection-missing", "error",
                "The saved Jellyfin connection is missing.",
                "La connexion Jellyfin enregistrée est absente.",
                "Run the installer and authorize a new Quick Connect code.",
                "Relancez l’installateur et autorisez un nouveau code Quick Connect."));
        else if (!jellyfinConnected)
            findings.Add(Finding(
                "jellyfin", jellyfinCode, "error",
                "Jellyfin could not be contacted with the saved connection.",
                "Jellyfin ne répond pas avec la connexion enregistrée.",
                "Check the server address and network, then try again. Change server only if the address is wrong.",
                "Vérifiez l’adresse et le réseau, puis réessayez. Changez de serveur uniquement si l’adresse est incorrecte."));

        if (!vlcReady)
        {
            var configuredPathMissing = !string.IsNullOrWhiteSpace(config.VlcPath);
            findings.Add(Finding(
                "vlc",
                configuredPathMissing ? "vlc.configured-path-missing" : "vlc.not-found",
                "error",
                configuredPathMissing ? "The configured VLC path no longer exists." : "VLC was not found on this PC.",
                configuredPathMissing ? "Le chemin VLC enregistré n’existe plus." : "VLC est introuvable sur ce PC.",
                "Select the installed vlc.exe in Playback settings.",
                "Sélectionnez le fichier vlc.exe installé dans les réglages de lecture."));
        }

        if (!protocolReady || !nativeMessagingReady)
            findings.Add(Finding(
                "browser", "browser.integration-missing", "error",
                "The Windows connection with the browser is incomplete.",
                "La connexion Windows avec le navigateur est incomplète.",
                "Select Repair, then fully reload Jellyfin.",
                "Cliquez sur Réparer, puis rechargez complètement Jellyfin."));
        else if (!extensionActive)
            findings.Add(Finding(
                "browser", "browser.extension-inactive", "warning",
                "The extension has not contacted the Bridge recently.",
                "L’extension n’a pas contacté le Bridge récemment.",
                "Open a Jellyfin page and reload it, then refresh this diagnostic.",
                "Ouvrez une page Jellyfin et rechargez-la, puis actualisez ce diagnostic."));

        var ready = jellyfinConnected && vlcReady && protocolReady &&
            nativeMessagingReady && extensionActive;
        return new BridgeHealthStatus(
            BridgeVersion.Current, BridgeConfig.DefaultPath, true, config.ServerUrl, secretReady,
            jellyfinConnected, jellyfinUser, jellyfinMessage, vlcReady, vlcPath, vlcVersion,
            protocolReady, nativeMessagingReady, extensionActive, heartbeat?.Version,
            heartbeat?.LastSeenUtc, config.PlaybackMode, BridgeLog.FilePath, ready, findings);
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

    private static BridgeHealthFinding Finding(
        string component,
        string code,
        string severity,
        string englishMessage,
        string frenchMessage,
        string englishAction,
        string frenchAction) => new(
            component,
            code,
            severity,
            UiLanguage.Text(englishMessage, frenchMessage),
            UiLanguage.Text(englishAction, frenchAction));

    private static BridgeHealthStatus Empty(string message) => new(
        BridgeVersion.Current, BridgeConfig.DefaultPath, false, null, false, false, null,
        message, false, null, null, false, false, false, null, null, "http", BridgeLog.FilePath,
        false,
        [
            Finding(
                "configuration", "configuration.invalid", "error",
                "The local configuration is missing or invalid.",
                "La configuration locale est absente ou invalide.",
                "Run the installer and complete Quick Connect again.",
                "Relancez l’installateur et terminez de nouveau Quick Connect.")
        ]);
}
