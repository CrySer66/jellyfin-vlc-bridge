$ErrorActionPreference = 'Stop'
$script:installerArguments = @($args)
$script:silentInstall = $script:installerArguments -contains '-Silent'

function Get-InternalArgumentValue([string]$name) {
    $index = [Array]::IndexOf($script:installerArguments, $name)
    if ($index -lt 0) { return $null }
    if ($index + 1 -ge $script:installerArguments.Count) { throw "Valeur manquante pour $name." }
    return [string]$script:installerArguments[$index + 1]
}

$script:isolatedTestRoot = Get-InternalArgumentValue '-TestRoot'
$script:isolatedTestMode = -not [string]::IsNullOrWhiteSpace($script:isolatedTestRoot)
$script:isolatedTestRequested = $env:JELLYFIN_VLC_BRIDGE_ISOLATED_TEST -eq '1'
if ($script:isolatedTestMode -ne $script:isolatedTestRequested) {
    throw 'Le mode de test isolé exige à la fois son indicateur et son dossier dédié.'
}
if ($script:isolatedTestMode -and -not $script:silentInstall) {
    throw 'Le dossier de test isolé est réservé aux validations silencieuses du paquet.'
}
$script:isolatedTestMarker = if ($script:isolatedTestMode) {
    Join-Path ([IO.Path]::GetFullPath($script:isolatedTestRoot)) '.jvb-isolated-test'
} else { $null }
if ($script:isolatedTestMode -and -not (Test-Path -LiteralPath $script:isolatedTestMarker -PathType Leaf)) {
    throw 'Le dossier de test isolé ne contient pas son marqueur de sécurité.'
}
$script:skipWindowsRegistration = $script:isolatedTestMode

$script:bridgeVersion = '1.18.1'
$script:chromeWebStoreId = 'hkjbodgdbjhignhlbecchiigcfigpidp'
$script:chromeWebStoreUrl = 'https://chromewebstore.google.com/detail/' + $script:chromeWebStoreId
$script:packageDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $script:packageDirectory 'Localization.ps1')
$script:rootDirectory = if ($script:isolatedTestMode) {
    [IO.Path]::GetFullPath($script:isolatedTestRoot)
} else {
    Join-Path $env:LOCALAPPDATA 'JellyfinVlcBridge'
}
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
$script:maintenanceMutex = $null
$script:applicationTransaction = $null
$script:installerLog = Join-Path $script:rootDirectory 'Logs\installer.log'

function Write-InstallerLog([string]$level, [string]$message) {
    try {
        $logDirectory = Split-Path -Parent $script:installerLog
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        $line = '{0:o} [{1}] {2}' -f [DateTimeOffset]::Now, $level.ToUpperInvariant(), $message
        Add-Content -LiteralPath $script:installerLog -Value $line -Encoding UTF8
    } catch { }
}

function Show-SetupError([string]$message) {
    Show-JvbMessageDialog 'Jellyfin VLC Bridge' $message 'Error' $applicationIcon (T 'Close')
}

function Open-ChromeWebStore {
    try { Start-Process $script:chromeWebStoreUrl }
    catch { Show-SetupError (T 'BrowserOpenFailed' @($script:chromeWebStoreUrl)) }
}

function Enter-MaintenanceLock {
    if ($script:maintenanceMutex) { return }
    $mutex = New-Object System.Threading.Mutex($false, 'Local\CrySer66.JellyfinVlcBridge.Maintenance')
    $acquired = $false
    try {
        try { $acquired = $mutex.WaitOne(0, $false) }
        catch [System.Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) { throw 'Une installation ou désinstallation de Jellyfin VLC Bridge est déjà en cours.' }
        $script:maintenanceMutex = $mutex
        Write-InstallerLog 'INFO' 'Verrou de maintenance acquis.'
        Remove-StaleApplicationTransactions
    } catch {
        if (-not $acquired) { $mutex.Dispose() }
        throw
    }
}

function Exit-MaintenanceLock {
    if (-not $script:maintenanceMutex) { return }
    try { $script:maintenanceMutex.ReleaseMutex() } catch { }
    $script:maintenanceMutex.Dispose()
    $script:maintenanceMutex = $null
    Write-InstallerLog 'INFO' 'Verrou de maintenance libéré.'
}

function Get-RequiredApplicationFiles {
    return @(
        'jellyfin-vlc-bridge.exe',
        'jellyfin-vlc-bridge-control.exe',
        'Centre-Controle.ps1',
        'Localization.ps1',
        'UiTheme.ps1',
        'DESINSTALLER-WINDOWS.cmd',
        'Desinstaller-GUI.ps1'
    )
}

function Remove-MaintenanceDirectory([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return }
    $root = [IO.Path]::GetFullPath($script:rootDirectory).TrimEnd('\') + '\'
    $resolved = [IO.Path]::GetFullPath($path)
    if (-not $resolved.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Parent $resolved) -ne $root.TrimEnd('\') -or
        (Split-Path -Leaf $resolved) -notlike 'App.*-*') {
        throw "Chemin de maintenance inattendu : $resolved"
    }
    for ($attempt = 1; $attempt -le 10 -and (Test-Path -LiteralPath $resolved); $attempt++) {
        try { Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop }
        catch {
            if ($attempt -eq 10) { throw }
            Start-Sleep -Milliseconds 250
        }
    }
    if (Test-Path -LiteralPath $resolved) { throw "Impossible de supprimer $resolved." }
}

function Remove-StaleApplicationTransactions {
    if (-not (Test-Path -LiteralPath $script:rootDirectory -PathType Container)) { return }
    foreach ($directory in Get-ChildItem -LiteralPath $script:rootDirectory -Directory -Force -ErrorAction SilentlyContinue) {
        if ($directory.Name -notmatch '^App\.(?:backup|staging|failed)-[0-9a-f]{32}$') { continue }
        try {
            Remove-MaintenanceDirectory $directory.FullName
            Write-InstallerLog 'INFO' "Ancienne transaction supprimée : $($directory.Name)"
        } catch {
            Write-InstallerLog 'WARN' ("Ancienne transaction conservée : " + $_.Exception.Message)
        }
    }
}

function Stop-InstalledBridgeProcesses {
    if (-not (Test-Path -LiteralPath $script:installDirectory)) { return }
    $installPrefix = [IO.Path]::GetFullPath($script:installDirectory).TrimEnd('\') + '\'
    $targets = @()
    Get-Process -Name 'jellyfin-vlc-bridge', 'jellyfin-vlc-bridge-control' -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $processPath = [IO.Path]::GetFullPath($_.Path)
            if ($processPath.StartsWith($installPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                $targets += $_
            }
        } catch { }
    }
    foreach ($process in $targets) {
        try {
            if ($process.MainWindowHandle -ne [IntPtr]::Zero) { [void]$process.CloseMainWindow() }
            if (-not $process.WaitForExit(1500)) {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
                if (-not $process.WaitForExit(5000)) {
                    throw "Le processus $($process.Id) ne s'est pas arrêté à temps."
                }
            }
        } catch {
            if (-not $process.HasExited) { throw }
        } finally {
            $process.Dispose()
        }
    }
    $remaining = @(Get-Process -Name 'jellyfin-vlc-bridge', 'jellyfin-vlc-bridge-control' -ErrorAction SilentlyContinue | Where-Object {
        try { [IO.Path]::GetFullPath($_.Path).StartsWith($installPrefix, [StringComparison]::OrdinalIgnoreCase) }
        catch { $false }
    })
    if ($remaining.Count -gt 0) { throw 'Un processus Jellyfin VLC Bridge installé est encore actif.' }
}

function Copy-ApplicationFiles {
    $requiredFiles = @(Get-RequiredApplicationFiles)
    foreach ($file in $requiredFiles) {
        if (-not (Test-Path (Join-Path $script:packageDirectory $file))) { throw (T 'MissingFile' @($file)) }
    }

    New-Item -ItemType Directory -Path $script:rootDirectory -Force | Out-Null
    $transactionId = [Guid]::NewGuid().ToString('N')
    $stagingDirectory = Join-Path $script:rootDirectory ('App.staging-' + $transactionId)
    $backupDirectory = Join-Path $script:rootDirectory ('App.backup-' + $transactionId)
    $previousApplication = Test-Path -LiteralPath $script:installDirectory
    New-Item -ItemType Directory -Path $stagingDirectory -Force | Out-Null
    try {
        foreach ($file in $requiredFiles) {
            Copy-Item -LiteralPath (Join-Path $script:packageDirectory $file) `
                -Destination (Join-Path $stagingDirectory $file) -Force
        }
        foreach ($file in $requiredFiles) {
            if (-not (Test-Path -LiteralPath (Join-Path $stagingDirectory $file))) {
                throw "Le fichier $file manque dans le dossier préparé."
            }
        }

        Stop-InstalledBridgeProcesses
        if ($previousApplication) {
            Move-Item -LiteralPath $script:installDirectory -Destination $backupDirectory -ErrorAction Stop
        }
        Move-Item -LiteralPath $stagingDirectory -Destination $script:installDirectory -ErrorAction Stop
        $script:applicationTransaction = [PSCustomObject]@{
            BackupDirectory = $backupDirectory
            StagingDirectory = $stagingDirectory
            PreviousApplication = $previousApplication
        }
        Write-InstallerLog 'INFO' "Application préparée et remplacée (ancienne version=$previousApplication)."
    } catch {
        $failure = $_.Exception
        try {
            if (-not (Test-Path -LiteralPath $script:installDirectory) -and
                (Test-Path -LiteralPath $backupDirectory)) {
                Move-Item -LiteralPath $backupDirectory -Destination $script:installDirectory -ErrorAction Stop
            }
            Remove-MaintenanceDirectory $stagingDirectory
        } catch {
            Write-InstallerLog 'ERROR' ("Échec du retour arrière initial : " + $_.Exception.Message)
        }
        throw $failure
    }
}

function Complete-ApplicationTransaction {
    if (-not $script:applicationTransaction) { return }
    try { Remove-MaintenanceDirectory $script:applicationTransaction.BackupDirectory }
    catch { Write-InstallerLog 'WARN' ("Ancienne version à nettoyer ultérieurement : " + $_.Exception.Message) }
    try { Remove-MaintenanceDirectory $script:applicationTransaction.StagingDirectory }
    catch { Write-InstallerLog 'WARN' ("Dossier préparatoire à nettoyer ultérieurement : " + $_.Exception.Message) }
    $script:applicationTransaction = $null
    Write-InstallerLog 'INFO' "Transaction d'installation validée."
}

function Undo-ApplicationTransaction {
    if (-not $script:applicationTransaction) { return }
    $transaction = $script:applicationTransaction
    Stop-InstalledBridgeProcesses
    if (Test-Path -LiteralPath $script:installDirectory) {
        $failedDirectory = Join-Path $script:rootDirectory ('App.failed-' + [Guid]::NewGuid().ToString('N'))
        Move-Item -LiteralPath $script:installDirectory -Destination $failedDirectory -ErrorAction Stop
        Remove-MaintenanceDirectory $failedDirectory
    }
    if ($transaction.PreviousApplication -and (Test-Path -LiteralPath $transaction.BackupDirectory)) {
        Move-Item -LiteralPath $transaction.BackupDirectory -Destination $script:installDirectory -ErrorAction Stop
    }
    if (-not $transaction.PreviousApplication) { Remove-NewApplicationRegistration }
    Remove-MaintenanceDirectory $transaction.StagingDirectory
    $script:applicationTransaction = $null
    Write-InstallerLog 'WARN' "Transaction d'installation annulée et ancienne application restaurée."
}

function Register-WindowsApplication {
    if ($script:skipWindowsRegistration) {
        Write-InstallerLog 'INFO' 'Enregistrement Windows ignoré pour le test isolé.'
        return
    }
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
    Set-ItemProperty -Path $registry -Name QuietUninstallString -Value "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$uninstaller`" -Silent"
    New-ItemProperty -Path $registry -Name NoModify -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $registry -Name NoRepair -Value 1 -PropertyType DWord -Force | Out-Null

    $runRegistry = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    New-Item -Path $runRegistry -Force | Out-Null
    Set-ItemProperty -Path $runRegistry -Name JellyfinVlcBridge `
        -Value ('"' + $controlCenter + '" --tray')
}

function Remove-NewApplicationRegistration {
    if ($script:skipWindowsRegistration) { return }
    foreach ($registryPath in @(
        'HKCU:\Software\Classes\jellyfin-vlc',
        'HKCU:\Software\Google\Chrome\NativeMessagingHosts\local.jellyfin_vlc_bridge',
        'HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\local.jellyfin_vlc_bridge',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\JellyfinVlcBridge'
    )) {
        Remove-Item -LiteralPath $registryPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    $runRegistry = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    Remove-ItemProperty -LiteralPath $runRegistry -Name JellyfinVlcBridge -Force -ErrorAction SilentlyContinue
    $startMenuDirectory = Join-Path ([Environment]::GetFolderPath('Programs')) 'Jellyfin VLC Bridge'
    if (Test-Path -LiteralPath $startMenuDirectory) {
        Remove-Item -LiteralPath $startMenuDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
    $nativeManifest = Join-Path $script:rootDirectory 'native-messaging-host.json'
    Remove-Item -LiteralPath $nativeManifest -Force -ErrorAction SilentlyContinue
}

function Invoke-BridgeInstallerCommand([string]$arguments) {
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $script:executable
    $processInfo.Arguments = $arguments
    $processInfo.WorkingDirectory = $script:installDirectory
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    try {
        Write-InstallerLog 'INFO' "Commande Bridge : $arguments"
        if (-not $process.Start()) { throw "Impossible de lancer $arguments." }
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            try { $process.Kill() } catch { }
            [void]$process.WaitForExit(5000)
            throw "La commande $arguments a dépassé le délai de 30 secondes."
        }
        $output = $outputTask.GetAwaiter().GetResult().Trim()
        $errorOutput = $errorTask.GetAwaiter().GetResult().Trim()
        if ($process.ExitCode -ne 0) {
            $detail = if ([string]::IsNullOrWhiteSpace($errorOutput)) {
                if ([string]::IsNullOrWhiteSpace($output)) { "code $($process.ExitCode)" } else { $output }
            } else {
                $errorOutput
            }
            throw "La commande $arguments a échoué : $detail"
        }
    } finally {
        $process.Dispose()
    }
}

function Install-ApplicationIntegrations {
    Invoke-BridgeInstallerCommand 'install-protocol'
    Invoke-BridgeInstallerCommand 'install-native-host'
    Register-WindowsApplication
}

if ($script:silentInstall) {
    try {
        Write-InstallerLog 'INFO' "Installation silencieuse $($script:bridgeVersion) démarrée."
        Enter-MaintenanceLock
        Copy-ApplicationFiles
        Install-ApplicationIntegrations
        Complete-ApplicationTransaction
        Write-InstallerLog 'INFO' 'Installation silencieuse terminée avec succès.'
        exit 0
    } catch {
        $installFailure = $_.Exception
        Write-InstallerLog 'ERROR' $installFailure.ToString()
        try { Undo-ApplicationTransaction }
        catch {
            Write-InstallerLog 'ERROR' ("Le retour arrière a également échoué : " + $_.Exception.ToString())
        }
        [Console]::Error.WriteLine($installFailure.Message)
        exit 1
    } finally {
        Exit-MaintenanceLock
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $script:packageDirectory 'UiTheme.ps1')

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
    Complete-ApplicationTransaction
    Exit-MaintenanceLock
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
$form.Text = 'Jellyfin VLC Bridge 1.18.1'
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
$versionText = New-JvbLabel $versionPill '1.18.1' 8 7 88 22 9 `
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
        $timerFailure = $_.Exception
        $timer.Stop()
        Write-InstallerLog 'ERROR' $timerFailure.ToString()
        try { Undo-ApplicationTransaction } catch { Write-InstallerLog 'ERROR' $_.Exception.ToString() }
        Exit-MaintenanceLock
        $installButton.Enabled = $true
        $statusLabel.Text = T 'InstallationInterrupted'
        Show-SetupError $timerFailure.Message
    }
})

$installButton.Add_Click({
    if ($script:installed) { $form.Close(); return }
    try {
        Enter-MaintenanceLock
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
            Invoke-BridgeInstallerCommand 'install-protocol'
            Invoke-BridgeInstallerCommand 'install-native-host'
            Complete-Installation
            return
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
        $buttonFailure = $_.Exception
        Write-InstallerLog 'ERROR' $buttonFailure.ToString()
        try { Undo-ApplicationTransaction } catch { Write-InstallerLog 'ERROR' $_.Exception.ToString() }
        Exit-MaintenanceLock
        $progress.Style = 'Continuous'
        $installButton.Enabled = $true
        $serverBox.Enabled = $true
        $statusLabel.Text = T 'InstallationInterrupted'
        Show-SetupError $buttonFailure.Message
    }
})

$form.Add_FormClosing({
    $timer.Stop()
    if (-not $script:installed -and $script:setupProcess -and
        $script:setupProcess.HasExited -and $script:setupProcess.ExitCode -eq 0) {
        Complete-Installation
    }
    if ($script:setupProcess -and -not $script:setupProcess.HasExited) {
        try {
            $script:setupProcess.Kill()
            [void]$script:setupProcess.WaitForExit(5000)
        } catch { }
    }
    if (-not $script:installed) {
        try { Undo-ApplicationTransaction } catch { Write-InstallerLog 'ERROR' $_.Exception.ToString() }
    }
    Exit-MaintenanceLock
    if (Test-Path $script:codeFile) { Remove-Item -LiteralPath $script:codeFile -Force -ErrorAction SilentlyContinue }
})

[void]$form.ShowDialog()
