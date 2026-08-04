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
    $OutputPath = Join-Path $projectDirectory 'outputs\SHA256SUMS.txt'
} elseif (-not [IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $projectDirectory $OutputPath
}

$assets = @(
    (Join-Path $projectDirectory "outputs\JellyfinVlcBridge-$Version-Setup.exe")
    (Join-Path $projectDirectory "outputs\JellyfinVlcBridge-$Version-win-x64.zip")
)

foreach ($asset in $assets) {
    if (-not (Test-Path -LiteralPath $asset -PathType Leaf)) {
        throw "Fichier de Release absent : $asset"
    }
}

$lines = $assets |
    Sort-Object { [IO.Path]::GetFileName($_) } |
    ForEach-Object {
        $hash = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $([IO.Path]::GetFileName($_))"
    }

$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$utf8WithoutBom = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText(
    [IO.Path]::GetFullPath($OutputPath),
    (($lines -join "`n") + "`n"),
    $utf8WithoutBom)

Write-Output ([IO.Path]::GetFullPath($OutputPath))
