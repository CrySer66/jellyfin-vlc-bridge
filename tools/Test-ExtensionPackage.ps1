param(
    [string]$Version = '1.8.0'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$projectDirectory = Split-Path -Parent $PSScriptRoot
$outputsDirectory = Join-Path $projectDirectory 'outputs'
$localPackage = Join-Path $outputsDirectory "JellyfinVlcBridge-Extension-$Version-Local.zip"
$storePackage = Join-Path $outputsDirectory "JellyfinVlcBridge-Extension-$Version-ChromeWebStore.zip"
$requiredEntries = @(
    'manifest.json',
    'background.js',
    'content.js',
    'content.css',
    'shared.js',
    'i18n.js',
    'popup.html',
    'popup.js',
    'popup.css',
    '_locales/en/messages.json',
    '_locales/fr/messages.json',
    'icons/icon128.png'
)

function Test-Package([string]$path, [bool]$expectKey) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Paquet d'extension manquant : $path"
    }

    $archive = [IO.Compression.ZipFile]::OpenRead($path)
    try {
        $entries = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
        foreach ($required in $requiredEntries) {
            if ($entries -notcontains $required) {
                throw "Fichier manquant dans $([IO.Path]::GetFileName($path)) : $required"
            }
        }
        if ($entries | Where-Object { $_ -match '(^|/)(outputs|work|\.git)(/|$)' }) {
            throw "Le paquet contient un dossier interne interdit : $path"
        }

        $manifestEntry = $archive.GetEntry('manifest.json')
        $reader = [IO.StreamReader]::new($manifestEntry.Open(), [Text.Encoding]::UTF8)
        try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json }
        finally { $reader.Dispose() }

        if ($manifest.version -ne $Version) {
            throw "Version inattendue dans le paquet : $($manifest.version)"
        }
        $hasKey = $null -ne $manifest.PSObject.Properties['key']
        if ($hasKey -ne $expectKey) {
            throw "Champ key inattendu dans $([IO.Path]::GetFileName($path))."
        }
        if ($manifest.permissions -notcontains 'nativeMessaging') {
            throw 'Autorisation nativeMessaging absente du manifeste.'
        }
    }
    finally { $archive.Dispose() }
}

Test-Package $localPackage $true
Write-Host 'OK  Paquet local avec identifiant de developpement stable'
Test-Package $storePackage $false
Write-Host 'OK  Paquet Chrome Web Store sans champ key'
Write-Host "Paquets extension $Version valides."
