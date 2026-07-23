using System.Net.Http.Json;
using System.Text.Json.Serialization;

namespace JellyfinVlcBridge.Core;

public sealed class JellyfinClient(
    HttpClient http,
    string serverUrl,
    string token,
    string? deviceId = null,
    TimeSpan? requestTimeout = null)
{
    private const string ClientName = "Jellyfin VLC Bridge";
    private const string ClientVersion = BridgeVersion.Current;
    private static readonly TimeSpan DefaultRequestTimeout = TimeSpan.FromSeconds(15);
    private readonly TimeSpan _requestTimeout = ValidateTimeout(requestTimeout);

    public async Task<QuickConnectResult> InitiateQuickConnectAsync(string deviceId, CancellationToken cancellationToken = default)
    {
        using var timeout = CreateRequestCancellation(cancellationToken);
        using var request = new HttpRequestMessage(HttpMethod.Post, $"{serverUrl.TrimEnd('/')}/QuickConnect/Initiate");
        AddClientAuthorization(request, deviceId);
        using var response = await http.SendAsync(request, timeout.Token);
        if (response.StatusCode == System.Net.HttpStatusCode.Unauthorized)
            throw new InvalidOperationException("Quick Connect est désactivé sur ce serveur Jellyfin.");
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<QuickConnectResult>(cancellationToken: timeout.Token)
            ?? throw new InvalidDataException("Jellyfin n'a pas fourni de code Quick Connect.");
    }

    public async Task<QuickConnectResult> GetQuickConnectStateAsync(string deviceId, string secret, CancellationToken cancellationToken = default)
    {
        using var timeout = CreateRequestCancellation(cancellationToken);
        using var request = new HttpRequestMessage(HttpMethod.Get,
            $"{serverUrl.TrimEnd('/')}/QuickConnect/Connect?secret={Uri.EscapeDataString(secret)}");
        AddClientAuthorization(request, deviceId);
        using var response = await http.SendAsync(request, timeout.Token);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<QuickConnectResult>(cancellationToken: timeout.Token)
            ?? throw new InvalidDataException("État Quick Connect vide.");
    }

    public async Task<AuthenticationResult> AuthenticateWithQuickConnectAsync(string deviceId, string secret, CancellationToken cancellationToken = default)
    {
        using var timeout = CreateRequestCancellation(cancellationToken);
        using var request = new HttpRequestMessage(HttpMethod.Post,
            $"{serverUrl.TrimEnd('/')}/Users/AuthenticateWithQuickConnect");
        AddClientAuthorization(request, deviceId);
        request.Content = JsonContent.Create(new { Secret = secret });
        using var response = await http.SendAsync(request, timeout.Token);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<AuthenticationResult>(cancellationToken: timeout.Token)
            ?? throw new InvalidDataException("Authentification Quick Connect vide.");
    }

    private static void AddClientAuthorization(HttpRequestMessage request, string deviceId)
    {
        var deviceName = Environment.MachineName.Replace("\"", "");
        request.Headers.TryAddWithoutValidation("Authorization",
            $"MediaBrowser Client=\"{ClientName}\", Device=\"{deviceName}\", DeviceId=\"{deviceId}\", Version=\"{ClientVersion}\"");
    }

    public async Task<IReadOnlyList<UserInfo>> GetUsersAsync(CancellationToken cancellationToken = default)
    {
        using var timeout = CreateRequestCancellation(cancellationToken);
        using var request = new HttpRequestMessage(HttpMethod.Get, $"{serverUrl.TrimEnd('/')}/Users");
        request.Headers.TryAddWithoutValidation("X-Emby-Token", token);
        using var response = await http.SendAsync(request, timeout.Token);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<List<UserInfo>>(cancellationToken: timeout.Token)
            ?? [];
    }

    public Task<UserInfo> GetCurrentUserAsync(CancellationToken cancellationToken = default) =>
        GetAuthenticatedAsync<UserInfo>("Users/Me", cancellationToken);

    public async Task<ItemInfo> GetItemAsync(string userId, string itemId, CancellationToken cancellationToken = default)
    {
        var path = $"Users/{Uri.EscapeDataString(userId)}/Items/{Uri.EscapeDataString(itemId)}?Fields=Path,MediaSources";
        return await GetAuthenticatedAsync<ItemInfo>(path, cancellationToken);
    }

    public async Task<IReadOnlyList<ItemInfo>> GetEpisodesAsync(
        string userId,
        string seriesId,
        string? seasonId = null,
        CancellationToken cancellationToken = default)
    {
        var path = $"Shows/{Uri.EscapeDataString(seriesId)}/Episodes" +
            $"?UserId={Uri.EscapeDataString(userId)}" +
            "&Fields=Path,MediaSources&EnableUserData=true";
        if (!string.IsNullOrWhiteSpace(seasonId))
            path += $"&SeasonId={Uri.EscapeDataString(seasonId)}";
        var result = await GetAuthenticatedAsync<ItemQueryResult>(path, cancellationToken);
        return result.Items ?? [];
    }

    public async Task<ItemInfo?> GetNextUpEpisodeAsync(
        string userId,
        string seriesId,
        CancellationToken cancellationToken = default)
    {
        var path = "Shows/NextUp" +
            $"?UserId={Uri.EscapeDataString(userId)}" +
            $"&SeriesId={Uri.EscapeDataString(seriesId)}" +
            "&Limit=1&Fields=Path,MediaSources&EnableUserData=true" +
            "&DisableFirstEpisode=false&EnableResumable=true";
        var result = await GetAuthenticatedAsync<ItemQueryResult>(path, cancellationToken);
        return result.Items?.FirstOrDefault();
    }

    public async Task<IReadOnlyList<ItemInfo>> GetCollectionItemsAsync(
        string userId,
        string collectionId,
        CancellationToken cancellationToken = default)
    {
        var path = $"Users/{Uri.EscapeDataString(userId)}/Items" +
            $"?ParentId={Uri.EscapeDataString(collectionId)}" +
            "&Recursive=true&IncludeItemTypes=Movie,Video" +
            "&SortBy=SortName&SortOrder=Ascending" +
            "&Fields=Path,MediaSources&EnableUserData=true";
        var result = await GetAuthenticatedAsync<ItemQueryResult>(path, cancellationToken);
        return result.Items ?? [];
    }

    public Task ReportPlaybackStartedAsync(string itemId, string? mediaSourceId, string playSessionId, long positionTicks, CancellationToken cancellationToken = default) =>
        ReportAsync("Sessions/Playing", new
        {
            CanSeek = true,
            ItemId = itemId,
            MediaSourceId = mediaSourceId,
            IsPaused = false,
            IsMuted = false,
            PositionTicks = positionTicks,
            PlayMethod = "DirectPlay",
            PlaySessionId = playSessionId
        }, cancellationToken);

    public Task ReportPlaybackProgressAsync(string itemId, string? mediaSourceId, string playSessionId, long positionTicks, bool paused, int? volume, CancellationToken cancellationToken = default) =>
        ReportAsync("Sessions/Playing/Progress", new
        {
            CanSeek = true,
            ItemId = itemId,
            MediaSourceId = mediaSourceId,
            IsPaused = paused,
            IsMuted = volume == 0,
            PositionTicks = positionTicks,
            VolumeLevel = volume,
            PlayMethod = "DirectPlay",
            PlaySessionId = playSessionId
        }, cancellationToken);

    public Task ReportPlaybackStoppedAsync(string itemId, string? mediaSourceId, string playSessionId, long positionTicks, bool failed, CancellationToken cancellationToken = default) =>
        ReportAsync("Sessions/Playing/Stopped", new
        {
            ItemId = itemId,
            MediaSourceId = mediaSourceId,
            PositionTicks = positionTicks,
            PlaySessionId = playSessionId,
            Failed = failed
        }, cancellationToken);

    private async Task ReportAsync(string path, object body, CancellationToken cancellationToken)
    {
        using var timeout = CreateRequestCancellation(cancellationToken);
        using var request = new HttpRequestMessage(HttpMethod.Post, $"{serverUrl.TrimEnd('/')}/{path}");
        AddAuthenticatedHeaders(request);
        request.Content = JsonContent.Create(body);
        using var response = await http.SendAsync(request, timeout.Token);
        response.EnsureSuccessStatusCode();
    }

    private async Task<T> GetAuthenticatedAsync<T>(string path, CancellationToken cancellationToken)
    {
        using var timeout = CreateRequestCancellation(cancellationToken);
        using var request = new HttpRequestMessage(HttpMethod.Get, $"{serverUrl.TrimEnd('/')}/{path}");
        AddAuthenticatedHeaders(request);
        using var response = await http.SendAsync(request, timeout.Token);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<T>(cancellationToken: timeout.Token)
            ?? throw new InvalidDataException("Réponse Jellyfin vide.");
    }

    private CancellationTokenSource CreateRequestCancellation(CancellationToken cancellationToken)
    {
        var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(_requestTimeout);
        return timeout;
    }

    private static TimeSpan ValidateTimeout(TimeSpan? timeout)
    {
        var value = timeout ?? DefaultRequestTimeout;
        if (value <= TimeSpan.Zero || value == Timeout.InfiniteTimeSpan)
            throw new ArgumentOutOfRangeException(nameof(timeout), "Le délai réseau doit être positif et limité.");
        return value;
    }

    private void AddAuthenticatedHeaders(HttpRequestMessage request)
    {
        request.Headers.TryAddWithoutValidation("X-Emby-Token", token);
        if (!string.IsNullOrWhiteSpace(deviceId))
        {
            var machine = Environment.MachineName.Replace("\"", "");
            request.Headers.TryAddWithoutValidation("X-Emby-Authorization",
                $"MediaBrowser Client=\"{ClientName}\", Device=\"{machine}\", DeviceId=\"{deviceId}\", Version=\"{ClientVersion}\", Token=\"{token}\"");
        }
    }
}

public sealed record UserInfo(
    [property: JsonPropertyName("Id")] string Id,
    [property: JsonPropertyName("Name")] string Name);

public sealed record QuickConnectResult(
    [property: JsonPropertyName("Authenticated")] bool Authenticated,
    [property: JsonPropertyName("Secret")] string Secret,
    [property: JsonPropertyName("Code")] string Code);

public sealed record AuthenticationResult(
    [property: JsonPropertyName("AccessToken")] string? AccessToken,
    [property: JsonPropertyName("User")] UserInfo? User);

public sealed record ItemInfo(
    [property: JsonPropertyName("Id")] string Id,
    [property: JsonPropertyName("Name")] string? Name,
    [property: JsonPropertyName("Path")] string? Path,
    [property: JsonPropertyName("MediaSources")] List<MediaSourceInfo>? MediaSources,
    [property: JsonPropertyName("UserData")] UserItemData? UserData,
    [property: JsonPropertyName("Type")] string? Type = null,
    [property: JsonPropertyName("SeriesId")] string? SeriesId = null,
    [property: JsonPropertyName("SeasonId")] string? SeasonId = null,
    [property: JsonPropertyName("ParentIndexNumber")] int? ParentIndexNumber = null,
    [property: JsonPropertyName("IndexNumber")] int? IndexNumber = null,
    [property: JsonPropertyName("RunTimeTicks")] long? RunTimeTicks = null);

public sealed record ItemQueryResult(
    [property: JsonPropertyName("Items")] List<ItemInfo>? Items,
    [property: JsonPropertyName("TotalRecordCount")] int TotalRecordCount = 0);

public sealed record MediaSourceInfo(
    [property: JsonPropertyName("Id")] string? Id,
    [property: JsonPropertyName("Path")] string? Path);

public sealed record UserItemData(
    [property: JsonPropertyName("PlaybackPositionTicks")] long PlaybackPositionTicks,
    [property: JsonPropertyName("Played")] bool Played);
