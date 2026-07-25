$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:bridgeVersion = '1.17.0'
$script:chromeWebStoreId = 'hkjbodgdbjhignhlbecchiigcfigpidp'
$script:chromeWebStoreUrl = 'https://chromewebstore.google.com/detail/' + $script:chromeWebStoreId
$script:packageDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $script:packageDirectory 'Localization.ps1')
. (Join-Path $script:packageDirectory 'UiTheme.ps1')
$script:rootDirectory = Join-Path $env:LOCALAPPDATA 'JellyfinVlcBridge'
$script:installDirectory = Join-Path $script:rootDirectory 'App'
$script:executable = Join-Path $script:installDirectory 'jellyfin-vlc-bridge.exe'
$script:configFile = Join-Path $script:rootDirectory 'config.json'
$script:hadExistingConfig = Test-Path $script:configFile
$script:existingServerUrl = $null
$script:replaceExistingConfig = $false
if ($script:hadExistingConfig) {
    try {
        $existingConfig = Get-Content -LiteralPath $script:configFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $existingUri = $null
        if ([string]::IsNullOrWhiteSpace([string]$existingConfig.userId) -or
            -not [Uri]::TryCreate([string]$existingConfig.serverUrl, [UriKind]::Absolute, [ref]$existingUri) -or
            $existingUri.Scheme -notin @('http', 'https') -or
            -not [string]::IsNullOrEmpty($existingUri.UserInfo) -or
            -not [string]::IsNullOrEmpty($existingUri.Query) -or
            -not [string]::IsNullOrEmpty($existingUri.Fragment)) {
            throw 'Configuration existante invalide.'
        }
        $script:existingServerUrl = ([string]$existingConfig.serverUrl).TrimEnd('/')
    } catch {
        $script:hadExistingConfig = $false
        $script:existingServerUrl = $null
    }
}
$script:codeFile = Join-Path $env:TEMP ('jellyfin-vlc-code-' + [Guid]::NewGuid().ToString('N') + '.txt')
$script:setupProcess = $null
$script:installed = $false

function Show-SetupError([string]$message) {
    Show-JvbMessageDialog 'Jellyfin VLC Bridge' $message 'Error' $applicationIcon (T 'Close')
}

function Open-ChromeWebStore {
    try { Start-Process $script:chromeWebStoreUrl }
    catch { Show-SetupError (T 'BrowserOpenFailed' @($script:chromeWebStoreUrl)) }
}

function Copy-ApplicationFiles {
    $requiredFiles = @(
        'jellyfin-vlc-bridge.exe',
        'jellyfin-vlc-bridge-control.exe',
        'Centre-Controle.ps1',
        'Localization.ps1',
        'UiTheme.ps1',
        'DESINSTALLER-WINDOWS.cmd',
        'Desinstaller-JellyfinVlcBridge.ps1',
        'Desinstaller-GUI.ps1'
    )
    foreach ($file in $requiredFiles) {
        if (-not (Test-Path (Join-Path $script:packageDirectory $file))) { throw (T 'MissingFile' @($file)) }
    }
    New-Item -ItemType Directory -Path $script:installDirectory -Force | Out-Null
    foreach ($file in $requiredFiles) {
        Copy-Item (Join-Path $script:packageDirectory $file) (Join-Path $script:installDirectory $file) -Force
    }
    foreach ($obsoleteFile in @(
        'jellyfin-vlc-bridge.dll',
        'jellyfin-vlc-bridge.deps.json',
        'jellyfin-vlc-bridge.runtimeconfig.json',
        'JellyfinVlcBridge.Core.dll'
    )) {
        $obsoletePath = Join-Path $script:installDirectory $obsoleteFile
        if (Test-Path -LiteralPath $obsoletePath) {
            try { Remove-Item -LiteralPath $obsoletePath -Force -ErrorAction Stop } catch { }
        }
    }
}

function Register-WindowsApplication {
    $shell = New-Object -ComObject WScript.Shell
    $oldDesktopShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Jellyfin VLC Bridge - Diagnostic.lnk'
    if (Test-Path $oldDesktopShortcut) { Remove-Item -LiteralPath $oldDesktopShortcut -Force }

    $startMenuDirectory = Join-Path ([Environment]::GetFolderPath('Programs')) 'Jellyfin VLC Bridge'
    New-Item -ItemType Directory -Path $startMenuDirectory -Force | Out-Null
    $oldDiagnostic = Join-Path $startMenuDirectory 'Diagnostic Jellyfin VLC Bridge.lnk'
    if (Test-Path $oldDiagnostic) { Remove-Item -LiteralPath $oldDiagnostic -Force }
    $controlCenter = Join-Path $script:installDirectory 'jellyfin-vlc-bridge-control.exe'
    $application = $shell.CreateShortcut((Join-Path $startMenuDirectory 'Jellyfin VLC Bridge.lnk'))
    $application.TargetPath = $controlCenter
    $application.Arguments = ''
    $application.WorkingDirectory = $script:installDirectory
    $application.IconLocation = $controlCenter
    $application.Save()

    $uninstaller = Join-Path $script:installDirectory 'Desinstaller-GUI.ps1'
    $uninstallShortcut = $shell.CreateShortcut((Join-Path $startMenuDirectory 'Desinstaller Jellyfin VLC Bridge.lnk'))
    $uninstallShortcut.TargetPath = 'powershell.exe'
    $uninstallShortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$uninstaller`""
    $uninstallShortcut.WorkingDirectory = $env:TEMP
    $uninstallShortcut.IconLocation = $controlCenter
    $uninstallShortcut.Save()

    $registry = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\JellyfinVlcBridge'
    New-Item -Path $registry -Force | Out-Null
    Set-ItemProperty -Path $registry -Name DisplayName -Value 'Jellyfin VLC Bridge'
    Set-ItemProperty -Path $registry -Name DisplayVersion -Value $script:bridgeVersion
    Set-ItemProperty -Path $registry -Name Publisher -Value 'Jellyfin VLC Bridge Project'
    Set-ItemProperty -Path $registry -Name InstallLocation -Value $script:installDirectory
    Set-ItemProperty -Path $registry -Name DisplayIcon -Value $controlCenter
    Set-ItemProperty -Path $registry -Name UninstallString -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$uninstaller`""
    New-ItemProperty -Path $registry -Name NoModify -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $registry -Name NoRepair -Value 1 -PropertyType DWord -Force | Out-Null

    $runRegistry = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    New-Item -Path $runRegistry -Force | Out-Null
    Set-ItemProperty -Path $runRegistry -Name JellyfinVlcBridge `
        -Value ('"' + $controlCenter + '" --tray')
}

function Set-SetupStage([int]$stage) {
    for ($index = 0; $index -lt $stepDots.Count; $index++) {
        $active = $index -le $stage
        $stepDots[$index].BackColor = if ($active) {
            $script:JvbPalette.Accent
        } else {
            $script:JvbPalette.TextFaint
        }
        $stepLabels[$index].ForeColor = if ($active) {
            $script:JvbPalette.Text
        } else {
            $script:JvbPalette.TextMuted
        }
    }
}

function Complete-Installation {
    Register-WindowsApplication
    $controlCenter = Join-Path $script:installDirectory 'jellyfin-vlc-bridge-control.exe'
    try {
        Start-Process -FilePath $controlCenter -ArgumentList '--tray' -WindowStyle Hidden
    } catch { }
    $script:installed = $true
    Set-SetupStage 2
    $timer.Stop()
    $progress.Style = 'Continuous'
    $progress.Value = 100
    $statusLabel.Text = T 'InstallSuccess'
    $statusLabel.ForeColor = $script:JvbPalette.Success
    $codeTitle.Visible = $false
    $codeLabel.Visible = $false
    if ($script:replaceExistingConfig) {
        $instructions.Text = T 'NewConnectionSaved'
        $extensionButton.Visible = $false
    } elseif ($script:hadExistingConfig) {
        $instructions.Text = T 'UpdateCompletePreserved'
        $extensionButton.Visible = $false
    } else {
        $instructions.Text = T 'InstallExtensionNow'
        $extensionButton.Visible = $true
    }
    $serverBox.Enabled = $false
    $installButton.Text = T 'Close'
    $installButton.Enabled = $true
    if (-not $script:hadExistingConfig) { Open-ChromeWebStore }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Jellyfin VLC Bridge 1.17.0'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(760, 640)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.MinimumSize = New-Object Drawing.Size(776, 679)
$controlExecutable = Join-Path $script:packageDirectory 'jellyfin-vlc-bridge-control.exe'
$applicationIcon = Get-JvbApplicationIcon @(
    $controlExecutable,
    (Join-Path $script:packageDirectory 'jellyfin-vlc-bridge.exe'))
Enable-JvbModernWindow $form $applicationIcon

$header = New-Object System.Windows.Forms.Panel
$header.Location = New-Object System.Drawing.Point(0, 0)
$header.Size = New-Object System.Drawing.Size(760, 118)
$header.BackColor = $script:JvbPalette.Header
$form.Controls.Add($header)

$accentLine = New-Object Windows.Forms.Panel
$accentLine.Location = New-Object Drawing.Point(0, 114)
$accentLine.Size = New-Object Drawing.Size(760, 4)
$accentLine.BackColor = $script:JvbPalette.Accent
$header.Controls.Add($accentLine)

$logo = New-Object System.Windows.Forms.PictureBox
$logo.Location = New-Object System.Drawing.Point(28, 22)
$logo.Size = New-Object System.Drawing.Size(72, 72)
$logo.SizeMode = 'Zoom'
if ($applicationIcon) { $logo.Image = $applicationIcon.ToBitmap() }
$header.Controls.Add($logo)

$title = New-JvbLabel $header 'Jellyfin VLC Bridge' 120 22 510 40 23 `
    ([Drawing.FontStyle]::Bold)
$subtitle = New-JvbLabel $header (T 'SetupSubtitle') 122 65 560 26 10 `
    ([Drawing.FontStyle]::Regular) $script:JvbPalette.TextMuted

$versionPill = New-JvbCard $header 628 20 104 34 $script:JvbPalette.SurfaceAlt 17
$versionText = New-JvbLabel $versionPill '1.17.0' 8 7 88 22 9 `
    ([Drawing.FontStyle]::Bold)
$versionText.TextAlign = 'MiddleCenter'

$stepsCard = New-JvbCard $form 26 136 708 60 $script:JvbPalette.Surface 14
$stepDots = @()
$stepLabels = @()
$stepNames = @((T 'StepConnect'), (T 'StepAuthorize'), (T 'StepReady'))
foreach ($stepIndex in 0..2) {
    $stepX = 42 + ($stepIndex * 225)
    $stepDots += New-JvbDot $stepsCard $stepX 25 $script:JvbPalette.TextFaint
    $stepLabels += New-JvbLabel $stepsCard $stepNames[$stepIndex] ($stepX + 20) 17 180 28 `
        9 ([Drawing.FontStyle]::Bold) $script:JvbPalette.TextMuted
    if ($stepIndex -lt 2) {
        $connector = New-Object Windows.Forms.Panel
        $connector.Location = New-Object Drawing.Point(($stepX + 152), 29)
        $connector.Size = New-Object Drawing.Size(62, 2)
        $connector.BackColor = $script:JvbPalette.Border
        $stepsCard.Controls.Add($connector)
    }
}

$contentCard = New-JvbCard $form 26 212 708 282
$contentTitle = New-JvbLabel $contentCard (T 'ServerAddress') 22 18 470 28 12 `
    ([Drawing.FontStyle]::Bold)
$contentSubtitle = New-JvbLabel $contentCard (T 'ServerAddressHint') 22 50 640 38 9 `
    ([Drawing.FontStyle]::Regular) $script:JvbPalette.TextMuted

$serverBox = New-Object System.Windows.Forms.TextBox
$serverBox.Location = New-Object System.Drawing.Point(22, 92)
$serverBox.Size = New-Object System.Drawing.Size(664, 32)
$serverBox.Text = if ($script:existingServerUrl) { $script:existingServerUrl } else { 'http://192.168.1.25:8096' }
$serverBox.ReadOnly = $script:hadExistingConfig
Set-JvbInputStyle $serverBox
$contentCard.Controls.Add($serverBox)

$changeServerButton = New-Object System.Windows.Forms.Button
$changeServerButton.Text = T 'ChangeServer'
$changeServerButton.Location = New-Object System.Drawing.Point(478, 136)
$changeServerButton.Size = New-Object System.Drawing.Size(208, 36)
$changeServerButton.Visible = $script:hadExistingConfig
Set-JvbButtonStyle $changeServerButton 'Secondary'
$contentCard.Controls.Add($changeServerButton)

$codeTitle = New-JvbLabel $contentCard (T 'QuickConnectCode') 22 143 270 24 9 `
    ([Drawing.FontStyle]::Bold) $script:JvbPalette.TextMuted
$codeTitle.Visible = $false

$codeLabel = New-Object System.Windows.Forms.Label
$codeLabel.Text = '------'
$codeLabel.Font = New-Object System.Drawing.Font('Consolas', 27, [System.Drawing.FontStyle]::Bold)
$codeLabel.ForeColor = $script:JvbPalette.Accent
$codeLabel.Location = New-Object System.Drawing.Point(18, 168)
$codeLabel.Size = New-Object System.Drawing.Size(270, 46)
$codeLabel.Visible = $false
$contentCard.Controls.Add($codeLabel)

$instructions = New-Object System.Windows.Forms.Label
$instructions.Text = if ($script:hadExistingConfig) {
    T 'ExistingConnection'
} else {
    T 'PerUserInstall'
}
$instructions.Location = New-Object System.Drawing.Point(22, 220)
$instructions.Size = New-Object System.Drawing.Size(664, 48)
$instructions.Font = New-JvbFont 9.5
$instructions.ForeColor = $script:JvbPalette.TextMuted
$contentCard.Controls.Add($instructions)

$statusLabel = New-JvbLabel $form (T 'ReadyToInstall') 28 510 704 26 10 `
    ([Drawing.FontStyle]::Bold)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(28, 542)
$progress.Size = New-Object System.Drawing.Size(704, 12)
$progress.Style = 'Continuous'
$form.Controls.Add($progress)

$extensionButton = New-Object System.Windows.Forms.Button
$extensionButton.Text = T 'OpenChromeStore'
$extensionButton.Location = New-Object System.Drawing.Point(316, 578)
$extensionButton.Size = New-Object System.Drawing.Size(216, 42)
$extensionButton.Visible = $false
Set-JvbButtonStyle $extensionButton 'Success'
$form.Controls.Add($extensionButton)

$installButton = New-Object System.Windows.Forms.Button
$installButton.Text = T 'Install'
$installButton.Location = New-Object System.Drawing.Point(542, 578)
$installButton.Size = New-Object System.Drawing.Size(190, 42)
Set-JvbButtonStyle $installButton 'Primary'
$form.Controls.Add($installButton)

$privacyNote = New-JvbLabel $form (T 'InstallerPrivacyNote') 28 611 704 22 8 `
    ([Drawing.FontStyle]::Regular) $script:JvbPalette.TextFaint
$privacyNote.TextAlign = 'MiddleLeft'

$extensionButton.Visible = $false
Set-SetupStage 0

$extensionButton.Add_Click({ Open-ChromeWebStore })

$changeServerButton.Add_Click({
    $confirmed = Show-JvbConfirmDialog (T 'ChangeServer') (T 'ChangeServerQuestion') `
        $applicationIcon (T 'Continue') (T 'Cancel')
    if (-not $confirmed) { return }
    $script:replaceExistingConfig = $true
    $contentTitle.Text = T 'NewServerAddress'
    $serverBox.ReadOnly = $false
    $serverBox.SelectAll()
    $serverBox.Focus()
    $changeServerButton.Visible = $false
    $instructions.Text = T 'NewServerInstructions'
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 500
$timer.Add_Tick({
    try {
        if (-not $codeLabel.Visible -and (Test-Path $script:codeFile)) {
            Set-SetupStage 1
            $codeLabel.Text = (Get-Content -LiteralPath $script:codeFile -Raw).Trim()
            $codeTitle.Visible = $true
            $codeLabel.Visible = $true
            $instructions.Text = T 'QuickConnectInstructions'
            $statusLabel.Text = T 'WaitingAuthorization'
        }
        if ($script:setupProcess -and $script:setupProcess.HasExited) {
            if ($script:setupProcess.ExitCode -ne 0) { throw (T 'QuickConnectFailed') }
            Complete-Installation
        }
    } catch {
        $timer.Stop()
        $installButton.Enabled = $true
        $statusLabel.Text = T 'InstallationInterrupted'
        Show-SetupError $_.Exception.Message
    }
})

$installButton.Add_Click({
    if ($script:installed) { $form.Close(); return }
    try {
        $uri = $null
        if (-not [Uri]::TryCreate($serverBox.Text.Trim(), [UriKind]::Absolute, [ref]$uri) -or
            $uri.Scheme -notin @('http', 'https') -or
            -not [string]::IsNullOrEmpty($uri.UserInfo) -or
            -not [string]::IsNullOrEmpty($uri.Query) -or
            -not [string]::IsNullOrEmpty($uri.Fragment)) {
            throw (T 'InvalidJellyfinAddress')
        }
        $installButton.Enabled = $false
        $serverBox.Enabled = $false
        $progress.Style = 'Marquee'
        $statusLabel.Text = T 'CopyingFiles'
        [System.Windows.Forms.Application]::DoEvents()
        Copy-ApplicationFiles

        if ((Test-Path $script:configFile) -and -not $script:replaceExistingConfig) {
            $statusLabel.Text = T 'ConnectionPreserved'
            Start-Process -FilePath $script:executable -ArgumentList 'install-protocol' -WindowStyle Hidden -Wait
            Start-Process -FilePath $script:executable -ArgumentList 'install-native-host' -WindowStyle Hidden -Wait
            Complete-Installation
            return
        }

        if ($script:replaceExistingConfig -and (Test-Path $script:configFile)) {
            $statusLabel.Text = T 'RemovingOldConnection'
            $cleanupProcess = Start-Process -FilePath $script:executable `
                -ArgumentList 'uninstall-cleanup --purge' -WindowStyle Hidden -Wait -PassThru
            if ($cleanupProcess.ExitCode -ne 0) { throw (T 'ReplaceConnectionFailed') }
        }

        $statusLabel.Text = T 'RequestingCode'
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $script:executable
        $processInfo.Arguments = 'setup --server "' + $serverBox.Text.Trim() + '" --code-path "' + $script:codeFile + '"'
        $processInfo.WorkingDirectory = $script:installDirectory
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        $script:setupProcess = [System.Diagnostics.Process]::Start($processInfo)
        $timer.Start()
    } catch {
        $progress.Style = 'Continuous'
        $installButton.Enabled = $true
        $serverBox.Enabled = $true
        $statusLabel.Text = T 'InstallationInterrupted'
        Show-SetupError $_.Exception.Message
    }
})

$form.Add_FormClosing({
    $timer.Stop()
    if ($script:setupProcess -and -not $script:setupProcess.HasExited) {
        try { $script:setupProcess.Kill() } catch { }
    }
    if (Test-Path $script:codeFile) { Remove-Item -LiteralPath $script:codeFile -Force -ErrorAction SilentlyContinue }
})

[void]$form.ShowDialog()
