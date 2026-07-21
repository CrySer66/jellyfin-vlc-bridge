param(
    [string]$Version = '1.8.0'
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

$nativeProcess = New-HiddenProcess 'chrome-extension://hkjbodgdbjhignhlbecchiigcfigpidp/'
if (-not $nativeProcess.Start()) { throw 'Impossible de lancer le canal natif.' }
$payload = [Text.Encoding]::UTF8.GetBytes('{"type":"ping","extensionVersion":"1.3.0"}')
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
