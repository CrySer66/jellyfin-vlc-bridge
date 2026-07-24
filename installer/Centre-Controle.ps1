param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:installDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $script:installDirectory 'Localization.ps1')
. (Join-Path $script:installDirectory 'UiTheme.ps1')
$script:bridgeVersion = '1.15.0'
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
$serverValue = New-JvbLabel $settings (T 'NotConfigured') 165 52 750 27 10 `
    ([Drawing.FontStyle]::Bold)

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
$modeHelp.Size = New-Object System.Drawing.Size(30, 30)
Set-JvbButtonStyle $modeHelp 'Ghost'
$settings.Controls.Add($modeHelp)
$toolTip.SetToolTip($modeHelp, (T 'ModeHelpTip'))

$modeDescription = New-JvbLabel $settings '' 455 86 465 42 9 `
    ([Drawing.FontStyle]::Regular) $script:muted

$vlcLabel = New-JvbLabel $settings (T 'VlcPath') 20 144 135 25 9 `
    ([Drawing.FontStyle]::Regular) $script:JvbPalette.TextMuted

$vlcHelp = New-Object System.Windows.Forms.Button
$vlcHelp.Text = '?'
$vlcHelp.Location = New-Object System.Drawing.Point(125, 138)
$vlcHelp.Size = New-Object System.Drawing.Size(30, 30)
Set-JvbButtonStyle $vlcHelp 'Ghost'
$settings.Controls.Add($vlcHelp)
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
Set-JvbButtonStyle $mappingHelp 'Ghost'
$mappingPanel.Controls.Add($mappingHelp)
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
})
$form.Add_FormClosing({
    $updateTimer.Stop()
    if ($script:updateProcess -and -not $script:updateProcess.HasExited) {
        try { $script:updateProcess.Kill() } catch { }
    }
})
if ($ValidateOnly) { exit 0 }
[void]$form.ShowDialog()
