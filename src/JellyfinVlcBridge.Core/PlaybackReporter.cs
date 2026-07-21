namespace JellyfinVlcBridge.Core;

// Seam for the next milestone: a VLC status source will feed this reporter,
// which will call Jellyfin's Sessions/Playing, Progress and Stopped endpoints.
public interface IPlaybackReporter
{
    Task StartedAsync(string itemId, long positionTicks, CancellationToken cancellationToken = default);
    Task ProgressAsync(string itemId, long positionTicks, bool paused, CancellationToken cancellationToken = default);
    Task StoppedAsync(string itemId, long positionTicks, CancellationToken cancellationToken = default);
}
