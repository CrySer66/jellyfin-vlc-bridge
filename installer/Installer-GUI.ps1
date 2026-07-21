$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:bridgeVersion = '1.8.1'
$script:chromeWebStoreId = 'hkjbodgdbjhignhlbecchiigcfigpidp'
$script:chromeWebStoreUrl = 'https://chromewebstore.google.com/detail/' + $script:chromeWebStoreId
$script:packageDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:rootDirectory = Join-Path $env:LOCALAPPDATA 'JellyfinVlcBridge'
$script:installDirectory = Join-Path $script:rootDirectory 'App'
$script:executable = Join-Path $script:installDirectory 'jellyfin-vlc-bridge.exe'
$script:configFile = Join-Path $script:rootDirectory 'config.json'
$script:hadExistingConfig = Test-Path $script:configFile
$script:existingServerUrl = $null
$script:replaceExistingConfig = $false
if ($script:hadExistingConfig) {
    try {
        $existingConfig = Get-Content -LiteralPath $script:configFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not [string]::IsNullOrWhiteSpace([string]$existingConfig.serverUrl)) {
            $script:existingServerUrl = [string]$existingConfig.serverUrl
        }
    } catch { }
}
$script:codeFile = Join-Path $env:TEMP ('jellyfin-vlc-code-' + [Guid]::NewGuid().ToString('N') + '.txt')
$script:setupProcess = $null
$script:installed = $false

function Show-SetupError([string]$message) {
    [System.Windows.Forms.MessageBox]::Show($message, 'Jellyfin VLC Bridge', 'OK', 'Error') | Out-Null
}

function Open-ChromeWebStore {
    try { Start-Process $script:chromeWebStoreUrl }
    catch { Show-SetupError "Impossible d'ouvrir le navigateur. Adresse : $script:chromeWebStoreUrl" }
}

function Copy-ApplicationFiles {
    $requiredFiles = @(
        'jellyfin-vlc-bridge.exe',
        'jellyfin-vlc-bridge-control.exe',
        'Centre-Controle.ps1',
        'DESINSTALLER-WINDOWS.cmd',
        'Desinstaller-JellyfinVlcBridge.ps1',
        'Desinstaller-GUI.ps1'
    )
    foreach ($file in $requiredFiles) {
        if (-not (Test-Path (Join-Path $script:packageDirectory $file))) { throw "Fichier manquant : $file" }
    }
    New-Item -ItemType Directory -Path $script:installDirectory -Force | Out-Null
    foreach ($file in $requiredFiles) {
        Copy-Item (Join-Path $script:packageDirectory $file) (Join-Path $script:installDirectory $file) -Force
    }
    foreach ($obsoleteFile in @(
        'jellyfin-vlc-bridge.dll',
        'jellyfin-vlc-bridge.deps.json',
        'jellyfin-vlc-bridge.runtimeconfig.json',
        'JellyfinVlcBridge.Core.dll'
    )) {
        $obsoletePath = Join-Path $script:installDirectory $obsoleteFile
        if (Test-Path -LiteralPath $obsoletePath) {
            try { Remove-Item -LiteralPath $obsoletePath -Force -ErrorAction Stop } catch { }
        }
    }
}

function Register-WindowsApplication {
    $shell = New-Object -ComObject WScript.Shell
    $oldDesktopShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Jellyfin VLC Bridge - Diagnostic.lnk'
    if (Test-Path $oldDesktopShortcut) { Remove-Item -LiteralPath $oldDesktopShortcut -Force }

    $startMenuDirectory = Join-Path ([Environment]::GetFolderPath('Programs')) 'Jellyfin VLC Bridge'
    New-Item -ItemType Directory -Path $startMenuDirectory -Force | Out-Null
    $oldDiagnostic = Join-Path $startMenuDirectory 'Diagnostic Jellyfin VLC Bridge.lnk'
    if (Test-Path $oldDiagnostic) { Remove-Item -LiteralPath $oldDiagnostic -Force }
    $controlCenter = Join-Path $script:installDirectory 'jellyfin-vlc-bridge-control.exe'
    $application = $shell.CreateShortcut((Join-Path $startMenuDirectory 'Jellyfin VLC Bridge.lnk'))
    $application.TargetPath = $controlCenter
    $application.Arguments = ''
    $application.WorkingDirectory = $script:installDirectory
    $application.IconLocation = $script:executable
    $application.Save()

    $uninstaller = Join-Path $script:installDirectory 'Desinstaller-GUI.ps1'
    $uninstallShortcut = $shell.CreateShortcut((Join-Path $startMenuDirectory 'Desinstaller Jellyfin VLC Bridge.lnk'))
    $uninstallShortcut.TargetPath = 'powershell.exe'
    $uninstallShortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$uninstaller`""
    $uninstallShortcut.WorkingDirectory = $script:installDirectory
    $uninstallShortcut.IconLocation = $script:executable
    $uninstallShortcut.Save()

    $registry = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\JellyfinVlcBridge'
    New-Item -Path $registry -Force | Out-Null
    Set-ItemProperty -Path $registry -Name DisplayName -Value 'Jellyfin VLC Bridge'
    Set-ItemProperty -Path $registry -Name DisplayVersion -Value $script:bridgeVersion
    Set-ItemProperty -Path $registry -Name Publisher -Value 'Jellyfin VLC Bridge Project'
    Set-ItemProperty -Path $registry -Name InstallLocation -Value $script:installDirectory
    Set-ItemProperty -Path $registry -Name DisplayIcon -Value $script:executable
    Set-ItemProperty -Path $registry -Name UninstallString -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$uninstaller`""
    New-ItemProperty -Path $registry -Name NoModify -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $registry -Name NoRepair -Value 1 -PropertyType DWord -Force | Out-Null
}

function Complete-Installation {
    Register-WindowsApplication
    $script:installed = $true
    $timer.Stop()
    $progress.Style = 'Continuous'
    $progress.Value = 100
    $statusLabel.Text = 'Installation terminee avec succes.'
    $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(34, 139, 34)
    $codeTitle.Visible = $false
    $codeLabel.Visible = $false
    if ($script:replaceExistingConfig) {
        $instructions.Text = 'Nouvelle connexion Jellyfin enregistree. L extension deja installee reste utilisable.'
        $extensionButton.Visible = $false
    } elseif ($script:hadExistingConfig) {
        $instructions.Text = 'Mise a jour terminee. Votre connexion Jellyfin et vos reglages ont ete conserves.'
        $extensionButton.Visible = $false
    } else {
        $instructions.Text = "Installez maintenant l'extension Chrome. Le bouton vert permet de rouvrir sa fiche."
        $extensionButton.Visible = $true
    }
    $serverBox.Enabled = $false
    $installButton.Text = 'Fermer'
    $installButton.Enabled = $true
    if (-not $script:hadExistingConfig) { Open-ChromeWebStore }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Jellyfin VLC Bridge 1.8.1'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(620, 445)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 250)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
try { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon((Join-Path $script:packageDirectory 'jellyfin-vlc-bridge.exe')) } catch { }

$header = New-Object System.Windows.Forms.Panel
$header.Location = New-Object System.Drawing.Point(0, 0)
$header.Size = New-Object System.Drawing.Size(620, 96)
$header.BackColor = [System.Drawing.Color]::FromArgb(8, 91, 126)
$form.Controls.Add($header)

$logo = New-Object System.Windows.Forms.PictureBox
$logo.Location = New-Object System.Drawing.Point(28, 18)
$logo.Size = New-Object System.Drawing.Size(60, 60)
$logo.SizeMode = 'StretchImage'
try { $logo.Image = $form.Icon.ToBitmap() } catch { }
$header.Controls.Add($logo)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Jellyfin VLC Bridge'
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 20)
$title.ForeColor = [System.Drawing.Color]::White
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(104, 17)
$header.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'Installation et connexion securisee avec Quick Connect'
$subtitle.AutoSize = $true
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(214, 238, 247)
$subtitle.Location = New-Object System.Drawing.Point(107, 58)
$header.Controls.Add($subtitle)

$serverLabel = New-Object System.Windows.Forms.Label
$serverLabel.Text = 'Adresse de votre serveur Jellyfin'
$serverLabel.AutoSize = $true
$serverLabel.Location = New-Object System.Drawing.Point(31, 116)
$form.Controls.Add($serverLabel)

$serverBox = New-Object System.Windows.Forms.TextBox
$serverBox.Location = New-Object System.Drawing.Point(34, 141)
$serverBox.Size = New-Object System.Drawing.Size(552, 30)
$serverBox.Text = if ($script:existingServerUrl) { $script:existingServerUrl } else { 'http://192.168.1.25:8096' }
$serverBox.ReadOnly = $script:hadExistingConfig
$form.Controls.Add($serverBox)

$changeServerButton = New-Object System.Windows.Forms.Button
$changeServerButton.Text = 'Changer de serveur Jellyfin'
$changeServerButton.Location = New-Object System.Drawing.Point(378, 180)
$changeServerButton.Size = New-Object System.Drawing.Size(208, 34)
$changeServerButton.FlatStyle = 'Flat'
$changeServerButton.Visible = $script:hadExistingConfig
$form.Controls.Add($changeServerButton)

$codeTitle = New-Object System.Windows.Forms.Label
$codeTitle.Text = 'Code Quick Connect'
$codeTitle.AutoSize = $true
$codeTitle.Location = New-Object System.Drawing.Point(31, 187)
$codeTitle.Visible = $false
$form.Controls.Add($codeTitle)

$codeLabel = New-Object System.Windows.Forms.Label
$codeLabel.Text = '------'
$codeLabel.Font = New-Object System.Drawing.Font('Consolas', 23, [System.Drawing.FontStyle]::Bold)
$codeLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 122, 204)
$codeLabel.AutoSize = $true
$codeLabel.Location = New-Object System.Drawing.Point(29, 211)
$codeLabel.Visible = $false
$form.Controls.Add($codeLabel)

$instructions = New-Object System.Windows.Forms.Label
$instructions.Text = if ($script:hadExistingConfig) {
    'Connexion existante detectee. Cette adresse, Quick Connect et vos reglages seront conserves.'
} else {
    'Le programme sera installe pour votre compte Windows, sans droits administrateur.'
}
$instructions.Location = New-Object System.Drawing.Point(31, 270)
$instructions.Size = New-Object System.Drawing.Size(555, 48)
$instructions.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($instructions)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = 'Pret a installer.'
$statusLabel.AutoSize = $true
$statusLabel.Location = New-Object System.Drawing.Point(31, 326)
$form.Controls.Add($statusLabel)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(34, 351)
$progress.Size = New-Object System.Drawing.Size(552, 22)
$form.Controls.Add($progress)

$extensionButton = New-Object System.Windows.Forms.Button
$extensionButton.Text = 'Ouvrir Chrome Web Store'
$extensionButton.Location = New-Object System.Drawing.Point(286, 390)
$extensionButton.Size = New-Object System.Drawing.Size(198, 38)
$extensionButton.BackColor = [System.Drawing.Color]::FromArgb(34, 139, 94)
$extensionButton.ForeColor = [System.Drawing.Color]::White
$extensionButton.FlatStyle = 'Flat'
$extensionButton.Visible = $false
$form.Controls.Add($extensionButton)

$installButton = New-Object System.Windows.Forms.Button
$installButton.Text = 'Installer'
$installButton.Location = New-Object System.Drawing.Point(496, 390)
$installButton.Size = New-Object System.Drawing.Size(90, 38)
$installButton.BackColor = [System.Drawing.Color]::FromArgb(8, 91, 126)
$installButton.ForeColor = [System.Drawing.Color]::White
$installButton.FlatStyle = 'Flat'
$form.Controls.Add($installButton)

$extensionButton.Add_Click({ Open-ChromeWebStore })

$changeServerButton.Add_Click({
    $choice = [System.Windows.Forms.MessageBox]::Show(
        "La connexion actuelle sera remplacee et Jellyfin demandera un nouveau code Quick Connect.`r`n`r`nContinuer ?",
        'Changer de serveur Jellyfin',
        'YesNo',
        'Question'
    )
    if ($choice -ne 'Yes') { return }
    $script:replaceExistingConfig = $true
    $serverLabel.Text = 'Adresse du nouveau serveur Jellyfin'
    $serverBox.ReadOnly = $false
    $serverBox.SelectAll()
    $serverBox.Focus()
    $changeServerButton.Visible = $false
    $instructions.Text = 'Saisissez la nouvelle adresse. Un nouveau code Quick Connect sera demande.'
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 500
$timer.Add_Tick({
    try {
        if (-not $codeLabel.Visible -and (Test-Path $script:codeFile)) {
            $codeLabel.Text = (Get-Content -LiteralPath $script:codeFile -Raw).Trim()
            $codeTitle.Visible = $true
            $codeLabel.Visible = $true
            $instructions.Text = 'Dans Jellyfin : Parametres > Quick Connect. Saisissez ce code puis confirmez.'
            $statusLabel.Text = "Attente de l'autorisation Jellyfin..."
        }
        if ($script:setupProcess -and $script:setupProcess.HasExited) {
            if ($script:setupProcess.ExitCode -ne 0) { throw 'Quick Connect a echoue ou a expire. Relancez installation.' }
            Complete-Installation
        }
    } catch {
        $timer.Stop()
        $installButton.Enabled = $true
        $statusLabel.Text = 'Installation interrompue.'
        Show-SetupError $_.Exception.Message
    }
})

$installButton.Add_Click({
    if ($script:installed) { $form.Close(); return }
    try {
        $uri = $null
        if (-not [Uri]::TryCreate($serverBox.Text.Trim(), [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @('http', 'https')) {
            throw 'Adresse Jellyfin invalide.'
        }
        $installButton.Enabled = $false
        $serverBox.Enabled = $false
        $progress.Style = 'Marquee'
        $statusLabel.Text = 'Copie des fichiers...'
        [System.Windows.Forms.Application]::DoEvents()
        Copy-ApplicationFiles

        if ((Test-Path $script:configFile) -and -not $script:replaceExistingConfig) {
            $statusLabel.Text = 'Connexion existante conservee.'
            Start-Process -FilePath $script:executable -ArgumentList 'install-protocol' -WindowStyle Hidden -Wait
            Start-Process -FilePath $script:executable -ArgumentList 'install-native-host' -WindowStyle Hidden -Wait
            Complete-Installation
            return
        }

        if ($script:replaceExistingConfig -and (Test-Path $script:configFile)) {
            $statusLabel.Text = 'Suppression de l ancienne connexion...'
            $cleanupProcess = Start-Process -FilePath $script:executable `
                -ArgumentList 'uninstall-cleanup --purge' -WindowStyle Hidden -Wait -PassThru
            if ($cleanupProcess.ExitCode -ne 0) { throw 'Impossible de remplacer la connexion Jellyfin existante.' }
        }

        $statusLabel.Text = 'Demande du code Quick Connect...'
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $script:executable
        $processInfo.Arguments = 'setup --server "' + $serverBox.Text.Trim() + '" --code-path "' + $script:codeFile + '"'
        $processInfo.WorkingDirectory = $script:installDirectory
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        $script:setupProcess = [System.Diagnostics.Process]::Start($processInfo)
        $timer.Start()
    } catch {
        $progress.Style = 'Continuous'
        $installButton.Enabled = $true
        $serverBox.Enabled = $true
        $statusLabel.Text = 'Installation interrompue.'
        Show-SetupError $_.Exception.Message
    }
})

$form.Add_FormClosing({
    $timer.Stop()
    if ($script:setupProcess -and -not $script:setupProcess.HasExited) {
        try { $script:setupProcess.Kill() } catch { }
    }
    if (Test-Path $script:codeFile) { Remove-Item -LiteralPath $script:codeFile -Force -ErrorAction SilentlyContinue }
})

[void]$form.ShowDialog()
