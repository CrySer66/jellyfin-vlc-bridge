namespace JellyfinVlcBridge.Core;

public static class MediaSourceSelector
{
    public static MediaSourceInfo? Select(ItemInfo item, string? requestedId)
    {
        var sources = item.MediaSources ?? [];
        if (string.IsNullOrWhiteSpace(requestedId)) return sources.FirstOrDefault();

        return sources.FirstOrDefault(source =>
            string.Equals(source.Id, requestedId, StringComparison.Ordinal))
            ?? throw new InvalidDataException("La version de média sélectionnée n’est plus disponible dans Jellyfin.");
    }

    public static string Label(MediaSourceInfo source, int index)
    {
        if (!string.IsNullOrWhiteSpace(source.Name)) return source.Name.Trim();

        var video = source.MediaStreams?.FirstOrDefault(stream =>
            string.Equals(stream.Type, "Video", StringComparison.OrdinalIgnoreCase));
        var details = new List<string>();
        if (video?.Height is > 0)
            details.Add(video.Height >= 2160 ? "4K" : $"{video.Height}p");
        if (!string.IsNullOrWhiteSpace(video?.Codec))
            details.Add(video.Codec.ToUpperInvariant());
        if (!string.IsNullOrWhiteSpace(source.Container))
            details.Add(source.Container.ToUpperInvariant());
        if (details.Count > 0) return string.Join(" · ", details);

        if (!string.IsNullOrWhiteSpace(source.Path))
        {
            var fileName = Path.GetFileNameWithoutExtension(source.Path);
            if (!string.IsNullOrWhiteSpace(fileName)) return fileName;
        }

        return UiLanguage.Text($"Media version {index + 1}", $"Version du média {index + 1}");
    }
}
