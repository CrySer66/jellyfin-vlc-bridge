# Extension 1.8.1 — préparation de la soumission

La version 1.8.1 est préparée séparément de l’application Windows 1.18.1.
La publication GitHub ne met pas à jour la fiche Chrome Web Store et ne vaut
pas validation par Google. Aucune soumission à la boutique n’a été effectuée
pendant la préparation du 10 septembre 2026.

Le correctif d’authentification Jellyfin 12 appartient au Bridge Windows
1.18.1 : la lecture a été vérifiée avec l’extension 1.8.0 déjà installée.
L’extension 1.8.1 améliore les messages d’erreur et permet de réessayer la
préparation sans fermer la fenêtre.

## Paquet et fiche à utiliser

- Fiche existante : `hkjbodgdbjhignhlbecchiigcfigpidp`.
- Paquet : `outputs/JellyfinVlcBridge-Extension-1.8.1-ChromeWebStore.zip`.
- Le paquet `Local.zip` sert aux essais locaux ; le paquet `ChromeWebStore.zip`
  exclut le champ de développement `key`.
- Version du manifeste : `1.8.1`. Autorisation `nativeMessaging`, périmètre
  des pages Jellyfin et utilisation des données inchangés.

Les commandes de construction et de validation figurent dans le
[guide de développement](DEVELOPMENT.md#construire-lextension-chrome).
Après une modification du code, reconstruire le ZIP avant de le transmettre.

Dans le tableau de bord développeur, ouvrir cette fiche existante, importer
le nouveau paquet dans l’onglet **Package**, vérifier les métadonnées, puis
envoyer la mise à jour à l’examen. Le traitement par Google et la disponibilité
publique se vérifient séparément. Voir la
[procédure officielle de mise à jour](https://developer.chrome.com/docs/webstore/update).

## Texte français du correctif

La préparation de la lecture affiche désormais les erreurs de connexion,
d’autorisation ou de média indisponible avec une action adaptée. Le bouton
« Réessayer » permet de reprendre après correction du problème. Un échec
ne lance plus automatiquement VLC et n’ouvre plus la page de téléchargement
de l’application. Le lancement classique reste proposé aux anciens Bridge
sans aperçu. Aucune nouvelle autorisation Chrome n’est demandée.

Pour Jellyfin 12, installez également Jellyfin VLC Bridge 1.18.1. Le Bridge
utilise un format d’authentification commun à Jellyfin 10.x et 12 ; les limites
des essais réalisés sont décrites dans le [guide de compatibilité](COMPATIBILITY.md).

## Vérification avant transmission

Les tests Node et le contrôle des deux ZIP vérifient les messages bilingues,
la conservation des erreurs natives, le comportement prévu avec un ancien
Bridge, le choix du fichier et le manifeste. Ils ne remplacent pas un essai
du paquet 1.8.1 dans Chrome.

La fixture `tests/extension-fixture.html` permet notamment de vérifier
`?remember=true&error=authentication_required&retryOnce=true#/details?id=123` :
le premier aperçu échoue sans lecture ; « Réessayer » rétablit ensuite
les choix mémorisés et l’aperçu. Recharger les onglets Jellyfin après la mise
à jour de l’extension.
