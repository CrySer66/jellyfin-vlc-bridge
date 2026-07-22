# Historique des versions

## 1.9.1 — 2026-07-23

- prise en charge des collections Jellyfin (`BoxSet`) comme listes de lecture VLC ;
- démarrage au premier film en cours ou non vu, puis enchaînement des films suivants ;
- messages de lecture groupée rendus génériques pour les séries et les collections ;
- ajout d'un test de non-régression dédié aux collections.

## 1.9.0 — 2026-07-23

- validation et normalisation centralisées des adresses Jellyfin avant leur enregistrement ;
- écriture atomique de la configuration pour éviter un fichier incomplet après une interruption ;
- ajout d'un délai maximal aux appels Jellyfin afin qu'une coupure réseau ne bloque jamais VLC indéfiniment ;
- synchronisation de progression rendue tolérante aux erreurs temporaires, avec nouvelles tentatives pendant la lecture ;
- fermeture fiable du relais HTTP local et attente des requêtes encore actives ;
- téléchargement des mises à jour dans un fichier temporaire, avec contrôle de taille avant activation ;
- correction des correspondances SMB pour empêcher qu'un dossier voisin au nom similaire soit choisi ;
- rejet des anciennes configurations invalides par l'installateur au lieu de les conserver silencieusement ;
- durcissement du chargement des API Windows du Gestionnaire d'identifiants ;
- ajout de tests de non-régression pour les adresses, les délais réseau, les mises à jour incomplètes et les mappings SMB.

## Extension Chrome 1.4.0 — 2026-07-22

- ajout d'une fenêtre claire accessible depuis l'icône Chrome avec l'état du Bridge local ;
- ajout d'un accès direct au dépôt GitHub, aux téléchargements et à l'assistance ;
- détection réelle de l'absence de l'application Windows dans les pages Jellyfin ;
- remplacement de « Lire avec VLC » par « Application non installée » lorsque le Bridge ne répond pas ;
- redirection vers la dernière version GitHub au clic, sans nouvelle autorisation Chrome.

## 1.8.1 — 2026-07-22

- correction du diagnostic graphique après le passage de l'application principale en mode sans console ;
- capture explicite et fiable du résultat JSON de Jellyfin, VLC et de l'extension ;
- sérialisation des écritures simultanées du signal de présence de l'extension Chrome ;
- nettoyage automatique des fichiers temporaires abandonnés par un ancien signal interrompu ;
- ajout de tests de concurrence et du parcours de diagnostic sans fenêtre CMD.

## 1.8.0 — 2026-07-22

- suppression de la fenêtre CMD pendant la lecture des films, saisons et séries ;
- maintien de la communication native avec Chrome en arrière-plan ;
- publication de l'application Windows en fichier autonome incluant .NET 8 ;
- suppression du prérequis d'installation séparée de .NET Runtime ;
- réduction du paquet installé aux fichiers réellement nécessaires ;
- affichage de l'adresse Jellyfin réellement conservée pendant une mise à jour ;
- ajout d'une action confirmée pour changer de serveur et relancer Quick Connect ;
- maintien de la lecture si le fichier de diagnostic de l'extension est momentanément verrouillé ;
- ajout d'une vérification du sous-système Windows et du dialogue natif avec l'extension.

## 1.7.0 — 2026-07-21

- ajout des vérifications automatiques GitHub sous Windows pour chaque modification et Pull Request ;
- génération automatique du Setup et du ZIP lorsqu'un tag de version est publié ;
- ajout de formulaires GitHub guidés pour signaler un bug ou proposer une amélioration ;
- ajout du bouton **Aide et signaler un bug** dans le centre de contrôle ;
- ajout de la version détectée de VLC dans le diagnostic sans secret ;
- contrôle automatique de la cohérence des numéros de version avant publication ;
- maintien volontaire d'une prise en charge exclusivement Windows, seule plateforme actuellement testée.

## 1.6.1 — 2026-07-21

- détection fondée sur un contact réel avec l'extension, et non plus uniquement sur le registre Windows ;
- affichage distinct d'une intégration à réparer et d'une extension dont l'activité reste à confirmer ;
- préparation de l'extension 1.3.0 avec signal d'activité lorsque Jellyfin est ouvert ;
- conservation de la seule autorisation Chrome indispensable, `nativeMessaging` ;
- correction du service worker et création d'un dossier local stable pour le chargement développeur ;
- conservation intacte du paquet 1.2.0 déjà soumis au Chrome Web Store.

## 1.6.0 — 2026-07-21

- vérification automatique de la dernière Release GitHub officielle ;
- affichage clair de l'état « à jour » ou de la nouvelle version disponible ;
- téléchargement sécurisé limité au dépôt `cryser66/jellyfin-vlc-bridge` ;
- lancement guidé du nouvel installateur depuis le centre de contrôle ;
- conservation automatique de Quick Connect et des réglages pendant la mise à jour ;
- fonctionnement non bloquant tant que le dépôt principal n'est pas encore public.

## 1.5.1 — 2026-07-21

- suppression de la fenêtre CMD lors de l'ouverture du centre de contrôle ;
- explications simples pour choisir entre HTTP Direct Play et SMB ;
- réglages SMB avancés masqués lorsqu'ils ne sont pas utilisés ;
- libellés SMB reformulés avec un exemple concret ;
- boutons d'aide contextuelle pour le mode de lecture, VLC et les chemins réseau.

## 1.5.0 — 2026-07-21

- ajout d'un centre de contrôle graphique dans le menu Démarrer ;
- vérification claire de Jellyfin, VLC et de l'intégration Chrome/Edge ;
- bouton de réparation de la communication avec l'extension ;
- réglage du mode HTTP/SMB et du chemin VLC sans ligne de commande ;
- copie d'un diagnostic partageable qui ne contient ni jeton ni identifiant utilisateur ;
- remplacement de l'ancien raccourci de diagnostic en console par l'application graphique.

## 1.4.0 — 2026-07-21

- ajout de l'icône Jellyfin VLC Bridge au programme, à l'installateur et aux raccourcis Windows ;
- nouvelle présentation graphique de l'assistant d'installation ;
- ajout d'un bouton permettant de rouvrir la fiche Chrome Web Store avant de fermer l'assistant ;
- possibilité de rouvrir la fiche Chrome Web Store après avoir fermé le navigateur ;
- suppression des fichiers de débogage, des documents développeur et de la copie locale de l'extension dans le ZIP public ;
- réécriture de la documentation autour du parcours actuel Quick Connect + Chrome Web Store.

## 1.3.2 — 2026-07-21

- autorisation de l'identifiant officiel Chrome Web Store `hkjbodgdbjhignhlbecchiigcfigpidp` ;
- conservation de l'identifiant local uniquement pour le développement et les tests ;
- ouverture automatique de la fiche Chrome Web Store à la fin de l'installation ;
- ajout d'un guide public détaillant l'installation, la désinstallation, les données locales et le fonctionnement du Bridge.

## 1.3.1 — 2026-07-20

- remplacement du redémarrage de VLC entre les épisodes par une vraie liste de lecture VLC ;
- préparation de tous les flux via un unique relais HTTP local ;
- passage automatique au prochain épisode dans la même fenêtre VLC ;
- suivi du changement d’épisode dans la playlist pour conserver une synchronisation Jellyfin distincte ;
- journalisation du statut HTTP de chaque flux pour faciliter le diagnostic.

## 1.3.0 — 2026-07-20

- lecture directe depuis une fiche de série ou de saison ;
- sélection automatique du prochain épisode Jellyfin, avec reprise de la position enregistrée ;
- enchaînement automatique des épisodes suivants lorsqu’un épisode se termine ;
- arrêt de la file si VLC est fermé manuellement avant la fin ;
- synchronisation Jellyfin distincte et correcte pour chaque épisode ;
- lecture d’un épisode individuel étendue automatiquement aux épisodes suivants.

## 1.2.0 — 2026-07-20

- bouton « Lire avec VLC » intégré dans la barre d'actions des fiches Jellyfin ;
- apparence adaptée au thème Jellyfin, aux écrans étroits et à la navigation au clavier ;
- icône VLC vectorielle et états visuels pendant le lancement ;
- notification de confirmation après l'ouverture du lecteur ;
- affichage limité aux fiches possédant réellement une action de lecture ;
- repositionnement automatique lors de la navigation entre films et épisodes.

## 1.1.0 — 2026-07-20

- nouvel assistant d'installation graphique sans fenêtre CMD ;
- nouvelle désinstallation graphique depuis Windows et le menu Démarrer ;
- affichage intégré du code Quick Connect et de l'état d'autorisation ;
- suppression du raccourci Diagnostic sur le Bureau ;
- maintien du diagnostic dans le menu Démarrer ;
- mise à jour graphique conservant automatiquement la connexion existante.

## 1.0.0 — 2026-07-19

Première version stable validée sur deux PC Windows et plusieurs films et épisodes.

- lecture VLC par HTTP Direct Play ou partage SMB ;
- action « Lire avec VLC » dans Jellyfin Web ;
- Quick Connect avec jeton par appareil ;
- communication native Chrome/Edge sans confirmation répétée ;
- reprise et synchronisation de progression Jellyfin ;
- stockage du secret dans le Gestionnaire d'identifiants Windows ;
- installation, mise à jour et désinstallation conservant ou purgeant la connexion ;
- relais HTTP local authentifié sans jeton dans l'URL VLC ;
- diagnostics et journal local avec rotation.
