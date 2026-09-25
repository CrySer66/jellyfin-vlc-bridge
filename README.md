<p align="center">
  <img src="browser-extension/icons/icon128.png" width="96" alt="Icône Jellyfin VLC Bridge">
</p>

<h1 align="center">Jellyfin VLC Bridge</h1>

<p align="center">Vos films et séries Jellyfin dans VLC, en un clic.</p>

<p align="center">
  <a href="https://github.com/CrySer66/jellyfin-vlc-bridge/releases/latest"><strong>1. Télécharger l’application Windows</strong></a>
  ·
  <a href="https://chromewebstore.google.com/detail/hkjbodgdbjhignhlbecchiigcfigpidp"><strong>2. Ajouter l’extension Chrome</strong></a>
</p>

<p align="center"><a href="README.en.md">English</a></p>

Jellyfin VLC Bridge ajoute le bouton **Lire avec VLC** dans votre navigateur. Vous choisissez un film ou une série sur Jellyfin, puis regardez la vidéo dans VLC sur votre PC. Votre progression est enregistrée dans Jellyfin.

**Il vous faut :** Windows 10 ou 11 en 64 bits, [VLC](https://www.videolan.org/vlc/), Google Chrome et un serveur Jellyfin auquel vous avez accès.

<p align="center">
  <img src="assets/preview-jellyfin-vlc-bridge.png" width="820" alt="Choisissez un média dans Jellyfin et regardez-le dans VLC sur votre PC">
</p>

## Pour commencer

1. **Installez l’application Windows.** Sur la page de téléchargement ci-dessus, ouvrez le fichier qui se termine par **`-Setup.exe`** et suivez l’assistant.
2. **Connectez Jellyfin.** Saisissez l’adresse de votre serveur. L’assistant affiche un code à autoriser dans **Jellyfin → Paramètres → Quick Connect**.
3. **Ajoutez l’extension Chrome.** Utilisez le second lien ci-dessus, rechargez Jellyfin, ouvrez un film ou un épisode et cliquez sur **Lire avec VLC**.

L’application et l’extension sont toutes les deux nécessaires. L’installation du Bridge ne demande pas de droits administrateur. Une mise à jour conserve votre connexion et vos réglages.

## Pendant la lecture

- Reprenez là où vous en étiez, ou repartez du début.
- Retrouvez votre progression et vos épisodes vus dans Jellyfin.
- Enchaînez les épisodes d’une saison ou les films d’une collection.
- Choisissez la version du média, par exemple 1080p ou 4K, lorsqu’elle existe.

L’application et l’extension sont disponibles en français et en anglais. Les pistes audio et les sous-titres se choisissent dans VLC.

## Besoin d’aide ?

Ouvrez **Jellyfin VLC Bridge** depuis le menu Démarrer : l’application vérifie votre connexion et vous indique quoi faire si la lecture ne démarre pas.

Consultez le [guide d’installation et de dépannage](INSTALLATION.md). Si Windows affiche SmartScreen, lisez le [guide de vérification du téléchargement](docs/VERIFY_DOWNLOADS.md) : l’application ne possède pas encore de signature Windows.

Pour signaler un problème, utilisez [le formulaire d’assistance](https://github.com/CrySer66/jellyfin-vlc-bridge/issues/new/choose).

## Pour aller plus loin

- [Compatibilité avec Jellyfin](docs/COMPATIBILITY.md) · [Historique des versions](CHANGELOG.md)
- [Vie privée](PRIVACY.md) · [Sécurité](SECURITY.md)
- [Développement](docs/DEVELOPMENT.md) · [Contribuer](CONTRIBUTING.md) · [Distribution](docs/DISTRIBUTION.md)

Sans publicité ni télémétrie. Le projet est indépendant de Jellyfin, VideoLAN, Google et Microsoft, et distribué sous [licence MIT](LICENSE).
