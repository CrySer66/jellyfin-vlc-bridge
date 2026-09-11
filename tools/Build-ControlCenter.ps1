param([Parameter(Mandatory = $true)][string]$OutputDirectory)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$output = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $output -Force | Out-Null
$icon = Join-Path $projectDirectory 'assets\JellyfinVlcBridge.ico'
if (-not (Test-Path -LiteralPath $icon)) { & (Join-Path $PSScriptRoot 'Build-AppIcon.ps1') -OutputPath $icon }

# Reuse the installer translations at build time. The desktop executable embeds
# its own resources and never starts PowerShell to display the interface.
. (Join-Path $projectDirectory 'installer\Localization.ps1')
$extraStrings = Join-Path $projectDirectory 'installer\ControlCenter.strings.json'
if (Test-Path -LiteralPath $extraStrings) {
    $extra = Get-Content -LiteralPath $extraStrings -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($language in @('en', 'fr')) {
        foreach ($property in $extra.$language.PSObject.Properties) {
            $script:JvbMessages[$language][$property.Name] = $property.Value
        }
    }
}
$stringsPath = Join-Path $output 'ControlCenter.strings.build.json'
[IO.File]::WriteAllText($stringsPath, ($script:JvbMessages | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
$framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$compiler = Join-Path $framework 'csc.exe'
$desktop = Join-Path $output 'jellyfin-vlc-bridge-control.exe'
try {
    & $compiler /nologo /target:winexe /platform:x64 /codepage:65001 /optimize+ "/out:$desktop" `
        "/win32icon:$icon" "/win32manifest:$(Join-Path $projectDirectory 'installer\ControlCenter.manifest')" `
        /reference:System.dll /reference:System.Core.dll /reference:System.Xaml.dll `
        /reference:System.Web.Extensions.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll `
        "/reference:$(Join-Path $framework 'WPF\WindowsBase.dll')" `
        "/reference:$(Join-Path $framework 'WPF\PresentationCore.dll')" `
        "/reference:$(Join-Path $framework 'WPF\PresentationFramework.dll')" `
        "/resource:$(Join-Path $projectDirectory 'installer\ControlCenter.xaml'),ControlCenter.xaml" `
        "/resource:$(Join-Path $projectDirectory 'installer\DesktopTheme.xaml'),DesktopTheme.xaml" `
        "/resource:$stringsPath,ControlCenter.strings.json" "/resource:$icon,ControlCenter.ico" `
        (Join-Path $projectDirectory 'installer\ControlCenterBootstrap.cs') `
        (Join-Path $projectDirectory 'installer\ControlCenterWindow.cs') `
        (Join-Path $projectDirectory 'installer\ControlCenterServices.cs')
    if ($LASTEXITCODE -ne 0) { throw 'La compilation du centre de contrôle WPF a échoué.' }
    Copy-Item -LiteralPath (Join-Path $projectDirectory 'installer\ControlCenter.config') -Destination ($desktop + '.config') -Force
} finally {
    if (Test-Path -LiteralPath $stringsPath) { Remove-Item -LiteralPath $stringsPath -Force }
}
Write-Host "Centre de contrôle WPF : $desktop"
