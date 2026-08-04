param(
    [switch]$ValidateOnly,
    [switch]$StartInTray,
    [string]$ShowEventName = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:installDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $script:installDirectory 'Localization.ps1')
. (Join-Path $script:installDirectory 'UiTheme.ps1')
$script:bridgeVersion = '1.18.0'
$script:executable = Join-Path $script:installDirectory 'jellyfin-vlc-bridge.exe'
$script:configFile = Join-Path $env:LOCALAPPDATA 'JellyfinVlcBridge\config.json'
$script:health = $null
$script:updateProcess = $null
$script:updateOperation = 'idle'
$script:updateAvailable = $false
$script:latestVersion = $null
$script:blue = $script:JvbPalette.Accent
$script:green = $script:JvbPalette.Success
$script:orange = $script:JvbPalette.Warning
$script:red = $script:JvbPalette.Danger
$script:muted = $script:JvbPalette.TextMuted
$script:allowExit = $false
$script:trayIcon = $null
$script:showEvent = $null
$script:showEventTimer = $null

function Center-ControlCenterOnActiveScreen {
    # Après Hide() depuis l'état minimisé, Win32 peut conserver la position
    # native spéciale -32000,-32000 alors que Form.Bounds semble encore valide.
    # Un placement explicite est donc nécessaire à chaque restauration.
    $workingArea = [Windows.Forms.Screen]::FromPoint(
        [Windows.Forms.Cursor]::Position).WorkingArea
    $left = $workingArea.Left + [Math]::Max(
        0,
        [int](($workingArea.Width - $form.Width) / 2))
    $top = $workingArea.Top + [Math]::Max(
        0,
        [int](($workingArea.Height - $form.Height) / 2))
    $form.StartPosition = [Windows.Forms.FormStartPosition]::Manual
    $form.SetDesktopLocation($left, $top)
}

function Show-ControlCenter {
    $form.Opacity = 1
    $form.ShowInTaskbar = $true
    $form.Show()
    $form.WindowState = [Windows.Forms.FormWindowState]::Normal
    Center-ControlCenterOnActiveScreen
    $form.Activate()
    $form.BringToFront()
}

function Hide-ControlCenter {
    $form.ShowInTaskbar = $false
    $form.Hide()
}

function Show-BridgeError([string]$message) {
    Show-JvbMessageDialog 'Jellyfin VLC Bridge' $message 'Error' $applicationIcon (T 'Close')
}

function New-StatusCard([int]$left, [string]$title) {
    $panel = New-JvbCard $form $left 216 306 140
    $dot = New-JvbDot $panel 20 22 $script:JvbPalette.TextFaint
    $name = New-JvbLabel $panel $title 42 15 240 26 11 `
        ([Drawing.FontStyle]::Bold)
    $state = New-JvbLabel $panel (T 'Checking') 20 52 265 25 10 `
        ([Drawing.FontStyle]::Bold) $script:JvbPalette.TextMuted
    $detail = New-JvbLabel $panel '' 20 82 265 46 9 `
        ([Drawing.FontStyle]::Regular) $script:muted
    return @{ Panel = $panel; Dot = $dot; State = $state; Detail = $detail }
}

function Set-Card($card, [bool]$ready, [string]$readyText, [string]$errorText, [string]$detail) {
    $card.State.Text = if ($ready) { $readyText } else { $errorText }
    $card.State.ForeColor = if ($ready) { $script:green } else { $script:orange }
    $card.Dot.BackColor = if ($ready) { $script:green } else { $script:orange }
    $card.Detail.Text = $detail
}

function Get-HealthFinding([string]$component) {
    if (-not $script:health -or -not $script:health.findings) { return $null }
    return @($script:health.findings) |
        Where-Object { $_.component -eq $component } |
        Select-Object -First 1
}

function Get-FindingDetail($finding, [string]$fallback) {
    if (-not $finding) { return $fallback }
    $translationKey = switch ([string]$finding.code) {
        'configuration.invalid' { 'FindingConfigurationInvalid' }
        'jellyfin.connection-missing' { 'FindingConnectionMissing' }
        'jellyfin.timeout' { 'FindingJellyfinTimeout' }
        'jellyfin.connection-refused' { 'FindingJellyfinRefused' }
        'jellyfin.unreachable' { 'FindingJellyfinUnreachable' }
        'jellyfin.ready' { 'FindingJellyfinReady' }
        'vlc.not-found' { 'FindingVlcMissing' }
        'vlc.configured-path-missing' { 'FindingVlcMissing' }
        'vlc.ready' { 'FindingVlcReady' }
        'browser.integration-missing' { 'FindingBrowserMissing' }
        'browser.extension-inactive' { 'FindingExtensionInactive' }
        'browser.ready' { 'FindingBrowserReady' }
        default { $null }
    }
    if ($translationKey) { return T $translationKey }
    return ($finding.message + ' ' + $finding.action).Trim()
}

function Update-MappingControls {
    $enabled = $modeBox.SelectedIndex -eq 1
    $mappingPanel.Visible = $enabled
    $modeDescription.Text = if ($enabled) {
        T 'SmbModeDescription'
    } else {
        T 'HttpModeDescription'
    }
}

function Invoke-Bridge([string[]]$arguments) {
    if (-not (Test-Path $script:executable)) { throw (T 'MainProgramMissing') }
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $script:executable
    $processInfo.Arguments = ($arguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }) -join ' '
    $processInfo.WorkingDirectory = $script:installDirectory
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::Start($processInfo)
    if (-not $process) { throw (T 'ProgramStartFailed') }
    try {
        $output = $process.StandardOutput.ReadToEnd()
        $errorOutput = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            $message = if ($errorOutput) { $errorOutput.Trim() } elseif ($output) { $output.Trim() } else { T 'UnknownError' }
            throw $message
        }
        if (($arguments -contains '--json') -and [string]::IsNullOrWhiteSpace($output)) {
            throw (T 'NoResult')
        }
        return $output.TrimEnd()
    } finally {
        $process.Dispose()
    }
}

function Show-ChangeServerDialog {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = T 'ChangeServer'
    $dialog.StartPosition = 'CenterParent'
    $dialog.ClientSize = New-Object Drawing.Size(620, 450)
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    Enable-JvbModernWindow $dialog $applicationIcon

    $title = New-JvbLabel $dialog (T 'ChangeServer') 28 22 560 34 18 `
        ([Drawing.FontStyle]::Bold)
    $description = New-JvbLabel $dialog (T 'ChangeServerControlDescription') 28 62 560 48 9.5 `
        ([Drawing.FontStyle]::Regular) $script:JvbPalette.TextMuted

    $addressLabel = New-JvbLabel $dialog (T 'NewServerAddress') 28 122 560 24 9 `
        ([Drawing.FontStyle]::Bold)
    $addressBox = New-Object Windows.Forms.TextBox
    $addressBox.Location = New-Object Drawing.Point(28, 150)
    $addressBox.Size = New-Object Drawing.Size(564, 32)
    $addressBox.Text = if ($script:health.serverUrl) {
        $script:health.serverUrl
    } else {
        'http://192.168.1.25:8096'
    }
    Set-JvbInputStyle $addressBox
    $dialog.Controls.Add($addressBox)

    $codeCard = New-JvbCard $dialog 28 202 564 104 $script:JvbPalette.SurfaceAlt 14
    $codeTitle = New-JvbLabel $codeCard (T 'QuickConnectCode') 18 10 528 24 9 `
        ([Drawing.FontStyle]::Bold) $script:JvbPalette.TextMuted
    $codeValue = New-JvbLabel $codeCard '------' 18 35 528 54 25 `
        ([Drawing.FontStyle]::Bold) $script:JvbPalette.Accent
    $codeValue.TextAlign = 'MiddleCenter'
    $codeCard.Visible = $false

    $status = New-JvbLabel $dialog (T 'ChangeServerReady') 28 320 564 44 9.5 `
        ([Drawing.FontStyle]::Regular) $script:JvbPalette.TextMuted

    $cancelButton = New-Object Windows.Forms.Button
    $cancelButton.Text = T 'Cancel'
    $cancelButton.Location = New-Object Drawing.Point(324, 382)
    $cancelButton.Size = New-Object Drawing.Size(118, 40)
    Set-JvbButtonStyle $cancelButton 'Secondary' 12
    $dialog.Controls.Add($cancelButton)

    $connectButton = New-Object Windows.Forms.Button
    $connectButton.Text = T 'RequestQuickConnect'
    $connectButton.Location = New-Object Drawing.Point(452, 382)
    $connectButton.Size = New-Object Drawing.Size(140, 40)
    Set-JvbButtonStyle $connectButton 'Primary' 12
    $dialog.Controls.Add($connectButton)

    $codeFile = Join-Path $env:TEMP ('jellyfin-vlc-server-' + [Guid]::NewGuid().ToString('N') + '.txt')
    $setupState = @{
        Process = $null
        Completed = $false
    }
    $timer = New-Object Windows.Forms.Timer
    $timer.Interval = 400

    $cancelButton.Add_Click({ $dialog.Close() })
    $connectButton.Add_Click({
        if ($setupState.Completed) {
            $dialog.DialogResult = [Windows.Forms.DialogResult]::OK
            $dialog.Close()
            return
        }
        try {
            $uri = $null
            if (-not [Uri]::TryCreate($addressBox.Text.Trim(), [UriKind]::Absolute, [ref]$uri) -or
                $uri.Scheme -notin @('http', 'https') -or
                -not [string]::IsNullOrEmpty($uri.UserInfo) -or
                -not [string]::IsNullOrEmpty($uri.Query) -or
                -not [string]::IsNullOrEmpty($uri.Fragment)) {
                throw (T 'InvalidJellyfinAddress')
            }
            $addressBox.Enabled = $false
            $connectButton.Enabled = $false
            $status.Text = T 'RequestingCode'
            $status.ForeColor = $script:JvbPalette.TextMuted
            [Windows.Forms.Application]::DoEvents()

            $processInfo = New-Object Diagnostics.ProcessStartInfo
            $processInfo.FileName = $script:executable
            $processInfo.Arguments = 'setup --server "' + $addressBox.Text.Trim() +
                '" --code-path "' + $codeFile + '"'
            $processInfo.WorkingDirectory = $script:installDirectory
            $processInfo.UseShellExecute = $false
            $processInfo.CreateNoWindow = $true
            $processInfo.RedirectStandardOutput = $true
            $processInfo.RedirectStandardError = $true
            $setupState.Process = [Diagnostics.Process]::Start($processInfo)
            if (-not $setupState.Process) { throw (T 'ProgramStartFailed') }
            $timer.Start()
        } catch {
            $addressBox.Enabled = $true
            $connectButton.Enabled = $true
            $status.Text = $_.Exception.Message
            $status.ForeColor = $script:JvbPalette.Danger
        }
    }.GetNewClosure())

    $timer.Add_Tick({
        try {
            if (-not $codeCard.Visible -and (Test-Path -LiteralPath $codeFile)) {
                $codeValue.Text = (Get-Content -LiteralPath $codeFile -Raw).Trim()
                $codeCard.Visible = $true
                $status.Text = T 'QuickConnectInstructions'
                $status.ForeColor = $script:JvbPalette.Text
            }
            if (-not $setupState.Process -or -not $setupState.Process.HasExited) { return }
            $timer.Stop()
            $output = $setupState.Process.StandardOutput.ReadToEnd()
            $errorOutput = $setupState.Process.StandardError.ReadToEnd()
            if ($setupState.Process.ExitCode -ne 0) {
                $message = if ($errorOutput) { $errorOutput.Trim() } else { $output.Trim() }
                if ([string]::IsNullOrWhiteSpace($message)) { $message = T 'ServerChangeFailed' }
                throw $message
            }
            $setupState.Process.Dispose()
            $setupState.Process = $null
            $setupState.Completed = $true
            $codeCard.Visible = $false
            $status.Text = T 'ServerChanged'
            $status.ForeColor = $script:JvbPalette.Success
            $connectButton.Text = T 'Close'
            $connectButton.Enabled = $true
            $cancelButton.Visible = $false
        } catch {
            $timer.Stop()
            if ($setupState.Process) {
                try { $setupState.Process.Dispose() } catch { }
                $setupState.Process = $null
            }
            $addressBox.Enabled = $true
            $connectButton.Enabled = $true
            $status.Text = $_.Exception.Message
            $status.ForeColor = $script:JvbPalette.Danger
        }
    }.GetNewClosure())

    $dialog.Add_FormClosing({
        $timer.Stop()
        if ($setupState.Process -and -not $setupState.Process.HasExited) {
            try { $setupState.Process.Kill() } catch { }
        }
        if ($setupState.Process) {
            try { $setupState.Process.Dispose() } catch { }
        }
        if (Test-Path -LiteralPath $codeFile) {
            Remove-Item -LiteralPath $codeFile -Force -ErrorAction SilentlyContinue
        }
    }.GetNewClosure())

    [void]$dialog.ShowDialog($form)
    return $setupState.Completed
}

function Start-UpdateOperation([string]$operation) {
    if ($script:updateProcess -and -not $script:updateProcess.HasExited) { return }
    try {
        $script:updateOperation = $operation
        $updateButton.Enabled = $false
        $updateStatus.Text = if ($operation -eq 'download') { T 'Downloading' } else { T 'UpdateChecking' }
        $updateStatus.ForeColor = [System.Drawing.Color]::White
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $script:executable
        $processInfo.Arguments = if ($operation -eq 'download') { 'download-update --json' } else { 'check-update --json' }
        $processInfo.WorkingDirectory = $script:installDirectory
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $script:updateProcess = [System.Diagnostics.Process]::Start($processInfo)
        $updateTimer.Start()
    } catch {
        $updateStatus.Text = T 'CheckImpossible'
        $updateButton.Text = T 'Retry'
        $updateButton.Enabled = $true
        $script:updateOperation = 'idle'
    }
}

function Refresh-BridgeStatus {
    try {
        $refreshButton.Enabled = $false
        $footer.Text = T 'CheckInProgress'
        [System.Windows.Forms.Application]::DoEvents()
        $script:health = (Invoke-Bridge @('status', '--json')) | ConvertFrom-Json

        $jellyfinFinding = Get-HealthFinding 'jellyfin'
        if (-not $jellyfinFinding) { $jellyfinFinding = Get-HealthFinding 'configuration' }
        $jellyfinDetail = Get-FindingDetail $jellyfinFinding $script:health.jellyfinMessage
        Set-Card $jellyfinCard $script:health.jellyfinConnected `
            (T 'Connected') (T 'Check') $jellyfinDetail
        $vlcDetail = if ($script:health.vlcPath) {
            $versionText = if ($script:health.vlcVersion) { 'VLC ' + $script:health.vlcVersion } else { 'VLC' }
            $versionText + [Environment]::NewLine + $script:health.vlcPath
        } else { T 'NoPath' }
        $vlcDetail = Get-FindingDetail (Get-HealthFinding 'vlc') $vlcDetail
        Set-Card $vlcCard $script:health.vlcReady `
            (T 'VlcDetected') (T 'VlcMissing') $vlcDetail
        $browserRegistered = $script:health.protocolReady -and $script:health.nativeMessagingReady
        $browserReady = $browserRegistered -and $script:health.extensionActive
        $browserFinding = Get-HealthFinding 'browser'
        if (-not $browserRegistered) {
            $browserDetail = Get-FindingDetail $browserFinding (T 'BrowserConnectionMissing')
            $browserError = T 'RepairRequired'
        } elseif ($script:health.extensionActive) {
            $browserDetail = T 'ExtensionContact' @($script:health.extensionVersion)
            $browserError = T 'ExtensionUnconfirmed'
        } else {
            $browserDetail = Get-FindingDetail $browserFinding (T 'ExtensionOpenHint')
            $browserError = T 'ExtensionUnconfirmed'
        }
        Set-Card $browserCard $browserReady (T 'ExtensionActive') $browserError $browserDetail

        $serverValue.Text = if ($script:health.serverUrl) { $script:health.serverUrl } else { T 'NotConfigured' }
        $versionLabel.Text = T 'Version' @($script:health.version)
        $modeBox.SelectedItem = if ($script:health.playbackMode -eq 'smb') { T 'SmbMode' } else { 'HTTP Direct Play' }
        $vlcBox.Text = if ($script:health.vlcPath) { $script:health.vlcPath } else { '' }
        if (Test-Path $script:configFile) {
            $savedConfig = Get-Content -LiteralPath $script:configFile -Raw | ConvertFrom-Json
            $firstMapping = @($savedConfig.pathMappings)[0]
            $serverPathBox.Text = if ($firstMapping) { $firstMapping.serverPrefix } else { '' }
            $clientPathBox.Text = if ($firstMapping) { $firstMapping.clientPrefix } else { '' }
        }
        Update-MappingControls

        $allReady = [bool]$script:health.ready
        $summary.Text = if ($allReady) { T 'AllReady' } else { T 'CheckNeeded' }
        $summary.ForeColor = if ($allReady) { $script:green } else { $script:orange }
        $summaryDot.BackColor = if ($allReady) { $script:green } else { $script:orange }
        $footer.Text = T 'LastCheck' @((Get-Date -Format 'HH:mm:ss'))
    } catch {
        $summary.Text = T 'CheckFailed'
        $summary.ForeColor = $script:red
        $summaryDot.BackColor = $script:red
        $footer.Text = $_.Exception.Message
    } finally {
        $refreshButton.Enabled = $true
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = T 'ControlCenterTitle'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(1000, 890)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.MinimumSize = New-Object Drawing.Size(1016, 929)
$controlExecutable = Join-Path $script:installDirectory 'jellyfin-vlc-bridge-control.exe'
$applicationIcon = Get-JvbApplicationIcon @($controlExecutable, $script:executable)
Enable-JvbModernWindow $form $applicationIcon

$header = New-Object System.Windows.Forms.Panel
$header.Location = New-Object System.Drawing.Point(0, 0)
$header.Size = New-Object System.Drawing.Size(1000, 118)
$header.BackColor = $script:JvbPalette.Header
$form.Controls.Add($header)

$accentLine = New-Object Windows.Forms.Panel
$accentLine.Location = New-Object Drawing.Point(0, 114)
$accentLine.Size = New-Object Drawing.Size(1000, 4)
$accentLine.BackColor = $script:JvbPalette.Accent
$header.Controls.Add($accentLine)

$logo = New-Object System.Windows.Forms.PictureBox
$logo.Location = New-Object System.Drawing.Point(28, 22)
$logo.Size = New-Object System.Drawing.Size(72, 72)
$logo.SizeMode = 'Zoom'
if ($applicationIcon) { $logo.Image = $applicationIcon.ToBitmap() }
$header.Controls.Add($logo)

$title = New-JvbLabel $header 'Jellyfin VLC Bridge' 120 22 390 40 23 `
    ([Drawing.FontStyle]::Bold)
$subtitle = New-JvbLabel $header (T 'ControlCenterSubtitle') 122 65 390 26 10 `
    ([Drawing.FontStyle]::Regular) $script:JvbPalette.TextMuted

$versionPill = New-JvbCard $header 770 18 198 34 $script:JvbPalette.SurfaceAlt 17
$versionLabel = New-JvbLabel $versionPill (T 'Version' @($script:bridgeVersion)) `
    12 7 174 22 9 ([Drawing.FontStyle]::Bold) $script:JvbPalette.Text
$versionLabel.TextAlign = 'MiddleCenter'

$updateStatus = New-JvbLabel $header (T 'UpdatesWaiting') 520 18 230 28 9 `
    ([Drawing.FontStyle]::Regular) $script:JvbPalette.TextMuted
$updateStatus.TextAlign = 'MiddleRight'

$languageLabel = New-JvbLabel $header (T 'Language') 520 76 70 24 9 `
    ([Drawing.FontStyle]::Regular) $script:JvbPalette.TextMuted
$languageLabel.TextAlign = 'MiddleLeft'

$languageBox = New-Object System.Windows.Forms.ComboBox
$languageBox.DropDownStyle = 'DropDownList'
[void]$languageBox.Items.Add((T 'LanguageAuto'))
[void]$languageBox.Items.Add((T 'LanguageFrench'))
[void]$languageBox.Items.Add((T 'LanguageEnglish'))
$languageBox.Location = New-Object System.Drawing.Point(590, 72)
$languageBox.Size = New-Object System.Drawing.Size(166, 28)
$languageBox.SelectedIndex = switch ($script:JvbLanguagePreference) { 'fr' { 1 } 'en' { 2 } default { 0 } }
Set-JvbComboStyle $languageBox
$header.Controls.Add($languageBox)

$updateButton = New-Object System.Windows.Forms.Button
$updateButton.Text = T 'CheckNow'
$updateButton.Location = New-Object System.Drawing.Point(770, 68)
$updateButton.Size = New-Object System.Drawing.Size(198, 36)
$updateButton.Enabled = $false
Set-JvbButtonStyle $updateButton 'Success'
$header.Controls.Add($updateButton)

$summaryCard = New-JvbCard $form 26 136 948 64 $script:JvbPalette.Surface 14
$summaryDot = New-JvbDot $summaryCard 22 27 $script:JvbPalette.TextFaint
$summary = New-JvbLabel $summaryCard (T 'CheckInProgress') 48 15 870 36 12 `
    ([Drawing.FontStyle]::Bold)
$summary.TextAlign = 'MiddleLeft'

$jellyfinCard = New-StatusCard 26 'Jellyfin'
$vlcCard = New-StatusCard 347 (T 'VlcPlayer')
$browserCard = New-StatusCard 668 (T 'BrowserExtension')

$settings = New-JvbCard $form 26 372 948 284
$settingsTitle = New-JvbLabel $settings (T 'PlaybackSettings') 20 14 400 30 13 `
    ([Drawing.FontStyle]::Bold)

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 12000
$toolTip.InitialDelay = 250
$toolTip.ReshowDelay = 100

$serverLabel = New-JvbLabel $settings (T 'JellyfinServer') 20 54 135 25 9 `
    ([Drawing.FontStyle]::Regular) $script:JvbPalette.TextMuted
$serverValue = New-JvbLabel $settings (T 'NotConfigured') 165 52 500 27 10 `
    ([Drawing.FontStyle]::Bold)

$changeServerButton = New-Object Windows.Forms.Button
$changeServerButton.Text = T 'ChangeServer'
$changeServerButton.Location = New-Object Drawing.Point(700, 48)
$changeServerButton.Size = New-Object Drawing.Size(220, 34)
Set-JvbButtonStyle $changeServerButton 'Secondary' 10
$settings.Controls.Add($changeServerButton)

$modeLabel = New-JvbLabel $settings (T 'PlaybackMode') 20 96 135 25 9 `
    ([Drawing.FontStyle]::Regular) $script:JvbPalette.TextMuted

$modeBox = New-Object System.Windows.Forms.ComboBox
$modeBox.DropDownStyle = 'DropDownList'
[void]$modeBox.Items.Add('HTTP Direct Play')
[void]$modeBox.Items.Add((T 'SmbMode'))
$modeBox.Location = New-Object System.Drawing.Point(165, 90)
$modeBox.Size = New-Object System.Drawing.Size(230, 30)
Set-JvbComboStyle $modeBox
$modeBox.SelectedIndex = 0
$settings.Controls.Add($modeBox)

$modeHelp = New-Object System.Windows.Forms.Button
$modeHelp.Text = '?'
$modeHelp.Location = New-Object System.Drawing.Point(405, 90)
$modeHelp.Size = New-Object System.Drawing.Size(28, 28)
Set-JvbButtonStyle $modeHelp 'Ghost' 14
$settings.Controls.Add($modeHelp)
$modeHelp.BringToFront()
$toolTip.SetToolTip($modeHelp, (T 'ModeHelpTip'))

$modeDescription = New-JvbLabel $settings '' 455 86 465 42 9 `
    ([Drawing.FontStyle]::Regular) $script:muted

$vlcLabel = New-JvbLabel $settings (T 'VlcPath') 20 144 104 25 9 `
    ([Drawing.FontStyle]::Regular) $script:JvbPalette.TextMuted

$vlcHelp = New-Object System.Windows.Forms.Button
$vlcHelp.Text = '?'
$vlcHelp.Location = New-Object System.Drawing.Point(128, 139)
$vlcHelp.Size = New-Object System.Drawing.Size(28, 28)
Set-JvbButtonStyle $vlcHelp 'Ghost' 14
$settings.Controls.Add($vlcHelp)
$vlcHelp.BringToFront()
$toolTip.SetToolTip($vlcHelp, (T 'VlcHelpTip'))

$vlcBox = New-Object System.Windows.Forms.TextBox
$vlcBox.Location = New-Object System.Drawing.Point(165, 138)
$vlcBox.Size = New-Object System.Drawing.Size(650, 30)
Set-JvbInputStyle $vlcBox
$settings.Controls.Add($vlcBox)

$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = T 'Browse'
$browseButton.Location = New-Object System.Drawing.Point(825, 136)
$browseButton.Size = New-Object System.Drawing.Size(100, 34)
Set-JvbButtonStyle $browseButton 'Secondary'
$settings.Controls.Add($browseButton)

$mappingPanel = New-JvbCard $settings 16 178 916 70 $script:JvbPalette.SurfaceAlt 10
$mappingPanel.Visible = $false

$serverPathLabel = New-JvbLabel $mappingPanel (T 'JellyfinPath') 14 6 390 20 8.5 `
    ([Drawing.FontStyle]::Regular) $script:JvbPalette.TextMuted

$serverPathBox = New-Object System.Windows.Forms.TextBox
$serverPathBox.Location = New-Object System.Drawing.Point(14, 30)
$serverPathBox.Size = New-Object System.Drawing.Size(390, 27)
Set-JvbInputStyle $serverPathBox
$mappingPanel.Controls.Add($serverPathBox)

$clientPathLabel = New-JvbLabel $mappingPanel (T 'ClientNetworkPath') 455 6 390 20 8.5 `
    ([Drawing.FontStyle]::Regular) $script:JvbPalette.TextMuted

$clientPathBox = New-Object System.Windows.Forms.TextBox
$clientPathBox.Location = New-Object System.Drawing.Point(455, 30)
$clientPathBox.Size = New-Object System.Drawing.Size(390, 27)
Set-JvbInputStyle $clientPathBox
$mappingPanel.Controls.Add($clientPathBox)

$mappingHint = New-Object System.Windows.Forms.Label
$mappingHint.Text = T 'MappingExample'
$mappingHint.Location = New-Object System.Drawing.Point(14, 51)
$mappingHint.Size = New-Object System.Drawing.Size(820, 16)
$mappingHint.ForeColor = $script:muted
$mappingHint.Font = New-JvbFont 7.5
$mappingPanel.Controls.Add($mappingHint)

$mappingHelp = New-Object System.Windows.Forms.Button
$mappingHelp.Text = '?'
$mappingHelp.Location = New-Object System.Drawing.Point(864, 28)
$mappingHelp.Size = New-Object System.Drawing.Size(32, 32)
Set-JvbButtonStyle $mappingHelp 'Ghost' 16
$mappingPanel.Controls.Add($mappingHelp)
$mappingHelp.BringToFront()
$toolTip.SetToolTip($mappingHelp, (T 'MappingHelpTip'))

$saveButton = New-Object System.Windows.Forms.Button
$saveButton.Text = T 'SaveSettings'
$saveButton.Location = New-Object System.Drawing.Point(742, 250)
$saveButton.Size = New-Object System.Drawing.Size(190, 38)
Set-JvbButtonStyle $saveButton 'Primary'
$settings.Controls.Add($saveButton)

$actions = New-JvbCard $form 26 672 948 142
$actionsTitle = New-JvbLabel $actions (T 'QuickActions') 18 10 450 26 11 `
    ([Drawing.FontStyle]::Bold)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = T 'Refresh'
$refreshButton.Location = New-Object System.Drawing.Point(18, 42)
$refreshButton.Size = New-Object System.Drawing.Size(118, 36)
Set-JvbButtonStyle $refreshButton 'Secondary'
$actions.Controls.Add($refreshButton)

$repairButton = New-Object System.Windows.Forms.Button
$repairButton.Text = T 'Repair'
$repairButton.Location = New-Object System.Drawing.Point(146, 42)
$repairButton.Size = New-Object System.Drawing.Size(118, 36)
Set-JvbButtonStyle $repairButton 'Success'
$actions.Controls.Add($repairButton)

$extensionButton = New-Object System.Windows.Forms.Button
$extensionButton.Text = T 'OpenExtension'
$extensionButton.Location = New-Object System.Drawing.Point(274, 42)
$extensionButton.Size = New-Object System.Drawing.Size(170, 36)
Set-JvbButtonStyle $extensionButton 'Secondary'
$actions.Controls.Add($extensionButton)

$logsButton = New-Object System.Windows.Forms.Button
$logsButton.Text = T 'ViewLogs'
$logsButton.Location = New-Object System.Drawing.Point(454, 42)
$logsButton.Size = New-Object System.Drawing.Size(132, 36)
Set-JvbButtonStyle $logsButton 'Secondary'
$actions.Controls.Add($logsButton)

$copyButton = New-Object System.Windows.Forms.Button
$copyButton.Text = T 'CopyDiagnostic'
$copyButton.Location = New-Object System.Drawing.Point(596, 42)
$copyButton.Size = New-Object System.Drawing.Size(160, 36)
Set-JvbButtonStyle $copyButton 'Ghost'
$actions.Controls.Add($copyButton)

$supportButton = New-Object System.Windows.Forms.Button
$supportButton.Text = T 'CreateSupportBundle'
$supportButton.Location = New-Object System.Drawing.Point(18, 90)
$supportButton.Size = New-Object System.Drawing.Size(230, 36)
Set-JvbButtonStyle $supportButton 'Primary'
$actions.Controls.Add($supportButton)
$toolTip.SetToolTip($supportButton, (T 'SupportBundleTip'))

$helpButton = New-Object System.Windows.Forms.Button
$helpButton.Text = T 'HelpBug'
$helpButton.Location = New-Object System.Drawing.Point(258, 90)
$helpButton.Size = New-Object System.Drawing.Size(190, 36)
Set-JvbButtonStyle $helpButton 'Secondary'
$actions.Controls.Add($helpButton)

$privacy = New-JvbLabel $form (T 'PrivacyNote') 28 824 944 26 8.5 `
    ([Drawing.FontStyle]::Regular) $script:JvbPalette.TextFaint
$footer = New-JvbLabel $form '' 28 854 944 24 8.5 `
    ([Drawing.FontStyle]::Regular) $script:JvbPalette.TextMuted

$refreshButton.Add_Click({ Refresh-BridgeStatus })
$changeServerButton.Add_Click({
    if (Show-ChangeServerDialog) {
        Refresh-BridgeStatus
        $footer.Text = T 'ServerChanged'
    }
})
$languageBox.Add_SelectedIndexChanged({
    $preference = switch ($languageBox.SelectedIndex) { 1 { 'fr' } 2 { 'en' } default { 'auto' } }
    if ($preference -eq $script:JvbLanguagePreference) { return }
    Set-JvbLanguagePreference $preference
    $script:JvbLanguagePreference = $preference
    $footer.Text = T 'LanguageRestart'
})
$updateButton.Add_Click({
    if ($script:updateAvailable) { Start-UpdateOperation 'download' }
    else { Start-UpdateOperation 'check' }
})
$modeHelp.Add_Click({
    Show-JvbMessageDialog (T 'HttpHelpTitle') (T 'HttpHelpBody') 'Info' `
        $applicationIcon (T 'Close')
})
$vlcHelp.Add_Click({
    Show-JvbMessageDialog (T 'VlcHelpTitle') (T 'VlcHelpBody') 'Info' `
        $applicationIcon (T 'Close')
})
$mappingHelp.Add_Click({
    Show-JvbMessageDialog (T 'MappingHelpTitle') (T 'MappingHelpBody') 'Info' `
        $applicationIcon (T 'Close')
})
$repairButton.Add_Click({
    try {
        $repairButton.Enabled = $false
        $footer.Text = T 'Repairing'
        [void](Invoke-Bridge @('repair'))
        Refresh-BridgeStatus
        Show-JvbMessageDialog 'Jellyfin VLC Bridge' (T 'RepairDone') 'Success' `
            $applicationIcon (T 'Close')
    } catch { Show-BridgeError $_.Exception.Message }
    finally { $repairButton.Enabled = $true }
})
$extensionButton.Add_Click({
    try { [void](Invoke-Bridge @('open-extension')) } catch { Show-BridgeError $_.Exception.Message }
})
$helpButton.Add_Click({
    try { [void](Invoke-Bridge @('open-help')) } catch { Show-BridgeError $_.Exception.Message }
})
$logsButton.Add_Click({
    try {
        $directory = Join-Path $env:LOCALAPPDATA 'JellyfinVlcBridge\Logs'
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        Start-Process explorer.exe $directory
    } catch { Show-BridgeError $_.Exception.Message }
})
$browseButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = 'VLC (vlc.exe)|vlc.exe|Programmes (*.exe)|*.exe'
    if ($dialog.ShowDialog() -eq 'OK') { $vlcBox.Text = $dialog.FileName }
})
$modeBox.Add_SelectedIndexChanged({ Update-MappingControls })
$saveButton.Add_Click({
    try {
        if (-not (Test-Path $script:configFile)) { throw (T 'MissingConfig') }
        $config = Get-Content -LiteralPath $script:configFile -Raw | ConvertFrom-Json
        $config.playbackMode = if ($modeBox.SelectedIndex -eq 1) { 'smb' } else { 'http' }
        $config.vlcPath = if ([string]::IsNullOrWhiteSpace($vlcBox.Text)) { $null } else { $vlcBox.Text.Trim() }
        if ($config.playbackMode -eq 'smb') {
            if ([string]::IsNullOrWhiteSpace($serverPathBox.Text) -or [string]::IsNullOrWhiteSpace($clientPathBox.Text)) {
                throw (T 'SmbRequiresMapping')
            }
            $config.pathMappings = @([PSCustomObject]@{
                serverPrefix = $serverPathBox.Text.Trim()
                clientPrefix = $clientPathBox.Text.Trim()
            })
        }
        $json = $config | ConvertTo-Json -Depth 8
        $temporaryConfig = $script:configFile + '.tmp-' + [Guid]::NewGuid().ToString('N')
        $backupConfig = $script:configFile + '.bak'
        try {
            $utf8 = New-Object System.Text.UTF8Encoding($false)
            [IO.File]::WriteAllText($temporaryConfig, $json, $utf8)
            [IO.File]::Replace($temporaryConfig, $script:configFile, $backupConfig, $true)
            if (Test-Path -LiteralPath $backupConfig) { Remove-Item -LiteralPath $backupConfig -Force }
        } finally {
            if (Test-Path -LiteralPath $temporaryConfig) { Remove-Item -LiteralPath $temporaryConfig -Force -ErrorAction SilentlyContinue }
        }
        $footer.Text = T 'SettingsSaved'
        Refresh-BridgeStatus
    } catch { Show-BridgeError $_.Exception.Message }
})
$copyButton.Add_Click({
    try {
        if (-not $script:health) { Refresh-BridgeStatus }
        $diagnostic = @(
            'BridgeVersion=' + $script:health.version,
            'Configured=' + $script:health.configured,
            'JellyfinConnected=' + $script:health.jellyfinConnected,
            'VlcDetected=' + $script:health.vlcReady,
            'VlcVersion=' + $script:health.vlcVersion,
            'BrowserIntegration=' + ($script:health.protocolReady -and $script:health.nativeMessagingReady),
            'ExtensionActive=' + $script:health.extensionActive,
            'ExtensionVersion=' + $script:health.extensionVersion,
            'PlaybackMode=' + $script:health.playbackMode,
            'Ready=' + $script:health.ready
        ) -join "`r`n"
        foreach ($finding in @($script:health.findings)) {
            $diagnostic += "`r`nFinding[$($finding.code)]=$($finding.message)"
            $diagnostic += "`r`nAction[$($finding.code)]=$($finding.action)"
        }
        [System.Windows.Forms.Clipboard]::SetText($diagnostic)
        $footer.Text = T 'DiagnosticCopied'
    } catch { Show-BridgeError $_.Exception.Message }
})

$supportButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Title = T 'SupportBundleDialogTitle'
    $dialog.Filter = T 'SupportBundleFilter'
    $dialog.FileName = 'JellyfinVlcBridge-Support-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.zip'
    $dialog.OverwritePrompt = $true
    if ($dialog.ShowDialog() -ne 'OK') { return }
    try {
        $supportButton.Enabled = $false
        $footer.Text = T 'CheckInProgress'
        $result = (Invoke-Bridge @('support-bundle', '--output', $dialog.FileName, '--json')) | ConvertFrom-Json
        $footer.Text = T 'SupportBundleCreated' @($result.path)
        Show-JvbMessageDialog 'Jellyfin VLC Bridge' `
            (T 'SupportBundleCreated' @($result.path)) 'Success' $applicationIcon (T 'Close')
    } catch { Show-BridgeError $_.Exception.Message }
    finally { $supportButton.Enabled = $true }
})

$updateTimer = New-Object System.Windows.Forms.Timer
$updateTimer.Interval = 300
$updateTimer.Add_Tick({
    if (-not $script:updateProcess -or -not $script:updateProcess.HasExited) { return }
    $updateTimer.Stop()
    try {
        $exitCode = $script:updateProcess.ExitCode
        $output = $script:updateProcess.StandardOutput.ReadToEnd()
        $errorOutput = $script:updateProcess.StandardError.ReadToEnd()
        $operation = $script:updateOperation
        $script:updateProcess.Dispose()
        $script:updateProcess = $null
        $script:updateOperation = 'idle'
        if ($exitCode -ne 0) { throw $errorOutput.Trim() }
        $result = $output | ConvertFrom-Json

        if ($operation -eq 'check') {
            $script:updateAvailable = [bool]$result.updateAvailable
            $script:latestVersion = $result.latestVersion
            if ($script:updateAvailable) {
                $updateStatus.Text = T 'NewVersion' @($result.latestVersion)
                $updateButton.Text = T 'InstallVersion' @($result.latestVersion)
                $updateButton.Enabled = $true
            } else {
                $updateStatus.Text = T 'UpToDate'
                $updateButton.Text = T 'UpToDateButton'
                $updateButton.Enabled = $false
            }
            return
        }

        $updatesRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'JellyfinVlcBridge\Updates')).TrimEnd('\') + '\'
        $installerPath = [IO.Path]::GetFullPath([string]$result.path)
        if (-not $installerPath.StartsWith($updatesRoot, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path $installerPath)) {
            throw (T 'UpdateFileUnsafe')
        }
        $updateStatus.Text = T 'InstallerOpening'
        Start-Process -FilePath $installerPath
        $script:allowExit = $true
        $form.Close()
    } catch {
        $message = $_.Exception.Message
        $script:updateAvailable = $false
        if ($message -match 'publication') {
            $updateStatus.Text = T 'AvailableAfterPublication'
        } else {
            $updateStatus.Text = T 'CheckImpossible'
            $footer.Text = $message
        }
        $updateButton.Text = T 'Retry'
        $updateButton.Enabled = $true
        $script:updateOperation = 'idle'
        if ($script:updateProcess) {
            try { $script:updateProcess.Dispose() } catch { }
            $script:updateProcess = $null
        }
    }
})

$form.Add_Shown({
    Refresh-BridgeStatus
    Start-UpdateOperation 'check'
    if ($StartInTray) {
        [void]$form.BeginInvoke([Action]{
            Hide-ControlCenter
            $form.Opacity = 1
            $form.WindowState = [Windows.Forms.FormWindowState]::Normal
        })
    }
})
$form.Add_FormClosing({
    # CloseMainWindow, le bouton X et certains raccourcis Windows n'utilisent pas
    # toujours le même CloseReason. Toute fermeture ordinaire doit donc masquer
    # le centre ; seuls Quitter, la mise à jour et l'arrêt de Windows le terminent.
    if (-not $script:allowExit -and
        $_.CloseReason -ne [Windows.Forms.CloseReason]::WindowsShutDown) {
        # L'annulation d'un WM_CLOSE peut rendre la fenêtre visible pendant
        # quelques millisecondes. La neutraliser avant Cancel supprime ce flash.
        $form.Opacity = 0
        $form.ShowInTaskbar = $false
        $_.Cancel = $true
        [void]$form.BeginInvoke([Action]{
            try {
                Hide-ControlCenter
            } finally {
                # Préparer le prochain affichage tout en restant masqué.
                $form.Opacity = 1
            }
        })
        return
    }
    $updateTimer.Stop()
    if ($script:showEventTimer) { $script:showEventTimer.Stop() }
    if ($script:updateProcess -and -not $script:updateProcess.HasExited) {
        try { $script:updateProcess.Kill() } catch { }
    }
})
if ($ValidateOnly) { exit 0 }

if (-not [string]::IsNullOrWhiteSpace($ShowEventName)) {
    try {
        $script:showEvent = [Threading.EventWaitHandle]::OpenExisting($ShowEventName)
        $script:showEventTimer = New-Object Windows.Forms.Timer
        $script:showEventTimer.Interval = 250
        $script:showEventTimer.Add_Tick({
            if ($script:showEvent -and $script:showEvent.WaitOne(0)) {
                Show-ControlCenter
            }
        })
        $script:showEventTimer.Start()
    } catch {
        $script:showEvent = $null
        $script:showEventTimer = $null
    }
}

$trayMenu = New-Object Windows.Forms.ContextMenu
$trayOpen = New-Object Windows.Forms.MenuItem (T 'TrayOpen')
$trayRefresh = New-Object Windows.Forms.MenuItem (T 'TrayRefresh')
$trayExit = New-Object Windows.Forms.MenuItem (T 'TrayExit')
$trayMenu.MenuItems.Add($trayOpen) | Out-Null
$trayMenu.MenuItems.Add($trayRefresh) | Out-Null
$trayMenu.MenuItems.Add('-') | Out-Null
$trayMenu.MenuItems.Add($trayExit) | Out-Null

$script:trayIcon = New-Object Windows.Forms.NotifyIcon
$script:trayIcon.Text = T 'TrayReady'
$script:trayIcon.Icon = if ($applicationIcon) {
    $applicationIcon
} else {
    [Drawing.SystemIcons]::Application
}
$script:trayIcon.ContextMenu = $trayMenu
$script:trayIcon.Visible = $true

$trayOpen.Add_Click({ Show-ControlCenter })
$trayRefresh.Add_Click({
    Show-ControlCenter
    Refresh-BridgeStatus
})
$trayExit.Add_Click({
    $script:allowExit = $true
    $form.Close()
})
$script:trayIcon.Add_DoubleClick({ Show-ControlCenter })

if ($StartInTray) {
    # Application.Run doit créer la fenêtre principale pour conserver une vraie
    # boucle de messages. La rendre invisible avant ce premier affichage évite
    # toutefois le flash de fenêtre à la fin de l'installation.
    $form.ShowInTaskbar = $false
    $form.Opacity = 0
}

try {
    # ShowDialog quitte sa boucle modale dès que la fenêtre est masquée. Le centre
    # et son NotifyIcon étaient donc détruits après Réduire ou Fermer.
    [Windows.Forms.Application]::Run($form)
} finally {
    if ($script:showEventTimer) {
        $script:showEventTimer.Stop()
        $script:showEventTimer.Dispose()
    }
    if ($script:showEvent) { $script:showEvent.Dispose() }
    if ($script:trayIcon) {
        $script:trayIcon.Visible = $false
        $script:trayIcon.Dispose()
    }
    $trayMenu.Dispose()
}
