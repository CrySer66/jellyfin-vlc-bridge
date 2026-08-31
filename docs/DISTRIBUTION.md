# Distribution / Distribution roadmap

Cette feuille de route décrit l'ordre envisagé pour rendre Jellyfin VLC Bridge
plus simple à trouver, installer et vérifier. Elle ne promet ni date ni
acceptation par un magasin tiers.

Jellyfin VLC Bridge reste volontairement une application **Windows 10/11 x64**.
Des versions Linux ou macOS ne sont pas prévues tant qu'elles ne peuvent pas
être testées sérieusement.

## Étapes prévues

1. **GitHub Releases** — publier l'installateur et le ZIP avec
   `SHA256SUMS.txt` et des attestations GitHub. C'est la source officielle du
   programme Windows.
2. **WinGet** — la version 1.18.0 a été acceptée et fusionnée le 31 août 2026
   ([demande nº 413912](https://github.com/microsoft/winget-pkgs/pull/413912)).
   La disponibilité dans le catalogue restait à confirmer lors de notre
   vérification du même jour. Le [guide WinGet](../INSTALLATION.md#installer-avec-winget-facultatif)
   distingue la vérification, l'installation et la première connexion.
   Chaque future version nécessite une nouvelle soumission ; une Release
   GitHub ne met pas automatiquement WinGet à jour.
3. **Microsoft Edge Add-ons** — préparer la fiche de l'extension, puis la
   soumettre une fois l'identifiant Microsoft obtenu. L'extension Chrome reste
   distribuée par le Chrome Web Store.
4. **MSIX / Microsoft Store** — étudier la compatibilité avec Native Messaging,
   les clés de registre utilisateur et le processus de mise à jour. Cette piste
   n'est pas annoncée comme disponible tant qu'un prototype complet n'a pas été
   validé.
5. **Signature Authenticode** — réévaluer SignPath ou une autre solution quand
   le projet disposera de davantage d'utilisateurs et d'un historique public
   plus solide.

Les liens officiels seront ajoutés aux guides uniquement après chaque
publication effective.

---

This roadmap describes the intended order for making Jellyfin VLC Bridge easier
to discover, install and verify. It does not promise a date or acceptance by any
third-party store.

Jellyfin VLC Bridge intentionally remains a **Windows 10/11 x64** application.
Linux and macOS builds are not planned while they cannot be tested properly.

## Planned steps

1. **GitHub Releases** — publish the installer and ZIP with
   `SHA256SUMS.txt` and GitHub attestations. This is the official source for the
   Windows application.
2. **WinGet** — version 1.18.0 was accepted and merged on August 31, 2026
   ([pull request #413912](https://github.com/microsoft/winget-pkgs/pull/413912)).
   Catalog availability still needed confirmation during our check that day.
   The [WinGet guide](../INSTALLATION.en.md#install-with-winget-optional)
   separates availability checks, installation and first connection.
   Each future version requires a new submission; publishing a GitHub Release
   does not automatically update WinGet.
3. **Microsoft Edge Add-ons** — prepare the extension listing, then submit it
   once a Microsoft extension ID is available. The Chrome extension remains
   distributed through the Chrome Web Store.
4. **MSIX / Microsoft Store** — study compatibility with Native Messaging,
   per-user registry entries and the update process. This route will not be
   announced as available until a complete prototype has been validated.
5. **Authenticode signing** — reconsider SignPath or another solution after the
   project has gained more users and a stronger public track record.

Official links will be added to the guides only after each publication is
actually available.
