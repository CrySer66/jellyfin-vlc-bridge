# Compatibilité

[English version](#compatibility)

## Environnement pris en charge

| Élément | Prise en charge |
|---|---|
| Windows | Windows 10 et Windows 11, édition x64 |
| VLC | VLC Media Player pour Windows ; VLC 3.x recommandé |
| Jellyfin | serveur accessible par HTTP ou HTTPS et interface Jellyfin Web sous `/web/` |
| Navigateur | Google Chrome ; Microsoft Edge basé sur Chromium peut utiliser l’extension Chrome |
| Réseau | HTTP Direct Play recommandé ; SMB disponible lorsqu’un partage fonctionne déjà dans l’Explorateur Windows |

L’installateur, le centre de contrôle et la désinstallation sont conçus et testés
pour Windows. Le code comporte quelques abstractions portables, mais Linux et macOS
ne sont pas annoncés comme pris en charge tant qu’ils ne peuvent pas être testés
régulièrement.

## Combinaisons de versions

- le Bridge 1.19.1 et le paquet de l’extension 1.8.1 forment la combinaison recommandée ; la soumission au Chrome Web Store suit un parcours séparé ;
- une extension plus ancienne peut continuer à lancer une lecture standard, sans
  le choix d’une version 1080p ou 4K ;
- après une mise à jour de l’extension, rechargez les onglets Jellyfin déjà ouverts ;
- seule la dernière version publiée du Bridge reçoit les correctifs.

## Jellyfin 10.x et 12

Jellyfin 12 désactive par défaut les anciennes méthodes d’authentification, y
compris sur les serveurs mis à jour. Cela peut provoquer une erreur 401 lors de
la préparation ou du lancement avec un ancien Bridge. Voir les [notes officielles
de Jellyfin 12](https://jellyfin.org/posts/jellyfin-release-12.0/#http-api).

Le Bridge 1.18.1 utilise `Authorization: MediaBrowser` pour l’API, Quick Connect
et le relais HTTP. Ce format est lu dans le code officiel de
[Jellyfin 10.8.13](https://github.com/jellyfin/jellyfin/blob/v10.8.13/Jellyfin.Server.Implementations/Security/AuthorizationContext.cs)
et de [Jellyfin 12.0](https://github.com/jellyfin/jellyfin/blob/v12.0/Jellyfin.Server.Implementations/Security/AuthorizationContext.cs).
Le correctif conserve donc un mécanisme commun aux anciennes et nouvelles
versions, sans changer la configuration d’authentification du serveur.

| Vérification | Portée et limite |
|---|---|
| Lecture des sources Jellyfin 10.8.13 et 12.0 | Confirme la prise en charge du même en-tête ; ne constitue pas un essai de lecture sur ces serveurs. |
| Tests natifs hors ligne | Couvrent les en-têtes des appels API, Quick Connect et du relais HTTP, notamment les requêtes partielles et `HEAD`, avec un serveur simulé. |
| Tests de l’extension hors ligne | Couvrent les erreurs de préparation et le lancement simplifié avec un ancien Bridge ; ne remplacent pas une vérification dans Chrome. |
| Essai réel Jellyfin 12.0.0, Bridge 1.18.1, extension 1.8.0 (10 septembre 2026) | Connexion existante conservée, aperçu complet, lancement depuis Chrome, vidéo décodée dans VLC, flux HTTP 206 et session Jellyfin en Direct Play à 50 secondes avec pause synchronisée. |
| Jellyfin 10.x ; séries, reprise et versions multiples sur serveur réel | Authentification vérifiée dans les sources et comportements couverts par les tests hors ligne. Pas d’essai réel de ces combinaisons pendant cette validation. |

Avec l’extension 1.8.1, une erreur de préparation reste visible dans la fenêtre
de lecture. Le lancement simplifié est réservé aux anciens Bridge qui ne
reconnaissent pas la commande de préparation. Pour appliquer le correctif, suivez
les [étapes de mise à jour](../INSTALLATION.md#après-une-mise-à-jour-vers-jellyfin-12).

## Modes de lecture

**HTTP Direct Play** utilise un relais authentifié limité à `127.0.0.1`. Le jeton
Jellyfin n’est jamais placé dans l’URL donnée à VLC.

**SMB** ouvre directement le chemin réseau configuré. Avant de sélectionner ce
mode, le même fichier doit déjà être lisible depuis l’Explorateur Windows avec le
compte de l’utilisateur.

## Signaler une incompatibilité

Créez un paquet d’assistance depuis le centre de contrôle et joignez-le à une
[Issue GitHub](https://github.com/CrySer66/jellyfin-vlc-bridge/issues/new/choose).
Indiquez les versions de Windows, VLC, Jellyfin, du Bridge et de l’extension.
Le paquet d’assistance retire les jetons et identifiants personnels connus.

---

# Compatibility

## Supported environment

| Component | Support |
|---|---|
| Windows | Windows 10 and Windows 11, x64 editions |
| VLC | VLC Media Player for Windows; VLC 3.x recommended |
| Jellyfin | server reachable through HTTP or HTTPS with Jellyfin Web under `/web/` |
| Browser | Google Chrome; Chromium-based Microsoft Edge can use the Chrome extension |
| Network | recommended HTTP Direct Play; SMB when the share already works in Windows File Explorer |

The installer, Control Center and uninstaller are designed and tested for Windows.
Linux and macOS are not advertised as supported until they can be tested regularly.

Bridge 1.19.1 with extension package 1.8.1 is the recommended combination;
Chrome Web Store submission is a separate process. An older
extension can still request standard playback but does not provide media-version
selection. Reload existing Jellyfin tabs after an extension update.

## Jellyfin 10.x and 12

Jellyfin 12 disables legacy authentication by default, including on upgraded
servers. An older Bridge may consequently receive HTTP 401 during preparation
or playback. See the [official Jellyfin 12 release notes](https://jellyfin.org/posts/jellyfin-release-12.0/#http-api).

Bridge 1.18.1 uses `Authorization: MediaBrowser` for API calls, Quick Connect and
the HTTP relay. The official authentication code accepts this format in both
[Jellyfin 10.8.13](https://github.com/jellyfin/jellyfin/blob/v10.8.13/Jellyfin.Server.Implementations/Security/AuthorizationContext.cs)
and [Jellyfin 12.0](https://github.com/jellyfin/jellyfin/blob/v12.0/Jellyfin.Server.Implementations/Security/AuthorizationContext.cs).
The fix keeps one mechanism across older and newer versions without changing
the server authentication settings.

| Verification | Scope and limitation |
|---|---|
| Jellyfin 10.8.13 and 12.0 source review | Confirms support for the same header; does not constitute playback testing on either server. |
| Offline native tests | Cover API, Quick Connect and HTTP relay headers, including range and `HEAD` requests, against a simulated server. |
| Offline extension tests | Cover preparation errors and simplified playback with an older Bridge; do not replace a check in Chrome. |
| Live Jellyfin 12.0.0, Bridge 1.18.1, extension 1.8.0 (10 September 2026) | Existing connection preserved; full preview; launch from Chrome; decoded video in VLC; HTTP 206 stream; Jellyfin Direct Play session at 50 seconds with synchronized pause. |
| Jellyfin 10.x; series, resume and multiple versions on a real server | Authentication checked in upstream source and behavior covered by offline tests. These combinations were not tested live during this validation. |

Extension 1.8.1 keeps preparation errors visible in the playback dialog.
Simplified playback is reserved for older Bridge versions that do not recognize
the preparation command. Follow the [upgrade steps](../INSTALLATION.en.md#after-upgrading-to-jellyfin-12)
to apply the fix.

For an incompatibility, create a redacted support package from the Control Center
and attach it to a [GitHub Issue](https://github.com/CrySer66/jellyfin-vlc-bridge/issues/new/choose).
