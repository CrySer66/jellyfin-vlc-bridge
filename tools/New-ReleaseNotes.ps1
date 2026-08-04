param(
    [string]$Version = '',
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($Version)) {
    [xml]$props = Get-Content -LiteralPath (Join-Path $projectDirectory 'Directory.Build.props') -Raw -Encoding UTF8
    $Version = [string]$props.Project.PropertyGroup.Version
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version invalide : $Version" }

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $projectDirectory 'outputs\RELEASE_NOTES.md'
} elseif (-not [IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $projectDirectory $OutputPath
}

$changeLogPath = Join-Path $projectDirectory 'CHANGELOG.md'
$changeLog = Get-Content -LiteralPath $changeLogPath -Raw -Encoding UTF8
$heading = [regex]::Match(
    $changeLog,
    "(?m)^##\s+$([regex]::Escape($Version))\s+[^\r\n]*\r?\n")
if (-not $heading.Success) {
    throw "La section $Version est absente de CHANGELOG.md."
}

$sectionStart = $heading.Index + $heading.Length
$nextHeading = ([regex]::new('(?m)^##\s+')).Match($changeLog, $sectionStart)
$sectionLength = if ($nextHeading.Success) {
    $nextHeading.Index - $sectionStart
} else {
    $changeLog.Length - $sectionStart
}
$section = $changeLog.Substring($sectionStart, $sectionLength).Trim()
if ([string]::IsNullOrWhiteSpace($section) -or $section -notmatch '(?m)^-\s+') {
    throw "La section $Version de CHANGELOG.md ne contient aucune nouveaute."
}

# Les outils sont aussi executes par Windows PowerShell 5.1, qui peut lire un
# script UTF-8 sans BOM comme de l'ANSI. Construire les rares accents evite que
# les notes publiques contiennent un titre mal encode.
$eAcute = [char]0x00E9
$downloadsTitle = "T${eAcute}l${eAcute}chargements"
$recommended = "recommand${eAcute}"
$downloads = "t${eAcute}l${eAcute}chargements"

$notes = @"
## Jellyfin VLC Bridge $Version

$section

## $downloadsTitle

- ``JellyfinVlcBridge-$Version-Setup.exe`` : installateur Windows $recommended.
- ``JellyfinVlcBridge-$Version-win-x64.zip`` : archive Windows pour installation manuelle.
- ``SHA256SUMS.txt`` : empreintes SHA-256 des deux $downloads.
"@

$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$utf8WithoutBom = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText(
    [IO.Path]::GetFullPath($OutputPath),
    ($notes.TrimEnd() + "`n"),
    $utf8WithoutBom)

Write-Output ([IO.Path]::GetFullPath($OutputPath))
