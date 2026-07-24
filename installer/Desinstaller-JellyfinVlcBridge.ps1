$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDirectory 'Localization.ps1')

Write-Host ''
Write-Host (T 'UninstallConsoleHeader') -ForegroundColor Cyan
Write-Host ''
Write-Host (T 'UninstallConsoleQuestion')
Write-Host (T 'UninstallConsoleKeep')
Write-Host (T 'UninstallConsolePurge')
$answer = (Read-Host (T 'UninstallConsolePrompt')).Trim()
$purge = $answer -match '^(o|oui|y|yes)$'

$rootDirectory = Join-Path $env:LOCALAPPDATA 'JellyfinVlcBridge'
$installDirectory = Join-Path $rootDirectory 'App'
$executable = Join-Path $installDirectory 'jellyfin-vlc-bridge.exe'
# Ne jamais garder comme dossier de travail le répertoire que nous allons retirer.
Set-Location -LiteralPath $env:TEMP
if (-not (Test-Path $executable)) {
    $packageExecutable = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'jellyfin-vlc-bridge.exe'
    if (Test-Path $packageExecutable) { $executable = $packageExecutable }
}

function Invoke-BridgeCleanup([string]$path, [bool]$removeSettings) {
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $path
    $processInfo.Arguments = if ($removeSettings) { 'uninstall-cleanup --purge' } else { 'uninstall-cleanup' }
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    if (-not $process.Start()) { throw (T 'CleanupStartFailed') }
    $outputTask = $process.StandardOutput.ReadToEndAsync()
    $errorTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $output = $outputTask.GetAwaiter().GetResult().Trim()
    $errorOutput = $errorTask.GetAwaiter().GetResult().Trim()
    return [PSCustomObject]@{
        ExitCode = $process.ExitCode
        Output = $output
        Error = $errorOutput
    }
}

$cleanupWarning = $null
if (Test-Path $executable) {
    try {
        $cleanupResult = Invoke-BridgeCleanup $executable $purge
        if ($cleanupResult.ExitCode -ne 0) {
            $detail = if ([string]::IsNullOrWhiteSpace($cleanupResult.Error)) {
                "code $($cleanupResult.ExitCode)"
            } else {
                $cleanupResult.Error
            }
            $cleanupWarning = T 'CleanupIncomplete' @($detail)
        }
    } catch {
        $cleanupWarning = T 'CleanupIncomplete' @($_.Exception.Message)
    }
}

$expected = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'JellyfinVlcBridge\App'))
$actual = [IO.Path]::GetFullPath($installDirectory)
if ($actual -ne $expected) { throw (T 'UnsafeUninstallPath') }
if (Test-Path $actual) {
    # Chrome/Edge peut conserver temporairement un hote natif après la fermeture de VLC.
    # Ne terminer que les processus dont l'exécutable provient exactement de notre dossier.
    Get-Process -Name 'jellyfin-vlc-bridge', 'jellyfin-vlc-bridge-control' -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $processPath = [IO.Path]::GetFullPath($_.Path)
            if ($processPath.StartsWith($actual + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
                Stop-Process -Id $_.Id -Force -ErrorAction Stop
            }
        } catch {
            Write-Host "Processus deja termine ou inaccessible : $($_.Id)"
        }
    }

    $removed = $false
    for ($attempt = 1; $attempt -le 10 -and -not $removed; $attempt++) {
        try {
            Remove-Item -LiteralPath $actual -Recurse -Force -ErrorAction Stop
            $removed = $true
        } catch {
            if ($attempt -eq 10) { throw }
            Start-Sleep -Milliseconds 500
        }
    }
}

if ($purge -and (Test-Path $rootDirectory) -and -not (Get-ChildItem -LiteralPath $rootDirectory -Force)) {
    Remove-Item -LiteralPath $rootDirectory -Force
}

Write-Host ''
Write-Host (T 'ProgramRemoved') -ForegroundColor Green
if ($purge) { Write-Host (T 'SettingsRemoved') }
else { Write-Host (T 'SettingsKept') }
Write-Host ''
Write-Host (T 'RemoveExtensionLast') -ForegroundColor Yellow
if (-not [string]::IsNullOrWhiteSpace($cleanupWarning)) {
    Write-Warning $cleanupWarning
}
