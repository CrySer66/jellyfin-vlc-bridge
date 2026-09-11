# Installation et désinstallation 1.19.1

La version 1.19.1 complète le [centre de contrôle 1.19.0](DESKTOP-1.19.0.md).
L’installateur et le désinstallateur utilisent désormais WPF avec le même
dictionnaire `DesktopTheme.xaml` : barre latérale bleu nuit, fond clair,
cartes et boutons arrondis, icônes vectorielles, repères de focus clavier.
Le message d’erreur du lanceur Setup utilise également ce thème.

Le centre de contrôle reste un exécutable C# natif. Les opérations de
maintenance restent écrites en PowerShell ; leur interface WPF s’affiche sans
console. Les points d’entrée Windows lancent PowerShell en mode STA.
Le français, l’anglais et le choix automatique sont conservés.

## Mettre à jour les trois interfaces

Exécuter `JellyfinVlcBridge-1.19.1-Setup.exe`. Si la connexion existante est
valide, l’assistant la conserve. La mise à jour remplace aussi le script et les
ressources du désinstallateur référencé dans les applications Windows.
Il est inutile de désinstaller d’abord le Bridge.

Un ancien Setup déjà téléchargé garde son ancienne interface. Il faut ouvrir
le nouveau fichier 1.19.1 pour voir ce changement. L’extension Chrome ne change
pas dans cette version.

## Comportement conservé

- Installation initiale avec adresse du serveur et code Quick Connect.
- Mise à jour sans nouvelle autorisation si la connexion existante est valide.
- Verrouillage de maintenance et restauration de l’ancienne application en cas d’échec.
- Désinstallation avec conservation de la connexion sélectionnée par défaut,
  ou suppression des données locales après choix explicite.
- Installation et désinstallation silencieuses pour les outils de maintenance.

Le désinstallateur copie les ressources nécessaires dans son dossier temporaire
avant de retirer l’application. Il peut ainsi afficher la progression et le
résultat même après la suppression du dossier installé.

Si un retour arrière échoue parce que des fichiers sont verrouillés, le bouton
« Réessayer » reste désactivé et un message explique la situation. Les dossiers
de sauvegarde d’une ancienne transaction ne sont plus supprimés automatiquement
par le lancement suivant. Une installation réussie retire normalement sa propre
sauvegarde ; une sauvegarde conservée après échec peut donc occuper de l’espace.

## Vérification sans installation

Les contrôles locaux couvrent le chargement WPF des deux assistants en FR/EN,
le centre de contrôle natif et ses huit groupes de tests de services, les deux
groupes de tests de récupération de l’installateur, l’installation silencieuse,
le retour arrière, le verrou concurrent, et la désinstallation avec conservation
ou purge dans des dossiers isolés. Le dialogue natif Chrome et les métadonnées
du paquet sont également vérifiés. Les rendus des états d’accueil, mise à jour,
autorisation, succès et erreur ont été inspectés.

Ces essais n’exécutent pas le cycle d’installation/désinstallation sur le compte
utilisateur. L’essai réel de Quick Connect et du nouveau désinstallateur reste
à faire avant une publication publique.

Depuis le dépôt ou le ZIP extrait, les commandes suivantes construisent les
vraies fenêtres WPF avec des données d’exemple et quittent avant toute action
sur le Bridge installé :

```powershell
powershell.exe -NoProfile -STA -File .\installer\Installer-GUI.ps1 -ValidateOnly -Language fr
powershell.exe -NoProfile -STA -File .\installer\Desinstaller-GUI.ps1 -ValidateOnly -Language en
powershell.exe -NoProfile -STA -File .\installer\Installer-GUI.ps1 -RenderPreview .\work\installation.png -PreviewState authorize -Language fr
powershell.exe -NoProfile -STA -File .\installer\Desinstaller-GUI.ps1 -RenderPreview .\work\desinstallation.png -PreviewState choice -Language fr
```

Dans le ZIP, les scripts sont à la racine : retirer `installer\` des chemins.
Les écrans d’installation disponibles sont l’accueil (sans `-PreviewState`),
`update`, `authorize`, `success` et `error`. Ceux de désinstallation sont
`choice`, `progress`, `success` et `error`.

Les captures livrées sont des rendus du vrai XAML avec des données d’exemple.
Elles ne prouvent pas une autorisation Quick Connect sur un serveur réel ni
un essai sur plusieurs moniteurs. Cette préparation ne publie ni Release
GitHub ni nouvelle version sur le Chrome Web Store.
