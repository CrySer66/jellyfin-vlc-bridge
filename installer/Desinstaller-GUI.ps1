param(
    [switch]$TemporaryRun,
    [switch]$Silent,
    [switch]$Purge,
    [switch]$IsolatedTest
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$localizationFile = Join-Path $scriptDirectory 'Localization.ps1'
$themeFile = Join-Path $scriptDirectory 'UiTheme.ps1'
if (Test-Path -LiteralPath $localizationFile) { . $localizationFile }
$uninstallerLog = Join-Path $env:TEMP 'JellyfinVlcBridge-uninstall.log'

function Write-UninstallerLog([string]$level, [string]$message) {
    try {
        $line = '{0:o} [{1}] {2}' -f [DateTimeOffset]::Now, $level.ToUpperInvariant(), $message
        Add-Content -LiteralPath $uninstallerLog -Value $line -Encoding UTF8
    } catch { }
}

$isolatedTestRequested = $env:JELLYFIN_VLC_BRIDGE_ISOLATED_TEST -eq '1'
if ([bool]$IsolatedTest -ne $isolatedTestRequested) {
    throw 'Le mode de test isolé exige à la fois son indicateur et son environnement dédié.'
}
if ($IsolatedTest -and -not $Silent) {
    throw 'Le mode de test isolé est réservé aux validations silencieuses du paquet.'
}

# Le script installé se trouve dans le dossier qu'il doit supprimer. Une copie
# temporaire évite que PowerShell ou son dossier de travail garde App verrouillé.
if (-not $TemporaryRun) {
    $temporaryDirectory = Join-Path $env:TEMP ('JellyfinVlcBridgeUninstall-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporaryDirectory -Force | Out-Null
    $temporaryScript = Join-Path $temporaryDirectory 'Desinstaller-GUI.ps1'
    Copy-Item -LiteralPath $MyInvocation.MyCommand.Path -Destination $temporaryScript -Force
    Copy-Item -LiteralPath $localizationFile -Destination (Join-Path $temporaryDirectory 'Localization.ps1') -Force
    Copy-Item -LiteralPath $themeFile -Destination (Join-Path $temporaryDirectory 'UiTheme.ps1') -Force

    # Le processus parent ne doit pas conserver App comme dossier de travail
    # pendant que la copie temporaire le supprime.
    Set-Location -LiteralPath $env:TEMP
    $temporaryArguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$temporaryScript`" -TemporaryRun"
    if ($Silent) { $temporaryArguments += ' -Silent' }
    if ($Purge) { $temporaryArguments += ' -Purge' }
    if ($IsolatedTest) { $temporaryArguments += ' -IsolatedTest' }
    $temporaryProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
    $temporaryProcessInfo.FileName = 'powershell.exe'
    $temporaryProcessInfo.Arguments = $temporaryArguments
    $temporaryProcessInfo.WorkingDirectory = $temporaryDirectory
    $temporaryProcessInfo.UseShellExecute = $false
    $temporaryProcessInfo.CreateNoWindow = $true
    $temporaryProcess = [System.Diagnostics.Process]::Start($temporaryProcessInfo)
    if ($null -eq $temporaryProcess) { throw (T 'CleanupStartFailed') }
    if ($Silent) {
        if (-not $temporaryProcess.WaitForExit(90000)) {
            try { $temporaryProcess.Kill() } catch { }
            [void]$temporaryProcess.WaitForExit(5000)
            Write-UninstallerLog 'ERROR' 'La désinstallation a dépassé le délai de 90 secondes.'
            $temporaryProcess.Dispose()
            exit 1
        }
        $temporaryExitCode = $temporaryProcess.ExitCode
        $temporaryProcess.Dispose()
        exit $temporaryExitCode
    }
    $temporaryProcess.Dispose()
    exit 0
}

# La copie est déjà chargée en mémoire ; elle peut se retirer immédiatement.
$currentTemporaryScript = $MyInvocation.MyCommand.Path
$currentTemporaryDirectory = Split-Path -Parent $currentTemporaryScript
$isTemporaryDirectory = (Split-Path -Leaf $currentTemporaryDirectory) -like 'JellyfinVlcBridgeUninstall-*'
Set-Location -LiteralPath $env:TEMP
Remove-Item -LiteralPath $currentTemporaryScript -Force -ErrorAction SilentlyContinue

function Remove-TemporaryUninstallFiles {
    if ($isTemporaryDirectory -and (Test-Path -LiteralPath $currentTemporaryDirectory)) {
        Set-Location -LiteralPath $env:TEMP
        Remove-Item -LiteralPath $currentTemporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$rootDirectory = Join-Path $env:LOCALAPPDATA 'JellyfinVlcBridge'
$isolatedTestMarker = Join-Path $rootDirectory '.jvb-isolated-test'
if ($IsolatedTest -and -not (Test-Path -LiteralPath $isolatedTestMarker -PathType Leaf)) {
    throw 'Le dossier de test isolé ne contient pas son marqueur de sécurité.'
}
$installDirectory = Join-Path $rootDirectory 'App'
$executable = Join-Path $installDirectory 'jellyfin-vlc-bridge.exe'
$controlExecutable = Join-Path $installDirectory 'jellyfin-vlc-bridge-control.exe'
$applicationIcon = $null
$maintenanceMutex = $null
if (-not $Silent) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.Application]::EnableVisualStyles()
    . (Join-Path $scriptDirectory 'UiTheme.ps1')
    $applicationIcon = Get-JvbApplicationIcon @($controlExecutable, $executable)
}

function Enter-MaintenanceLock {
    $mutex = New-Object System.Threading.Mutex($false, 'Local\CrySer66.JellyfinVlcBridge.Maintenance')
    $acquired = $false
    try {
        try { $acquired = $mutex.WaitOne(0, $false) }
        catch [System.Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) { throw 'Une installation ou désinstallation de Jellyfin VLC Bridge est déjà en cours.' }
        $script:maintenanceMutex = $mutex
        Write-UninstallerLog 'INFO' 'Verrou de maintenance acquis.'
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
}

function Remove-StaleApplicationTransactions {
    if (-not (Test-Path -LiteralPath $rootDirectory -PathType Container)) { return }
    $expectedRoot = [IO.Path]::GetFullPath($rootDirectory).TrimEnd('\') + '\'
    foreach ($directory in Get-ChildItem -LiteralPath $rootDirectory -Directory -Force -ErrorAction SilentlyContinue) {
        if ($directory.Name -notmatch '^App\.(?:backup|staging|failed)-[0-9a-f]{32}$') { continue }
        $resolved = [IO.Path]::GetFullPath($directory.FullName)
        if (-not $resolved.StartsWith($expectedRoot, [StringComparison]::OrdinalIgnoreCase) -or
            (Split-Path -Parent $resolved) -ne $expectedRoot.TrimEnd('\')) {
            throw "Chemin de transaction inattendu : $resolved"
        }
        for ($attempt = 1; $attempt -le 10 -and (Test-Path -LiteralPath $resolved); $attempt++) {
            try { Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop }
            catch {
                if ($attempt -eq 10) { throw }
                Start-Sleep -Milliseconds 250
            }
        }
    }
}

function Show-UninstallChoice {
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = T 'UninstallTitle'
    $dialog.StartPosition = 'CenterScreen'
    $dialog.ClientSize = New-Object Drawing.Size(640, 470)
    $dialog.FormBorderStyle = 'FixedSingle'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    Enable-JvbModernWindow $dialog $applicationIcon

    $header = New-Object Windows.Forms.Panel
    $header.Location = New-Object Drawing.Point(0, 0)
    $header.Size = New-Object Drawing.Size(640, 104)
    $header.BackColor = $script:JvbPalette.Header
    $dialog.Controls.Add($header)

    $accent = New-Object Windows.Forms.Panel
    $accent.Location = New-Object Drawing.Point(0, 100)
    $accent.Size = New-Object Drawing.Size(640, 4)
    $accent.BackColor = $script:JvbPalette.Danger
    $header.Controls.Add($accent)

    $logo = New-Object Windows.Forms.PictureBox
    $logo.Location = New-Object Drawing.Point(26, 19)
    $logo.Size = New-Object Drawing.Size(64, 64)
    $logo.SizeMode = 'Zoom'
    if ($applicationIcon) { $logo.Image = $applicationIcon.ToBitmap() }
    $header.Controls.Add($logo)

    [void](New-JvbLabel $header (T 'UninstallTitle') 108 22 500 36 20 `
        ([Drawing.FontStyle]::Bold))
    [void](New-JvbLabel $header 'Jellyfin VLC Bridge' 110 61 460 24 9.5 `
        ([Drawing.FontStyle]::Regular) $script:JvbPalette.TextMuted)

    [void](New-JvbLabel $dialog (T 'UninstallQuestion') 28 126 584 58 11 `
        ([Drawing.FontStyle]::Bold))

    $keepCard = New-JvbCard $dialog 28 198 584 88 $script:JvbPalette.Surface 14
    [void](New-JvbDot $keepCard 22 20 $script:JvbPalette.Success)
    [void](New-JvbLabel $keepCard (T 'UninstallKeep') 46 12 510 28 11 `
        ([Drawing.FontStyle]::Bold))
    [void](New-JvbLabel $keepCard (T 'UninstallKeepDescription') 46 42 510 34 9 `
        ([Drawing.FontStyle]::Regular) $script:JvbPalette.TextMuted)
    $keepCard.Cursor = [Windows.Forms.Cursors]::Hand

    $purgeCard = New-JvbCard $dialog 28 300 584 88 $script:JvbPalette.Surface 14
    [void](New-JvbDot $purgeCard 22 20 $script:JvbPalette.Danger)
    [void](New-JvbLabel $purgeCard (T 'UninstallRemoveAll') 46 12 510 28 11 `
        ([Drawing.FontStyle]::Bold))
    [void](New-JvbLabel $purgeCard (T 'UninstallRemoveAllDescription') 46 42 510 34 9 `
        ([Drawing.FontStyle]::Regular) $script:JvbPalette.TextMuted)
    $purgeCard.Cursor = [Windows.Forms.Cursors]::Hand

    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = T 'Cancel'
    $cancel.Location = New-Object Drawing.Point(452, 410)
    $cancel.Size = New-Object Drawing.Size(160, 40)
    Set-JvbButtonStyle $cancel 'Secondary'
    $dialog.Controls.Add($cancel)

    $script:uninstallChoice = 'cancel'
    $selectKeep = {
        $script:uninstallChoice = 'keep'
        $dialog.Close()
    }
    $selectPurge = {
        $script:uninstallChoice = 'purge'
        $dialog.Close()
    }
    $keepCard.Add_Click($selectKeep)
    foreach ($child in $keepCard.Controls) { $child.Add_Click($selectKeep) }
    $purgeCard.Add_Click($selectPurge)
    foreach ($child in $purgeCard.Controls) { $child.Add_Click($selectPurge) }
    $cancel.Add_Click({ $dialog.Close() })
    [void]$dialog.ShowDialog()
    return $script:uninstallChoice
}

function Show-UninstallResult(
    [string]$title,
    [string]$message,
    [bool]$success
) {
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = $title
    $dialog.StartPosition = 'CenterScreen'
    $dialog.ClientSize = New-Object Drawing.Size(560, 320)
    $dialog.FormBorderStyle = 'FixedSingle'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    Enable-JvbModernWindow $dialog $applicationIcon

    $statusColor = if ($success) { $script:JvbPalette.Success } else { $script:JvbPalette.Danger }
    $card = New-JvbCard $dialog 28 28 504 206
    [void](New-JvbDot $card 24 26 $statusColor)
    [void](New-JvbLabel $card $title 50 15 420 34 15 ([Drawing.FontStyle]::Bold))
    [void](New-JvbLabel $card $message 24 68 456 112 10 `
        ([Drawing.FontStyle]::Regular) $script:JvbPalette.TextMuted)

    $closeButton = New-Object Windows.Forms.Button
    $closeButton.Text = T 'Close'
    $closeButton.Location = New-Object Drawing.Point(372, 254)
    $closeButton.Size = New-Object Drawing.Size(160, 42)
    Set-JvbButtonStyle $closeButton $(if ($success) { 'Primary' } else { 'Danger' })
    $closeButton.Add_Click({ $dialog.Close() })
    $dialog.Controls.Add($closeButton)
    [void]$dialog.ShowDialog()
}

$choice = if ($Silent) {
    if ($Purge) { 'purge' } else { 'keep' }
} else {
    Show-UninstallChoice
}
if ($choice -eq 'cancel') { exit 0 }
$purge = $choice -eq 'purge'

function Invoke-BridgeCleanup([string]$path, [bool]$removeSettings) {
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $path
    $processInfo.Arguments = if ($removeSettings) { 'uninstall-cleanup --purge' } else { 'uninstall-cleanup' }
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    try {
        if (-not $process.Start()) { throw (T 'CleanupStartFailed') }
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            try { $process.Kill() } catch { }
            [void]$process.WaitForExit(5000)
            throw 'Le nettoyage du Bridge a dépassé le délai de 30 secondes.'
        }
        $output = $outputTask.GetAwaiter().GetResult().Trim()
        $errorOutput = $errorTask.GetAwaiter().GetResult().Trim()
        return [PSCustomObject]@{
            ExitCode = $process.ExitCode
            Output = $output
            Error = $errorOutput
        }
    } finally {
        $process.Dispose()
    }
}

function Test-BridgeRunRegistration {
    $runRegistry = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if (-not (Test-Path -LiteralPath $runRegistry)) { return $false }
    $runValues = Get-ItemProperty -LiteralPath $runRegistry -ErrorAction Stop
    return $null -ne $runValues.PSObject.Properties['JellyfinVlcBridge']
}

function Remove-BridgeRegistrationFallback {
    if ($IsolatedTest) { return }
    foreach ($registryPath in @(
        'HKCU:\Software\Classes\jellyfin-vlc',
        'HKCU:\Software\Google\Chrome\NativeMessagingHosts\local.jellyfin_vlc_bridge',
        'HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\local.jellyfin_vlc_bridge',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\JellyfinVlcBridge'
    )) {
        if (Test-Path -LiteralPath $registryPath) {
            Remove-Item -LiteralPath $registryPath -Recurse -Force -ErrorAction Stop
        }
    }
    $runRegistry = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if (Test-BridgeRunRegistration) {
        Remove-ItemProperty -LiteralPath $runRegistry -Name JellyfinVlcBridge -Force -ErrorAction Stop
    }
    foreach ($path in @(
        (Join-Path $rootDirectory 'native-messaging-host.json'),
        (Join-Path $rootDirectory 'extension-heartbeat.json'),
        (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Jellyfin VLC Bridge - Diagnostic.lnk'),
        (Join-Path ([Environment]::GetFolderPath('Programs')) 'Jellyfin VLC Bridge')
    )) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
        }
    }
}

function Assert-BridgeRegistrationRemoved {
    if ($IsolatedTest) { return }
    foreach ($registryPath in @(
        'HKCU:\Software\Classes\jellyfin-vlc',
        'HKCU:\Software\Google\Chrome\NativeMessagingHosts\local.jellyfin_vlc_bridge',
        'HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\local.jellyfin_vlc_bridge',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\JellyfinVlcBridge'
    )) {
        if (Test-Path -LiteralPath $registryPath) { throw "Enregistrement Windows encore présent : $registryPath" }
    }
    if (Test-BridgeRunRegistration) { throw 'Le démarrage automatique du Bridge est encore enregistré.' }
}

try {
    Enter-MaintenanceLock
    Write-UninstallerLog 'INFO' "Désinstallation démarrée (silencieuse=$Silent, purge=$purge)."
    $cleanupWarnings = New-Object System.Collections.Generic.List[string]
    if (Test-Path $executable) {
        try {
            $cleanupResult = Invoke-BridgeCleanup $executable $purge
            if ($cleanupResult.ExitCode -ne 0) {
                $detail = if ([string]::IsNullOrWhiteSpace($cleanupResult.Error)) {
                    "code $($cleanupResult.ExitCode)"
                } else {
                    $cleanupResult.Error
                }
                $cleanupWarnings.Add((T 'CleanupIncomplete' @($detail)))
            }
        } catch {
            $cleanupWarnings.Add((T 'CleanupIncomplete' @($_.Exception.Message)))
        }
    } elseif ($purge) {
        $cleanupWarnings.Add((T 'CleanupIncomplete' @("exécutable absent ; les secrets Windows n’ont pas pu être vérifiés")))
    }
    try {
        Remove-BridgeRegistrationFallback
        Assert-BridgeRegistrationRemoved
    } catch {
        $cleanupWarnings.Add((T 'CleanupIncomplete' @($_.Exception.Message)))
    }

    $expected = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'JellyfinVlcBridge\App'))
    $actual = [IO.Path]::GetFullPath($installDirectory)
    if ($actual -ne $expected) { throw (T 'UnsafeUninstallPath') }

    if (Test-Path $actual) {
        Get-Process -Name 'jellyfin-vlc-bridge', 'jellyfin-vlc-bridge-control' -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $processPath = [IO.Path]::GetFullPath($_.Path)
                if ($processPath.StartsWith($actual + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
                    Stop-Process -Id $_.Id -Force -ErrorAction Stop
                }
            } catch { }
        }
        for ($attempt = 1; $attempt -le 10 -and (Test-Path $actual); $attempt++) {
            try { Remove-Item -LiteralPath $actual -Recurse -Force -ErrorAction Stop }
            catch {
                if ($attempt -eq 10) { throw }
                Start-Sleep -Milliseconds 500
            }
        }
    }
    if (Test-Path -LiteralPath $actual) { throw "Le dossier application existe encore : $actual" }
    Remove-StaleApplicationTransactions

    if ($purge -and (Test-Path $rootDirectory)) {
        Remove-Item -LiteralPath $rootDirectory -Recurse -Force -ErrorAction Stop
    }
    if ($purge -and (Test-Path -LiteralPath $rootDirectory)) {
        throw "Les données locales existent encore : $rootDirectory"
    }
    $completionMessage = T 'UninstallComplete'
    $completionIcon = 'Information'
    if ($cleanupWarnings.Count -gt 0) {
        $cleanupWarning = $cleanupWarnings -join ' | '
        Write-UninstallerLog 'WARN' $cleanupWarning
        if ($Silent) { throw $cleanupWarning }
        $completionMessage += "`r`n`r`n" + (T 'Warning' @($cleanupWarning))
        $completionIcon = 'Warning'
    }
    if (-not $Silent) {
        Show-UninstallResult (T 'UninstallCompleteTitle') $completionMessage $true
    }
    Write-UninstallerLog 'INFO' 'Désinstallation terminée avec succès.'
    Remove-TemporaryUninstallFiles
} catch {
    Write-UninstallerLog 'ERROR' $_.Exception.ToString()
    if ($Silent) {
        [Console]::Error.WriteLine($_.Exception.Message)
    } else {
        Show-UninstallResult (T 'UninstallErrorTitle') $_.Exception.Message $false
    }
    Remove-TemporaryUninstallFiles
    exit 1
} finally {
    Exit-MaintenanceLock
}
