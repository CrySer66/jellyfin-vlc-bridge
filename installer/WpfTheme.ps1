# Shared desktop identity for the installer and uninstaller. Load in Windows
# PowerShell 5.1 using -STA. No Application.Run or Windows Forms UI is required.
$script:JvbWpfThemeDirectory = $PSScriptRoot

function Initialize-JvbWpfTheme {
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) {
        throw 'The Jellyfin VLC Bridge interface requires an STA thread.'
    }

    if (-not ('JellyfinVlcBridge.WpfNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace JellyfinVlcBridge
{
    public static class WpfNative
    {
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
        [DllImport("shcore.dll")]
        public static extern int SetProcessDpiAwareness(int value);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetProcessDPIAware();
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        public static extern int SetCurrentProcessExplicitAppUserModelID(string value);
        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);
    }
}
'@
    }

    if (-not $script:JvbWpfInitialized) {
        # The process must opt in before WPF creates its first HWND. These calls
        # affect only this process and fall back on older supported Windows.
        $dpiReady = $false
        try { $dpiReady = [JellyfinVlcBridge.WpfNative]::SetProcessDpiAwarenessContext([IntPtr]::new(-4)) } catch { }
        if (-not $dpiReady) {
            try { $dpiReady = [JellyfinVlcBridge.WpfNative]::SetProcessDpiAwareness(2) -eq 0 } catch { }
        }
        if (-not $dpiReady) { try { [void][JellyfinVlcBridge.WpfNative]::SetProcessDPIAware() } catch { } }
        try { [AppContext]::SetSwitch('Switch.System.Windows.DoNotScaleForDpiChanges', $false) } catch { }
        try { [void][JellyfinVlcBridge.WpfNative]::SetCurrentProcessExplicitAppUserModelID('CrySer66.JellyfinVlcBridge') } catch { }
        Add-Type -AssemblyName WindowsBase, PresentationCore, PresentationFramework, System.Xaml
        $script:JvbWpfInitialized = $true
    }

    if ($null -eq [Windows.Application]::Current) {
        $script:JvbWpfApplication = New-Object Windows.Application
        $script:JvbWpfApplication.ShutdownMode = [Windows.ShutdownMode]::OnExplicitShutdown
    }
    $application = [Windows.Application]::Current
    if (-not $application.Dispatcher.CheckAccess()) { throw 'The WPF application belongs to another thread.' }
    if ($null -eq $script:JvbWpfResources) {
        $themePath = Join-Path $script:JvbWpfThemeDirectory 'DesktopTheme.xaml'
        if (-not (Test-Path -LiteralPath $themePath -PathType Leaf)) { throw "Missing desktop theme: $themePath" }
        $script:JvbWpfResources = [Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText($themePath))
        $application.Resources.MergedDictionaries.Add($script:JvbWpfResources)
    }

    # The existing localization file contains en/fr tables. Flat maps remain
    # supported for isolated previews and callers that already selected a locale.
    $messages = $script:JvbMessages
    if ($messages -is [Collections.IDictionary]) {
        $language = $script:JvbLanguage
        if ($language -ne 'fr' -and $language -ne 'en') {
            $language = if ([Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'fr') { 'fr' } else { 'en' }
        }
        if ($messages['en'] -is [Collections.IDictionary]) {
            foreach ($entry in $messages['en'].GetEnumerator()) { $application.Resources[$entry.Key] = $entry.Value }
            if ($messages[$language] -is [Collections.IDictionary]) {
                foreach ($entry in $messages[$language].GetEnumerator()) { $application.Resources[$entry.Key] = $entry.Value }
            }
        }
        else {
            foreach ($entry in $messages.GetEnumerator()) { $application.Resources[$entry.Key] = $entry.Value }
        }
    }
}

function New-JvbWpfWindow {
    param([Parameter(Mandatory = $true)][string]$Xaml)
    Initialize-JvbWpfTheme
    # StaticResource styles must already be in Application.Resources here.
    $window = [Windows.Markup.XamlReader]::Parse($Xaml)
    if ($window -isnot [Windows.Window]) { throw 'The desktop XAML must contain a Window.' }
    $window.UseLayoutRounding = $true
    $window.SnapsToDevicePixels = $true
    $window.Language = [Windows.Markup.XmlLanguage]::GetLanguage(
        $(if ($script:JvbLanguage -eq 'fr') { 'fr-FR' } else { 'en-US' }))
    $iconPath = Join-Path $script:JvbWpfThemeDirectory 'jellyfin-vlc-bridge-control.exe'
    if (Test-Path -LiteralPath $iconPath -PathType Leaf) {
        try {
            Add-Type -AssemblyName System.Drawing
            $icon = [Drawing.Icon]::ExtractAssociatedIcon($iconPath)
            try {
                $window.Icon = [Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
                    $icon.Handle, [Windows.Int32Rect]::Empty, [Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
                $window.Icon.Freeze()
            }
            finally { if ($icon) { $icon.Dispose() } }
        }
        catch { }
    }
    $window.Add_SourceInitialized({
        try {
            $handle = (New-Object Windows.Interop.WindowInteropHelper($this)).Handle
            $rounded = 2
            [void][JellyfinVlcBridge.WpfNative]::DwmSetWindowAttribute($handle, 33, [ref]$rounded, 4)
        }
        catch { }
    })
    return $window
}

function Invoke-JvbWpfRender {
    param([Parameter(Mandatory = $true)]$Window)
    $Window.UpdateLayout()
    # A Render-priority no-op lets already queued layout and paint operations
    # run before the caller begins a synchronous local install/uninstall step.
    [void]$Window.Dispatcher.Invoke([Windows.Threading.DispatcherPriority]::Render, [Action]{ })
}

function Show-JvbWpfMessage {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Information', 'Warning', 'Error', 'Success')][string]$Kind = 'Information'
    )
    $dialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="560" SizeToContent="Height" MinHeight="230" MaxHeight="720"
        ResizeMode="NoResize" WindowStartupLocation="CenterScreen" ShowInTaskbar="False">
  <Grid Margin="28">
    <Grid.RowDefinitions><RowDefinition Height="Auto" /><RowDefinition Height="Auto" /><RowDefinition Height="Auto" /></Grid.RowDefinitions>
    <StackPanel Orientation="Horizontal" Margin="0,0,0,20">
      <Border x:Name="MessageBadge" Width="40" Height="40" Background="#DEF1EC" CornerRadius="12" Margin="0,0,14,0">
        <TextBlock x:Name="MessageSymbol" Text="i" Foreground="#087C73" FontSize="22" FontWeight="SemiBold" HorizontalAlignment="Center" VerticalAlignment="Center" />
      </Border>
      <TextBlock x:Name="MessageTitle" Style="{StaticResource SectionTitle}" VerticalAlignment="Center" MaxWidth="416" />
    </StackPanel>
    <ScrollViewer Grid.Row="1" MaxHeight="460" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
      <TextBlock x:Name="MessageBody" Style="{StaticResource Caption}" FontSize="14" Foreground="{StaticResource Ink}" Margin="0,0,8,0" />
    </ScrollViewer>
    <Button x:Name="MessageClose" Grid.Row="2" Content="OK" Style="{StaticResource PrimaryButton}" HorizontalAlignment="Right" MinWidth="100" Margin="0,24,0,0" IsDefault="True" IsCancel="True" />
  </Grid>
</Window>
'@
    $dialog = New-JvbWpfWindow -Xaml $dialogXaml
    $dialog.Title = $Title
    $dialog.FindName('MessageTitle').Text = $Title
    $dialog.FindName('MessageBody').Text = $Message
    $closeText = [Windows.Application]::Current.TryFindResource('Close')
    if ($closeText) { $dialog.FindName('MessageClose').Content = $closeText }
    if ($Kind -eq 'Error') {
        $dialog.FindName('MessageBadge').Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#FAE9EB')
        $dialog.FindName('MessageSymbol').Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#B63D45')
        $dialog.FindName('MessageSymbol').Text = '!'
    }
    elseif ($Kind -eq 'Warning') {
        $dialog.FindName('MessageBadge').Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#FFF2DD')
        $dialog.FindName('MessageSymbol').Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#966219')
        $dialog.FindName('MessageSymbol').Text = '!'
    }
    elseif ($Kind -eq 'Success') { $dialog.FindName('MessageSymbol').Text = [char]0x2713 }
    foreach ($candidate in [Windows.Application]::Current.Windows) {
        if ($candidate -ne $dialog -and $candidate.IsActive -and $candidate.IsVisible) {
            $dialog.Owner = $candidate
            $dialog.WindowStartupLocation = [Windows.WindowStartupLocation]::CenterOwner
            break
        }
    }
    # Close through the button's visual owner; neither handlers nor dialogs keep
    # a global owner reference that could outlive an uninstall window.
    $dialog.FindName('MessageClose').Add_Click({ [Windows.Window]::GetWindow($this).Close() })
    [void]$dialog.ShowDialog()
}

function Save-JvbWpfPreview {
    param(
        [Parameter(Mandatory = $true)]$Window,
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateRange(1.0, 3.0)][double]$Scale = 1.0
    )
    if ($Window.IsVisible) { throw 'Preview rendering requires an unshown window.' }
    $content = $Window.Content
    if ($content -isnot [Windows.FrameworkElement]) { throw 'Preview content must be a FrameworkElement.' }
    $width = $Window.Width
    $height = $Window.Height
    if ([double]::IsNaN($width) -or [double]::IsNaN($height) -or $width -le 0 -or $height -le 0) {
        throw 'Preview windows must specify a positive Width and Height.'
    }
    $size = [Windows.Size]::new($width, $height)
    $content.Measure($size)
    $content.Arrange([Windows.Rect]::new(0, 0, $width, $height))
    $content.UpdateLayout()
    $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new(
        [int][Math]::Ceiling($width * $Scale), [int][Math]::Ceiling($height * $Scale),
        96 * $Scale, 96 * $Scale, [Windows.Media.PixelFormats]::Pbgra32)
    # Paint the window's canvas first. Rendering Content alone otherwise makes
    # transparent panels black in PNG viewers and hides the shared light theme.
    $background = New-Object Windows.Media.DrawingVisual
    $drawing = $background.RenderOpen()
    try { $drawing.DrawRectangle($Window.Background, $null, [Windows.Rect]::new(0, 0, $width, $height)) }
    finally { $drawing.Close() }
    $bitmap.Render($background)
    $bitmap.Render($content)
    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $fullPath = [IO.Path]::GetFullPath($Path)
    $directory = [IO.Path]::GetDirectoryName($fullPath)
    [void][IO.Directory]::CreateDirectory($directory)
    $stream = [IO.File]::Create($fullPath)
    try { $encoder.Save($stream) }
    finally { $stream.Dispose() }
}
