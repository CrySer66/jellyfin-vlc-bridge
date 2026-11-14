$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$metadataPath = Join-Path $PSScriptRoot 'Test-ReleaseMetadata.ps1'
$tokens = $null
$parseErrors = $null
$metadata = [System.Management.Automation.Language.Parser]::ParseFile(
    $metadataPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw 'Le controle des metadonnees contient une erreur de syntaxe.' }

# Load the real validators without running builds, reading release assets or using the network.
foreach ($name in @('Assert-WorkflowActionPins', 'Assert-ReleaseAttestations')) {
    $definition = $metadata.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $false)
    if ($null -eq $definition) { throw "Controle de workflow introuvable : $name" }
    . ([scriptblock]::Create($definition.Extent.Text))
}

$release = Get-Content -LiteralPath (Join-Path $projectDirectory '.github/workflows/release.yml') -Raw -Encoding UTF8
$ci = Get-Content -LiteralPath (Join-Path $projectDirectory '.github/workflows/ci.yml') -Raw -Encoding UTF8
$currentCommit = [regex]::Match($release, 'actions/attest@([0-9a-f]{40})').Groups[1].Value
if ($currentCommit.Length -ne 40) { throw 'Empreinte de reference actions/attest introuvable.' }
$replacementCommit = if ($currentCommit -cne ('f' * 40)) { 'f' * 40 } else { 'e' * 40 }
$setupSubject = 'outputs/JellyfinVlcBridge-${{ steps.version.outputs.version }}-Setup.exe'
$zipSubject = 'outputs/JellyfinVlcBridge-${{ steps.version.outputs.version }}-win-x64.zip'
$script:caseCount = 0

function Assert-Throws([scriptblock]$action, [string]$messagePart) {
    $caught = $null
    try { & $action | Out-Null } catch { $caught = $_.Exception.Message }
    if ($null -eq $caught -or -not $caught.Contains($messagePart)) {
        throw "Erreur attendue absente : $messagePart (erreur recue : $caught)"
    }
}

function Assert-ReleaseWorkflow([string]$source) {
    Assert-WorkflowActionPins $source
    Assert-ReleaseAttestations $source
}

function Test-Case([string]$name, [scriptblock]$action) {
    & $action
    $script:caseCount++
    Write-Host "OK : $name"
}

Test-Case 'Les workflows actuels utilisent des empreintes completes et deux artefacts distincts' {
    Assert-WorkflowActionPins $ci
    Assert-ReleaseWorkflow $release
}

Test-Case 'Une mise a jour des deux empreintes actions/attest reste autorisee' {
    $updated = $release.Replace($currentCommit, $replacementCommit)
    Assert-ReleaseWorkflow $updated
}

Test-Case 'Une action attest referencee par un tag mutable est refusee' {
    Assert-Throws { Assert-ReleaseWorkflow ($release.Replace($currentCommit, 'v4.2.2')) } 'non figee par empreinte'
}

Test-Case 'Une empreinte abregee est refusee' {
    Assert-Throws { Assert-ReleaseWorkflow ($release.Replace($currentCommit, $currentCommit.Substring(0, 7))) } 'non figee par empreinte'
}

Test-Case 'Des empreintes differentes entre Setup et ZIP sont refusees' {
    $changedOnce = ([regex]::new([regex]::Escape($currentCommit))).Replace($release, $replacementCommit, 1)
    Assert-Throws { Assert-ReleaseWorkflow $changedOnce } 'meme empreinte'
}

Test-Case 'Attester deux fois le Setup sans attester le ZIP est refuse' {
    Assert-Throws { Assert-ReleaseWorkflow ($release.Replace($zipSubject, $setupSubject)) } 'une fois le Setup et une fois le ZIP'
}

Test-Case 'Une attestation absente est refusee' {
    $missing = ([regex]::new('actions/attest@')).Replace($release, 'actions/checkout@', 1)
    Assert-Throws { Assert-ReleaseWorkflow $missing } 'exactement deux attestations'
}

Test-Case 'Un chemin mentionne hors de son attestation ne remplace pas subject-path' {
    $subjectLine = '(?m)^[ \t]*subject-path:[ \t]*' + [regex]::Escape($zipSubject) + '[ \t]*\r?\n'
    $missingSubject = [regex]::Replace($release, $subjectLine, '')
    $missingSubject += "`n      - name: Hors attestation`n        subject-path: $zipSubject`n"
    Assert-Throws { Assert-ReleaseWorkflow $missingSubject } 'exactement un subject-path'
}

Test-Case 'Une action differente utilisee sans empreinte est egalement refusee' {
    $mutableCheckout = [regex]::Replace($ci, 'actions/checkout@[0-9a-f]{40}', 'actions/checkout@main')
    Assert-Throws { Assert-WorkflowActionPins $mutableCheckout } 'non figee par empreinte'
}

Test-Case 'Une action anonyme utilisee sans empreinte est refusee' {
    Assert-Throws { Assert-WorkflowActionPins '      - uses: actions/checkout@main' } 'non figee par empreinte'
}

Write-Host "Workflows : $($script:caseCount) tests hors reseau reussis."
