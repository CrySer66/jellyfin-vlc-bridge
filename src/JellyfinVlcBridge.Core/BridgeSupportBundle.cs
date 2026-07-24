using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace JellyfinVlcBridge.Core;

public sealed record BridgeSupportBundleResult(
    string Path,
    DateTimeOffset CreatedAtUtc,
    IReadOnlyList<string> Entries);

public static partial class BridgeSupportBundle
{
    private const int MaximumLogCharacters = 400_000;

    public static async Task<BridgeSupportBundleResult> CreateAsync(
        string outputPath,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(outputPath))
            throw new ArgumentException("Le chemin du paquet d’assistance est absent.", nameof(outputPath));

        var fullPath = Path.GetFullPath(outputPath);
        if (!string.Equals(Path.GetExtension(fullPath), ".zip", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Le paquet d’assistance doit utiliser l’extension .zip.");

        var parent = Path.GetDirectoryName(fullPath)
            ?? throw new InvalidDataException("Le dossier du paquet d’assistance est invalide.");
        Directory.CreateDirectory(parent);

        var status = await BridgeDiagnostics.CheckAsync(cancellationToken);
        BridgeConfig? config = null;
        string? token = null;
        try
        {
            config = BridgeConfig.Load();
            token = new EnvironmentOrWindowsCredentialStore().Read(SecretKeys.ForServer(config.ServerUrl));
        }
        catch { }

        var createdAt = DateTimeOffset.UtcNow;
        var entries = new List<string>();
        var temporary = fullPath + ".tmp-" + Guid.NewGuid().ToString("N");
        try
        {
            await using (var stream = new FileStream(
                temporary, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.None, 4096, true))
            using (var archive = new ZipArchive(stream, ZipArchiveMode.Create, false, Encoding.UTF8))
            {
                var safeStatus = new
                {
                    createdAtUtc = createdAt,
                    bridgeVersion = status.Version,
                    operatingSystem = RuntimeInformation.OSDescription,
                    osArchitecture = RuntimeInformation.OSArchitecture.ToString(),
                    processArchitecture = RuntimeInformation.ProcessArchitecture.ToString(),
                    configured = status.Configured,
                    secretReady = status.SecretReady,
                    jellyfinConnected = status.JellyfinConnected,
                    vlcReady = status.VlcReady,
                    vlcVersion = status.VlcVersion,
                    protocolReady = status.ProtocolReady,
                    nativeMessagingReady = status.NativeMessagingReady,
                    extensionActive = status.ExtensionActive,
                    extensionVersion = status.ExtensionVersion,
                    extensionLastSeenUtc = status.ExtensionLastSeenUtc,
                    playbackMode = status.PlaybackMode,
                    ready = status.Ready,
                    findings = status.Findings
                };
                AddText(
                    archive,
                    entries,
                    "diagnostic.json",
                    JsonSerializer.Serialize(safeStatus, new JsonSerializerOptions { WriteIndented = true }));
                AddText(archive, entries, "diagnostic.txt", SafeSummary(status, createdAt));

                foreach (var logPath in new[]
                {
                    BridgeLog.FilePath,
                    System.IO.Path.Combine(BridgeLog.DirectoryPath, "bridge.previous.log")
                })
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    if (!File.Exists(logPath)) continue;
                    var content = await ReadSharedTextAsync(logPath, cancellationToken);
                    content = Tail(content, MaximumLogCharacters);
                    content = Sanitize(content, config, token);
                    AddText(archive, entries, "logs/" + System.IO.Path.GetFileName(logPath), content);
                }
            }

            File.Move(temporary, fullPath, true);
            return new BridgeSupportBundleResult(fullPath, createdAt, entries);
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

    internal static string Sanitize(string value, BridgeConfig? config, string? token)
    {
        var sanitized = value;
        foreach (var secret in new[]
        {
            token,
            config?.ServerUrl,
            config?.UserId,
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            Environment.UserName
        }.Where(item => !string.IsNullOrWhiteSpace(item) && item!.Length >= 4)
         .OrderByDescending(item => item!.Length))
        {
            sanitized = sanitized.Replace(
                secret!,
                secret == Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
                    ? "%USERPROFILE%"
                    : "<REDACTED>",
                StringComparison.OrdinalIgnoreCase);
        }

        sanitized = AuthorizationRegex().Replace(sanitized, "$1<REDACTED>");
        sanitized = TokenQueryRegex().Replace(sanitized, "$1<REDACTED>");
        sanitized = LongIdentifierRegex().Replace(sanitized, "<ID>");
        sanitized = QuotedWindowsPathRegex().Replace(sanitized, "\"%WINDOWS_PATH%\"");
        sanitized = WindowsPathRegex().Replace(sanitized, "%WINDOWS_PATH%");
        sanitized = NetworkPathRegex().Replace(sanitized, "%NETWORK_PATH%");
        return sanitized;
    }

    private static string SafeSummary(BridgeHealthStatus status, DateTimeOffset createdAt)
    {
        var lines = new List<string>
        {
            $"Jellyfin VLC Bridge {status.Version}",
            $"Created UTC: {createdAt:O}",
            $"Windows: {RuntimeInformation.OSDescription}",
            $"Architecture: {RuntimeInformation.OSArchitecture}",
            $"Configured: {status.Configured}",
            $"Jellyfin connected: {status.JellyfinConnected}",
            $"VLC detected: {status.VlcReady}",
            $"VLC version: {status.VlcVersion ?? "unknown"}",
            $"Browser integration: {status.ProtocolReady && status.NativeMessagingReady}",
            $"Extension active: {status.ExtensionActive}",
            $"Extension version: {status.ExtensionVersion ?? "unknown"}",
            $"Playback mode: {status.PlaybackMode}",
            $"Ready: {status.Ready}"
        };
        foreach (var finding in status.Findings)
        {
            lines.Add($"[{finding.Severity}] {finding.Code}: {finding.Message}");
            lines.Add($"Action: {finding.Action}");
        }
        return string.Join(Environment.NewLine, lines) + Environment.NewLine;
    }

    private static async Task<string> ReadSharedTextAsync(string path, CancellationToken cancellationToken)
    {
        await using var stream = new FileStream(
            path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete, 4096, true);
        using var reader = new StreamReader(stream, Encoding.UTF8, true);
        return await reader.ReadToEndAsync(cancellationToken);
    }

    private static string Tail(string value, int maximumCharacters) =>
        value.Length <= maximumCharacters ? value : value[^maximumCharacters..];

    private static void AddText(
        ZipArchive archive,
        ICollection<string> entries,
        string name,
        string content)
    {
        var entry = archive.CreateEntry(name, CompressionLevel.Optimal);
        using var writer = new StreamWriter(entry.Open(), new UTF8Encoding(false));
        writer.Write(content);
        entries.Add(name);
    }

    [GeneratedRegex(@"(?im)\b(authorization\s*:\s*(?:bearer\s+)?)[^\s,;]+")]
    private static partial Regex AuthorizationRegex();

    [GeneratedRegex(@"(?i)([?&](?:api_key|access_token|token)=)[^&\s]+")]
    private static partial Regex TokenQueryRegex();

    [GeneratedRegex(@"\b[0-9a-fA-F]{24,64}\b")]
    private static partial Regex LongIdentifierRegex();

    [GeneratedRegex("(?i)\"[a-z]:\\\\[^\"\\r\\n]*\"")]
    private static partial Regex QuotedWindowsPathRegex();

    [GeneratedRegex(@"(?i)\b[a-z]:\\[^\r\n,;]*")]
    private static partial Regex WindowsPathRegex();

    [GeneratedRegex(@"\\\\[^\\\s]+\\[^\r\n,;]*")]
    private static partial Regex NetworkPathRegex();
}
