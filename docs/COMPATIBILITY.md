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

- le Bridge 1.14.0 et l’extension 1.8.0 forment la combinaison recommandée ;
- une extension plus ancienne peut continuer à lancer une lecture standard, sans
  le choix d’une version 1080p ou 4K ;
- après une mise à jour de l’extension, rechargez les onglets Jellyfin déjà ouverts ;
- seule la dernière version publiée du Bridge reçoit les correctifs.

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

Bridge 1.14.0 with extension 1.8.0 is the recommended combination. An older
extension can still request standard playback but does not provide media-version
selection. Reload existing Jellyfin tabs after an extension update.

For an incompatibility, create a redacted support package from the Control Center
and attach it to a [GitHub Issue](https://github.com/CrySer66/jellyfin-vlc-bridge/issues/new/choose).
