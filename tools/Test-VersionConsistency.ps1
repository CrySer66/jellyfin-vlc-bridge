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
    'Centre-Controle.ps1' = Read-MatchedVersion 'installer\Centre-Controle.ps1' '\$script:bridgeVersion\s*=\s*''([^'']+)'''
    'ControlCenterBootstrap.cs' = Read-MatchedVersion 'installer\ControlCenterBootstrap.cs' 'AssemblyVersion\("([^"]+)\.0"\)'
    'SetupBootstrap.cs' = Read-MatchedVersion 'installer\SetupBootstrap.cs' 'AssemblyVersion\("([^"]+)\.0"\)'
    'README.md' = Read-MatchedVersion 'README.md' '\|\s*\*\*([0-9]+\.[0-9]+\.[0-9]+)\*\*\s*\|\s*\*\*Windows'
    'README.en.md' = Read-MatchedVersion 'README.en.md' '\|\s*\*\*([0-9]+\.[0-9]+\.[0-9]+)\*\*\s*\|\s*\*\*Windows'
}

$invalid = $versions.GetEnumerator() | Where-Object { $_.Value -ne $ExpectedVersion }
if ($invalid) {
    $details = ($invalid | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '
    throw "Versions incoherentes. Attendu $ExpectedVersion : $details"
}

$extensionVersion = Read-MatchedVersion 'browser-extension\manifest.json' '"version"\s*:\s*"([^"]+)"'
$extensionBuildVersion = Read-MatchedVersion 'tools\Build-ExtensionPackage.ps1' '\[string\]\$Version\s*=\s*''([^'']+)'''
$extensionPackageTestVersion = Read-MatchedVersion 'tools\Test-ExtensionPackage.ps1' '\[string\]\$Version\s*=\s*''([^'']+)'''
if ($extensionVersion -ne $extensionBuildVersion -or $extensionVersion -ne $extensionPackageTestVersion) {
    throw "Versions de l'extension incoherentes : manifest=$extensionVersion, build=$extensionBuildVersion, test=$extensionPackageTestVersion"
}

$extensionDocumentationVersions = [ordered]@{
    'README.md' = Read-MatchedVersion 'README.md' 'Chrome Web Store\s+([0-9]+\.[0-9]+\.[0-9]+)'
    'README.en.md' = Read-MatchedVersion 'README.en.md' 'Chrome Web Store\s+([0-9]+\.[0-9]+\.[0-9]+)'
}
$invalidExtensionDocumentation = $extensionDocumentationVersions.GetEnumerator() |
    Where-Object { $_.Value -ne $extensionVersion }
if ($invalidExtensionDocumentation) {
    $details = ($invalidExtensionDocumentation | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '
    throw "Version d extension incoherente dans la documentation. Attendu $extensionVersion : $details"
}

$changeLog = Get-Content -LiteralPath (Join-Path $projectDirectory 'CHANGELOG.md') -Raw -Encoding UTF8
if ($changeLog -notmatch [regex]::Escape("## $ExpectedVersion ") -or
    $changeLog -notmatch [regex]::Escape("## Extension Chrome $extensionVersion ")) {
    throw "Le CHANGELOG ne decrit pas les versions courantes $ExpectedVersion et $extensionVersion."
}

foreach ($requiredFile in @('SECURITY.md', 'CONTRIBUTING.md', 'INSTALLATION.en.md', '.github\dependabot.yml')) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectDirectory $requiredFile) -PathType Leaf)) {
        throw "Fichier public requis introuvable : $requiredFile"
    }
}

Write-Host "Versions coherentes : $ExpectedVersion"
Write-Host "Version extension coherente : $extensionVersion"
