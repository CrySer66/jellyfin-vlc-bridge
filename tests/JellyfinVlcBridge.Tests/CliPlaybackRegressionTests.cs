using System.Net;
using System.Reflection;
using System.Text;
using System.Text.Json;
using JellyfinVlcBridge.Core;

internal static class CliPlaybackRegressionTests
{
    private const string SingleTestMedia = "http://127.0.0.1:1234/single-stop-test";

    public static bool IsSingleTest(string[] args) => args.Contains(SingleTestMedia);

    public static async Task WithoutSyncAsync()
    {
        var directory = Path.Combine(Path.GetTempPath(), "JvbNoSyncTest-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        var config = new BridgeConfig
        {
            ServerUrl = "http://test.invalid", UserId = "test-user", PlaybackMode = "smb",
            PathMappings = [new("/media", directory)], ProgressSyncEnabled = false
        };
        using var handler = new ReportsHandler();
        using var http = new HttpClient(handler);
        var jellyfin = new JellyfinClient(http, config.ServerUrl, "fictional-token", "test-device");
        var started = 0;
        Func<Task> onStarted = () => { started++; return Task.CompletedTask; };
        try
        {
            using var runtime = new PortableRuntime();
            var single = new ItemInfo("single", "Single", "/media/capture-single", null, new UserItemData(42 * TimeSpan.TicksPerSecond, false));
            await Invoke("PlayResolvedItemAsync", FakePlayer(), config, "fictional-token", http, jellyfin, single, null, false, false, onStarted);
            var queue = new[]
            {
                single with { Id = "one", Path = "/media/capture-queue" },
                single with { Id = "two", Path = "/media/capture-next" }
            };
            await Invoke("PlayQueueAsync", FakePlayer(), config, "fictional-token", http, jellyfin, queue, false, onStarted);
            Equal(2, started);
            Equal(0, handler.Reports.Count);
            foreach (var name in new[] { "capture-single", "capture-queue" })
            {
                var arguments = JsonSerializer.Deserialize<string[]>(File.ReadAllText(Path.Combine(directory, name + ".launch.json")))!;
                Equal(false, arguments.Any(arg => arg.StartsWith("--http-", StringComparison.Ordinal) || arg == "--extraintf=http"));
                Equal(true, arguments.Contains(":start-time=42"));
            }
        }
        finally { Directory.Delete(directory, true); }
    }

    public static async Task SingleStoppedPositionAsync()
    {
        using var runtime = new PortableRuntime();
        using var handler = new ReportsHandler();
        using var http = new HttpClient(handler);
        var jellyfin = new JellyfinClient(http, "http://test.invalid", "fictional-token", "test-device");
        Func<Task> onStarted = () => Task.CompletedTask;
        await Invoke("RunVlcWithSyncAsync", FakePlayer(), SingleTestMedia, null, jellyfin, "single", null, onStarted);
        Equal(42L, handler.Reports.Single(report => report.Path == "/Sessions/Playing").Seconds);
        Equal(42L, handler.Reports.Single(report => report.Path == "/Sessions/Playing/Stopped").Seconds);
        Equal(false, handler.Reports.Any(report => report.Seconds == 0));
    }

    public static Task<int> RunUntrackedFakeAsync(string[] args)
    {
        var media = args.Skip(2).First();
        File.WriteAllText(media + ".launch.json", JsonSerializer.Serialize(args));
        return Task.FromResult(0);
    }

    public static async Task<int> RunSingleFakeAsync(string[] args)
    {
        var port = int.Parse(args.Single(arg => arg.StartsWith("--http-port=", StringComparison.Ordinal)).Split('=')[1]);
        var password = args.Single(arg => arg.StartsWith("--http-password=", StringComparison.Ordinal)).Split('=')[1];
        var authorization = "Basic " + Convert.ToBase64String(Encoding.UTF8.GetBytes(":" + password));
        using var listener = new HttpListener();
        listener.Prefixes.Add($"http://127.0.0.1:{port}/");
        listener.Start();
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(35));
        var next = 0;
        while (next < 3)
        {
            var context = await listener.GetContextAsync().WaitAsync(timeout.Token);
            if (context.Request.Headers["Authorization"] != authorization)
            {
                context.Response.StatusCode = 401;
                context.Response.Close();
                continue;
            }
            var active = next++ == 1;
            var bytes = JsonSerializer.SerializeToUtf8Bytes(new
            {
                state = active ? "playing" : "stopped", time = active ? 42 : 0,
                length = active ? 300 : 0, volume = 256, currentplid = active ? 4 : -1
            });
            context.Response.ContentType = "application/json";
            context.Response.ContentLength64 = bytes.Length;
            await context.Response.OutputStream.WriteAsync(bytes);
            context.Response.Close();
        }
        await Task.Delay(200);
        return 0;
    }

    private static string FakePlayer() => Path.Combine(AppContext.BaseDirectory,
        OperatingSystem.IsWindows() ? "JellyfinVlcBridge.Tests.exe" : "JellyfinVlcBridge.Tests");

    private static async Task Invoke(string name, params object?[] arguments)
    {
        var method = Assembly.Load("jellyfin-vlc-bridge").GetType("Program")!
            .GetMethods(BindingFlags.Static | BindingFlags.NonPublic)
            .Single(method => method.Name.Contains("g__" + name + "|", StringComparison.Ordinal));
        await ((Task)method.Invoke(null, arguments)!).WaitAsync(TimeSpan.FromSeconds(40));
    }

    private static void Equal<T>(T expected, T actual)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual)) throw new Exception($"Expected {expected}, got {actual}.");
    }

    private sealed class PortableRuntime : IDisposable
    {
        private readonly string? original = Environment.GetEnvironmentVariable("DOTNET_ROOT");
        public PortableRuntime()
        {
            if (string.IsNullOrWhiteSpace(original))
                Environment.SetEnvironmentVariable("DOTNET_ROOT", Path.GetFullPath(Path.Combine(
                    Path.GetDirectoryName(typeof(object).Assembly.Location)!, "..", "..", "..")));
        }
        public void Dispose() => Environment.SetEnvironmentVariable("DOTNET_ROOT", original);
    }

    private sealed record Report(string Path, long Seconds);
    private sealed class ReportsHandler : HttpMessageHandler
    {
        public List<Report> Reports { get; } = [];
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            using var json = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(cancellationToken));
            Reports.Add(new Report(request.RequestUri!.AbsolutePath, json.RootElement.GetProperty("positionTicks").GetInt64() / TimeSpan.TicksPerSecond));
            return new HttpResponseMessage(HttpStatusCode.NoContent);
        }
    }
}
