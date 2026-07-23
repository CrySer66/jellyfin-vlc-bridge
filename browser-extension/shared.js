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

  function normalizePreferences(value) {
    const source = value?.preferences || value || {};
    const scopes = source.scopes && typeof source.scopes === 'object' ? source.scopes : {};
    const normalizedScopes = {};
    for (const [itemType, scope] of Object.entries(scopes)) {
      const key = String(itemType || '').trim().toLowerCase();
      const normalizedScope = String(scope || '').trim().toLowerCase();
      if (key && ['single', 'following', 'all'].includes(normalizedScope))
        normalizedScopes[key] = normalizedScope;
    }
    return Object.freeze({
      rememberChoices: source.rememberChoices === true,
      startMode: source.startMode === 'restart' ? 'restart' : 'resume',
      scopes: Object.freeze(normalizedScopes)
    });
  }

  function preferredScope(preferences, itemType) {
    const choices = scopeChoices(itemType);
    const normalized = normalizePreferences(preferences);
    if (!normalized.rememberChoices) return choices[0].value;
    const saved = normalized.scopes[String(itemType || '').toLowerCase()];
    return choices.some(choice => choice.value === saved) ? saved : choices[0].value;
  }

  function preferredStartMode(preferences, hasResume) {
    if (!hasResume) return 'restart';
    const normalized = normalizePreferences(preferences);
    return normalized.rememberChoices ? normalized.startMode : 'resume';
  }

  const api = Object.freeze({
    links,
    availabilityFromResult,
    buttonPresentation,
    formatDuration,
    scopeChoices,
    normalizePreferences,
    preferredScope,
    preferredStartMode
  });
  globalThis.JellyfinVlcBridge = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})();
