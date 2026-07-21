param(
    [string]$Repository = 'CrySer66/jellyfin-vlc-bridge',
    [string]$Version = '1.6.1'
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$outputsDirectory = Join-Path $projectDirectory 'outputs'
$workDirectory = Join-Path $projectDirectory 'work'
$stagingDirectory = Join-Path $workDirectory 'github-publish'
$setupFile = Join-Path $outputsDirectory "JellyfinVlcBridge-$Version-Setup.exe"
$portableFile = Join-Path $outputsDirectory "JellyfinVlcBridge-$Version-win-x64.zip"

function Stop-WithMessage([string]$message) {
    Write-Host ''
    Write-Host $message -ForegroundColor Red
    Write-Host ''
    Read-Host 'Appuyez sur Entree pour fermer'
    exit 1
}

try {
    Write-Host ''
    Write-Host '=== Publication officielle de Jellyfin VLC Bridge ===' -ForegroundColor Cyan
    Write-Host ''

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Stop-WithMessage 'Git est introuvable sur ce PC.'
    }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Stop-WithMessage 'GitHub CLI est introuvable sur ce PC.'
    }
    if (-not (Test-Path -LiteralPath $setupFile) -or -not (Test-Path -LiteralPath $portableFile)) {
        Stop-WithMessage 'Les deux fichiers de la version Windows sont introuvables dans outputs.'
    }

    & gh auth status *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Une autorisation GitHub est necessaire.' -ForegroundColor Yellow
        Write-Host 'Une page GitHub va s ouvrir. Autorisez GitHub CLI, puis revenez ici.'
        & gh auth login -h github.com -p https -w
        if ($LASTEXITCODE -ne 0) { Stop-WithMessage 'La connexion GitHub n a pas abouti.' }
    }
    & gh auth setup-git
    if ($LASTEXITCODE -ne 0) { Stop-WithMessage 'GitHub n a pas pu configurer la connexion Git.' }

    $resolvedWork = [IO.Path]::GetFullPath($workDirectory).TrimEnd('\') + '\'
    $resolvedStaging = [IO.Path]::GetFullPath($stagingDirectory)
    if (-not $resolvedStaging.StartsWith($resolvedWork, [StringComparison]::OrdinalIgnoreCase)) {
        Stop-WithMessage 'Le dossier temporaire de publication est inattendu.'
    }
    if (Test-Path -LiteralPath $resolvedStaging) {
        Remove-Item -LiteralPath $resolvedStaging -Recurse -Force
    }
    New-Item -ItemType Directory -Path $resolvedStaging -Force | Out-Null

    $excludedDirectories = @('.git', '.agents', '.codex', '.vs', '.vscode', '.idea', 'bin', 'obj', 'outputs', 'publish', 'TestResults', 'work')
    $excludedNames = @('config.json', 'native-messaging-host.json')
    $sourceFiles = Get-ChildItem -LiteralPath $projectDirectory -Recurse -File -Force | Where-Object {
        $relative = $_.FullName.Substring($projectDirectory.Length).TrimStart('\')
        $parts = $relative -split '\\'
        -not ($parts | Where-Object { $excludedDirectories -contains $_ }) -and
        $excludedNames -notcontains $_.Name -and
        $_.Extension -notin @('.exe', '.dll', '.pdb', '.zip', '.crx', '.log', '.token', '.secret')
    }

    foreach ($file in $sourceFiles) {
        $relative = $file.FullName.Substring($projectDirectory.Length).TrimStart('\')
        $destination = Join-Path $resolvedStaging $relative
        $parent = Split-Path -Parent $destination
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
    }

    Push-Location $resolvedStaging
    try {
        & git init -b main
        if ($LASTEXITCODE -ne 0) { Stop-WithMessage 'Impossible de preparer le depot Git local.' }
        $login = (& gh api user --jq .login).Trim()
        if (-not $login) { Stop-WithMessage 'Le nom du compte GitHub est introuvable.' }
        & git config user.name $login
        & git config user.email "$login@users.noreply.github.com"
        & git add --all
        & git commit -m "Publication initiale $Version"
        if ($LASTEXITCODE -ne 0) { Stop-WithMessage 'Impossible de creer la publication locale.' }
        & git remote add origin "https://github.com/$Repository.git"

        Write-Host ''
        Write-Host "Depot public : https://github.com/$Repository" -ForegroundColor White
        Write-Host "Fichiers sources : $($sourceFiles.Count)" -ForegroundColor White
        $confirmation = Read-Host 'Publier maintenant le code et la version Windows ? O/N'
        if ($confirmation -notmatch '^[OoYy]$') {
            Write-Host 'Publication annulee. Aucun fichier n a ete envoye.' -ForegroundColor Yellow
            Read-Host 'Appuyez sur Entree pour fermer'
            exit 0
        }

        & git push -u origin main
        if ($LASTEXITCODE -ne 0) { Stop-WithMessage 'Le code source n a pas pu etre envoye sur GitHub.' }
    } finally {
        Pop-Location
    }

    $releaseNotes = @"
Premiere version publique de Jellyfin VLC Bridge.

- installation Windows graphique avec Quick Connect ;
- lecture HTTP Direct Play ou SMB dans VLC ;
- reprise et synchronisation de progression Jellyfin ;
- enchainement automatique des episodes ;
- centre de controle, diagnostic, reparation et mises a jour.

Installez VLC, telechargez le fichier Setup.exe, puis suivez l assistant.
"@
    & gh release create "v$Version" $setupFile $portableFile --repo $Repository --title "Jellyfin VLC Bridge $Version" --notes $releaseNotes --target main
    if ($LASTEXITCODE -ne 0) { Stop-WithMessage 'Le code est publie, mais la Release GitHub n a pas pu etre creee.' }

    Write-Host ''
    Write-Host 'Publication terminee avec succes.' -ForegroundColor Green
    Write-Host "https://github.com/$Repository/releases/tag/v$Version"
    Start-Process "https://github.com/$Repository/releases/tag/v$Version"
    Read-Host 'Appuyez sur Entree pour fermer'
} catch {
    Stop-WithMessage $_.Exception.Message
}
