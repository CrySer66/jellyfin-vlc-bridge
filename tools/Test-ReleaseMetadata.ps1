param([string]$Version = '')

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot

function Assert-WorkflowActionPins([string]$workflowSource) {
    foreach ($usesMatch in [regex]::Matches($workflowSource, '(?m)^[ \t]*(?:-[ \t]+)?uses:[ \t]*(?<action>[^\s#]+)')) {
        $action = $usesMatch.Groups['action'].Value
        if ($action -notmatch '@[0-9a-f]{40}$') {
            throw "Action GitHub non figee par empreinte : $action"
        }
    }
}

function Assert-ReleaseAttestations([string]$workflowSource) {
    $uses = [regex]::Matches($workflowSource, '(?m)^(?<indent>[ \t]*)(?<inline>-[ \t]+)?uses:[ \t]*(?<action>[^\s#]+)[^\r\n]*')
    $attestations = @($uses | Where-Object { $_.Groups['action'].Value -match '^actions/attest(?:@|$)' })
    if ($attestations.Count -ne 2) {
        throw 'La Release doit contenir exactement deux attestations distinctes.'
    }
    $expectedSubjects = @(
        'outputs/JellyfinVlcBridge-${{ steps.version.outputs.version }}-Setup.exe',
        'outputs/JellyfinVlcBridge-${{ steps.version.outputs.version }}-win-x64.zip'
    )
    $subjects = @()
    $attestCommit = $null
    foreach ($attestation in $attestations) {
        $action = $attestation.Groups['action'].Value
        if ($action -notmatch '^actions/attest@(?<commit>[0-9a-f]{40})$') {
            throw "Action GitHub non figee par empreinte : $action"
        }
        $commit = $Matches.commit
        if ($null -ne $attestCommit -and $commit -cne $attestCommit) {
            throw 'Les deux attestations doivent utiliser la meme empreinte actions/attest.'
        }
        $attestCommit = $commit

        # Bind each subject to its own step; a path mentioned elsewhere is not an attestation.
        $propertyIndent = $attestation.Groups['indent'].Length + $attestation.Groups['inline'].Length
        $stepLines = @()
        $remaining = $workflowSource.Substring($attestation.Index + $attestation.Length)
        foreach ($line in ($remaining -split "`r?`n")) {
            if (-not [string]::IsNullOrWhiteSpace($line) -and $line.TrimStart() -notlike '#*') {
                $indent = [regex]::Match($line, '^[ \t]*').Length
                if ($indent -lt $propertyIndent) { break }
            }
            $stepLines += $line
        }
        $subjectMatches = [regex]::Matches(($stepLines -join "`n"), '(?m)^[ \t]*subject-path:[ \t]*(?<path>[^\r\n#]*)')
        if ($subjectMatches.Count -ne 1) {
            throw 'Chaque attestation doit declarer exactement un subject-path.'
        }
        $subjects += $subjectMatches[0].Groups['path'].Value.Trim()
    }
    foreach ($expectedSubject in $expectedSubjects) {
        if (@($subjects | Where-Object { $_ -ceq $expectedSubject }).Count -ne 1) {
            throw 'Les attestations doivent couvrir une fois le Setup et une fois le ZIP.'
        }
    }
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    [xml]$props = Get-Content -LiteralPath (Join-Path $projectDirectory 'Directory.Build.props') -Raw -Encoding UTF8
    $Version = [string]$props.Project.PropertyGroup.Version
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version invalide : $Version" }

$workflowPath = Join-Path $projectDirectory '.github\workflows\release.yml'
$workflow = Get-Content -LiteralPath $workflowPath -Raw -Encoding UTF8
$ciWorkflow = Get-Content -LiteralPath (Join-Path $projectDirectory '.github\workflows\ci.yml') -Raw -Encoding UTF8
$publisher = Get-Content -LiteralPath (Join-Path $projectDirectory 'tools\Publier-Mise-A-Jour-GitHub.ps1') -Raw -Encoding UTF8

foreach ($requiredPublisherGuard in @(
    'config\.json',
    'native-messaging-host\.json',
    '[IO.FileAttributes]::ReparsePoint',
    'gh pr list --repo $Repository',
    'Pull Request existante reprise',
    'gh pr update-branch',
    'gh workflow run release.yml',
    'Relancer le workflow GitHub'
)) {
    if (-not $publisher.Contains($requiredPublisherGuard)) {
        throw "Protection du script de publication manquante : $requiredPublisherGuard"
    }
}

$sdkConfig = Get-Content -LiteralPath (Join-Path $projectDirectory 'global.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($sdkConfig.sdk.version -notmatch '^10\.0\.\d+$') { throw 'Le projet doit selectionner un SDK .NET 10 dans global.json.' }
foreach ($workflowSource in @($workflow, $ciWorkflow)) {
    if ($workflowSource -notmatch '(?m)^[ \t]+global-json-file:[ \t]*global\.json[ \t]*\r?$' -or
        $workflowSource -match '(?m)^[ \t]+dotnet-version:') {
        throw 'Le workflow doit installer uniquement le SDK .NET 10 selectionne dans global.json.'
    }
    if (-not $workflowSource.Contains('Test-WindowsLifecycle.ps1')) {
        throw 'Le workflow ne teste pas le cycle reel du Setup Windows.'
    }
}

foreach ($workflowSource in @($workflow, $ciWorkflow)) {
    Assert-WorkflowActionPins $workflowSource
}

foreach ($workflowSource in @($workflow, $ciWorkflow)) {
    $insideRunBlock = $false
    $runIndent = -1
    foreach ($line in ($workflowSource -split "`r?`n")) {
        $indent = ([regex]::Match($line, '^\s*').Value).Length
        if ($insideRunBlock -and -not [string]::IsNullOrWhiteSpace($line) -and $indent -le $runIndent) {
            $insideRunBlock = $false
        }
        if ($insideRunBlock -and $line -match '\$\{\{') {
            throw "Expression GitHub injectée directement dans un bloc de commande : $line"
        }
        $runMatch = [regex]::Match($line, '^(?<indent>\s*)run:\s*(?<command>.*)$')
        if (-not $runMatch.Success) { continue }
        $command = $runMatch.Groups['command'].Value
        if ($command -match '\$\{\{') {
            throw "Expression GitHub injectée directement dans une commande : $line"
        }
        if ($command.Trim() -in @('|', '|-', '|+')) {
            $insideRunBlock = $true
            $runIndent = $runMatch.Groups['indent'].Value.Length
        }
    }
}

foreach ($requiredPermission in @('contents:\s*write', 'id-token:\s*write', 'attestations:\s*write')) {
    if ($workflow -notmatch $requiredPermission) {
        throw "Autorisation de Release manquante : $requiredPermission"
    }
}
$permissionsBlock = [regex]::Match(
    $workflow,
    '(?ms)^permissions:\s*\r?\n(?<body>(?:  [a-z-]+:\s*[a-z]+\s*\r?\n)+)')
if (-not $permissionsBlock.Success) { throw 'Bloc permissions de la Release illisible.' }
$permissionNames = @([regex]::Matches($permissionsBlock.Groups['body'].Value, '(?m)^  ([a-z-]+):') |
    ForEach-Object { $_.Groups[1].Value })
$unexpectedPermissions = @($permissionNames | Where-Object {
    $_ -notin @('contents', 'id-token', 'attestations')
})
if ($unexpectedPermissions.Count -gt 0) {
    throw "Autorisations de Release trop larges : $($unexpectedPermissions -join ', ')"
}
Assert-ReleaseAttestations $workflow
foreach ($requiredText in @(
    'fetch-depth: 0',
    'EVENT_NAME: ${{ github.event_name }}',
    'SOURCE_REF: ${{ github.ref }}',
    'SOURCE_SHA: ${{ github.sha }}',
    "`$env:EVENT_NAME -eq 'workflow_dispatch'",
    "`$env:SOURCE_REF -ne 'refs/heads/main'",
    'refs/tags/v$($env:REQUESTED_VERSION)',
    "git merge-base --is-ancestor `$env:SOURCE_SHA 'refs/remotes/origin/main'",
    "group: release-`${{ github.event_name == 'workflow_dispatch' && format('v{0}', inputs.version) || github.ref_name }}",
    "if (`$tag -notmatch '^v(?<version>\d+\.\d+\.\d+)`$')",
    'git rev-parse "refs/tags/$tag^{commit}"',
    'reste immuable. Cr',
    'New-ReleaseChecksums.ps1',
    'New-ReleaseNotes.ps1',
    'Test-ReleaseMetadata.ps1',
    'subject-path: outputs/JellyfinVlcBridge-${{ steps.version.outputs.version }}-Setup.exe',
    'subject-path: outputs/JellyfinVlcBridge-${{ steps.version.outputs.version }}-win-x64.zip',
    '$setup = "outputs/JellyfinVlcBridge-$version-Setup.exe"',
    '$portable = "outputs/JellyfinVlcBridge-$version-win-x64.zip"',
    '--notes-file $notes',
    '$checksums'
)) {
    if (-not $workflow.Contains($requiredText)) {
        throw "Metadonnee de Release manquante : $requiredText"
    }
}
if ($workflow -match '--generate-notes') {
    throw 'Les notes GitHub automatiques sont interdites : utiliser la section courante de CHANGELOG.md.'
}
if ($workflow -match 'gh release (?:upload|edit)' -or $workflow -match '--clobber') {
    throw 'Une Release existante ne doit jamais etre modifiee ni ecrasee.'
}
$checkedCreate = "(?ms)gh release create[^\r\n]*\r?\n\s+if \(\`$LASTEXITCODE -ne 0\) \{ throw"
if ($workflow -notmatch $checkedCreate) {
    throw "Le code retour de gh release create n'est pas controle."
}

$notesPath = Join-Path ([IO.Path]::GetTempPath()) "JellyfinVlcBridge-$Version-release-notes-$([Guid]::NewGuid().ToString('N')).md"
try {
    & (Join-Path $PSScriptRoot 'New-ReleaseNotes.ps1') -Version $Version -OutputPath $notesPath | Out-Null
    $notes = Get-Content -LiteralPath $notesPath -Raw -Encoding UTF8
    $eAcute = [char]0x00E9
    $downloadsTitle = "T${eAcute}l${eAcute}chargements"
    foreach ($requiredText in @(
        "## Jellyfin VLC Bridge $Version",
        "## $downloadsTitle",
        "JellyfinVlcBridge-$Version-Setup.exe",
        "JellyfinVlcBridge-$Version-win-x64.zip",
        'SHA256SUMS.txt'
    )) {
        if (-not $notes.Contains($requiredText)) {
            throw "Notes de Release incompletes : $requiredText"
        }
    }
    if ($notes -match "(?i)what'?s changed|full changelog") {
        throw 'Les notes de Release contiennent encore le changelog automatique de GitHub.'
    }
} finally {
    Remove-Item -LiteralPath $notesPath -Force -ErrorAction SilentlyContinue
}

$checksumsPath = Join-Path $projectDirectory 'outputs\SHA256SUMS.txt'
if (-not (Test-Path -LiteralPath $checksumsPath -PathType Leaf)) {
    throw "Fichier d'empreintes absent : $checksumsPath"
}
$checksumLines = @(Get-Content -LiteralPath $checksumsPath -Encoding UTF8 | Where-Object { $_ -ne '' })
$expectedAssets = @(
    "JellyfinVlcBridge-$Version-Setup.exe"
    "JellyfinVlcBridge-$Version-win-x64.zip"
)
if ($checksumLines.Count -ne $expectedAssets.Count) {
    throw "SHA256SUMS.txt contient $($checksumLines.Count) ligne(s), $($expectedAssets.Count) attendues."
}
foreach ($assetName in $expectedAssets) {
    $line = @($checksumLines | Where-Object { $_ -match "^[0-9a-f]{64}  $([regex]::Escape($assetName))$" })
    if ($line.Count -ne 1) { throw "Empreinte absente ou invalide pour $assetName." }
    $assetPath = Join-Path $projectDirectory "outputs\$assetName"
    $actualHash = (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if (-not $line[0].StartsWith($actualHash + '  ', [StringComparison]::Ordinal)) {
        throw "Empreinte incorrecte pour $assetName."
    }
}

$wingetOutput = Join-Path ([IO.Path]::GetTempPath()) "JellyfinVlcBridge-$Version-winget-$([Guid]::NewGuid().ToString('N'))"
try {
    $testHash = 'A' * 64
    & (Join-Path $PSScriptRoot 'New-WinGetManifests.ps1') `
        -Version $Version `
        -InstallerSha256 $testHash `
        -ReleaseDate '2026-01-01' `
        -OutputDirectory $wingetOutput | Out-Null
    $manifests = @(Get-ChildItem -LiteralPath $wingetOutput -Filter '*.yaml' -File)
    if ($manifests.Count -ne 4) { throw 'La preparation WinGet doit produire quatre manifestes.' }
    $manifestText = ($manifests | ForEach-Object {
        Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
    }) -join "`n"
    foreach ($requiredText in @(
        'PackageIdentifier: CrySer66.JellyfinVlcBridge',
        "PackageVersion: `"$Version`"",
        'ManifestVersion: 1.12.0',
        'https://aka.ms/winget-manifest.installer.1.12.0.schema.json',
        'https://aka.ms/winget-manifest.defaultLocale.1.12.0.schema.json',
        'https://aka.ms/winget-manifest.locale.1.12.0.schema.json',
        'https://aka.ms/winget-manifest.version.1.12.0.schema.json',
        '  - interactive',
        'Silent: /quiet',
        'PackageIdentifier: VideoLAN.VLC',
        "releases/download/v$Version/JellyfinVlcBridge-$Version-Setup.exe",
        "InstallerSha256: `"$testHash`""
    )) {
        if (-not $manifestText.Contains($requiredText)) {
            throw "Manifeste WinGet incomplet : $requiredText"
        }
    }
    if ($manifestText -match '\{\{[^}]+\}\}') {
        throw 'Un marqueur non remplace subsiste dans les manifestes WinGet generes.'
    }
    if ($manifestText -match 'silentWithProgress|SilentWithProgress') {
        throw 'Le manifeste ne doit pas annoncer une progression inexistante en mode silencieux.'
    }
    if ($manifestText -match '(?ms)AppsAndFeaturesEntries:.*?DisplayVersion:') {
        throw 'DisplayVersion doit etre omis quand il est identique a PackageVersion.'
    }
} finally {
    Remove-Item -LiteralPath $wingetOutput -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'Metadonnees, notes, empreintes et modeles WinGet valides.'
