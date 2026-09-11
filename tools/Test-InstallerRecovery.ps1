param()

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$installerPath = Join-Path $projectDirectory 'installer\Installer-GUI.ps1'
$tokens = $null
$parseErrors = $null
$installerAst = [Management.Automation.Language.Parser]::ParseFile($installerPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw ('Invalid installer syntax: ' + $parseErrors[0].Message) }

# Import only these function definitions. The installer entry point, registry
# integration, process discovery and real GUI are never evaluated by this test.
foreach ($functionName in @('Reset-InstallationAfterFailure', 'Remove-MaintenanceDirectory', 'Remove-StaleApplicationTransactions')) {
    $definition = @($installerAst.EndBlock.Statements | Where-Object {
        $_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq $functionName
    })
    if ($definition.Count -ne 1) { throw "Expected one top-level installer function: $functionName" }
    . ([scriptblock]::Create($definition[0].Extent.Text))
}

function Assert-Recovery([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

$script:recoveryLog = New-Object 'Collections.Generic.List[string]'
function Write-InstallerLog([string]$level, [string]$message) {
    $script:recoveryLog.Add($level + ': ' + $message)
}
function T([string]$key, [object[]]$values = @()) { return $key + $(if ($values.Count) { ': ' + ($values -join ', ') } else { '' }) }
function Set-SetupStage([int]$stage) { $script:lastSetupStage = $stage }
function Undo-ApplicationTransaction {
    $script:undoCalls++
    if ($script:failRollback) { throw 'Simulated rollback failure: backup is still needed.' }
    $script:applicationTransaction = $null
}
function Exit-MaintenanceLock { $script:lockReleaseCalls++ }

function New-RecoveryControl {
    return [PSCustomObject]@{
        IsEnabled = $false; IsIndeterminate = $true; Value = 50
        Content = ''; Text = ''; Visibility = 'Visible'; Foreground = ''
    }
}

function Test-ResetRecovery([bool]$rollbackFails) {
    $script:failRollback = $rollbackFails
    $script:undoCalls = 0
    $script:lockReleaseCalls = 0
    $script:lastSetupStage = 1
    $script:applicationTransaction = [PSCustomObject]@{ BackupDirectory = 'mock-backup' }
    $script:timer = [PSCustomObject]@{ StopCalls = 0 }
    $script:timer | Add-Member ScriptMethod Stop { $this.StopCalls++ }
    $fakeProcess = [PSCustomObject]@{ HasExited = $false; KillCalls = 0; WaitCalls = 0; DisposeCalls = 0 }
    $fakeProcess | Add-Member ScriptMethod Kill { $this.KillCalls++; $this.HasExited = $true }
    $fakeProcess | Add-Member ScriptMethod WaitForExit { param([int]$timeout) $this.WaitCalls++; return $this.HasExited }
    $fakeProcess | Add-Member ScriptMethod Dispose { $this.DisposeCalls++ }
    $script:setupProcess = $fakeProcess
    foreach ($control in @('progress', 'installButton', 'serverBox', 'changeServerButton', 'cancelButton', 'codeCard', 'statusLabel', 'instructions')) {
        Set-Variable -Name $control -Scope Script -Value (New-RecoveryControl)
    }

    Reset-InstallationAfterFailure ([InvalidOperationException]::new('Simulated Quick Connect failure.'))

    Assert-Recovery ($script:undoCalls -eq 1) 'Recovery did not try to restore the application exactly once.'
    Assert-Recovery ($script:lastSetupStage -eq 0) 'Recovery did not return the assistant to its initial step.'
    Assert-Recovery ($script:timer.StopCalls -eq 1) 'Recovery did not stop the Quick Connect timer.'
    Assert-Recovery ($fakeProcess.KillCalls -eq 1 -and $fakeProcess.WaitCalls -eq 1 -and $fakeProcess.DisposeCalls -eq 1 -and $null -eq $script:setupProcess) 'Recovery did not finish and dispose the pending Quick Connect process.'
    Assert-Recovery (-not $script:progress.IsIndeterminate -and $script:progress.Value -eq 0) 'Recovery left an active progress indicator.'
    Assert-Recovery ($script:cancelButton.IsEnabled) 'The user must still be able to close the assistant after a failure.'
    if ($rollbackFails) {
        Assert-Recovery (-not $script:installButton.IsEnabled) 'Retry must stay disabled when rollback fails.'
        Assert-Recovery ($script:lockReleaseCalls -eq 0) 'A failed rollback must keep the maintenance lock until the assistant closes.'
        Assert-Recovery ($null -ne $script:applicationTransaction) 'A failed rollback lost the transaction needed for recovery.'
        Assert-Recovery ($script:statusLabel.Text -match 'RollbackIncomplete') 'A failed rollback must explain that recovery is incomplete.'
    } else {
        Assert-Recovery ($script:installButton.IsEnabled) 'A successful rollback must make Retry available.'
        Assert-Recovery ($script:lockReleaseCalls -eq 1) 'A successful rollback must release the maintenance lock.'
        Assert-Recovery ($null -eq $script:applicationTransaction) 'A successful rollback left the transaction active.'
    }
}

Test-ResetRecovery $true
Test-ResetRecovery $false
Write-Host 'OK  Failed rollback blocks Retry and keeps its lock; successful recovery permits Retry'

$workDirectory = [IO.Path]::GetFullPath((Join-Path $projectDirectory 'work')).TrimEnd('\')
$testDirectory = [IO.Path]::GetFullPath((Join-Path $workDirectory ('installer-recovery-' + [Guid]::NewGuid().ToString('N'))))
if (-not $testDirectory.StartsWith($workDirectory + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Installer recovery tests must stay inside the project work directory.'
}
try {
    $script:rootDirectory = Join-Path $testDirectory 'BridgeData'
    [void][IO.Directory]::CreateDirectory($script:rootDirectory)
    [IO.File]::WriteAllText((Join-Path $script:rootDirectory '.jvb-isolated-test'), 'Jellyfin VLC Bridge recovery test')
    $backup = Join-Path $script:rootDirectory ('App.backup-' + [Guid]::NewGuid().ToString('N'))
    $staging = Join-Path $script:rootDirectory ('App.staging-' + [Guid]::NewGuid().ToString('N'))
    $failed = Join-Path $script:rootDirectory ('App.failed-' + [Guid]::NewGuid().ToString('N'))
    $active = Join-Path $script:rootDirectory 'App'
    $unrelated = Join-Path $script:rootDirectory 'App.backup-personal'
    foreach ($directory in @($backup, $staging, $failed, $active, $unrelated)) {
        [void][IO.Directory]::CreateDirectory($directory)
        [IO.File]::WriteAllText((Join-Path $directory 'retained-file.txt'), 'previous-installation')
        [IO.Directory]::SetLastWriteTimeUtc($directory, [DateTime]::UtcNow.AddDays(-30))
    }

    Remove-StaleApplicationTransactions

    Assert-Recovery (Test-Path -LiteralPath $backup -PathType Container) 'Stale cleanup removed a backup that may be the only recoverable application.'
    Assert-Recovery ([IO.File]::ReadAllText((Join-Path $backup 'retained-file.txt')) -eq 'previous-installation') 'Stale cleanup changed the previous application backup.'
    Assert-Recovery (-not (Test-Path -LiteralPath $staging) -and -not (Test-Path -LiteralPath $failed)) 'Stale cleanup did not remove disposable staging and failed directories.'
    foreach ($preserved in @($active, $unrelated)) {
        Assert-Recovery (Test-Path -LiteralPath (Join-Path $preserved 'retained-file.txt') -PathType Leaf) 'Stale cleanup touched the active application or an unrelated directory.'
    }
    Write-Host 'OK  Stale cleanup preserves recovery backups and removes only staging or failed transactions'
} finally {
    $resolvedTestDirectory = [IO.Path]::GetFullPath($testDirectory)
    if ($resolvedTestDirectory.StartsWith($workDirectory + '\', [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedTestDirectory)) {
        Remove-Item -LiteralPath $resolvedTestDirectory -Recurse -Force
    }
}
