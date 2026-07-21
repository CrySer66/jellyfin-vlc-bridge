using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json.Serialization;

namespace JellyfinVlcBridge.Core;

public sealed class VlcController : IDisposable
{
    private readonly HttpClient _http;

    public VlcController(VlcControlOptions options)
    {
        _http = new HttpClient { BaseAddress = new Uri($"http://127.0.0.1:{options.Port}/"), Timeout = TimeSpan.FromSeconds(3) };
        _http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic",
            Convert.ToBase64String(Encoding.UTF8.GetBytes(":" + options.Password)));
    }

    public async Task<VlcStatus> WaitUntilReadyAsync(TimeSpan timeout, CancellationToken cancellationToken = default)
    {
        var deadline = DateTime.UtcNow + timeout;
        Exception? lastError = null;
        while (DateTime.UtcNow < deadline)
        {
            try { return await GetStatusAsync(cancellationToken); }
            catch (Exception exception) when (exception is HttpRequestException or TaskCanceledException)
            {
                lastError = exception;
                await Task.Delay(300, cancellationToken);
            }
        }
        throw new TimeoutException("L'interface de suivi VLC n'a pas démarré.", lastError);
    }

    public async Task<VlcStatus> GetStatusAsync(CancellationToken cancellationToken = default) =>
        await _http.GetFromJsonAsync<VlcStatus>("requests/status.json", cancellationToken)
        ?? throw new InvalidDataException("État VLC vide.");

    public void Dispose() => _http.Dispose();
}

public sealed record VlcStatus(
    [property: JsonPropertyName("state")] string State,
    [property: JsonPropertyName("time")] long Time,
    [property: JsonPropertyName("length")] long Length,
    [property: JsonPropertyName("volume")] int Volume,
    [property: JsonPropertyName("currentplid")] int CurrentPlaylistId = -1)
{
    public bool IsPaused => State.Equals("paused", StringComparison.OrdinalIgnoreCase);
    public long PositionTicks => Math.Max(0, Time) * TimeSpan.TicksPerSecond;
    public long DurationTicks => Math.Max(0, Length) * TimeSpan.TicksPerSecond;
}
