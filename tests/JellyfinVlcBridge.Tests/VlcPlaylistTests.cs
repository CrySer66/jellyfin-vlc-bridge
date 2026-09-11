using JellyfinVlcBridge.Core;
using System.Text.Json;

internal static class VlcPlaylistTests
{
    public static Task RunAsync()
    {
        using var nested = JsonDocument.Parse("""
        {"type":"node","id":"0","children":[{"type":"node","id":"1","children":[
          {"type":"leaf","id":"4","uri":"http://127.0.0.1:1234/first"},
          {"type":"leaf","id":"7","uri":"http://127.0.0.1:1234/second"},
          {"type":"leaf","id":"11","uri":"http://127.0.0.1:1234/third"}
        ]}]}
        """);
        var snapshot = VlcPlaylistSnapshot.Parse(nested.RootElement);
        string[] media = ["http://127.0.0.1:1234/first", "http://127.0.0.1:1234/second", "http://127.0.0.1:1234/third"];
        // Direct jump, previous and another pass through the same entry.
        var ids = new[] { 4, 11, 7, 4, 11 };
        var expected = new[] { 0, 2, 1, 0, 2 };
        for (var i = 0; i < ids.Length; i++) Equal(expected[i], snapshot.FindMediaIndex(ids[i], media));
        Equal(-1, snapshot.FindMediaIndex(90, media));
        Equal(-1, snapshot.FindMediaIndex(4, [media[0], media[0]]));

        using var flat = JsonDocument.Parse("""
        [{"type":"leaf","id":22,"uri":"http://127.0.0.1:1234/second"},
         {"type":"leaf","id":"23","uri":"file:///C:/Films/Mon%20film.mkv"},
         {"type":"leaf","id":"24","uri":"file://nas/Films/Mon%20film.mkv"},
         {"id":"incorrect","uri":"http://127.0.0.1:1234/first"}]
        """);
        var flatSnapshot = VlcPlaylistSnapshot.Parse(flat.RootElement);
        Equal(1, flatSnapshot.FindMediaIndex(22, media));
        if (OperatingSystem.IsWindows())
        {
            Equal(0, flatSnapshot.FindMediaIndex(23, [@"C:\Films\Mon film.mkv"]));
            Equal(0, flatSnapshot.FindMediaIndex(24, [@"\\nas\Films\Mon film.mkv"]));
        }
        Equal(-1, flatSnapshot.FindMediaIndex(22, ["http://127.0.0.1:1234/SECOND"]));
        return Task.CompletedTask;
    }

    private static void Equal(int expected, int actual)
    {
        if (expected != actual) throw new InvalidOperationException($"Index attendu : {expected}, obtenu : {actual}.");
    }
}
