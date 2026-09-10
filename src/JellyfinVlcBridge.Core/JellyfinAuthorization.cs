using System.Net.Http.Headers;

namespace JellyfinVlcBridge.Core;

internal static class JellyfinAuthorization
{
    public static void Add(HttpRequestMessage request, string? token, string? deviceId = null)
    {
        var parameters = new List<string>();
        if (!string.IsNullOrWhiteSpace(deviceId))
        {
            parameters.Add(Parameter("Client", "Jellyfin VLC Bridge"));
            parameters.Add(Parameter("Device", Environment.MachineName));
            parameters.Add(Parameter("DeviceId", deviceId));
            parameters.Add(Parameter("Version", BridgeVersion.Current));
        }
        if (token is not null)
            parameters.Add(Parameter("Token", token));

        // Supported by Jellyfin 10.x and 12; the X-Emby-* headers are disabled in 12.
        request.Headers.Authorization = new AuthenticationHeaderValue("MediaBrowser", string.Join(", ", parameters));
    }

    private static string Parameter(string name, string value) =>
        $"{name}=\"{Uri.EscapeDataString(value)}\"";
}
