# Centre de contrôle 1.19.0

La version 1.19.0 est préparée localement le 11 septembre 2026. Elle apporte
une nouvelle interface Windows et des corrections internes du Bridge. Elle
n’est pas encore publiée sur GitHub ; les téléchargements publics restent ceux
de la version 1.18.1. L’extension reste en version 1.8.1.

## Nouvelle interface

Le centre de contrôle devient une application native WPF, écrite en C# et
ciblant .NET Framework 4.8 sur Windows 10/11. Son affichage ne démarre plus
PowerShell. L’assistant d’installation et les autres assistants conservent
leurs scripts PowerShell.

La fenêtre propose une barre latérale bleu nuit, des cartes claires arrondies
et trois pages :

- **Vue d’ensemble** : état de Jellyfin, de VLC et de l’extension, accès au
  serveur et aux réglages de lecture ;
- **Réglages** : changement de serveur, choix HTTP Direct Play ou SMB, chemin
  de VLC et correspondance des dossiers réseau ;
- **Diagnostic** : réparation du navigateur, accès à l’extension, journaux,
  export d’assistance et recherche de mises à jour.

Les textes et icônes utilisent le rendu vectoriel WPF. La fenêtre est
redimensionnable, avec défilement vertical du contenu aux petites dimensions,
états de survol et repères de focus clavier. Le français, l’anglais et le
choix automatique de la langue sont conservés. Le XAML, les traductions et
l’icône sont embarqués dans l’exécutable.

Les appels au Bridge sont asynchrones pour laisser l’interface réagir pendant
une vérification. Le service de lancement lit simultanément les sorties des
processus enfants et gère leurs erreurs, leurs délais maximaux et leur
annulation. Ces changements évitent qu’une sortie volumineuse ou un processus
qui ne répond plus bloque indéfiniment l’interface.

## Corrections internes

| Déclencheur | Comportement corrigé |
|---|---|
| Un épisode choisi est absent de la liste d’épisodes renvoyée par Jellyfin. | La lecture conserve cet épisode au lieu de démarrer un autre épisode de la série. |
| L’utilisateur saute un élément ou revient en arrière dans la liste VLC ; VLC signale ensuite un arrêt avec une position à zéro. | La progression est associée à l’identité du média réellement lu et le rapport d’arrêt conserve sa dernière position utile. |
| Un export d’assistance contient un en-tête `Authorization: MediaBrowser`, alors que le jeton utilisé dans cet en-tête n’est plus disponible dans la configuration courante. | L’en-tête entier est masqué, y compris son jeton et son identifiant d’appareil. |
| La liste des correspondances SMB contient une entrée `null`. | La validation renvoie une erreur de configuration explicite. |
| Une configuration possède plusieurs correspondances SMB et les réglages sont enregistrés depuis le centre de contrôle. | Les correspondances secondaires sont conservées lorsque la première est modifiée. |

Ces changements conservent les corrections d’authentification Jellyfin 12
introduites en 1.18.1. Ils ne nécessitent pas de nouvelle autorisation pour
l’extension Chrome.

## Vérifications réalisées

La préparation a passé les **52 tests du Bridge** et les **8 groupes de tests
des services du centre de contrôle**. Les scénarios de suivi de lecture
utilisent des réponses Jellyfin et un VLC simulés, y compris un test du
parcours CLI qui vérifie l’association des rapports au média courant.

Le XAML a été chargé par le moteur WPF réel. Les pages ont été rendues en
français et en anglais, avec vérification des ressources et des contrôles
nommés. La mise en page a également été mesurée à la taille minimale de la
fenêtre pour vérifier le défilement vertical.

Les rendus à différentes échelles permettent d’inspecter la netteté et les
espacements. Ils ne constituent pas une validation sur plusieurs moniteurs
physiques. Les corrections de playlist n’ont pas encore fait l’objet d’un
nouvel essai de lecture avec un serveur Jellyfin et VLC réels pour cette
version. Les essais réels de la 1.18.1 ne remplacent pas cette vérification.

L’installateur et le ZIP 1.19.0 ont également passé les tests de paquet Windows,
dont installation silencieuse, retour à la version précédente après échec,
verrouillage concurrent, désinstallation avec conservation ou purge des données
dans des dossiers isolés, et dialogue natif Chrome. Les métadonnées et empreintes
SHA256 sont vérifiées. La version 1.19.0 n’a pas été installée sur le compte courant.

Le pilotage interactif a été tenté, mais l’outil n’a pas exposé de fenêtre
ciblable. Les captures fournies sont des rendus du vrai XAML WPF avec des données
d’exemple ; les clics réels, Quick Connect et la zone de notification restent à
vérifier avec cette interface avant une publication publique.

Références techniques : [présentation officielle de WPF](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/overview/)
et [gestion DPI Windows](https://learn.microsoft.com/en-us/windows/win32/hidpi/setting-the-default-dpi-awareness-for-a-process).

## Compiler et essayer sans modifier la connexion

Depuis la racine du dépôt :

```powershell
.\tools\Build-ControlCenter.ps1 -OutputDirectory .\work\desktop-preview
.\tools\Test-DesktopControl.ps1
.\work\desktop-preview\jellyfin-vlc-bridge-control.exe --preview --language fr
```

Le mode `--preview` affiche des données d’exemple. Il ne lit ni ne modifie la
connexion installée, ne crée pas d’icône de notification et n’exécute pas les
actions de lecture ou de maintenance. Il peut être ouvert à côté du Bridge
installé.

Pour enregistrer une image de l’interface :

```powershell
.\work\desktop-preview\jellyfin-vlc-bridge-control.exe --render-preview .\work\desktop-overview-fr.png --language fr --page overview --scale 1
.\work\desktop-preview\jellyfin-vlc-bridge-control.exe --render-preview .\work\desktop-settings-fr.png --language fr --page settings --scale 1.5
.\work\desktop-preview\jellyfin-vlc-bridge-control.exe --render-preview .\work\desktop-diagnostics-en.png --language en --page diagnostics --scale 2
```

Les pages disponibles sont `overview`, `settings` et `diagnostics`, les langues
`fr` et `en`, et les échelles de vérification `1`, `1.5` et `2`. Les fichiers
PNG sont écrits à l’emplacement demandé. Le mode de rendu applique les mêmes
protections que l’aperçu interactif.

Le [guide de développement](DEVELOPMENT.md) décrit la compilation du Setup et
du ZIP Windows. Construire ces fichiers ne publie aucune Release GitHub et
ne soumet pas l’extension au Chrome Web Store.
