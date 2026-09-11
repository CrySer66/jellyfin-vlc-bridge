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
$script:validateOnly = $script:installerArguments -contains '-ValidateOnly'
$script:renderPreview = Get-InternalArgumentValue '-RenderPreview'
$script:previewMode = $script:validateOnly -or $script:renderPreview -or ($script:installerArguments -contains '-Preview')
$script:previewState = Get-InternalArgumentValue '-PreviewState'
if ($script:previewMode -and $script:silentInstall) { throw 'Un aperçu ne peut pas exécuter une installation silencieuse.' }
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

$script:bridgeVersion = '1.19.1'
$script:chromeWebStoreId = 'hkjbodgdbjhignhlbecchiigcfigpidp'
$script:chromeWebStoreUrl = 'https://chromewebstore.google.com/detail/' + $script:chromeWebStoreId
$script:packageDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $script:packageDirectory 'Localization.ps1') -Preview:$script:previewMode
$previewLanguage = Get-InternalArgumentValue '-Language'
if ($script:previewMode -and $previewLanguage -in @('fr', 'en')) { $script:JvbLanguage = $previewLanguage }
$script:rootDirectory = if ($script:isolatedTestMode) {
    [IO.Path]::GetFullPath($script:isolatedTestRoot)
} else {
    Join-Path $env:LOCALAPPDATA 'JellyfinVlcBridge'
}
$script:installDirectory = Join-Path $script:rootDirectory 'App'
$script:executable = Join-Path $script:installDirectory 'jellyfin-vlc-bridge.exe'
$script:configFile = Join-Path $script:rootDirectory 'config.json'
$script:hadExistingConfig = -not $script:previewMode -and (Test-Path $script:configFile)
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
    Show-JvbWpfMessage 'Jellyfin VLC Bridge' $message 'Error'
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
        'jellyfin-vlc-bridge-control.exe.config',
        'Centre-Controle.ps1',
        'Localization.ps1',
        'UiTheme.ps1',
        'DesktopTheme.xaml',
        'WpfTheme.ps1',
        'InstallWindow.xaml',
        'UninstallWindow.xaml',
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
        # Only successful completion may discard a backup. A previous rollback
        # may have failed while files were locked, leaving this as the last copy.
        if ($directory.Name -like 'App.backup-*') { continue }
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
    $uninstallShortcut.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$uninstaller`""
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
    Set-ItemProperty -Path $registry -Name UninstallString -Value "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$uninstaller`""
    Set-ItemProperty -Path $registry -Name QuietUninstallString -Value "powershell.exe -NoProfile -STA -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$uninstaller`" -Silent"
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

. (Join-Path $script:packageDirectory 'WpfTheme.ps1')
Initialize-JvbWpfTheme

$script:form = New-JvbWpfWindow ([IO.File]::ReadAllText((Join-Path $script:packageDirectory 'InstallWindow.xaml')))
$script:form.Title = 'Jellyfin VLC Bridge ' + $script:bridgeVersion + ' — ' + (T 'MaintenanceInstallTitle')
foreach ($entry in @{
    serverBox = 'ServerBox'; installButton = 'InstallButton'; cancelButton = 'CancelButton'
    changeServerButton = 'ChangeServerButton'; codeCard = 'CodeCard'; codeLabel = 'CodeValue'
    instructions = 'Instructions'; statusLabel = 'StatusLabel'; progress = 'Progress'
    extensionButton = 'ExtensionButton'; headline = 'Headline'; contentTitle = 'CardTitle'
    versionLabel = 'VersionLabel'
}.GetEnumerator()) {
    Set-Variable -Name $entry.Key -Value ($form.FindName($entry.Value)) -Scope Script
}
$versionLabel.Text = T 'Version' @($script:bridgeVersion)
$script:setupOutputTask = $null
$script:setupErrorTask = $null
$script:timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(350)

function Set-SetupStage([int]$stage) {
    foreach ($index in 0..2) {
        $step = $form.FindName('Step' + $index)
        $step.Background = if ($index -eq $stage) { '#263D56' } else { 'Transparent' }
        $step.BorderBrush = if ($index -eq $stage) { '#395773' } else { 'Transparent' }
        $step.BorderThickness = [Windows.Thickness]::new(1)
        $step.Opacity = if ($index -le $stage) { 1 } else { 0.65 }
    }
}

function Set-InstallationReadyView {
    Set-SetupStage 2
    $progress.IsIndeterminate = $false
    $progress.Value = 100
    $statusLabel.Text = T 'InstallSuccess'
    $statusLabel.Foreground = '#16856D'
    $headline.Text = T 'InstallComplete'
    $contentTitle.Text = T 'StepReady'
    $codeCard.Visibility = 'Collapsed'
    $form.FindName('AddressHint').Visibility = 'Collapsed'
    $instructions.Visibility = 'Visible'
    $serverBox.Visibility = 'Collapsed'
    $changeServerButton.Visibility = 'Collapsed'
    $instructions.Text = if ($script:replaceExistingConfig) { T 'NewConnectionSaved' }
        elseif ($script:hadExistingConfig) { T 'UpdateCompletePreserved' }
        else { T 'InstallCompleteDetail' }
    $installButton.Content = T 'MaintenanceFinish'
    $installButton.IsEnabled = $true
    $cancelButton.Content = T 'Close'
    $cancelButton.IsEnabled = $true
    $extensionButton.Visibility = if ($script:hadExistingConfig) { 'Collapsed' } else { 'Visible' }
}

function Complete-Installation {
    Register-WindowsApplication
    Complete-ApplicationTransaction
    Exit-MaintenanceLock
    $script:installed = $true
    $timer.Stop()
    if ($script:setupProcess) { $script:setupProcess.Dispose(); $script:setupProcess = $null }
    Set-InstallationReadyView
    $controlCenter = Join-Path $script:installDirectory 'jellyfin-vlc-bridge-control.exe'
    try { Start-Process -FilePath $controlCenter -ArgumentList '--tray' -WindowStyle Hidden } catch { }
}

function Reset-InstallationAfterFailure([Exception]$failure) {
    $timer.Stop()
    Set-SetupStage 0
    Write-InstallerLog 'ERROR' $failure.ToString()
    if ($script:setupProcess) {
        try {
            if (-not $script:setupProcess.HasExited) { $script:setupProcess.Kill(); [void]$script:setupProcess.WaitForExit(5000) }
        } catch { }
        $script:setupProcess.Dispose()
        $script:setupProcess = $null
    }
    $rollbackFailed = $false
    try { Undo-ApplicationTransaction }
    catch {
        $rollbackFailed = $true
        Write-InstallerLog 'ERROR' $_.Exception.ToString()
    }
    if (-not $rollbackFailed) { Exit-MaintenanceLock }
    $progress.IsIndeterminate = $false
    $progress.Value = 0
    $installButton.IsEnabled = -not $rollbackFailed
    $serverBox.IsEnabled = $true
    $changeServerButton.IsEnabled = $true
    $cancelButton.IsEnabled = $true
    $installButton.Content = T 'Retry'
    $codeCard.Visibility = 'Collapsed'
    $statusLabel.Text = if ($rollbackFailed) { T 'RollbackIncomplete' }
        else { (T 'InstallationInterrupted') + ' ' + $failure.Message }
    $instructions.Visibility = 'Visible'
    $statusLabel.Foreground = '#BC3D53'
}

$serverBox.Text = if ($script:existingServerUrl) { $script:existingServerUrl } else { 'http://192.168.1.25:8096' }
$serverBox.IsReadOnly = $script:hadExistingConfig
if ($script:hadExistingConfig) {
    $changeServerButton.Visibility = 'Visible'
    $installButton.Content = T 'MaintenanceUpdateAction'
    $headline.Text = T 'MaintenanceUpdateLead'
    $contentTitle.Text = T 'MaintenanceUpdateTitle'
    $instructions.Text = T 'ExistingConnection'
}
Set-SetupStage 0

# Build/QA entry points show sample data and return before wiring any operation.
if ($script:previewMode) {
    $serverBox.Text = 'http://jellyfin.local:8096'
    $statusLabel.Text = T 'MaintenancePreview'
    switch ($script:previewState) {
        'update' {
            $script:hadExistingConfig = $true
            $installButton.Content = T 'MaintenanceUpdateAction'
            $serverBox.IsReadOnly = $true
            $changeServerButton.Visibility = 'Visible'
            $headline.Text = T 'MaintenanceUpdateLead'
            $contentTitle.Text = T 'MaintenanceUpdateTitle'
            $instructions.Text = T 'ExistingConnection'
        }
        'authorize' {
            Set-SetupStage 1
            $codeCard.Visibility = 'Visible'
            $codeLabel.Text = '834 219'
            $instructions.Visibility = 'Collapsed'
            $serverBox.IsEnabled = $false
            $installButton.IsEnabled = $false
            $progress.IsIndeterminate = $true
            $statusLabel.Text = T 'WaitingAuthorization'
        }
        'success' { Set-InstallationReadyView }
        'error' {
            $statusLabel.Text = T 'QuickConnectFailed'
            $statusLabel.Foreground = '#BC3D53'
            $installButton.Content = T 'Retry'
        }
    }
    if ($script:validateOnly) {
        foreach ($size in @([Windows.Size]::new($form.MinWidth, $form.MinHeight), [Windows.Size]::new($form.Width, $form.Height))) {
            $form.Content.Measure($size)
            $form.Content.Arrange([Windows.Rect]::new([Windows.Point]::new(0, 0), $size))
            $form.Content.UpdateLayout()
        }
        if (-not $serverBox -or -not $installButton -or -not $codeCard) { throw 'Contrôles WPF manquants.' }
    }
    if ($script:renderPreview) { Save-JvbWpfPreview $form $script:renderPreview; exit 0 }
    if ($script:validateOnly) { exit 0 }
    $cancelButton.Add_Click({ $form.Close() })
    $installButton.Add_Click({ $statusLabel.Text = T 'MaintenancePreview' })
    [void]$form.ShowDialog()
    exit 0
}

$extensionButton.Add_Click({ Open-ChromeWebStore })
$cancelButton.Add_Click({ $form.Close() })
$changeServerButton.Add_Click({
    $script:replaceExistingConfig = $true
    $contentTitle.Text = T 'NewServerAddress'
    $serverBox.IsReadOnly = $false
    $serverBox.SelectAll()
    [void]$serverBox.Focus()
    $changeServerButton.Visibility = 'Collapsed'
    $instructions.Text = T 'ChangeServerReady'
})

$timer.Add_Tick({
    try {
        if (Test-Path -LiteralPath $script:codeFile) {
            try { $code = [IO.File]::ReadAllText($script:codeFile).Trim() } catch [IO.IOException] { $code = '' }
            if ($code) {
                Set-SetupStage 1
                $codeLabel.Text = $code
                $codeCard.Visibility = 'Visible'
                $instructions.Visibility = 'Collapsed'
                $statusLabel.Text = T 'WaitingAuthorization'
            }
        }
        if ($script:setupProcess -and $script:setupProcess.HasExited) {
            $timer.Stop()
            if ($script:setupProcess.ExitCode -ne 0) {
                # Drain both streams continuously while Quick Connect is pending.
                $output = $script:setupOutputTask.GetAwaiter().GetResult()
                $errorText = $script:setupErrorTask.GetAwaiter().GetResult()
                Write-InstallerLog 'ERROR' ($output + [Environment]::NewLine + $errorText)
                throw (T 'QuickConnectFailed')
            }
            Complete-Installation
        }
    } catch { Reset-InstallationAfterFailure $_.Exception }
})

$installButton.Add_Click({
    if ($script:installed) {
        try { Start-Process -FilePath (Join-Path $script:installDirectory 'jellyfin-vlc-bridge-control.exe') -WindowStyle Normal }
        catch { Show-SetupError $_.Exception.Message; return }
        $form.Close()
        return
    }
    try {
        $uri = $null
        if (-not [Uri]::TryCreate($serverBox.Text.Trim(), [UriKind]::Absolute, [ref]$uri) -or
            $uri.Scheme -notin @('http', 'https') -or -not [string]::IsNullOrEmpty($uri.UserInfo) -or
            -not [string]::IsNullOrEmpty($uri.Query) -or -not [string]::IsNullOrEmpty($uri.Fragment)) {
            throw (T 'InvalidJellyfinAddress')
        }
        Enter-MaintenanceLock
        $installButton.IsEnabled = $false
        $serverBox.IsEnabled = $false
        $changeServerButton.IsEnabled = $false
        $progress.IsIndeterminate = $true
        $statusLabel.Foreground = '#17283E'
        $statusLabel.Text = T 'CopyingFiles'
        $codeCard.Visibility = 'Collapsed'
        if (Test-Path -LiteralPath $script:codeFile) { Remove-Item -LiteralPath $script:codeFile -Force }
        Invoke-JvbWpfRender $form
        Copy-ApplicationFiles
        if ($script:hadExistingConfig -and -not $script:replaceExistingConfig) {
            $statusLabel.Text = T 'ConnectionPreserved'
            Invoke-JvbWpfRender $form
            Install-ApplicationIntegrations
            Complete-Installation
            return
        }
        $statusLabel.Text = T 'RequestingCode'
        $processInfo = New-Object Diagnostics.ProcessStartInfo
        $processInfo.FileName = $script:executable
        $processInfo.Arguments = 'setup --server "' + $uri.AbsoluteUri.TrimEnd('/') + '" --code-path "' + $script:codeFile + '"'
        $processInfo.WorkingDirectory = $script:installDirectory
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.StandardOutputEncoding = [Text.Encoding]::UTF8
        $processInfo.StandardErrorEncoding = [Text.Encoding]::UTF8
        $script:setupProcess = [Diagnostics.Process]::Start($processInfo)
        if (-not $script:setupProcess) { throw (T 'ProgramStartFailed') }
        $script:setupOutputTask = $script:setupProcess.StandardOutput.ReadToEndAsync()
        $script:setupErrorTask = $script:setupProcess.StandardError.ReadToEndAsync()
        $timer.Start()
    } catch { Reset-InstallationAfterFailure $_.Exception }
})

$form.Add_Closing({
    $timer.Stop()
    if (-not $script:installed -and $script:setupProcess -and
        $script:setupProcess.HasExited -and $script:setupProcess.ExitCode -eq 0) {
        try { Complete-Installation } catch { Reset-InstallationAfterFailure $_.Exception }
    }
    if ($script:setupProcess -and -not $script:setupProcess.HasExited) {
        try { $script:setupProcess.Kill(); [void]$script:setupProcess.WaitForExit(5000) } catch { }
    }
    if ($script:setupProcess) { $script:setupProcess.Dispose(); $script:setupProcess = $null }
    if (-not $script:installed) {
        try { Undo-ApplicationTransaction } catch { Write-InstallerLog 'ERROR' $_.Exception.ToString() }
    }
    Exit-MaintenanceLock
    if (Test-Path -LiteralPath $script:codeFile) { Remove-Item -LiteralPath $script:codeFile -Force -ErrorAction SilentlyContinue }
})
[void]$form.ShowDialog()
