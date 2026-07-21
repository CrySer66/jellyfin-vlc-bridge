(() => {
  'use strict';

  const BUTTON_ID = 'jellyfin-vlc-bridge-button';
  const TOAST_ID = 'jellyfin-vlc-bridge-toast';
  const ACTION_CONTAINERS = [
    '.detailPagePrimaryContainer .mainDetailButtons',
    '.detailPageContent .mainDetailButtons',
    '.mainDetailButtons',
    '.detailButtons'
  ];
  const PLAY_CONTROLS = [
    'button.btnResume',
    'button.btnPlay',
    'button[data-action="resume"]',
    'button[data-action="play"]'
  ].join(',');

  let scheduled = false;
  let activeItemId = null;
  let lastHeartbeat = 0;

  function notifyBridgeActivity(force = false) {
    const now = Date.now();
    if (!force && now - lastHeartbeat < 12000) return;
    lastHeartbeat = now;
    try {
      chrome.runtime.sendMessage({ type: 'heartbeat' }, () => void chrome.runtime.lastError);
    } catch { /* The page will be reloaded after an extension update. */ }
  }

  function getItemId() {
    const hash = location.hash || '';
    const query = hash.includes('?') ? hash.slice(hash.indexOf('?') + 1) : '';
    return new URLSearchParams(query).get('id') ||
      new URLSearchParams(location.search).get('id');
  }

  function isVisible(element) {
    return Boolean(element && element.isConnected && element.getClientRects().length);
  }

  function findPlayControl() {
    return Array.from(document.querySelectorAll(PLAY_CONTROLS)).find(isVisible) || null;
  }

  function findActionContainer(playControl) {
    for (const selector of ACTION_CONTAINERS) {
      const container = Array.from(document.querySelectorAll(selector)).find(isVisible);
      if (container) return container;
    }

    return playControl?.closest('.mainDetailButtons, .detailButtons') || playControl?.parentElement || null;
  }

  function iconMarkup() {
    return `
      <svg class="jellyfin-vlc-icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
        <path d="M10.1 3.4a2.2 2.2 0 0 1 3.8 0l1.35 2.42H8.75L10.1 3.4Zm-2.4 4.3h8.6l1.12 2H6.58l1.12-2Zm-2.16 3.88h12.92l2.14 3.84a2 2 0 0 1-1.75 2.98H5.15a2 2 0 0 1-1.75-2.98l2.14-3.84Zm1.22 7.72h10.48l.78 1.4H5.98l.78-1.4Z"/>
      </svg>`;
  }

  function setButtonState(button, state) {
    button.dataset.state = state;
    button.disabled = state === 'loading';
    const label = button.querySelector('.jellyfin-vlc-label');
    if (!label) return;
    label.textContent = state === 'loading' ? 'Ouverture…' : state === 'success' ? 'VLC lancé' : 'Lire avec VLC';
  }

  function showToast(message, kind = 'success') {
    document.getElementById(TOAST_ID)?.remove();
    const toast = document.createElement('div');
    toast.id = TOAST_ID;
    toast.className = `jellyfin-vlc-toast jellyfin-vlc-toast--${kind}`;
    toast.setAttribute('role', 'status');
    toast.textContent = message;
    document.body.appendChild(toast);
    requestAnimationFrame(() => toast.classList.add('is-visible'));
    window.setTimeout(() => {
      toast.classList.remove('is-visible');
      window.setTimeout(() => toast.remove(), 220);
    }, 3200);
  }

  function protocolFallback(itemId, button) {
    setButtonState(button, 'idle');
    showToast('Ouverture de VLC par Windows…', 'info');
    location.href = `jellyfin-vlc://play?itemId=${encodeURIComponent(itemId)}`;
  }

  function playItem(itemId, button) {
    if (button.dataset.state === 'loading') return;
    setButtonState(button, 'loading');

    try {
      if (!globalThis.chrome?.runtime?.id) {
        protocolFallback(itemId, button);
        return;
      }

      chrome.runtime.sendMessage({ type: 'play', itemId }, response => {
        let runtimeError;
        try {
          runtimeError = chrome.runtime.lastError;
        } catch {
          protocolFallback(itemId, button);
          return;
        }

        if (runtimeError || !response?.ok) {
          console.warn('Jellyfin VLC Bridge : communication directe indisponible.', runtimeError?.message || response?.error);
          protocolFallback(itemId, button);
          return;
        }

        setButtonState(button, 'success');
        showToast('Lecture lancée dans VLC.');
        window.setTimeout(() => setButtonState(button, 'idle'), 1800);
      });
    } catch (error) {
      console.warn('Jellyfin VLC Bridge : rechargez la page après une mise à jour de l’extension.', error);
      protocolFallback(itemId, button);
    }
  }

  function createButton(itemId) {
    const button = document.createElement('button');
    button.id = BUTTON_ID;
    button.type = 'button';
    button.className = 'emby-button button-flat detailButton jellyfin-vlc-button';
    button.title = 'Lire le fichier original avec VLC';
    button.setAttribute('aria-label', 'Lire avec VLC');
    button.dataset.itemId = itemId;
    button.dataset.state = 'idle';
    button.innerHTML = `${iconMarkup()}<span class="jellyfin-vlc-label">Lire avec VLC</span>`;
    button.addEventListener('click', () => playItem(button.dataset.itemId, button));
    return button;
  }

  function mountButton() {
    scheduled = false;
    notifyBridgeActivity();
    const itemId = getItemId();
    let button = document.getElementById(BUTTON_ID);

    if (!itemId) {
      button?.remove();
      activeItemId = null;
      return;
    }

    const playControl = findPlayControl();
    if (!playControl) {
      button?.remove();
      return;
    }

    const container = findActionContainer(playControl);
    if (!container) return;

    if (!button || activeItemId !== itemId) {
      button?.remove();
      button = createButton(itemId);
      activeItemId = itemId;
    }

    button.dataset.itemId = itemId;
    const isIntegrated = container.matches('.mainDetailButtons, .detailButtons');
    button.classList.toggle('jellyfin-vlc-button--floating', !isIntegrated);

    if (button.parentElement !== container) {
      const reference = playControl.parentElement === container ? playControl.nextSibling : null;
      container.insertBefore(button, reference);
    }
  }

  function scheduleMount() {
    if (scheduled) return;
    scheduled = true;
    window.setTimeout(mountButton, 120);
  }

  new MutationObserver(scheduleMount).observe(document.documentElement, { childList: true, subtree: true });
  window.addEventListener('hashchange', scheduleMount);
  window.addEventListener('popstate', scheduleMount);
  window.addEventListener('focus', () => notifyBridgeActivity(true));
  window.setInterval(notifyBridgeActivity, 15000);
  notifyBridgeActivity(true);
  scheduleMount();
})();
