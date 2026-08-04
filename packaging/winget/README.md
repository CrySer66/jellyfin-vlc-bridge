# Préparation WinGet

Ce dossier prépare une future publication de Jellyfin VLC Bridge dans le dépôt
communautaire WinGet. Il ne publie et ne soumet rien automatiquement.

## Pourquoi les fichiers sont des modèles

Une soumission WinGet doit référencer un installateur déjà public et son
empreinte SHA-256 exacte. Les modèles conservent donc des marqueurs explicites
tant que la Release correspondante n’existe pas.

Après publication et validation d’une Release GitHub :

1. récupérer l’empreinte du Setup dans le `SHA256SUMS.txt` public ;
2. générer les manifestes localement :

   ```powershell
   .\tools\New-WinGetManifests.ps1 `
     -Version 1.18.0 `
     -InstallerSha256 EMPREINTE_SHA256_PUBLIEE
   ```

3. tester les fichiers produits dans `outputs\winget` avec WinGetCreate et une
   installation propre ;
4. vérifier l’installation avec `/quiet`, la première connexion Quick Connect,
   la mise à niveau et la désinstallation silencieuse ;
5. seulement ensuite, ouvrir manuellement une Pull Request vers
   `microsoft/winget-pkgs`.

Le commutateur WinGet retenu est `/quiet`. Il installe les fichiers et
intégrations sans fenêtre, sans ouvrir Chrome ni démarrer Quick Connect. La
connexion Jellyfin reste une action volontaire lors de la première ouverture du
centre de contrôle. La désinstallation silencieuse est fournie par la valeur
Windows `QuietUninstallString` enregistrée par l’installateur.

Le manifeste déclare `VideoLAN.VLC` comme dépendance. Il propose un mode
interactif et un mode silencieux réel ; il n’annonce pas de progression visuelle
pendant `/quiet`.

L’identifiant `CrySer66.JellyfinVlcBridge` reste un candidat jusqu’à sa première
acceptation dans le dépôt communautaire. Une seule soumission de version doit
être ouverte à la fois.

Documentation officielle :

- <https://learn.microsoft.com/windows/package-manager/package/manifest>
- <https://github.com/microsoft/winget-pkgs>
