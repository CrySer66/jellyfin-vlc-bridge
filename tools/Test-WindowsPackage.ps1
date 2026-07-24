param(
    [string]$Version = '1.13.0'
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$packageDirectory = Join-Path $projectDirectory "outputs\JellyfinVlcBridge-$Version-win-x64"
$executable = Join-Path $packageDirectory 'jellyfin-vlc-bridge.exe'
$setup = Join-Path $projectDirectory "outputs\JellyfinVlcBridge-$Version-Setup.exe"
$zip = Join-Path $projectDirectory "outputs\JellyfinVlcBridge-$Version-win-x64.zip"

foreach ($path in @($executable, $setup, $zip)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Fichier de paquet manquant : $path" }
}

$localizationPath = Join-Path $packageDirectory 'Localization.ps1'
if (-not (Test-Path -LiteralPath $localizationPath)) {
    throw 'Le module de traduction est absent du paquet Windows.'
}
$packagedScripts = Get-ChildItem -LiteralPath $packageDirectory -Filter '*.ps1' -File
foreach ($packagedScript in $packagedScripts) {
    $scriptBytes = [IO.File]::ReadAllBytes($packagedScript.FullName)
    $hasUtf8Bom = $scriptBytes.Length -ge 3 -and
        $scriptBytes[0] -eq 0xEF -and $scriptBytes[1] -eq 0xBB -and $scriptBytes[2] -eq 0xBF
    if (-not $hasUtf8Bom) {
        throw "Le script $($packagedScript.Name) n'est pas encodé en UTF-8 compatible avec Windows PowerShell."
    }
}
Write-Host 'OK  Accents UTF-8 compatibles avec Windows PowerShell'

$localizationScript = Get-Content -LiteralPath $localizationPath -Raw -Encoding UTF8
if ($localizationScript -notmatch 'LanguageAuto' -or
    $localizationScript -notmatch 'LanguageFrench' -or
    $localizationScript -notmatch 'LanguageEnglish') {
    throw 'Les traductions française et anglaise sont incomplètes.'
}
Write-Host 'OK  Traductions française et anglaise incluses'

function Read-Exactly([IO.Stream]$stream, [byte[]]$buffer) {
    $offset = 0
    while ($offset -lt $buffer.Length) {
        $read = $stream.Read($buffer, $offset, $buffer.Length - $offset)
        if ($read -eq 0) { throw 'Le processus a ferme sa sortie avant la reponse complete.' }
        $offset += $read
    }
}

function New-HiddenProcess([string]$arguments) {
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $executable
    $startInfo.Arguments = $arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    return New-Object Diagnostics.Process -Property @{ StartInfo = $startInfo }
}

# Une application Windows graphique utilise le sous-systeme PE 2. Le sous-systeme 3
# afficherait une console, ce qui recreerait la fenetre CMD pendant une serie.
$bytes = [IO.File]::ReadAllBytes($executable)
$peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
$subsystem = [BitConverter]::ToUInt16($bytes, $peOffset + 24 + 68)
if ($subsystem -ne 2) { throw "Sous-systeme Windows inattendu : $subsystem (attendu : 2)." }
Write-Host 'OK  Application Windows sans console'

$versionProcess = New-HiddenProcess 'version'
if (-not $versionProcess.Start()) { throw 'Impossible de lancer la commande version.' }
$versionProcess.StandardInput.Close()
$versionOutput = $versionProcess.StandardOutput.ReadToEnd().Trim()
$versionError = $versionProcess.StandardError.ReadToEnd().Trim()
$versionProcess.WaitForExit()
if ($versionProcess.ExitCode -ne 0 -or $versionOutput -ne "Jellyfin VLC Bridge $Version") {
    throw "Commande version invalide. Sortie='$versionOutput' Erreur='$versionError'"
}
Write-Host "OK  Version redirigee : $versionOutput"

$statusProcess = New-HiddenProcess 'status --json'
if (-not $statusProcess.Start()) { throw 'Impossible de lancer le diagnostic redirige.' }
$statusProcess.StandardInput.Close()
$statusOutput = $statusProcess.StandardOutput.ReadToEnd().Trim()
$statusError = $statusProcess.StandardError.ReadToEnd().Trim()
$statusProcess.WaitForExit()
if ($statusProcess.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($statusOutput)) {
    throw "Diagnostic redirige invalide. Sortie='$statusOutput' Erreur='$statusError'"
}
$status = $statusOutput | ConvertFrom-Json
if ($status.version -ne $Version) { throw "Version de diagnostic inattendue : $($status.version)" }
Write-Host 'OK  Diagnostic JSON redirige pour le centre de controle'

$controlScript = Get-Content -LiteralPath (Join-Path $packageDirectory 'Centre-Controle.ps1') -Raw
if ($controlScript -notmatch 'RedirectStandardOutput\s*=\s*\$true' -or
    $controlScript -notmatch 'StandardOutput\.ReadToEnd\(\)' -or
    $controlScript -notmatch 'Set-JvbLanguagePreference') {
    throw 'Le centre de controle ne capture pas explicitement le diagnostic de l application graphique.'
}
Write-Host 'OK  Centre de controle compatible avec l application sans console'

$uninstallerScript = Get-Content -LiteralPath (Join-Path $packageDirectory 'Desinstaller-GUI.ps1') -Raw
if ($uninstallerScript -match '&\s+\$executable\s+uninstall-cleanup' -or
    $uninstallerScript -notmatch 'ProcessStartInfo' -or
    $uninstallerScript -notmatch 'WaitForExit\(\)' -or
    $uninstallerScript -notmatch '\.ExitCode' -or
    $uninstallerScript -notmatch 'jellyfin-vlc-bridge-control' -or
    $uninstallerScript -notmatch 'JellyfinVlcBridgeUninstall-' -or
    $uninstallerScript -notmatch 'TemporaryRun' -or
    $uninstallerScript -notmatch 'Set-Location\s+-LiteralPath\s+\$env:TEMP') {
    throw 'Le desinstallateur ne gere pas correctement application graphique ou centre de controle.'
}
$installerScript = Get-Content -LiteralPath (Join-Path $packageDirectory 'Installer-GUI.ps1') -Raw
if ($installerScript -notmatch '\$uninstallShortcut\.WorkingDirectory\s*=\s*\$env:TEMP') {
    throw 'Le raccourci de desinstallation conserve encore le dossier application comme repertoire de travail.'
}
Write-Host 'OK  Desinstallation executee hors du dossier supprime et sans faux code erreur'

$nativeProcess = New-HiddenProcess 'chrome-extension://hkjbodgdbjhignhlbecchiigcfigpidp/'
if (-not $nativeProcess.Start()) { throw 'Impossible de lancer le canal natif.' }
$payload = [Text.Encoding]::UTF8.GetBytes('{"type":"ping","extensionVersion":"1.7.0"}')
$nativeProcess.StandardInput.BaseStream.Write([BitConverter]::GetBytes([int]$payload.Length), 0, 4)
$nativeProcess.StandardInput.BaseStream.Write($payload, 0, $payload.Length)
$nativeProcess.StandardInput.BaseStream.Flush()
$nativeProcess.StandardInput.Close()

$lengthBytes = New-Object byte[] 4
try {
    Read-Exactly $nativeProcess.StandardOutput.BaseStream $lengthBytes
} catch {
    $earlyNativeError = $nativeProcess.StandardError.ReadToEnd().Trim()
    $nativeProcess.WaitForExit()
    throw "Aucune reponse native. Erreur='$earlyNativeError'"
}
$responseLength = [BitConverter]::ToInt32($lengthBytes, 0)
if ($responseLength -le 0 -or $responseLength -gt 1048576) { throw "Longueur de reponse native invalide : $responseLength" }
$responseBytes = New-Object byte[] $responseLength
Read-Exactly $nativeProcess.StandardOutput.BaseStream $responseBytes
$nativeResponse = [Text.Encoding]::UTF8.GetString($responseBytes) | ConvertFrom-Json
$nativeError = $nativeProcess.StandardError.ReadToEnd().Trim()
$nativeProcess.WaitForExit()
if ($nativeProcess.ExitCode -ne 0 -or -not $nativeResponse.accepted -or $nativeResponse.type -ne 'pong' -or $nativeResponse.bridgeVersion -ne $Version) {
    throw "Dialogue natif invalide. Reponse='$($nativeResponse | ConvertTo-Json -Compress)' Erreur='$nativeError'"
}
Write-Host 'OK  Dialogue natif Chrome conserve'

$forbiddenFiles = @(
    'jellyfin-vlc-bridge.dll',
    'jellyfin-vlc-bridge.deps.json',
    'jellyfin-vlc-bridge.runtimeconfig.json',
    'JellyfinVlcBridge.Core.dll',
    'hostfxr.dll',
    'coreclr.dll'
)
foreach ($file in $forbiddenFiles) {
    if (Test-Path -LiteralPath (Join-Path $packageDirectory $file)) {
        throw "Le paquet autonome contient encore un fichier separe inutile : $file"
    }
}
Write-Host 'OK  Application autonome en un seul fichier'
Write-Host "Paquet Windows $Version valide."
