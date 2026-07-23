# Guide d'installation

## Prérequis

- Windows 10 ou Windows 11 en 64 bits ;
- VLC Media Player ;
- Google Chrome ;
- un serveur Jellyfin accessible depuis le PC ;
- Quick Connect activé dans Jellyfin.

L'environnement .NET nécessaire est déjà inclus dans l'application. Il n'y a rien d'autre à installer que VLC et l'extension Chrome.

## Installer le Bridge

1. Téléchargez `JellyfinVlcBridge-1.10.0-Setup.exe` depuis la dernière **Release GitHub**.
2. Lancez le fichier.
3. Saisissez l'adresse de Jellyfin, par exemple `http://192.168.1.25:8096`.
4. L'assistant affiche un code Quick Connect temporaire.
5. Dans Jellyfin, ouvrez **Paramètres → Quick Connect**, saisissez le code et confirmez.
6. Attendez le message **Installation terminée avec succès**.

Une réinstallation par-dessus une version existante affiche l'adresse Jellyfin actuelle et conserve automatiquement la connexion. Le champ est verrouillé pour éviter de saisir accidentellement une autre adresse.

Pour utiliser un autre serveur, cliquez sur **Changer de serveur Jellyfin**. Après confirmation, l'ancienne connexion est supprimée et l'assistant demande un nouveau code Quick Connect.

## Centre de contrôle

Ouvrez **Jellyfin VLC Bridge** depuis le menu Démarrer. La fenêtre indique immédiatement si Jellyfin, VLC et l'intégration Chrome/Edge sont prêts.

- **Réparer** réenregistre la communication locale avec l'extension ;
- **Réglages de lecture** permet de choisir HTTP Direct Play ou SMB et le chemin de VLC ;
- **Copier un diagnostic sans secret** prépare les versions de l'application et de VLC ainsi que les informations utiles, sans jeton ni identifiant utilisateur ;
- **Aide et signaler un bug** ouvre les guides et formulaires officiels du projet.

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
