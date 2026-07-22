namespace JellyfinVlcBridge.Core;

public static class PlaybackQueueResolver
{
    public static async Task<IReadOnlyList<ItemInfo>> ResolveAsync(
        JellyfinClient jellyfin,
        string userId,
        ItemInfo selected,
        CancellationToken cancellationToken = default)
    {
        if (selected.Type?.Equals("Series", StringComparison.OrdinalIgnoreCase) == true)
        {
            var episodes = Playable(await jellyfin.GetEpisodesAsync(userId, selected.Id, cancellationToken: cancellationToken));
            var nextUp = await jellyfin.GetNextUpEpisodeAsync(userId, selected.Id, cancellationToken);
            return FromPreferredStart(episodes, nextUp?.Id);
        }

        if (selected.Type?.Equals("Season", StringComparison.OrdinalIgnoreCase) == true &&
            !string.IsNullOrWhiteSpace(selected.SeriesId))
        {
            var episodes = Playable(await jellyfin.GetEpisodesAsync(userId, selected.SeriesId, selected.Id, cancellationToken));
            return FromPreferredStart(episodes, PreferredLocalStart(episodes)?.Id);
        }

        if (selected.Type?.Equals("Episode", StringComparison.OrdinalIgnoreCase) == true &&
            !string.IsNullOrWhiteSpace(selected.SeriesId))
        {
            var episodes = Playable(await jellyfin.GetEpisodesAsync(userId, selected.SeriesId, cancellationToken: cancellationToken));
            var queue = FromPreferredStart(episodes, selected.Id);
            return queue.Count > 0 ? queue : [selected];
        }

        if (selected.Type?.Equals("BoxSet", StringComparison.OrdinalIgnoreCase) == true)
        {
            var items = Playable(await jellyfin.GetCollectionItemsAsync(userId, selected.Id, cancellationToken));
            return FromPreferredStart(items, PreferredLocalStart(items)?.Id);
        }

        return [selected];
    }

    public static bool ShouldContinue(long positionTicks, long durationTicks, bool failed)
    {
        if (failed || durationTicks <= 0 || positionTicks < 0) return false;
        var remaining = durationTicks - positionTicks;
        return remaining <= TimeSpan.FromSeconds(90).Ticks || positionTicks >= durationTicks * 0.95;
    }

    private static List<ItemInfo> Playable(IReadOnlyList<ItemInfo> episodes) => episodes
        .Where(item => !string.IsNullOrWhiteSpace(item.Path) || item.MediaSources?.Count > 0)
        .ToList();

    private static ItemInfo? PreferredLocalStart(IReadOnlyList<ItemInfo> episodes) =>
        episodes.FirstOrDefault(item => item.UserData is { PlaybackPositionTicks: > 0 }) ??
        episodes.FirstOrDefault(item => item.UserData?.Played != true) ??
        episodes.FirstOrDefault();

    private static IReadOnlyList<ItemInfo> FromPreferredStart(IReadOnlyList<ItemInfo> episodes, string? preferredId)
    {
        if (episodes.Count == 0) return [];
        var index = string.IsNullOrWhiteSpace(preferredId)
            ? -1
            : episodes.ToList().FindIndex(item => item.Id.Equals(preferredId, StringComparison.OrdinalIgnoreCase));
        if (index < 0)
        {
            var fallback = PreferredLocalStart(episodes);
            index = fallback is null ? 0 : episodes.ToList().FindIndex(item => item.Id == fallback.Id);
        }
        return episodes.Skip(Math.Max(0, index)).ToList();
    }
}
