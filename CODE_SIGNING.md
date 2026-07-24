# Code signing policy

## Current status

Jellyfin VLC Bridge is applying to the SignPath Foundation open-source code
signing program. Releases remain unsigned until the application has been
accepted and the signing workflow described below has been activated.

If the application is accepted, the following acknowledgement will apply:

> Free code signing provided by SignPath.io, certificate by SignPath Foundation.

This page will be updated with the certificate details and verification
instructions before the first signed release is published.

## Scope

The signing policy covers first-party Windows artifacts built from this
repository:

- `JellyfinVlcBridge-<version>-Setup.exe`;
- `jellyfin-vlc-bridge.exe`;
- `jellyfin-vlc-bridge-control.exe`.

Third-party components and system libraries are not signed using the project's
certificate. The Chrome extension is distributed and reviewed separately by the
Chrome Web Store.

## Trusted build and release process

Only artifacts produced from the public
[`CrySer66/jellyfin-vlc-bridge`](https://github.com/CrySer66/jellyfin-vlc-bridge)
repository are eligible for signing.

1. Changes are proposed through a pull request.
2. The protected `main` branch requires the Windows build and test workflow to
   succeed.
3. A release tag must point to a commit on `main`.
4. Release artifacts are built on GitHub-hosted Windows runners.
5. Unsigned first-party artifacts are submitted to SignPath from the same
   GitHub Actions workflow using origin verification.
6. Each production signing request requires manual approval by the project
   approver.
7. Signed artifacts are verified before they are attached to the GitHub
   Release.

Locally built files and artifacts from untrusted forks are never eligible for a
production signature.

## Team roles

This is currently a solo-maintained open-source project.

| Role | Member | Responsibility |
|---|---|---|
| Committer | [CrySer66](https://github.com/CrySer66) | Maintains source code and build scripts |
| Reviewer | [CrySer66](https://github.com/CrySer66) | Reviews external contributions and release changes |
| Approver | [CrySer66](https://github.com/CrySer66) | Approves each production signing request |

Changes submitted by contributors who are not project committers must be
reviewed before merge. Multi-factor authentication is required for accounts
with repository or signing access.

## Privacy and security

The application communicates only with services needed for user-requested
features: the user's own Jellyfin server, the local VLC player, and GitHub for
update checks. Details are documented in the
[privacy policy](PRIVACY.md).

Security issues affecting the signing or release process must be reported using
[GitHub private vulnerability reporting](https://github.com/CrySer66/jellyfin-vlc-bridge/security/advisories/new),
not a public Issue.

---

# Politique de signature du code

Jellyfin VLC Bridge prépare actuellement sa candidature au programme gratuit de
signature open source de SignPath Foundation. Les versions restent non signées
tant que la candidature n'a pas été acceptée.

Après acceptation, seuls les exécutables produits depuis la branche protégée
`main`, testés sur un runner Windows hébergé par GitHub et approuvés
manuellement pourront recevoir la signature de production. Les fichiers
compilés localement et les artefacts provenant de forks non approuvés en sont
exclus.

Les rôles de responsable du code, de relecteur et d'approbateur sont
actuellement assurés par [CrySer66](https://github.com/CrySer66). Les détails
techniques et les informations du certificat seront ajoutés ici avant la
première version signée.
