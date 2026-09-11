# Développement et publication

Ce document concerne les personnes qui souhaitent examiner, compiler ou contribuer au projet.

## Environnement

- Windows 10/11 x64 pour construire l'installateur ;
- SDK .NET 8 ou plus récent ;
- .NET Framework 4.8 pour le centre de contrôle WPF sur Windows 10/11 ;
- PowerShell 5.1 ou plus récent ;
- VLC pour les tests de lecture réels.

## Compiler et tester

Depuis la racine du dépôt :

```powershell
dotnet restore JellyfinVlcBridge.slnx --configfile NuGet.Config
dotnet build JellyfinVlcBridge.slnx --configuration Release --no-restore
dotnet run --project tests\JellyfinVlcBridge.Tests --configuration Debug --no-restore
```

Les tests sont hors ligne et ne nécessitent aucun jeton Jellyfin.

À chaque envoi sur `main` et pour chaque Pull Request, GitHub Actions vérifie automatiquement les versions, la syntaxe PowerShell et JavaScript, la compilation et les tests Windows.

## Centre de contrôle natif WPF

La version 1.19.1 intègre le centre de contrôle préparé en 1.19.0 et remplace l’interface
PowerShell/WinForms par `jellyfin-vlc-bridge-control.exe`, une application WPF
ciblant .NET Framework 4.8. Ce composant Windows est disponible sur Windows
10/11 ; il doit être installé si la machine en est dépourvue. Le centre de
contrôle démarre directement, sans interpréteur PowerShell pour afficher son
interface. Les assistants d’installation et de désinstallation conservent leurs
scripts PowerShell et partagent le thème WPF `installer/DesktopTheme.xaml` avec
le centre de contrôle.

La compilation utilise le compilateur C# de .NET Framework et embarque le XAML,
les traductions et l’icône. `Localization.ps1` et
`installer/ControlCenter.strings.json` sont fusionnés à la compilation : ils ne
sont pas chargés depuis le disque pour afficher le centre installé.

```powershell
.\tools\Build-ControlCenter.ps1 -OutputDirectory .\work\desktop-preview
.\tools\Test-DesktopControl.ps1
```

Le dossier produit contient `jellyfin-vlc-bridge-control.exe` et son fichier
`.config`, à conserver ensemble. Pour parcourir l’interface avec des données
d’exemple :

```powershell
.\work\desktop-preview\jellyfin-vlc-bridge-control.exe --preview --language fr
```

Le mode `--preview` ne lit ni ne modifie la connexion installée, n’exécute pas
ses commandes de lecture ou de maintenance et ne crée pas d’icône de
notification. Il ne prend pas la place de l’instance installée. Les actions de
lecture et de maintenance affichent seulement une indication d’aperçu.

Pour produire un PNG sans ouvrir de fenêtre interactive :

```powershell
.\work\desktop-preview\jellyfin-vlc-bridge-control.exe --render-preview .\work\desktop-overview-fr.png --language fr --page overview --scale 1
.\work\desktop-preview\jellyfin-vlc-bridge-control.exe --render-preview .\work\desktop-settings-fr.png --language fr --page settings --scale 1.5
.\work\desktop-preview\jellyfin-vlc-bridge-control.exe --render-preview .\work\desktop-diagnostics-en.png --language en --page diagnostics --scale 2
```

`--page` accepte `overview`, `settings` ou `diagnostics`, et `--language` accepte
`fr` ou `en`. Les facteurs `--scale 1`, `1.5` et `2` permettent de vérifier le
rendu à 100 %, 150 % et 200 %. Ce rendu utilise les mêmes données d’exemple et
protections que `--preview` ; il ne remplace pas un essai de déplacement réel
entre écrans ayant des facteurs d’échelle différents.

`Test-DesktopControl.ps1` teste les services avec des processus simulés et des
fichiers temporaires isolés : transmission des arguments Windows, UTF-8,
lecture simultanée des sorties, erreurs, délais, annulation et conservation des
réglages. Le [guide 1.19.0](DESKTOP-1.19.0.md) détaille les corrections et les
limites des vérifications.

## Construire la version Windows

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-WindowsRelease.ps1 -Version 1.19.1
```

Le script :

1. génère l'icône Windows depuis les icônes de l'extension ;
2. restaure et publie l'application Windows autonome en un seul fichier, avec .NET 8 intégré ;
3. compile le centre de contrôle natif WPF avec ses ressources embarquées ;
4. retire les symboles de débogage du paquet public ;
5. construit le ZIP Windows ;
6. intègre le même contenu dans l'installateur graphique `.exe`.

Fichiers produits :

```text
outputs\JellyfinVlcBridge-1.19.1-Setup.exe
outputs\JellyfinVlcBridge-1.19.1-win-x64.zip
```

Pour préparer localement les métadonnées qui accompagneront la Release :

```powershell
.\tools\New-ReleaseChecksums.ps1 -Version 1.19.1
.\tools\New-ReleaseNotes.ps1 -Version 1.19.1
.\tools\Test-ReleaseMetadata.ps1 -Version 1.19.1
```

Ces commandes préparent des fichiers locaux. La publication des téléchargements
est effectuée séparément par le workflow GitHub depuis `main` ou le tag exact.

Le workflow public atteste séparément le Setup et le ZIP exacts qu'il joint à
la Release. Une attestation GitHub établit la provenance de la compilation ;
elle ne remplace pas une signature Authenticode Windows.

## Construire l'extension Chrome

La version du manifeste de l'extension peut évoluer indépendamment de celle du Bridge.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-ExtensionPackage.ps1 -Version 1.8.1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-ExtensionPackage.ps1 -Version 1.8.1
```

Le ZIP Chrome Web Store ne contient pas le champ de développement `key`. L'élément existant dans le tableau de bord conserve l'identifiant officiel :

```text
hkjbodgdbjhignhlbecchiigcfigpidp
```

Le paquet doit être envoyé sur la fiche existante du Chrome Web Store afin de
conserver l’identifiant officiel. La publication de l’extension reste distincte
des versions Windows et passe par l’examen de Google.

Le contrôle du paquet vérifie les fichiers nécessaires, les deux langues, la
version du manifeste, l’autorisation `nativeMessaging` et l’absence du champ
`key` dans le ZIP destiné au magasin.

## Structure du code

- `src/JellyfinVlcBridge.Core` : API Jellyfin, configuration, secrets, proxy HTTP, VLC et synchronisation ;
- `src/JellyfinVlcBridge.Cli` : commandes, Quick Connect et intégration Windows ;
- `browser-extension` : manifeste, service worker, injection du bouton et styles ;
- `installer` : assistant, désinstallation, bootstrap du Setup et centre de contrôle natif WPF (`ControlCenter*.cs`, XAML, traductions et manifeste) ;
- `tests` : tests fonctionnels hors ligne ;
- `tools` : construction des icônes et paquets.

## Règles de sécurité

- ne jamais committer `config.json`, un jeton, une clé API, un journal utilisateur ou un export du Gestionnaire d'identifiants ;
- ne jamais placer le jeton dans une URL VLC ;
- conserver le proxy sur `127.0.0.1` ;
- valider les identifiants reçus de la page Jellyfin ;
- limiter `allowed_origins` aux identifiants connus de l'extension.

Le `.gitignore` exclut les compilations, paquets, journaux et configurations locales.

## Publier une Release GitHub

Le parcours recommandé tient dans une seule commande :

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Publier-Mise-A-Jour-GitHub.ps1
```

Le numéro est lu automatiquement dans `Directory.Build.props`. Le script :

1. vérifie les versions, PowerShell et JavaScript ;
2. compile et exécute les tests du Bridge et de l'extension ;
3. construit localement le Setup et le ZIP ;
4. vérifie que GitHub CLI et Git utilisent le même compte ;
5. crée une copie Git neuve et une branche de publication ;
6. ouvre une Pull Request et attend les tests GitHub ;
7. fusionne seulement si tous les tests ont réussi ;
8. crée le tag puis attend que le Setup et le ZIP soient disponibles.

Pour contrôler le projet et la connexion GitHub sans envoyer le moindre fichier :

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Publier-Mise-A-Jour-GitHub.ps1 -ValidateOnly
```

Si Internet ou GitHub s'interrompt après la création du tag, relancer exactement la
même commande reprend la vérification de la Release sans renvoyer le code.

Une modification volontaire de `.github/workflows` exige l'autorisation GitHub
supplémentaire `workflow`. Le script s'arrête avant tout envoi si elle manque et
affiche la commande unique à exécuter.

La construction locale est la méthode de publication recommandée : elle permet de tester exactement les deux fichiers qui seront proposés aux utilisateurs. Les vérifications GitHub Actions restent un contrôle complémentaire du code source.

L'extension Chrome possède son propre cycle de version et reste publiée séparément dans le Chrome Web Store après examen par Google. Les textes, captures d’écran et autres éléments promotionnels sont gérés dans le tableau de bord du magasin et ne font pas partie des sources nécessaires à la compilation.

## Préparer WinGet

Une soumission WinGet nécessite l'URL et l'empreinte du Setup déjà publié. Après
validation d'une Release publique, générez les quatre manifestes avec :

```powershell
.\tools\New-WinGetManifests.ps1 `
  -Version 1.18.1 `
  -InstallerSha256 EMPREINTE_SHA256_PUBLIEE `
  -ReleaseDate AAAA-MM-JJ
```

La date doit correspondre à la publication de la Release GitHub. Validez ensuite
les manifestes avec `winget validate`, puis l'installation `/quiet`, la première
connexion Quick Connect, la mise à niveau et la désinstallation dans un
environnement propre. Le dossier
[`packaging/winget`](../packaging/winget/README.md) décrit le parcours. Aucun
script du projet ne soumet automatiquement un paquet à Microsoft.

## Tester le vrai cycle Windows

La CI construit le véritable Setup auto-extractible sur une machine Windows
éphémère, l'installe deux fois silencieusement, vérifie les fichiers, raccourcis,
clés HKCU, protocole et hôtes natifs, puis exécute la désinstallation silencieuse
enregistrée par Windows :

```powershell
.\tools\Test-WindowsLifecycle.ps1
```

Le script refuse de démarrer lorsqu'une installation du Bridge existe déjà. Il
est destiné à une VM propre ou au runner GitHub, sans serveur Jellyfin, jeton,
navigateur ou VLC réel. Les interactions visuelles et Quick Connect restent des
vérifications manuelles avant publication.

## Publication du code

Le dépôt Git contient les sources et la documentation. Les fichiers compilés de `outputs/` sont exclus du dépôt et ajoutés séparément à GitHub Releases.

Le projet utilise la licence MIT. Toute copie ou redistribution doit conserver le fichier `LICENSE` et l'avis de copyright.
