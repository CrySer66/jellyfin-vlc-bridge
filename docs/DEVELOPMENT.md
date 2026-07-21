# Développement et publication

Ce document concerne les personnes qui souhaitent examiner, compiler ou contribuer au projet.

## Environnement

- Windows 10/11 x64 pour construire l'installateur ;
- SDK .NET 8 ou plus récent ;
- PowerShell 5.1 ou plus récent ;
- VLC pour les tests de lecture réels.

## Compiler et tester

Depuis la racine du dépôt :

```powershell
dotnet restore JellyfinVlcBridge.slnx --configfile NuGet.Config
dotnet build JellyfinVlcBridge.slnx --configuration Release --no-restore
dotnet run --project tests\JellyfinVlcBridge.Tests --configuration Release --no-restore
```

Les tests sont hors ligne et ne nécessitent aucun jeton Jellyfin.

## Construire la version Windows

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-WindowsRelease.ps1 -Version 1.6.1
```

Le script :

1. génère l'icône Windows depuis les icônes de l'extension ;
2. restaure et publie l'application .NET ;
3. retire les symboles de débogage du paquet public ;
4. construit le ZIP Windows ;
5. intègre le même contenu dans l'installateur graphique `.exe`.

Fichiers produits :

```text
outputs\JellyfinVlcBridge-1.6.1-Setup.exe
outputs\JellyfinVlcBridge-1.6.1-win-x64.zip
```

## Construire l'extension Chrome

La version du manifeste de l'extension peut évoluer indépendamment de celle du Bridge.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-ExtensionPackage.ps1 -Version 1.3.0
```

Le ZIP Chrome Web Store ne contient pas le champ de développement `key`. L'élément existant dans le tableau de bord conserve l'identifiant officiel :

```text
hkjbodgdbjhignhlbecchiigcfigpidp
```

Consultez [STORE-PUBLISHING.md](../STORE-PUBLISHING.md) avant d'envoyer une mise à jour.

## Structure du code

- `src/JellyfinVlcBridge.Core` : API Jellyfin, configuration, secrets, proxy HTTP, VLC et synchronisation ;
- `src/JellyfinVlcBridge.Cli` : commandes, Quick Connect et intégration Windows ;
- `browser-extension` : manifeste, service worker, injection du bouton et styles ;
- `installer` : assistant, désinstallation et bootstrap du Setup ;
- `tests` : tests fonctionnels hors ligne ;
- `tools` : construction des icônes et paquets.

## Règles de sécurité

- ne jamais committer `config.json`, un jeton, une clé API, un journal utilisateur ou un export du Gestionnaire d'identifiants ;
- ne jamais placer le jeton dans une URL VLC ;
- conserver le proxy sur `127.0.0.1` ;
- valider les identifiants reçus de la page Jellyfin ;
- limiter `allowed_origins` aux identifiants connus de l'extension.

Le `.gitignore` exclut les compilations, paquets, journaux et configurations locales.

## Checklist d'une Release GitHub

1. mettre à jour `Directory.Build.props`, `BridgeVersion.cs`, les installateurs et le changelog ;
2. lancer la compilation et tous les tests ;
3. construire les paquets ;
4. vérifier la version et l'icône de l'installateur ;
5. tester une mise à jour par-dessus une installation existante ;
6. tester une installation propre et Quick Connect ;
7. tester l'ouverture de la fiche Chrome Web Store ;
8. créer le tag correspondant, par exemple `v1.6.1` ;
9. joindre uniquement le Setup et le ZIP Windows à la Release ;
10. publier des notes de version compréhensibles.

## Publication du code

Le dépôt Git contient les sources et la documentation. Les fichiers compilés de `outputs/` sont exclus du dépôt et ajoutés séparément à GitHub Releases.

Le projet utilise la licence MIT. Toute copie ou redistribution doit conserver le fichier `LICENSE` et l'avis de copyright.
