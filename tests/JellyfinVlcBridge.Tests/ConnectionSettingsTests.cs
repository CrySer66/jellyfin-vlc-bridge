using JellyfinVlcBridge.Core;

internal static class ConnectionSettingsTests
{
    public static Task RunAsync()
    {
        var directory = Path.Combine(Path.GetTempPath(), "JvbConnectionTest-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, "config.json");
        var previous = new BridgeConfig { ServerUrl = "http://test.invalid", UserId = "previous-user", DeviceId = "device" };
        var updated = previous with { UserId = "new-user" };
        var key = SecretKeys.ForServer(previous.ServerUrl);
        var store = new FakeSecretStore();
        store.Secrets[key] = "previous-token";
        try
        {
            previous.Save(path);
            var original = File.ReadAllText(path);
            store.FailNextWrite = true;
            Throws<IOException>(() => ConnectionSettingsStore.Save(updated, "new-token", store, path));
            Equal(original, File.ReadAllText(path));
            Equal("previous-token", store.Read(key));

            if (OperatingSystem.IsWindows())
            {
                using (var locked = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
                    ThrowsWriteFailure(() => ConnectionSettingsStore.Save(updated, "new-token", store, path));
                Equal(original, File.ReadAllText(path));
                Equal("previous-token", store.Read(key));
            }

            var blockedPath = Path.Combine(directory, "directory-instead-of-config");
            Directory.CreateDirectory(blockedPath);
            ThrowsWriteFailure(() => ConnectionSettingsStore.Save(updated, "new-token", store, blockedPath));
            Equal("previous-token", store.Read(key));

            var fresh = updated with { ServerUrl = "http://new-server.invalid" };
            ThrowsWriteFailure(() => ConnectionSettingsStore.Save(fresh, "new-token", store, blockedPath));
            Equal(null, store.Read(SecretKeys.ForServer(fresh.ServerUrl)));
            Equal("previous-token", store.Read(key));
            Equal(0, Directory.GetFiles(directory, "*.tmp-*").Length);

            Throws<InvalidDataException>(() => ConnectionSettingsStore.Save(updated with { UserId = "" }, "new-token", store, path));
            Equal("previous-token", store.Read(key));
            Equal(original, File.ReadAllText(path));

            ConnectionSettingsStore.Save(updated, "new-token", store, path);
            Equal("new-user", BridgeConfig.Load(path).UserId);
            Equal("device", BridgeConfig.Load(path).DeviceId);
            Equal("new-token", store.Read(key));
        }
        finally { Directory.Delete(directory, true); }
        return Task.CompletedTask;
    }

    private static void Equal<T>(T expected, T actual)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual)) throw new Exception($"Expected {expected}, got {actual}.");
    }

    private static void Throws<T>(Action action) where T : Exception
    {
        try { action(); }
        catch (T) { return; }
        throw new Exception($"Expected {typeof(T).Name}.");
    }

    private static void ThrowsWriteFailure(Action action)
    {
        try { action(); }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException) { return; }
        throw new Exception("Expected a file write failure.");
    }

    private sealed class FakeSecretStore : ISecretStore
    {
        internal Dictionary<string, string> Secrets { get; } = [];
        internal bool FailNextWrite { get; set; }
        public string? Read(string key) => Secrets.GetValueOrDefault(key);
        public void Write(string key, string secret)
        {
            if (FailNextWrite) { FailNextWrite = false; throw new IOException("Simulated credential failure."); }
            Secrets[key] = secret;
        }
        public void Delete(string key) => Secrets.Remove(key);
    }
}
