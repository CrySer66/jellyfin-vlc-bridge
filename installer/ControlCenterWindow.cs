using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

internal sealed class ControlCenterWindow : IDisposable
{
    public Window Window { get; private set; }
    public bool AllowExit { get; set; }
    private readonly bool preview;
    private readonly DesktopBridge bridge = new DesktopBridge();
    private readonly Dictionary<string, object> translations;
    private Dictionary<string, object> health;
    private Forms.NotifyIcon tray;
    private Forms.ContextMenuStrip trayMenu;
    private bool busy, binding, dirty, updateAvailable, disposed;
    private string language, preference, currentPage = "Overview", settingsServer = "";
    private readonly string version = Assembly.GetExecutingAssembly().GetName().Version.ToString(3);
    private static readonly Brush Green = Brush("#16856D"), Orange = Brush("#A65F13"), Red = Brush("#BC3D53");
    private static readonly string[] ActionNames = {
        "RefreshButton", "SaveButton", "ChangeServerButton", "RepairButton", "SupportButton",
        "UpdateButton", "CopyButton", "OpenJellyfinButton", "ExtensionButton", "HelpButton"
    };

    public ControlCenterWindow(bool preview, string languageOverride)
    {
        this.preview = preview;
        translations = DesktopBridge.Parse(ReadResource("ControlCenter.strings.json"));
        preference = "auto";
        if (!preview)
        {
            try { preference = DesktopBridge.Text(DesktopBridge.Parse(File.ReadAllText(System.IO.Path.Combine(DesktopBridge.DataPath, "ui-language.json"))), "language"); }
            catch (IOException) { }
            catch (ArgumentException) { }
            catch (InvalidOperationException) { }
        }
        if (languageOverride == "en" || languageOverride == "fr") preference = languageOverride;
        Window = (Window)XamlReader.Parse(ReadResource("ControlCenter.xaml"));
        try
        {
            using (var icon = Assembly.GetExecutingAssembly().GetManifestResourceStream("ControlCenter.ico"))
                Window.Icon = BitmapFrame.Create(icon, BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
        }
        catch (Exception) { }
        ApplyLanguage();
        // Read local fields before the first network check so edits made while a
        // slow server is being checked are never replaced by late initialization.
        if (!preview) { try { LoadSettings(); } catch (Exception exception) { Error(exception); } }
        BindEvents();
        if (preview) { ApplyHealth(PreviewHealth()); LoadPreviewSettings(); }
        Navigate("Overview");
    }

    private static string ReadResource(string name)
    {
        using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(name))
        {
            if (stream == null) throw new FileNotFoundException("Missing desktop resource: " + name);
            using (var reader = new StreamReader(stream)) return reader.ReadToEnd();
        }
    }

    private TControl Get<TControl>(string name) where TControl : class
    {
        var value = Window.FindName(name) as TControl;
        if (value == null) throw new InvalidDataException("Missing desktop control: " + name);
        return value;
    }
    private static Brush Brush(string color) { var brush = (SolidColorBrush)new BrushConverter().ConvertFromString(color); brush.Freeze(); return brush; }
    private void Text(string name, string value) { Get<TextBlock>(name).Text = value; }
    private string T(string key, params object[] args)
    {
        var dictionary = (Dictionary<string, object>)translations[language ?? "en"];
        object value;
        if (!dictionary.TryGetValue(key, out value)) ((Dictionary<string, object>)translations["en"]).TryGetValue(key, out value);
        var text = value == null ? key : Convert.ToString(value);
        return args.Length == 0 ? text : string.Format(CultureInfo.CurrentCulture, text, args);
    }

    private void ApplyLanguage()
    {
        language = preference == "fr" || preference == "en" ? preference :
            (CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "fr" ? "fr" : "en");
        foreach (var entry in (Dictionary<string, object>)translations["en"]) Window.Resources[entry.Key] = entry.Value;
        foreach (var entry in (Dictionary<string, object>)translations[language]) Window.Resources[entry.Key] = entry.Value;
        binding = true;
        Get<ComboBox>("LanguageBox").SelectedIndex = preference == "fr" ? 1 : preference == "en" ? 2 : 0;
        binding = false;
        Text("VersionLabel", T("Version", version));
        Window.Title = T("ControlCenterTitle") + (preview ? " — " + T("DesktopPreview") : "");
        Navigate(currentPage);
        if (health != null) ApplyHealth(health);
        UpdateMode();
        Text("UpdateStatus", preview ? T("DesktopPreview") : T("UpdatesWaiting"));
        Get<Button>("UpdateButton").Content = T("CheckNow");
        updateAvailable = false;
        if (trayMenu != null)
        {
            trayMenu.Items[0].Text = T("TrayOpen");
            trayMenu.Items[1].Text = T("TrayRefresh");
            trayMenu.Items[3].Text = T("TrayExit");
        }
    }

    private void BindEvents()
    {
        Click("OverviewNav", delegate { Navigate("Overview"); });
        Click("SettingsNav", delegate { Navigate("Settings"); });
        Click("DiagnosticsNav", delegate { Navigate("Diagnostics"); });
        Click("GoSettingsButton", delegate { Navigate("Settings"); });
        AsyncClick("RefreshButton", Refresh);
        AsyncClick("OpenJellyfinButton", delegate {
            if (preview) return PreviewAction();
            string address = DesktopBridge.Text(health, "serverUrl");
            Uri uri;
            if (!Uri.TryCreate(address, UriKind.Absolute, out uri) || (uri.Scheme != "http" && uri.Scheme != "https") ||
                !string.IsNullOrEmpty(uri.UserInfo)) throw new InvalidOperationException(T("InvalidJellyfinAddress"));
            Open(uri.AbsoluteUri.TrimEnd('/') + "/web/");
            return Task.FromResult(0);
        });
        AsyncClick("RepairButton", async delegate {
            if (preview) { await PreviewAction(); return; }
            await bridge.Run(new[] { "repair" }, 45);
            await Refresh();
            Text("Footer", T("RepairDone"));
        });
        AsyncClick("ExtensionButton", delegate { return Command("open-extension"); });
        AsyncClick("HelpButton", delegate { return Command("open-help"); });
        Click("LogsButton", delegate {
            if (preview) { Text("Footer", T("DesktopPreviewNotice")); return; }
            try { string directory = System.IO.Path.Combine(DesktopBridge.DataPath, "Logs"); Directory.CreateDirectory(directory); Open(directory); }
            catch (Exception exception) { Error(exception); }
        });
        Click("BrowseButton", delegate {
            var dialog = new Microsoft.Win32.OpenFileDialog { Filter = "VLC (vlc.exe)|vlc.exe|Programmes (*.exe)|*.exe", CheckFileExists = true };
            if (dialog.ShowDialog(Window) == true) Get<TextBox>("VlcBox").Text = dialog.FileName;
        });
        AsyncClick("SaveButton", Save);
        AsyncClick("ChangeServerButton", ChangeServer);
        AsyncClick("CopyButton", async delegate {
            if (health == null) await Refresh();
            if (health == null) return;
            // Deliberately omit server URLs, paths, user IDs and raw finding messages.
            var keys = new[] { "version", "configured", "jellyfinConnected", "vlcReady", "vlcVersion",
                "protocolReady", "nativeMessagingReady", "extensionActive", "extensionVersion", "playbackMode", "ready" };
            string diagnostic = string.Join(Environment.NewLine, keys.Select(key => key + "=" + DesktopBridge.Text(health, key)));
            foreach (var finding in Findings()) diagnostic += Environment.NewLine + "Finding=" + DesktopBridge.Text(finding, "code");
            Clipboard.SetText(diagnostic);
            Text("Footer", T("DiagnosticCopied"));
        });
        AsyncClick("SupportButton", async delegate {
            if (preview) { await PreviewAction(); return; }
            var dialog = new Microsoft.Win32.SaveFileDialog {
                Title = T("SupportBundleDialogTitle"), Filter = T("SupportBundleFilter"),
                FileName = "JellyfinVlcBridge-Support-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".zip", OverwritePrompt = true
            };
            if (dialog.ShowDialog(Window) != true) return;
            var result = await bridge.RunJson(new[] { "support-bundle", "--output", dialog.FileName, "--json" }, 60);
            Text("Footer", T("SupportBundleCreated", DesktopBridge.Text(result, "path")));
        });
        AsyncClick("UpdateButton", Update);
        Get<ComboBox>("ModeBox").SelectionChanged += delegate { UpdateMode(); if (!binding) MarkDirty(); };
        foreach (string name in new[] { "VlcBox", "ServerPathBox", "ClientPathBox" })
            Get<TextBox>(name).TextChanged += delegate { if (!binding) MarkDirty(); };
        Get<ComboBox>("LanguageBox").SelectionChanged += delegate {
            if (binding) return;
            try
            {
                int selected = Get<ComboBox>("LanguageBox").SelectedIndex;
                preference = selected == 1 ? "fr" : selected == 2 ? "en" : "auto";
                if (!preview) DesktopBridge.WriteJson(System.IO.Path.Combine(DesktopBridge.DataPath, "ui-language.json"),
                    new Dictionary<string, object> { { "language", preference } });
                ApplyLanguage();
            }
            catch (Exception exception) { Error(exception); }
        };
        Window.Closing += delegate(object sender, System.ComponentModel.CancelEventArgs args) {
            if (!AllowExit && !preview && tray != null) { args.Cancel = true; Window.Hide(); return; }
            Application.Current.Shutdown();
        };
    }

    private void Click(string name, Action action) { Get<Button>(name).Click += delegate { action(); }; }
    private void AsyncClick(string name, Func<Task> action) { Get<Button>(name).Click += async delegate { await Guard(action); }; }
    private async Task Guard(Func<Task> action)
    {
        if (busy || disposed) return;
        busy = true;
        SetBusy(true);
        try { await action(); }
        catch (OperationCanceledException) { if (!disposed) Text("Footer", T("Cancel")); }
        catch (Exception exception) { if (!disposed) Error(exception); }
        finally { busy = false; if (!disposed) SetBusy(false); }
    }
    private void SetBusy(bool value)
    {
        foreach (string name in ActionNames) Get<Button>(name).IsEnabled = !value;
        Get<ComboBox>("LanguageBox").IsEnabled = !value;
        Get<ProgressBar>("BusyBar").Visibility = value ? Visibility.Visible : Visibility.Collapsed;
    }
    private void Error(Exception exception) { Text("Footer", exception.Message); Get<TextBlock>("Footer").Foreground = Red; }
    private Task PreviewAction() { Text("Footer", T("DesktopPreviewNotice")); return Task.FromResult(0); }
    private Task Command(string name) { return preview ? PreviewAction() : bridge.Run(new[] { name }, 30); }
    private static void Open(string path) { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(path) { UseShellExecute = true }); }

    private void Navigate(string page)
    {
        currentPage = page;
        foreach (string candidate in new[] { "Overview", "Settings", "Diagnostics" })
        {
            Get<FrameworkElement>(candidate + "Page").Visibility = candidate == page ? Visibility.Visible : Visibility.Collapsed;
            Get<Button>(candidate + "Nav").Tag = candidate == page ? "selected" : null;
        }
        Text("PageTitle", T("Desktop" + page));
        Text("PageSubtitle", T("Desktop" + page + "Subtitle"));
    }
    private void UpdateMode()
    {
        bool smb = Get<ComboBox>("ModeBox").SelectedIndex == 1;
        Get<FrameworkElement>("MappingPanel").Visibility = smb ? Visibility.Visible : Visibility.Collapsed;
        Text("ModeDescription", T(smb ? "SmbModeDescription" : "HttpModeDescription"));
    }
    private void MarkDirty() { dirty = true; Text("Footer", T("DesktopUnsaved")); }

    private async Task Refresh()
    {
        if (preview) { ApplyHealth(PreviewHealth()); return; }
        Text("Footer", T("CheckInProgress"));
        Get<TextBlock>("Footer").Foreground = Brush("#667085");
        try
        {
            ApplyHealth(await bridge.RunJson(new[] { "status", "--json" }, 45));
            if (!dirty) LoadSettings();
            Text("Footer", T("LastCheck", DateTime.Now.ToString("HH:mm:ss")) + (dirty ? " · " + T("DesktopUnsaved") : ""));
        }
        catch
        {
            Text("Summary", T("CheckFailed"));
            Text("SummaryDetail", T("DesktopCheckHint"));
            Get<System.Windows.Shapes.Ellipse>("SummaryDot").Fill = Red;
            throw;
        }
    }
    private void ApplyHealth(Dictionary<string, object> result)
    {
        health = result;
        bool ready = DesktopBridge.Flag(health, "ready");
        Text("Summary", T(ready ? "AllReady" : "CheckNeeded"));
        Text("SummaryDetail", T(ready ? "DesktopReadyHint" : "DesktopCheckHint"));
        Get<System.Windows.Shapes.Ellipse>("SummaryDot").Fill = ready ? Brush("#66E3BD") : Brush("#F1C16D");
        SetCard("Jellyfin", DesktopBridge.Flag(health, "jellyfinConnected"), T("Connected"), T("Check"),
            FindingDetail("jellyfin", DesktopBridge.Text(health, "jellyfinMessage")));
        SetCard("Vlc", DesktopBridge.Flag(health, "vlcReady"), T("VlcDetected"), T("VlcMissing"),
            FindingDetail("vlc", DesktopBridge.Text(health, "vlcVersion")));
        bool registered = DesktopBridge.Flag(health, "protocolReady") && DesktopBridge.Flag(health, "nativeMessagingReady");
        bool active = DesktopBridge.Flag(health, "extensionActive");
        SetCard("Browser", registered && active, T("ExtensionActive"), T(registered ? "ExtensionUnconfirmed" : "RepairRequired"),
            registered && active ? T("ExtensionContact", DesktopBridge.Text(health, "extensionVersion")) :
            FindingDetail("browser", T(registered ? "ExtensionOpenHint" : "BrowserConnectionMissing")));
        string server = DesktopBridge.Text(health, "serverUrl");
        Text("ServerValue", string.IsNullOrWhiteSpace(server) ? T("NotConfigured") : server);
        Get<TextBlock>("ServerValue").ToolTip = server;
    }
    private void SetCard(string prefix, bool ready, string good, string bad, string detail)
    {
        Text(prefix + "State", ready ? good : bad);
        Text(prefix + "Detail", detail);
        Get<TextBlock>(prefix + "State").Foreground = ready ? Green : Orange;
        Get<System.Windows.Shapes.Ellipse>(prefix + "Dot").Fill = ready ? Green : Orange;
    }
    private IEnumerable<Dictionary<string, object>> Findings()
    {
        object value;
        var entries = health != null && health.TryGetValue("findings", out value) ? value as System.Collections.IEnumerable : null;
        return entries == null ? Enumerable.Empty<Dictionary<string, object>>() : entries.OfType<Dictionary<string, object>>();
    }
    private string FindingDetail(string component, string fallback)
    {
        var finding = Findings().FirstOrDefault(value => DesktopBridge.Text(value, "component") == component);
        if (finding == null && component == "jellyfin")
            finding = Findings().FirstOrDefault(value => DesktopBridge.Text(value, "component") == "configuration");
        if (finding == null) return fallback;
        string code = DesktopBridge.Text(finding, "code");
        var keys = new Dictionary<string, string> {
            { "configuration.invalid", "FindingConfigurationInvalid" }, { "jellyfin.connection-missing", "FindingConnectionMissing" },
            { "jellyfin.timeout", "FindingJellyfinTimeout" }, { "jellyfin.connection-refused", "FindingJellyfinRefused" },
            { "jellyfin.unreachable", "FindingJellyfinUnreachable" }, { "jellyfin.ready", "FindingJellyfinReady" },
            { "vlc.not-found", "FindingVlcMissing" }, { "vlc.configured-path-missing", "FindingVlcMissing" }, { "vlc.ready", "FindingVlcReady" },
            { "browser.integration-missing", "FindingBrowserMissing" }, { "browser.extension-inactive", "FindingExtensionInactive" },
            { "browser.ready", "FindingBrowserReady" }
        };
        string key;
        return keys.TryGetValue(code, out key) ? T(key) : DesktopBridge.Text(finding, "message");
    }

    private void LoadSettings()
    {
        string path = System.IO.Path.Combine(DesktopBridge.DataPath, "config.json");
        binding = true;
        try
        {
            var config = File.Exists(path) ? DesktopBridge.Parse(File.ReadAllText(path)) : new Dictionary<string, object>();
            settingsServer = DesktopBridge.Text(config, "serverUrl");
            Get<ComboBox>("ModeBox").SelectedIndex = DesktopBridge.Text(config, "playbackMode") == "smb" ? 1 : 0;
            // Leave automatic detection empty; do not turn a detected path into an override.
            Get<TextBox>("VlcBox").Text = DesktopBridge.Text(config, "vlcPath");
            var mappingEntry = config.FirstOrDefault(entry => entry.Key.Equals("pathMappings", StringComparison.OrdinalIgnoreCase));
            var mappings = mappingEntry.Value as System.Collections.IEnumerable;
            var first = mappings == null ? null : mappings.Cast<object>().FirstOrDefault() as Dictionary<string, object>;
            Get<TextBox>("ServerPathBox").Text = DesktopBridge.Text(first, "serverPrefix");
            Get<TextBox>("ClientPathBox").Text = DesktopBridge.Text(first, "clientPrefix");
            dirty = false;
        }
        finally { binding = false; UpdateMode(); }
    }
    private async Task Save()
    {
        if (preview) { await PreviewAction(); return; }
        string path = System.IO.Path.Combine(DesktopBridge.DataPath, "config.json");
        if (!File.Exists(path)) throw new InvalidOperationException(T("MissingConfig"));
        string mode = Get<ComboBox>("ModeBox").SelectedIndex == 1 ? "smb" : "http";
        string serverPrefix = Get<TextBox>("ServerPathBox").Text.Trim(), clientPrefix = Get<TextBox>("ClientPathBox").Text.Trim();
        if (mode == "smb" && (serverPrefix.Length == 0 || clientPrefix.Length == 0))
            throw new InvalidOperationException(T("SmbRequiresMapping"));
        string vlc = Get<TextBox>("VlcBox").Text.Trim();
        if (vlc.Length > 0 && !File.Exists(vlc)) throw new InvalidOperationException(T("VlcMissing"));
        DesktopBridge.SavePlaybackSettings(path, settingsServer, mode, vlc, serverPrefix, clientPrefix);
        dirty = false;
        await Refresh();
        Text("Footer", T("SettingsSaved"));
    }

    private async Task CheckUpdate()
    {
        if (preview) return;
        Text("UpdateStatus", T("UpdateChecking"));
        try
        {
            var result = await bridge.RunJson(new[] { "check-update", "--json" }, 35);
            updateAvailable = DesktopBridge.Flag(result, "updateAvailable");
            Text("UpdateStatus", updateAvailable ? T("NewVersion", DesktopBridge.Text(result, "latestVersion")) : T("UpToDate"));
            Get<Button>("UpdateButton").Content = updateAvailable ? T("InstallVersion", DesktopBridge.Text(result, "latestVersion")) : T("CheckNow");
        }
        catch (Exception exception) { Text("UpdateStatus", T("CheckImpossible")); throw new InvalidOperationException(exception.Message, exception); }
    }
    private async Task Update()
    {
        if (preview) { await PreviewAction(); return; }
        if (!updateAvailable) { await CheckUpdate(); return; }
        Text("UpdateStatus", T("Downloading"));
        var result = await bridge.RunJson(new[] { "download-update", "--json" }, 300);
        string root = System.IO.Path.GetFullPath(System.IO.Path.Combine(DesktopBridge.DataPath, "Updates")).TrimEnd('\\') + "\\";
        string installer = System.IO.Path.GetFullPath(DesktopBridge.Text(result, "path"));
        if (!installer.StartsWith(root, StringComparison.OrdinalIgnoreCase) || !File.Exists(installer) ||
            !System.IO.Path.GetExtension(installer).Equals(".exe", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException(T("UpdateFileUnsafe"));
        Open(installer);
        AllowExit = true;
        Window.Close();
    }

    private Task ChangeServer()
    {
        if (preview) return PreviewAction();
        ShowChangeServer();
        return Task.FromResult(0);
    }
    private void ShowChangeServer()
    {
        var dialog = new Window {
            Owner = Window, Title = T("ChangeServer"), Width = 610, Height = 520, MinWidth = 500, MinHeight = 450,
            WindowStartupLocation = WindowStartupLocation.CenterOwner, Background = Brush("#F5F7FB"), FontFamily = Window.FontFamily,
            FontSize = 14, ShowInTaskbar = false, UseLayoutRounding = true, Resources = Window.Resources
        };
        var stack = new StackPanel { Margin = new Thickness(30) };
        dialog.Content = new ScrollViewer { Content = stack, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        stack.Children.Add(new TextBlock { Text = T("ChangeServer"), FontSize = 24, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
        stack.Children.Add(new TextBlock { Text = T("ChangeServerControlDescription"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 24), Foreground = Brush("#667085") });
        stack.Children.Add(new TextBlock { Text = T("NewServerAddress"), Margin = new Thickness(0, 0, 0, 8) });
        var address = new TextBox { Text = DesktopBridge.Text(health, "serverUrl"), MinHeight = 42 };
        stack.Children.Add(address);
        var code = new TextBlock { Text = "", FontSize = 36, FontWeight = FontWeights.SemiBold, Foreground = Green, Margin = new Thickness(0, 22, 0, 12), TextAlignment = TextAlignment.Center };
        stack.Children.Add(code);
        var status = new TextBlock { Text = T("ChangeServerReady"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 20) };
        stack.Children.Add(status);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var cancel = new Button { Content = T("Cancel"), MinWidth = 100, Margin = new Thickness(0, 0, 12, 0), IsCancel = true };
        var connect = new Button { Content = T("RequestQuickConnect"), MinWidth = 160, IsDefault = true };
        buttons.Children.Add(cancel); buttons.Children.Add(connect); stack.Children.Add(buttons);
        var cancellation = new CancellationTokenSource();
        string codePath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "jellyfin-vlc-" + Guid.NewGuid().ToString("N") + ".txt");
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(350) };
        bool completed = false, running = false;
        timer.Tick += delegate {
            try
            {
                if (File.Exists(codePath))
                {
                    string value = File.ReadAllText(codePath).Trim();
                    if (value.Length > 0) { code.Text = value; status.Text = T("QuickConnectInstructions"); }
                }
            }
            catch (IOException) { }
        };
        cancel.Click += delegate { dialog.Close(); };
        connect.Click += async delegate {
            if (completed) { dialog.Close(); return; }
            try
            {
                Uri uri;
                if (!Uri.TryCreate(address.Text.Trim(), UriKind.Absolute, out uri) || (uri.Scheme != "http" && uri.Scheme != "https") ||
                    !string.IsNullOrEmpty(uri.UserInfo) || !string.IsNullOrEmpty(uri.Query) || !string.IsNullOrEmpty(uri.Fragment))
                    throw new InvalidOperationException(T("InvalidJellyfinAddress"));
                address.IsEnabled = false; connect.IsEnabled = false; running = true;
                code.Text = "";
                if (File.Exists(codePath)) File.Delete(codePath);
                status.Text = T("RequestingCode"); status.Foreground = Brush("#667085");
                timer.Start();
                await bridge.Run(new[] { "setup", "--server", uri.AbsoluteUri.TrimEnd('/'), "--code-path", codePath }, 215, cancellation.Token);
                completed = true;
                code.Text = ""; status.Text = T("ServerChanged"); status.Foreground = Green;
                connect.Content = T("Close"); cancel.Visibility = Visibility.Collapsed;
            }
            catch (OperationCanceledException) { }
            catch (Exception exception)
            {
                if (dialog.IsVisible) { status.Text = exception.Message; status.Foreground = Red; address.IsEnabled = true; }
            }
            finally
            {
                running = false; timer.Stop(); connect.IsEnabled = true;
                if (File.Exists(codePath)) { try { File.Delete(codePath); } catch (IOException) { } }
                if (!dialog.IsVisible) cancellation.Dispose();
            }
        };
        dialog.Closed += delegate { timer.Stop(); cancellation.Cancel(); if (!running) cancellation.Dispose(); };
        dialog.ShowDialog();
        if (completed)
        {
            dirty = false;
            Window.Dispatcher.BeginInvoke(new Action(async delegate { await Guard(Refresh); }));
        }
    }

    public void Start(bool startInTray)
    {
        if (!preview)
        {
            trayMenu = new Forms.ContextMenuStrip();
            trayMenu.Items.Add(T("TrayOpen"), null, delegate { Show(); });
            trayMenu.Items.Add(T("TrayRefresh"), null, async delegate { Show(); await Guard(Refresh); });
            trayMenu.Items.Add(new Forms.ToolStripSeparator());
            trayMenu.Items.Add(T("TrayExit"), null, delegate { AllowExit = true; Window.Close(); });
            tray = new Forms.NotifyIcon {
                Text = "Jellyfin VLC Bridge",
                Icon = System.Drawing.Icon.ExtractAssociatedIcon(Assembly.GetExecutingAssembly().Location),
                ContextMenuStrip = trayMenu, Visible = true
            };
            tray.DoubleClick += delegate { Show(); };
        }
        if (!startInTray || preview) Show();
        if (!preview) Window.Dispatcher.BeginInvoke(new Action(async delegate {
            await Guard(Refresh);
            await Guard(CheckUpdate);
        }));
    }
    public void Show()
    {
        Window.Show();
        if (Window.WindowState == WindowState.Minimized) Window.WindowState = WindowState.Normal;
        // Screen.WorkingArea uses physical pixels. Move in those same units first,
        // then let WPF process the DPI change before sizing on the target monitor.
        var area = Forms.Screen.FromPoint(Forms.Cursor.Position).WorkingArea;
        if (Window.WindowState != WindowState.Maximized)
        {
            IntPtr handle = new WindowInteropHelper(Window).Handle;
            NativeRect bounds;
            if (GetWindowRect(handle, out bounds))
                SetWindowPos(handle, IntPtr.Zero, area.Left + Math.Max(0, (area.Width - bounds.Width) / 2),
                    area.Top + Math.Max(0, (area.Height - bounds.Height) / 2), 0, 0, 0x0015);
            Window.Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(delegate {
                if (disposed || !Window.IsVisible || Window.WindowState != WindowState.Normal) return;
                NativeRect current;
                if (!GetWindowRect(handle, out current)) return;
                int width = Math.Min(current.Width, area.Width), height = Math.Min(current.Height, area.Height);
                SetWindowPos(handle, IntPtr.Zero, area.Left + (area.Width - width) / 2,
                    area.Top + (area.Height - height) / 2, width, height, 0x0014);
            }));
        }
        Window.Activate();
    }

    private Dictionary<string, object> PreviewHealth()
    {
        return new Dictionary<string, object> {
            { "version", version }, { "ready", true }, { "configured", true }, { "jellyfinConnected", true },
            { "jellyfinMessage", T("FindingJellyfinReady") }, { "vlcReady", true }, { "vlcVersion", "3.0.23" },
            { "protocolReady", true }, { "nativeMessagingReady", true }, { "extensionActive", true },
            { "extensionVersion", "1.8.1" }, { "serverUrl", "http://jellyfin.local:8096" }, { "playbackMode", "http" }
        };
    }
    private void LoadPreviewSettings()
    {
        binding = true;
        Get<ComboBox>("ModeBox").SelectedIndex = 0;
        Get<TextBox>("VlcBox").Text = "";
        Get<TextBox>("ServerPathBox").Text = "/media/films";
        Get<TextBox>("ClientPathBox").Text = @"\\NAS\Films";
        binding = false;
        dirty = false;
        Text("Footer", T("DesktopPreviewNotice"));
    }

    public void Validate()
    {
        foreach (System.Text.RegularExpressions.Match resource in System.Text.RegularExpressions.Regex.Matches(
            ReadResource("ControlCenter.xaml"), @"\{DynamicResource ([^}]+)\}"))
            if (Window.TryFindResource(resource.Groups[1].Value) == null)
                throw new InvalidDataException("Missing resource: " + resource.Groups[1].Value);
        foreach (string name in ActionNames) Get<Button>(name);
        foreach (string page in new[] { "Overview", "Settings", "Diagnostics" }) { Navigate(page); Window.Measure(new Size(1100, 780)); Window.Arrange(new Rect(0, 0, 1100, 780)); Window.UpdateLayout(); }
        foreach (string choice in new[] { "en", "fr" }) { preference = choice; ApplyLanguage(); }
        if (Get<ComboBox>("LanguageBox").Items.Count != 3 || Get<ComboBox>("ModeBox").Items.Count != 2)
            throw new InvalidDataException("Invalid desktop settings choices.");
        if (Window.MinHeight > 650 || Window.MinWidth > 850) throw new InvalidDataException("Desktop minimum size is too large.");
    }
    public void RenderPreview(string path, string page, string scaleText)
    {
        Navigate(page == "settings" ? "Settings" : page == "diagnostics" ? "Diagnostics" : "Overview");
        if (page == "settings") { binding = true; Get<ComboBox>("ModeBox").SelectedIndex = 1; binding = false; }
        double scale;
        if (!double.TryParse(scaleText, NumberStyles.Float, CultureInfo.InvariantCulture, out scale) || scale < 1 || scale > 3) scale = 1;
        var content = (FrameworkElement)Window.Content;
        var panel = content as Panel;
        if (panel != null && panel.Background == null) panel.Background = Window.Background;
        content.Measure(new Size(1100, 740)); content.Arrange(new Rect(0, 0, 1100, 740)); content.UpdateLayout();
        var image = new RenderTargetBitmap((int)(1100 * scale), (int)(740 * scale), 96 * scale, 96 * scale, PixelFormats.Pbgra32);
        image.Render(content);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(image));
        using (var stream = File.Create(System.IO.Path.GetFullPath(path))) encoder.Save(stream);
    }
    public void Dispose()
    {
        disposed = true;
        bridge.Dispose();
        if (tray != null) { tray.Visible = false; var icon = tray.Icon; tray.Dispose(); if (icon != null) icon.Dispose(); }
        if (trayMenu != null) trayMenu.Dispose();
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left, Top, Right, Bottom;
        public int Width { get { return Right - Left; } }
        public int Height { get { return Bottom - Top; } }
    }
    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr window, out NativeRect bounds);
    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(IntPtr window, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
}
