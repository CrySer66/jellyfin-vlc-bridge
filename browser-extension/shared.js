(() => {
  'use strict';

  const links = Object.freeze({
    repository: 'https://github.com/CrySer66/jellyfin-vlc-bridge',
    latestRelease: 'https://github.com/CrySer66/jellyfin-vlc-bridge/releases/latest',
    support: 'https://github.com/CrySer66/jellyfin-vlc-bridge/issues/new/choose'
  });

  function availabilityFromResult(result) {
    return result?.ok ? 'ready' : 'missing';
  }

  function buttonPresentation(state) {
    const presentations = {
      checking: { label: 'Vérification…', title: 'Vérification de Jellyfin VLC Bridge', disabled: true },
      loading: { label: 'Ouverture…', title: 'Ouverture du média dans VLC', disabled: true },
      success: { label: 'VLC lancé', title: 'Lecture lancée dans VLC', disabled: false },
      missing: { label: 'Application non installée', title: "Télécharger l'application Jellyfin VLC Bridge", disabled: false },
      ready: { label: 'Lire avec VLC', title: 'Lire le fichier original avec VLC', disabled: false }
    };

    return presentations[state] || presentations.checking;
  }

  const api = Object.freeze({ links, availabilityFromResult, buttonPresentation });
  globalThis.JellyfinVlcBridge = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})();
