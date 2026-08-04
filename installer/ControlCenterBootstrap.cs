using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Jellyfin VLC Bridge Control Center")]
[assembly: AssemblyDescription("Lance le centre de contrôle sans fenêtre de console")]
[assembly: AssemblyCompany("Jellyfin VLC Bridge Project")]
[assembly: AssemblyProduct("Jellyfin VLC Bridge")]
[assembly: AssemblyVersion("1.18.0.0")]
[assembly: AssemblyFileVersion("1.18.0.0")]

internal static class ControlCenterBootstrap
{
    private const string MutexName = @"Local\CrySer66.JellyfinVlcBridge.ControlCenter";
    private const string ShowEventName = @"Local\CrySer66.JellyfinVlcBridge.ControlCenter.Show";

    private static bool IsFrench
    {
        get { return CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "fr"; }
    }

    private static string Localized(string english, string french)
    {
        return IsFrench ? french : english;
    }

    [STAThread]
    private static int Main(string[] args)
    {
        bool ownsMutex = false;
        using (var mutex = new Mutex(true, MutexName, out ownsMutex))
        {
            if (!ownsMutex)
            {
                try
                {
                    using (var showEvent = EventWaitHandle.OpenExisting(ShowEventName))
                        showEvent.Set();
                }
                catch (WaitHandleCannotBeOpenedException)
                {
                    MessageBox.Show(
                        Localized(
                            "Jellyfin VLC Bridge is already running in the notification area.",
                            "Jellyfin VLC Bridge fonctionne déjà dans la zone de notification."),
                        "Jellyfin VLC Bridge",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Information);
                }
                return 0;
            }

            try
            {
                using (var showEvent = new EventWaitHandle(
                    false,
                    EventResetMode.AutoReset,
                    ShowEventName))
                {
                    return RunControlCenter(args);
                }
            }
            finally
            {
                mutex.ReleaseMutex();
            }
        }
    }

    private static int RunControlCenter(string[] args)
    {
        try
        {
            string directory = AppDomain.CurrentDomain.BaseDirectory;
            string script = Path.Combine(directory, "Centre-Controle.ps1");
            if (!File.Exists(script))
                throw new FileNotFoundException(
                    Localized(
                        "The Control Center installation is incomplete.",
                        "L’installation du centre de contrôle est incomplète."),
                    script);

            bool validateOnly = Array.IndexOf(args, "--validate-only") >= 0;
            bool startInTray = Array.IndexOf(args, "--tray") >= 0;
            string scriptArguments =
                "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + script + "\"" +
                (validateOnly ? " -ValidateOnly" : "") +
                (startInTray ? " -StartInTray" : "") +
                " -ShowEventName \"" + ShowEventName + "\"";

            var startInfo = new ProcessStartInfo("powershell.exe", scriptArguments)
            {
                WorkingDirectory = directory,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using (Process process = Process.Start(startInfo))
            {
                if (process == null)
                    throw new InvalidOperationException(
                        Localized(
                            "The Control Center could not start.",
                            "Le centre de contrôle n’a pas pu démarrer."));
                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                exception.Message,
                "Jellyfin VLC Bridge",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }
    }
}
