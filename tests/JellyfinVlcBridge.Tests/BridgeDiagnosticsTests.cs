using System.Net;
using System.Net.Http.Json;
using JellyfinVlcBridge.Core;

internal static class BridgeDiagnosticsTests
{
    public static async Task RunAsync()
    {
        foreach (var (status, expectedCode, expectedConnected) in new[]
        {
            (HttpStatusCode.Unauthorized, "jellyfin.authentication-required", false),
            (HttpStatusCode.ServiceUnavailable, "jellyfin.unreachable", false),
            (HttpStatusCode.Forbidden, "jellyfin.unreachable", false),
            (HttpStatusCode.OK, "jellyfin.ready", true)
        })
        {
            using var http = new HttpClient(new DiagnosticHandler(status));
            var result = await BridgeDiagnostics.CheckJellyfinConnectionAsync(
                new JellyfinClient(http, "http://test.invalid", "fictional-token", "test-device"));
            if (result.Code != expectedCode || result.Connected != expectedConnected)
                throw new InvalidOperationException($"HTTP {(int)status}: unexpected diagnostic {result.Code}.");
            if (result.Message.Contains("fictional-token", StringComparison.Ordinal))
                throw new InvalidOperationException("A credential appeared in the diagnostic.");
        }
    }

    private sealed class DiagnosticHandler(HttpStatusCode status) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            if (request.RequestUri!.AbsolutePath != "/Users/Me")
                throw new InvalidOperationException("Unexpected diagnostic endpoint.");
            return Task.FromResult(new HttpResponseMessage(status)
            {
                Content = JsonContent.Create(new { Id = "test-user", Name = "Test" })
            });
        }
    }
}
