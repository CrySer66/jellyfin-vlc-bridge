(() => {
  'use strict';

  const fallbackMessages = Object.freeze({
    extensionName: 'Jellyfin VLC Bridge',
    checking: 'Checking…',
    opening: 'Opening…',
    vlcStarted: 'VLC started',
    reloadJellyfin: 'Reload Jellyfin',
    applicationNotInstalled: 'Application not installed',
    playWithVlc: 'Play with VLC',
    checkingBridgeTitle: 'Checking Jellyfin VLC Bridge',
    openingMediaTitle: 'Opening the media in VLC',
    playbackStartedTitle: 'Playback started in VLC',
    reloadRequiredTitle: 'The extension was updated: reload this page',
    downloadApplicationTitle: 'Download the Jellyfin VLC Bridge application',
    playOriginalTitle: 'Play the original file with VLC',
    durationMinutes: '$1 min',
    durationHours: '$1 h',
    durationHoursMinutes: '$1 h $2 min',
    scopeEpisodeFollowing: 'This episode and the following ones',
    scopeEpisodeSingle: 'This episode only',
    scopeSeriesFollowing: 'From the next episode',
    scopeSeriesAll: 'The whole series from the beginning',
    scopeSeasonFollowing: 'From the next episode',
    scopeSeasonAll: 'The whole season from the beginning',
    scopeBoxSetFollowing: 'From the next movie',
    scopeBoxSetAll: 'The whole collection from the beginning',
    scopeSingle: 'This media only',
    extensionUpdatedToast: 'The extension was updated. Reload the Jellyfin page.',
    previewUnavailable: 'Preview unavailable',
    preparePlayback: 'Prepare playback',
    close: 'Close',
    loadingPlaylist: 'Loading playlist…',
    startingPoint: 'Starting point',
    resume: 'Resume',
    playFromBeginning: 'Play from the beginning',
    itemsToPlay: 'Items to play',
    rememberChoices: 'Remember these choices',
    rememberChoicesHint: 'They will be suggested automatically for this type of content.',
    cancel: 'Cancel',
    launchInVlc: 'Launch in VLC',
    itemReady: '1 item ready',
    itemsReady: '$1 items ready',
    noPlayableMedia: 'No playable media in this selection.',
    resumeAt: 'Resume at $1',
    noResume: 'No saved resume point',
    mediaSummary: '$1 media',
    mediasSummary: '$1 media',
    approximatelyDuration: ' • approximately $1',
    andOthers: '… and $1 more',
    launchMediaCount: 'Launch $1 media',
    refreshingPlaylist: 'Refreshing the playlist…',
    classicLaunchWarning: 'Preview unavailable: launching with the usual settings.',
    updateBridgeWarning: 'Update the Bridge to enable preview. Standard playback started.',
    installBridgeToast: 'Install Jellyfin VLC Bridge to use VLC.',
    playbackStartedToast: 'Playback started in VLC.',
    popupExtensionVersion: 'Extension $1',
    popupCheckingTitle: 'Checking the application…',
    popupCheckingDetail: 'Communicating with the Bridge installed on this PC.',
    popupDownload: 'Download the Windows application',
    popupGithub: 'View the project on GitHub',
    popupSupport: 'Help and report a problem',
    popupReadyTitle: 'Application ready',
    popupReadyDetail: 'The Bridge is installed and can launch VLC from Jellyfin.',
    popupMissingTitle: 'Application not installed',
    popupMissingDetail: 'Install the Windows Bridge to enable playback with VLC.'
  });

  function replacePlaceholders(message, substitutions) {
    const values = Array.isArray(substitutions) ? substitutions : [substitutions];
    return values.reduce(
      (result, value, index) => result.replaceAll(`$${index + 1}`, String(value ?? '')),
      message
    );
  }

  function t(key, substitutions) {
    try {
      const translated = globalThis.chrome?.i18n?.getMessage?.(key, substitutions);
      if (translated) return translated;
    } catch { }
    return replacePlaceholders(fallbackMessages[key] || key, substitutions);
  }

  function locale() {
    try {
      return globalThis.chrome?.i18n?.getUILanguage?.() || 'en';
    } catch {
      return 'en';
    }
  }

  const api = Object.freeze({ t, locale });
  globalThis.JellyfinVlcBridgeI18n = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})();
