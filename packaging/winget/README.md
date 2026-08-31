# Maintenance de la distribution WinGet

L'identifiant **CrySer66.JellyfinVlcBridge** a été accepté dans le dépôt
communautaire WinGet pour la version **1.18.0** le **31 août 2026** :
[demande nº 413912](https://github.com/microsoft/winget-pkgs/pull/413912).

Ce dossier prépare les prochaines versions. Il ne publie et ne soumet rien
automatiquement. Pour installer le logiciel, utilisez le
[guide utilisateur](../../INSTALLATION.md#installer-avec-winget-facultatif)
ou son [équivalent anglais](../../INSTALLATION.en.md#install-with-winget-optional).

## État vérifié le 31 août 2026

- Demande fusionnée, validation des manifestes, analyse des installateurs et
  test d'installation réussis chez Microsoft.
- Cycle Setup, réinstallation et désinstallation réussi dans notre
  [CI Windows sur une machine éphémère](https://github.com/CrySer66/jellyfin-vlc-bridge/actions/runs/31224628649).
- Catalogue WinGet actualisé : le paquet n'est pas encore trouvé. Un test réel
  avec `winget install --id` depuis ce catalogue reste donc à effectuer.
- Le Setup téléchargé depuis la Release 1.18.0 correspond à l'empreinte du
  manifeste Microsoft et au fichier public `SHA256SUMS.txt`.

`winget validate` valide la structure avec un avertissement sur les commutateurs
silencieux des installateurs EXE. Le manifeste fournit `Silent: /quiet`, mais
pas `SilentWithProgress`, car le Setup ne possède pas ce mode avec progression.
Le validateur peut retourner un code non nul pour cet avertissement : il faut
lire son message, et ne pas déclarer un mode non pris en charge pour le masquer.
Le mode `/quiet` a été testé par notre CI et par Microsoft.

Une validation du manifeste ou du Setup ne doit pas être présentée comme une
preuve de disponibilité dans le catalogue. La présence dans WinGet n'est pas
une signature Authenticode et ne garantit pas l'absence d'avertissement Windows.

## Vérifier la disponibilité sans installer

```powershell
winget source update --name winget
winget show --id CrySer66.JellyfinVlcBridge --exact --source winget
```

Si le paquet n'est pas trouvé après actualisation, conserver GitHub Releases
comme solution de téléchargement. Ne pas ouvrir une deuxième demande pour la
même version, recréer le tag ou remplacer l'installateur déjà accepté.

## Recette finale sur un PC de test

Utiliser une machine virtuelle, Windows Sandbox si disponible, ou un PC de test
sans installation personnelle à préserver. Ne pas exécuter
`tools/Test-WindowsLifecycle.ps1` dans la session Windows habituelle : ce test
installe et désinstalle réellement le programme.

1. Confirmer que la fiche apparaît avec `winget show`.
2. Installer avec `winget install --id CrySer66.JellyfinVlcBridge --exact --source winget --silent`.
3. Vérifier le code de sortie, la présence du Bridge dans les applications Windows,
   la version installée et la disponibilité de VLC, déclaré comme dépendance.
4. Ouvrir le centre de contrôle depuis le menu Démarrer ; connecter volontairement
   un serveur de test avec Quick Connect et ajouter l'extension Chrome officielle.
5. Tester un film, une reprise et l'enchaînement de deux épisodes.
6. Lors d'une prochaine version disponible dans WinGet, tester `winget upgrade`
   avec le même identifiant et vérifier la conservation de la connexion et des réglages.
   Une réinstallation de la même version ne prouve pas une mise à niveau interversions.
7. Désinstaller depuis les paramètres Windows, puis vérifier que le programme
   et ses intégrations ont été retirés. L'extension Chrome et VLC sont séparés.

Après vérification réelle, actualiser les mentions d'attente dans les README,
les guides d'installation et `docs/DISTRIBUTION.md`, avec la date et la version
testées. Aucun nouveau numéro de version du logiciel n'est requis pour ces textes.

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
     -InstallerSha256 EMPREINTE_SHA256_PUBLIEE `
     -ReleaseDate AAAA-MM-JJ
   ```

   La date doit être celle de la Release GitHub, pas la date de génération des
   manifestes.

3. valider les fichiers produits dans `outputs\winget` avec `winget validate` ;
4. tester les manifestes dans Windows Sandbox avec le script `SandboxTest.ps1`
   du dépôt `microsoft/winget-pkgs` ;
5. vérifier l’installation avec `/quiet`, la première connexion Quick Connect,
   la mise à niveau et la désinstallation silencieuse ;
6. seulement ensuite, ouvrir manuellement une Pull Request vers
   `microsoft/winget-pkgs`.

Le commutateur WinGet retenu est `/quiet`. Il installe les fichiers et
intégrations sans fenêtre, sans ouvrir Chrome ni démarrer Quick Connect. La
connexion Jellyfin reste une action volontaire lors de la première ouverture du
centre de contrôle. La désinstallation silencieuse est fournie par la valeur
Windows `QuietUninstallString` enregistrée par l’installateur.

Le manifeste déclare `VideoLAN.VLC` comme dépendance. Il propose un mode
interactif et un mode silencieux réel ; il n’annonce pas de progression visuelle
pendant `/quiet`.

Conserver l'identifiant `CrySer66.JellyfinVlcBridge` pour toutes les versions.
Une seule soumission de version doit être ouverte à la fois. Publier une Release
GitHub ne déclenche pas automatiquement une mise à jour WinGet. Le manifeste
doit toujours viser le Setup immuable de la version et son empreinte exacte,
jamais l'adresse mobile `releases/latest`.

Documentation officielle :

- <https://learn.microsoft.com/windows/package-manager/package/manifest>
- <https://github.com/microsoft/winget-pkgs>
