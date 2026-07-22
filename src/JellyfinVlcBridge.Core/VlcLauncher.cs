using System.Diagnostics;

namespace JellyfinVlcBridge.Core;

public static class VlcLauncher
{
    public static string Resolve(string? configuredPath)
    {
        if (!string.IsNullOrWhiteSpace(configuredPath) && File.Exists(configuredPath)) return configuredPath;
        if (OperatingSystem.IsWindows())
        {
            var candidates = new[]
            {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "VideoLAN", "VLC", "vlc.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "VideoLAN", "VLC", "vlc.exe")
            };
            var found = candidates.FirstOrDefault(File.Exists);
            if (found is not null) return found;
        }
        if (OperatingSystem.IsMacOS() && File.Exists("/Applications/VLC.app/Contents/MacOS/VLC"))
            return "/Applications/VLC.app/Contents/MacOS/VLC";
        return "vlc";
    }

    public static Process Start(string executable, string media, TimeSpan? startAt = null, VlcControlOptions? control = null)
    {
        return StartPlaylist(executable, [new VlcLaunchItem(media, startAt)], control);
    }

    public static Process StartPlaylist(string executable, IReadOnlyList<VlcLaunchItem> media, VlcControlOptions? control = null)
    {
        if (media.Count == 0) throw new ArgumentException("La liste de lecture VLC est vide.", nameof(media));
        var info = new ProcessStartInfo(executable) { UseShellExecute = false };
        info.ArgumentList.Add("--no-one-instance");
        info.ArgumentList.Add("--play-and-exit");
        if (control is not null)
        {
            info.ArgumentList.Add("--extraintf=http");
            info.ArgumentList.Add("--http-host=127.0.0.1");
            info.ArgumentList.Add($"--http-port={control.Port}");
            info.ArgumentList.Add($"--http-password={control.Password}");
        }
        foreach (var item in media)
        {
            info.ArgumentList.Add(item.Media);
            if (item.StartAt is { TotalSeconds: > 0 })
                info.ArgumentList.Add($":start-time={item.StartAt.Value.TotalSeconds:0}");
        }
        return Process.Start(info) ?? throw new InvalidOperationException("VLC n'a pas pu être lancé.");
    }
}

public sealed record VlcLaunchItem(string Media, TimeSpan? StartAt = null);

public sealed record VlcControlOptions(int Port, string Password)
{
    public static VlcControlOptions Create() => new(
        FreeTcpPort(),
        Convert.ToHexString(System.Security.Cryptography.RandomNumberGenerator.GetBytes(24)));

    private static int FreeTcpPort()
    {
        var listener = new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
        try
        {
            listener.Start();
            return ((System.Net.IPEndPoint)listener.LocalEndpoint).Port;
        }
        finally { listener.Stop(); }
    }
}
