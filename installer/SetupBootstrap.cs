using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Globalization;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Jellyfin VLC Bridge Setup")]
[assembly: AssemblyDescription("Installateur de Jellyfin VLC Bridge")]
[assembly: AssemblyCompany("Jellyfin VLC Bridge Project")]
[assembly: AssemblyProduct("Jellyfin VLC Bridge")]
[assembly: AssemblyVersion("1.19.0.0")]
[assembly: AssemblyFileVersion("1.19.0.0")]

internal static class SetupBootstrap
{
    private static bool IsFrench { get { return CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "fr"; } }
    private static string Localized(string english, string french) { return IsFrench ? french : english; }

    private static void WriteSilentLog(string message)
    {
        try
        {
            string log = Path.Combine(Path.GetTempPath(), "JellyfinVlcBridge-setup.log");
            File.AppendAllText(log, DateTimeOffset.Now.ToString("O") + " [ERROR] " + message + Environment.NewLine);
        }
        catch { }
    }

    private static bool IsSilentArgument(string argument)
    {
        switch ((argument ?? "").Trim().ToLowerInvariant())
        {
            case "/s":
            case "/silent":
            case "/quiet":
            case "--silent":
            case "--quiet":
                return true;
            default:
                return false;
        }
    }

    private static void ValidateArguments(string[] args)
    {
        foreach (string argument in args)
        {
            if (!IsSilentArgument(argument))
                throw new ArgumentException(
                    Localized(
                        "Unknown installer option: " + argument,
                        "Option d'installation inconnue : " + argument));
        }
    }

    [STAThread]
    private static int Main(string[] args)
    {
        bool silent = Array.Exists(args, IsSilentArgument);
        string temporaryDirectory = Path.Combine(Path.GetTempPath(), "JellyfinVlcBridgeSetup-" + Guid.NewGuid().ToString("N"));
        try
        {
            ValidateArguments(args);
            Directory.CreateDirectory(temporaryDirectory);
            using (Stream payload = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
            {
                if (payload == null)
                    throw new InvalidDataException(
                        Localized("The internal installation package is missing.", "Le paquet d’installation interne est absent."));
                using (ZipArchive archive = new ZipArchive(payload, ZipArchiveMode.Read))
                {
                    archive.ExtractToDirectory(temporaryDirectory);
                }
            }

            string installer = Path.Combine(temporaryDirectory, "Installer-GUI.ps1");
            if (!File.Exists(installer))
                throw new InvalidDataException(
                    Localized("The internal installation package is incomplete.", "Le paquet d’installation interne est incomplet."));
            string scriptArguments =
                "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + installer + "\"" +
                (silent ? " -Silent" : "");
            ProcessStartInfo startInfo = new ProcessStartInfo("powershell.exe", scriptArguments);
            startInfo.WorkingDirectory = temporaryDirectory;
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;
            using (Process process = Process.Start(startInfo))
            {
                if (process == null)
                    throw new InvalidOperationException(
                        Localized("The installer could not start.", "L’installateur n’a pas pu démarrer."));
                if (silent)
                {
                    if (!process.WaitForExit(120000))
                    {
                        try { process.Kill(); }
                        catch { }
                        process.WaitForExit(5000);
                        throw new TimeoutException(
                            Localized(
                                "Silent installation exceeded the two-minute limit.",
                                "L'installation silencieuse a dépassé le délai de deux minutes."));
                    }
                }
                else process.WaitForExit();
                if (process.ExitCode != 0)
                    throw new InvalidOperationException(
                        Localized("Installation failed with code ", "L’installation a échoué avec le code ") +
                        process.ExitCode + ".");
            }
            return 0;
        }
        catch (Exception exception)
        {
            if (silent) WriteSilentLog(exception.ToString());
            else
                MessageBox.Show(exception.Message, "Jellyfin VLC Bridge Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally
        {
            for (int attempt = 0; attempt < 5 && Directory.Exists(temporaryDirectory); attempt++)
            {
                try { Directory.Delete(temporaryDirectory, true); }
                catch { Thread.Sleep(300); }
            }
        }
    }
}
