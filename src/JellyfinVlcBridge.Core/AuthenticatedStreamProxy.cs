using System.Net;
using System.Collections.Concurrent;

namespace JellyfinVlcBridge.Core;

public sealed class AuthenticatedStreamProxy(HttpClient http, string upstreamUrl, string jellyfinToken) : IAsyncDisposable
{
    private readonly HttpListener _listener = new();
    private readonly string _nonce = Convert.ToHexString(System.Security.Cryptography.RandomNumberGenerator.GetBytes(18));
    private readonly Dictionary<string, string> _routes = [];
    private readonly HashSet<string> _loggedRoutes = [];
    private readonly ConcurrentDictionary<int, Task> _activeRequests = new();
    private CancellationTokenSource? _cts;
    private Task? _loop;
    private string? _baseUrl;
    private int _requestSequence;

    public string Start()
    {
        var port = FindFreePort();
        _baseUrl = $"http://127.0.0.1:{port}/";
        _routes[_nonce] = upstreamUrl;
        _listener.Prefixes.Add(_baseUrl);
        _listener.Start();
        _cts = new CancellationTokenSource();
        _loop = RunAsync(_cts.Token);
        return _baseUrl + _nonce;
    }

    public string AddStream(string upstream)
    {
        if (_baseUrl is null) throw new InvalidOperationException("Le relais doit être démarré avant d'ajouter un média.");
        var nonce = Convert.ToHexString(System.Security.Cryptography.RandomNumberGenerator.GetBytes(18));
        lock (_routes) _routes[nonce] = upstream;
        return _baseUrl + nonce;
    }

    private async Task RunAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            HttpListenerContext context;
            try { context = await _listener.GetContextAsync().WaitAsync(cancellationToken); }
            catch (OperationCanceledException) { break; }
            catch (ObjectDisposedException) when (cancellationToken.IsCancellationRequested) { break; }
            catch (HttpListenerException) when (cancellationToken.IsCancellationRequested) { break; }

            var requestId = Interlocked.Increment(ref _requestSequence);
            var task = ForwardAsync(context, cancellationToken);
            _activeRequests[requestId] = task;
            _ = task.ContinueWith(
                _completed => _activeRequests.TryRemove(requestId, out _),
                CancellationToken.None,
                TaskContinuationOptions.ExecuteSynchronously,
                TaskScheduler.Default);
        }
    }

    private async Task ForwardAsync(HttpListenerContext context, CancellationToken cancellationToken)
    {
        var route = context.Request.Url?.AbsolutePath.TrimStart('/') ?? "";
        string? selectedUpstream;
        lock (_routes) _routes.TryGetValue(route, out selectedUpstream);
        if (selectedUpstream is null)
        {
            context.Response.StatusCode = 404;
            context.Response.Close();
            return;
        }

        try
        {
            var method = context.Request.HttpMethod.Equals("HEAD", StringComparison.OrdinalIgnoreCase)
                ? HttpMethod.Head : HttpMethod.Get;
            using var request = new HttpRequestMessage(method, selectedUpstream);
            request.Headers.TryAddWithoutValidation("X-Emby-Token", jellyfinToken);
            if (!string.IsNullOrWhiteSpace(context.Request.Headers["Range"]))
                request.Headers.TryAddWithoutValidation("Range", context.Request.Headers["Range"]);
            using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            bool firstRequest;
            lock (_loggedRoutes) firstRequest = _loggedRoutes.Add(route);
            if (firstRequest || !response.IsSuccessStatusCode)
                BridgeLog.Info($"Relais {method} {new Uri(selectedUpstream).AbsolutePath} -> {(int)response.StatusCode}");
            context.Response.StatusCode = (int)response.StatusCode;
            context.Response.ContentType = response.Content.Headers.ContentType?.ToString();
            if (response.Content.Headers.ContentLength is { } length) context.Response.ContentLength64 = length;
            foreach (var header in response.Headers.Concat(response.Content.Headers))
                if (header.Key is not ("Transfer-Encoding" or "Content-Length" or "Content-Type" or "Connection" or "Date" or "Server"))
                    context.Response.Headers[header.Key] = string.Join(",", header.Value);
            if (method != HttpMethod.Head)
                await response.Content.CopyToAsync(context.Response.OutputStream, cancellationToken);
            context.Response.Close();
        }
        catch when (cancellationToken.IsCancellationRequested)
        {
            try { context.Response.Abort(); }
            catch (ObjectDisposedException) { }
            catch (HttpListenerException) { }
        }
        catch (Exception exception)
        {
            BridgeLog.Warning($"Erreur du relais {new Uri(selectedUpstream).AbsolutePath}: {exception.Message}");
            if (context.Response.OutputStream.CanWrite) context.Response.Abort();
        }
    }

    public async ValueTask DisposeAsync()
    {
        _cts?.Cancel();
        _listener.Close();
        if (_loop is not null)
        {
            try { await _loop; }
            catch (OperationCanceledException) { }
            catch (ObjectDisposedException) { }
            catch (HttpListenerException) { }
        }
        var activeRequests = _activeRequests.Values.ToArray();
        if (activeRequests.Length > 0)
        {
            try { await Task.WhenAll(activeRequests); }
            catch (OperationCanceledException) { }
        }
        _cts?.Dispose();
    }

    private static int FindFreePort()
    {
        var listener = new System.Net.Sockets.TcpListener(IPAddress.Loopback, 0);
        try
        {
            listener.Start();
            return ((IPEndPoint)listener.LocalEndpoint).Port;
        }
        finally { listener.Stop(); }
    }
}
