using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("Jellyfin VLC Bridge Control Center")]
[assembly: AssemblyDescription("Lance le centre de contrôle sans fenêtre de console")]
[assembly: AssemblyCompany("Jellyfin VLC Bridge Project")]
[assembly: AssemblyProduct("Jellyfin VLC Bridge")]
[assembly: AssemblyVersion("1.11.0.0")]
[assembly: AssemblyFileVersion("1.11.0.0")]

internal static class ControlCenterBootstrap
{
    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            string directory = AppDomain.CurrentDomain.BaseDirectory;
            string script = Path.Combine(directory, "Centre-Controle.ps1");
            if (!File.Exists(script))
                throw new FileNotFoundException("Le centre de contrôle est incomplet.", script);

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
                if (process == null) throw new InvalidOperationException("Le centre de contrôle n'a pas pu démarrer.");
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
