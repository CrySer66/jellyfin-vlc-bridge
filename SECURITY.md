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
