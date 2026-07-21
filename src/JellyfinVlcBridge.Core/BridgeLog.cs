namespace JellyfinVlcBridge.Core;

public static class BridgeLog
{
    private static readonly object Gate = new();
    public static string DirectoryPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "JellyfinVlcBridge", "Logs");
    public static string FilePath => Path.Combine(DirectoryPath, "bridge.log");

    public static void Info(string message) => Write("INFO", message);
    public static void Warning(string message) => Write("WARN", message);
    public static void Error(string message) => Write("ERROR", message);

    private static void Write(string level, string message)
    {
        try
        {
            lock (Gate)
            {
                Directory.CreateDirectory(DirectoryPath);
                if (File.Exists(FilePath) && new FileInfo(FilePath).Length > 2 * 1024 * 1024)
                {
                    var previous = Path.Combine(DirectoryPath, "bridge.previous.log");
                    File.Move(FilePath, previous, true);
                }
                File.AppendAllText(FilePath, $"{DateTimeOffset.Now:O} [{level}] {message}{Environment.NewLine}");
            }
        }
        catch { /* Logging must never prevent playback. */ }
    }
}
