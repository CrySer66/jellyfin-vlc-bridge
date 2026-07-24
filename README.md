<p align="center">
  <img src="browser-extension/icons/icon128.png" width="96" alt="Icône Jellyfin VLC Bridge">
</p>

<h1 align="center">Jellyfin VLC Bridge</h1>

<p align="center">
  Lancez vos films, séries et collections Jellyfin dans VLC, avec reprise et progression synchronisée.
</p>

<p align="center">
  <a href="https://github.com/CrySer66/jellyfin-vlc-bridge/releases/latest"><img alt="Dernière version" src="https://img.shields.io/github/v/release/CrySer66/jellyfin-vlc-bridge?display_name=tag&sort=semver"></a>
  <a href="https://github.com/CrySer66/jellyfin-vlc-bridge/actions/workflows/ci.yml"><img alt="Vérifications Windows" src="https://github.com/CrySer66/jellyfin-vlc-bridge/actions/workflows/ci.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="Licence MIT" src="https://img.shields.io/github/license/CrySer66/jellyfin-vlc-bridge"></a>
</p>

<p align="center">
  <a href="https://github.com/CrySer66/jellyfin-vlc-bridge/releases/latest"><strong>Télécharger pour Windows</strong></a>
  ·
  <a href="https://chromewebstore.google.com/detail/hkjbodgdbjhignhlbecchiigcfigpidp"><strong>Installer l’extension Chrome</strong></a>
  ·
  <a href="INSTALLATION.md">Guide d’installation</a>
  ·
  <a href="README.en.md">English</a>
</p>

Jellyfin VLC Bridge ajoute l’action **Lire avec VLC** dans Jellyfin Web. Le média original est ouvert sur le PC Windows dans VLC, sans modifier le serveur Jellyfin et sans envoyer de données au développeur.

| Application | Plateforme | Extension |
|---|---|---|
| **1.14.0** | **Windows 10/11 x64** | **Chrome Web Store 1.8.0** |

<p align="center">
  <img src="assets/preview-jellyfin-vlc-bridge.png" width="820" alt="Un média passe de Jellyfin vers VLC grâce au Bridge local">
</p>

## Installation

1. Installez [VLC Media Player](https://www.videolan.org/vlc/).
2. Téléchargez `JellyfinVlcBridge-<version>-Setup.exe` depuis la [dernière version GitHub](https://github.com/CrySer66/jellyfin-vlc-bridge/releases/latest).
3. Lancez l’installateur et indiquez l’adresse de votre serveur Jellyfin.
4. Autorisez le code dans **Jellyfin → Paramètres → Quick Connect**.
5. Installez l’[extension Chrome officielle](https://chromewebstore.google.com/detail/hkjbodgdbjhignhlbecchiigcfigpidp).
6. Rechargez Jellyfin, ouvrez un média et sélectionnez **Lire avec VLC**.

L’installation se fait pour l’utilisateur Windows actuel et ne demande pas de droits administrateur. Le [guide détaillé](INSTALLATION.md) explique aussi HTTP Direct Play, SMB, les mises à jour et la désinstallation.

## Ce que le Bridge sait faire

- lire des films, épisodes, saisons, séries et collections ;
- choisir la version Jellyfin d’un média, par exemple 1080p ou 4K, avant de lancer VLC ;
- reprendre à la position enregistrée ou recommencer depuis le début ;
- synchroniser lecture, pause, arrêt et progression avec Jellyfin ;
- enchaîner automatiquement les épisodes ou les films préparés ;
- utiliser HTTP Direct Play, recommandé, ou un partage SMB existant ;
- se connecter avec Quick Connect, sans clé API administrateur à copier ;
- protéger le jeton Jellyfin dans le Gestionnaire d’identifiants Windows ;
- diagnostiquer et réparer l’intégration depuis un centre de contrôle graphique ;
- installer les mises à jour publiées dans GitHub Releases ;
- fonctionner sans fenêtre de commande et sans modifier les fichiers de Jellyfin.

## Vie privée et sécurité

Le projet ne contient ni publicité, ni télémétrie, ni outil d’analyse. L’extension transmet au programme installé sur le même PC uniquement l’identifiant technique du média et les choix de lecture. Le relais local écoute exclusivement sur `127.0.0.1`.

Le diagnostic et le paquet d’assistance générés par l’application excluent le jeton Jellyfin et les identifiants personnels. Consultez la [politique de confidentialité](PRIVACY.md), la [politique de sécurité](SECURITY.md) et la [politique de signature](CODE_SIGNING.md).

La candidature au programme gratuit de signature open source de SignPath Foundation a été envoyée et reste en attente d’examen. Les téléchargements sont donc encore non signés et Windows SmartScreen peut afficher un avertissement.

## Langues

L’application Windows et l’extension Chrome sont disponibles en français et en anglais. Chrome suit automatiquement la langue du navigateur. Le centre de contrôle suit Windows, avec un choix manuel possible.

## Documentation et contribution

- [Installation détaillée](INSTALLATION.md)
- [Compilation et développement](docs/DEVELOPMENT.md)
- [Compatibilité et environnements pris en charge](docs/COMPATIBILITY.md)
- [Proposer une correction](CONTRIBUTING.md)
- [Historique des versions](CHANGELOG.md)
- [Signaler un problème](https://github.com/CrySer66/jellyfin-vlc-bridge/issues/new/choose)

Les sources de l’application, de l’extension, de l’installateur et des tests sont publiques. Les exécutables compilés sont publiés séparément dans [GitHub Releases](https://github.com/CrySer66/jellyfin-vlc-bridge/releases).

## Limites actuelles

- l’installateur finalisé cible Windows 10/11 x64 ;
- VLC doit être installé séparément ;
- les pistes audio et les sous-titres sont sélectionnés dans VLC ;
- une évolution importante de Jellyfin Web peut nécessiter une adaptation de l’extension.

## Licence

Jellyfin VLC Bridge est un projet indépendant, non affilié à Jellyfin, VideoLAN, Google ou Microsoft. Il est distribué sous [licence MIT](LICENSE).
