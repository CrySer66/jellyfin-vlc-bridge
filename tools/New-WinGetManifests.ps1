param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$InstallerSha256,

    [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
    [string]$ReleaseDate = [DateTime]::UtcNow.ToString('yyyy-MM-dd'),

    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$templateDirectory = Join-Path $projectDirectory 'packaging\winget\templates'

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectDirectory "outputs\winget\CrySer66.JellyfinVlcBridge\$Version"
} elseif (-not [IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectDirectory $OutputDirectory
}

$templates = Get-ChildItem -LiteralPath $templateDirectory -Filter '*.yaml.template' -File
if ($templates.Count -ne 4) {
    throw "Quatre modeles WinGet sont attendus dans $templateDirectory."
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$utf8WithoutBom = New-Object Text.UTF8Encoding($false)
foreach ($template in $templates) {
    $content = Get-Content -LiteralPath $template.FullName -Raw -Encoding UTF8
    $content = $content.Replace('{{VERSION}}', $Version)
    $content = $content.Replace('{{INSTALLER_SHA256}}', $InstallerSha256.ToUpperInvariant())
    $content = $content.Replace('{{RELEASE_DATE}}', $ReleaseDate)
    if ($content -match '\{\{[^}]+\}\}') {
        throw "Marqueur WinGet non remplace dans $($template.Name)."
    }

    $targetName = $template.Name.Substring(0, $template.Name.Length - '.template'.Length)
    $targetPath = Join-Path $OutputDirectory $targetName
    [IO.File]::WriteAllText($targetPath, ($content.TrimEnd() + "`n"), $utf8WithoutBom)
}

Write-Output ([IO.Path]::GetFullPath($OutputDirectory))
