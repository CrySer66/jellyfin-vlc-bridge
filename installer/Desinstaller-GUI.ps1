param(
    [switch]$TemporaryRun
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$localizationFile = Join-Path $scriptDirectory 'Localization.ps1'
if (Test-Path -LiteralPath $localizationFile) { . $localizationFile }

# Le script installé se trouve dans le dossier qu'il doit supprimer. Une copie
# temporaire évite que PowerShell ou son dossier de travail garde App verrouillé.
if (-not $TemporaryRun) {
    $temporaryDirectory = Join-Path $env:TEMP ('JellyfinVlcBridgeUninstall-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporaryDirectory -Force | Out-Null
    $temporaryScript = Join-Path $temporaryDirectory 'Desinstaller-GUI.ps1'
    Copy-Item -LiteralPath $MyInvocation.MyCommand.Path -Destination $temporaryScript -Force
    Copy-Item -LiteralPath $localizationFile -Destination (Join-Path $temporaryDirectory 'Localization.ps1') -Force

    $temporaryProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
    $temporaryProcessInfo.FileName = 'powershell.exe'
    $temporaryProcessInfo.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$temporaryScript`" -TemporaryRun"
    $temporaryProcessInfo.WorkingDirectory = $temporaryDirectory
    $temporaryProcessInfo.UseShellExecute = $false
    $temporaryProcessInfo.CreateNoWindow = $true
    $temporaryProcess = [System.Diagnostics.Process]::Start($temporaryProcessInfo)
    if ($null -eq $temporaryProcess) { throw (T 'CleanupStartFailed') }
    $temporaryProcess.Dispose()
    exit 0
}

# La copie est déjà chargée en mémoire ; elle peut se retirer immédiatement.
$currentTemporaryScript = $MyInvocation.MyCommand.Path
$currentTemporaryDirectory = Split-Path -Parent $currentTemporaryScript
Set-Location -LiteralPath $env:TEMP
Remove-Item -LiteralPath $currentTemporaryScript -Force -ErrorAction SilentlyContinue
if ((Split-Path -Leaf $currentTemporaryDirectory) -like 'JellyfinVlcBridgeUninstall-*') {
    Remove-Item -LiteralPath $currentTemporaryDirectory -Force -ErrorAction SilentlyContinue
}

Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

$choice = [System.Windows.Forms.MessageBox]::Show(
    (T 'UninstallQuestion'),
    (T 'UninstallTitle'),
    [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
    [System.Windows.Forms.MessageBoxIcon]::Question)

if ($choice -eq [System.Windows.Forms.DialogResult]::Cancel) { exit 0 }
$purge = $choice -eq [System.Windows.Forms.DialogResult]::Yes
$rootDirectory = Join-Path $env:LOCALAPPDATA 'JellyfinVlcBridge'
$installDirectory = Join-Path $rootDirectory 'App'
$executable = Join-Path $installDirectory 'jellyfin-vlc-bridge.exe'

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

try {
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
        Get-Process -Name 'jellyfin-vlc-bridge', 'jellyfin-vlc-bridge-control' -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $processPath = [IO.Path]::GetFullPath($_.Path)
                if ($processPath.StartsWith($actual + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
                    Stop-Process -Id $_.Id -Force -ErrorAction Stop
                }
            } catch { }
        }
        for ($attempt = 1; $attempt -le 10 -and (Test-Path $actual); $attempt++) {
            try { Remove-Item -LiteralPath $actual -Recurse -Force -ErrorAction Stop }
            catch {
                if ($attempt -eq 10) { throw }
                Start-Sleep -Milliseconds 500
            }
        }
    }

    if ($purge -and (Test-Path $rootDirectory)) {
        Remove-Item -LiteralPath $rootDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
    $completionMessage = T 'UninstallComplete'
    $completionIcon = 'Information'
    if (-not [string]::IsNullOrWhiteSpace($cleanupWarning)) {
        $completionMessage += "`r`n`r`n" + (T 'Warning' @($cleanupWarning))
        $completionIcon = 'Warning'
    }
    [System.Windows.Forms.MessageBox]::Show(
        $completionMessage,
        (T 'UninstallCompleteTitle'), 'OK', $completionIcon) | Out-Null
} catch {
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, (T 'UninstallErrorTitle'), 'OK', 'Error') | Out-Null
    exit 1
}
