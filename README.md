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
| **1.19.1** | **Windows 10/11 x64** | **1.8.1** (paquet préparé) |

**Nouveautés 1.19.1 :** le centre de contrôle, l’installateur et le désinstallateur partagent désormais une interface WPF avec cartes arrondies et icônes vectorielles. Cette version inclut aussi les corrections de suivi VLC, de réglages SMB et d’export d’assistance préparées en 1.19.0. Exécutez le nouveau Setup pour mettre à jour les trois interfaces en conservant votre connexion. Consultez le [guide des assistants et des vérifications](docs/MAINTENANCE-1.19.1.md).

<p align="center">
  <img src="assets/preview-jellyfin-vlc-bridge.png" width="820" alt="Un média passe de Jellyfin vers VLC grâce au Bridge local">
</p>

## Installation

1. **Préparez VLC** — installez [VLC Media Player](https://www.videolan.org/vlc/).
2. **Installez le Bridge** — téléchargez `JellyfinVlcBridge-<version>-Setup.exe` depuis la [dernière version GitHub](https://github.com/CrySer66/jellyfin-vlc-bridge/releases/latest), lancez-le, puis autorisez son code dans **Jellyfin → Paramètres → Quick Connect**.
3. **Ajoutez le bouton** — installez l’[extension Chrome officielle](https://chromewebstore.google.com/detail/hkjbodgdbjhignhlbecchiigcfigpidp), rechargez Jellyfin, ouvrez un média et sélectionnez **Lire avec VLC**.

**Vérification rapide :** ouvrez la fiche d’un film ou d’un épisode dans Jellyfin. Le bouton **Lire avec VLC** doit apparaître dans la barre d’actions.

**Jellyfin 12 :** le Bridge 1.18.1 adapte l’authentification tout en conservant le même mécanisme pour Jellyfin 10.x. L’extension 1.8.1 affiche les erreurs de préparation dans la fenêtre de lecture. Consultez les [étapes de mise à jour](INSTALLATION.md#après-une-mise-à-jour-vers-jellyfin-12) et les [limites des vérifications de compatibilité](docs/COMPATIBILITY.md#jellyfin-10x-et-12).

Le correctif de lecture fonctionne avec l’extension 1.8.0 déjà installée. Le paquet 1.8.1 est prêt pour une soumission séparée au Chrome Web Store ; sa présence sur GitHub ne signifie pas qu’il est déjà disponible dans la boutique.

L’installation se fait pour l’utilisateur Windows actuel et ne demande pas de droits administrateur. Le [guide détaillé](INSTALLATION.md) explique aussi HTTP Direct Play, SMB, les mises à jour et la désinstallation.

**WinGet (facultatif) :** la version 1.18.0 a été [acceptée le 31 août 2026](https://github.com/microsoft/winget-pkgs/pull/413912). Sa disponibilité dans le catalogue n’était pas encore confirmée lors de notre vérification du même jour. Le [guide WinGet](INSTALLATION.md#installer-avec-winget-facultatif) explique comment la vérifier, puis installer et mettre à jour le Bridge. Le téléchargement GitHub reste disponible.

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
- retrouver le centre de contrôle depuis une icône discrète près de l’horloge Windows ;
- installer les mises à jour publiées dans GitHub Releases ;
- fonctionner sans fenêtre de commande et sans modifier les fichiers de Jellyfin.

## Vie privée et sécurité

Le projet ne contient ni publicité, ni télémétrie, ni outil d’analyse. L’extension transmet au programme installé sur le même PC uniquement l’identifiant technique du média et les choix de lecture. Le relais local écoute exclusivement sur `127.0.0.1`.

Le diagnostic et le paquet d’assistance générés par l’application excluent le jeton Jellyfin et les identifiants personnels. Consultez la [politique de confidentialité](PRIVACY.md), la [politique de sécurité](SECURITY.md), la [politique de signature](CODE_SIGNING.md) et le [guide de vérification](docs/VERIFY_DOWNLOADS.md).

## Télécharger en confiance

Les exécutables Windows ne possèdent actuellement **pas de signature Authenticode**. La première candidature au programme open source de SignPath Foundation n’a pas été acceptée, le projet n’ayant pas encore assez de visibilité et de réputation. Windows SmartScreen peut donc afficher un avertissement, même pour un fichier officiel intact.

Téléchargez toujours le Bridge depuis la page [Releases de ce dépôt](https://github.com/CrySer66/jellyfin-vlc-bridge/releases). À partir de la version 1.18.0, les versions fournissent :

- une empreinte SHA-256 dans `SHA256SUMS.txt` ;
- une attestation GitHub pour l’installateur et le ZIP, qui permet de confirmer qu’ils proviennent du workflow public de ce dépôt.

Le centre de contrôle compare aussi automatiquement l’empreinte SHA-256 annoncée par GitHub avant d’ouvrir un installateur de mise à jour.

Consultez le [guide de vérification des téléchargements](docs/VERIFY_DOWNLOADS.md) avant de prendre une décision face à un avertissement Windows. Une attestation de provenance ne remplace pas une signature Windows et ne supprime pas SmartScreen.

## Langues

L’application Windows et l’extension Chrome sont disponibles en français et en anglais. Chrome suit automatiquement la langue du navigateur. Le centre de contrôle suit Windows, avec un choix manuel possible.

## Documentation et contribution

- [Installation détaillée](INSTALLATION.md)
- [Compilation et développement](docs/DEVELOPMENT.md)
- [Compatibilité et environnements pris en charge](docs/COMPATIBILITY.md)
- [Vérifier un téléchargement](docs/VERIFY_DOWNLOADS.md)
- [Feuille de route de distribution](docs/DISTRIBUTION.md)
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
