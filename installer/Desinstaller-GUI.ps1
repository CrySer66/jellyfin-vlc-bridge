param(
    [switch]$TemporaryRun,
    [switch]$Silent,
    [switch]$Purge,
    [switch]$IsolatedTest,
    [switch]$ValidateOnly,
    [string]$RenderPreview,
    [ValidateSet('choice', 'progress', 'success', 'error')][string]$PreviewState = 'choice',
    [ValidateSet('auto', 'fr', 'en')][string]$Language = 'auto'
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$localizationFile = Join-Path $scriptDirectory 'Localization.ps1'
$themeFile = Join-Path $scriptDirectory 'WpfTheme.ps1'
$previewMode = $ValidateOnly -or -not [string]::IsNullOrWhiteSpace($RenderPreview)
if (Test-Path -LiteralPath $localizationFile) { . $localizationFile -Preview:$previewMode }
if ($Language -ne 'auto') { $script:JvbLanguage = $Language }
$uninstallerLog = Join-Path $env:TEMP 'JellyfinVlcBridge-uninstall.log'

# These labels belong to the uninstall flow; the visual styles are shared with
# the native control center and the installation flow.
$uninstallMessages = @{
    fr = @{
        UninstallNavigation = 'Désinstallation'
        UninstallPageTitle = 'Désinstaller le Bridge'
        UninstallAction = 'Désinstaller'
        UninstallLocalOnly = 'Cette action concerne uniquement le Bridge installé sur cet ordinateur.'
        UninstallMediaPreserved = 'Votre serveur Jellyfin, vos films et vos séries ne sont pas modifiés.'
        UninstallWorking = 'Désinstallation en cours'
        UninstallWorkingDetail = "Préparation du retrait de l’application…"
        UninstallRemovingLinks = 'Retrait des connexions à Windows et aux navigateurs…'
        UninstallRemovingFiles = "Suppression des fichiers de l’application…"
        UninstallRemovingSettings = 'Suppression des données locales sélectionnées…'
        UninstallFinishing = 'Vérification et finalisation…'
        UninstallSuccessSubtitle = 'Le Bridge a été retiré de cet ordinateur.'
        UninstallAppRemoved = 'Le logiciel a été retiré.'
        UninstallErrorSubtitle = "La désinstallation n’a pas pu se terminer."
        UninstallPreviewError = 'Un fichier du Bridge est encore utilisé. Fermez le centre de contrôle, puis relancez la désinstallation.'
    }
    en = @{
        UninstallNavigation = 'Uninstall'
        UninstallPageTitle = 'Uninstall the Bridge'
        UninstallAction = 'Uninstall'
        UninstallLocalOnly = 'This action only affects the Bridge installed on this computer.'
        UninstallMediaPreserved = 'Your Jellyfin server, movies and series will not be changed.'
        UninstallWorking = 'Uninstalling'
        UninstallWorkingDetail = 'Preparing to remove the application…'
        UninstallRemovingLinks = 'Removing Windows and browser connections…'
        UninstallRemovingFiles = 'Removing the application files…'
        UninstallRemovingSettings = 'Removing the selected local data…'
        UninstallFinishing = 'Checking and finishing…'
        UninstallSuccessSubtitle = 'The Bridge was removed from this computer.'
        UninstallAppRemoved = 'The application was removed.'
        UninstallErrorSubtitle = 'The uninstall could not be completed.'
        UninstallPreviewError = 'A Bridge file is still in use. Close the control center, then run the uninstaller again.'
    }
}
foreach ($locale in $uninstallMessages.Keys) {
    foreach ($key in $uninstallMessages[$locale].Keys) {
        $script:JvbMessages[$locale][$key] = $uninstallMessages[$locale][$key]
    }
}

function New-UninstallWindow {
    . $themeFile
    Initialize-JvbWpfTheme
    $window = New-JvbWpfWindow -Xaml (Get-Content -LiteralPath (Join-Path $scriptDirectory 'UninstallWindow.xaml') -Raw -Encoding UTF8)
    foreach ($name in @('ChoicePanel', 'ProgressPanel', 'ResultPanel', 'KeepOption', 'PurgeOption',
            'PageTitle', 'PageSubtitle', 'ProgressLabel', 'ProgressFill', 'ResultTitle', 'ResultMessage',
            'ResultIcon', 'ResultIconBackground', 'SettingsResultCard', 'SettingsResult',
            'CancelButton', 'RemoveButton', 'CloseButton')) {
        if ($null -eq $window.FindName($name)) { throw "Missing uninstall control: $name" }
    }
    return $window
}

function Set-UninstallView([string]$state, [string]$message = '') {
    $window = $script:uninstallWindow
    foreach ($name in @('ChoicePanel', 'ProgressPanel', 'ResultPanel', 'CancelButton', 'RemoveButton', 'CloseButton')) {
        $window.FindName($name).Visibility = 'Collapsed'
    }
    switch ($state) {
        'choice' {
            $window.FindName('ChoicePanel').Visibility = 'Visible'
            $window.FindName('CancelButton').Visibility = 'Visible'
            $window.FindName('RemoveButton').Visibility = 'Visible'
            $window.FindName('PageTitle').Text = T 'UninstallPageTitle'
            $window.FindName('PageSubtitle').Text = T 'UninstallQuestion'
        }
        'progress' {
            $window.FindName('ProgressPanel').Visibility = 'Visible'
            $window.FindName('PageTitle').Text = T 'UninstallWorking'
            $window.FindName('PageSubtitle').Text = T 'UninstallMediaPreserved'
            if ($message) { $window.FindName('ProgressLabel').Text = $message }
        }
        default {
            $success = $state -eq 'success'
            $window.FindName('ResultPanel').Visibility = 'Visible'
            $window.FindName('CloseButton').Visibility = 'Visible'
            $window.FindName('PageTitle').Text = T $(if ($success) { 'UninstallCompleteTitle' } else { 'UninstallErrorTitle' })
            $window.FindName('PageSubtitle').Text = T $(if ($success) { 'UninstallSuccessSubtitle' } else { 'UninstallErrorSubtitle' })
            $window.FindName('ResultTitle').Text = T $(if ($success) { 'UninstallAppRemoved' } else { 'UninstallErrorTitle' })
            $window.FindName('ResultMessage').Text = $message
            $window.FindName('SettingsResultCard').Visibility = if ($success) { 'Visible' } else { 'Collapsed' }
            $window.FindName('SettingsResult').Text = T $(if ($script:uninstallPurgesSettings) { 'SettingsRemoved' } else { 'SettingsKept' })
            $window.FindName('ResultIconBackground').Background = if ($success) { '#E2F3EC' } else { '#FBEAEA' }
            $window.FindName('ResultIcon').Stroke = if ($success) { '#087C73' } else { '#B83232' }
            $window.FindName('ResultIcon').Data = if ($success) { 'M 2 10 L 8 16 L 20 3' } else { 'M 3 3 L 19 19 M 19 3 L 3 19' }
        }
    }
}

function Show-UninstallChoice {
    $script:uninstallWindow = New-UninstallWindow
    $script:uninstallChoice = 'cancel'
    Set-UninstallView 'choice'
    $script:uninstallWindow.FindName('CancelButton').Add_Click({ $script:uninstallWindow.Close() })
    $script:uninstallWindow.FindName('RemoveButton').Add_Click({
        $script:uninstallChoice = if ($script:uninstallWindow.FindName('PurgeOption').IsChecked) { 'purge' } else { 'keep' }
        $script:uninstallWindow.Close()
    })
    [void]$script:uninstallWindow.ShowDialog()
    return $script:uninstallChoice
}

function Update-UninstallProgress([string]$message, [double]$fraction = 0) {
    if ($Silent -or $null -eq $script:uninstallWindow) { return }
    if ($message) { $script:uninstallWindow.FindName('ProgressLabel').Text = $message }
    if ($fraction -gt 0) {
        $fill = $script:uninstallWindow.FindName('ProgressFill')
        $available = [Math]::Max(72, $fill.Parent.ActualWidth)
        $fill.Width = [Math]::Max(12, $available * [Math]::Min(1, $fraction))
    }
    Invoke-JvbWpfRender -Window $script:uninstallWindow
}

function Show-UninstallResult([string]$title, [string]$message, [bool]$success) {
    $script:uninstallInProgress = $false
    if ($null -ne $script:uninstallWindow -and $script:uninstallWindow.IsVisible) {
        $script:uninstallWindow.Close()
    }
    $script:uninstallWindow = New-UninstallWindow
    $script:uninstallWindow.Title = $title
    Set-UninstallView $(if ($success) { 'success' } else { 'error' }) $message
    $script:uninstallWindow.FindName('CloseButton').Add_Click({ $script:uninstallWindow.Close() })
    [void]$script:uninstallWindow.ShowDialog()
}

# Preview and validation exit before relocation, logging, configuration checks,
# process termination, registry access or cleanup. They use only sample text.
if ($previewMode) {
    . $themeFile
    $script:uninstallWindow = New-UninstallWindow
    $sampleMessage = switch ($PreviewState) {
        'success' { T 'RemoveExtensionLast' }
        'error' { T 'UninstallPreviewError' }
        default { '' }
    }
    Set-UninstallView $PreviewState $sampleMessage
    if ($ValidateOnly) {
        # Exercise layout at the minimum supported size without creating HWNDs
        # or wiring any action capable of uninstalling the application.
        $minimumSize = New-Object Windows.Size($script:uninstallWindow.MinWidth, $script:uninstallWindow.MinHeight)
        $script:uninstallWindow.Content.Measure($minimumSize)
        $script:uninstallWindow.Content.Arrange((New-Object Windows.Rect(0, 0, $minimumSize.Width, $minimumSize.Height)))
        $script:uninstallWindow.Content.UpdateLayout()
    }
    if ($RenderPreview) { Save-JvbWpfPreview -Window $script:uninstallWindow -Path $RenderPreview }
    $script:uninstallWindow.Close()
    if ($ValidateOnly) { [Console]::WriteLine('Uninstall WPF interface validated.') }
    return
}

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
    Copy-Item -LiteralPath $themeFile -Destination (Join-Path $temporaryDirectory 'WpfTheme.ps1') -Force
    foreach ($uiFile in @('DesktopTheme.xaml', 'UninstallWindow.xaml')) {
        Copy-Item -LiteralPath (Join-Path $scriptDirectory $uiFile) -Destination (Join-Path $temporaryDirectory $uiFile) -Force
    }

    # Le processus parent ne doit pas conserver App comme dossier de travail
    # pendant que la copie temporaire le supprime.
    Set-Location -LiteralPath $env:TEMP
    $temporaryArguments = "-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$temporaryScript`" -TemporaryRun"
    if ($Language -ne 'auto') { $temporaryArguments += " -Language $Language" }
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
$maintenanceMutex = $null
if (-not $Silent) {
    . $themeFile
    Initialize-JvbWpfTheme
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

$choice = if ($Silent) {
    if ($Purge) { 'purge' } else { 'keep' }
} else {
    Show-UninstallChoice
}
if ($choice -eq 'cancel') {
    Remove-TemporaryUninstallFiles
    exit 0
}
$purge = $choice -eq 'purge'
$script:uninstallPurgesSettings = $purge

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
        $finished = if ($Silent) {
            $process.WaitForExit(30000)
        } else {
            $waitTimer = [Diagnostics.Stopwatch]::StartNew()
            while (-not $process.WaitForExit(100) -and $waitTimer.ElapsedMilliseconds -lt 30000) {
                Update-UninstallProgress
            }
            $process.HasExited
        }
        if (-not $finished) {
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
    if (-not $Silent) {
        $script:uninstallWindow = New-UninstallWindow
        $script:uninstallInProgress = $true
        $script:uninstallWindow.Add_Closing({
            param($sender, $eventArgs)
            if ($script:uninstallInProgress) { $eventArgs.Cancel = $true }
        })
        Set-UninstallView 'progress' (T 'UninstallWorkingDetail')
        $script:uninstallWindow.Show()
        Update-UninstallProgress (T 'UninstallWorkingDetail') 0.08
    }
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
    Update-UninstallProgress (T 'UninstallRemovingLinks') 0.3
    try {
        Remove-BridgeRegistrationFallback
        Assert-BridgeRegistrationRemoved
    } catch {
        $cleanupWarnings.Add((T 'CleanupIncomplete' @($_.Exception.Message)))
    }

    $expected = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'JellyfinVlcBridge\App'))
    $actual = [IO.Path]::GetFullPath($installDirectory)
    if ($actual -ne $expected) { throw (T 'UnsafeUninstallPath') }

    Update-UninstallProgress (T 'UninstallRemovingFiles') 0.55
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
                Update-UninstallProgress
                Start-Sleep -Milliseconds 500
            }
        }
    }
    if (Test-Path -LiteralPath $actual) { throw "Le dossier application existe encore : $actual" }
    Remove-StaleApplicationTransactions

    Update-UninstallProgress (T 'UninstallRemovingSettings') 0.8
    if ($purge -and (Test-Path $rootDirectory)) {
        Remove-Item -LiteralPath $rootDirectory -Recurse -Force -ErrorAction Stop
    }
    if ($purge -and (Test-Path -LiteralPath $rootDirectory)) {
        throw "Les données locales existent encore : $rootDirectory"
    }
    Update-UninstallProgress (T 'UninstallFinishing') 1
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
