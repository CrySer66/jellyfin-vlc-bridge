# Contribuer à Jellyfin VLC Bridge

[English version](#contributing-to-jellyfin-vlc-bridge)

Merci de votre intérêt pour le projet. Les petites corrections documentées et
faciles à vérifier sont les bienvenues.

## Avant de commencer

- utilisez une [Issue](https://github.com/CrySer66/jellyfin-vlc-bridge/issues/new/choose)
  pour décrire un bug reproductible ou une amélioration importante ;
- ne publiez jamais de jeton Jellyfin, mot de passe, clé API, journal privé ou
  contenu du Gestionnaire d'identifiants Windows ;
- conservez la compatibilité Windows 10/11 x64 ;
- ne modifiez pas les permissions Chrome sans expliquer précisément leur nécessité.

## Vérifier une modification

Depuis la racine du projet :

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Publier-Mise-A-Jour-GitHub.ps1 -ValidateOnly
```

Cette commande vérifie les versions, analyse PowerShell et JavaScript, compile le
Bridge, exécute les tests et construit les paquets Windows sans rien publier.

## Pull Request

Une Pull Request doit expliquer :

- le problème résolu ;
- le comportement avant et après la modification ;
- les vérifications réalisées ;
- les éventuelles limites restantes.

Gardez la modification ciblée et mettez à jour la documentation ou les tests
correspondants. Toute Pull Request doit réussir les vérifications Windows.

---

# Contributing to Jellyfin VLC Bridge

Thank you for your interest in the project. Small, documented and verifiable
changes are welcome.

## Before starting

- use an [Issue](https://github.com/CrySer66/jellyfin-vlc-bridge/issues/new/choose)
  to describe a reproducible bug or a significant feature;
- never publish a Jellyfin token, password, API key, private log or Windows
  Credential Manager content;
- preserve Windows 10/11 x64 compatibility;
- do not add Chrome permissions without clearly explaining why they are required.

## Validating a change

Run this command from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Publier-Mise-A-Jour-GitHub.ps1 -ValidateOnly
```

It checks versions, PowerShell and JavaScript, builds the Bridge, runs the tests
and creates the Windows packages without publishing anything.

## Pull Requests

Explain the problem, the behavior before and after the change, the checks you ran
and any remaining limitation. Keep the change focused and update the related
documentation or tests. Every Pull Request must pass the Windows checks.
