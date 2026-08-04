# Politique de sécurité

[English version](#security-policy)

## Versions prises en charge

Seule la dernière version publiée de Jellyfin VLC Bridge reçoit les correctifs de
sécurité. Avant de signaler un problème, vérifiez qu'il existe encore avec la
[dernière Release](https://github.com/CrySer66/jellyfin-vlc-bridge/releases/latest).

## Signaler une vulnérabilité

Ne créez pas d'Issue publique si le problème peut exposer un jeton Jellyfin,
contourner les permissions locales, exécuter une commande ou rendre le relais HTTP
accessible depuis le réseau.

Utilisez plutôt le
[signalement privé GitHub](https://github.com/CrySer66/jellyfin-vlc-bridge/security/advisories/new).
Indiquez :

- la version du Bridge et de l'extension ;
- les conditions nécessaires pour reproduire le problème ;
- son impact possible ;
- une proposition de correction, si vous en avez une.

Ne joignez jamais un vrai jeton, mot de passe ou fichier du Gestionnaire
d'identifiants Windows. Un accusé de réception sera donné dès que possible, puis le
correctif sera préparé avant toute divulgation publique.

## Vérifier un téléchargement

Les exécutables Windows sont actuellement non signés. Téléchargez-les uniquement
depuis les [Releases officielles](https://github.com/CrySer66/jellyfin-vlc-bridge/releases)
et vérifiez leur empreinte SHA-256 ou leur attestation GitHub avant de décider
quoi faire face à un avertissement SmartScreen. Le
[guide de vérification](docs/VERIFY_DOWNLOADS.md) fournit les commandes et
explique ce que chaque contrôle garantit.

Les règles protégeant la construction, la provenance et une future signature
des exécutables sont décrites dans la [politique de signature du code](CODE_SIGNING.md).

---

# Security policy

## Supported versions

Only the latest published version of Jellyfin VLC Bridge receives security fixes.
Before reporting a problem, confirm that it still exists in the
[latest Release](https://github.com/CrySer66/jellyfin-vlc-bridge/releases/latest).

## Reporting a vulnerability

Do not open a public Issue if the problem could expose a Jellyfin token, bypass
local permissions, execute a command, or make the local HTTP relay reachable from
the network.

Use
[GitHub private vulnerability reporting](https://github.com/CrySer66/jellyfin-vlc-bridge/security/advisories/new)
instead. Include the affected Bridge and extension versions, reproduction
conditions, possible impact and, when available, a suggested fix.

Never include a real token, password or Windows Credential Manager export. The
report will be acknowledged as soon as possible and a fix will be prepared before
public disclosure.

## Verifying a download

Windows executables are currently unsigned. Download them only from the
[official Releases](https://github.com/CrySer66/jellyfin-vlc-bridge/releases)
and verify their SHA-256 digest or GitHub attestation before deciding how to
respond to a SmartScreen warning. The
[download verification guide](docs/VERIFY_DOWNLOADS.md) provides the commands
and explains what each check guarantees.

The controls protecting builds, provenance and any future executable signature
are documented in the [code-signing policy](CODE_SIGNING.md).
