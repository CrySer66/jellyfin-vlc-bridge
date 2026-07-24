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
[assembly: AssemblyVersion("1.14.0.0")]
[assembly: AssemblyFileVersion("1.14.0.0")]

internal static class SetupBootstrap
{
    private static bool IsFrench { get { return CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "fr"; } }
    private static string Localized(string english, string french) { return IsFrench ? french : english; }

    [STAThread]
    private static int Main()
    {
        string temporaryDirectory = Path.Combine(Path.GetTempPath(), "JellyfinVlcBridgeSetup-" + Guid.NewGuid().ToString("N"));
        try
        {
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
            ProcessStartInfo startInfo = new ProcessStartInfo("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + installer + "\"");
            startInfo.WorkingDirectory = temporaryDirectory;
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;
            using (Process process = Process.Start(startInfo))
            {
                if (process == null)
                    throw new InvalidOperationException(
                        Localized("The installer could not start.", "L’installateur n’a pas pu démarrer."));
                process.WaitForExit();
                if (process.ExitCode != 0)
                    throw new InvalidOperationException(
                        Localized("Installation failed with code ", "L’installation a échoué avec le code ") +
                        process.ExitCode + ".");
            }
            return 0;
        }
        catch (Exception exception)
        {
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
