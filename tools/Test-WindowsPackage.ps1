param(
    [string]$Version = '1.18.0'
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$packageDirectory = Join-Path $projectDirectory "outputs\JellyfinVlcBridge-$Version-win-x64"
$executable = Join-Path $packageDirectory 'jellyfin-vlc-bridge.exe'
$controlExecutable = Join-Path $packageDirectory 'jellyfin-vlc-bridge-control.exe'
$setup = Join-Path $projectDirectory "outputs\JellyfinVlcBridge-$Version-Setup.exe"
$zip = Join-Path $projectDirectory "outputs\JellyfinVlcBridge-$Version-win-x64.zip"
$runtimeTestRoot = Join-Path $projectDirectory ('work\package-runtime-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runtimeTestRoot -Force | Out-Null

foreach ($path in @($executable, $controlExecutable, $setup, $zip)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Fichier de paquet manquant : $path" }
}

$localizationPath = Join-Path $packageDirectory 'Localization.ps1'
if (-not (Test-Path -LiteralPath $localizationPath)) {
    throw 'Le module de traduction est absent du paquet Windows.'
}
$themePath = Join-Path $packageDirectory 'UiTheme.ps1'
if (-not (Test-Path -LiteralPath $themePath)) {
    throw 'Le thème graphique Windows est absent du paquet.'
}
$packagedScripts = Get-ChildItem -LiteralPath $packageDirectory -Filter '*.ps1' -File
foreach ($packagedScript in $packagedScripts) {
    $scriptBytes = [IO.File]::ReadAllBytes($packagedScript.FullName)
    $hasUtf8Bom = $scriptBytes.Length -ge 3 -and
        $scriptBytes[0] -eq 0xEF -and $scriptBytes[1] -eq 0xBB -and $scriptBytes[2] -eq 0xBF
    if (-not $hasUtf8Bom) {
        throw "Le script $($packagedScript.Name) n'est pas encodé en UTF-8 compatible avec Windows PowerShell."
    }
}
Write-Host 'OK  Accents UTF-8 compatibles avec Windows PowerShell'

$localizationScript = Get-Content -LiteralPath $localizationPath -Raw -Encoding UTF8
if ($localizationScript -notmatch 'LanguageAuto' -or
    $localizationScript -notmatch 'LanguageFrench' -or
    $localizationScript -notmatch 'LanguageEnglish') {
    throw 'Les traductions française et anglaise sont incomplètes.'
}
Write-Host 'OK  Traductions française et anglaise incluses'

$themeScript = Get-Content -LiteralPath $themePath -Raw -Encoding UTF8
if ($themeScript -notmatch 'SetCurrentProcessExplicitAppUserModelID' -or
    $themeScript -notmatch 'CrySer66\.JellyfinVlcBridge' -or
    $themeScript -notmatch 'DwmSetWindowAttribute' -or
    $themeScript -notmatch 'Enable-JvbModernWindow') {
    throw 'Le thème ne configure pas complètement l identité Windows moderne.'
}
Write-Host 'OK  Identité et icône dédiées pour la barre des tâches'
if ($themeScript -notmatch 'New-JvbRoundedPath' -or
    $themeScript -notmatch 'BorderSize\s*=\s*0') {
    throw 'Les boutons et cartes n utilisent pas le nouveau rendu arrondi sans bordure parasite.'
}
Write-Host 'OK  Coins arrondis propres pour les cartes et boutons'

function Read-Exactly([IO.Stream]$stream, [byte[]]$buffer) {
    $offset = 0
    while ($offset -lt $buffer.Length) {
        $read = $stream.Read($buffer, $offset, $buffer.Length - $offset)
        if ($read -eq 0) { throw 'Le processus a ferme sa sortie avant la reponse complete.' }
        $offset += $read
    }
}

function New-HiddenProcess([string]$arguments, [string]$isolatedLocalAppData = '') {
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $executable
    $startInfo.Arguments = $arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    if (-not [string]::IsNullOrWhiteSpace($isolatedLocalAppData)) {
        $startInfo.EnvironmentVariables['LOCALAPPDATA'] = $isolatedLocalAppData
    }
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

$statusProcess = New-HiddenProcess 'status --json' $runtimeTestRoot
if (-not $statusProcess.Start()) { throw 'Impossible de lancer le diagnostic redirige.' }
$statusProcess.StandardInput.Close()
$statusOutput = $statusProcess.StandardOutput.ReadToEnd().Trim()
$statusError = $statusProcess.StandardError.ReadToEnd().Trim()
$statusProcess.WaitForExit()
if ($statusProcess.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($statusOutput)) {
    throw "Diagnostic redirige invalide. Sortie='$statusOutput' Erreur='$statusError'"
}
$status = $statusOutput | ConvertFrom-Json
if ($status.version -ne $Version) { throw "Version de diagnostic inattendue : $($status.version)" }
Write-Host 'OK  Diagnostic JSON redirige pour le centre de controle'

$controlScript = Get-Content -LiteralPath (Join-Path $packageDirectory 'Centre-Controle.ps1') -Raw
if ($controlScript -notmatch 'RedirectStandardOutput\s*=\s*\$true' -or
    $controlScript -notmatch 'StandardOutput\.ReadToEnd\(\)' -or
    $controlScript -notmatch 'Set-JvbLanguagePreference' -or
    $controlScript -notmatch 'UiTheme\.ps1' -or
    $controlScript -notmatch 'New-JvbCard') {
    throw 'Le centre de controle ne capture pas explicitement le diagnostic de l application graphique.'
}
Write-Host 'OK  Centre de controle compatible avec l application sans console'
if ($controlScript -notmatch 'NotifyIcon' -or
    $controlScript -notmatch 'StartInTray' -or
    $controlScript -notmatch 'Hide-ControlCenter' -or
    $controlScript -notmatch 'TrayExit' -or
    $controlScript -notmatch 'ShowEventName' -or
    $controlScript -notmatch 'Center-ControlCenterOnActiveScreen' -or
    $controlScript -notmatch 'SetDesktopLocation\(\$left,\s*\$top\)' -or
    $controlScript -notmatch 'Application\]::Run\(\$form\)' -or
    $controlScript -notmatch '\$_\.Cancel\s*=\s*\$true' -or
    $controlScript -notmatch '(?s)Add_FormClosing.*?\$form\.Opacity\s*=\s*0.*?\$form\.ShowInTaskbar\s*=\s*\$false.*?\$_\.Cancel' -or
    $controlScript -notmatch '(?s)Add_FormClosing.*?BeginInvoke.*?Hide-ControlCenter' -or
    $controlScript -match '\$form\.Add_Resize\(' -or
    $controlScript -match '\[void\]\$form\.ShowDialog\(\)') {
    throw 'Le centre de controle ne gere pas completement la zone de notification.'
}
$bootstrapSource = Get-Content -LiteralPath (
    Join-Path $projectDirectory 'installer\ControlCenterBootstrap.cs') -Raw
if ($bootstrapSource -notmatch 'MutexName' -or
    $bootstrapSource -notmatch 'EventWaitHandle' -or
    $bootstrapSource -notmatch '"--tray"' -or
    $bootstrapSource -notmatch 'ShowEventName') {
    throw 'Le lanceur du centre de controle ne gere pas l instance unique ou sa restauration.'
}
$controlValidationInfo = New-Object Diagnostics.ProcessStartInfo
$controlValidationInfo.FileName = $controlExecutable
$controlValidationInfo.Arguments = '--validate-only'
$controlValidationInfo.WorkingDirectory = $packageDirectory
$controlValidationInfo.UseShellExecute = $false
$controlValidationInfo.CreateNoWindow = $true
$controlValidation = [Diagnostics.Process]::Start($controlValidationInfo)
if (-not $controlValidation) { throw 'Impossible de lancer la validation du centre de controle.' }
$controlValidation.WaitForExit()
if ($controlValidation.ExitCode -ne 0) {
    throw "Le centre de controle a echoue en validation : $($controlValidation.ExitCode)"
}
$controlValidation.Dispose()
Write-Host 'OK  Zone de notification et instance unique du centre de controle'
if ($controlScript -notmatch 'Show-ChangeServerDialog' -or
    $controlScript -notmatch 'setup --server' -or
    $controlScript -notmatch 'RequestQuickConnect' -or
    $controlScript -notmatch '\$changeServerButton') {
    throw 'Le changement de serveur Quick Connect est absent du centre de controle.'
}
$programSource = Get-Content -LiteralPath (
    Join-Path $projectDirectory 'src\JellyfinVlcBridge.Cli\Program.cs') -Raw
if ($programSource -notmatch 'VlcPath\s*=\s*existing\?\.VlcPath' -or
    $programSource -notmatch 'PlaybackMode\s*=\s*existing\?\.PlaybackMode' -or
    $programSource -notmatch 'PathMappings\s*=\s*existing\?\.PathMappings' -or
    $programSource -notmatch 'ProgressSyncEnabled\s*=\s*existing\?\.ProgressSyncEnabled') {
    throw 'Quick Connect ne conserve pas tous les reglages de lecture lors du changement de serveur.'
}
if ($programSource -notmatch 'CurrentVersion\\Run' -or
    $programSource -notmatch 'DeleteValue\("JellyfinVlcBridge"') {
    throw 'La desinstallation ne retire pas le demarrage automatique du centre de controle.'
}
$secretStoreSource = Get-Content -LiteralPath (
    Join-Path $projectDirectory 'src\JellyfinVlcBridge.Core\SecretStore.cs') -Raw
if ($programSource -notmatch 'DeleteByPrefix\(SecretKeys\.Prefix\)' -or
    $secretStoreSource -notmatch 'CredEnumerateW' -or
    $secretStoreSource -notmatch 'StartsWith\(prefix,\s*StringComparison\.OrdinalIgnoreCase\)' -or
    $secretStoreSource -notmatch 'const string Prefix = "JellyfinVlcBridge:"') {
    throw 'La purge ne supprime pas strictement tous les secrets appartenant au Bridge.'
}
Write-Host 'OK  Changement de serveur Quick Connect avec réglages conservés'

$uninstallerScript = Get-Content -LiteralPath (Join-Path $packageDirectory 'Desinstaller-GUI.ps1') -Raw
$uninstallerLauncher = Get-Content -LiteralPath (Join-Path $packageDirectory 'DESINSTALLER-WINDOWS.cmd') -Raw
if ($uninstallerScript -match '&\s+\$executable\s+uninstall-cleanup' -or
    $uninstallerScript -notmatch 'ProcessStartInfo' -or
    $uninstallerScript -notmatch 'WaitForExit\(30000\)' -or
    $uninstallerScript -notmatch '\.ExitCode' -or
    $uninstallerScript -notmatch 'jellyfin-vlc-bridge-control' -or
    $uninstallerScript -notmatch 'JellyfinVlcBridgeUninstall-' -or
    $uninstallerScript -notmatch 'TemporaryRun' -or
    $uninstallerScript -notmatch 'Set-Location\s+-LiteralPath\s+\$env:TEMP' -or
    $uninstallerScript -notmatch 'UiTheme\.ps1' -or
    $uninstallerScript -notmatch 'Show-UninstallChoice' -or
    $uninstallerScript -notmatch '\[switch\]\$Silent' -or
    $uninstallerScript -notmatch '\[switch\]\$Purge' -or
    $uninstallerScript -notmatch '\$temporaryArguments\s*\+=' -or
    $uninstallerScript -notmatch '\$temporaryProcess\.WaitForExit\(90000\)' -or
    $uninstallerScript -notmatch 'exit\s+\$temporaryExitCode' -or
    $uninstallerScript -notmatch 'CrySer66\.JellyfinVlcBridge\.Maintenance' -or
    $uninstallerScript -notmatch 'Assert-BridgeRegistrationRemoved' -or
    $uninstallerScript -notmatch 'if\s*\(\$Silent\)\s*\{\s*throw\s+\$cleanupWarning' -or
    $uninstallerScript -notmatch 'if\s*\(\$Purge\)\s*\{\s*''purge''\s*\}\s*else\s*\{\s*''keep''\s*\}') {
    throw 'Le desinstallateur ne gere pas correctement application graphique ou centre de controle.'
}
if ($uninstallerLauncher -notmatch 'Desinstaller-GUI\.ps1' -or
    $uninstallerLauncher -notmatch 'WindowStyle Hidden' -or
    $uninstallerLauncher -match 'Desinstaller-JellyfinVlcBridge\.ps1') {
    throw 'Le lanceur de desinstallation manuel ne delegue pas au desinstallateur transactionnel.'
}
$installerScript = Get-Content -LiteralPath (Join-Path $packageDirectory 'Installer-GUI.ps1') -Raw
$cliSource = Get-Content -LiteralPath (Join-Path $projectDirectory 'src\JellyfinVlcBridge.Cli\Program.cs') -Raw -Encoding UTF8
$installerTokens = $null
$installerParseErrors = $null
$installerAst = [System.Management.Automation.Language.Parser]::ParseInput(
    $installerScript,
    'Installer-GUI.ps1',
    [ref]$installerTokens,
    [ref]$installerParseErrors)
if ($installerParseErrors.Count -gt 0) {
    throw ('Le script d installation contient une erreur de syntaxe : ' + $installerParseErrors[0].Message)
}
$topLevelInstallerFunctions = @(
    $installerAst.EndBlock.Statements |
        Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] } |
        ForEach-Object Name
)
foreach ($requiredFunction in @(
    'Copy-ApplicationFiles',
    'Complete-ApplicationTransaction',
    'Undo-ApplicationTransaction',
    'Register-WindowsApplication'
)) {
    if ($requiredFunction -notin $topLevelInstallerFunctions) {
        throw "La fonction critique $requiredFunction n est pas definie au niveau principal de l installateur."
    }
}
if ($installerScript -notmatch '\$uninstallShortcut\.WorkingDirectory\s*=\s*\$env:TEMP' -or
    $installerScript -notmatch '\$application\.IconLocation\s*=\s*\$controlCenter' -or
    $installerScript -notmatch 'CurrentVersion\\Run' -or
    $installerScript -notmatch '" --tray' -or
    $installerScript -notmatch 'UiTheme\.ps1' -or
    $installerScript -notmatch 'QuietUninstallString' -or
    $installerScript -notmatch 'QuietUninstallString.*-Silent' -or
    $installerScript -notmatch '\$script:silentInstall' -or
    $installerScript -notmatch 'Install-ApplicationIntegrations' -or
    $installerScript -notmatch 'CrySer66\.JellyfinVlcBridge\.Maintenance' -or
    $installerScript -notmatch 'App\.staging-' -or
    $installerScript -notmatch 'App\.backup-' -or
    $installerScript -notmatch 'Undo-ApplicationTransaction') {
    throw 'Le raccourci de desinstallation conserve encore le dossier application comme repertoire de travail.'
}
if ($installerScript -match "uninstall-cleanup --purge[\s\S]{0,800}RequestingCode" -or
    $cliSource -notmatch 'InstallNativeHost\(\);[\s\S]{0,800}credentialStore\.Write[\s\S]{0,800}updatedConfig\.Save\(\);[\s\S]{0,800}credentialStore\.Delete\(previousSecretKey\)' -or
    $installerScript -notmatch '\$script:setupProcess\.HasExited[\s\S]{0,300}\$script:setupProcess\.ExitCode\s+-eq\s+0[\s\S]{0,300}Complete-Installation') {
    throw 'Le changement de serveur ne conserve pas l ancienne connexion jusqu a la reussite de Quick Connect.'
}
Write-Host 'OK  Fonctions transactionnelles de l installateur reconnues par PowerShell'
Write-Host 'OK  Ancienne connexion conservee jusqu au nouveau Quick Connect'
Write-Host 'OK  Desinstallation executee hors du dossier supprime et sans faux code erreur'

$setupBootstrapSource = Get-Content -LiteralPath (
    Join-Path $projectDirectory 'installer\SetupBootstrap.cs') -Raw
if ($setupBootstrapSource -notmatch 'Main\(string\[\]\s+args\)' -or
    $setupBootstrapSource -notmatch 'IsSilentArgument' -or
    $setupBootstrapSource -notmatch 'case\s+"/quiet"' -or
    $setupBootstrapSource -notmatch 'case\s+"/s"' -or
    $setupBootstrapSource -notmatch '\(silent\s*\?\s*" -Silent"' -or
    $setupBootstrapSource -notmatch 'WaitForExit\(120000\)' -or
    $setupBootstrapSource -notmatch 'WriteSilentLog' -or
    $setupBootstrapSource -notmatch 'if\s*\(silent\)\s+WriteSilentLog[\s\S]*?else\s+MessageBox\.Show') {
    throw 'L installateur EXE ne propage pas correctement le mode silencieux.'
}
$invalidSilentInfo = New-Object Diagnostics.ProcessStartInfo
$invalidSilentInfo.FileName = $setup
$invalidSilentInfo.Arguments = '/quiet --option-inconnue'
$invalidSilentInfo.UseShellExecute = $false
$invalidSilentInfo.CreateNoWindow = $true
$invalidSilentProcess = [Diagnostics.Process]::Start($invalidSilentInfo)
if (-not $invalidSilentProcess) { throw 'Impossible de tester les options silencieuses de l installateur.' }
if (-not $invalidSilentProcess.WaitForExit(10000)) {
    try { $invalidSilentProcess.Kill() } catch { }
    throw 'L installateur silencieux a affiche une interface pour une option invalide.'
}
if ($invalidSilentProcess.ExitCode -eq 0) {
    throw 'L installateur silencieux accepte une option inconnue.'
}
$invalidSilentProcess.Dispose()
Write-Host 'OK  Installation silencieuse sans interface et options strictement validees'

function New-FakeBridgePackage([string]$testRoot) {
    $testPackage = Join-Path $testRoot 'Package'
    New-Item -ItemType Directory -Path $testPackage -Force | Out-Null
    Get-ChildItem -LiteralPath $packageDirectory -Force | Copy-Item -Destination $testPackage -Recurse -Force
    $fakeSource = Join-Path $testRoot 'FakeBridge.cs'
    $fakeExecutable = Join-Path $testPackage 'jellyfin-vlc-bridge.exe'
    $source = @'
using System;
using System.IO;
using System.Threading;

internal static class FakeBridge
{
    private static int Main(string[] args)
    {
        string command = string.Join(" ", args);
        string log = Environment.GetEnvironmentVariable("JVB_FAKE_LOG");
        if (string.IsNullOrWhiteSpace(log)) log = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "commands.log");
        File.AppendAllText(log, command + Environment.NewLine);
        int delay;
        if (int.TryParse(Environment.GetEnvironmentVariable("JVB_FAKE_DELAY_MS"), out delay) && delay > 0)
            Thread.Sleep(Math.Min(delay, 10000));
        if (Array.IndexOf(args, "--hold") >= 0) Thread.Sleep(60000);
        if (command.StartsWith("install-native-host", StringComparison.OrdinalIgnoreCase) &&
            Environment.GetEnvironmentVariable("JVB_FAKE_FAIL_NATIVE") == "1") return 17;
        if (command.StartsWith("uninstall-cleanup", StringComparison.OrdinalIgnoreCase) &&
            Environment.GetEnvironmentVariable("JVB_FAKE_FAIL_CLEANUP") == "1") return 23;
        return 0;
    }
}
'@
    [IO.File]::WriteAllText($fakeSource, $source, (New-Object Text.UTF8Encoding($false)))
    $compiler = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $compiler)) { throw 'Compilateur de test Windows introuvable.' }
    Remove-Item -LiteralPath $fakeExecutable -Force -ErrorAction SilentlyContinue
    & $compiler /nologo /target:winexe "/out:$fakeExecutable" $fakeSource
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $fakeExecutable)) {
        throw 'La creation du faux Bridge de test a echoue.'
    }
    Copy-Item -LiteralPath $fakeExecutable `
        -Destination (Join-Path $testPackage 'jellyfin-vlc-bridge-control.exe') -Force
    return $testPackage
}

function Invoke-IsolatedInstaller(
    [string]$testPackage,
    [string]$bridgeRoot,
    [string]$fakeLog,
    [bool]$failNative,
    [int]$expectedExitCode
) {
    $processInfo = New-Object Diagnostics.ProcessStartInfo
    $processInfo.FileName = 'powershell.exe'
    $processInfo.Arguments =
        "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $testPackage 'Installer-GUI.ps1')`" -Silent -TestRoot `"$bridgeRoot`""
    $processInfo.WorkingDirectory = $env:TEMP
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.EnvironmentVariables['JELLYFIN_VLC_BRIDGE_ISOLATED_TEST'] = '1'
    $processInfo.EnvironmentVariables['JVB_FAKE_LOG'] = $fakeLog
    if ($failNative) { $processInfo.EnvironmentVariables['JVB_FAKE_FAIL_NATIVE'] = '1' }
    else { $processInfo.EnvironmentVariables.Remove('JVB_FAKE_FAIL_NATIVE') }
    $process = [Diagnostics.Process]::Start($processInfo)
    if (-not $process) { throw 'Impossible de lancer l installation silencieuse isolee.' }
    $outputTask = $process.StandardOutput.ReadToEndAsync()
    $errorTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(30000)) {
        try { $process.Kill() } catch { }
        throw 'L installation silencieuse isolee a depasse 30 secondes.'
    }
    $output = $outputTask.GetAwaiter().GetResult().Trim()
    $errorOutput = $errorTask.GetAwaiter().GetResult().Trim()
    $exitCode = $process.ExitCode
    $process.Dispose()
    if ($exitCode -ne $expectedExitCode) {
        $installerLog = Join-Path $bridgeRoot 'Logs\installer.log'
        $logText = if (Test-Path -LiteralPath $installerLog) {
            (Get-Content -LiteralPath $installerLog -Raw -ErrorAction SilentlyContinue).Trim()
        } else { '' }
        throw "Code installation isolee inattendu : $exitCode. Sortie='$output' Erreur='$errorOutput' Journal='$logText'"
    }
}

function Test-IsolatedSilentInstall {
    $testRoot = Join-Path $projectDirectory ('work\silent-install-' + [Guid]::NewGuid().ToString('N'))
    try {
        $testPackage = New-FakeBridgePackage $testRoot
        $bridgeRoot = Join-Path $testRoot 'BridgeData'
        $fakeLog = Join-Path $testRoot 'bridge-commands.log'
        New-Item -ItemType Directory -Path $bridgeRoot -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $bridgeRoot '.jvb-isolated-test'), 'Jellyfin VLC Bridge package test')
        [IO.File]::WriteAllText((Join-Path $bridgeRoot 'config.json'), '{"preserve":true}')

        Invoke-IsolatedInstaller $testPackage $bridgeRoot $fakeLog $false 0
        $installedApp = Join-Path $bridgeRoot 'App'
        if (-not (Test-Path -LiteralPath (Join-Path $installedApp 'jellyfin-vlc-bridge.exe'))) {
            throw 'L installation silencieuse reelle n a pas deploye le Bridge.'
        }
        if (-not (Test-Path -LiteralPath (Join-Path $bridgeRoot 'config.json'))) {
            throw 'L installation silencieuse reelle n a pas conserve la configuration.'
        }
        $commands = Get-Content -LiteralPath $fakeLog -Raw
        if ($commands -notmatch 'install-protocol' -or $commands -notmatch 'install-native-host') {
            throw 'L installation silencieuse n a pas execute les integrations du Bridge.'
        }

        [IO.File]::WriteAllText((Join-Path $installedApp 'Centre-Controle.ps1'), 'ancienne-version')
        Remove-Item -LiteralPath $fakeLog -Force
        Invoke-IsolatedInstaller $testPackage $bridgeRoot $fakeLog $true 1
        $restored = Get-Content -LiteralPath (Join-Path $installedApp 'Centre-Controle.ps1') -Raw
        if ($restored -ne 'ancienne-version') {
            $transactionLog = Get-Content -LiteralPath (Join-Path $bridgeRoot 'Logs\installer.log') `
                -Raw -ErrorAction SilentlyContinue
            throw "Le retour arriere silencieux n a pas restaure l ancienne application. Valeur='$restored' Journal='$transactionLog'"
        }
        if (Get-ChildItem -LiteralPath $bridgeRoot -Directory -Filter 'App.*-*') {
            throw 'Une transaction silencieuse a laisse un dossier staging/backup.'
        }

        $mutex = New-Object Threading.Mutex($false, 'Local\CrySer66.JellyfinVlcBridge.Maintenance')
        $ownsMutex = $mutex.WaitOne(0, $false)
        try {
            if (-not $ownsMutex) { throw 'Le verrou de test est deja occupe.' }
            Invoke-IsolatedInstaller $testPackage $bridgeRoot $fakeLog $false 1
        } finally {
            if ($ownsMutex) { $mutex.ReleaseMutex() }
            $mutex.Dispose()
        }
    } finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Test-IsolatedSilentInstall
Write-Host 'OK  Installation silencieuse reelle, rollback et verrou concurrent isoles'

function Test-IsolatedCliCleanup {
    $testRoot = Join-Path $projectDirectory ('work\cli-cleanup-' + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $testRoot '.jvb-isolated-test'), 'Jellyfin VLC Bridge package test')
        foreach ($name in @('native-messaging-host.json', 'extension-heartbeat.json', 'config.json', 'playback-preferences.json')) {
            [IO.File]::WriteAllText((Join-Path $testRoot $name), 'test')
        }
        foreach ($purge in @($false, $true)) {
            if ($purge) {
                foreach ($name in @('native-messaging-host.json', 'extension-heartbeat.json')) {
                    [IO.File]::WriteAllText((Join-Path $testRoot $name), 'test')
                }
            }
            $arguments = "uninstall-cleanup --isolated-test-root `"$testRoot`"" + $(if ($purge) { ' --purge' } else { '' })
            $cleanupProcess = New-HiddenProcess $arguments
            $cleanupProcess.StartInfo.EnvironmentVariables['JELLYFIN_VLC_BRIDGE_ISOLATED_TEST'] = '1'
            if (-not $cleanupProcess.Start()) { throw 'Impossible de lancer uninstall-cleanup isole.' }
            $cleanupProcess.StandardInput.Close()
            $cleanupOutput = $cleanupProcess.StandardOutput.ReadToEnd().Trim()
            $cleanupError = $cleanupProcess.StandardError.ReadToEnd().Trim()
            if (-not $cleanupProcess.WaitForExit(15000)) {
                try { $cleanupProcess.Kill() } catch { }
                throw 'uninstall-cleanup isole a depasse le delai.'
            }
            if ($cleanupProcess.ExitCode -ne 0) {
                throw "uninstall-cleanup isole a echoue. Sortie='$cleanupOutput' Erreur='$cleanupError'"
            }
            $cleanupProcess.Dispose()
            if ((Test-Path -LiteralPath (Join-Path $testRoot 'native-messaging-host.json')) -or
                (Test-Path -LiteralPath (Join-Path $testRoot 'extension-heartbeat.json'))) {
                throw 'uninstall-cleanup n a pas retire les fichiers d integration.'
            }
            if (-not $purge -and -not (Test-Path -LiteralPath (Join-Path $testRoot 'config.json'))) {
                throw 'uninstall-cleanup sans purge a supprime la configuration.'
            }
            if ($purge -and ((Test-Path -LiteralPath (Join-Path $testRoot 'config.json')) -or
                (Test-Path -LiteralPath (Join-Path $testRoot 'playback-preferences.json')))) {
                throw 'uninstall-cleanup --purge a conserve des donnees locales.'
            }
        }
    } finally {
        if (Test-Path -LiteralPath $testRoot) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Test-IsolatedCliCleanup
Write-Host 'OK  uninstall-cleanup reel valide en mode isole'

function Invoke-IsolatedSilentUninstall([bool]$removeSettings, [bool]$failCleanup) {
    $testRoot = Join-Path $projectDirectory ('work\silent-uninstall-' + [Guid]::NewGuid().ToString('N'))
    $workParent = [IO.Path]::GetFullPath((Join-Path $projectDirectory 'work')).TrimEnd('\') + '\'
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    if (-not $resolvedTestRoot.StartsWith($workParent, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Chemin de test de desinstallation inattendu : $resolvedTestRoot"
    }
    try {
        $testPackage = New-FakeBridgePackage $resolvedTestRoot
        $testLocalAppData = Join-Path $resolvedTestRoot 'LocalAppData'
        $testBridgeRoot = Join-Path $testLocalAppData 'JellyfinVlcBridge'
        $testApp = Join-Path $testBridgeRoot 'App'
        $fakeLog = Join-Path $resolvedTestRoot 'uninstall-commands.log'
        New-Item -ItemType Directory -Path $testBridgeRoot -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $testBridgeRoot '.jvb-isolated-test'), 'Jellyfin VLC Bridge package test')
        Invoke-IsolatedInstaller $testPackage $testBridgeRoot $fakeLog $false 0
        [IO.File]::WriteAllText((Join-Path $testBridgeRoot 'config.json'), '{"test":true}')
        $orphanTransaction = Join-Path $testBridgeRoot ('App.backup-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $orphanTransaction -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $orphanTransaction 'ancien-fichier.txt'), 'test')
        Remove-Item -LiteralPath $fakeLog -Force -ErrorAction SilentlyContinue

        $uninstallInfo = New-Object Diagnostics.ProcessStartInfo
        $uninstallInfo.FileName = 'powershell.exe'
        $uninstallInfo.Arguments =
            "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $testPackage 'Desinstaller-GUI.ps1')`" -Silent -IsolatedTest" +
            $(if ($removeSettings) { ' -Purge' } else { '' })
        $uninstallInfo.WorkingDirectory = $env:TEMP
        $uninstallInfo.UseShellExecute = $false
        $uninstallInfo.CreateNoWindow = $true
        $uninstallInfo.RedirectStandardOutput = $true
        $uninstallInfo.RedirectStandardError = $true
        $uninstallInfo.EnvironmentVariables['LOCALAPPDATA'] = $testLocalAppData
        $uninstallInfo.EnvironmentVariables['JELLYFIN_VLC_BRIDGE_ISOLATED_TEST'] = '1'
        $uninstallInfo.EnvironmentVariables['JVB_FAKE_LOG'] = $fakeLog
        if ($failCleanup) { $uninstallInfo.EnvironmentVariables['JVB_FAKE_FAIL_CLEANUP'] = '1' }
        else { $uninstallInfo.EnvironmentVariables.Remove('JVB_FAKE_FAIL_CLEANUP') }
        $uninstallProcess = [Diagnostics.Process]::Start($uninstallInfo)
        if (-not $uninstallProcess) { throw 'Impossible de lancer le test de desinstallation silencieuse.' }
        $outputTask = $uninstallProcess.StandardOutput.ReadToEndAsync()
        $errorTask = $uninstallProcess.StandardError.ReadToEndAsync()
        if (-not $uninstallProcess.WaitForExit(15000)) {
            try { $uninstallProcess.Kill() } catch { }
            throw 'La desinstallation silencieuse n a pas attendu sa copie temporaire.'
        }
        $output = $outputTask.GetAwaiter().GetResult().Trim()
        $errorOutput = $errorTask.GetAwaiter().GetResult().Trim()
        $expectedExitCode = if ($failCleanup) { 1 } else { 0 }
        if ($uninstallProcess.ExitCode -ne $expectedExitCode) {
            throw "Code de desinstallation silencieuse inattendu : $($uninstallProcess.ExitCode). Sortie='$output' Erreur='$errorOutput'"
        }
        $uninstallProcess.Dispose()
        $cleanupCommand = Get-Content -LiteralPath $fakeLog -Raw
        if ($cleanupCommand -notmatch 'uninstall-cleanup') {
            throw 'La desinstallation n a pas execute uninstall-cleanup.'
        }
        if ($removeSettings -and $cleanupCommand -notmatch 'uninstall-cleanup --purge') {
            throw 'La purge n a pas transmis --purge au Bridge.'
        }
        if (Test-Path -LiteralPath $testApp) {
            throw 'La desinstallation silencieuse a rendu la main avant de supprimer l application.'
        }
        if (Test-Path -LiteralPath $orphanTransaction) {
            throw 'La desinstallation silencieuse a conserve une ancienne transaction.'
        }
        $testConfig = Join-Path $testBridgeRoot 'config.json'
        if ($removeSettings -and -not $failCleanup -and (Test-Path -LiteralPath $testBridgeRoot)) {
            throw 'La purge silencieuse a conserve les donnees locales.'
        }
        if (-not $removeSettings -and -not (Test-Path -LiteralPath $testConfig)) {
            throw 'La desinstallation silencieuse a supprime la configuration sans demande explicite.'
        }
    } finally {
        if (Test-Path -LiteralPath $resolvedTestRoot) {
            Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Invoke-IsolatedSilentUninstall $false $false
Invoke-IsolatedSilentUninstall $true $false
Invoke-IsolatedSilentUninstall $false $true
Write-Host 'OK  Desinstallation silencieuse reelle, cleanup, conservation, purge et code d echec'

$nativeProcess = New-HiddenProcess 'chrome-extension://hkjbodgdbjhignhlbecchiigcfigpidp/' $runtimeTestRoot
if (-not $nativeProcess.Start()) { throw 'Impossible de lancer le canal natif.' }
$payload = [Text.Encoding]::UTF8.GetBytes('{"type":"ping","extensionVersion":"1.8.0"}')
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
    'Desinstaller-JellyfinVlcBridge.ps1',
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

$privateBuildRoots = @($projectDirectory, $env:USERPROFILE) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') } |
    Select-Object -Unique
foreach ($binaryPath in @($executable, $controlExecutable, $setup)) {
    $binaryBytes = [IO.File]::ReadAllBytes($binaryPath)
    $binaryAscii = [Text.Encoding]::UTF8.GetString($binaryBytes)
    $binaryUnicode = [Text.Encoding]::Unicode.GetString($binaryBytes)
    foreach ($privateRoot in $privateBuildRoots) {
        if ($binaryAscii.IndexOf($privateRoot, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $binaryUnicode.IndexOf($privateRoot, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw "Le binaire $([IO.Path]::GetFileName($binaryPath)) divulgue un chemin local de compilation."
        }
    }
}
Write-Host 'OK  Aucun chemin personnel de compilation dans les binaires'
if (Test-Path -LiteralPath $runtimeTestRoot) {
    Remove-Item -LiteralPath $runtimeTestRoot -Recurse -Force -ErrorAction Stop
}
Write-Host "Paquet Windows $Version valide."
