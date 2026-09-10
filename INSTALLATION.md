# Guide d'installation

## Prérequis

- Windows 10 ou Windows 11 en 64 bits ;
- VLC Media Player ;
- Google Chrome ;
- un serveur Jellyfin accessible depuis le PC ;
- Quick Connect activé dans Jellyfin.

L'environnement .NET nécessaire est déjà inclus dans l'application. Il n'y a rien d'autre à installer que VLC et l'extension Chrome.

## Installer le Bridge

1. Téléchargez `JellyfinVlcBridge-<version>-Setup.exe` depuis la [dernière Release GitHub](https://github.com/CrySer66/jellyfin-vlc-bridge/releases/latest).
2. Lancez le fichier.
3. Saisissez l'adresse de Jellyfin, par exemple `http://192.168.1.25:8096`.
4. L'assistant affiche un code Quick Connect temporaire.
5. Dans Jellyfin, ouvrez **Paramètres → Quick Connect**, saisissez le code et confirmez.
6. Attendez le message **Installation terminée avec succès**.

Une réinstallation par-dessus une version existante affiche l'adresse Jellyfin actuelle et conserve automatiquement la connexion. Le champ est verrouillé pour éviter de saisir accidentellement une autre adresse.

Pour utiliser un autre serveur, cliquez sur **Changer de serveur Jellyfin**. Après confirmation, l'ancienne connexion est supprimée et l'assistant demande un nouveau code Quick Connect.

## Installer avec WinGet (facultatif)

La version 1.18.0 a été [acceptée dans le dépôt communautaire WinGet le 31 août 2026](https://github.com/microsoft/winget-pkgs/pull/413912). Lors de notre vérification du même jour, le catalogue actualisé ne la proposait pas encore. Il n'est pas nécessaire de désinstaller le Bridge ni de modifier votre configuration.

Dans PowerShell ou Terminal Windows, vérifiez d'abord la disponibilité, sans rien installer :

```powershell
winget source update --name winget
winget show --id CrySer66.JellyfinVlcBridge --exact --source winget
```

Si WinGet répond **Aucun package ne correspond aux critères sélectionnés**, réessayez plus tard ou utilisez l'installateur GitHub ci-dessus. Si la commande `winget` est introuvable, consultez le [guide Microsoft](https://learn.microsoft.com/windows/package-manager/winget/) ou utilisez l'installation classique. Ne désactivez pas les vérifications de sécurité et ne réinitialisez pas les sources pour contourner l'attente.

Lorsque la fiche est disponible, vous pouvez installer le Bridge avec :

```powershell
winget install --id CrySer66.JellyfinVlcBridge --exact --source winget --silent
```

Cette commande utilise le même installateur officiel hébergé sur GitHub. WinGet vérifie son empreinte et le manifeste déclare **VideoLAN.VLC** comme dépendance. VLC peut demander une autorisation administrateur s'il doit être installé ; le Bridge reste installé pour l'utilisateur courant. Lisez les éventuelles demandes d'accord affichées par WinGet.

Le mode silencieux n'ouvre ni navigateur ni fenêtre de connexion. Une fois l'installation terminée :

1. Ouvrez **Jellyfin VLC Bridge** depuis le menu Démarrer et connectez votre serveur avec **Quick Connect**.
2. Installez l'[extension Chrome officielle](https://chromewebstore.google.com/detail/hkjbodgdbjhignhlbecchiigcfigpidp) séparément.
3. Rechargez Jellyfin et essayez **Lire avec VLC** sur un film ou un épisode.

Pour une future mise à jour disponible dans WinGet, fermez le centre de contrôle et terminez les lectures en cours, puis utilisez :

```powershell
winget upgrade --id CrySer66.JellyfinVlcBridge --exact --source winget --silent
```

Le jeton Quick Connect et les réglages sont conservés. Les versions WinGet peuvent arriver après les Releases GitHub : **aucune mise à jour disponible** n'est donc pas forcément une erreur. Les mises à jour intégrées au centre de contrôle restent utilisables ; ne lancez pas les deux méthodes simultanément.

Pour désinstaller, utilisez **Paramètres Windows → Applications → Jellyfin VLC Bridge**, comme décrit plus bas. WinGet ne remplace ni la gestion de l'extension par Chrome, ni une signature Authenticode : il ne garantit pas la disparition de SmartScreen.

Références Microsoft : [installation](https://learn.microsoft.com/windows/package-manager/winget/install), [mise à jour](https://learn.microsoft.com/windows/package-manager/winget/upgrade).

## Centre de contrôle

Ouvrez **Jellyfin VLC Bridge** depuis le menu Démarrer. La fenêtre indique immédiatement si Jellyfin, VLC et l’intégration Chrome/Edge sont prêts.

Après l’installation, une icône Jellyfin VLC Bridge démarre discrètement près de
l’horloge Windows. Le bouton **Réduire** conserve la fenêtre dans la barre des
tâches, tandis que la croix **Fermer** la masque près de l’horloge. Un double-clic
sur l’icône rouvre le centre de contrôle ; son menu permet aussi
d’actualiser le diagnostic ou de quitter l’icône jusqu’à la prochaine ouverture
de session. La lecture depuis l’extension reste disponible même si cette icône
est quittée.

- **Réparer navigateur** réenregistre la communication locale avec l'extension ;
- **Réglages de lecture** permet de choisir HTTP Direct Play ou SMB et le chemin de VLC ;
- **Copier un diagnostic sans secret** prépare les versions de l'application et de VLC ainsi que les informations utiles, sans jeton ni identifiant utilisateur ;
- **Créer un paquet d’assistance** enregistre un ZIP contenant le diagnostic et les journaux récents expurgés, prêt à être joint à une Issue GitHub ;
- **Aide et signaler un bug** ouvre les guides et formulaires officiels du projet.

Lorsqu’un contrôle échoue, la carte concernée indique la cause probable et
l’action conseillée. Le paquet d’assistance retire automatiquement les jetons,
identifiants Jellyfin, adresses serveur et chemins Windows personnels.

## Installer l'extension Chrome

À la fin de l'installation, la fiche Chrome Web Store s'ouvre automatiquement. Cliquez sur **Ajouter à Chrome**, puis confirmez.

Si la page a été fermée, utilisez le bouton vert **Ouvrir Chrome Web Store** tant que l'assistant est encore affiché, ou ouvrez cette adresse :

https://chromewebstore.google.com/detail/hkjbodgdbjhignhlbecchiigcfigpidp

L'extension est disponible publiquement sur le Chrome Web Store et recevra automatiquement les mises à jour validées par Google.

Cliquez sur son icône dans la barre d'outils Chrome pour vérifier si l'application Windows est prête, télécharger le Bridge ou ouvrir le projet GitHub. Si l'application n'est pas installée, Jellyfin affiche **Application non installée** à la place de **Lire avec VLC** ; cliquez sur cette action pour ouvrir le téléchargement officiel.

## Première lecture

1. Rechargez la page Jellyfin.
2. Ouvrez un film, un épisode, une saison ou une série.
3. Cliquez sur **Lire avec VLC**.
4. Acceptez éventuellement le premier avertissement de Windows ou du pare-feu concernant VLC.

Pour une série ou une saison, le Bridge commence au prochain épisode Jellyfin et prépare les épisodes suivants dans la même liste de lecture VLC.

Le Bridge reste actif silencieusement pendant la lecture : aucune fenêtre CMD n'est nécessaire. Les informations de diagnostic restent accessibles depuis le Centre de contrôle.

## Mise à jour

Le centre de contrôle vérifie automatiquement la dernière Release du dépôt officiel `cryser66/jellyfin-vlc-bridge`. Lorsqu'une nouvelle version est disponible, cliquez sur **Installer**. Le Bridge télécharge l'installateur officiel, ferme sa fenêtre puis lance la mise à jour.

Les fichiers du programme sont remplacés, tandis que la configuration, le jeton Quick Connect et les réglages sont conservés.

L'extension est mise à jour automatiquement par le Chrome Web Store.

### Après une mise à jour vers Jellyfin 12

1. Installez le Bridge **1.18.1 ou ultérieur** par-dessus l’installation actuelle. La connexion et les réglages sont conservés.
2. Vérifiez la version de l’extension dans `chrome://extensions` : **1.8.1 ou ultérieure** affiche les erreurs de préparation dans la fenêtre de lecture. Sa diffusion sur le Chrome Web Store est indépendante de celle du Bridge.
3. Rechargez complètement les onglets Jellyfin avec **Ctrl+Maj+R**, puis ouvrez un film ou un épisode et cliquez sur **Lire avec VLC**.

Si la fenêtre signale encore une connexion refusée, ouvrez le centre de contrôle et actualisez le diagnostic. Ne refaites Quick Connect que si le diagnostic demande de reconnecter le serveur. Les contrôles des anciennes et nouvelles versions sont détaillés dans le [guide de compatibilité](docs/COMPATIBILITY.md#jellyfin-10x-et-12).

## Installation automatisée (avancé)

Le Setup accepte `/quiet` pour les gestionnaires de paquets et les déploiements
non interactifs :

```powershell
.\JellyfinVlcBridge-<version>-Setup.exe /quiet
```

Ce mode installe les fichiers et l'intégration Windows, mais n'ouvre ni Chrome,
ni le centre de contrôle, ni Quick Connect. Lors de la première utilisation,
ouvrez **Jellyfin VLC Bridge** depuis le menu Démarrer et connectez votre serveur
avec Quick Connect. Une connexion déjà présente est conservée pendant une mise
à jour.

Les alias `/silent`, `/S`, `--quiet` et `--silent` sont également acceptés. La
désinstallation non interactive utilise automatiquement la commande Windows
`QuietUninstallString` et conserve la connexion par défaut. L'option technique
`-Silent -Purge` du script de désinstallation supprime aussi la configuration et
le jeton.

## Désinstallation

Ouvrez :

```text
Paramètres Windows → Applications → Applications installées → Jellyfin VLC Bridge
```

Le désinstallateur propose :

- **Conserver la connexion** pour une future réinstallation ;
- **Tout effacer** pour supprimer également la configuration et le jeton Jellyfin.

Chrome gère l'extension séparément. Pour la retirer, ouvrez `chrome://extensions`.

## Ce qui est ajouté sur Windows

Programme :

```text
%LOCALAPPDATA%\JellyfinVlcBridge\App
```

Configuration non secrète :

```text
%LOCALAPPDATA%\JellyfinVlcBridge\config.json
```

Le jeton Quick Connect est conservé dans le Gestionnaire d'identifiants Windows. Il n'est pas enregistré dans l'extension, le dépôt GitHub ou le fichier de configuration.

Intégrations créées pour l'utilisateur Windows actuel :

```text
HKCU\Software\Google\Chrome\NativeMessagingHosts\local.jellyfin_vlc_bridge
HKCU\Software\Microsoft\Edge\NativeMessagingHosts\local.jellyfin_vlc_bridge
HKCU\Software\Classes\jellyfin-vlc
HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\JellyfinVlcBridge
HKCU\Software\Microsoft\Windows\CurrentVersion\Run\JellyfinVlcBridge
```

Le menu Démarrer contient uniquement le centre de contrôle et la désinstallation. Aucun raccourci n'est ajouté sur le Bureau.

## Dépannage rapide

### Le bouton n'apparaît pas

- vérifiez que l'extension est installée et activée dans `chrome://extensions` ;
- rechargez complètement Jellyfin ;
- ouvrez une fiche possédant réellement une action de lecture.

### Le bouton apparaît, mais VLC ne démarre pas

- vérifiez que VLC est installé ;
- ouvrez **Jellyfin VLC Bridge** depuis le menu Démarrer ;
- cliquez sur **Réparer**, puis sur **Actualiser**.

### Quick Connect ne fonctionne pas

- vérifiez l'adresse du serveur ;
- activez Quick Connect dans l'administration Jellyfin ;
- vérifiez que le PC peut ouvrir Jellyfin dans son navigateur.

### L'antivirus ou SmartScreen affiche un avertissement

Le projet est public, mais l'installateur n'est pas encore signé avec un certificat commercial. Téléchargez-le uniquement depuis la page Releases officielle du dépôt.
