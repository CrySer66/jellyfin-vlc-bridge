$ErrorActionPreference = 'Stop'

Write-Host ''
Write-Host '=== Desinstallation de Jellyfin VLC Bridge ===' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Voulez-vous aussi effacer la connexion Jellyfin enregistree ?'
Write-Host '  N = conserver la connexion pour une future reinstallation (recommande)'
Write-Host '  O = tout effacer et repartir completement a zero'
$answer = (Read-Host 'Tout effacer ? O/N').Trim()
$purge = $answer -match '^(o|oui|y|yes)$'

$rootDirectory = Join-Path $env:LOCALAPPDATA 'JellyfinVlcBridge'
$installDirectory = Join-Path $rootDirectory 'App'
$executable = Join-Path $installDirectory 'jellyfin-vlc-bridge.exe'
if (-not (Test-Path $executable)) {
    $packageExecutable = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'jellyfin-vlc-bridge.exe'
    if (Test-Path $packageExecutable) { $executable = $packageExecutable }
}

if (Test-Path $executable) {
    if ($purge) { & $executable uninstall-cleanup --purge }
    else { & $executable uninstall-cleanup }
    if ($LASTEXITCODE -ne 0) { throw 'Le nettoyage du Bridge a echoue.' }
}

$expected = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'JellyfinVlcBridge\App'))
$actual = [IO.Path]::GetFullPath($installDirectory)
if ($actual -ne $expected) { throw 'Chemin de desinstallation inattendu, arret de securite.' }
if (Test-Path $actual) {
    # Chrome/Edge peut conserver temporairement un hote natif après la fermeture de VLC.
    # Ne terminer que les processus dont l'exécutable provient exactement de notre dossier.
    Get-Process -Name 'jellyfin-vlc-bridge' -ErrorAction SilentlyContinue | ForEach-Object {
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
Write-Host 'Le programme et les associations Windows ont ete retires.' -ForegroundColor Green
if ($purge) { Write-Host 'La configuration et le jeton ont aussi ete effaces.' }
else { Write-Host 'La configuration est conservee et sera reutilisee automatiquement.' }
Write-Host ''
Write-Host 'Derniere action : retirez manuellement extension Jellyfin VLC Bridge dans Chrome/Edge.' -ForegroundColor Yellow
