using System;
using System.Diagnostics;
using System.IO;
using System.Globalization;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("Jellyfin VLC Bridge Control Center")]
[assembly: AssemblyDescription("Lance le centre de contrôle sans fenêtre de console")]
[assembly: AssemblyCompany("Jellyfin VLC Bridge Project")]
[assembly: AssemblyProduct("Jellyfin VLC Bridge")]
[assembly: AssemblyVersion("1.13.0.0")]
[assembly: AssemblyFileVersion("1.13.0.0")]

internal static class ControlCenterBootstrap
{
    private static bool IsFrench { get { return CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "fr"; } }
    private static string Localized(string english, string french) { return IsFrench ? french : english; }

    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            string directory = AppDomain.CurrentDomain.BaseDirectory;
            string script = Path.Combine(directory, "Centre-Controle.ps1");
            if (!File.Exists(script))
                throw new FileNotFoundException(
                    Localized("The Control Center installation is incomplete.", "L’installation du centre de contrôle est incomplète."),
                    script);

            string validationArgument = Array.IndexOf(args, "--validate-only") >= 0 ? " -ValidateOnly" : "";
            var startInfo = new ProcessStartInfo(
                "powershell.exe",
                "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + script + "\"" + validationArgument)
            {
                WorkingDirectory = directory,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using (Process process = Process.Start(startInfo))
            {
                if (process == null)
                    throw new InvalidOperationException(
                        Localized("The Control Center could not start.", "Le centre de contrôle n’a pas pu démarrer."));
                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception exception)
        {
            MessageBox.Show(exception.Message, "Jellyfin VLC Bridge", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
