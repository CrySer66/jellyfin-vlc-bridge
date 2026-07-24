$script:JvbLanguageFile = Join-Path $env:LOCALAPPDATA 'JellyfinVlcBridge\ui-language.json'

$script:JvbMessages = @{
    en = @{
        ControlCenterTitle = 'Jellyfin VLC Bridge - Control Center'
        ControlCenterSubtitle = 'Control center and diagnostics'
        Language = 'Language'
        LanguageAuto = 'Automatic'
        LanguageFrench = 'Français'
        LanguageEnglish = 'English'
        LanguageRestart = 'Language saved. Reopen the Control Center to apply it everywhere.'
        Checking = 'Checking...'
        CheckInProgress = 'Check in progress...'
        CheckFailed = 'Diagnostics failed.'
        CheckNeeded = 'A check is required.'
        AllReady = 'Everything is ready to play with VLC.'
        LastCheck = 'Last check: {0}'
        Connected = 'Connected'
        Check = 'Check'
        NoPath = 'No path detected'
        VlcDetected = 'VLC detected'
        VlcMissing = 'VLC not found'
        BrowserConnectionMissing = 'Windows connection is missing. Use Repair.'
        RepairRequired = 'Repair required'
        ExtensionContact = 'Extension {0} is communicating with the Bridge.'
        ExtensionOpenHint = 'Open or reload Jellyfin to confirm that the extension is active.'
        ExtensionUnconfirmed = 'Extension not confirmed'
        ExtensionActive = 'Extension active'
        NotConfigured = 'Not configured'
        VlcPlayer = 'VLC player'
        BrowserExtension = 'Browser extension'
        PlaybackSettings = 'Playback settings'
        JellyfinServer = 'Jellyfin server'
        PlaybackMode = 'Playback mode'
        SmbMode = 'SMB (network share)'
        HttpModeDescription = 'Recommended: Jellyfin sends the original file to VLC without transcoding.'
        SmbModeDescription = 'Advanced: VLC opens a shared folder directly over the network.'
        ModeHelpTip = 'HTTP Direct Play is recommended. SMB is intended for users who already have a working Windows network share.'
        VlcPath = 'VLC path'
        VlcHelpTip = 'The Bridge normally detects VLC automatically. Change this path only if VLC is installed in an unusual folder.'
        Browse = 'Browse...'
        JellyfinPath = 'Path used by Jellyfin'
        ClientNetworkPath = 'Network address available on this PC'
        MappingExample = 'Example: D:\Movies   becomes   \\MEDIA-PC\Movies'
        MappingHelpTip = 'The first path is stored in Jellyfin on the server. The second is the network share used by this PC. This is not needed with HTTP Direct Play.'
        SaveSettings = 'Save settings'
        Refresh = 'Refresh'
        Repair = 'Repair'
        OpenExtension = 'Open extension'
        ViewLogs = 'View logs'
        CopyDiagnostic = 'Copy a diagnostic without secrets'
        HelpBug = 'Help and report a bug'
        PrivacyNote = 'The Jellyfin token stays protected in Windows and is never included in diagnostics.'
        MainProgramMissing = 'The main program could not be found.'
        ProgramStartFailed = 'The main program could not start.'
        UnknownError = 'Unknown error.'
        NoResult = 'The main program returned no result.'
        UpdatesWaiting = 'Updates: waiting'
        CheckNow = 'Check now'
        Downloading = 'Downloading...'
        UpdateChecking = 'Checking for updates...'
        CheckImpossible = 'Unable to check.'
        Retry = 'Try again'
        NewVersion = 'New version: {0}'
        InstallVersion = 'Install {0}'
        UpToDate = 'The application is up to date.'
        UpToDateButton = 'Up to date'
        InstallerOpening = 'Opening the installer...'
        UpdateFileUnsafe = 'The update file is missing or is not trusted.'
        AvailableAfterPublication = 'Available after the GitHub release is published.'
        HttpHelpTitle = 'Which mode should I choose?'
        HttpHelpBody = "HTTP Direct Play (recommended)`r`nJellyfin sends the original file without transcoding. No network folder is required.`r`n`r`nSMB (advanced)`r`nVLC opens a Windows share directly. Choose this only if the share already works in File Explorer."
        VlcHelpTitle = 'VLC path'
        VlcHelpBody = "The Bridge normally finds VLC automatically.`r`n`r`nUse Browse only if VLC is installed in an unusual folder or if VLC not found is displayed."
        MappingHelpTitle = 'SMB folder mapping'
        MappingHelpBody = "This setting translates the path known by Jellyfin into the share available on this PC.`r`n`r`nExample:`r`nPath used by Jellyfin: D:\Movies`r`nNetwork address on this PC: \\MEDIA-PC\Movies`r`n`r`nIt is not used with HTTP Direct Play."
        Repairing = 'Repair in progress...'
        RepairDone = 'Chrome and Edge integration repaired.'
        MissingConfig = 'The Jellyfin configuration is missing. Reinstall using Quick Connect.'
        SmbRequiresMapping = 'SMB mode requires the server folder and its matching network share.'
        SettingsSaved = 'Settings saved.'
        DiagnosticCopied = 'Diagnostic copied. No token or user identifier was included.'
        Version = 'Version {0}'
        SetupSubtitle = 'Secure installation and connection with Quick Connect'
        ServerAddress = 'Your Jellyfin server address'
        ChangeServer = 'Change Jellyfin server'
        QuickConnectCode = 'Quick Connect code'
        ExistingConnection = 'An existing connection was found. The address, Quick Connect and your settings will be preserved.'
        PerUserInstall = 'The application will be installed for your Windows account without administrator rights.'
        ReadyToInstall = 'Ready to install.'
        OpenChromeStore = 'Open Chrome Web Store'
        Install = 'Install'
        Close = 'Close'
        ChangeServerQuestion = "The current connection will be replaced and Jellyfin will request a new Quick Connect code.`r`n`r`nContinue?"
        NewServerAddress = 'New Jellyfin server address'
        NewServerInstructions = 'Enter the new address. A new Quick Connect code will be requested.'
        QuickConnectInstructions = 'In Jellyfin: Settings > Quick Connect. Enter this code, then confirm.'
        WaitingAuthorization = 'Waiting for Jellyfin authorization...'
        QuickConnectFailed = 'Quick Connect failed or expired. Restart the installation.'
        InstallationInterrupted = 'Installation interrupted.'
        InvalidJellyfinAddress = 'Invalid Jellyfin address.'
        CopyingFiles = 'Copying files...'
        ConnectionPreserved = 'Existing connection preserved.'
        RemovingOldConnection = 'Removing the old connection...'
        ReplaceConnectionFailed = 'Unable to replace the existing Jellyfin connection.'
        RequestingCode = 'Requesting a Quick Connect code...'
        InstallComplete = 'Installation complete.'
        InstallCompleteDetail = 'The Bridge is ready. Install or open the browser extension to use “Play with VLC”.'
        BrowserOpenFailed = 'Unable to open the browser. Address: {0}'
        MissingFile = 'Missing file: {0}'
        InstallSuccess = 'Installation completed successfully.'
        NewConnectionSaved = 'The new Jellyfin connection was saved. The installed extension remains available.'
        UpdateCompletePreserved = 'Update complete. Your Jellyfin connection and settings were preserved.'
        InstallExtensionNow = 'Now install the Chrome extension. The green button opens its store page again.'
        UninstallQuestion = "Do you also want to remove the saved Jellyfin connection?`r`n`r`nYes: remove everything and start over.`r`nNo: keep the connection for a future reinstall.`r`nCancel: make no changes."
        UninstallTitle = 'Uninstall Jellyfin VLC Bridge'
        CleanupStartFailed = 'Unable to start Bridge cleanup.'
        CleanupIncomplete = 'Windows association cleanup is incomplete: {0}'
        UnsafeUninstallPath = 'Unexpected uninstall path.'
        UninstallComplete = "Jellyfin VLC Bridge was uninstalled.`r`n`r`nYou can now remove the extension from Chrome or Edge."
        Warning = 'Warning: {0}'
        UninstallCompleteTitle = 'Uninstall complete'
        UninstallErrorTitle = 'Uninstall error'
        UninstallConsoleHeader = '=== Uninstall Jellyfin VLC Bridge ==='
        UninstallConsoleQuestion = 'Do you also want to remove the saved Jellyfin connection?'
        UninstallConsoleKeep = '  N = keep the connection for a future reinstall (recommended)'
        UninstallConsolePurge = '  Y = remove everything and start over'
        UninstallConsolePrompt = 'Remove everything? Y/N'
        ProgramRemoved = 'The application and Windows associations were removed.'
        SettingsRemoved = 'The configuration and token were also removed.'
        SettingsKept = 'The configuration was kept and will be reused automatically.'
        RemoveExtensionLast = 'Last step: manually remove Jellyfin VLC Bridge from Chrome or Edge.'
    }
    fr = @{
        ControlCenterTitle = 'Jellyfin VLC Bridge - Centre de contrôle'
        ControlCenterSubtitle = 'Centre de contrôle et diagnostic'
        Language = 'Langue'
        LanguageAuto = 'Automatique'
        LanguageFrench = 'Français'
        LanguageEnglish = 'English'
        LanguageRestart = "Langue enregistrée. Rouvrez le centre de contrôle pour l’appliquer partout."
        Checking = 'Vérification...'
        CheckInProgress = 'Vérification en cours...'
        CheckFailed = 'Le diagnostic a échoué.'
        CheckNeeded = 'Une vérification est nécessaire.'
        AllReady = 'Tout est prêt pour lire avec VLC.'
        LastCheck = 'Dernière vérification : {0}'
        Connected = 'Connecté'
        Check = 'À vérifier'
        NoPath = 'Aucun chemin détecté'
        VlcDetected = 'VLC détecté'
        VlcMissing = 'VLC introuvable'
        BrowserConnectionMissing = 'Connexion Windows absente. Utilisez Réparer.'
        RepairRequired = 'Réparation requise'
        ExtensionContact = 'Extension {0} en contact avec le Bridge.'
        ExtensionOpenHint = "Ouvrez ou rechargez Jellyfin pour confirmer que l’extension est active."
        ExtensionUnconfirmed = 'Extension non confirmée'
        ExtensionActive = 'Extension active'
        NotConfigured = 'Non configuré'
        VlcPlayer = 'Lecteur VLC'
        BrowserExtension = 'Extension navigateur'
        PlaybackSettings = 'Réglages de lecture'
        JellyfinServer = 'Serveur Jellyfin'
        PlaybackMode = 'Mode de lecture'
        SmbMode = 'SMB (partage réseau)'
        HttpModeDescription = 'Mode recommandé : Jellyfin envoie le fichier original à VLC, sans transcodage.'
        SmbModeDescription = 'Mode avancé : VLC ouvre directement un dossier partagé sur le réseau.'
        ModeHelpTip = "HTTP Direct Play est recommandé. SMB est réservé aux utilisateurs qui disposent déjà d’un partage réseau Windows fonctionnel."
        VlcPath = 'Chemin de VLC'
        VlcHelpTip = 'Le Bridge détecte normalement VLC tout seul. Modifiez ce chemin uniquement si VLC est installé dans un dossier inhabituel.'
        Browse = 'Parcourir...'
        JellyfinPath = 'Chemin vu par Jellyfin'
        ClientNetworkPath = 'Adresse réseau utilisable sur ce PC'
        MappingExample = 'Exemple : D:\Films   devient   \\PC-SERVEUR\Films'
        MappingHelpTip = 'Le premier chemin est enregistré dans Jellyfin sur le serveur. Le second est le partage réseau utilisé par ce PC. Cette option ne sert pas en HTTP Direct Play.'
        SaveSettings = 'Enregistrer les réglages'
        Refresh = 'Actualiser'
        Repair = 'Réparer'
        OpenExtension = 'Ouvrir extension'
        ViewLogs = 'Voir les journaux'
        CopyDiagnostic = 'Copier un diagnostic sans secret'
        HelpBug = 'Aide et signaler un bug'
        PrivacyNote = 'Le jeton Jellyfin reste protégé dans Windows et ne figure jamais dans le diagnostic.'
        MainProgramMissing = 'Le programme principal est introuvable.'
        ProgramStartFailed = "Le programme principal n’a pas pu démarrer."
        UnknownError = 'Erreur inconnue.'
        NoResult = "Le programme principal n’a renvoyé aucun résultat."
        UpdatesWaiting = 'Mises à jour : en attente'
        CheckNow = 'Vérifier maintenant'
        Downloading = 'Téléchargement en cours...'
        UpdateChecking = 'Vérification des mises à jour...'
        CheckImpossible = 'Vérification impossible.'
        Retry = 'Réessayer'
        NewVersion = 'Nouvelle version : {0}'
        InstallVersion = 'Installer {0}'
        UpToDate = 'Le logiciel est à jour.'
        UpToDateButton = 'À jour'
        InstallerOpening = "Ouverture de l’installateur..."
        UpdateFileUnsafe = 'Le fichier de mise à jour est introuvable ou non sûr.'
        AvailableAfterPublication = 'Disponible après publication GitHub.'
        HttpHelpTitle = 'Quel mode choisir ?'
        HttpHelpBody = "HTTP Direct Play (recommandé)`r`nLe fichier original passe par Jellyfin sans transcodage. Aucun dossier réseau n’est à régler.`r`n`r`nSMB (avancé)`r`nVLC ouvre directement un partage Windows. Choisissez ce mode uniquement si ce partage fonctionne déjà dans l’Explorateur de fichiers."
        VlcHelpTitle = 'Chemin de VLC'
        VlcHelpBody = "Le Bridge trouve normalement VLC automatiquement.`r`n`r`nUtilisez Parcourir uniquement si VLC est installé dans un dossier inhabituel ou si le message VLC introuvable apparaît."
        MappingHelpTitle = 'Correspondance des dossiers SMB'
        MappingHelpBody = "Ce réglage traduit le chemin connu par Jellyfin vers le partage accessible depuis ce PC.`r`n`r`nExemple :`r`nChemin vu par Jellyfin : D:\Films`r`nAdresse réseau sur ce PC : \\PC-SERVEUR\Films`r`n`r`nIl est inutile en HTTP Direct Play."
        Repairing = 'Réparation en cours...'
        RepairDone = 'Intégration Chrome et Edge réparée.'
        MissingConfig = 'La configuration Jellyfin est absente. Réinstallez avec Quick Connect.'
        SmbRequiresMapping = 'Le mode SMB exige le dossier serveur et le partage réseau correspondant.'
        SettingsSaved = 'Réglages enregistrés.'
        DiagnosticCopied = 'Diagnostic copié. Aucun jeton ni identifiant utilisateur inclus.'
        Version = 'Version {0}'
        SetupSubtitle = 'Installation et connexion sécurisée avec Quick Connect'
        ServerAddress = 'Adresse de votre serveur Jellyfin'
        ChangeServer = 'Changer de serveur Jellyfin'
        QuickConnectCode = 'Code Quick Connect'
        ExistingConnection = 'Connexion existante détectée. Cette adresse, Quick Connect et vos réglages seront conservés.'
        PerUserInstall = 'Le programme sera installé pour votre compte Windows, sans droits administrateur.'
        ReadyToInstall = 'Prêt à installer.'
        OpenChromeStore = 'Ouvrir Chrome Web Store'
        Install = 'Installer'
        Close = 'Fermer'
        ChangeServerQuestion = "La connexion actuelle sera remplacée et Jellyfin demandera un nouveau code Quick Connect.`r`n`r`nContinuer ?"
        NewServerAddress = 'Adresse du nouveau serveur Jellyfin'
        NewServerInstructions = 'Saisissez la nouvelle adresse. Un nouveau code Quick Connect sera demandé.'
        QuickConnectInstructions = 'Dans Jellyfin : Paramètres > Quick Connect. Saisissez ce code puis confirmez.'
        WaitingAuthorization = "Attente de l’autorisation Jellyfin..."
        QuickConnectFailed = "Quick Connect a échoué ou a expiré. Relancez l’installation."
        InstallationInterrupted = 'Installation interrompue.'
        InvalidJellyfinAddress = 'Adresse Jellyfin invalide.'
        CopyingFiles = 'Copie des fichiers...'
        ConnectionPreserved = 'Connexion existante conservée.'
        RemovingOldConnection = "Suppression de l’ancienne connexion..."
        ReplaceConnectionFailed = 'Impossible de remplacer la connexion Jellyfin existante.'
        RequestingCode = 'Demande du code Quick Connect...'
        InstallComplete = 'Installation terminée.'
        InstallCompleteDetail = "Le Bridge est prêt. Installez ou ouvrez l’extension pour utiliser « Lire avec VLC »."
        BrowserOpenFailed = "Impossible d’ouvrir le navigateur. Adresse : {0}"
        MissingFile = 'Fichier manquant : {0}'
        InstallSuccess = 'Installation terminée avec succès.'
        NewConnectionSaved = "Nouvelle connexion Jellyfin enregistrée. L’extension déjà installée reste utilisable."
        UpdateCompletePreserved = 'Mise à jour terminée. Votre connexion Jellyfin et vos réglages ont été conservés.'
        InstallExtensionNow = "Installez maintenant l’extension Chrome. Le bouton vert permet de rouvrir sa fiche."
        UninstallQuestion = "Voulez-vous aussi effacer la connexion Jellyfin enregistrée ?`r`n`r`nOui : tout effacer et repartir à zéro.`r`nNon : conserver la connexion pour une réinstallation.`r`nAnnuler : ne rien modifier."
        UninstallTitle = 'Désinstaller Jellyfin VLC Bridge'
        CleanupStartFailed = 'Impossible de démarrer le nettoyage du Bridge.'
        CleanupIncomplete = 'Le nettoyage des associations Windows est incomplet : {0}'
        UnsafeUninstallPath = 'Chemin de désinstallation inattendu.'
        UninstallComplete = "Jellyfin VLC Bridge a été désinstallé.`r`n`r`nVous pouvez maintenant retirer l’extension de Chrome ou Edge."
        Warning = 'Attention : {0}'
        UninstallCompleteTitle = 'Désinstallation terminée'
        UninstallErrorTitle = 'Erreur de désinstallation'
        UninstallConsoleHeader = '=== Désinstallation de Jellyfin VLC Bridge ==='
        UninstallConsoleQuestion = 'Voulez-vous aussi effacer la connexion Jellyfin enregistrée ?'
        UninstallConsoleKeep = '  N = conserver la connexion pour une future réinstallation (recommandé)'
        UninstallConsolePurge = '  O = tout effacer et repartir complètement à zéro'
        UninstallConsolePrompt = 'Tout effacer ? O/N'
        ProgramRemoved = 'Le programme et les associations Windows ont été retirés.'
        SettingsRemoved = 'La configuration et le jeton ont aussi été effacés.'
        SettingsKept = 'La configuration est conservée et sera réutilisée automatiquement.'
        RemoveExtensionLast = 'Dernière action : retirez manuellement Jellyfin VLC Bridge de Chrome ou Edge.'
    }
}

function Get-JvbLanguagePreference {
    if (-not (Test-Path -LiteralPath $script:JvbLanguageFile)) { return 'auto' }
    try {
        $saved = Get-Content -LiteralPath $script:JvbLanguageFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$saved.language -in @('auto', 'en', 'fr')) { return [string]$saved.language }
    } catch { }
    return 'auto'
}

function Get-JvbEffectiveLanguage {
    param([string]$Preference = (Get-JvbLanguagePreference))
    if ($Preference -in @('en', 'fr')) { return $Preference }
    if ([Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'fr') { return 'fr' }
    return 'en'
}

function Set-JvbLanguagePreference([ValidateSet('auto', 'en', 'fr')][string]$Language) {
    $directory = Split-Path -Parent $script:JvbLanguageFile
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $json = @{ language = $Language } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText($script:JvbLanguageFile, $json, (New-Object Text.UTF8Encoding($false)))
}

$script:JvbLanguagePreference = Get-JvbLanguagePreference
$script:JvbLanguage = Get-JvbEffectiveLanguage $script:JvbLanguagePreference

function T([string]$Key, [object[]]$Arguments) {
    $message = $script:JvbMessages[$script:JvbLanguage][$Key]
    if ([string]::IsNullOrEmpty($message)) { $message = $script:JvbMessages.en[$Key] }
    if ([string]::IsNullOrEmpty($message)) { return $Key }
    if ($null -ne $Arguments -and $Arguments.Count -gt 0) { return $message -f $Arguments }
    return $message
}
