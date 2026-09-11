using System;
using System.Reflection;
using System.Runtime.Versioning;
using System.Threading;
using System.Windows;
using System.Windows.Threading;

[assembly: AssemblyTitle("Jellyfin VLC Bridge Control Center")]
[assembly: AssemblyDescription("Centre de contrôle Windows natif")]
[assembly: AssemblyCompany("Jellyfin VLC Bridge Project")]
[assembly: AssemblyProduct("Jellyfin VLC Bridge")]
[assembly: AssemblyVersion("1.19.0.0")]
[assembly: AssemblyFileVersion("1.19.0.0")]
[assembly: TargetFramework(".NETFramework,Version=v4.8")]

internal static class ControlCenterBootstrap
{
    private const string MutexName = @"Local\CrySer66.JellyfinVlcBridge.ControlCenter";
    private const string ShowEventName = @"Local\CrySer66.JellyfinVlcBridge.ControlCenter.Show";

    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            bool preview = Array.IndexOf(args, "--preview") >= 0;
            bool validate = Array.IndexOf(args, "--validate-only") >= 0;
            string renderPath = Option(args, "--render-preview");
            // Preview and validation never take over or signal the installed instance.
            if (preview || validate || renderPath != null)
                return Run(args, true, validate, renderPath, null);
            bool ownsMutex;
            using (var mutex = new Mutex(true, MutexName, out ownsMutex))
            {
                if (!ownsMutex)
                {
                    for (int attempt = 0; attempt < 20; attempt++)
                    {
                        try
                        {
                            using (var signal = EventWaitHandle.OpenExisting(ShowEventName)) signal.Set();
                            return 0;
                        }
                        catch (WaitHandleCannotBeOpenedException) { Thread.Sleep(100); }
                    }
                    return 1;
                }
                try
                {
                    using (var signal = new EventWaitHandle(false, EventResetMode.AutoReset, ShowEventName))
                        return Run(args, false, false, null, signal);
                }
                finally { mutex.ReleaseMutex(); }
            }
        }
        catch (Exception exception)
        {
            if (Array.IndexOf(args, "--validate-only") < 0 && Option(args, "--render-preview") == null)
                MessageBox.Show(exception.Message, "Jellyfin VLC Bridge", MessageBoxButton.OK, MessageBoxImage.Error);
            // Headless validation must fail promptly rather than block on an error dialog.
            try { Console.Error.WriteLine(exception.ToString()); } catch { }
            return 1;
        }
    }

    private static int Run(string[] args, bool preview, bool validate, string renderPath, EventWaitHandle signal)
    {
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        using (var desktop = new ControlCenterWindow(preview, Option(args, "--language")))
        {
            app.MainWindow = desktop.Window;
            if (validate) { desktop.Validate(); return 0; }
            if (renderPath != null)
            {
                desktop.RenderPreview(renderPath, Option(args, "--page"), Option(args, "--scale"));
                return 0;
            }
            var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
            if (signal != null)
            {
                timer.Tick += delegate { if (signal.WaitOne(0)) desktop.Show(); };
                timer.Start();
            }
            app.SessionEnding += delegate { desktop.AllowExit = true; };
            desktop.Start(Array.IndexOf(args, "--tray") >= 0);
            try { return app.Run(); }
            finally { timer.Stop(); }
        }
    }

    private static string Option(string[] args, string name)
    {
        int index = Array.IndexOf(args, name);
        return index >= 0 && index + 1 < args.Length ? args[index + 1] : null;
    }
}
