# Code signing and release provenance

## Current status

Jellyfin VLC Bridge Windows executables are currently **unsigned**. They do not
contain an Authenticode certificate, and Windows SmartScreen may display a
reputation warning.

The project's first application to SignPath Foundation's open-source signing
program was not accepted because the project does not yet have enough public
visibility and reputation. The project may apply again after its user base and
public track record have grown. No SignPath signature or endorsement is claimed.

SmartScreen uses reputation signals in addition to signatures. An unsigned file
can therefore trigger a warning when its hash is new. The project never asks
users to disable SmartScreen or antivirus protection. See
[Microsoft's SmartScreen documentation](https://learn.microsoft.com/windows/apps/package-and-deploy/smartscreen-reputation)
for details.

## How releases are verified today

Starting with version 1.18.0, releases provide two complementary checks:

- `SHA256SUMS.txt`, containing the SHA-256 digest of the installer and Windows
  archive, for an integrity comparison with the value published in the same
  Release;
- GitHub artifact attestations, confirming that each binary was produced for
  this public repository by its release workflow.

The Control Center also checks the installer digest returned by GitHub before
executing a downloaded update. A missing or mismatched digest blocks automatic
installation.

Detailed commands and their limitations are documented in the
[download verification guide](docs/VERIFY_DOWNLOADS.md). A GitHub attestation
proves build provenance; it is not an Authenticode signature, does not establish
publisher reputation in Windows, and does not remove SmartScreen warnings.

## Scope

This policy covers first-party Windows artifacts built from this repository:

- `JellyfinVlcBridge-<version>-Setup.exe`;
- `JellyfinVlcBridge-<version>-win-x64.zip`;
- the first-party executables contained in those packages.

Third-party components and system libraries are outside the project's signing
scope. The Chrome extension is distributed and reviewed separately by the
Chrome Web Store.

## Build and release process

Only artifacts produced for the public
[`CrySer66/jellyfin-vlc-bridge`](https://github.com/CrySer66/jellyfin-vlc-bridge)
repository are eligible for publication.

1. Changes are proposed through a pull request.
2. The protected `main` branch requires the Windows build and test workflow to
   succeed.
3. A release tag must point to a commit on `main`.
4. Release artifacts are built on GitHub-hosted Windows runners.
5. SHA-256 digests and GitHub artifact attestations are generated for the
   Windows downloads.
6. The downloads are attached to a new GitHub Release. An existing release is
   never overwritten; a correction requires a new version number.

Third-party GitHub Actions used by the build and release workflows are pinned
to full commit hashes. Dependabot can propose reviewed updates to those hashes.

Locally built files and artifacts from untrusted forks are never published as
official project downloads.

If Authenticode signing is activated in the future, its certificate identity,
trusted-build integration and approval rules will be documented here before the
first signed release is published.

## Team roles

This is currently a solo-maintained open-source project.

| Role | Member | Responsibility |
|---|---|---|
| Committer | [CrySer66](https://github.com/CrySer66) | Maintains source code and build scripts |
| Reviewer | [CrySer66](https://github.com/CrySer66) | Reviews external contributions and release changes |
| Approver | [CrySer66](https://github.com/CrySer66) | Approves production releases |

Changes submitted by contributors who are not project committers must be
reviewed before merge. Multi-factor authentication is required for accounts
with repository or future signing access.

## Privacy and security

The application communicates only with services needed for user-requested
features: the user's own Jellyfin server, the local VLC player, and GitHub for
update checks. Details are documented in the [privacy policy](PRIVACY.md).

Security issues affecting the build, provenance or release process must be
reported using
[GitHub private vulnerability reporting](https://github.com/CrySer66/jellyfin-vlc-bridge/security/advisories/new),
not a public Issue.

---

# Signature du code et provenance des versions

## État actuel

Les exécutables Windows de Jellyfin VLC Bridge sont actuellement **non signés**.
Ils ne contiennent pas de certificat Authenticode et Windows SmartScreen peut
afficher un avertissement de réputation.

La première candidature du projet au programme open source de SignPath
Foundation n'a pas été acceptée, car le projet ne dispose pas encore d'assez de
visibilité et de réputation publiques. Une nouvelle candidature pourra être
envisagée lorsque son usage et son historique public auront progressé. Le projet
ne revendique donc aucune signature ni approbation de SignPath.

SmartScreen tient compte de plusieurs signaux de réputation en plus de la
signature. Un fichier non signé dont l'empreinte est nouvelle peut ainsi
déclencher un avertissement. Le projet ne demande jamais de désactiver
SmartScreen ou l'antivirus.

## Vérification actuelle des versions

À partir de la version 1.18.0, les versions fournissent deux contrôles
complémentaires :

- `SHA256SUMS.txt`, avec l'empreinte SHA-256 de l'installateur et de l'archive
  Windows, pour comparer leur intégrité avec la valeur publiée dans la même
  Release ;
- des attestations GitHub, qui confirment que chaque binaire a été produit pour
  ce dépôt public par son workflow de publication.

Le centre de contrôle vérifie aussi l'empreinte de l'installateur renvoyée par
GitHub avant d'exécuter une mise à jour téléchargée. Une empreinte absente ou
différente bloque l'installation automatique.

Le [guide de vérification des téléchargements](docs/VERIFY_DOWNLOADS.md) donne
les commandes et explique leurs limites. Une attestation GitHub prouve la
provenance de la compilation ; ce n'est pas une signature Authenticode, elle ne
crée pas de réputation d'éditeur Windows et ne supprime pas SmartScreen.

## Périmètre

Cette politique couvre les fichiers Windows produits par le projet :

- `JellyfinVlcBridge-<version>-Setup.exe` ;
- `JellyfinVlcBridge-<version>-win-x64.zip` ;
- les exécutables du projet contenus dans ces paquets.

Les composants tiers et bibliothèques système sont hors du périmètre de
signature du projet. L'extension Chrome est distribuée et examinée séparément
par le Chrome Web Store.

## Processus de publication

Seuls les fichiers produits pour le dépôt public
[`CrySer66/jellyfin-vlc-bridge`](https://github.com/CrySer66/jellyfin-vlc-bridge)
peuvent être publiés comme téléchargements officiels :

1. les changements passent par une pull request ;
2. la branche protégée `main` exige la réussite des contrôles Windows ;
3. le tag de version pointe vers un commit de `main` ;
4. GitHub Actions construit et teste les fichiers sur un runner Windows ;
5. le workflow génère les empreintes et attestations ;
6. les téléchargements sont joints à une nouvelle Release GitHub. Une
   Release existante n'est jamais écrasée : une correction impose un nouveau
   numéro de version.

Les actions GitHub tierces utilisées pour compiler et publier sont figées par
leur empreinte de commit complète. Dependabot peut proposer la mise à jour de
ces empreintes, qui doit ensuite être relue.

Les fichiers compilés localement et les artefacts de forks non approuvés ne sont
jamais publiés comme versions officielles. Si une signature Authenticode est
activée plus tard, l'identité du certificat et le processus d'approbation seront
ajoutés ici avant la première version signée.

## Rôles

Les rôles de responsable du code, de relecteur et d'approbateur sont
actuellement assurés par [CrySer66](https://github.com/CrySer66).
L'authentification multifacteur est obligatoire pour les comptes ayant accès au
dépôt ou à une future solution de signature.

Les vulnérabilités touchant la construction, la provenance ou la publication
doivent être transmises avec le
[signalement privé GitHub](https://github.com/CrySer66/jellyfin-vlc-bridge/security/advisories/new),
et non dans une Issue publique.
