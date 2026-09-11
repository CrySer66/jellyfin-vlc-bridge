using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Globalization;
using System.Reflection;
using System.Runtime.Versioning;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;

[assembly: AssemblyTitle("Jellyfin VLC Bridge Setup")]
[assembly: AssemblyDescription("Installateur de Jellyfin VLC Bridge")]
[assembly: AssemblyCompany("Jellyfin VLC Bridge Project")]
[assembly: AssemblyProduct("Jellyfin VLC Bridge")]
[assembly: AssemblyVersion("1.19.1.0")]
[assembly: AssemblyFileVersion("1.19.1.0")]
[assembly: TargetFramework(".NETFramework,Version=v4.8")]

internal static class SetupBootstrap
{
    private static bool IsFrench { get { return CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "fr"; } }
    private static string Localized(string english, string french) { return IsFrench ? french : english; }

    private static Window CreateErrorWindow(string message)
    {
        AppContext.SetSwitch("Switch.System.Windows.DoNotScaleForDpiChanges", false);
        var application = Application.Current ?? new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("DesktopTheme.xaml"))
        {
            if (stream == null) throw new InvalidDataException("The embedded desktop theme is missing.");
            using (var reader = new StreamReader(stream))
                application.Resources.MergedDictionaries.Add((ResourceDictionary)XamlReader.Parse(reader.ReadToEnd()));
        }
        // The same dictionary is embedded in the native center and distributed
        // with both maintenance scripts. Even extraction failures keep its identity.
        const string xaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Width='620' SizeToContent='Height' MinHeight='350' MaxHeight='760'
        ResizeMode='NoResize' WindowStartupLocation='CenterScreen'>
  <Grid>
    <Grid.RowDefinitions><RowDefinition Height='Auto'/><RowDefinition Height='Auto'/></Grid.RowDefinitions>
    <Border Background='{StaticResource Sidebar}' Padding='28,22'>
      <StackPanel Orientation='Horizontal'>
        <Image Source='{StaticResource ApplicationIcon}' Width='40' Height='40' Margin='0,0,14,0'/>
        <StackPanel VerticalAlignment='Center'>
          <TextBlock Text='Jellyfin VLC Bridge' Foreground='White' FontSize='20' FontWeight='SemiBold'/>
          <TextBlock x:Name='SetupLabel' Foreground='#B9C9DA' FontSize='13' Margin='0,3,0,0'/>
        </StackPanel>
      </StackPanel>
    </Border>
    <StackPanel Grid.Row='1' Margin='28'>
      <TextBlock x:Name='FailureHeading' Style='{StaticResource SectionTitle}' Margin='0,0,0,10'/>
      <TextBlock x:Name='FailureHint' Style='{StaticResource Caption}' Margin='0,0,0,20'/>
      <Border Style='{StaticResource Card}' Padding='18' Background='#FFF8F8' BorderBrush='#F0DADD'>
        <ScrollViewer MaxHeight='290' VerticalScrollBarVisibility='Auto' HorizontalScrollBarVisibility='Disabled'>
          <TextBlock x:Name='FailureMessage' Foreground='#9E313B' LineHeight='21'/>
        </ScrollViewer>
      </Border>
      <Button x:Name='CloseButton' Style='{StaticResource PrimaryButton}' HorizontalAlignment='Right'
              MinWidth='110' Margin='0,22,0,0' IsDefault='True' IsCancel='True'/>
    </StackPanel>
  </Grid>
</Window>";
        var window = (Window)XamlReader.Parse(xaml);
        window.Title = "Jellyfin VLC Bridge — " + Localized("Installation", "Installation");
        ((TextBlock)window.FindName("SetupLabel")).Text = Localized("Installation", "Installation");
        ((TextBlock)window.FindName("FailureHeading")).Text = Localized("Installation interrupted", "Installation interrompue");
        ((TextBlock)window.FindName("FailureHint")).Text = Localized(
            "The installer could not complete this step. Check the details below before trying again.",
            "L’installateur n’a pas pu terminer cette étape. Vérifiez les détails ci-dessous avant de réessayer.");
        ((TextBlock)window.FindName("FailureMessage")).Text = message;
        var close = (Button)window.FindName("CloseButton");
        close.Content = Localized("Close", "Fermer");
        close.Click += delegate { window.Close(); };
        return window;
    }

    private static void ShowErrorDialog(string message)
    {
        try { CreateErrorWindow(message).ShowDialog(); }
        catch (Exception displayException)
        {
            // If the Windows presentation subsystem is unavailable, leave a
            // useful diagnostic instead of failing recursively in another UI.
            WriteSilentLog(message + Environment.NewLine + displayException);
        }
    }

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
                "-NoProfile -STA -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + installer + "\"" +
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
            else ShowErrorDialog(exception.Message);
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
