param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:installDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $script:installDirectory 'Localization.ps1')
$script:bridgeVersion = '1.12.0'
$script:executable = Join-Path $script:installDirectory 'jellyfin-vlc-bridge.exe'
$script:configFile = Join-Path $env:LOCALAPPDATA 'JellyfinVlcBridge\config.json'
$script:health = $null
$script:updateProcess = $null
$script:updateOperation = 'idle'
$script:updateAvailable = $false
$script:latestVersion = $null
$script:blue = [System.Drawing.Color]::FromArgb(8, 91, 126)
$script:green = [System.Drawing.Color]::FromArgb(31, 143, 91)
$script:orange = [System.Drawing.Color]::FromArgb(202, 116, 24)
$script:red = [System.Drawing.Color]::FromArgb(190, 55, 55)
$script:muted = [System.Drawing.Color]::FromArgb(91, 101, 111)

function Show-BridgeError([string]$message) {
    [System.Windows.Forms.MessageBox]::Show($message, 'Jellyfin VLC Bridge', 'OK', 'Error') | Out-Null
}

function New-StatusCard([int]$left, [string]$title) {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point($left, 145)
    $panel.Size = New-Object System.Drawing.Size(234, 118)
    $panel.BackColor = [System.Drawing.Color]::White
    $panel.BorderStyle = 'FixedSingle'

    $name = New-Object System.Windows.Forms.Label
    $name.Text = $title
    $name.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
    $name.Location = New-Object System.Drawing.Point(15, 13)
    $name.AutoSize = $true
    $panel.Controls.Add($name)

    $state = New-Object System.Windows.Forms.Label
    $state.Text = T 'Checking'
    $state.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $state.Location = New-Object System.Drawing.Point(15, 43)
    $state.AutoSize = $true
    $panel.Controls.Add($state)

    $detail = New-Object System.Windows.Forms.Label
    $detail.Text = ''
    $detail.Location = New-Object System.Drawing.Point(15, 70)
    $detail.Size = New-Object System.Drawing.Size(202, 38)
    $detail.ForeColor = $script:muted
    $panel.Controls.Add($detail)

    $form.Controls.Add($panel)
    return @{ Panel = $panel; State = $state; Detail = $detail }
}

function Set-Card($card, [bool]$ready, [string]$readyText, [string]$errorText, [string]$detail) {
    $card.State.Text = if ($ready) { $readyText } else { $errorText }
    $card.State.ForeColor = if ($ready) { $script:green } else { $script:orange }
    $card.Detail.Text = $detail
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

        Set-Card $jellyfinCard $script:health.jellyfinConnected `
            (T 'Connected') (T 'Check') $script:health.jellyfinMessage
        $vlcDetail = if ($script:health.vlcPath) { $script:health.vlcPath } else { T 'NoPath' }
        Set-Card $vlcCard $script:health.vlcReady `
            (T 'VlcDetected') (T 'VlcMissing') $vlcDetail
        $browserRegistered = $script:health.nativeMessagingReady
        $browserReady = $browserRegistered -and $script:health.extensionActive
        if (-not $browserRegistered) {
            $browserDetail = T 'BrowserConnectionMissing'
            $browserError = T 'RepairRequired'
        } elseif ($script:health.extensionActive) {
            $browserDetail = T 'ExtensionContact' @($script:health.extensionVersion)
            $browserError = T 'ExtensionUnconfirmed'
        } else {
            $browserDetail = T 'ExtensionOpenHint'
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

        $allReady = $script:health.jellyfinConnected -and $script:health.vlcReady -and $browserReady
        $summary.Text = if ($allReady) { T 'AllReady' } else { T 'CheckNeeded' }
        $summary.ForeColor = if ($allReady) { $script:green } else { $script:orange }
        $footer.Text = T 'LastCheck' @((Get-Date -Format 'HH:mm:ss'))
    } catch {
        $summary.Text = T 'CheckFailed'
        $summary.ForeColor = $script:red
        $footer.Text = $_.Exception.Message
    } finally {
        $refreshButton.Enabled = $true
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = T 'ControlCenterTitle'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(780, 690)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 250)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
try { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($script:executable) } catch { }

$header = New-Object System.Windows.Forms.Panel
$header.Location = New-Object System.Drawing.Point(0, 0)
$header.Size = New-Object System.Drawing.Size(780, 112)
$header.BackColor = $script:blue
$form.Controls.Add($header)

$logo = New-Object System.Windows.Forms.PictureBox
$logo.Location = New-Object System.Drawing.Point(28, 22)
$logo.Size = New-Object System.Drawing.Size(66, 66)
$logo.SizeMode = 'StretchImage'
try { $logo.Image = $form.Icon.ToBitmap() } catch { }
$header.Controls.Add($logo)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Jellyfin VLC Bridge'
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 21)
$title.ForeColor = [System.Drawing.Color]::White
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(112, 22)
$header.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = T 'ControlCenterSubtitle'
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(214, 238, 247)
$subtitle.AutoSize = $true
$subtitle.Location = New-Object System.Drawing.Point(116, 64)
$header.Controls.Add($subtitle)

$versionLabel = New-Object System.Windows.Forms.Label
$versionLabel.Text = T 'Version' @($script:bridgeVersion)
$versionLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
$versionLabel.ForeColor = [System.Drawing.Color]::White
$versionLabel.AutoSize = $true
$versionLabel.Location = New-Object System.Drawing.Point(515, 17)
$header.Controls.Add($versionLabel)

$updateStatus = New-Object System.Windows.Forms.Label
$updateStatus.Text = T 'UpdatesWaiting'
$updateStatus.ForeColor = [System.Drawing.Color]::FromArgb(214, 238, 247)
$updateStatus.Location = New-Object System.Drawing.Point(515, 43)
$updateStatus.Size = New-Object System.Drawing.Size(235, 22)
$updateStatus.TextAlign = 'MiddleLeft'
$header.Controls.Add($updateStatus)

$updateButton = New-Object System.Windows.Forms.Button
$updateButton.Text = T 'CheckNow'
$updateButton.Location = New-Object System.Drawing.Point(585, 72)
$updateButton.Size = New-Object System.Drawing.Size(165, 30)
$updateButton.BackColor = [System.Drawing.Color]::FromArgb(34, 139, 94)
$updateButton.ForeColor = [System.Drawing.Color]::White
$updateButton.FlatStyle = 'Flat'
$updateButton.Enabled = $false
$header.Controls.Add($updateButton)

$languageLabel = New-Object System.Windows.Forms.Label
$languageLabel.Text = T 'Language'
$languageLabel.ForeColor = [System.Drawing.Color]::White
$languageLabel.AutoSize = $true
$languageLabel.Location = New-Object System.Drawing.Point(333, 79)
$header.Controls.Add($languageLabel)

$languageBox = New-Object System.Windows.Forms.ComboBox
$languageBox.DropDownStyle = 'DropDownList'
[void]$languageBox.Items.Add((T 'LanguageAuto'))
[void]$languageBox.Items.Add((T 'LanguageFrench'))
[void]$languageBox.Items.Add((T 'LanguageEnglish'))
$languageBox.Location = New-Object System.Drawing.Point(400, 74)
$languageBox.Size = New-Object System.Drawing.Size(170, 28)
$languageBox.SelectedIndex = switch ($script:JvbLanguagePreference) { 'fr' { 1 } 'en' { 2 } default { 0 } }
$header.Controls.Add($languageBox)

$summary = New-Object System.Windows.Forms.Label
$summary.Text = T 'CheckInProgress'
$summary.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
$summary.AutoSize = $true
$summary.Location = New-Object System.Drawing.Point(24, 121)
$form.Controls.Add($summary)

$jellyfinCard = New-StatusCard 24 'Jellyfin'
$vlcCard = New-StatusCard 273 (T 'VlcPlayer')
$browserCard = New-StatusCard 522 (T 'BrowserExtension')

$settings = New-Object System.Windows.Forms.GroupBox
$settings.Text = T 'PlaybackSettings'
$settings.Location = New-Object System.Drawing.Point(24, 282)
$settings.Size = New-Object System.Drawing.Size(732, 230)
$form.Controls.Add($settings)

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 12000
$toolTip.InitialDelay = 250
$toolTip.ReshowDelay = 100

$serverLabel = New-Object System.Windows.Forms.Label
$serverLabel.Text = T 'JellyfinServer'
$serverLabel.Location = New-Object System.Drawing.Point(18, 31)
$serverLabel.AutoSize = $true
$settings.Controls.Add($serverLabel)

$serverValue = New-Object System.Windows.Forms.Label
$serverValue.Text = T 'NotConfigured'
$serverValue.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
$serverValue.Location = New-Object System.Drawing.Point(153, 31)
$serverValue.Size = New-Object System.Drawing.Size(550, 22)
$settings.Controls.Add($serverValue)

$modeLabel = New-Object System.Windows.Forms.Label
$modeLabel.Text = T 'PlaybackMode'
$modeLabel.Location = New-Object System.Drawing.Point(18, 70)
$modeLabel.AutoSize = $true
$settings.Controls.Add($modeLabel)

$modeBox = New-Object System.Windows.Forms.ComboBox
$modeBox.DropDownStyle = 'DropDownList'
[void]$modeBox.Items.Add('HTTP Direct Play')
[void]$modeBox.Items.Add((T 'SmbMode'))
$modeBox.Location = New-Object System.Drawing.Point(153, 66)
$modeBox.Size = New-Object System.Drawing.Size(225, 28)
$settings.Controls.Add($modeBox)

$modeHelp = New-Object System.Windows.Forms.Button
$modeHelp.Text = '?'
$modeHelp.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$modeHelp.Location = New-Object System.Drawing.Point(385, 66)
$modeHelp.Size = New-Object System.Drawing.Size(26, 26)
$modeHelp.FlatStyle = 'Flat'
$modeHelp.FlatAppearance.BorderColor = $script:blue
$modeHelp.ForeColor = $script:blue
$settings.Controls.Add($modeHelp)
$toolTip.SetToolTip($modeHelp, (T 'ModeHelpTip'))

$modeDescription = New-Object System.Windows.Forms.Label
$modeDescription.Location = New-Object System.Drawing.Point(425, 61)
$modeDescription.Size = New-Object System.Drawing.Size(280, 42)
$modeDescription.ForeColor = $script:muted
$settings.Controls.Add($modeDescription)

$vlcLabel = New-Object System.Windows.Forms.Label
$vlcLabel.Text = T 'VlcPath'
$vlcLabel.Location = New-Object System.Drawing.Point(18, 112)
$vlcLabel.AutoSize = $true
$settings.Controls.Add($vlcLabel)

$vlcHelp = New-Object System.Windows.Forms.Button
$vlcHelp.Text = '?'
$vlcHelp.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$vlcHelp.Location = New-Object System.Drawing.Point(119, 107)
$vlcHelp.Size = New-Object System.Drawing.Size(26, 26)
$vlcHelp.FlatStyle = 'Flat'
$vlcHelp.FlatAppearance.BorderColor = $script:blue
$vlcHelp.ForeColor = $script:blue
$settings.Controls.Add($vlcHelp)
$toolTip.SetToolTip($vlcHelp, (T 'VlcHelpTip'))

$vlcBox = New-Object System.Windows.Forms.TextBox
$vlcBox.Location = New-Object System.Drawing.Point(153, 108)
$vlcBox.Size = New-Object System.Drawing.Size(452, 28)
$settings.Controls.Add($vlcBox)

$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = T 'Browse'
$browseButton.Location = New-Object System.Drawing.Point(614, 106)
$browseButton.Size = New-Object System.Drawing.Size(95, 31)
$settings.Controls.Add($browseButton)

$mappingPanel = New-Object System.Windows.Forms.Panel
$mappingPanel.Location = New-Object System.Drawing.Point(14, 145)
$mappingPanel.Size = New-Object System.Drawing.Size(702, 76)
$mappingPanel.Visible = $false
$settings.Controls.Add($mappingPanel)

$serverPathLabel = New-Object System.Windows.Forms.Label
$serverPathLabel.Text = T 'JellyfinPath'
$serverPathLabel.Location = New-Object System.Drawing.Point(4, 1)
$serverPathLabel.AutoSize = $true
$mappingPanel.Controls.Add($serverPathLabel)

$serverPathBox = New-Object System.Windows.Forms.TextBox
$serverPathBox.Location = New-Object System.Drawing.Point(4, 24)
$serverPathBox.Size = New-Object System.Drawing.Size(315, 28)
$mappingPanel.Controls.Add($serverPathBox)

$clientPathLabel = New-Object System.Windows.Forms.Label
$clientPathLabel.Text = T 'ClientNetworkPath'
$clientPathLabel.Location = New-Object System.Drawing.Point(346, 1)
$clientPathLabel.AutoSize = $true
$mappingPanel.Controls.Add($clientPathLabel)

$clientPathBox = New-Object System.Windows.Forms.TextBox
$clientPathBox.Location = New-Object System.Drawing.Point(346, 24)
$clientPathBox.Size = New-Object System.Drawing.Size(315, 28)
$mappingPanel.Controls.Add($clientPathBox)

$mappingHint = New-Object System.Windows.Forms.Label
$mappingHint.Text = T 'MappingExample'
$mappingHint.Location = New-Object System.Drawing.Point(4, 55)
$mappingHint.Size = New-Object System.Drawing.Size(610, 20)
$mappingHint.ForeColor = $script:muted
$mappingPanel.Controls.Add($mappingHint)

$mappingHelp = New-Object System.Windows.Forms.Button
$mappingHelp.Text = '?'
$mappingHelp.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$mappingHelp.Location = New-Object System.Drawing.Point(668, 23)
$mappingHelp.Size = New-Object System.Drawing.Size(26, 26)
$mappingHelp.FlatStyle = 'Flat'
$mappingHelp.FlatAppearance.BorderColor = $script:blue
$mappingHelp.ForeColor = $script:blue
$mappingPanel.Controls.Add($mappingHelp)
$toolTip.SetToolTip($mappingHelp, (T 'MappingHelpTip'))

$saveButton = New-Object System.Windows.Forms.Button
$saveButton.Text = T 'SaveSettings'
$saveButton.Location = New-Object System.Drawing.Point(568, 529)
$saveButton.Size = New-Object System.Drawing.Size(188, 38)
$saveButton.BackColor = $script:blue
$saveButton.ForeColor = [System.Drawing.Color]::White
$saveButton.FlatStyle = 'Flat'
$form.Controls.Add($saveButton)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = T 'Refresh'
$refreshButton.Location = New-Object System.Drawing.Point(24, 529)
$refreshButton.Size = New-Object System.Drawing.Size(105, 38)
$form.Controls.Add($refreshButton)

$repairButton = New-Object System.Windows.Forms.Button
$repairButton.Text = T 'Repair'
$repairButton.Location = New-Object System.Drawing.Point(139, 529)
$repairButton.Size = New-Object System.Drawing.Size(105, 38)
$repairButton.BackColor = [System.Drawing.Color]::FromArgb(34, 139, 94)
$repairButton.ForeColor = [System.Drawing.Color]::White
$repairButton.FlatStyle = 'Flat'
$form.Controls.Add($repairButton)

$extensionButton = New-Object System.Windows.Forms.Button
$extensionButton.Text = T 'OpenExtension'
$extensionButton.Location = New-Object System.Drawing.Point(254, 529)
$extensionButton.Size = New-Object System.Drawing.Size(136, 38)
$form.Controls.Add($extensionButton)

$logsButton = New-Object System.Windows.Forms.Button
$logsButton.Text = T 'ViewLogs'
$logsButton.Location = New-Object System.Drawing.Point(400, 529)
$logsButton.Size = New-Object System.Drawing.Size(146, 38)
$form.Controls.Add($logsButton)

$copyButton = New-Object System.Windows.Forms.Button
$copyButton.Text = T 'CopyDiagnostic'
$copyButton.Location = New-Object System.Drawing.Point(24, 586)
$copyButton.Size = New-Object System.Drawing.Size(246, 36)
$form.Controls.Add($copyButton)

$helpButton = New-Object System.Windows.Forms.Button
$helpButton.Text = T 'HelpBug'
$helpButton.Location = New-Object System.Drawing.Point(574, 586)
$helpButton.Size = New-Object System.Drawing.Size(182, 36)
$form.Controls.Add($helpButton)

$privacy = New-Object System.Windows.Forms.Label
$privacy.Text = T 'PrivacyNote'
$privacy.Location = New-Object System.Drawing.Point(287, 593)
$privacy.Size = New-Object System.Drawing.Size(270, 40)
$privacy.ForeColor = $script:muted
$form.Controls.Add($privacy)

$footer = New-Object System.Windows.Forms.Label
$footer.Text = ''
$footer.Location = New-Object System.Drawing.Point(24, 650)
$footer.Size = New-Object System.Drawing.Size(732, 24)
$footer.ForeColor = $script:muted
$form.Controls.Add($footer)

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
    [System.Windows.Forms.MessageBox]::Show(
        (T 'HttpHelpBody'), (T 'HttpHelpTitle'), 'OK', 'Information') | Out-Null
})
$vlcHelp.Add_Click({
    [System.Windows.Forms.MessageBox]::Show(
        (T 'VlcHelpBody'), (T 'VlcHelpTitle'), 'OK', 'Information') | Out-Null
})
$mappingHelp.Add_Click({
    [System.Windows.Forms.MessageBox]::Show(
        (T 'MappingHelpBody'), (T 'MappingHelpTitle'), 'OK', 'Information') | Out-Null
})
$repairButton.Add_Click({
    try {
        $repairButton.Enabled = $false
        $footer.Text = T 'Repairing'
        [void](Invoke-Bridge @('repair'))
        Refresh-BridgeStatus
        [System.Windows.Forms.MessageBox]::Show((T 'RepairDone'), 'Jellyfin VLC Bridge', 'OK', 'Information') | Out-Null
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
            'Jellyfin VLC Bridge ' + $script:health.version,
            'Serveur : ' + $script:health.serverUrl,
            'Jellyfin connecte : ' + $script:health.jellyfinConnected,
            'VLC detecte : ' + $script:health.vlcReady,
            'VLC : ' + $script:health.vlcPath,
            'Version VLC : ' + $script:health.vlcVersion,
            'Integration navigateur : ' + ($script:health.protocolReady -and $script:health.nativeMessagingReady),
            'Extension active : ' + $script:health.extensionActive,
            'Version extension : ' + $script:health.extensionVersion,
            'Mode : ' + $script:health.playbackMode,
            'Journal : ' + $script:health.logPath
        ) -join "`r`n"
        [System.Windows.Forms.Clipboard]::SetText($diagnostic)
        $footer.Text = T 'DiagnosticCopied'
    } catch { Show-BridgeError $_.Exception.Message }
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
