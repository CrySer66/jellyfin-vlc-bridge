using System.Globalization;
using System.Text.Json;

namespace JellyfinVlcBridge.Core;

public sealed class VlcPlaylistSnapshot
{
    private readonly Dictionary<int, string> _mediaById = [];

    private VlcPlaylistSnapshot() { }

    internal static VlcPlaylistSnapshot Parse(JsonElement root)
    {
        var result = new VlcPlaylistSnapshot();
        result.AddEntries(root);
        return result;
    }

    public int FindMediaIndex(int playlistId, IReadOnlyList<string> media)
    {
        if (!_mediaById.TryGetValue(playlistId, out var current)) return -1;
        var match = -1;
        for (var index = 0; index < media.Count; index++)
        {
            if (!SameMedia(current, media[index])) continue;
            // Ambiguous or foreign items must not update another Jellyfin item.
            if (match >= 0) return -1;
            match = index;
        }
        return match;
    }

    private void AddEntries(JsonElement node)
    {
        // VLC 3 returns nested nodes; VLC 4 returns a flat array of leaves.
        if (node.ValueKind == JsonValueKind.Array)
        {
            foreach (var child in node.EnumerateArray()) AddEntries(child);
            return;
        }
        if (node.ValueKind != JsonValueKind.Object) return;
        if (node.TryGetProperty("children", out var children)) AddEntries(children);
        if (!node.TryGetProperty("id", out var id) ||
            !node.TryGetProperty("uri", out var uri) || uri.ValueKind != JsonValueKind.String)
            return;
        var idText = id.ValueKind == JsonValueKind.String ? id.GetString() : id.GetRawText();
        if (int.TryParse(idText, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value) &&
            value >= 0 && !string.IsNullOrWhiteSpace(uri.GetString()))
            _mediaById[value] = uri.GetString()!;
    }

    private static bool SameMedia(string left, string right)
    {
        if (string.Equals(left, right, StringComparison.Ordinal)) return true;
        if (!Uri.TryCreate(left, UriKind.Absolute, out var leftUri) ||
            !Uri.TryCreate(right, UriKind.Absolute, out var rightUri)) return false;
        if (leftUri.IsFile && rightUri.IsFile)
            return string.Equals(leftUri.LocalPath, rightUri.LocalPath,
                OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal);
        return leftUri.Equals(rightUri);
    }
}
