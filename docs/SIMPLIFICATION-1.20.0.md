# Une utilisation plus simple — application 1.20.0 et extension 1.9.0

## Ce qui change au quotidien

L’accueil du Bridge propose la prochaine étape adaptée : connecter Jellyfin,
retrouver VLC, vérifier un serveur indisponible, réparer le lien avec le navigateur
ou ouvrir Jellyfin. Une connexion refusée par le serveur propose Quick Connect.
L’absence de contact récent avec l’extension invite d’abord à ouvrir Jellyfin.

Les réglages usuels restent automatiques. Le mode de lecture, l’emplacement de
VLC et les dossiers réseau sont regroupés dans **Options avancées**. Les réglages
déjà enregistrés sont conservés ; un mode SMB ou un chemin VLC personnalisé
laisse cette section ouverte pour rester visible.

L’extension indique si l’application répond et explique la prochaine étape. Elle
propose **Réessayer** en cas de problème temporaire. Elle n’affirme plus que
l’application manque pour toute erreur de communication. La vérification de
connexion expire après dix secondes, sans imposer ce délai à la préparation
d’une lecture. Le choix Reprendre/Recommencer est conservé lorsque l’étendue
de la lecture change.

Le README français et anglais présente les deux téléchargements, trois étapes
d’installation et une aide courte. Les instructions techniques restent dans les
guides liés. Le script de publication vérifie l’authentification avant de compiler
et limite la fusion au commit dont les tests ont réussi.

## Corrections de fiabilité

- Échec d’enregistrement d’une nouvelle connexion : restauration du jeton
  précédent lorsque l’erreur est interceptée. Ce mécanisme ne constitue pas une
  transaction résistante à une coupure du processus entre les deux écritures.
- Synchronisation désactivée dans la configuration : aucun rapport de lecture
  envoyé à Jellyfin et aucune interface HTTP VLC ouverte pour le suivi.
- Arrêt de VLC signalé à zéro : conservation de la dernière position utile du
  film. Le premier rapport attend une lecture active.
- Réponses de vérification arrivées dans le désordre : les anciennes réponses
  ne remplacent plus l’état de connexion le plus récent dans l’extension.
- Publication GitHub : un test .NET en échec ne peut plus être masqué par le
  succès du test JavaScript exécuté ensuite.

## Vérifications

Les tests couvrent les services du centre de contrôle, les choix de l’accueil,
les erreurs de sauvegarde de connexion, le suivi de lecture, les réponses HTTP
d’authentification et les comportements du popup et du bouton de lecture.
Les tests existants d’authentification Jellyfin, de playlists et de proxy Range/HEAD
restent conservés.

Les rendus WPF ont été inspectés et le popup a été vérifié dans un navigateur en
français et en anglais, avec une communication Chrome simulée. Les paquets sont
compilés puis vérifiés : ressources, versions, Native Messaging, installation et
désinstallation silencieuses isolées, retour arrière et empreintes.
La CI Windows teste aussi le cycle du Setup sur une machine sans installation
préexistante.

Ces vérifications utilisent des serveurs et lecteurs simulés. Elles ne remplacent
pas une lecture complète sur chaque version de Jellyfin ni un contrôle de tous
les environnements Windows. Aucune connexion réelle n’est changée par les aperçus.

Pour reproduire un aperçu du bureau après compilation :

```powershell
./jellyfin-vlc-bridge-control.exe --preview --scenario revoked --language fr
```

Scénarios disponibles : `ready`, `connect`, `credential`, `revoked`, `vlc`,
`vlc-settings`, `offline`, `repair`, `extension`. Les commandes `--validate-only`
et `--render-preview` restent disponibles pour les contrôles sans action.

## Deux publications distinctes

La publication Windows ne met pas à jour le Chrome Web Store. Le ZIP
`JellyfinVlcBridge-Extension-1.9.0-ChromeWebStore.zip` est prêt pour une soumission
sur la fiche existante. La version du Store demeure 1.8.1 tant que la nouvelle
soumission n’a pas été approuvée et publiée par Google.
