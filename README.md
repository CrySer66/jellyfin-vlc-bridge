# Jellyfin VLC Bridge

[![Vérifications Windows](https://github.com/CrySer66/jellyfin-vlc-bridge/actions/workflows/ci.yml/badge.svg)](https://github.com/CrySer66/jellyfin-vlc-bridge/actions/workflows/ci.yml)

Jellyfin VLC Bridge ajoute un bouton **Lire avec VLC** dans Jellyfin Web. Le média original est ouvert dans VLC sur le PC client, sans modifier Jellyfin et sans transmettre de données au développeur.

Version actuelle : **1.8.1**  
Plateforme disponible : **Windows 10/11 x64**  
Extension Chrome Web Store : **disponible publiquement**

## Installation rapide

1. Installez [VLC Media Player](https://www.videolan.org/vlc/).
2. Téléchargez `JellyfinVlcBridge-1.8.1-Setup.exe` depuis la page **Releases** de ce dépôt.
3. Lancez l'installateur et saisissez l'adresse de votre serveur Jellyfin.
4. Dans Jellyfin, autorisez le code affiché depuis **Paramètres → Quick Connect**.
5. La fiche Chrome Web Store s'ouvre automatiquement. Cliquez sur **Ajouter à Chrome**.
6. Rechargez Jellyfin et utilisez **Lire avec VLC**.

Si la page de l'extension a été fermée, ouvrez simplement :

[Installer l'extension Jellyfin VLC Bridge](https://chromewebstore.google.com/detail/hkjbodgdbjhignhlbecchiigcfigpidp)

Le guide détaillé se trouve dans [INSTALLATION.md](INSTALLATION.md).

## Fonctionnalités

- films, épisodes, saisons et séries ;
- reprise à la position enregistrée dans Jellyfin ;
- synchronisation de la lecture, de la pause et de l'arrêt ;
- enchaînement automatique des épisodes dans une seule liste VLC ;
- HTTP Direct Play recommandé ou chemins SMB configurables ;
- Quick Connect, sans clé API administrateur à copier ;
- jeton conservé dans le Gestionnaire d'identifiants Windows ;
- installation et désinstallation graphiques ;
- centre de contrôle graphique avec diagnostic et réparation en un clic ;
- aide intégrée pour ouvrir le guide ou signaler un problème ;
- vérification et installation guidée des nouvelles Releases GitHub ;
- lecture lancée silencieusement en arrière-plan, sans fenêtre CMD ;
- environnement .NET intégré à l'application, sans prérequis à installer séparément ;
- aucune modification des fichiers du serveur Jellyfin.

Après l'installation, ouvrez **Jellyfin VLC Bridge** depuis le menu Démarrer. Cette fenêtre permet de vérifier Jellyfin, VLC et Chrome/Edge, de choisir le mode HTTP ou SMB et de copier un diagnostic sans secret.

## Deux téléchargements

- `JellyfinVlcBridge-1.8.1-Setup.exe` : installation recommandée et guidée ;
- `JellyfinVlcBridge-1.8.1-win-x64.zip` : paquet avancé inspectable et utilisable manuellement.

Les sources de l'application et de l'extension restent toutes disponibles dans ce dépôt. Elles ne sont pas dupliquées dans le ZIP Windows afin de garder le téléchargement lisible.

## Vie privée et sécurité

L'extension transmet uniquement l'identifiant technique du média au programme installé sur le même PC. Le programme communique ensuite directement avec le serveur Jellyfin choisi par l'utilisateur.

- aucun compte auprès du développeur ;
- aucune publicité, télémétrie ou analyse d'utilisation ;
- aucun jeton dans l'extension ou dans l'URL donnée à VLC ;
- relais HTTP limité à `127.0.0.1` ;
- accès natif autorisé uniquement pour les identifiants connus de l'extension.

Consultez la [politique de confidentialité](PRIVACY.md) et la [description détaillée de l'installation](INSTALLATION.md#ce-qui-est-ajouté-sur-windows).

## Organisation du dépôt

```text
browser-extension/   extension Chrome complète
installer/           installation et désinstallation Windows
src/                 application .NET
tests/               tests automatisés hors ligne
tools/               scripts de construction
docs/                documentation complémentaire
```

Les fichiers compilés ne sont pas placés dans le code source Git. Ils sont attachés aux versions dans **GitHub Releases**.

## Développement

Les instructions de compilation, les vérifications automatiques et la publication d'une nouvelle version sont dans [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Limites actuelles

- Windows est la seule plateforme disposant d'un installateur finalisé ;
- VLC doit être installé séparément ;
- les pistes audio et les sous-titres sont choisis dans VLC ;
- l'extension dépend de l'interface Jellyfin Web et peut nécessiter une adaptation après une évolution importante de Jellyfin ;
- l'installateur n'est pas encore signé avec un certificat commercial, Windows SmartScreen peut donc afficher un avertissement.

## Signaler un problème

Utilisez **Aide et signaler un bug** dans le centre de contrôle, ou ouvrez directement le [formulaire d'assistance GitHub](https://github.com/CrySer66/jellyfin-vlc-bridge/issues/new/choose). Le diagnostic copié par l'application indique les versions utiles sans inclure le jeton Jellyfin.

Ne publiez jamais un mot de passe, un jeton Jellyfin, une clé API ou le contenu du Gestionnaire d'identifiants Windows.

## Licence

Jellyfin VLC Bridge est distribué sous [licence MIT](LICENSE). Le code peut être consulté, utilisé, modifié et redistribué en conservant l'avis de copyright et la licence.
