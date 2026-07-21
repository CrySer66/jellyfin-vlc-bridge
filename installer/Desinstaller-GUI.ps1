$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

$choice = [System.Windows.Forms.MessageBox]::Show(
    "Voulez-vous aussi effacer la connexion Jellyfin enregistree ?`r`n`r`nOui : tout effacer et repartir a zero.`r`nNon : conserver la connexion pour une reinstallation.`r`nAnnuler : ne rien modifier.",
    'Desinstaller Jellyfin VLC Bridge',
    [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
    [System.Windows.Forms.MessageBoxIcon]::Question)

if ($choice -eq [System.Windows.Forms.DialogResult]::Cancel) { exit 0 }
$purge = $choice -eq [System.Windows.Forms.DialogResult]::Yes
$rootDirectory = Join-Path $env:LOCALAPPDATA 'JellyfinVlcBridge'
$installDirectory = Join-Path $rootDirectory 'App'
$executable = Join-Path $installDirectory 'jellyfin-vlc-bridge.exe'

try {
    if (Test-Path $executable) {
        if ($purge) { & $executable uninstall-cleanup --purge }
        else { & $executable uninstall-cleanup }
        if ($LASTEXITCODE -ne 0) { throw 'Le nettoyage du Bridge a echoue.' }
    }

    $expected = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'JellyfinVlcBridge\App'))
    $actual = [IO.Path]::GetFullPath($installDirectory)
    if ($actual -ne $expected) { throw 'Chemin de desinstallation inattendu.' }

    if (Test-Path $actual) {
        Get-Process -Name 'jellyfin-vlc-bridge' -ErrorAction SilentlyContinue | ForEach-Object {
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
    [System.Windows.Forms.MessageBox]::Show(
        "Jellyfin VLC Bridge a ete desinstalle.`r`n`r`nRetirez maintenant extension depuis Chrome ou Edge.",
        'Desinstallation terminee', 'OK', 'Information') | Out-Null
} catch {
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Erreur de desinstallation', 'OK', 'Error') | Out-Null
    exit 1
}
