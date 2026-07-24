(() => {
  'use strict';

  const bridge = globalThis.JellyfinVlcBridge;
  const i18n = globalThis.JellyfinVlcBridgeI18n;
  const t = i18n.t;
  const status = document.getElementById('status');
  const title = document.getElementById('status-title');
  const detail = document.getElementById('status-detail');

  document.documentElement.lang = i18n.locale().split('-')[0] || 'en';
  document.getElementById('version').textContent =
    t('popupExtensionVersion', chrome.runtime.getManifest().version);
  document.getElementById('download').href = bridge.links.latestRelease;
  document.getElementById('download').textContent = t('popupDownload');
  document.getElementById('github').href = bridge.links.repository;
  document.getElementById('github').textContent = t('popupGithub');
  document.getElementById('support').href = bridge.links.support;
  document.getElementById('support').textContent = t('popupSupport');
  title.textContent = t('popupCheckingTitle');
  detail.textContent = t('popupCheckingDetail');

  for (const link of document.querySelectorAll('a')) {
    link.target = '_blank';
    link.rel = 'noopener noreferrer';
  }

  chrome.runtime.sendMessage({ type: 'status' }, result => {
    const runtimeError = chrome.runtime.lastError;
    const availability = runtimeError ? 'missing' : bridge.availabilityFromResult(result);
    status.className = `status status--${availability}`;

    if (availability === 'ready') {
      title.textContent = t('popupReadyTitle');
      detail.textContent = t('popupReadyDetail');
    } else {
      title.textContent = t('popupMissingTitle');
      detail.textContent = t('popupMissingDetail');
    }
  });
})();
