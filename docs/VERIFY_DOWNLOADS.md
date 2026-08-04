# Vérifier un téléchargement / Verify a download

Ce guide permet de vérifier qu'un installateur ou un ZIP Jellyfin VLC Bridge est
identique au fichier publié par le projet et qu'il provient du workflow GitHub
officiel. Il ne remplace ni l'antivirus ni la prudence habituelle.

[English instructions](#english-instructions)

## Instructions en français

### 1. Utiliser la source officielle

Téléchargez uniquement les fichiers associés à la version souhaitée depuis :

https://github.com/CrySer66/jellyfin-vlc-bridge/releases

Pour une installation Windows normale, choisissez
`JellyfinVlcBridge-<version>-Setup.exe`. Le fichier `win-x64.zip` est l'archive
autonome destinée aux installations manuelles.

Dans les commandes suivantes, remplacez `1.18.0` par la version réellement
téléchargée :

```powershell
$version = '1.18.0'
```

### 2. Comparer l'empreinte SHA-256

Téléchargez aussi `SHA256SUMS.txt`, puis ouvrez PowerShell dans le dossier des
téléchargements :

```powershell
Get-FileHash -Algorithm SHA256 ".\JellyfinVlcBridge-$version-Setup.exe"
Get-Content .\SHA256SUMS.txt
```

Les deux suites de 64 caractères correspondant à l'installateur doivent être
strictement identiques. Faites la même vérification avec le ZIP si vous
l'utilisez. Une différence signifie que le fichier ne doit pas être exécuté.

### 3. Vérifier l'attestation GitHub

Avec une version récente de [GitHub CLI](https://cli.github.com/) :

```powershell
gh attestation verify ".\JellyfinVlcBridge-$version-Setup.exe" --repo CrySer66/jellyfin-vlc-bridge --signer-workflow CrySer66/jellyfin-vlc-bridge/.github/workflows/release.yml
```

Pour le ZIP :

```powershell
gh attestation verify ".\JellyfinVlcBridge-$version-win-x64.zip" --repo CrySer66/jellyfin-vlc-bridge --signer-workflow CrySer66/jellyfin-vlc-bridge/.github/workflows/release.yml
```

La commande doit confirmer une attestation provenant du dépôt
`CrySer66/jellyfin-vlc-bridge` et du workflow `release.yml`. GitHub CLI peut
demander une connexion préalable avec `gh auth login`. Les versions antérieures
à la 1.18.0 ne possèdent pas forcément d'attestation ni de fichier
`SHA256SUMS.txt` ; privilégiez la dernière version.

### Comprendre SmartScreen

Les exécutables actuels ne possèdent pas de signature Authenticode. Windows peut
donc afficher un avertissement SmartScreen malgré une empreinte et une
attestation valides. Ces contrôles confirment l'intégrité et la provenance du
fichier, mais ils ne constituent pas une signature d'éditeur Windows et ne
garantissent pas à eux seuls l'absence de vulnérabilité.

Le projet ne demande pas de désactiver SmartScreen ou l'antivirus. Si la source,
l'empreinte ou l'attestation ne correspond pas, n'exécutez pas le fichier et
[signalez le problème de façon privée](https://github.com/CrySer66/jellyfin-vlc-bridge/security/advisories/new).

## English instructions

### 1. Use the official source

Download release files only from:

https://github.com/CrySer66/jellyfin-vlc-bridge/releases

For a normal Windows installation, choose
`JellyfinVlcBridge-<version>-Setup.exe`. The `win-x64.zip` file is the
self-contained archive for manual installations.

In the commands below, replace `1.18.0` with the version you actually
downloaded:

```powershell
$version = '1.18.0'
```

### 2. Compare the SHA-256 digest

Download `SHA256SUMS.txt` as well, then open PowerShell in your Downloads folder:

```powershell
Get-FileHash -Algorithm SHA256 ".\JellyfinVlcBridge-$version-Setup.exe"
Get-Content .\SHA256SUMS.txt
```

The two 64-character values for the installer must match exactly. Repeat the
check for the ZIP if you use it. Do not run a file whose digest does not match.

### 3. Verify the GitHub attestation

Using a recent version of [GitHub CLI](https://cli.github.com/):

```powershell
gh attestation verify ".\JellyfinVlcBridge-$version-Setup.exe" --repo CrySer66/jellyfin-vlc-bridge --signer-workflow CrySer66/jellyfin-vlc-bridge/.github/workflows/release.yml
```

For the ZIP:

```powershell
gh attestation verify ".\JellyfinVlcBridge-$version-win-x64.zip" --repo CrySer66/jellyfin-vlc-bridge --signer-workflow CrySer66/jellyfin-vlc-bridge/.github/workflows/release.yml
```

The command must confirm an attestation from the
`CrySer66/jellyfin-vlc-bridge` repository and the `release.yml` workflow.
GitHub CLI may first ask you to sign in with `gh auth login`. Versions earlier
than 1.18.0 may have neither an attestation nor `SHA256SUMS.txt`; prefer the
latest release.

### Understanding SmartScreen

Current executables have no Authenticode signature. Windows may therefore show
a SmartScreen warning even when the digest and attestation are valid. These
checks confirm file integrity and build provenance, but they are not a Windows
publisher signature and do not by themselves guarantee that software has no
vulnerabilities.

The project does not ask users to disable SmartScreen or antivirus protection.
If the source, digest or attestation does not match, do not run the file and
[report the problem privately](https://github.com/CrySer66/jellyfin-vlc-bridge/security/advisories/new).
