param(
    [switch]$ValidateOnly,
    [switch]$StartInTray,
    [string]$ShowEventName = ''
)
$ErrorActionPreference = 'Stop'
$script:bridgeVersion = '1.19.0'
# Compatibility entry point for old shortcuts. The interface now lives entirely
# in the native WPF executable; PowerShell no longer draws or owns its windows.
$desktop = Join-Path $PSScriptRoot 'jellyfin-vlc-bridge-control.exe'
if (-not (Test-Path -LiteralPath $desktop)) { throw "Centre de contrôle absent : $desktop" }
$launch = @{ FilePath = $desktop; PassThru = $true }
if ($ValidateOnly) { $launch.ArgumentList = '--validate-only'; $launch.Wait = $true; $launch.WindowStyle = 'Hidden' }
elseif ($StartInTray) { $launch.ArgumentList = '--tray'; $launch.WindowStyle = 'Hidden' }
else { $launch.WindowStyle = 'Normal' }
$process = Start-Process @launch
if ($ValidateOnly) { exit $process.ExitCode }
