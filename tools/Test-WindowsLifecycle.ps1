param(
    [string]$SetupPath = '',
    [string]$Version = ''
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$bridgeRoot = Join-Path $env:LOCALAPPDATA 'JellyfinVlcBridge'
$applicationDirectory = Join-Path $bridgeRoot 'App'
$uninstallRegistry = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\JellyfinVlcBridge'
$runRegistry = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$protocolRegistry = 'HKCU:\Software\Classes\jellyfin-vlc'
$chromeHostRegistry = 'HKCU:\Software\Google\Chrome\NativeMessagingHosts\local.jellyfin_vlc_bridge'
$edgeHostRegistry = 'HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\local.jellyfin_vlc_bridge'
$startMenuDirectory = Join-Path ([Environment]::GetFolderPath('Programs')) 'Jellyfin VLC Bridge'

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

function Test-RegistryValue([string]$path, [string]$name) {
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    $values = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
    return $null -ne $values.PSObject.Properties[$name]
}

function Invoke-WaitingProcess([string]$filePath, [string[]]$arguments, [int]$timeoutSeconds = 150) {
    $process = Start-Process -FilePath $filePath -ArgumentList $arguments -PassThru
    try {
        if (-not $process.WaitForExit($timeoutSeconds * 1000)) {
            try { $process.Kill() } catch { }
            [void]$process.WaitForExit(5000)
            throw "$filePath a depasse le delai de $timeoutSeconds secondes."
        }
        if ($process.ExitCode -ne 0) {
            throw "$filePath a echoue avec le code $($process.ExitCode)."
        }
    } finally {
        $process.Dispose()
    }
}

function Show-LifecycleLogs {
    foreach ($logPath in @(
        (Join-Path $bridgeRoot 'Logs\installer.log'),
        (Join-Path $env:TEMP 'JellyfinVlcBridge-setup.log'),
        (Join-Path $env:TEMP 'JellyfinVlcBridge-uninstall.log')
    )) {
        if (Test-Path -LiteralPath $logPath -PathType Leaf) {
            Write-Host "`n--- $logPath ---"
            Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue
        }
    }
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    [xml]$buildProperties = Get-Content -LiteralPath (Join-Path $projectDirectory 'Directory.Build.props') -Raw
    $Version = [string]$buildProperties.Project.PropertyGroup.Version
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version invalide : $Version" }

if ([string]::IsNullOrWhiteSpace($SetupPath)) {
    $SetupPath = Join-Path $projectDirectory "outputs\JellyfinVlcBridge-$Version-Setup.exe"
} elseif (-not [IO.Path]::IsPathRooted($SetupPath)) {
    $SetupPath = Join-Path $projectDirectory $SetupPath
}
$SetupPath = [IO.Path]::GetFullPath($SetupPath)
Assert-True (Test-Path -LiteralPath $SetupPath -PathType Leaf) "Setup introuvable : $SetupPath"

$existingMarkers = @(
    $bridgeRoot,
    $uninstallRegistry,
    $protocolRegistry,
    $chromeHostRegistry,
    $edgeHostRegistry
) | Where-Object { Test-Path -LiteralPath $_ }
if ($existingMarkers.Count -gt 0 -or (Test-RegistryValue $runRegistry 'JellyfinVlcBridge')) {
    throw 'Le test de cycle complet exige une session Windows sans Jellyfin VLC Bridge deja installe.'
}

$installedByTest = $false
try {
    Write-Host "Installation reelle et silencieuse de Jellyfin VLC Bridge $Version..."
    Invoke-WaitingProcess $SetupPath @('/quiet')
    $installedByTest = $true

    $bridgeExecutable = Join-Path $applicationDirectory 'jellyfin-vlc-bridge.exe'
    $controlCenter = Join-Path $applicationDirectory 'jellyfin-vlc-bridge-control.exe'
    $uninstaller = Join-Path $applicationDirectory 'Desinstaller-GUI.ps1'
    foreach ($requiredFile in @(
        $bridgeExecutable,
        $controlCenter,
        $uninstaller,
        (Join-Path $applicationDirectory 'Centre-Controle.ps1'),
        (Join-Path $applicationDirectory 'Localization.ps1'),
        (Join-Path $applicationDirectory 'UiTheme.ps1')
    )) {
        Assert-True (Test-Path -LiteralPath $requiredFile -PathType Leaf) "Fichier installe absent : $requiredFile"
    }

    $versionOutput = (& $bridgeExecutable version 2>&1 | Out-String).Trim()
    Assert-True ($LASTEXITCODE -eq 0) 'La commande version de l application installee a echoue.'
    Assert-True ($versionOutput -eq "Jellyfin VLC Bridge $Version") "Version installee inattendue : '$versionOutput'."
    Invoke-WaitingProcess $controlCenter @('--validate-only') 60

    $uninstallEntry = Get-ItemProperty -LiteralPath $uninstallRegistry -ErrorAction Stop
    Assert-True ($uninstallEntry.DisplayName -eq 'Jellyfin VLC Bridge') 'Nom absent des applications installees.'
    Assert-True ($uninstallEntry.DisplayVersion -eq $Version) 'Version incorrecte dans les applications installees.'
    Assert-True ($uninstallEntry.Publisher -eq 'Jellyfin VLC Bridge Project') 'Editeur incorrect dans les applications installees.'
    Assert-True ([IO.Path]::GetFullPath([string]$uninstallEntry.InstallLocation) -eq [IO.Path]::GetFullPath($applicationDirectory)) 'Emplacement d installation incorrect.'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$uninstallEntry.QuietUninstallString)) 'Commande de desinstallation silencieuse absente.'

    foreach ($registryPath in @($protocolRegistry, $chromeHostRegistry, $edgeHostRegistry)) {
        Assert-True (Test-Path -LiteralPath $registryPath) "Enregistrement Windows absent : $registryPath"
    }
    $runValue = Get-ItemPropertyValue -LiteralPath $runRegistry -Name JellyfinVlcBridge -ErrorAction Stop
    Assert-True ([string]$runValue -like "*$controlCenter*--tray*") 'Demarrage automatique incorrect.'

    $nativeManifest = Join-Path $bridgeRoot 'native-messaging-host.json'
    Assert-True (Test-Path -LiteralPath $nativeManifest -PathType Leaf) 'Manifeste de messagerie native absent.'
    $nativeConfiguration = Get-Content -LiteralPath $nativeManifest -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([IO.Path]::GetFullPath([string]$nativeConfiguration.path) -eq [IO.Path]::GetFullPath($bridgeExecutable)) 'Chemin du Bridge incorrect dans le manifeste natif.'
    Assert-True ($nativeConfiguration.allowed_origins -contains 'chrome-extension://hkjbodgdbjhignhlbecchiigcfigpidp/') 'Extension Chrome officielle absente du manifeste natif.'
    Assert-True (Test-Path -LiteralPath (Join-Path $startMenuDirectory 'Jellyfin VLC Bridge.lnk') -PathType Leaf) 'Raccourci principal absent du menu Demarrer.'
    Assert-True (Test-Path -LiteralPath (Join-Path $startMenuDirectory 'Desinstaller Jellyfin VLC Bridge.lnk') -PathType Leaf) 'Raccourci de desinstallation absent du menu Demarrer.'

    Write-Host 'Reinstallation silencieuse pour valider le chemin de mise a niveau/reparation...'
    Invoke-WaitingProcess $SetupPath @('/quiet')
    $secondVersionOutput = (& $bridgeExecutable version 2>&1 | Out-String).Trim()
    Assert-True ($LASTEXITCODE -eq 0 -and $secondVersionOutput -eq "Jellyfin VLC Bridge $Version") 'La reinstallation n a pas conserve la bonne version.'

    Write-Host 'Desinstallation reelle avec la commande silencieuse enregistree...'
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File $uninstaller -Silent
    Assert-True ($LASTEXITCODE -eq 0) "La desinstallation silencieuse a echoue avec le code $LASTEXITCODE."
    $installedByTest = $false

    Assert-True (-not (Test-Path -LiteralPath $applicationDirectory)) 'Le dossier de l application existe encore apres desinstallation.'
    foreach ($registryPath in @($uninstallRegistry, $protocolRegistry, $chromeHostRegistry, $edgeHostRegistry)) {
        Assert-True (-not (Test-Path -LiteralPath $registryPath)) "Enregistrement encore present apres desinstallation : $registryPath"
    }
    Assert-True (-not (Test-RegistryValue $runRegistry 'JellyfinVlcBridge')) 'Le demarrage automatique existe encore apres desinstallation.'
    Assert-True (-not (Test-Path -LiteralPath $startMenuDirectory)) 'Le dossier du menu Demarrer existe encore apres desinstallation.'

    Write-Host 'OK  Cycle reel Setup, enregistrements Windows, reinstallation et desinstallation'
} catch {
    Show-LifecycleLogs
    throw
} finally {
    if ($installedByTest -and (Test-Path -LiteralPath (Join-Path $applicationDirectory 'Desinstaller-GUI.ps1'))) {
        try {
            & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden `
                -File (Join-Path $applicationDirectory 'Desinstaller-GUI.ps1') -Silent -Purge
        } catch { }
    }
    foreach ($registryPath in @($uninstallRegistry, $protocolRegistry, $chromeHostRegistry, $edgeHostRegistry)) {
        Remove-Item -LiteralPath $registryPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-ItemProperty -LiteralPath $runRegistry -Name JellyfinVlcBridge -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $startMenuDirectory -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $bridgeRoot) {
        Remove-Item -LiteralPath $bridgeRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
