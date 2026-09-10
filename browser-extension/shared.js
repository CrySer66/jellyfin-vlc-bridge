(() => {
  'use strict';

  const t = (key, substitutions) =>
    globalThis.JellyfinVlcBridgeI18n?.t(key, substitutions) || key;

  const links = Object.freeze({
    repository: 'https://github.com/CrySer66/jellyfin-vlc-bridge',
    latestRelease: 'https://github.com/CrySer66/jellyfin-vlc-bridge/releases/latest',
    support: 'https://github.com/CrySer66/jellyfin-vlc-bridge/issues/new/choose'
  });

  function availabilityFromResult(result) {
    return result?.ok ? 'ready' : 'missing';
  }

  function supportsInspection(version) {
    const match = /^(\d+)\.(\d+)(?:\.|$)/.exec(String(version || ''));
    if (!match) return null;
    return Number(match[1]) > 1 || (Number(match[1]) === 1 && Number(match[2]) >= 10);
  }

  function canPlayWithoutPreview(error, version) {
    if (error?.errorCode === 'unsupported_request') return true;
    // Inspection was added in Bridge 1.10. Older hosts may close the native
    // channel for an unknown request instead of sending a structured error.
    return supportsInspection(version) === false &&
      (!error?.errorCode || error.errorCode === 'native_transport');
  }

  function requestErrorMessage(error) {
    switch (error?.errorCode) {
      case 'authentication_required': return t('jellyfinAuthenticationRequired');
      case 'access_denied': return t('jellyfinAccessDenied');
      case 'item_not_found': return t('jellyfinItemNotFound');
      case 'native_transport': return t('bridgeCommunicationFailed');
      default: return t('playbackRequestFailed');
    }
  }

  function buttonPresentation(state) {
    const presentations = {
      checking: { label: t('checking'), title: t('checkingBridgeTitle'), disabled: true },
      loading: { label: t('opening'), title: t('openingMediaTitle'), disabled: true },
      success: { label: t('vlcStarted'), title: t('playbackStartedTitle'), disabled: false },
      reload: { label: t('reloadJellyfin'), title: t('reloadRequiredTitle'), disabled: false },
      missing: { label: t('applicationNotInstalled'), title: t('downloadApplicationTitle'), disabled: false },
      ready: { label: t('playWithVlc'), title: t('playOriginalTitle'), disabled: false }
    };

    return presentations[state] || presentations.checking;
  }

  function formatDuration(seconds) {
    const value = Math.max(0, Number(seconds) || 0);
    if (!value) return '';
    const totalMinutes = Math.max(1, Math.round(value / 60));
    const hours = Math.floor(totalMinutes / 60);
    const minutes = totalMinutes % 60;
    if (!hours) return t('durationMinutes', String(minutes));
    return minutes
      ? t('durationHoursMinutes', [String(hours), String(minutes)])
      : t('durationHours', String(hours));
  }

  function scopeChoices(itemType) {
    switch ((itemType || '').toLowerCase()) {
      case 'episode':
        return [
          { value: 'following', label: t('scopeEpisodeFollowing') },
          { value: 'single', label: t('scopeEpisodeSingle') }
        ];
      case 'series':
        return [
          { value: 'following', label: t('scopeSeriesFollowing') },
          { value: 'all', label: t('scopeSeriesAll') }
        ];
      case 'season':
        return [
          { value: 'following', label: t('scopeSeasonFollowing') },
          { value: 'all', label: t('scopeSeasonAll') }
        ];
      case 'boxset':
        return [
          { value: 'following', label: t('scopeBoxSetFollowing') },
          { value: 'all', label: t('scopeBoxSetAll') }
        ];
      default:
        return [{ value: 'single', label: t('scopeSingle') }];
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
    supportsInspection,
    canPlayWithoutPreview,
    requestErrorMessage,
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
