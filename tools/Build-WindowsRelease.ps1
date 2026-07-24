param(
    [string]$Version = '1.12.0'
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$outputsDirectory = Join-Path $projectDirectory 'outputs'
$releaseDirectory = Join-Path $outputsDirectory "JellyfinVlcBridge-$Version-win-x64"
$releaseZip = Join-Path $outputsDirectory "JellyfinVlcBridge-$Version-win-x64.zip"
$setupExe = Join-Path $outputsDirectory "JellyfinVlcBridge-$Version-Setup.exe"
$workRoot = Join-Path $projectDirectory 'work'
$buildDirectory = Join-Path $workRoot "release-$Version"
$appIcon = Join-Path $projectDirectory 'assets\JellyfinVlcBridge.ico'
$runtimeFrameworkVersion = '8.0.22'
$globalPackagesDirectory = Join-Path $env:USERPROFILE '.nuget\packages'

function Remove-GeneratedDirectory([string]$path, [string]$expectedParent) {
    $resolved = [IO.Path]::GetFullPath($path)
    $parent = [IO.Path]::GetFullPath($expectedParent).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($parent, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Chemin de génération inattendu : $resolved"
    }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}

New-Item -ItemType Directory -Path $outputsDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
Remove-GeneratedDirectory $releaseDirectory $outputsDirectory
Remove-GeneratedDirectory $buildDirectory $workRoot
New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $buildDirectory -Force | Out-Null

try {
    & (Join-Path $projectDirectory 'tools\Build-AppIcon.ps1') -OutputPath $appIcon
    if (-not (Test-Path -LiteralPath $appIcon)) { throw "La création de l’icône a échoué." }

    $appData = Join-Path $buildDirectory 'appdata'
    New-Item -ItemType Directory -Path $appData -Force | Out-Null
    $env:APPDATA = $appData

    & dotnet restore (Join-Path $projectDirectory 'src\JellyfinVlcBridge.Cli\JellyfinVlcBridge.Cli.csproj') `
        --runtime win-x64 `
        --packages $globalPackagesDirectory `
        --ignore-failed-sources `
        -p:RuntimeFrameworkVersion=$runtimeFrameworkVersion `
        --configfile (Join-Path $projectDirectory 'NuGet.Config')
    if ($LASTEXITCODE -ne 0) { throw 'La restauration .NET a échoué.' }
    & dotnet publish (Join-Path $projectDirectory 'src\JellyfinVlcBridge.Cli\JellyfinVlcBridge.Cli.csproj') `
        --configuration Release `
        --runtime win-x64 `
        --self-contained true `
        --no-restore `
        --output $releaseDirectory `
        -p:RuntimeFrameworkVersion=$runtimeFrameworkVersion `
        -p:PublishSingleFile=true `
        -p:IncludeNativeLibrariesForSelfExtract=true `
        -p:DebugType=None
    if ($LASTEXITCODE -ne 0) { throw 'La publication Windows a échoué.' }

    Get-ChildItem -LiteralPath $releaseDirectory -Filter '*.pdb' -File | Remove-Item -Force

    $compiler = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path $compiler)) { throw 'Compilateur Windows .NET Framework introuvable.' }
    $controlCenterExe = Join-Path $releaseDirectory 'jellyfin-vlc-bridge-control.exe'
    & $compiler /nologo /target:winexe /codepage:65001 "/out:$controlCenterExe" `
        "/win32icon:$appIcon" `
        /reference:System.Windows.Forms.dll `
        (Join-Path $projectDirectory 'installer\ControlCenterBootstrap.cs')
    if ($LASTEXITCODE -ne 0) { throw 'La creation du centre de controle graphique a echoue.' }

    foreach ($file in @(
        'installer\Installer-GUI.ps1',
        'installer\Centre-Controle.ps1',
        'installer\Localization.ps1',
        'installer\INSTALLER-WINDOWS.cmd',
        'installer\Desinstaller-GUI.ps1',
        'installer\Desinstaller-JellyfinVlcBridge.ps1',
        'installer\DESINSTALLER-WINDOWS.cmd',
        'README.md',
        'README.en.md',
        'LICENSE',
        'PRIVACY.md'
    )) { Copy-Item (Join-Path $projectDirectory $file) $releaseDirectory -Force }

    # Windows PowerShell 5.1 interprète un fichier UTF-8 sans signature comme du
    # texte ANSI. La signature UTF-8 évite les textes du type "sÃ©curisÃ©e" dans
    # l'installateur, le centre de contrôle et le désinstallateur.
    $utf8WithBom = New-Object System.Text.UTF8Encoding($true)
    $utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
    Get-ChildItem -LiteralPath $releaseDirectory -Filter '*.ps1' -File | ForEach-Object {
        $scriptContent = [IO.File]::ReadAllText($_.FullName, $utf8Strict)
        [IO.File]::WriteAllText($_.FullName, $scriptContent, $utf8WithBom)
    }

    Compress-Archive -Path (Join-Path $releaseDirectory '*') -DestinationPath $releaseZip -CompressionLevel Optimal -Force

    $payload = Join-Path $buildDirectory 'payload.zip'
    Compress-Archive -Path (Join-Path $releaseDirectory '*') -DestinationPath $payload -CompressionLevel Optimal -Force
    & $compiler /nologo /target:winexe /codepage:65001 "/out:$setupExe" `
        "/win32icon:$appIcon" `
        /reference:System.Windows.Forms.dll `
        /reference:System.IO.Compression.dll `
        /reference:System.IO.Compression.FileSystem.dll `
        "/resource:$payload,payload.zip" `
        (Join-Path $projectDirectory 'installer\SetupBootstrap.cs')
    if ($LASTEXITCODE -ne 0) { throw "La création de l’installateur EXE a échoué." }

    Write-Output $setupExe
    Write-Output $releaseZip
} finally {
    Remove-GeneratedDirectory $buildDirectory $workRoot
}
