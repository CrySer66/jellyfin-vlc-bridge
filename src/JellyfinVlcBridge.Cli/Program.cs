using JellyfinVlcBridge.Core;
using Microsoft.Win32;

return await MainAsync(args);

static async Task<int> MainAsync(string[] args)
{
    try
    {
        if (args.Length == 0) return Help();
        return args[0].ToLowerInvariant() switch
        {
            "setup" => await QuickSetupAsync(args[1..]),
            "setup-api" => await SetupApiAsync(),
            "configure" => Configure(args[1..]),
            "play" => await PlayAsync(args[1..]),
            "handle-uri" => await HandleUriAsync(args[1..]),
            "install-protocol" => InstallProtocol(),
            "doctor" => await DoctorAsync(),
            "status" => await StatusAsync(args[1..]),
            "support-bundle" => await SupportBundleAsync(args[1..]),
            "repair" => Repair(),
            "version" or "--version" => ShowVersion(),
            "install-native-host" => InstallNativeHost(),
            "open-extension" => OpenExtensionPage(),
            "open-help" => OpenHelpPage(),
            "check-update" => await CheckUpdateAsync(args[1..]),
            "download-update" => await DownloadUpdateAsync(args[1..]),
            "uninstall-cleanup" => UninstallCleanup(args[1..]),
            _ when args.Any(x => x.StartsWith("chrome-extension://", StringComparison.OrdinalIgnoreCase)) => await NativeMessageAsync(args),
            _ when args[0].StartsWith("jellyfin-vlc:", StringComparison.OrdinalIgnoreCase) => await HandleUriAsync(args),
            _ => Help()
        };
    }
    catch (Exception exception)
    {
        BridgeLog.Error(exception.ToString());
        Console.Error.WriteLine($"Erreur : {exception.Message}");
        return 1;
    }
}

static async Task<int> QuickSetupAsync(string[] args)
{
    Console.WriteLine("Configuration Quick Connect de Jellyfin VLC Bridge");
    var server = Optional(args, "--server")?.Trim().TrimEnd('/');
    if (string.IsNullOrWhiteSpace(server))
    {
        Console.Write("Adresse du serveur Jellyfin (ex. http://192.168.1.25:8096) : ");
        server = (Console.ReadLine() ?? "").Trim().TrimEnd('/');
    }
    server = ServerAddress.Normalize(server);

    BridgeConfig? existing = null;
    if (File.Exists(BridgeConfig.DefaultPath))
    {
        try { existing = BridgeConfig.Load(); }
        catch (Exception exception)
        {
            BridgeLog.Warning("Configuration existante ignorée pendant Quick Connect : " + exception.Message);
        }
    }
    var deviceId = !string.IsNullOrWhiteSpace(existing?.DeviceId) ? existing.DeviceId : Guid.NewGuid().ToString("N");
    using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
    var client = new JellyfinClient(http, server, "");
    var state = await client.InitiateQuickConnectAsync(deviceId);
    var codePath = Optional(args, "--code-path");
    if (!string.IsNullOrWhiteSpace(codePath))
    {
        var parent = Path.GetDirectoryName(Path.GetFullPath(codePath));
        if (!string.IsNullOrWhiteSpace(parent)) Directory.CreateDirectory(parent);
        File.WriteAllText(codePath, state.Code);
    }

    Console.WriteLine();
    Console.WriteLine($"CODE QUICK CONNECT : {state.Code}");
    Console.WriteLine();
    Console.WriteLine("Dans Jellyfin déjà connecté : Profil/Paramètres → Quick Connect → saisissez ce code.");
    Console.Write("Attente de l'autorisation");

    using var timeout = new CancellationTokenSource(TimeSpan.FromMinutes(3));
    while (!state.Authenticated)
    {
        await Task.Delay(TimeSpan.FromSeconds(5), timeout.Token);
        state = await client.GetQuickConnectStateAsync(deviceId, state.Secret, timeout.Token);
        Console.Write(".");
    }
    Console.WriteLine();

    var authentication = await client.AuthenticateWithQuickConnectAsync(deviceId, state.Secret, timeout.Token);
    if (string.IsNullOrWhiteSpace(authentication.AccessToken) || authentication.User is null)
        throw new InvalidDataException("Jellyfin n'a pas retourné le jeton ou l'utilisateur attendu.");

    new BridgeConfig
    {
        ServerUrl = server,
        UserId = authentication.User.Id,
        DeviceId = deviceId,
        PlaybackMode = "http"
    }.Save();
    new EnvironmentOrWindowsCredentialStore().Write(SecretKeys.ForServer(server), authentication.AccessToken);
    Console.WriteLine($"Appareil autorisé pour l'utilisateur « {authentication.User.Name} ».");
    if (OperatingSystem.IsWindows())
    {
        InstallProtocol();
        InstallNativeHost();
    }
    Console.WriteLine("Configuration terminée.");
    return 0;
}

static async Task<int> SetupApiAsync()
{
    Console.WriteLine("Configuration guidée de Jellyfin VLC Bridge");
    Console.Write("Adresse du serveur Jellyfin (ex. http://192.168.1.25:8096) : ");
    var server = (Console.ReadLine() ?? "").Trim().TrimEnd('/');
    server = ServerAddress.Normalize(server);

    Console.Write("Nom de l'utilisateur Jellyfin (ex. Admin) : ");
    var userName = (Console.ReadLine() ?? "").Trim();
    if (string.IsNullOrWhiteSpace(userName)) throw new ArgumentException("Le nom utilisateur est obligatoire.");

    Console.Write("Clé API Jellyfin (saisie masquée) : ");
    var token = ReadSecret();
    if (string.IsNullOrWhiteSpace(token)) throw new ArgumentException("La clé API est obligatoire.");

    using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
    IReadOnlyList<UserInfo> users;
    try { users = await new JellyfinClient(http, server, token).GetUsersAsync(); }
    catch (HttpRequestException exception)
    {
        throw new InvalidOperationException("Connexion refusée par Jellyfin. Vérifiez l'adresse et la clé API.", exception);
    }
    var user = users.FirstOrDefault(x => x.Name.Equals(userName, StringComparison.OrdinalIgnoreCase))
        ?? throw new InvalidOperationException($"Utilisateur « {userName} » introuvable. Utilisateurs visibles : {string.Join(", ", users.Select(x => x.Name))}");

    new BridgeConfig
    {
        ServerUrl = server,
        UserId = user.Id,
        PlaybackMode = "http"
    }.Save();
    new EnvironmentOrWindowsCredentialStore().Write(SecretKeys.ForServer(server), token);
    Console.WriteLine($"Serveur validé et utilisateur « {user.Name} » reconnu.");
    if (OperatingSystem.IsWindows())
    {
        InstallProtocol();
        InstallNativeHost();
    }
    Console.WriteLine("Configuration terminée. Lancez maintenant la commande doctor.");
    return 0;
}

static int Configure(string[] args)
{
    var server = ServerAddress.Normalize(Required(args, "--server"));
    var userId = Required(args, "--user-id");
    var mode = Optional(args, "--mode") ?? "http";
    if (mode is not ("http" or "smb")) throw new ArgumentException("--mode doit valoir http ou smb.");
    var mappings = Values(args, "--map").Select(ParseMapping).ToList();
    var config = new BridgeConfig
    {
        ServerUrl = server,
        UserId = userId,
        VlcPath = Optional(args, "--vlc"),
        PlaybackMode = mode,
        DeviceId = Guid.NewGuid().ToString("N"),
        PathMappings = mappings
    };
    config.Save();

    Console.Write("Jeton API Jellyfin (saisie masquée, Entrée pour utiliser JELLYFIN_VLC_TOKEN) : ");
    var token = ReadSecret();
    if (!string.IsNullOrWhiteSpace(token))
        new EnvironmentOrWindowsCredentialStore().Write(SecretKeys.ForServer(server), token);
    Console.WriteLine($"Configuration enregistrée dans {BridgeConfig.DefaultPath}");
    return 0;
}

static async Task<int> HandleUriAsync(string[] args)
{
    if (args.Length != 1) throw new ArgumentException("URI jellyfin-vlc manquante.");
    var uri = new Uri(args[0]);
    if (!uri.Scheme.Equals("jellyfin-vlc", StringComparison.OrdinalIgnoreCase) || uri.Host != "play")
        throw new ArgumentException("URI Jellyfin VLC invalide.");
    var query = ParseQuery(uri.Query);
    if (!query.TryGetValue("itemId", out var itemId) || string.IsNullOrWhiteSpace(itemId))
        throw new ArgumentException("itemId manque dans l'URI.");
    var playArgs = new List<string> { "--item", itemId };
    if (query.TryGetValue("scope", out var scope)) playArgs.AddRange(["--scope", scope]);
    if (query.TryGetValue("start", out var start)) playArgs.AddRange(["--start", start]);
    if (query.TryGetValue("mediaSourceId", out var mediaSourceId))
        playArgs.AddRange(["--media-source", ValidateOptionalIdentifier(mediaSourceId, "version de média")!]);
    return await PlayAsync([.. playArgs]);
}

static async Task<int> PlayAsync(string[] args)
{
    var itemId = ValidateItemId(Required(args, "--item"));
    var scope = PlaybackQueueResolver.ParseScope(Optional(args, "--scope"));
    var restartFirst = ParseStartMode(Optional(args, "--start"));
    var selectedMediaSourceId = ValidateOptionalIdentifier(Optional(args, "--media-source"), "version de média");
    var dryRun = args.Contains("--dry-run");
    var config = BridgeConfig.Load();
    var token = new EnvironmentOrWindowsCredentialStore().Read(SecretKeys.ForServer(config.ServerUrl));
    if (string.IsNullOrWhiteSpace(token))
        throw new InvalidOperationException("Jeton absent. Relancez configure ou définissez JELLYFIN_VLC_TOKEN.");
    var vlc = VlcLauncher.Resolve(config.VlcPath);

    using var http = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
    var jellyfin = new JellyfinClient(http, config.ServerUrl, token, config.DeviceId);
    var selected = await jellyfin.GetItemAsync(config.UserId, itemId);
    var queue = await PlaybackQueueResolver.ResolveAsync(jellyfin, config.UserId, selected, scope);
    if (queue.Count == 0)
        throw new InvalidDataException("Cet élément ne contient aucun média lisible.");

    if (queue.Count > 1)
    {
        var groupName = selected.Type?.Equals("BoxSet", StringComparison.OrdinalIgnoreCase) == true
            ? "collection"
            : "série";
        Console.WriteLine($"Lecture de la {groupName} : {queue.Count} médias à partir de {EpisodeLabel(queue[0])}.");
    }

    if (queue.Count == 1)
    {
        await PlayResolvedItemAsync(
            vlc, config, token, http, jellyfin, queue[0], selectedMediaSourceId, dryRun, restartFirst);
        return 0;
    }

    if (dryRun)
        for (var index = 0; index < queue.Count; index++)
            await PlayResolvedItemAsync(
                vlc, config, token, http, jellyfin, queue[index], null, true, restartFirst && index == 0);
    else
        await PlayQueueAsync(vlc, config, token, http, jellyfin, queue, restartFirst);
    return 0;
}

static async Task<int> InspectPlaybackAsync(string itemId, PlaybackScope scope)
{
    var config = BridgeConfig.Load();
    var token = new EnvironmentOrWindowsCredentialStore().Read(SecretKeys.ForServer(config.ServerUrl));
    if (string.IsNullOrWhiteSpace(token))
        throw new InvalidOperationException("Jeton absent. Relancez la configuration Quick Connect.");

    using var http = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
    var jellyfin = new JellyfinClient(http, config.ServerUrl, token, config.DeviceId);
    var selected = await jellyfin.GetItemAsync(config.UserId, itemId);
    var queue = await PlaybackQueueResolver.ResolveAsync(jellyfin, config.UserId, selected, scope);
    var firstResumeTicks = queue.FirstOrDefault()?.UserData?.PlaybackPositionTicks ?? 0;
    var totalDurationTicks = queue.Sum(item => Math.Max(0, item.RunTimeTicks ?? 0));
    var firstItem = queue.FirstOrDefault();
    var mediaSources = queue.Count == 1
        ? (firstItem?.MediaSources ?? [])
            .Where(source => !string.IsNullOrWhiteSpace(source.Id))
            .Select((source, index) => new
            {
                id = PreviewText(source.Id!, 256),
                label = PreviewText(MediaSourceSelector.Label(source, index))
            })
            .ToArray()
        : [];

    await WriteNativeResponseAsync(new
    {
        accepted = true,
        type = "inspection",
        bridgeVersion = BridgeVersion.Current,
        itemType = selected.Type ?? "Video",
        title = PreviewText(selected.Name ?? "Lecture Jellyfin"),
        scope = ScopeValue(scope),
        totalCount = queue.Count,
        totalDurationSeconds = totalDurationTicks / TimeSpan.TicksPerSecond,
        hasResume = firstResumeTicks > 0,
        resumeSeconds = firstResumeTicks / TimeSpan.TicksPerSecond,
        mediaSources,
        items = queue.Take(100).Select(item => new
        {
            id = PreviewText(item.Id, 256),
            label = PreviewText(EpisodeLabel(item)),
            resumeSeconds = Math.Max(0, item.UserData?.PlaybackPositionTicks ?? 0) / TimeSpan.TicksPerSecond,
            durationSeconds = Math.Max(0, item.RunTimeTicks ?? 0) / TimeSpan.TicksPerSecond,
            played = item.UserData?.Played == true
        }).ToArray()
    });
    return 0;
}

static async Task PlayQueueAsync(
    string vlc,
    BridgeConfig config,
    string token,
    HttpClient http,
    JellyfinClient jellyfin,
    IReadOnlyList<ItemInfo> queue,
    bool restartFirst)
{
    AuthenticatedStreamProxy? proxy = null;
    var playlist = new List<PlaybackMedia>();
    try
    {
        for (var index = 0; index < queue.Count; index++)
        {
            var item = queue[index];
            var mediaSourceId = item.MediaSources?.FirstOrDefault()?.Id;
            var resumeTicks = restartFirst && index == 0 ? 0 : item.UserData?.PlaybackPositionTicks ?? 0;
            var resumeAt = resumeTicks > 0 ? TimeSpan.FromTicks(resumeTicks) : (TimeSpan?)null;
            string media;
            if (config.PlaybackMode == "smb")
            {
                var sourcePath = item.Path ?? item.MediaSources?.FirstOrDefault()?.Path
                    ?? throw new InvalidDataException($"Aucun chemin disponible pour {EpisodeLabel(item)}.");
                media = PathMapper.Map(sourcePath, config.PathMappings);
            }
            else
            {
                // Let Jellyfin select the default source for each item. A source id obtained
                // from a grouped listing can be incomplete on some server versions.
                var upstream = $"{config.ServerUrl}/Videos/{Uri.EscapeDataString(item.Id)}/stream?static=true";
                if (proxy is null)
                {
                    proxy = new AuthenticatedStreamProxy(http, upstream, token);
                    media = proxy.Start();
                }
                else media = proxy.AddStream(upstream);
            }
            playlist.Add(new PlaybackMedia(item, mediaSourceId, media, resumeAt));
        }

        Console.WriteLine("Liste de lecture VLC préparée ; les médias s'enchaîneront dans la même fenêtre.");
        await RunVlcPlaylistWithSyncAsync(vlc, playlist, jellyfin);
    }
    finally
    {
        if (proxy is not null) await proxy.DisposeAsync();
    }
}

static async Task<PlaybackRunResult> PlayResolvedItemAsync(
    string vlc,
    BridgeConfig config,
    string token,
    HttpClient http,
    JellyfinClient jellyfin,
    ItemInfo item,
    string? selectedMediaSourceId,
    bool dryRun,
    bool restart)
{
    var itemId = item.Id;
    var mediaSource = MediaSourceSelector.Select(item, selectedMediaSourceId);
    var mediaSourceId = mediaSource?.Id;
    var resumeTicks = restart ? 0 : item.UserData?.PlaybackPositionTicks ?? 0;
    var resumeAt = resumeTicks > 0 ? TimeSpan.FromTicks(resumeTicks) : (TimeSpan?)null;
    if (config.PlaybackMode == "smb")
    {
        var sourcePath = mediaSource?.Path ??
            (string.IsNullOrWhiteSpace(selectedMediaSourceId) ? item.Path : null)
            ?? throw new InvalidDataException("Jellyfin n'a retourné aucun chemin pour ce média.");
        var media = PathMapper.Map(sourcePath, config.PathMappings);
        Console.WriteLine($"VLC ouvrira le partage : {media}");
        return dryRun
            ? new PlaybackRunResult(true, resumeTicks, 0)
            : await RunVlcWithSyncAsync(vlc, media, resumeAt, jellyfin, itemId, mediaSourceId);
    }

    var mediaSourceQuery = string.IsNullOrWhiteSpace(mediaSourceId) ? "" : $"&MediaSourceId={Uri.EscapeDataString(mediaSourceId)}";
    var upstream = $"{config.ServerUrl}/Videos/{Uri.EscapeDataString(itemId)}/stream?static=true{mediaSourceQuery}";
    await using var proxy = new AuthenticatedStreamProxy(http, upstream, token);
    var localUrl = proxy.Start();
    Console.WriteLine("VLC ouvrira un relais local authentifié (le jeton ne figure pas dans l'URL ni la ligne de commande). ");
    if (dryRun) return new PlaybackRunResult(true, resumeTicks, 0);
    return await RunVlcWithSyncAsync(vlc, localUrl, resumeAt, jellyfin, itemId, mediaSourceId);
}

static async Task<PlaybackRunResult> RunVlcWithSyncAsync(
    string vlc,
    string media,
    TimeSpan? resumeAt,
    JellyfinClient jellyfin,
    string itemId,
    string? mediaSourceId)
{
    var controlOptions = VlcControlOptions.Create();
    var playSessionId = Guid.NewGuid().ToString("N");
    using var process = VlcLauncher.Start(vlc, media, resumeAt, controlOptions);
    BridgeLog.Info($"Lecture démarrée item={itemId} repriseTicks={resumeAt?.Ticks ?? 0}");
    using var controller = new VlcController(controlOptions);
    long lastPositionTicks = resumeAt?.Ticks ?? 0;
    long durationTicks = 0;
    var reportingStarted = false;
    var failed = false;

    try
    {
        var initial = await controller.WaitUntilReadyAsync(TimeSpan.FromSeconds(20));
        lastPositionTicks = Math.Max(lastPositionTicks, initial.PositionTicks);
        durationTicks = Math.Max(durationTicks, initial.DurationTicks);
        reportingStarted = await TryReportPlaybackStartedAsync(
            jellyfin, itemId, mediaSourceId, playSessionId, lastPositionTicks);
        Console.WriteLine(resumeAt is { TotalSeconds: > 0 }
            ? $"Reprise Jellyfin à {resumeAt.Value:hh\\:mm\\:ss} ; synchronisation active."
            : "Synchronisation de progression Jellyfin active.");
        if (!reportingStarted)
            Console.WriteLine("Jellyfin est momentanément indisponible ; la synchronisation réessaiera pendant la lecture.");

        while (!process.HasExited)
        {
            await Task.Delay(TimeSpan.FromSeconds(10));
            if (process.HasExited) break;
            try
            {
                var status = await controller.GetStatusAsync();
                lastPositionTicks = status.PositionTicks;
                durationTicks = Math.Max(durationTicks, status.DurationTicks);
                var volume = Math.Clamp((int)Math.Round(status.Volume / 2.56), 0, 100);
                if (!reportingStarted)
                    reportingStarted = await TryReportPlaybackStartedAsync(
                        jellyfin, itemId, mediaSourceId, playSessionId, lastPositionTicks);
                if (reportingStarted)
                    await TryReportPlaybackProgressAsync(
                        jellyfin, itemId, mediaSourceId, playSessionId,
                        lastPositionTicks, status.IsPaused, volume);
            }
            catch (Exception exception) when (exception is HttpRequestException or TaskCanceledException)
            {
                // VLC can briefly stop answering while seeking or closing; the next poll retries.
            }
        }
        await process.WaitForExitAsync();
        failed = process.ExitCode != 0;
    }
    catch (Exception exception)
    {
        failed = process.HasExited && process.ExitCode != 0;
        Console.Error.WriteLine($"Avertissement : suivi de progression indisponible ({exception.Message}). La lecture VLC continue.");
        BridgeLog.Warning($"Suivi indisponible item={itemId}: {exception.Message}");
        if (!process.HasExited) await process.WaitForExitAsync();
    }
    finally
    {
        if (reportingStarted)
            await TryReportPlaybackStoppedAsync(
                jellyfin, itemId, mediaSourceId, playSessionId, lastPositionTicks, failed);
        BridgeLog.Info($"Lecture terminée item={itemId} positionTicks={lastPositionTicks} failed={failed}");
    }
    return new PlaybackRunResult(
        PlaybackQueueResolver.ShouldContinue(lastPositionTicks, durationTicks, failed),
        lastPositionTicks,
        durationTicks);
}

static async Task RunVlcPlaylistWithSyncAsync(
    string vlc,
    IReadOnlyList<PlaybackMedia> playlist,
    JellyfinClient jellyfin)
{
    var controlOptions = VlcControlOptions.Create();
    using var process = VlcLauncher.StartPlaylist(
        vlc,
        playlist.Select(item => new VlcLaunchItem(item.Media, item.ResumeAt)).ToList(),
        controlOptions);
    using var controller = new VlcController(controlOptions);
    var currentIndex = 0;
    var playSessionId = Guid.NewGuid().ToString("N");
    var lastPlaylistId = -1;
    long lastPositionTicks = playlist[0].ResumeAt?.Ticks ?? 0;
    var reportingStarted = false;
    var failed = false;
    var nextProgressReport = DateTime.UtcNow;
    BridgeLog.Info($"Liste VLC démarrée count={playlist.Count} premierItem={playlist[0].Item.Id}");

    try
    {
        var initial = await WaitForActiveMediaAsync(controller, process, TimeSpan.FromSeconds(20));
        lastPlaylistId = initial.CurrentPlaylistId;
        lastPositionTicks = Math.Max(lastPositionTicks, initial.PositionTicks);
        reportingStarted = await TryReportPlaybackStartedAsync(
            jellyfin, playlist[0].Item.Id, playlist[0].MediaSourceId, playSessionId, lastPositionTicks);
        nextProgressReport = DateTime.UtcNow + TimeSpan.FromSeconds(10);
        Console.WriteLine(playlist[0].ResumeAt is { TotalSeconds: > 0 }
            ? $"Reprise Jellyfin à {playlist[0].ResumeAt.GetValueOrDefault():hh\\:mm\\:ss} ; synchronisation de la liste active."
            : "Synchronisation de la liste Jellyfin active.");
        if (!reportingStarted)
            Console.WriteLine("Jellyfin est momentanément indisponible ; la synchronisation réessaiera pendant la liste.");

        while (!process.HasExited)
        {
            await Task.Delay(TimeSpan.FromSeconds(2));
            if (process.HasExited) break;
            VlcStatus status;
            try { status = await controller.GetStatusAsync(); }
            catch (Exception exception) when (exception is HttpRequestException or TaskCanceledException) { continue; }

            if (status.CurrentPlaylistId >= 0 && lastPlaylistId >= 0 && status.CurrentPlaylistId != lastPlaylistId)
            {
                await TryReportPlaybackStoppedAsync(
                    jellyfin,
                    playlist[currentIndex].Item.Id,
                    playlist[currentIndex].MediaSourceId,
                    playSessionId,
                    lastPositionTicks,
                    false);
                BridgeLog.Info($"Transition VLC item={playlist[currentIndex].Item.Id} positionTicks={lastPositionTicks}");

                currentIndex++;
                if (currentIndex >= playlist.Count) break;
                lastPlaylistId = status.CurrentPlaylistId;
                playSessionId = Guid.NewGuid().ToString("N");
                lastPositionTicks = status.PositionTicks;
                reportingStarted = await TryReportPlaybackStartedAsync(
                    jellyfin,
                    playlist[currentIndex].Item.Id,
                    playlist[currentIndex].MediaSourceId,
                    playSessionId,
                    lastPositionTicks);
                Console.WriteLine($"Lecture suivante : {EpisodeLabel(playlist[currentIndex].Item)}");
                BridgeLog.Info($"Média suivant item={playlist[currentIndex].Item.Id} session={playSessionId}");
                nextProgressReport = DateTime.UtcNow + TimeSpan.FromSeconds(10);
                continue;
            }

            if (lastPlaylistId < 0 && status.CurrentPlaylistId >= 0)
                lastPlaylistId = status.CurrentPlaylistId;
            lastPositionTicks = status.PositionTicks;
            if (DateTime.UtcNow >= nextProgressReport)
            {
                var volume = Math.Clamp((int)Math.Round(status.Volume / 2.56), 0, 100);
                if (!reportingStarted)
                    reportingStarted = await TryReportPlaybackStartedAsync(
                        jellyfin, playlist[currentIndex].Item.Id, playlist[currentIndex].MediaSourceId,
                        playSessionId, lastPositionTicks);
                if (reportingStarted)
                    await TryReportPlaybackProgressAsync(
                        jellyfin, playlist[currentIndex].Item.Id, playlist[currentIndex].MediaSourceId,
                        playSessionId, lastPositionTicks, status.IsPaused, volume);
                nextProgressReport = DateTime.UtcNow + TimeSpan.FromSeconds(10);
            }
        }
        await process.WaitForExitAsync();
        failed = process.ExitCode != 0;
    }
    catch (Exception exception)
    {
        failed = process.HasExited && process.ExitCode != 0;
        Console.Error.WriteLine($"Avertissement : suivi de la liste indisponible ({exception.Message}). La liste VLC continue.");
        BridgeLog.Warning($"Suivi de liste indisponible item={playlist[currentIndex].Item.Id}: {exception.Message}");
        if (!process.HasExited) await process.WaitForExitAsync();
    }
    finally
    {
        if (reportingStarted && currentIndex < playlist.Count)
            await TryReportPlaybackStoppedAsync(
                jellyfin,
                playlist[currentIndex].Item.Id,
                playlist[currentIndex].MediaSourceId,
                playSessionId,
                lastPositionTicks,
                failed);
        BridgeLog.Info($"Liste VLC terminée index={currentIndex} positionTicks={lastPositionTicks} failed={failed}");
    }
}

static async Task<bool> TryReportPlaybackStartedAsync(
    JellyfinClient jellyfin,
    string itemId,
    string? mediaSourceId,
    string playSessionId,
    long positionTicks)
{
    try
    {
        await jellyfin.ReportPlaybackStartedAsync(itemId, mediaSourceId, playSessionId, positionTicks);
        BridgeLog.Info($"Synchronisation active item={itemId} session={playSessionId}");
        return true;
    }
    catch (Exception exception)
    {
        BridgeLog.Warning($"Démarrage de synchronisation différé item={itemId}: {exception.Message}");
        return false;
    }
}

static async Task TryReportPlaybackProgressAsync(
    JellyfinClient jellyfin,
    string itemId,
    string? mediaSourceId,
    string playSessionId,
    long positionTicks,
    bool paused,
    int? volume)
{
    try
    {
        await jellyfin.ReportPlaybackProgressAsync(
            itemId, mediaSourceId, playSessionId, positionTicks, paused, volume);
    }
    catch (Exception exception)
    {
        BridgeLog.Warning($"Progression non envoyée item={itemId}: {exception.Message}");
    }
}

static async Task TryReportPlaybackStoppedAsync(
    JellyfinClient jellyfin,
    string itemId,
    string? mediaSourceId,
    string playSessionId,
    long positionTicks,
    bool failed)
{
    try
    {
        await jellyfin.ReportPlaybackStoppedAsync(
            itemId, mediaSourceId, playSessionId, positionTicks, failed);
    }
    catch (Exception exception)
    {
        BridgeLog.Warning($"Position finale non envoyée item={itemId}: {exception.Message}");
    }
}

static async Task<VlcStatus> WaitForActiveMediaAsync(
    VlcController controller,
    System.Diagnostics.Process process,
    TimeSpan timeout)
{
    var deadline = DateTime.UtcNow + timeout;
    Exception? lastError = null;
    while (DateTime.UtcNow < deadline && !process.HasExited)
    {
        try
        {
            var status = await controller.GetStatusAsync();
            if (status.CurrentPlaylistId >= 0 &&
                status.State is not ("stopped" or "ended" or "error")) return status;
        }
        catch (Exception exception) when (exception is HttpRequestException or TaskCanceledException)
        {
            lastError = exception;
        }
        await Task.Delay(300);
    }
    throw new TimeoutException("VLC n'a pas chargé le premier média de la liste.", lastError);
}

static string EpisodeLabel(ItemInfo item)
{
    var number = item.ParentIndexNumber is { } season && item.IndexNumber is { } episode
        ? $"S{season:00}E{episode:00} — "
        : "";
    return number + (item.Name ?? item.Id);
}

static string PreviewText(string value, int maximumLength = 240)
{
    var normalized = value.Replace('\r', ' ').Replace('\n', ' ').Trim();
    return normalized.Length <= maximumLength
        ? normalized
        : normalized[..maximumLength] + "…";
}

static int InstallProtocol()
{
    if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Installation automatique disponible sur Windows uniquement.");
    var executable = Environment.ProcessPath ?? throw new InvalidOperationException("Chemin de l'exécutable introuvable.");
    using var key = Registry.CurrentUser.CreateSubKey(@"Software\Classes\jellyfin-vlc");
    key.SetValue(null, "URL:Jellyfin VLC Bridge Protocol");
    key.SetValue("URL Protocol", "");
    using var command = key.CreateSubKey(@"shell\open\command");
    command.SetValue(null, $"\"{executable}\" handle-uri \"%1\"");
    Console.WriteLine("Protocole jellyfin-vlc:// enregistré pour l'utilisateur actuel.");
    return 0;
}

static int InstallNativeHost()
{
    if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Messagerie native automatique disponible sur Windows uniquement.");
    const string hostName = "local.jellyfin_vlc_bridge";
    var executable = Environment.ProcessPath ?? throw new InvalidOperationException("Chemin de l'exécutable introuvable.");
    var directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "JellyfinVlcBridge");
    Directory.CreateDirectory(directory);
    var manifestPath = Path.Combine(directory, "native-messaging-host.json");
    var manifest = new
    {
        name = hostName,
        description = "Jellyfin VLC Bridge Native Host",
        path = executable,
        type = "stdio",
        allowed_origins = BridgeLinks.AllowedExtensionIds.Select(id => $"chrome-extension://{id}/").ToArray()
    };
    File.WriteAllText(manifestPath, System.Text.Json.JsonSerializer.Serialize(manifest, new System.Text.Json.JsonSerializerOptions { WriteIndented = true }));

    foreach (var registryPath in new[]
    {
        $@"Software\Google\Chrome\NativeMessagingHosts\{hostName}",
        $@"Software\Microsoft\Edge\NativeMessagingHosts\{hostName}"
    })
    {
        using var key = Registry.CurrentUser.CreateSubKey(registryPath);
        key.SetValue(null, manifestPath);
    }
    Console.WriteLine("Communication directe avec Chrome/Edge enregistrée.");
    return 0;
}

static int OpenExtensionPage()
{
    OpenWebPage(BridgeLinks.ChromeWebStoreUrl);
    return 0;
}

static int OpenHelpPage()
{
    OpenWebPage(BridgeLinks.GitHubIssuesUrl);
    return 0;
}

static void OpenWebPage(string url) => System.Diagnostics.Process.Start(
    new System.Diagnostics.ProcessStartInfo { FileName = url, UseShellExecute = true });

static async Task<int> CheckUpdateAsync(string[] args)
{
    if (!args.Contains("--json")) throw new ArgumentException("Utilisez check-update --json.");
    using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(12) };
    var update = await new GitHubUpdateService(http).CheckAsync();
    Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(update,
        new System.Text.Json.JsonSerializerOptions { PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase }));
    return 0;
}

static async Task<int> DownloadUpdateAsync(string[] args)
{
    if (!args.Contains("--json")) throw new ArgumentException("Utilisez download-update --json.");
    var directory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "JellyfinVlcBridge", "Updates");
    using var http = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
    var downloaded = await new GitHubUpdateService(http).DownloadLatestAsync(directory);
    Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(downloaded,
        new System.Text.Json.JsonSerializerOptions { PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase }));
    return 0;
}

static int UninstallCleanup(string[] args)
{
    if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Désinstallation automatique disponible sur Windows uniquement.");
    var purge = args.Contains("--purge");
    BridgeConfig? config = null;
    if (File.Exists(BridgeConfig.DefaultPath))
    {
        try { config = BridgeConfig.Load(); } catch { }
    }

    foreach (var registryPath in new[]
    {
        @"Software\Classes\jellyfin-vlc",
        @"Software\Google\Chrome\NativeMessagingHosts\local.jellyfin_vlc_bridge",
        @"Software\Microsoft\Edge\NativeMessagingHosts\local.jellyfin_vlc_bridge",
        @"Software\Microsoft\Windows\CurrentVersion\Uninstall\JellyfinVlcBridge"
    }) Registry.CurrentUser.DeleteSubKeyTree(registryPath, false);

    var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "JellyfinVlcBridge");
    var nativeManifest = Path.Combine(root, "native-messaging-host.json");
    if (File.Exists(nativeManifest)) File.Delete(nativeManifest);
    if (File.Exists(ExtensionHeartbeat.FilePath)) File.Delete(ExtensionHeartbeat.FilePath);
    var shortcut = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Desktop), "Jellyfin VLC Bridge - Diagnostic.lnk");
    if (File.Exists(shortcut)) File.Delete(shortcut);
    var startMenu = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Jellyfin VLC Bridge");
    if (Directory.Exists(startMenu)) Directory.Delete(startMenu, true);

    if (purge)
    {
        if (config is not null)
            new EnvironmentOrWindowsCredentialStore().Delete(SecretKeys.ForServer(config.ServerUrl));
        if (File.Exists(BridgeConfig.DefaultPath)) File.Delete(BridgeConfig.DefaultPath);
        if (File.Exists(PlaybackPreferencesStore.DefaultPath)) File.Delete(PlaybackPreferencesStore.DefaultPath);
        Console.WriteLine("Associations, configuration et jeton supprimés.");
    }
    else Console.WriteLine("Application retirée ; configuration et jeton conservés pour une réinstallation.");
    return 0;
}

static async Task<int> NativeMessageAsync(string[] args)
{
    var origin = args.FirstOrDefault(x => x.StartsWith("chrome-extension://", StringComparison.OrdinalIgnoreCase))
        ?? throw new InvalidDataException("Origine de l'extension absente.");
    var extensionId = origin["chrome-extension://".Length..].TrimEnd('/');
    if (!BridgeLinks.AllowedExtensionIds.Contains(extensionId))
        throw new InvalidDataException("Extension Chrome non autorisée.");

    var input = Console.OpenStandardInput();
    var lengthBytes = new byte[4];
    await ReadExactlyAsync(input, lengthBytes);
    var length = BitConverter.ToInt32(lengthBytes, 0);
    if (length is <= 0 or > 1024 * 1024) throw new InvalidDataException("Message navigateur invalide.");
    var payload = new byte[length];
    await ReadExactlyAsync(input, payload);
    using var document = System.Text.Json.JsonDocument.Parse(payload);
    var messageType = document.RootElement.TryGetProperty("type", out var typeProperty)
        ? typeProperty.GetString()
        : "play";
    var extensionVersion = document.RootElement.TryGetProperty("extensionVersion", out var versionProperty)
        ? versionProperty.GetString()
        : null;
    ExtensionHeartbeat.Record(extensionId, extensionVersion);

    if (messageType == "ping")
    {
        await WriteNativeResponseAsync(new { accepted = true, type = "pong", bridgeVersion = BridgeVersion.Current });
        return 0;
    }
    if (messageType == "preferences-get")
    {
        await WritePreferencesResponseAsync(PlaybackPreferencesStore.LoadOrDefault());
        return 0;
    }
    if (messageType == "preferences-save")
    {
        var rememberChoices = document.RootElement.TryGetProperty("rememberChoices", out var rememberProperty) &&
            rememberProperty.ValueKind == System.Text.Json.JsonValueKind.True;
        var preferences = PlaybackPreferencesStore.LoadOrDefault();
        if (rememberChoices)
        {
            var savedStartMode = document.RootElement.TryGetProperty("startMode", out var savedStartProperty)
                ? savedStartProperty.GetString()
                : null;
            var itemType = document.RootElement.TryGetProperty("itemType", out var itemTypeProperty)
                ? itemTypeProperty.GetString()
                : null;
            var savedScope = document.RootElement.TryGetProperty("scope", out var savedScopeProperty)
                ? savedScopeProperty.GetString()
                : null;
            preferences = preferences.WithChoice(true, savedStartMode, itemType, savedScope);
        }
        else preferences = preferences with { RememberChoices = false };
        PlaybackPreferencesStore.Save(preferences);
        await WritePreferencesResponseAsync(preferences);
        return 0;
    }
    if (messageType is not ("play" or "inspect"))
        throw new InvalidDataException("Type de message navigateur inconnu.");
    if (!document.RootElement.TryGetProperty("itemId", out var itemProperty))
        throw new InvalidDataException("itemId absent du message navigateur.");
    var itemId = ValidateItemId(itemProperty.GetString());
    var scopeText = document.RootElement.TryGetProperty("scope", out var scopeProperty)
        ? scopeProperty.GetString()
        : null;
    var scope = PlaybackQueueResolver.ParseScope(scopeText);

    if (messageType == "inspect")
        return await InspectPlaybackAsync(itemId, scope);

    var startMode = document.RootElement.TryGetProperty("startMode", out var startProperty)
        ? startProperty.GetString()
        : null;
    ParseStartMode(startMode);
    var selectedMediaSourceId = document.RootElement.TryGetProperty("mediaSourceId", out var sourceProperty)
        ? ValidateOptionalIdentifier(sourceProperty.GetString(), "version de média")
        : null;

    await WriteNativeResponseAsync(new { accepted = true });
    Console.SetOut(Console.Error);
    var playArguments = new List<string>
    {
        "--item", itemId,
        "--scope", ScopeValue(scope),
        "--start", startMode ?? "resume"
    };
    if (!string.IsNullOrWhiteSpace(selectedMediaSourceId))
        playArguments.AddRange(["--media-source", selectedMediaSourceId]);
    return await PlayAsync([.. playArguments]);
}

static Task WritePreferencesResponseAsync(PlaybackPreferences preferences) => WriteNativeResponseAsync(new
{
    accepted = true,
    type = "preferences",
    rememberChoices = preferences.RememberChoices,
    startMode = preferences.StartMode,
    scopes = preferences.Scopes
});

static async Task WriteNativeResponseAsync(object value)
{
    var response = System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(value);
    var output = Console.OpenStandardOutput();
    await output.WriteAsync(BitConverter.GetBytes(response.Length));
    await output.WriteAsync(response);
    await output.FlushAsync();
}

static async Task ReadExactlyAsync(Stream stream, byte[] buffer)
{
    var offset = 0;
    while (offset < buffer.Length)
    {
        var read = await stream.ReadAsync(buffer.AsMemory(offset));
        if (read == 0) throw new EndOfStreamException("Le navigateur a fermé la communication.");
        offset += read;
    }
}

static async Task<int> DoctorAsync()
{
    var status = await BridgeDiagnostics.CheckAsync();
    Console.WriteLine($"Version : {status.Version}");
    Console.WriteLine($"Configuration : {(status.Configured ? "OK" : "ABSENTE")} ({status.ConfigPath})");
    Console.WriteLine($"Jellyfin : {(status.JellyfinConnected ? "OK" : "ERREUR")} - {status.JellyfinMessage}");
    Console.WriteLine($"VLC : {(status.VlcReady ? "OK" : "ABSENT")} - {status.VlcPath ?? "non détecté"}");
    Console.WriteLine($"Version VLC : {status.VlcVersion ?? "inconnue"}");
    Console.WriteLine($"Secret : {(status.SecretReady ? "OK" : "ABSENT")}");
    Console.WriteLine($"Chrome : {(status.NativeMessagingReady ? "OK" : "A REPARER")}");
    Console.WriteLine($"Extension : {(status.ExtensionActive ? $"ACTIVE ({status.ExtensionVersion})" : "INACTIVE OU SANS CONTACT")}");
    Console.WriteLine($"Mode : {status.PlaybackMode}");
    Console.WriteLine($"Journal : {status.LogPath}");
    foreach (var finding in status.Findings)
    {
        Console.WriteLine($"[{finding.Severity.ToUpperInvariant()}] {finding.Code} - {finding.Message}");
        Console.WriteLine($"  Action : {finding.Action}");
    }
    return status.Ready ? 0 : 1;
}

static async Task<int> StatusAsync(string[] args)
{
    if (!args.Contains("--json")) throw new ArgumentException("Utilisez status --json.");
    var status = await BridgeDiagnostics.CheckAsync();
    Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(status,
        new System.Text.Json.JsonSerializerOptions { PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase }));
    return 0;
}

static async Task<int> SupportBundleAsync(string[] args)
{
    var output = Required(args, "--output");
    var result = await BridgeSupportBundle.CreateAsync(output);
    if (args.Contains("--json"))
    {
        Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(result,
            new System.Text.Json.JsonSerializerOptions
            {
                PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase
            }));
    }
    else Console.WriteLine($"Paquet d’assistance créé : {result.Path}");
    return 0;
}

static int Repair()
{
    InstallProtocol();
    InstallNativeHost();
    Console.WriteLine("Intégration navigateur réparée.");
    return 0;
}

static int ShowVersion()
{
    Console.WriteLine($"Jellyfin VLC Bridge {BridgeVersion.Current}");
    return 0;
}

static int Help()
{
    Console.WriteLine("""
Jellyfin VLC Bridge
  version                       Affiche la version installée
  setup                         Configuration Quick Connect recommandée
  setup-api                     Ancienne configuration par clé API
  configure --server URL --user-id ID [--vlc CHEMIN] [--mode http|smb] [--map SERVEUR=CLIENT]
  install-protocol
  install-native-host            Supprime la confirmation répétée du navigateur
  open-extension                Ouvre la fiche officielle Chrome Web Store
  open-help                     Ouvre l'assistance GitHub officielle
  check-update --json           Vérifie la dernière Release GitHub officielle
  download-update --json        Télécharge le nouvel installateur officiel
  status --json                 État complet lisible par le centre de contrôle
  support-bundle --output ZIP [--json]
                                Crée un paquet d’assistance expurgé
  repair                        Répare le protocole et la connexion Chrome/Edge
  uninstall-cleanup [--purge]    Nettoyage Windows utilisé par le désinstallateur
  play --item ID [--scope auto|single|following|all] [--start resume|restart] [--media-source ID] [--dry-run]
  doctor
""");
    return 2;
}

static string Required(string[] args, string name) => Optional(args, name)
    ?? throw new ArgumentException($"Option requise : {name}");
static string? Optional(string[] args, string name)
{
    var index = Array.IndexOf(args, name);
    return index >= 0 && index + 1 < args.Length ? args[index + 1] : null;
}
static bool ParseStartMode(string? value) => value?.Trim().ToLowerInvariant() switch
{
    null or "" or "resume" => false,
    "restart" => true,
    _ => throw new ArgumentException("Mode de démarrage inconnu.", nameof(value))
};
static string ScopeValue(PlaybackScope scope) => scope switch
{
    PlaybackScope.Single => "single",
    PlaybackScope.Following => "following",
    PlaybackScope.All => "all",
    _ => "auto"
};
static IEnumerable<string> Values(string[] args, string name)
{
    for (var i = 0; i < args.Length - 1; i++) if (args[i] == name) yield return args[i + 1];
}
static PathMapping ParseMapping(string value)
{
    var index = value.IndexOf('=');
    if (index < 1) throw new ArgumentException("Mapping attendu : CHEMIN_SERVEUR=CHEMIN_CLIENT");
    return new PathMapping(value[..index], value[(index + 1)..]);
}
static string ValidateItemId(string? value)
{
    var itemId = value?.Trim();
    if (string.IsNullOrWhiteSpace(itemId) || itemId.Length > 256 || itemId.Any(char.IsControl))
        throw new InvalidDataException("Identifiant de média Jellyfin invalide.");
    return itemId;
}
static string? ValidateOptionalIdentifier(string? value, string label)
{
    if (string.IsNullOrWhiteSpace(value)) return null;
    var identifier = value.Trim();
    if (identifier.Length > 256 || identifier.Any(char.IsControl))
        throw new InvalidDataException($"Identifiant de {label} invalide.");
    return identifier;
}
static Dictionary<string, string> ParseQuery(string query) => query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries)
    .Select(part => part.Split('=', 2)).ToDictionary(x => Uri.UnescapeDataString(x[0]), x => x.Length > 1 ? Uri.UnescapeDataString(x[1]) : "");
static string ReadSecret()
{
    var result = new System.Text.StringBuilder();
    if (Console.IsInputRedirected) return Console.ReadLine() ?? "";
    while (true)
    {
        var key = Console.ReadKey(true);
        if (key.Key == ConsoleKey.Enter) { Console.WriteLine(); return result.ToString(); }
        if (key.Key == ConsoleKey.Backspace && result.Length > 0) result.Length--;
        else if (!char.IsControl(key.KeyChar)) result.Append(key.KeyChar);
    }
}

sealed record PlaybackRunResult(bool CompletedNaturally, long PositionTicks, long DurationTicks);
sealed record PlaybackMedia(ItemInfo Item, string? MediaSourceId, string Media, TimeSpan? ResumeAt);
