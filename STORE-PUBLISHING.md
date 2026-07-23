# Publication de Jellyfin VLC Bridge sur le Chrome Web Store

## Point important avant la publication

L'extension appelle une application installée sur le PC grâce à la messagerie native de Chrome. Le Bridge Windows doit autoriser précisément l'identifiant attribué à l'extension par la boutique ; les caractères génériques ne sont pas permis.

L'identifiant officiel attribué par le Chrome Web Store est `hkjbodgdbjhignhlbecchiigcfigpidp`. Le Bridge 1.4.0 et les versions suivantes l'autorisent dans le manifeste de messagerie native. L'identifiant de développement `hpbbmehpokomkjfnemlbdlalbmckmkld` reste également autorisé pour les tests locaux à partir des sources.

Le paquet destiné à la boutique ne contient volontairement pas le champ `key`, car le Chrome Web Store le refuse et conserve lui-même l'identifiant officiel de l'élément existant.

## État de la publication

La version 1.4.0 a été acceptée par Google et l'extension est disponible publiquement sous l'identifiant `hkjbodgdbjhignhlbecchiigcfigpidp`.

La version 1.5.0 est la mise à jour actuellement soumise à Google. Elle ajoute le choix de reprise, l'étendue des séries et collections ainsi qu'un aperçu local de la playlist, sans demander de nouvelle autorisation Chrome.

La version 1.6.0 est préparée localement pour l'étape suivante. Elle ajoute l'option facultative « Retenir ces choix », toujours sans nouvelle autorisation Chrome. Elle ne doit être envoyée qu'après la fin de l'examen de la version 1.5.0 et la mise à disposition de l'application Windows 1.11.0.

## Envoyer une mise à jour

1. Ouvrir l'élément existant dans le Chrome Web Store Developer Dashboard.
2. Pour la prochaine étape, importer `JellyfinVlcBridge-Extension-1.6.0-ChromeWebStore.zip` dans **Package**.
3. Vérifier que la version affichée est `1.6.0` et que seule l'autorisation `nativeMessaging` est demandée.
4. Enregistrer le brouillon, puis choisir **Envoyer pour examen**.
5. Après validation, tester une installation depuis la fiche publique. Chrome met ensuite automatiquement les utilisateurs à jour.

## Texte conseillé pour la fiche

### Résumé court

Ajoute « Lire avec VLC » aux fiches Jellyfin, permet de préparer la playlist et transmet la lecture au Bridge VLC installé sur votre ordinateur.

### Objectif unique

Permettre à l'utilisateur de choisir et prévisualiser les médias Jellyfin à lancer dans VLC, puis de synchroniser localement leur progression avec son propre serveur Jellyfin.

### Justification de `nativeMessaging`

Cette permission est nécessaire pour échanger localement l'identifiant du média, l'aperçu de la playlist et les choix de lecture avec le programme Jellyfin VLC Bridge installé sur l'ordinateur. L'extension ne peut pas démarrer VLC directement depuis la page Web sans cette communication native.

### Données

L'extension lit l'identifiant technique du média affiché dans l'URL Jellyfin. Cet identifiant et les choix de lecture sont transmis au Bridge installé sur le même ordinateur. Le Bridge renvoie localement les titres, durées et positions de reprise nécessaires à l'aperçu, sans les conserver dans l'extension. Aucune donnée n'est envoyée au développeur, à un service publicitaire ou à un serveur tiers.

## Éléments graphiques à fournir

- l'icône de l'extension est déjà incluse dans le ZIP ;
- ajouter au moins une capture claire montrant le bouton dans une fiche Jellyfin ;
- masquer toute adresse locale, nom d'utilisateur ou information privée visible sur la capture ;
- utiliser une description fidèle, sans promettre que VLC fonctionne sans le Bridge local.

## Après publication

Chaque mise à jour doit utiliser le même élément du tableau de bord, conserver tous les fichiers dans le ZIP et augmenter la version dans `manifest.json`. Les utilisateurs recevront ensuite automatiquement les versions validées par Google.

L'installateur Windows 1.11.0 ouvre directement la fiche officielle `https://chromewebstore.google.com/detail/hkjbodgdbjhignhlbecchiigcfigpidp`. Les sources complètes de l'extension restent dans le dépôt GitHub et dans son propre ZIP Chrome Web Store ; elles ne sont plus dupliquées dans le paquet Windows.
