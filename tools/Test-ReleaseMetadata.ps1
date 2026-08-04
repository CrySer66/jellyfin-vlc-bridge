param([string]$Version = '')

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot

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

foreach ($workflowSource in @($workflow, $ciWorkflow)) {
    if ($workflowSource -notmatch '(?ms)dotnet-version:\s*\|\s*\r?\n\s+8\.0\.x\s*\r?\n\s+10\.0\.x') {
        throw 'Le workflow n installe pas les SDK .NET 8 et 10 requis par le projet.'
    }
}

foreach ($workflowSource in @($workflow, $ciWorkflow)) {
    foreach ($usesMatch in [regex]::Matches($workflowSource, '(?m)^\s*uses:\s*(?<action>[^\s#]+)')) {
        $action = $usesMatch.Groups['action'].Value
        if ($action -notmatch '@[0-9a-f]{40}$') {
            throw "Action GitHub non figee par empreinte : $action"
        }
    }
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
$attestCommit = '508db95dd578ae2727ebd6217d5ba78e4fbda05d'
if ([regex]::Matches($workflow, "uses:\s*actions/attest@$attestCommit").Count -ne 2) {
    throw 'La Release doit attester separement le Setup et le ZIP avec une action figee.'
}
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
} finally {
    Remove-Item -LiteralPath $wingetOutput -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'Metadonnees, notes, empreintes et modeles WinGet valides.'
