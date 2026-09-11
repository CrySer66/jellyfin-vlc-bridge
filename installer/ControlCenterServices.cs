using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

internal sealed class DesktopBridge : IDisposable
{
    internal static readonly string DirectoryPath = AppDomain.CurrentDomain.BaseDirectory;
    internal static readonly string DataPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "JellyfinVlcBridge");
    internal static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = 4 * 1024 * 1024 };
    private static readonly object SettingsGate = new object();
    private readonly object gate = new object();
    private readonly HashSet<Process> children = new HashSet<Process>();
    private readonly CancellationTokenSource lifetime = new CancellationTokenSource();
    private bool disposed;
    private bool lifetimeDisposed;

    internal static Dictionary<string, object> Parse(string value)
    {
        Dictionary<string, object> parsed;
        lock (Json) parsed = Json.Deserialize<Dictionary<string, object>>(value);
        if (parsed == null) throw new InvalidDataException("The Bridge returned an empty JSON object.");
        return parsed;
    }

    private static object Value(IDictionary<string, object> values, string key)
    {
        if (values == null) return null;
        object result;
        if (values.TryGetValue(key, out result)) return result;
        foreach (KeyValuePair<string, object> entry in values)
            if (String.Equals(entry.Key, key, StringComparison.OrdinalIgnoreCase)) return entry.Value;
        return null;
    }

    internal static string Text(IDictionary<string, object> values, string key)
    {
        object value = Value(values, key);
        return value == null ? String.Empty : Convert.ToString(value, CultureInfo.InvariantCulture);
    }

    internal static bool Flag(IDictionary<string, object> values, string key)
    {
        object value = Value(values, key);
        if (value is bool) return (bool)value;
        bool result;
        return Boolean.TryParse(Text(values, key), out result) && result;
    }

    internal Task<string> Run(string[] arguments, int timeoutSeconds, CancellationToken cancellation = default(CancellationToken))
    {
        if (arguments == null) throw new ArgumentNullException("arguments");
        string[] quoted = Array.ConvertAll(arguments, Quote);
        var info = new ProcessStartInfo(Path.Combine(DirectoryPath, "jellyfin-vlc-bridge.exe"), String.Join(" ", quoted));
        info.WorkingDirectory = DirectoryPath;
        return RunProcess(info, timeoutSeconds, cancellation);
    }

    internal async Task<Dictionary<string, object>> RunJson(string[] arguments, int timeoutSeconds)
    {
        return Parse(await Run(arguments, timeoutSeconds).ConfigureAwait(false));
    }

    internal async Task<string> RunProcess(ProcessStartInfo info, int timeoutSeconds, CancellationToken cancellation)
    {
        if (info == null) throw new ArgumentNullException("info");
        if (timeoutSeconds <= 0 || timeoutSeconds > Int32.MaxValue / 1000)
            throw new ArgumentOutOfRangeException("timeoutSeconds");
        cancellation.ThrowIfCancellationRequested();
        info.UseShellExecute = false;
        info.CreateNoWindow = true;
        info.WindowStyle = ProcessWindowStyle.Hidden;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.StandardOutputEncoding = new UTF8Encoding(false);
        info.StandardErrorEncoding = new UTF8Encoding(false);

        var child = new Process { StartInfo = info, EnableRaisingEvents = true };
        var exited = new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously);
        child.Exited += delegate
        {
            try { exited.TrySetResult(child.ExitCode); }
            catch (InvalidOperationException) { }
        };
        CancellationTokenSource linked = null;
        Task<string> stdout = null;
        Task<string> stderr = null;
        Task completion = null;
        try
        {
            lock (gate)
            {
                if (disposed) throw new ObjectDisposedException("DesktopBridge");
                linked = CancellationTokenSource.CreateLinkedTokenSource(cancellation, lifetime.Token);
                linked.Token.ThrowIfCancellationRequested();
                if (!child.Start()) throw new InvalidOperationException("The Bridge process could not start.");
                children.Add(child);
            }
            // Drain both pipes immediately: a full stderr pipe must not block stdout or process exit.
            stdout = child.StandardOutput.ReadToEndAsync();
            stderr = child.StandardError.ReadToEndAsync();
            if (child.HasExited) exited.TrySetResult(child.ExitCode);
            completion = Task.WhenAll(exited.Task, stdout, stderr);
            using (var deadline = CancellationTokenSource.CreateLinkedTokenSource(linked.Token))
            {
                deadline.CancelAfter(TimeSpan.FromSeconds(timeoutSeconds));
                Task interrupted = Task.Delay(Timeout.Infinite, deadline.Token);
                Task finished = await Task.WhenAny(completion, interrupted).ConfigureAwait(false);
                if (finished != completion)
                {
                    StopChild(child);
                    linked.Token.ThrowIfCancellationRequested();
                    throw new TimeoutException("The Bridge did not respond within " + timeoutSeconds + " seconds.");
                }
                await completion.ConfigureAwait(false);
                linked.Token.ThrowIfCancellationRequested();
                if (exited.Task.Result != 0)
                {
                    string details = String.IsNullOrWhiteSpace(stderr.Result) ? stdout.Result : stderr.Result;
                    details = details.Trim();
                    if (details.Length > 4096) details = details.Substring(details.Length - 4096);
                    throw new InvalidOperationException(String.IsNullOrWhiteSpace(details)
                        ? "The Bridge command failed (exit " + exited.Task.Result + ")." : details);
                }
                return stdout.Result;
            }
        }
        finally
        {
            StopChild(child);
            // Closing the readers also releases pending reads if another process inherited a pipe.
            CloseReader(child, true);
            CloseReader(child, false);
            ObserveFailure(stdout);
            ObserveFailure(stderr);
            ObserveFailure(completion);
            lock (gate)
            {
                children.Remove(child);
                DisposeLifetimeIfIdle();
            }
            if (linked != null) linked.Dispose();
            child.Dispose();
        }
    }

    private static void CloseReader(Process process, bool standardOutput)
    {
        try
        {
            if (standardOutput) process.StandardOutput.Dispose();
            else process.StandardError.Dispose();
        }
        catch (InvalidOperationException) { }
        catch (IOException) { }
    }

    private static void ObserveFailure(Task task)
    {
        if (task == null) return;
        task.ContinueWith(delegate(Task failed) { var ignored = failed.Exception; },
            CancellationToken.None, TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously,
            TaskScheduler.Default);
    }

    private static void StopChild(Process process)
    {
        try
        {
            if (!process.HasExited) process.Kill();
            process.WaitForExit(5000);
        }
        catch (InvalidOperationException) { }
        catch (System.ComponentModel.Win32Exception) { }
    }

    public void Dispose()
    {
        Process[] active;
        lock (gate)
        {
            if (disposed) return;
            disposed = true;
            lifetime.Cancel();
            active = new Process[children.Count];
            children.CopyTo(active);
            DisposeLifetimeIfIdle();
        }
        foreach (Process child in active) StopChild(child);
    }

    private void DisposeLifetimeIfIdle()
    {
        if (disposed && children.Count == 0 && !lifetimeDisposed)
        {
            lifetimeDisposed = true;
            lifetime.Dispose();
        }
    }

    internal static string Quote(string value)
    {
        if (value == null) throw new ArgumentNullException("value");
        var result = new StringBuilder("\"");
        int slashes = 0;
        foreach (char character in value)
        {
            if (character == '\\') { slashes++; continue; }
            if (character == '"')
                result.Append('\\', slashes * 2 + 1);
            else
                result.Append('\\', slashes);
            result.Append(character);
            slashes = 0;
        }
        result.Append('\\', slashes * 2);
        return result.Append('"').ToString();
    }

    internal static void WriteJson(string path, IDictionary<string, object> values)
    {
        string fullPath = Path.GetFullPath(path);
        string parent = Path.GetDirectoryName(fullPath);
        Directory.CreateDirectory(parent);
        string temporary = fullPath + ".tmp-" + Guid.NewGuid().ToString("N");
        try
        {
            string content;
            lock (Json) content = Json.Serialize(values);
            byte[] bytes = new UTF8Encoding(false).GetBytes(content);
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                stream.Write(bytes, 0, bytes.Length);
                stream.Flush(true);
            }
            if (File.Exists(fullPath)) File.Replace(temporary, fullPath, null);
            else File.Move(temporary, fullPath);
        }
        finally
        {
            try { if (File.Exists(temporary)) File.Delete(temporary); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }

    internal static void SavePlaybackSettings(string path, string expectedServer, string mode, string vlc,
        string serverPrefix, string clientPrefix)
    {
        mode = (mode ?? String.Empty).Trim().ToLowerInvariant();
        if (mode != "http" && mode != "smb") throw new InvalidDataException("The playback mode must be HTTP or SMB.");
        if (mode == "smb" && (String.IsNullOrWhiteSpace(serverPrefix) || String.IsNullOrWhiteSpace(clientPrefix)))
            throw new InvalidDataException("SMB playback requires both folder paths.");
        lock (SettingsGate)
        {
            string original = File.ReadAllText(path);
            Dictionary<string, object> config = Parse(original);
            if (String.IsNullOrWhiteSpace(expectedServer) ||
                !String.Equals(Text(config, "serverUrl").TrimEnd('/'), expectedServer.Trim().TrimEnd('/'), StringComparison.Ordinal))
                throw new InvalidOperationException("The Jellyfin server changed. Refresh the settings before saving.");
            SetValue(config, "playbackMode", mode);
            SetValue(config, "vlcPath", String.IsNullOrWhiteSpace(vlc) ? null : vlc.Trim());
            if (mode == "smb")
            {
                var mappings = new List<object>();
                object savedMappings = Value(config, "pathMappings");
                if (savedMappings != null)
                {
                    IEnumerable sequence = savedMappings as IEnumerable;
                    if (sequence == null || savedMappings is string || savedMappings is IDictionary)
                        throw new InvalidDataException("The saved SMB folder mappings are invalid.");
                    foreach (object mapping in sequence) mappings.Add(mapping);
                }
                var first = mappings.Count == 0 ? null : mappings[0] as IDictionary<string, object>;
                var replacement = first == null ? new Dictionary<string, object>() : new Dictionary<string, object>(first);
                SetValue(replacement, "serverPrefix", serverPrefix.Trim());
                SetValue(replacement, "clientPrefix", clientPrefix.Trim());
                if (mappings.Count == 0) mappings.Add(replacement);
                else mappings[0] = replacement;
                SetValue(config, "pathMappings", mappings);
            }
            if (!String.Equals(original, File.ReadAllText(path), StringComparison.Ordinal))
                throw new InvalidOperationException("The configuration changed. Refresh the settings before saving.");
            WriteJson(path, config);
        }
    }

    private static void SetValue(IDictionary<string, object> values, string key, object value)
    {
        foreach (string savedKey in new List<string>(values.Keys))
        {
            if (!String.Equals(savedKey, key, StringComparison.OrdinalIgnoreCase)) continue;
            values[savedKey] = value;
            return;
        }
        values[key] = value;
    }
}
