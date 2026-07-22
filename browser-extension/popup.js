(() => {
  'use strict';

  const bridge = globalThis.JellyfinVlcBridge;
  const status = document.getElementById('status');
  const title = document.getElementById('status-title');
  const detail = document.getElementById('status-detail');

  document.getElementById('version').textContent = `Extension ${chrome.runtime.getManifest().version}`;
  document.getElementById('download').href = bridge.links.latestRelease;
  document.getElementById('github').href = bridge.links.repository;
  document.getElementById('support').href = bridge.links.support;

  for (const link of document.querySelectorAll('a')) {
    link.target = '_blank';
    link.rel = 'noopener noreferrer';
  }

  chrome.runtime.sendMessage({ type: 'status' }, result => {
    const runtimeError = chrome.runtime.lastError;
    const availability = runtimeError ? 'missing' : bridge.availabilityFromResult(result);
    status.className = `status status--${availability}`;

    if (availability === 'ready') {
      title.textContent = 'Application prête';
      detail.textContent = 'Le Bridge est installé et peut lancer VLC depuis Jellyfin.';
    } else {
      title.textContent = 'Application non installée';
      detail.textContent = 'Installez le Bridge Windows pour activer la lecture avec VLC.';
    }
  });
})();
