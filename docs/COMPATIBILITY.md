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

**Windows 11 x64 est recommandé.** Pour Windows 10, la prise en charge de
.NET 10 par Microsoft dépend de l’édition et de son cycle de support. Consultez
la [liste officielle des systèmes pris en charge](https://github.com/dotnet/core/blob/main/release-notes/10.0/supported-os.md#windows).
Cette liste ne remplace pas les essais du Bridge rapportés ci-dessous.

## Combinaisons de versions

- utilisez la [dernière version Windows publiée](https://github.com/CrySer66/jellyfin-vlc-bridge/releases/latest) avec l’extension **1.9.0**, publiée sur le Chrome Web Store le 26 septembre 2026 ;
- une extension plus ancienne peut continuer à lancer une lecture standard, sans
  le choix d’une version 1080p ou 4K ;
- après une mise à jour de l’extension, rechargez les onglets Jellyfin déjà ouverts ;
- seule la dernière version publiée du Bridge reçoit les correctifs.

Le Bridge **1.21.0 utilise un moteur de lecture reposant sur**
**.NET 10 LTS**, inclus dans l’application. Cette migration ne nécessite pas
d’installer .NET séparément et conserve l’extension 1.9.0. La disponibilité
publique se vérifie sur GitHub Releases ; un paquet local ne vaut pas publication.

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
| Essai réel isolé Jellyfin 12.4.0, Bridge 1.21.0 sous .NET 10.0.15, VLC 3.0.24 (14 novembre 2026) | Deux lectures d’une vidéo synthétique par la boucle de lecture réelle du Bridge, décodage vidéo confirmé ; progression enregistrée à 9 secondes, reprise à 9 secondes puis progression enregistrée à 21 secondes. |

L’essai du 14 novembre utilise un serveur, un compte et un profil VLC de test
isolés, avec une vidéo synthétique de 120 secondes, des seuils de reprise
adaptés à sa courte durée et VLC sans affichage ni son. Il ne couvre pas le
parcours Chrome, Quick Connect, les séries ni les
versions multiples sur Jellyfin 12.4. Les essais historiques restent indiqués
séparément dans la matrice.

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

**Windows 11 x64 is recommended.** On Windows 10, Microsoft's .NET 10 support
depends on the edition and its support lifecycle. See the
[official supported OS list](https://github.com/dotnet/core/blob/main/release-notes/10.0/supported-os.md#windows).
That list does not replace the Bridge tests reported below.

Use the [latest published Windows release](https://github.com/CrySer66/jellyfin-vlc-bridge/releases/latest)
with extension **1.9.0**, published on the Chrome Web Store on September 26, 2026. An older
extension can still request standard playback but does not provide media-version
selection. Reload existing Jellyfin tabs after an extension update.

Bridge **1.21.0 uses a playback engine based on .NET 10 LTS**,
included in the application. No separate .NET installation is needed, and the
extension remains at 1.9.0. Check GitHub Releases for public availability;
a local package does not constitute publication.

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
| Isolated live Jellyfin 12.4.0, Bridge 1.21.0 on .NET 10.0.15, VLC 3.0.24 (14 November 2026) | Two plays of a synthetic video through the actual Bridge playback loop, with video decoding confirmed; progress saved at 9 seconds, resumed at 9 seconds, then saved at 21 seconds. |

The November 14 test uses an isolated test server, account and VLC profile.
A 120-second synthetic video is used with resume thresholds adjusted to its
short duration and VLC running without video or audio output. It does not
cover the Chrome flow, Quick Connect, series or multiple media
versions on Jellyfin 12.4. Historical checks remain listed separately in the
matrix.

Extension 1.8.1 keeps preparation errors visible in the playback dialog.
Simplified playback is reserved for older Bridge versions that do not recognize
the preparation command. Follow the [upgrade steps](../INSTALLATION.en.md#after-upgrading-to-jellyfin-12)
to apply the fix.

For an incompatibility, create a redacted support package from the Control Center
and attach it to a [GitHub Issue](https://github.com/CrySer66/jellyfin-vlc-bridge/issues/new/choose).
