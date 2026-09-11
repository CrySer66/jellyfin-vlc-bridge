using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

internal static class DesktopControlTests
{
    private static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        Console.InputEncoding = new UTF8Encoding(false);
        if (args.Length > 0 && args[0] == "--mock") return Mock(args.Skip(1).ToArray());
        try
        {
            Run(args[0]).GetAwaiter().GetResult();
            return 0;
        }
        catch (Exception exception) { Console.Error.WriteLine(exception); return 1; }
    }

    private static int Mock(string[] args)
    {
        if (args[0] == "echo")
        {
            Console.Write(DesktopBridge.Json.Serialize(new Dictionary<string, object> { { "arguments", args.Skip(1).ToArray() } }));
            return 0;
        }
        if (args[0] == "flood")
        {
            for (int i = 0; i < 64; i++) Console.Error.Write(new string('x', 65536));
            Console.Write("été 日本語");
            return 0;
        }
        if (args[0] == "hang")
        {
            File.WriteAllText(args[1], Process.GetCurrentProcess().Id.ToString());
            Thread.Sleep(60000);
            return 0;
        }
        if (args[0] == "error") { Console.Error.Write("échec contrôlé"); return 7; }
        Console.Write("{\"ready\":true,\"name\":\"été\"}");
        return 0;
    }

    private static async Task Run(string root)
    {
        using (var bridge = new DesktopBridge())
        {
            string[] values = { "", "plain", "two words", @"C:\folder with space\", "a\"b", @"a\\\""b\", "é 日本語", "line\tvalue", "& | $() %PATH%" };
            string[] arguments = new[] { "--mock", "echo" }.Concat(values).ToArray();
            Dictionary<string, object> echoed = await bridge.RunJson(arguments, 10);
            string[] received = ((IEnumerable)echoed["arguments"]).Cast<object>().Select(value => value.ToString()).ToArray();
            Equal(String.Join("\u001f", values), String.Join("\u001f", received));
            Console.WriteLine("OK  Windows arguments round-trip, including quotes and trailing backslashes");

            Equal("été 日本語", await bridge.Run(new[] { "--mock", "flood" }, 10));
            Console.WriteLine("OK  UTF-8 output and simultaneous draining of 4 MB stderr");

            Dictionary<string, object> result = await bridge.RunJson(new[] { "--mock", "json" }, 10);
            Equal(true, DesktopBridge.Flag(result, "READY"));
            Equal("été", DesktopBridge.Text(result, "Name"));
            Equal("", DesktopBridge.Text(result, "absent"));
            Equal(false, DesktopBridge.Flag(result, "absent"));
            await Throws<InvalidOperationException>(delegate { return bridge.Run(new[] { "--mock", "error" }, 10); });
            Console.WriteLine("OK  JSON helpers and process failure reporting");

            string timeoutPid = Path.Combine(root, "timeout.pid");
            await Throws<TimeoutException>(delegate { return bridge.RunProcess(HangingProcess(timeoutPid), 1, CancellationToken.None); });
            AssertStopped(timeoutPid);
            Console.WriteLine("OK  Timeout terminates and reaps the child process");

            string canceledPid = Path.Combine(root, "canceled.pid");
            using (var cancellation = new CancellationTokenSource())
            {
                Task<string> pending = bridge.RunProcess(HangingProcess(canceledPid), 30, cancellation.Token);
                await WaitForFile(canceledPid);
                cancellation.Cancel();
                await Throws<OperationCanceledException>(delegate { return pending; });
                AssertStopped(canceledPid);
            }
            Console.WriteLine("OK  Explicit cancellation terminates the child process");
        }

        var disposedBridge = new DesktopBridge();
        string disposedPid = Path.Combine(root, "disposed.pid");
        string secondDisposedPid = Path.Combine(root, "disposed-second.pid");
        Task<string> disposedTask = disposedBridge.RunProcess(HangingProcess(disposedPid), 30, CancellationToken.None);
        Task<string> secondDisposedTask = disposedBridge.RunProcess(HangingProcess(secondDisposedPid), 30, CancellationToken.None);
        await WaitForFile(disposedPid);
        await WaitForFile(secondDisposedPid);
        disposedBridge.Dispose();
        disposedBridge.Dispose();
        await Throws<OperationCanceledException>(delegate { return disposedTask; });
        await Throws<OperationCanceledException>(delegate { return secondDisposedTask; });
        AssertStopped(disposedPid);
        AssertStopped(secondDisposedPid);
        await Throws<ObjectDisposedException>(delegate { return disposedBridge.Run(new[] { "--mock", "json" }, 10); });
        Console.WriteLine("OK  Disposing the window service cancels children and prevents new commands");

        TestSettings(root);
    }

    private static ProcessStartInfo HangingProcess(string pidPath)
    {
        return new ProcessStartInfo(Process.GetCurrentProcess().MainModule.FileName,
            "--mock hang " + DesktopBridge.Quote(pidPath));
    }

    private static async Task WaitForFile(string path)
    {
        Stopwatch watch = Stopwatch.StartNew();
        while (!File.Exists(path) || new FileInfo(path).Length == 0)
        {
            if (watch.Elapsed > TimeSpan.FromSeconds(5)) throw new TimeoutException("The test process did not start.");
            await Task.Delay(20);
        }
    }

    private static void AssertStopped(string pidPath)
    {
        if (!File.Exists(pidPath)) throw new Exception("The child process did not record its PID.");
        int pid = Int32.Parse(File.ReadAllText(pidPath));
        try
        {
            using (Process process = Process.GetProcessById(pid))
                if (!process.HasExited) throw new Exception("Child process is still running: " + pid);
        }
        catch (ArgumentException) { }
    }

    private static void TestSettings(string root)
    {
        string path = Path.Combine(root, "config.json");
        var config = new Dictionary<string, object>
        {
            { "ServerUrl", "http://jellyfin:8096/base" },
            { "UserId", "saved-user" }, { "DeviceId", "saved-device" }, { "AccessToken", "fictional-preserved-token" },
            { "PlaybackMode", "http" }, { "VlcPath", null }, { "ProgressSyncEnabled", false },
            { "futureProperty", new Dictionary<string, object> { { "value", 42 } } },
            { "PathMappings", new object[] {
                new Dictionary<string, object> { { "ServerPrefix", "/media" }, { "ClientPrefix", @"\\old\media" }, { "priority", 7 } },
                new Dictionary<string, object> { { "ServerPrefix", "/series" }, { "ClientPrefix", @"\\nas\series" } }
            } }
        };
        DesktopBridge.WriteJson(path, config);
        DesktopBridge.SavePlaybackSettings(path, "http://jellyfin:8096/base/", "SMB", @" C:\VLC\vlc.exe ", "/films", @"\\nas\films");
        Dictionary<string, object> saved = DesktopBridge.Parse(File.ReadAllText(path));
        Equal(config.Count, saved.Count);
        Equal("smb", DesktopBridge.Text(saved, "PlaybackMode"));
        Equal(@"C:\VLC\vlc.exe", DesktopBridge.Text(saved, "VlcPath"));
        Equal("saved-user", DesktopBridge.Text(saved, "UserId"));
        Equal("saved-device", DesktopBridge.Text(saved, "DeviceId"));
        Equal("fictional-preserved-token", DesktopBridge.Text(saved, "AccessToken"));
        Equal(false, DesktopBridge.Flag(saved, "ProgressSyncEnabled"));
        Equal("42", DesktopBridge.Text((IDictionary<string, object>)saved["futureProperty"], "value"));
        object[] mappings = ((IEnumerable)saved["PathMappings"]).Cast<object>().ToArray();
        Equal(2, mappings.Length);
        Equal("/films", DesktopBridge.Text((IDictionary<string, object>)mappings[0], "serverPrefix"));
        Equal("7", DesktopBridge.Text((IDictionary<string, object>)mappings[0], "priority"));
        Equal("/series", DesktopBridge.Text((IDictionary<string, object>)mappings[1], "ServerPrefix"));
        Equal(@"\\nas\series", DesktopBridge.Text((IDictionary<string, object>)mappings[1], "clientPrefix"));
        string mappingJson = DesktopBridge.Json.Serialize(saved["PathMappings"]);
        DesktopBridge.SavePlaybackSettings(path, "http://jellyfin:8096/base", "http", "", "", "");
        saved = DesktopBridge.Parse(File.ReadAllText(path));
        Equal(mappingJson, DesktopBridge.Json.Serialize(saved["PathMappings"]));
        Equal(null, saved["VlcPath"]);
        Console.WriteLine("OK  Settings preserve account, unknown properties, progress and additional SMB mappings");

        string unchanged = File.ReadAllText(path);
        ThrowsSync<InvalidOperationException>(delegate
        {
            DesktopBridge.SavePlaybackSettings(path, "http://old-server", "http", "", "", "");
        });
        ThrowsSync<InvalidDataException>(delegate
        {
            DesktopBridge.SavePlaybackSettings(path, "http://jellyfin:8096/base", "smb", "", "", @"\\nas\films");
        });
        Equal(unchanged, File.ReadAllText(path));
        string blockedTarget = Path.Combine(root, "directory-target");
        Directory.CreateDirectory(blockedTarget);
        ThrowsSync<IOException>(delegate { DesktopBridge.WriteJson(blockedTarget, config); });
        Equal(0, Directory.GetFiles(root, "*.tmp-*").Length);
        Console.WriteLine("OK  Stale settings and invalid mappings are rejected; atomic writes clean temporary files");
    }

    private static void Equal<T>(T expected, T actual)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
            throw new Exception("Expected " + expected + ", got " + actual);
    }

    private static async Task Throws<T>(Func<Task> action) where T : Exception
    {
        try { await action(); }
        catch (T) { return; }
        throw new Exception("Expected " + typeof(T).Name);
    }

    private static void ThrowsSync<T>(Action action) where T : Exception
    {
        try { action(); }
        catch (T) { return; }
        throw new Exception("Expected " + typeof(T).Name);
    }
}
