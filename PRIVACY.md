# Politique de confidentialité — Jellyfin VLC Bridge

Dernière mise à jour : 23 juillet 2026

## Résumé

Jellyfin VLC Bridge traite uniquement les informations nécessaires à son fonctionnement sur l'appareil de l'utilisateur. Le développeur ne collecte, ne conserve, ne vend et ne partage aucune donnée personnelle.

## Informations traitées localement

Lorsque l'utilisateur consulte une fiche vidéo Jellyfin, l'extension examine l'adresse de la page et la présence des commandes de lecture afin d'afficher le bouton « Lire avec VLC ». Après un clic explicite, elle transmet l'identifiant technique du média et les choix de lecture au programme Jellyfin VLC Bridge installé sur le même ordinateur, grâce à la messagerie native de Chrome. Le programme renvoie localement les titres, durées et positions de reprise nécessaires à l'aperçu de la liste de lecture.

Si l'utilisateur active explicitement l'option « Retenir ces choix », l'application compagnon enregistre uniquement, sur cet ordinateur, le choix entre reprise et redémarrage ainsi que l'étendue préférée pour chaque type de contenu. Ces préférences ne contiennent ni jeton Jellyfin, ni historique de lecture, ni titre de média, et ne sont pas transmises au développeur.

Ces opérations peuvent relever des catégories « activité de navigation Web » et « contenu du site Web » dans les déclarations du Chrome Web Store. Elles sont limitées à la page Jellyfin en cours, restent locales et servent exclusivement à la fonctionnalité demandée par l'utilisateur.

## Communication avec Jellyfin

L'application compagnon communique avec le serveur Jellyfin choisi et configuré par l'utilisateur afin d'obtenir le flux du média et de synchroniser la progression. Ce serveur n'est ni fourni ni contrôlé par le développeur de l'extension. Les informations de connexion sont gérées séparément par l'application locale.

## Absence de collecte par le développeur

L'extension ne contient aucun système publicitaire, outil d'analyse, traceur ou service de télémétrie. Elle n'envoie aucune information au développeur et ne transfère aucune donnée à un service publicitaire ou à un autre tiers. Elle ne vend aucune donnée et ne les utilise pas pour établir un profil, déterminer une solvabilité ou proposer de la publicité.

## Conservation et suppression

L'extension ne conserve pas d'historique de navigation ni de copie du contenu Jellyfin. Les informations affichées dans l'aperçu restent en mémoire uniquement pendant l'ouverture de la fenêtre de lecture. Sa suppression arrête immédiatement son accès aux pages Jellyfin. Les préférences facultatives et les autres informations enregistrées par l'application compagnon peuvent être supprimées en choisissant la désinstallation complète de Jellyfin VLC Bridge.

## Modifications

Cette politique sera mise à jour si le fonctionnement de l'extension ou son utilisation des données change.
