$ErrorActionPreference = 'Stop'
$publisherPath = Join-Path $PSScriptRoot 'Publier-Mise-A-Jour-GitHub.ps1'
$tokens = $null
$parseErrors = $null
$publisher = [System.Management.Automation.Language.Parser]::ParseFile(
    $publisherPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw 'Le script de publication contient une erreur de syntaxe.' }

# Load only the functions being tested, never the publisher's executable body.
foreach ($name in @(
    'Invoke-Checked', 'Assert-GitHubConnection', 'Get-PullRequestState',
    'Wait-ForPullRequestChecks', 'Merge-ValidatedPullRequest', 'Get-MergedReleaseCommit'
)) {
    $definition = $publisher.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $false)
    if ($null -eq $definition) { throw "Fonction de publication introuvable : $name" }
    . ([scriptblock]::Create($definition.Extent.Text))
}

$Repository = 'example/bridge'
$Version = '1.2.3'
$TimeoutMinutes = 1
$script:validatedHead = 'a' * 40
$script:mergeCommit = 'b' * 40
$script:caseCount = 0

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

function Assert-Throws([scriptblock]$action, [string]$messagePart) {
    $caught = $null
    try { & $action | Out-Null } catch { $caught = $_.Exception.Message }
    Assert-True ($null -ne $caught -and $caught.Contains($messagePart)) "Erreur attendue absente : $messagePart"
}

function New-PullRequest([string]$state = 'OPEN', [string]$conclusion = 'SUCCESS') {
    return [pscustomobject]@{
        state = $state
        headRefOid = $script:validatedHead
        mergeCommit = [pscustomobject]@{ oid = $script:mergeCommit }
        statusCheckRollup = @([pscustomobject]@{
            name = 'Windows'
            status = 'COMPLETED'
            conclusion = $conclusion
        })
    }
}

function Reset-TestState {
    $script:commands = [System.Collections.Generic.List[string]]::new()
    $script:pullRequests = [System.Collections.Generic.Queue[object]]::new()
    $script:authFails = $false
    $script:remoteHead = $script:validatedHead
    $script:fetchFails = $false
    $script:commitFetched = $false
    $script:commitOnMain = $true
    $script:buildInvoked = $false
    $script:mergedPullRequestList = @()
    $script:mergedVersion = $Version
    $script:validatedTree = 'd' * 40
    $script:mergedTree = $script:validatedTree
    $script:sleepCount = 0
    $global:LASTEXITCODE = 0
}

# All external publication commands are replaced. Unexpected commands fail closed.
function gh {
    $command = $args -join ' '
    $script:commands.Add('gh ' + $command)
    $global:LASTEXITCODE = 0
    if ($command -like 'api user *') {
        Assert-True ($command.Contains('--hostname github.com')) 'Le compte doit etre verifie sur github.com.'
        if ($script:authFails) { $global:LASTEXITCODE = 1; return }
        return 'example'
    }
    if ($command -like 'repo view *') { return $Repository }
    if ($command -eq 'auth setup-git --hostname github.com') { return }
    if ($command -like 'pr list *') {
        Assert-True ($command.Contains("--base main --head release/v$Version --state merged")) 'La reprise doit rechercher la branche de cette version uniquement.'
        return (ConvertTo-Json -InputObject $script:mergedPullRequestList -Depth 4 -Compress)
    }
    if ($command -like 'pr view *') {
        Assert-True ($script:pullRequests.Count -gt 0) 'Lecture GitHub inattendue.'
        return ($script:pullRequests.Dequeue() | ConvertTo-Json -Depth 5 -Compress)
    }
    if ($command -like 'pr merge *') {
        $headOption = [Array]::IndexOf($args, '--match-head-commit')
        Assert-True ($headOption -ge 0) 'La fusion doit etre limitee au commit valide.'
        if ($args[$headOption + 1] -ne $script:remoteHead) { $global:LASTEXITCODE = 1; return }
        return 'Fusion simulee.'
    }
    throw "Commande GitHub interdite pendant le test : $command"
}

function git {
    $command = $args -join ' '
    $script:commands.Add('git ' + $command)
    $global:LASTEXITCODE = 0
    if ($command -eq 'fetch origin refs/heads/main:refs/remotes/origin/main') {
        if ($script:fetchFails) { $global:LASTEXITCODE = 1; return }
        $script:commitFetched = $true
        return 'Recuperation simulee.'
    }
    if ($command -eq "merge-base --is-ancestor $($script:mergeCommit) refs/remotes/origin/main") {
        if (-not $script:commitFetched -or -not $script:commitOnMain) { $global:LASTEXITCODE = 1 }
        return
    }
    if ($command -eq "show $($script:mergeCommit):Directory.Build.props") {
        return "<Project><PropertyGroup><Version>$($script:mergedVersion)</Version></PropertyGroup></Project>"
    }
    if ($command -eq 'write-tree') { return $script:validatedTree }
    if ($command -eq "rev-parse $($script:mergeCommit)^{tree}") { return $script:mergedTree }
    throw "Commande Git interdite pendant le test : $command"
}

function Start-Sleep {
    param([int]$Seconds)
    $script:sleepCount++
    if ($script:sleepCount -gt 3) { throw 'Attente inattendue pendant le test.' }
}

function Test-Case([string]$name, [scriptblock]$action) {
    Reset-TestState
    & $action
    $script:caseCount++
    Write-Host "OK : $name"
}

Test-Case 'La verification GitHub ne change pas la configuration Git' {
    Assert-GitHubConnection -ReadOnly | Out-Null
    Assert-True (-not (($script:commands -join ';') -match 'setup-git')) 'Le precontrole doit rester en lecture seule.'
}

Test-Case 'Les tests en cours sont attendus puis le commit valide est retourne' {
    $pending = New-PullRequest
    $pending.statusCheckRollup[0].status = 'IN_PROGRESS'
    $pending.statusCheckRollup[0].conclusion = $null
    $script:pullRequests.Enqueue($pending)
    $script:pullRequests.Enqueue((New-PullRequest))
    $head = Wait-ForPullRequestChecks 42
    Assert-True ($head -ceq $script:validatedHead -and $script:sleepCount -eq 1) 'Le commit retourne ne correspond pas aux tests termines.'
}

Test-Case 'Des tests en echec ne permettent pas de fusionner' {
    $script:pullRequests.Enqueue((New-PullRequest -conclusion 'FAILURE'))
    Assert-Throws { Wait-ForPullRequestChecks 42 } 'Les tests GitHub ont echoue'
}

Test-Case 'Une Pull Request fermee ne permet pas de publier' {
    $script:pullRequests.Enqueue((New-PullRequest -state 'CLOSED'))
    Assert-Throws { Wait-ForPullRequestChecks 42 } 'n est plus ouverte'
}

Test-Case 'Un commit modifie apres les tests empeche la fusion' {
    $script:remoteHead = 'c' * 40
    Assert-Throws { Merge-ValidatedPullRequest 42 $script:validatedHead } 'n a pas pu etre fusionnee'
    Assert-True (-not $script:commitFetched) 'La publication a continue apres une fusion refusee.'
}

Test-Case 'Le commit fusionne est recupere avant de preparer le tag' {
    $script:pullRequests.Enqueue((New-PullRequest -state 'MERGED'))
    $commit = Merge-ValidatedPullRequest 42 $script:validatedHead
    Assert-True ($commit -ceq $script:mergeCommit) 'La fonction doit retourner uniquement le commit fusionne.'
    Assert-True ($script:commitFetched) 'Le clone doit recuperer la fusion distante.'
}

Test-Case 'Un echec de recuperation empeche la creation du tag' {
    $script:pullRequests.Enqueue((New-PullRequest -state 'MERGED'))
    $script:fetchFails = $true
    Assert-Throws { Merge-ValidatedPullRequest 42 $script:validatedHead } 'Impossible de recuperer la fusion'
}

Test-Case 'Un commit absent de main empeche la creation du tag' {
    $script:pullRequests.Enqueue((New-PullRequest -state 'MERGED'))
    $script:commitOnMain = $false
    Assert-Throws { Merge-ValidatedPullRequest 42 $script:validatedHead } 'absent de main'
}

Test-Case 'Une nouvelle version ne reprend pas une autre publication' {
    $commit = Get-MergedReleaseCommit "release/v$Version"
    Assert-True ($null -eq $commit -and $script:commands.Count -eq 1) 'Une reprise a ete proposee sans Pull Request fusionnee.'
}

Test-Case 'Apres une fusion, la reprise vise son commit exact sans recreer le code' {
    $script:mergedPullRequestList = @([pscustomobject]@{ number = 42; url = 'https://github.com/example/bridge/pull/42' })
    $script:pullRequests.Enqueue((New-PullRequest -state 'MERGED'))
    $commit = Get-MergedReleaseCommit "release/v$Version"
    Assert-True ($commit -ceq $script:mergeCommit) 'La reprise doit viser le commit fusionne, pas le main actuel.'
    Assert-True (-not (($script:commands -join ';') -match 'gh pr (create|merge)|git (commit|push|tag)')) 'La reprise a recree ou envoye du code.'
}

Test-Case 'Plusieurs fusions pour une version empechent une reprise ambigue' {
    $script:mergedPullRequestList = @([pscustomobject]@{ number = 42 }, [pscustomobject]@{ number = 43 })
    Assert-Throws { Get-MergedReleaseCommit "release/v$Version" } 'Plusieurs Pull Requests fusionnees'
}

Test-Case 'La version enregistree dans la fusion doit correspondre au tag prevu' {
    $script:mergedPullRequestList = @([pscustomobject]@{ number = 42 })
    $script:pullRequests.Enqueue((New-PullRequest -state 'MERGED'))
    $script:mergedVersion = '9.9.9'
    Assert-Throws { Get-MergedReleaseCommit "release/v$Version" } 'ne correspond pas'
}

Test-Case 'Des sources differentes de la fusion bloquent la reprise' {
    $script:mergedPullRequestList = @([pscustomobject]@{ number = 42 })
    $script:pullRequests.Enqueue((New-PullRequest -state 'MERGED'))
    $script:validatedTree = 'e' * 40
    Assert-Throws { Get-MergedReleaseCommit "release/v$Version" } 'sources locales different'
}

Test-Case 'Une fusion retiree de main ne peut pas etre reprise' {
    $script:mergedPullRequestList = @([pscustomobject]@{ number = 42 })
    $script:pullRequests.Enqueue((New-PullRequest -state 'MERGED'))
    $script:commitOnMain = $false
    Assert-Throws { Get-MergedReleaseCommit "release/v$Version" } 'absente de main'
}

Test-Case 'Une connexion GitHub absente est detectee avant toute compilation' {
    function Assert-Program { param([string]$name, [string]$displayName) }
    function Invoke-LocalValidation { $script:buildInvoked = $true; throw 'Compilation inattendue.' }
    function Complete-Script { param([int]$exitCode) throw "TEST_EXIT:$exitCode" }
    $script:authFails = $true
    $Version = '1.2.3'
    $ValidateOnly = $true
    $NoPause = $true
    $publicationSucceeded = $false
    $stagingDirectory = $null
    $main = @($publisher.EndBlock.Statements | Where-Object {
        $_ -is [System.Management.Automation.Language.TryStatementAst]
    })
    Assert-True ($main.Count -eq 1) 'Point d entree du script de publication introuvable.'
    Assert-Throws { & ([scriptblock]::Create($main[0].Extent.Text)) } 'TEST_EXIT:1'
    Assert-True (-not $script:buildInvoked) 'La compilation a commence avant le controle de la connexion.'
}

Write-Host "Publication : $($script:caseCount) tests hors reseau reussis."
# The failed-auth scenario must not leak its simulated native exit code to CI.
$global:LASTEXITCODE = 0
