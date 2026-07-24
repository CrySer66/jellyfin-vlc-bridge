# Fiche Chrome Web Store — extension 1.6.0

Ce document contient les textes prêts à copier dans le tableau de bord du Chrome Web Store.

## Résumé issu du package

Lance films, épisodes et collections Jellyfin dans VLC, avec reprise et listes de lecture.

## Description

Jellyfin VLC Bridge ajoute l’action « Lire avec VLC » directement dans Jellyfin Web.

Conservez l’interface de votre médiathèque Jellyfin pour choisir un film, un épisode, une série ou une collection, puis confiez la lecture à VLC sur votre ordinateur.

Fonctionnalités principales :

• ouverture du fichier original dans VLC avec HTTP Direct Play ou un partage SMB configuré ;
• reprise à la dernière position connue ou redémarrage depuis le début ;
• préparation et aperçu des épisodes ou films qui seront lus ;
• enchaînement des séries et collections ;
• mémorisation facultative des choix de lecture ;
• synchronisation de la progression avec votre propre serveur Jellyfin ;
• fonctionnement local, sans publicité ni télémétrie.

L’application compagnon Jellyfin VLC Bridge pour Windows ainsi que VLC doivent être installés sur le même ordinateur. La première connexion au serveur Jellyfin s’effectue simplement avec Quick Connect.

L’extension communique uniquement avec l’application compagnon installée localement. Elle ne transmet aucune donnée au développeur, à un service publicitaire ou à un serveur tiers.

Projet indépendant, non affilié à Jellyfin, VideoLAN ou Google.

## Objectif unique

Ajouter à Jellyfin Web une action « Lire avec VLC » permettant à l’utilisateur de choisir le point de départ et les médias à lire, de les transmettre à l’application compagnon installée sur son ordinateur, puis de synchroniser localement la progression avec son propre serveur Jellyfin.

## Justification de `nativeMessaging`

`nativeMessaging` est indispensable pour communiquer, après une action explicite de l’utilisateur, avec l’application Jellyfin VLC Bridge installée sur le même ordinateur. L’extension lui transmet l’identifiant du média et les choix de lecture. L’application renvoie l’aperçu local, ouvre VLC et synchronise la progression. Cette communication reste sur l’appareil ; aucune donnée n’est envoyée au développeur ou à un serveur tiers.

## Justification de l’autorisation d’accès à l’hôte

Jellyfin est un logiciel auto-hébergé : chaque utilisateur peut y accéder par une adresse IP locale, un nom de domaine, HTTP ou HTTPS, avec éventuellement un chemin personnalisé. Une liste fixe de domaines ne peut donc pas être fournie. Le script est déclaré uniquement pour les URL pouvant contenir l’interface Jellyfin Web (`/web/`). Il vérifie ensuite que la page est compatible avant d’ajouter le bouton. Il ne collecte ni historique de navigation ni contenu provenant d’autres sites.

## Code distant

Sélectionner :

> Non, je n’utilise pas de code distant.

Tous les fichiers JavaScript exécutés sont inclus dans le package. Aucun script ou module exécutable n’est téléchargé à distance.

## Déclarations relatives aux données

Conserver les déclarations déjà acceptées par Google et cohérentes avec la politique de confidentialité :

- contenu du site Web, limité aux informations du média affiché ;
- activité de l’utilisateur, limitée au clic explicite et aux choix de lecture.

Ne pas déclarer :

- informations d’authentification : le jeton Jellyfin reste dans l’application Windows et n’est jamais accessible à l’extension ;
- historique Web : l’extension ne conserve pas de liste des pages visitées ;
- informations personnelles, financières, de santé, localisation ou communications.

Cocher les trois certifications obligatoires concernant l’absence de vente, d’usage sans rapport et d’usage pour la solvabilité.

## Liens

- page d’accueil : `https://github.com/CrySer66/jellyfin-vlc-bridge`
- assistance : `https://github.com/CrySer66/jellyfin-vlc-bridge/issues`
- confidentialité : `https://cryser66.github.io/jellyfin-vlc-bridge-privacy/`

## Visuels à importer

Le dossier `outputs/ChromeWebStore-Assets-1.6.0` contient :

1. `capture-01-film-1280x800.png` — fenêtre de préparation d’un film ;
2. `capture-02-collection-1280x800.png` — préparation d’une collection complète ;
3. `capture-03-fonctionnalites-1280x800.png` — présentation synthétique des deux usages ;
4. `promotion-petite-440x280.png` — petite image promotionnelle ;
5. `promotion-marquee-1400x560.png` — image promotionnelle en haut de la page.

Tous les fichiers sont des PNG 24 bits sans transparence et respectent les dimensions demandées par le Chrome Web Store.
