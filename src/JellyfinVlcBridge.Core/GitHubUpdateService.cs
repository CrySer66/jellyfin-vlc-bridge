using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace JellyfinVlcBridge.Core;

public sealed record UpdateCheckResult(
    string CurrentVersion,
    string LatestVersion,
    bool UpdateAvailable,
    string ReleaseUrl,
    string? DownloadUrl,
    string? AssetName,
    long? AssetSize);

public sealed record DownloadedUpdate(string Version, string Path, long Size);

public sealed class GitHubUpdateService(HttpClient http)
{
    private const long MaximumInstallerSize = 200L * 1024 * 1024;
    private static readonly Regex SetupName = new(
        @"^JellyfinVlcBridge-(?<version>\d+\.\d+\.\d+)-Setup\.exe$",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    public async Task<UpdateCheckResult> CheckAsync(CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, BridgeLinks.GitHubLatestReleaseApiUrl);
        request.Headers.UserAgent.ParseAdd($"Jellyfin-VLC-Bridge/{BridgeVersion.Current}");
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        request.Headers.TryAddWithoutValidation("X-GitHub-Api-Version", "2022-11-28");
        using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
            throw new InvalidOperationException("Les mises à jour seront disponibles après la publication du dépôt GitHub.");
        response.EnsureSuccessStatusCode();

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
        var root = document.RootElement;
        var tag = root.GetProperty("tag_name").GetString()?.Trim()
            ?? throw new InvalidDataException("La Release GitHub ne contient pas de version.");
        var latestText = tag.TrimStart('v', 'V');
        if (!Version.TryParse(latestText, out var latest) || latest.Build < 0)
            throw new InvalidDataException($"Version GitHub non reconnue : {tag}");
        if (!Version.TryParse(BridgeVersion.Current, out var current))
            throw new InvalidDataException("La version installée est invalide.");

        var releaseUrl = root.GetProperty("html_url").GetString() ?? BridgeLinks.GitHubRepositoryUrl + "/releases";
        ValidateGitHubUrl(releaseUrl, allowApi: false);
        string? downloadUrl = null;
        string? assetName = null;
        long? assetSize = null;
        foreach (var asset in root.GetProperty("assets").EnumerateArray())
        {
            var name = asset.GetProperty("name").GetString();
            if (name is null) continue;
            var match = SetupName.Match(name);
            if (!match.Success || !match.Groups["version"].Value.Equals(latestText, StringComparison.OrdinalIgnoreCase))
                continue;
            var candidate = asset.GetProperty("browser_download_url").GetString();
            if (string.IsNullOrWhiteSpace(candidate)) continue;
            ValidateGitHubUrl(candidate, allowApi: false);
            downloadUrl = candidate;
            assetName = name;
            assetSize = asset.TryGetProperty("size", out var size) ? size.GetInt64() : null;
            break;
        }

        var available = latest > current;
        if (available && downloadUrl is null)
            throw new InvalidDataException($"La Release {latestText} ne contient pas l'installateur Windows attendu.");
        if (assetSize is > MaximumInstallerSize)
            throw new InvalidDataException("L'installateur annoncé est anormalement volumineux.");
        return new UpdateCheckResult(
            BridgeVersion.Current, latestText, available, releaseUrl,
            downloadUrl, assetName, assetSize);
    }

    public async Task<DownloadedUpdate> DownloadLatestAsync(
        string destinationDirectory,
        CancellationToken cancellationToken = default)
    {
        var update = await CheckAsync(cancellationToken);
        if (!update.UpdateAvailable || update.DownloadUrl is null || update.AssetName is null)
            throw new InvalidOperationException("Jellyfin VLC Bridge est déjà à jour.");

        ValidateGitHubUrl(update.DownloadUrl, allowApi: false);
        Directory.CreateDirectory(destinationDirectory);
        var destination = Path.GetFullPath(Path.Combine(destinationDirectory, update.AssetName));
        var expectedRoot = Path.GetFullPath(destinationDirectory).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        if (!destination.StartsWith(expectedRoot, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Nom d'installateur GitHub non sûr.");

        using var request = new HttpRequestMessage(HttpMethod.Get, update.DownloadUrl);
        request.Headers.UserAgent.ParseAdd($"Jellyfin-VLC-Bridge/{BridgeVersion.Current}");
        using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        response.EnsureSuccessStatusCode();
        if (response.Content.Headers.ContentLength is > MaximumInstallerSize)
            throw new InvalidDataException("L'installateur téléchargé est anormalement volumineux.");

        await using (var input = await response.Content.ReadAsStreamAsync(cancellationToken))
        await using (var output = new FileStream(destination, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            var buffer = new byte[81920];
            long total = 0;
            while (true)
            {
                var read = await input.ReadAsync(buffer, cancellationToken);
                if (read == 0) break;
                total += read;
                if (total > MaximumInstallerSize)
                    throw new InvalidDataException("Le téléchargement dépasse la taille maximale autorisée.");
                await output.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
            }
        }

        var info = new FileInfo(destination);
        if (info.Length < 64 * 1024 || !HasPortableExecutableHeader(destination))
        {
            try { File.Delete(destination); } catch { }
            throw new InvalidDataException("Le fichier téléchargé n'est pas un installateur Windows valide.");
        }
        return new DownloadedUpdate(update.LatestVersion, destination, info.Length);
    }

    private static bool HasPortableExecutableHeader(string path)
    {
        using var stream = File.OpenRead(path);
        return stream.ReadByte() == 'M' && stream.ReadByte() == 'Z';
    }

    private static void ValidateGitHubUrl(string value, bool allowApi)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps)
            throw new InvalidDataException("Adresse de mise à jour non sécurisée.");
        var allowed = uri.Host.Equals("github.com", StringComparison.OrdinalIgnoreCase) ||
            (allowApi && uri.Host.Equals("api.github.com", StringComparison.OrdinalIgnoreCase));
        if (!allowed) throw new InvalidDataException("La mise à jour ne provient pas du dépôt GitHub officiel.");
        if (!uri.AbsolutePath.StartsWith("/cryser66/jellyfin-vlc-bridge/", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("La mise à jour ne correspond pas au dépôt officiel.");
    }
}
