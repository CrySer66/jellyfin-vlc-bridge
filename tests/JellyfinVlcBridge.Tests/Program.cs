using JellyfinVlcBridge.Core;

var tests = new (string Name, Func<Task> Run)[]
{
    ("Mapping Windows vers SMB", () => Completed(() => Equal(@"\\serveur\Films\Alien\Alien.mkv",
        PathMapper.Map(@"D:\Films\Alien\Alien.mkv", [new(@"D:\Films", @"\\serveur\Films")])))),
    ("Mapping le plus spécifique", () => Completed(() => Equal(@"\\nas\4K\Film.mkv",
        PathMapper.Map(@"D:\Films\4K\Film.mkv", [new(@"D:\Films", @"\\nas\Films"), new(@"D:\Films\4K", @"\\nas\4K")])))),
    ("Échec sans mapping", () => Completed(() => Throws<InvalidOperationException>(() => PathMapper.Map(@"E:\Autre\x.mkv", [])))),
    ("Clé de secret stable", () => Completed(() => Equal("JellyfinVlcBridge:192.168.1.25:8096", SecretKeys.ForServer("http://192.168.1.25:8096")))),
    ("Conversion temps VLC", () => Completed(() => Equal(42L * TimeSpan.TicksPerSecond, new VlcStatus("playing", 42, 100, 256).PositionTicks))),
    ("Identifiant Chrome Web Store officiel", () => Completed(() =>
        Equal("hkjbodgdbjhignhlbecchiigcfigpidp", BridgeLinks.ChromeWebStoreExtensionId))),
    ("Origines Chrome limitées aux deux extensions attendues", () => Completed(() =>
        Equal("hkjbodgdbjhignhlbecchiigcfigpidp,hpbbmehpokomkjfnemlbdlalbmckmkld",
            string.Join(',', BridgeLinks.AllowedExtensionIds)))),
    ("Signal récent de l'extension reconnu", () => Completed(() =>
    {
        var state = new ExtensionHeartbeatState(
            BridgeLinks.DevelopmentExtensionId, "1.3.0", DateTimeOffset.UtcNow);
        Equal(true, ExtensionHeartbeat.IsActive(state));
    })),
    ("Signal ancien de l'extension considéré inactif", () => Completed(() =>
    {
        var state = new ExtensionHeartbeatState(
            BridgeLinks.DevelopmentExtensionId, "1.3.0", DateTimeOffset.UtcNow.AddMinutes(-2));
        Equal(false, ExtensionHeartbeat.IsActive(state));
    })),
    ("Signaux simultanes de l'extension enregistres sans fichier abandonne", async () =>
    {
        var directory = Path.Combine(Path.GetTempPath(), "JvbHeartbeatTest-" + Guid.NewGuid().ToString("N"));
        var filePath = Path.Combine(directory, "extension-heartbeat.json");
        try
        {
            Directory.CreateDirectory(directory);
            await Task.WhenAll(Enumerable.Range(0, 24).Select(index => Task.Run(() =>
                ExtensionHeartbeat.Record(filePath, BridgeLinks.ChromeWebStoreExtensionId, "1.3." + index))));
            var state = System.Text.Json.JsonSerializer.Deserialize<ExtensionHeartbeatState>(File.ReadAllText(filePath));
            Equal(BridgeLinks.ChromeWebStoreExtensionId, state?.ExtensionId);
            Equal(0, Directory.GetFiles(directory, "*.tmp-*").Length);
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, true);
        }
    }),
    ("Dépôt GitHub officiel stable", () => Completed(() =>
        Equal("cryser66/jellyfin-vlc-bridge", BridgeLinks.GitHubRepository))),
    ("Assistance GitHub officielle stable", () => Completed(() =>
        Equal("https://github.com/cryser66/jellyfin-vlc-bridge/issues/new/choose", BridgeLinks.GitHubIssuesUrl))),
    ("Une nouvelle Release GitHub est détectée", async () =>
    {
        using var http = new HttpClient(new ReleaseHandler(false));
        var update = await new GitHubUpdateService(http).CheckAsync();
        Equal(true, update.UpdateAvailable);
        Equal("9.9.9", update.LatestVersion);
        Equal("JellyfinVlcBridge-9.9.9-Setup.exe", update.AssetName);
    }),
    ("Un installateur extérieur à GitHub est refusé", async () =>
    {
        using var http = new HttpClient(new ReleaseHandler(true));
        await ThrowsAsync<InvalidDataException>(() => new GitHubUpdateService(http).CheckAsync());
    }),
    ("L'installateur officiel est téléchargé et validé", async () =>
    {
        var directory = Path.Combine(Path.GetTempPath(), "JvbUpdateTest-" + Guid.NewGuid().ToString("N"));
        try
        {
            using var http = new HttpClient(new DownloadReleaseHandler());
            var result = await new GitHubUpdateService(http).DownloadLatestAsync(directory);
            Equal("9.9.9", result.Version);
            Equal(true, File.Exists(result.Path));
            Equal((byte)'M', File.ReadAllBytes(result.Path)[0]);
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, true);
        }
    }),
    ("Fin naturelle déclenche l'épisode suivant", () => Completed(() =>
        Equal(true, PlaybackQueueResolver.ShouldContinue(TimeSpan.FromMinutes(42).Ticks, TimeSpan.FromMinutes(43).Ticks, false)))),
    ("Fermeture manuelle arrête la série", () => Completed(() =>
        Equal(false, PlaybackQueueResolver.ShouldContinue(TimeSpan.FromMinutes(12).Ticks, TimeSpan.FromMinutes(43).Ticks, false)))),
    ("Une série commence au prochain épisode Jellyfin", async () =>
    {
        using var http = new HttpClient(new SeriesQueueHandler());
        var client = new JellyfinClient(http, "http://jellyfin", "secret", "device");
        var series = new ItemInfo("series", "Ma série", null, null, null, Type: "Series");
        var queue = await PlaybackQueueResolver.ResolveAsync(client, "user", series);
        Equal(2, queue.Count);
        Equal("episode-2", queue[0].Id);
        Equal("episode-3", queue[1].Id);
    }),
    ("Rapports Jellyfin", async () =>
    {
        var handler = new CaptureHandler();
        using var http = new HttpClient(handler);
        var client = new JellyfinClient(http, "http://jellyfin", "secret", "device");
        await client.ReportPlaybackStartedAsync("956b5d10-c0fb-a3ca-8dfa-4c0777302559", "source", "session", 123);
        await client.ReportPlaybackProgressAsync("956b5d10-c0fb-a3ca-8dfa-4c0777302559", "source", "session", 456, false, 50);
        await client.ReportPlaybackStoppedAsync("956b5d10-c0fb-a3ca-8dfa-4c0777302559", "source", "session", 789, false);
        Equal("/Sessions/Playing,/Sessions/Playing/Progress,/Sessions/Playing/Stopped", string.Join(',', handler.Paths));
        if (handler.Bodies.Any(x => !x.Contains("\"playSessionId\":\"session\""))) throw new Exception("PlaySessionId absent");
    })
};

var failures = 0;
foreach (var test in tests)
{
    try { await test.Run(); Console.WriteLine($"OK  {test.Name}"); }
    catch (Exception ex) { failures++; Console.Error.WriteLine($"KO  {test.Name}: {ex}"); }
}
return failures;

static void Equal<T>(T expected, T actual)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual)) throw new Exception($"attendu={expected}, obtenu={actual}");
}
static void Throws<T>(Action action) where T : Exception
{
    try { action(); }
    catch (T) { return; }
    throw new Exception($"exception {typeof(T).Name} attendue");
}
static Task Completed(Action action) { action(); return Task.CompletedTask; }
static async Task ThrowsAsync<T>(Func<Task> action) where T : Exception
{
    try { await action(); }
    catch (T) { return; }
    throw new Exception($"exception {typeof(T).Name} attendue");
}

sealed class CaptureHandler : HttpMessageHandler
{
    public List<string> Paths { get; } = [];
    public List<string> Bodies { get; } = [];
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Paths.Add(request.RequestUri!.AbsolutePath);
        Bodies.Add(request.Content is null ? "" : await request.Content.ReadAsStringAsync(cancellationToken));
        return new HttpResponseMessage(System.Net.HttpStatusCode.NoContent);
    }
}

sealed class SeriesQueueHandler : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var json = request.RequestUri!.AbsolutePath.EndsWith("/Shows/NextUp", StringComparison.Ordinal)
            ? """{"Items":[{"Id":"episode-2","Name":"Deux","Type":"Episode","Path":"D:\\Series\\S01E02.mkv"}],"TotalRecordCount":1}"""
            : """{"Items":[{"Id":"episode-1","Name":"Un","Type":"Episode","Path":"D:\\Series\\S01E01.mkv","UserData":{"PlaybackPositionTicks":0,"Played":true}},{"Id":"episode-2","Name":"Deux","Type":"Episode","Path":"D:\\Series\\S01E02.mkv","UserData":{"PlaybackPositionTicks":1200000000,"Played":false}},{"Id":"episode-3","Name":"Trois","Type":"Episode","Path":"D:\\Series\\S01E03.mkv","UserData":{"PlaybackPositionTicks":0,"Played":false}}],"TotalRecordCount":3}""";
        return Task.FromResult(new HttpResponseMessage(System.Net.HttpStatusCode.OK)
        {
            Content = new StringContent(json, System.Text.Encoding.UTF8, "application/json")
        });
    }
}

sealed class ReleaseHandler(bool evil) : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var download = evil
            ? "https://example.com/JellyfinVlcBridge-9.9.9-Setup.exe"
            : "https://github.com/cryser66/jellyfin-vlc-bridge/releases/download/v9.9.9/JellyfinVlcBridge-9.9.9-Setup.exe";
        var json = $$"""
        {
          "tag_name": "v9.9.9",
          "html_url": "https://github.com/cryser66/jellyfin-vlc-bridge/releases/tag/v9.9.9",
          "assets": [{
            "name": "JellyfinVlcBridge-9.9.9-Setup.exe",
            "browser_download_url": "{{download}}",
            "size": 200000
          }]
        }
        """;
        return Task.FromResult(new HttpResponseMessage(System.Net.HttpStatusCode.OK)
        {
            Content = new StringContent(json, System.Text.Encoding.UTF8, "application/json")
        });
    }
}

sealed class DownloadReleaseHandler : HttpMessageHandler
{
    private int requestNumber;

    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        requestNumber++;
        if (requestNumber == 1)
        {
            const string json = """
            {
              "tag_name": "v9.9.9",
              "html_url": "https://github.com/cryser66/jellyfin-vlc-bridge/releases/tag/v9.9.9",
              "assets": [{
                "name": "JellyfinVlcBridge-9.9.9-Setup.exe",
                "browser_download_url": "https://github.com/cryser66/jellyfin-vlc-bridge/releases/download/v9.9.9/JellyfinVlcBridge-9.9.9-Setup.exe",
                "size": 70000
              }]
            }
            """;
            return Task.FromResult(new HttpResponseMessage(System.Net.HttpStatusCode.OK)
            {
                Content = new StringContent(json, System.Text.Encoding.UTF8, "application/json")
            });
        }

        var installer = new byte[70000];
        installer[0] = (byte)'M';
        installer[1] = (byte)'Z';
        return Task.FromResult(new HttpResponseMessage(System.Net.HttpStatusCode.OK)
        {
            Content = new ByteArrayContent(installer)
        });
    }
}
