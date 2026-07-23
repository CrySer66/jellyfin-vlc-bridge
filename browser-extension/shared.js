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
      reload: { label: 'Recharger Jellyfin', title: 'L’extension a été mise à jour : rechargez cette page', disabled: false },
      missing: { label: 'Application non installée', title: "Télécharger l'application Jellyfin VLC Bridge", disabled: false },
      ready: { label: 'Lire avec VLC', title: 'Lire le fichier original avec VLC', disabled: false }
    };

    return presentations[state] || presentations.checking;
  }

  function formatDuration(seconds) {
    const value = Math.max(0, Number(seconds) || 0);
    if (!value) return '';
    const totalMinutes = Math.max(1, Math.round(value / 60));
    const hours = Math.floor(totalMinutes / 60);
    const minutes = totalMinutes % 60;
    return hours
      ? `${hours} h${minutes ? ` ${minutes} min` : ''}`
      : `${minutes} min`;
  }

  function scopeChoices(itemType) {
    switch ((itemType || '').toLowerCase()) {
      case 'episode':
        return [
          { value: 'following', label: 'Cet épisode et les suivants' },
          { value: 'single', label: 'Cet épisode uniquement' }
        ];
      case 'series':
        return [
          { value: 'following', label: 'À partir du prochain épisode' },
          { value: 'all', label: 'Toute la série depuis le début' }
        ];
      case 'season':
        return [
          { value: 'following', label: 'À partir du prochain épisode' },
          { value: 'all', label: 'Toute la saison depuis le début' }
        ];
      case 'boxset':
        return [
          { value: 'following', label: 'À partir du prochain film' },
          { value: 'all', label: 'Toute la collection depuis le début' }
        ];
      default:
        return [{ value: 'single', label: 'Ce média uniquement' }];
    }
  }

  const api = Object.freeze({ links, availabilityFromResult, buttonPresentation, formatDuration, scopeChoices });
  globalThis.JellyfinVlcBridge = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})();
