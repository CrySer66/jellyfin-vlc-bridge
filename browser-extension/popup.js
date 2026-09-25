(() => {
  'use strict';

  const bridge = globalThis.JellyfinVlcBridge;
  const i18n = globalThis.JellyfinVlcBridgeI18n;
  const t = i18n.t;
  const status = document.getElementById('status');
  const title = document.getElementById('status-title');
  const detail = document.getElementById('status-detail');
  const retry = document.getElementById('retry');
  const download = document.getElementById('download');

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
  retry.textContent = t('retry');
  download.hidden = true;

  for (const link of document.querySelectorAll('a')) {
    link.target = '_blank';
    link.rel = 'noopener noreferrer';
  }

  function renderStatus(availability) {
    status.className = `status status--${availability}`;
    retry.disabled = false;
    retry.hidden = availability === 'ready';
    download.hidden = availability !== 'missing';

    if (availability === 'ready') {
      title.textContent = t('popupReadyTitle');
      detail.textContent = t('popupReadyDetail');
    } else if (availability === 'missing') {
      title.textContent = t('popupMissingTitle');
      detail.textContent = t('popupMissingDetail');
    } else {
      title.textContent = t('checkConnection');
      detail.textContent = t('bridgeCommunicationFailed');
    }
  }

  function checkStatus() {
    retry.disabled = true;
    download.hidden = true;
    status.className = 'status status--checking';
    title.textContent = t('popupCheckingTitle');
    detail.textContent = t('popupCheckingDetail');
    try {
      chrome.runtime.sendMessage({ type: 'status' }, result => {
        renderStatus(chrome.runtime.lastError ? 'unavailable' : bridge.availabilityFromResult(result));
      });
    } catch {
      renderStatus('unavailable');
    }
  }
  retry.addEventListener('click', checkStatus);
  checkStatus();
})();
