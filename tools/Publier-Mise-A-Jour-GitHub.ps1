param(
    [string]$Repository = 'CrySer66/jellyfin-vlc-bridge',
    [string]$Version = '1.12.0'
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$workDirectory = Join-Path $projectDirectory 'work'
$stagingDirectory = Join-Path $workDirectory 'github-publish'

function Stop-WithMessage([string]$message) {
    Write-Host ''
    Write-Host $message -ForegroundColor Red
    Write-Host ''
    Read-Host 'Appuyez sur Entree pour fermer'
    exit 1
}

function Invoke-Checked([scriptblock]$command, [string]$failureMessage) {
    & $command
    if ($LASTEXITCODE -ne 0) { throw $failureMessage }
}

try {
    Write-Host ''
    Write-Host "=== Preparation de Jellyfin VLC Bridge $Version ===" -ForegroundColor Cyan
    Write-Host 'Aucun envoi ne sera effectue sans votre confirmation.'
    Write-Host ''

    if ($Version -notmatch '^\d+\.\d+\.\d+$') { Stop-WithMessage 'Le numero de version est invalide.' }
    foreach ($program in @('git', 'dotnet')) {
        if (-not (Get-Command $program -ErrorAction SilentlyContinue)) {
            Stop-WithMessage "$program est introuvable sur ce PC."
        }
    }

    Write-Host '[1/4] Verification du projet...' -ForegroundColor Yellow
    & (Join-Path $PSScriptRoot 'Test-VersionConsistency.ps1') -ExpectedVersion $Version
    & (Join-Path $PSScriptRoot 'Test-PowerShellSyntax.ps1')
    Invoke-Checked { dotnet restore (Join-Path $projectDirectory 'JellyfinVlcBridge.slnx') --configfile (Join-Path $projectDirectory 'NuGet.Config') } 'La restauration .NET a echoue.'
    Invoke-Checked { dotnet build (Join-Path $projectDirectory 'JellyfinVlcBridge.slnx') --configuration Release --no-restore } 'La compilation a echoue.'
    # Les tests n'ont pas besoin d'optimisation. Le mode Debug évite aussi certains
    # faux positifs antivirus rencontrés avec l'exécutable de simulation réseau optimisé.
    Invoke-Checked { dotnet run --project (Join-Path $projectDirectory 'tests\JellyfinVlcBridge.Tests') --configuration Debug --no-restore } 'Les tests ont echoue.'
    & (Join-Path $PSScriptRoot 'Build-WindowsRelease.ps1') -Version $Version

    Write-Host '[2/4] Preparation de la connexion Git...' -ForegroundColor Yellow
    & git credential-manager --version *> $null
    if ($LASTEXITCODE -ne 0) {
        Stop-WithMessage 'Le gestionnaire de connexion Git de Windows est introuvable. Reinstallez Git for Windows.'
    }
    $repositoryOwner = ($Repository -split '/', 2)[0]
    Write-Host 'Git demandera une autorisation dans le navigateur uniquement si elle est necessaire.'

    $resolvedWork = [IO.Path]::GetFullPath($workDirectory).TrimEnd('\') + '\'
    $resolvedStaging = [IO.Path]::GetFullPath($stagingDirectory)
    if (-not $resolvedStaging.StartsWith($resolvedWork, [StringComparison]::OrdinalIgnoreCase)) {
        Stop-WithMessage 'Le dossier temporaire de publication est inattendu.'
    }

    Write-Host '[3/4] Preparation des sources publiques...' -ForegroundColor Yellow
    if (-not (Test-Path -LiteralPath (Join-Path $resolvedStaging '.git'))) {
        New-Item -ItemType Directory -Path $workDirectory -Force | Out-Null
        Invoke-Checked { git clone "https://github.com/$Repository.git" $resolvedStaging } 'Impossible de recuperer le depot GitHub.'
    }

    Push-Location $resolvedStaging
    try {
        Invoke-Checked { git status --porcelain } 'Impossible de verifier le depot local.'
        if (& git status --porcelain) {
            Stop-WithMessage 'Le dossier temporaire contient deja des modifications. Rien n a ete ecrase.'
        }
        Invoke-Checked { git pull --ff-only origin main } 'Le depot local ne peut pas etre mis a jour proprement.'
        Invoke-Checked { git fetch origin --tags } 'Impossible de verifier les versions deja publiees.'
        $existingTag = & git tag --list "v$Version"
        if (-not [string]::IsNullOrWhiteSpace($existingTag)) {
            Stop-WithMessage "Le tag v$Version existe deja."
        }

        Write-Host ''
        Write-Host "Depot : https://github.com/$Repository" -ForegroundColor White
        Write-Host "Version : $Version" -ForegroundColor White
        Write-Host 'GitHub reconstruira lui-meme le Setup et le ZIP apres l envoi.'
        Write-Host ''
        $confirmation = Read-Host "Publier la version $Version sur GitHub ? O/N"
        if ($confirmation -notmatch '^[OoYy]$') {
            Write-Host 'Publication annulee. Aucun fichier n a ete modifie ni envoye.' -ForegroundColor Yellow
            Read-Host 'Appuyez sur Entree pour fermer'
            exit 0
        }

        Invoke-Checked { git rm -r --ignore-unmatch . } 'Impossible de preparer la copie publique.'

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
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
        }
        Invoke-Checked { git add --all } 'Impossible de preparer les modifications Git.'

        Write-Host ''
        & git diff --cached --stat

        & git config user.name $repositoryOwner
        & git config user.email "$repositoryOwner@users.noreply.github.com"
        Invoke-Checked { git commit -m "Preparer la version $Version" } 'Impossible de creer le commit.'
        Invoke-Checked { git push origin main } 'Le code source n a pas pu etre envoye.'
        Invoke-Checked { git tag -a "v$Version" -m "Jellyfin VLC Bridge $Version" } 'Impossible de creer le tag.'
        Invoke-Checked { git push origin "v$Version" } 'Le tag n a pas pu etre envoye.'
    } finally {
        Pop-Location
    }

    Write-Host '[4/4] Publication lancee.' -ForegroundColor Green
    Write-Host 'GitHub verifie le code puis fabrique automatiquement le Setup et le ZIP.'
    $actionsUrl = "https://github.com/$Repository/actions"
    Start-Process $actionsUrl
    Write-Host $actionsUrl
    Read-Host 'Appuyez sur Entree pour fermer'
} catch {
    Stop-WithMessage $_.Exception.Message
}
