param([string]$ExpectedVersion)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot

function Read-MatchedVersion([string]$relativePath, [string]$pattern) {
    $path = Join-Path $projectDirectory $relativePath
    $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $match = [regex]::Match($content, $pattern)
    if (-not $match.Success) { throw "Version introuvable dans $relativePath" }
    return $match.Groups[1].Value
}

[xml]$props = Get-Content -LiteralPath (Join-Path $projectDirectory 'Directory.Build.props') -Raw -Encoding UTF8
$projectVersion = [string]$props.Project.PropertyGroup.Version
if ([string]::IsNullOrWhiteSpace($ExpectedVersion)) { $ExpectedVersion = $projectVersion }
if ($ExpectedVersion -notmatch '^\d+\.\d+\.\d+$') { throw "Version attendue invalide : $ExpectedVersion" }

$versions = [ordered]@{
    'Directory.Build.props' = $projectVersion
    'BridgeVersion.cs' = Read-MatchedVersion 'src\JellyfinVlcBridge.Core\BridgeVersion.cs' 'Current\s*=\s*"([^"]+)"'
    'Build-WindowsRelease.ps1' = Read-MatchedVersion 'tools\Build-WindowsRelease.ps1' '\[string\]\$Version\s*=\s*''([^'']+)'''
    'Test-WindowsPackage.ps1' = Read-MatchedVersion 'tools\Test-WindowsPackage.ps1' '\[string\]\$Version\s*=\s*''([^'']+)'''
    'Installer-GUI.ps1' = Read-MatchedVersion 'installer\Installer-GUI.ps1' '\$script:bridgeVersion\s*=\s*''([^'']+)'''
    'Centre-Controle.ps1' = Read-MatchedVersion 'installer\Centre-Controle.ps1' '\$versionLabel\.Text\s*=\s*''Version\s+([^'']+)'''
    'ControlCenterBootstrap.cs' = Read-MatchedVersion 'installer\ControlCenterBootstrap.cs' 'AssemblyVersion\("([^"]+)\.0"\)'
    'SetupBootstrap.cs' = Read-MatchedVersion 'installer\SetupBootstrap.cs' 'AssemblyVersion\("([^"]+)\.0"\)'
    'README.md' = Read-MatchedVersion 'README.md' 'Version actuelle\s*:\s*\*\*([^*]+)\*\*'
    'INSTALLATION.md' = Read-MatchedVersion 'INSTALLATION.md' 'JellyfinVlcBridge-([0-9]+\.[0-9]+\.[0-9]+)-Setup\.exe'
}

$invalid = $versions.GetEnumerator() | Where-Object { $_.Value -ne $ExpectedVersion }
if ($invalid) {
    $details = ($invalid | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '
    throw "Versions incoherentes. Attendu $ExpectedVersion : $details"
}

$extensionVersion = Read-MatchedVersion 'browser-extension\manifest.json' '"version"\s*:\s*"([^"]+)"'
$extensionBuildVersion = Read-MatchedVersion 'tools\Build-ExtensionPackage.ps1' '\[string\]\$Version\s*=\s*''([^'']+)'''
if ($extensionVersion -ne $extensionBuildVersion) {
    throw "Versions de l'extension incoherentes : manifest=$extensionVersion, build=$extensionBuildVersion"
}

Write-Host "Versions coherentes : $ExpectedVersion"
Write-Host "Version extension coherente : $extensionVersion"
