param(
    [string]$Repository = 'CrySer66/jellyfin-vlc-bridge',
    [string]$Version = '',
    [switch]$ValidateOnly,
    [switch]$AllowWorkflowChanges,
    [switch]$KeepTemporaryFiles,
    [switch]$NoPause,
    [ValidateRange(5, 60)]
    [int]$TimeoutMinutes = 25
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$workDirectory = Join-Path $projectDirectory 'work'
$stagingDirectory = $null
$publicationSucceeded = $false
$tag = $null

function Complete-Script([int]$exitCode) {
    if (-not $NoPause) {
        Write-Host ''
        Read-Host 'Appuyez sur Entree pour fermer' | Out-Null
    }
    exit $exitCode
}

function Invoke-Checked([scriptblock]$command, [string]$failureMessage) {
    & $command
    if ($LASTEXITCODE -ne 0) { throw $failureMessage }
}

function Get-ProjectVersion {
    $propsPath = Join-Path $projectDirectory 'Directory.Build.props'
    [xml]$props = Get-Content -Raw -LiteralPath $propsPath
    $value = [string]$props.Project.PropertyGroup.Version
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw 'Le numero de version est introuvable dans Directory.Build.props.'
    }
    return $value.Trim()
}

function Assert-Program([string]$name, [string]$displayName) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "$displayName est introuvable sur ce PC."
    }
}

function Invoke-LocalValidation {
    Write-Host '[1/6] Verification complete du projet...' -ForegroundColor Yellow
    & (Join-Path $PSScriptRoot 'Test-VersionConsistency.ps1') -ExpectedVersion $Version

    & (Join-Path $PSScriptRoot 'Test-PowerShellSyntax.ps1')

    Invoke-Checked {
        dotnet restore (Join-Path $projectDirectory 'JellyfinVlcBridge.slnx') --configfile (Join-Path $projectDirectory 'NuGet.Config')
    } 'La restauration .NET a echoue.'
    Invoke-Checked {
        dotnet build (Join-Path $projectDirectory 'JellyfinVlcBridge.slnx') --configuration Release --no-restore
    } 'La compilation a echoue.'
    Invoke-Checked {
        dotnet run --project (Join-Path $projectDirectory 'tests\JellyfinVlcBridge.Tests') --configuration Debug --no-restore
    } 'Les tests du Bridge ont echoue.'

    Invoke-Checked {
        node --check (Join-Path $projectDirectory 'browser-extension\background.js')
    } 'Le service de fond de l extension contient une erreur JavaScript.'
    Invoke-Checked {
        node --check (Join-Path $projectDirectory 'browser-extension\content.js')
    } 'Le script injecte dans Jellyfin contient une erreur JavaScript.'
    Invoke-Checked {
        node (Join-Path $projectDirectory 'tests\extension-tests.js')
    } 'Les tests de l extension Chrome ont echoue.'

    $appDataBeforeBuild = $env:APPDATA
    & (Join-Path $PSScriptRoot 'Build-WindowsRelease.ps1') -Version $Version
    if ($env:APPDATA -ne $appDataBeforeBuild) {
        $env:APPDATA = $appDataBeforeBuild
        throw 'La construction a modifie la session Windows. La valeur APPDATA a ete restauree par securite.'
    }

    & (Join-Path $PSScriptRoot 'New-ReleaseChecksums.ps1') -Version $Version | Out-Null
    & (Join-Path $PSScriptRoot 'New-ReleaseNotes.ps1') -Version $Version | Out-Null
    & (Join-Path $PSScriptRoot 'Test-ReleaseMetadata.ps1') -Version $Version

    foreach ($asset in @(
        (Join-Path $projectDirectory "outputs\JellyfinVlcBridge-$Version-Setup.exe"),
        (Join-Path $projectDirectory "outputs\JellyfinVlcBridge-$Version-win-x64.zip"),
        (Join-Path $projectDirectory 'outputs\SHA256SUMS.txt'),
        (Join-Path $projectDirectory 'outputs\RELEASE_NOTES.md')
    )) {
        if (-not (Test-Path -LiteralPath $asset -PathType Leaf) -or (Get-Item -LiteralPath $asset).Length -le 0) {
            throw "Le fichier attendu n a pas ete cree : $asset"
        }
    }
}

function Assert-GitHubConnection([switch]$ReadOnly) {
    Write-Host '[2/6] Verification de la connexion GitHub...' -ForegroundColor Yellow
    $accountName = & gh api user --jq '.login' 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($accountName | Out-String))) {
        throw @'
GitHub CLI n est pas connecte dans cette session Windows.

Executez une seule fois :
  gh auth login --hostname github.com --git-protocol https --web

Puis relancez ce script.
'@
    }
    Write-Host "Compte GitHub detecte : $(($accountName | Out-String).Trim())" -ForegroundColor Green

    Invoke-Checked {
        gh repo view $Repository --json nameWithOwner --jq '.nameWithOwner'
    } "Le depot GitHub $Repository est inaccessible avec ce compte."

    if (-not $ReadOnly) {
        # Git et GitHub CLI utilisent ainsi la meme connexion Windows.
        Invoke-Checked { gh auth setup-git } 'GitHub CLI n a pas pu configurer la connexion de Git.'
    }
}

function Get-ReleaseState {
    $json = & gh release view $tag --repo $Repository --json url,assets 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($json | Out-String))) {
        return $null
    }
    return (($json | Out-String) | ConvertFrom-Json)
}

function Test-ReleaseComplete($release) {
    if ($null -eq $release) { return $false }
    $assetNames = @($release.assets | ForEach-Object { $_.name })
    return (
        $assetNames -contains "JellyfinVlcBridge-$Version-Setup.exe" -and
        $assetNames -contains "JellyfinVlcBridge-$Version-win-x64.zip" -and
        $assetNames -contains 'SHA256SUMS.txt'
    )
}

function Wait-ForRelease {
    Write-Host '[6/6] Verification des telechargements publics...' -ForegroundColor Yellow
    $deadline = [DateTimeOffset]::Now.AddMinutes($TimeoutMinutes)
    $lastMessage = [DateTimeOffset]::MinValue

    while ([DateTimeOffset]::Now -lt $deadline) {
        $release = Get-ReleaseState
        if (Test-ReleaseComplete $release) {
            Write-Host ''
            Write-Host 'Publication confirmee : le Setup, le ZIP et leurs empreintes sont disponibles.' -ForegroundColor Green
            Write-Host $release.url
            Write-Host "https://github.com/$Repository/releases/download/$tag/JellyfinVlcBridge-$Version-Setup.exe"
            Write-Host "https://github.com/$Repository/releases/download/$tag/JellyfinVlcBridge-$Version-win-x64.zip"
            Write-Host "https://github.com/$Repository/releases/download/$tag/SHA256SUMS.txt"
            return
        }

        if (([DateTimeOffset]::Now - $lastMessage).TotalSeconds -ge 30) {
            Write-Host 'GitHub construit encore les fichiers. Nouvelle verification automatique...'
            $lastMessage = [DateTimeOffset]::Now
        }
        Start-Sleep -Seconds 10
    }

    $incompleteRelease = Get-ReleaseState
    if ($null -ne $incompleteRelease) {
        throw "La Release $tag existe mais reste incomplete. Consultez le workflow GitHub : elle ne sera jamais ecrasee automatiquement."
    }
    throw "GitHub n a pas termine dans les $TimeoutMinutes minutes. Relancez le script pour reprendre la verification du tag existant."
}

function Get-PullRequestState([int]$number) {
    $json = & gh pr view $number --repo $Repository --json state,mergeable,mergeStateStatus,statusCheckRollup,mergeCommit,url
    if ($LASTEXITCODE -ne 0) {
        throw "Impossible de lire l etat de la Pull Request #$number."
    }
    return (($json | Out-String) | ConvertFrom-Json)
}

function Wait-ForPullRequestChecks([int]$number) {
    Write-Host '[4/6] Attente des tests GitHub...' -ForegroundColor Yellow
    $deadline = [DateTimeOffset]::Now.AddMinutes($TimeoutMinutes)
    $lastMessage = [DateTimeOffset]::MinValue

    while ([DateTimeOffset]::Now -lt $deadline) {
        $pr = Get-PullRequestState $number
        $checks = @($pr.statusCheckRollup)
        $failures = @($checks | Where-Object {
            $_.conclusion -in @('FAILURE', 'CANCELLED', 'TIMED_OUT', 'ACTION_REQUIRED', 'STARTUP_FAILURE')
        })
        if ($failures.Count -gt 0) {
            $failedNames = ($failures | ForEach-Object { $_.name }) -join ', '
            throw "Les tests GitHub ont echoue : $failedNames. Aucun tag ni Release n a ete cree."
        }

        $unfinished = @($checks | Where-Object {
            $_.status -ne 'COMPLETED' -or
            $_.conclusion -notin @('SUCCESS', 'NEUTRAL', 'SKIPPED')
        })
        if ($checks.Count -gt 0 -and $unfinished.Count -eq 0) {
            Write-Host 'Tous les tests GitHub ont reussi.' -ForegroundColor Green
            return
        }

        if (([DateTimeOffset]::Now - $lastMessage).TotalSeconds -ge 30) {
            if ($checks.Count -eq 0) {
                Write-Host 'Les tests GitHub vont demarrer...'
            } else {
                Write-Host "$($unfinished.Count) verification(s) encore en cours..."
            }
            $lastMessage = [DateTimeOffset]::Now
        }
        Start-Sleep -Seconds 10
    }

    throw "Les tests GitHub n ont pas termine dans les $TimeoutMinutes minutes. La Pull Request reste ouverte et rien n a ete publie."
}

function Update-PullRequestBranchIfNeeded([int]$number) {
    $pr = Get-PullRequestState $number
    if ($pr.mergeStateStatus -ne 'BEHIND') { return }
    Write-Host 'Mise a jour de la branche avec la version actuelle de main...' -ForegroundColor Yellow
    Invoke-Checked {
        gh pr update-branch $number --repo $Repository
    } "La branche de la Pull Request #$number ne peut pas etre mise a jour automatiquement."
}

function Copy-PublicSources([string]$destinationRoot) {
    Invoke-Checked { git rm -r --ignore-unmatch . } 'Impossible de preparer la copie publique.'

    $allowedDirectories = @(
        '.github', 'assets', 'browser-extension', 'docs', 'installer',
        'packaging', 'src', 'tests', 'tools'
    )
    $allowedRootFiles = @(
        '.gitignore', 'CHANGELOG.md', 'CODE_SIGNING.md', 'CONTRIBUTING.md',
        'Directory.Build.props', 'global.json', 'INSTALLATION.en.md',
        'INSTALLATION.md', 'JellyfinVlcBridge.slnx', 'LICENSE', 'NuGet.Config',
        'PRIVACY.md', 'README.en.md', 'README.md', 'SECURITY.md'
    )
    $blockedNamePattern = '(?i)(^|/)(\.env(?:\..*)?|credentials?(?:\..*)?|secrets?(?:\..*)?|config\.json|native-messaging-host\.json|extension-heartbeat\.json|playback-preferences\.json|language\.json|[^/]+\.log|\.npmrc|\.pypirc|id_rsa|id_ed25519|[^/]+\.(?:pfx|p12|pem|key|token|secret))$'
    $secretContentPattern = '(?i)(-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{16,}|sk_live_[A-Za-z0-9]{16,})'

    $relativeFiles = @(git -C $projectDirectory ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'Impossible de dresser la liste sure des sources publiques.' }
    $relativeFiles = @($relativeFiles | ForEach-Object { ([string]$_).Replace('\', '/').Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    if ($relativeFiles.Count -eq 0) { throw 'Aucune source publique n a ete trouvee.' }

    $sourceFiles = foreach ($relative in $relativeFiles) {
        if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|/)\.\.(/|$)' -or $relative -match ':') {
            throw "Chemin source refuse : $relative"
        }
        $topLevel = ($relative -split '/', 2)[0]
        $allowed = if ($relative.Contains('/')) {
            $allowedDirectories -contains $topLevel
        } else {
            $allowedRootFiles -contains $relative
        }
        if (-not $allowed) {
            throw "Fichier non autorise dans la copie publique : $relative"
        }
        if ($relative -match $blockedNamePattern) {
            throw "Fichier potentiellement sensible refuse : $relative"
        }

        $joinedPath = Join-Path $projectDirectory ($relative.Replace('/', '\'))
        $fullPath = [IO.Path]::GetFullPath($joinedPath)
        $sourceRoot = [IO.Path]::GetFullPath($projectDirectory).TrimEnd('\') + '\'
        if (-not $fullPath.StartsWith($sourceRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Source publique hors du projet : $relative"
        }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw "Source publique introuvable : $relative"
        }
        $sourceItem = Get-Item -LiteralPath $fullPath -Force
        if (($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Lien ou point de reanalyse refuse dans la copie publique : $relative"
        }
        $extension = [IO.Path]::GetExtension($fullPath).ToLowerInvariant()
        if ($extension -notin @('.png', '.ico')) {
            $content = Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8
            if ($content -match $secretContentPattern) {
                throw "Secret potentiel detecte dans $relative. Publication interrompue."
            }
        }
        [PSCustomObject]@{ Relative = $relative; FullName = $fullPath }
    }

    foreach ($file in $sourceFiles) {
        $destination = Join-Path $destinationRoot ($file.Relative.Replace('/', '\'))
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
    }
    Invoke-Checked { git add --all } 'Impossible de preparer les modifications Git.'
    Invoke-Checked { git diff --cached --check } 'Git a detecte un fichier mal forme.'
}

function Remove-SafeTemporaryDirectory {
    if ([string]::IsNullOrWhiteSpace($stagingDirectory) -or -not (Test-Path -LiteralPath $stagingDirectory)) {
        return
    }
    $resolvedWork = [IO.Path]::GetFullPath($workDirectory).TrimEnd('\') + '\'
    $resolvedStaging = [IO.Path]::GetFullPath($stagingDirectory)
    $leaf = [IO.Path]::GetFileName($resolvedStaging)
    if (
        $resolvedStaging.StartsWith($resolvedWork, [StringComparison]::OrdinalIgnoreCase) -and
        $leaf.StartsWith("github-release-$Version-", [StringComparison]::OrdinalIgnoreCase)
    ) {
        Remove-Item -LiteralPath $resolvedStaging -Recurse -Force
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($Version)) { $Version = Get-ProjectVersion }
    if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Le numero de version est invalide.' }
    $tag = "v$Version"

    Write-Host ''
    Write-Host "=== Publication fiable de Jellyfin VLC Bridge $Version ===" -ForegroundColor Cyan
    if ($ValidateOnly) {
        Write-Host 'Mode verification : aucun envoi ne sera effectue.'
    } else {
        Write-Host 'Aucun envoi ne sera effectue sans votre confirmation.'
    }
    Write-Host ''

    Assert-Program 'git' 'Git'
    Assert-Program 'dotnet' '.NET SDK'
    Assert-Program 'node' 'Node.js'
    Assert-Program 'gh' 'GitHub CLI'

    Invoke-LocalValidation
    if ($ValidateOnly) {
        Assert-GitHubConnection -ReadOnly
        Write-Host ''
        Write-Host 'Verification terminee : le projet et la connexion GitHub sont prets.' -ForegroundColor Green
        $publicationSucceeded = $true
        Complete-Script 0
    }

    Assert-GitHubConnection

    $existingRelease = Get-ReleaseState
    if (Test-ReleaseComplete $existingRelease) {
        Write-Host ''
        Write-Host "La version $Version est deja publiee et complete." -ForegroundColor Green
        Write-Host $existingRelease.url
        $publicationSucceeded = $true
        Complete-Script 0
    }

    $remoteTag = & git ls-remote --tags "https://github.com/$Repository.git" "refs/tags/$tag"
    if ($LASTEXITCODE -ne 0) { throw 'Impossible de verifier les tags du depot.' }
    if (-not [string]::IsNullOrWhiteSpace(($remoteTag | Out-String))) {
        if ($null -ne $existingRelease) {
            throw "La Release $tag existe mais reste incomplete. Consultez son workflow avant de choisir un nouveau numero de version."
        }
        Write-Host "Le tag $tag existe deja, mais aucune Release n a ete creee." -ForegroundColor Yellow
        $retryConfirmation = Read-Host "Relancer le workflow GitHub pour $tag ? O/N"
        if ($retryConfirmation -notmatch '^[OoYy]$') {
            Write-Host 'Relance annulee. Aucun workflow n a ete demarre.' -ForegroundColor Yellow
            $publicationSucceeded = $true
            Complete-Script 0
        }
        Invoke-Checked {
            gh workflow run release.yml --repo $Repository --ref $tag -f "version=$Version"
        } "Le workflow de Release n a pas pu etre relance pour $tag."
        Wait-ForRelease
        $publicationSucceeded = $true
        Complete-Script 0
    }

    $branchName = "release/v$Version"
    $repositoryOwner = ($Repository -split '/', 2)[0]
    $remoteBranch = & git ls-remote --heads "https://github.com/$Repository.git" "refs/heads/$branchName"
    if ($LASTEXITCODE -ne 0) { throw 'Impossible de verifier la branche de publication distante.' }
    $remoteBranchExists = -not [string]::IsNullOrWhiteSpace(($remoteBranch | Out-String))

    Write-Host '[3/6] Preparation d une copie Git neuve...' -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $workDirectory -Force | Out-Null
    $uniqueSuffix = [DateTimeOffset]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 6)
    $stagingDirectory = Join-Path $workDirectory "github-release-$Version-$uniqueSuffix"
    Invoke-Checked {
        git clone --branch main --single-branch "https://github.com/$Repository.git" $stagingDirectory
    } 'Impossible de recuperer une copie neuve du depot GitHub.'

    Push-Location $stagingDirectory
    try {
        Invoke-Checked { git config user.name $repositoryOwner } 'Impossible de configurer le nom Git.'
        Invoke-Checked { git config user.email "$repositoryOwner@users.noreply.github.com" } 'Impossible de configurer l adresse Git.'
        if ($remoteBranchExists) {
            Invoke-Checked {
                git fetch origin "refs/heads/${branchName}:refs/remotes/origin/${branchName}"
            } 'Impossible de recuperer la branche de publication existante.'
            Invoke-Checked {
                git switch -c $branchName --track "origin/$branchName"
            } 'Impossible de reprendre la branche de publication existante.'
            Write-Host "Branche existante reprise : $branchName" -ForegroundColor Yellow
        } else {
            Invoke-Checked { git switch -c $branchName } 'Impossible de creer la branche de publication.'
        }
        Copy-PublicSources $stagingDirectory

        & git diff --cached --quiet
        $hasSourceChanges = $LASTEXITCODE -eq 1
        if ($LASTEXITCODE -notin @(0, 1)) { throw 'Impossible de comparer les sources.' }
        if (-not $hasSourceChanges -and -not $remoteBranchExists) {
            throw 'Aucune modification source n est presente pour cette nouvelle version.'
        }

        $workflowChanges = @(& git diff --cached --name-only -- '.github/workflows')
        if ($workflowChanges.Count -gt 0) {
            if (-not $AllowWorkflowChanges) {
                throw @"
Un fichier de fonctionnement GitHub a change :
  $($workflowChanges -join "`n  ")

Par securite, aucun envoi n a ete effectue.
Si ce changement est volontaire, executez une seule fois :
  gh auth refresh --hostname github.com --scopes workflow

Puis relancez avec l option -AllowWorkflowChanges.
"@
            }
            $authHeaders = (& gh api --include user 2>&1 | Out-String)
            if ($LASTEXITCODE -ne 0 -or $authHeaders -notmatch "(?im)^x-oauth-scopes:.*\bworkflow\b") {
                throw 'L autorisation GitHub workflow manque encore. Executez : gh auth refresh --hostname github.com --scopes workflow'
            }
        }

        Write-Host ''
        if ($hasSourceChanges) { & git diff --cached --stat }
        else { Write-Host 'La branche distante contient deja exactement les sources validees.' -ForegroundColor Green }
        Write-Host ''
        Write-Host "Depot   : https://github.com/$Repository" -ForegroundColor White
        Write-Host "Version : $Version" -ForegroundColor White
        Write-Host 'Parcours : branche temporaire > tests GitHub > fusion > tag > Release'
        Write-Host ''
        $confirmation = Read-Host "Publier ou reprendre la version $Version ? O/N"
        if ($confirmation -notmatch '^[OoYy]$') {
            Write-Host 'Publication annulee. Aucun fichier n a ete envoye.' -ForegroundColor Yellow
            $publicationSucceeded = $true
            Complete-Script 0
        }

        if ($hasSourceChanges) {
            Invoke-Checked { git commit -m "Preparer la version $Version" } 'Impossible de creer le commit.'
            if ($remoteBranchExists) {
                Invoke-Checked { git push origin $branchName } 'La branche de publication existante n a pas pu etre mise a jour.'
            } else {
                Invoke-Checked { git push --set-upstream origin $branchName } 'La branche de publication n a pas pu etre envoyee.'
            }
        }

        $prBodyPath = Join-Path $stagingDirectory '.release-pr-body.md'
        @"
## Version $Version

- verification locale complete ;
- compilation et tests du Bridge reussis ;
- tests de l extension Chrome reussis ;
- Setup et ZIP Windows construits localement ;
- empreintes SHA-256 et notes lisibles verifiees.

La fusion et le tag sont effectues uniquement apres la reussite des controles GitHub.
"@ | Set-Content -LiteralPath $prBodyPath -Encoding UTF8

        $openPrJson = & gh pr list --repo $Repository --base main --head $branchName --state open --limit 2 --json number,url
        if ($LASTEXITCODE -ne 0) { throw 'Impossible de rechercher une Pull Request existante.' }
        $openPullRequests = @(($openPrJson | Out-String) | ConvertFrom-Json)
        if ($openPullRequests.Count -gt 1) { throw "Plusieurs Pull Requests utilisent la branche $branchName." }
        if ($openPullRequests.Count -eq 1) {
            $prNumber = [int]$openPullRequests[0].number
            $prUrl = [string]$openPullRequests[0].url
            Write-Host "Pull Request existante reprise : $prUrl" -ForegroundColor Yellow
        } else {
            $prUrl = & gh pr create --repo $Repository --base main --head $branchName --title "Preparer la version $Version" --body-file $prBodyPath
            if ($LASTEXITCODE -ne 0 -or ($prUrl | Out-String) -notmatch '/pull/(\d+)') {
                throw "La Pull Request n a pas pu etre creee. La branche $branchName reste disponible sur GitHub."
            }
            $prNumber = [int]$Matches[1]
            Write-Host "Pull Request creee : $($prUrl | Out-String)" -ForegroundColor Green
        }

        Update-PullRequestBranchIfNeeded $prNumber
        Wait-ForPullRequestChecks $prNumber

        Write-Host '[5/6] Fusion et creation de la version...' -ForegroundColor Yellow
        Invoke-Checked {
            gh pr merge $prNumber --repo $Repository --merge --delete-branch
        } "La Pull Request #$prNumber n a pas pu etre fusionnee."

        $mergedPr = Get-PullRequestState $prNumber
        if ($mergedPr.state -ne 'MERGED' -or [string]::IsNullOrWhiteSpace([string]$mergedPr.mergeCommit.oid)) {
            throw "La fusion de la Pull Request #$prNumber n est pas confirmee."
        }
        $mergeCommit = [string]$mergedPr.mergeCommit.oid

        Invoke-Checked {
            git tag -a $tag $mergeCommit -m "Jellyfin VLC Bridge $Version"
        } "Impossible de creer le tag $tag."
        Invoke-Checked {
            git push origin $tag
        } "Impossible d envoyer le tag $tag. Relancez le script : il reprendra sans recreer le code."
    } finally {
        Pop-Location
    }

    Wait-ForRelease
    $publicationSucceeded = $true
    Complete-Script 0
} catch {
    Write-Host ''
    Write-Host 'Publication arretee proprement.' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace($stagingDirectory) -and (Test-Path -LiteralPath $stagingDirectory)) {
        Write-Host ''
        Write-Host "Copie de diagnostic conservee : $stagingDirectory" -ForegroundColor Yellow
    }
    Complete-Script 1
} finally {
    if ($publicationSucceeded -and -not $KeepTemporaryFiles) {
        Remove-SafeTemporaryDirectory
    }
}
