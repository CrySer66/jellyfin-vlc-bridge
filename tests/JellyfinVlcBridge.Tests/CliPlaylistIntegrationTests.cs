using System.Net;
using System.Reflection;
using System.Text;
using System.Text.Json;
using JellyfinVlcBridge.Core;

internal static class CliPlaylistIntegrationTests
{
    public static async Task RunAsync()
    {
        // Exercise the real CLI loop with a local fake VLC process. Configuration,
        // credentials and the user's installed player are never read or changed.
        var cli = Assembly.Load("jellyfin-vlc-bridge");
        var playbackMediaType = cli.GetType("PlaybackMedia")!;
        var playlist = Array.CreateInstance(playbackMediaType, 3);
        for (var index = 0; index < 3; index++)
            playlist.SetValue(Activator.CreateInstance(playbackMediaType,
                new ItemInfo($"test-episode-{index}", $"Test {index}", null, [], null),
                null, $"http://127.0.0.1:1234/test-{index}", null), index);

        var method = cli.GetType("Program")!.GetMethods(BindingFlags.Static | BindingFlags.NonPublic)
            .Single(method => method.Name.Contains("g__RunVlcPlaylistWithSyncAsync|", StringComparison.Ordinal));
        var fakePlayer = Path.Combine(AppContext.BaseDirectory,
            OperatingSystem.IsWindows() ? "JellyfinVlcBridge.Tests.exe" : "JellyfinVlcBridge.Tests");
        using var reports = new PlaybackReportHandler();
        using var http = new HttpClient(reports);
        var jellyfin = new JellyfinClient(http, "http://test.invalid", "test-token", "test-device");
        var started = 0;
        Func<Task> onStarted = () => { started++; return Task.CompletedTask; };
        var originalRuntimeRoot = Environment.GetEnvironmentVariable("DOTNET_ROOT");
        try
        {
            // Keep the fake child runnable when the SDK itself lives in a
            // portable workspace rather than in the machine-wide installation.
            if (string.IsNullOrWhiteSpace(originalRuntimeRoot))
                Environment.SetEnvironmentVariable("DOTNET_ROOT", Path.GetFullPath(Path.Combine(
                    Path.GetDirectoryName(typeof(object).Assembly.Location)!, "..", "..", "..")));
            var task = (Task)method.Invoke(null, [fakePlayer, playlist, jellyfin, onStarted])!;
            await task.WaitAsync(TimeSpan.FromSeconds(40));
        }
        finally { Environment.SetEnvironmentVariable("DOTNET_ROOT", originalRuntimeRoot); }
        Equal("1", started.ToString());

        var starts = reports.Events.Where(item => item.Path == "/Sessions/Playing").ToArray();
        Equal("test-episode-0,test-episode-2,test-episode-1,test-episode-0,test-episode-2",
            string.Join(',', starts.Select(item => item.ItemId)));
        Equal("5", starts.Select(item => item.SessionId).Distinct().Count().ToString());
        var stops = reports.Events.Where(item => item.Path == "/Sessions/Playing/Stopped").ToArray();
        Equal("12,25,5,42,30", string.Join(',', stops.Select(item => item.PositionTicks / TimeSpan.TicksPerSecond)));
        foreach (var progress in reports.Events.Where(item => item.Path == "/Sessions/Playing/Progress"))
            if (!starts.Any(start => start.ItemId == progress.ItemId && start.SessionId == progress.SessionId))
                throw new InvalidOperationException("Progression attribuée à une session inconnue.");
    }

    public static async Task<int> RunFakeVlcAsync(string[] args)
    {
        var port = int.Parse(args.Single(arg => arg.StartsWith("--http-port=", StringComparison.Ordinal)).Split('=')[1]);
        var password = args.Single(arg => arg.StartsWith("--http-password=", StringComparison.Ordinal)).Split('=')[1];
        var expectedAuthorization = "Basic " + Convert.ToBase64String(Encoding.UTF8.GetBytes(":" + password));
        using var listener = new HttpListener();
        listener.Prefixes.Add($"http://127.0.0.1:{port}/");
        listener.Start();
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(35));
        var states = new[]
        {
            (Id: 4, Time: 12, State: "playing"),
            (Id: -1, Time: 0, State: "stopped"), // VLC's transition must not clear the old position.
            (Id: 11, Time: 25, State: "playing"), // Skip to episode three.
            (Id: 7, Time: 5, State: "playing"),   // Previous to episode two.
            (Id: 4, Time: 42, State: "playing"),  // Previous to episode one.
            (Id: 90, Time: 8, State: "playing"),  // User added a foreign media item.
            (Id: 11, Time: 30, State: "playing")  // Return to a known episode.
        };
        var nextState = 0;
        try
        {
            while (!timeout.IsCancellationRequested)
            {
                var context = await listener.GetContextAsync().WaitAsync(timeout.Token);
                if (context.Request.Headers["Authorization"] != expectedAuthorization)
                {
                    context.Response.StatusCode = 401;
                    context.Response.Close();
                    continue;
                }
                object payload;
                if (context.Request.Url!.AbsolutePath == "/requests/playlist.json")
                    payload = new { children = new[] { new { children = new[]
                    {
                        new { id = "4", uri = "http://127.0.0.1:1234/test-0" },
                        new { id = "7", uri = "http://127.0.0.1:1234/test-1" },
                        new { id = "11", uri = "http://127.0.0.1:1234/test-2" },
                        new { id = "90", uri = "http://127.0.0.1:1234/foreign" }
                    } } } };
                else
                {
                    var status = states[Math.Min(nextState++, states.Length - 1)];
                    payload = new { state = status.State, time = status.Time, length = 300, volume = 256, currentplid = status.Id };
                }
                var json = JsonSerializer.SerializeToUtf8Bytes(payload);
                context.Response.ContentType = "application/json";
                context.Response.ContentLength64 = json.Length;
                await context.Response.OutputStream.WriteAsync(json);
                context.Response.Close();
                if (nextState >= states.Length)
                {
                    await Task.Delay(200);
                    return 0;
                }
            }
        }
        catch (OperationCanceledException) { }
        return 1;
    }

    private static void Equal(string expected, string actual)
    {
        if (expected != actual) throw new InvalidOperationException($"Attendu : {expected}, obtenu : {actual}.");
    }

    private sealed record PlaybackReport(string Path, string ItemId, string SessionId, long PositionTicks);

    private sealed class PlaybackReportHandler : HttpMessageHandler
    {
        public List<PlaybackReport> Events { get; } = [];

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            using var json = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(cancellationToken));
            Events.Add(new PlaybackReport(request.RequestUri!.AbsolutePath,
                json.RootElement.GetProperty("itemId").GetString()!,
                json.RootElement.GetProperty("playSessionId").GetString()!,
                json.RootElement.GetProperty("positionTicks").GetInt64()));
            return new HttpResponseMessage(HttpStatusCode.NoContent);
        }
    }
}
