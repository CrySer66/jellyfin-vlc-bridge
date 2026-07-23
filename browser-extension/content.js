(() => {
  'use strict';

  const BUTTON_ID = 'jellyfin-vlc-bridge-button';
  const TOAST_ID = 'jellyfin-vlc-bridge-toast';
  const DIALOG_ID = 'jellyfin-vlc-bridge-dialog';
  const BRIDGE = globalThis.JellyfinVlcBridge;
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
  let lastAvailabilityCheck = 0;
  let bridgeAvailability = 'checking';
  let closeActiveDialog = null;

  function applyAvailability() {
    const button = document.getElementById(BUTTON_ID);
    if (!button || button.dataset.state === 'loading' || button.dataset.state === 'success') return;
    setButtonState(button, bridgeAvailability);
  }

  function isInvalidExtensionContext(error) {
    const message = typeof error === 'string' ? error : error?.message;
    return !globalThis.chrome?.runtime?.id || /extension context invalidated/i.test(message || '');
  }

  function showReloadNotice(button) {
    bridgeAvailability = 'reload';
    setButtonState(button, 'reload');
    showToast('L’extension a été mise à jour. Rechargez la page Jellyfin.', 'warning');
  }

  function checkBridgeAvailability(force = false) {
    const now = Date.now();
    if (!force && now - lastAvailabilityCheck < 12000) return;
    lastAvailabilityCheck = now;
    try {
      chrome.runtime.sendMessage({ type: 'status' }, result => {
        let runtimeError;
        try { runtimeError = chrome.runtime.lastError; } catch { runtimeError = true; }
        bridgeAvailability = isInvalidExtensionContext(runtimeError)
          ? 'reload'
          : runtimeError ? 'missing' : BRIDGE.availabilityFromResult(result);
        applyAvailability();
      });
    } catch {
      bridgeAvailability = globalThis.chrome?.runtime?.id ? 'missing' : 'reload';
      applyAvailability();
    }
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
    const presentation = BRIDGE.buttonPresentation(state);
    button.dataset.state = state;
    button.disabled = presentation.disabled;
    button.title = presentation.title;
    button.setAttribute('aria-label', presentation.label);
    const label = button.querySelector('.jellyfin-vlc-label');
    if (!label) return;
    label.textContent = presentation.label;
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

  function formatDuration(seconds) {
    return BRIDGE.formatDuration(seconds);
  }

  function scopeChoices(itemType) {
    return BRIDGE.scopeChoices(itemType);
  }

  function inspectItem(itemId, scope) {
    return new Promise((resolve, reject) => {
      try {
        chrome.runtime.sendMessage({ type: 'inspect', itemId, scope }, response => {
          let runtimeError;
          try { runtimeError = chrome.runtime.lastError; } catch { runtimeError = true; }
          if (runtimeError || !response?.ok || !response.inspection) {
            reject(new Error(runtimeError?.message || response?.error || 'Aperçu indisponible'));
            return;
          }
          resolve(response.inspection);
        });
      } catch (error) {
        reject(error);
      }
    });
  }

  function loadPlaybackPreferences() {
    return new Promise(resolve => {
      try {
        chrome.runtime.sendMessage({ type: 'preferences-get' }, response => {
          let runtimeError;
          try { runtimeError = chrome.runtime.lastError; } catch { runtimeError = true; }
          resolve(runtimeError || !response?.ok
            ? { supported: false, preferences: BRIDGE.normalizePreferences() }
            : { supported: true, preferences: BRIDGE.normalizePreferences(response.preferences) });
        });
      } catch {
        resolve({ supported: false, preferences: BRIDGE.normalizePreferences() });
      }
    });
  }

  function savePlaybackPreferences(preferences) {
    try {
      chrome.runtime.sendMessage({ type: 'preferences-save', ...preferences }, response => {
        let runtimeError;
        try { runtimeError = chrome.runtime.lastError; } catch { runtimeError = true; }
        if (runtimeError || !response?.ok)
          console.warn('Jellyfin VLC Bridge : préférences non enregistrées.', runtimeError?.message || response?.error);
      });
    } catch (error) {
      console.warn('Jellyfin VLC Bridge : préférences non enregistrées.', error);
    }
  }

  function createPlaybackDialog() {
    closeActiveDialog?.();
    const previousFocus = document.activeElement;
    const overlay = document.createElement('div');
    overlay.id = DIALOG_ID;
    overlay.className = 'jellyfin-vlc-dialog';
    overlay.innerHTML = `
      <section class="jellyfin-vlc-dialog__panel" role="dialog" aria-modal="true" aria-labelledby="jellyfin-vlc-dialog-title">
        <header class="jellyfin-vlc-dialog__header">
          <div>
            <span class="jellyfin-vlc-dialog__eyebrow">Jellyfin VLC Bridge</span>
            <h2 id="jellyfin-vlc-dialog-title">Préparer la lecture</h2>
          </div>
          <button class="jellyfin-vlc-dialog__close" type="button" aria-label="Fermer">×</button>
        </header>
        <div class="jellyfin-vlc-dialog__body">
          <p class="jellyfin-vlc-dialog__status" role="status">Chargement de la liste de lecture…</p>
          <fieldset class="jellyfin-vlc-dialog__section jellyfin-vlc-dialog__start" hidden>
            <legend>Point de départ</legend>
            <label><input type="radio" name="jvb-start" value="resume"> <span class="jellyfin-vlc-resume-label">Reprendre</span></label>
            <label><input type="radio" name="jvb-start" value="restart"> Lire depuis le début</label>
          </fieldset>
          <fieldset class="jellyfin-vlc-dialog__section jellyfin-vlc-dialog__scope" hidden>
            <legend>Éléments à lire</legend>
            <div class="jellyfin-vlc-dialog__scope-options"></div>
          </fieldset>
          <div class="jellyfin-vlc-dialog__preview" hidden>
            <div class="jellyfin-vlc-dialog__summary"></div>
            <ol class="jellyfin-vlc-dialog__items"></ol>
          </div>
          <label class="jellyfin-vlc-dialog__remember" hidden>
            <input type="checkbox" class="jellyfin-vlc-dialog__remember-input">
            <span>
              <strong>Retenir ces choix</strong>
              <small>Ils seront proposés automatiquement pour ce type de contenu.</small>
            </span>
          </label>
        </div>
        <footer class="jellyfin-vlc-dialog__footer">
          <button class="emby-button jellyfin-vlc-dialog__cancel" type="button">Annuler</button>
          <button class="emby-button jellyfin-vlc-dialog__launch" type="button" disabled>Lancer dans VLC</button>
        </footer>
      </section>`;
    document.body.appendChild(overlay);

    let closed = false;
    const close = () => {
      if (closed) return;
      closed = true;
      document.removeEventListener('keydown', onKeyDown);
      overlay.remove();
      if (closeActiveDialog === close) closeActiveDialog = null;
      if (previousFocus instanceof HTMLElement && previousFocus.isConnected) previousFocus.focus();
    };
    const onKeyDown = event => {
      if (event.key === 'Escape') close();
    };
    closeActiveDialog = close;
    overlay.querySelector('.jellyfin-vlc-dialog__close').addEventListener('click', close);
    overlay.querySelector('.jellyfin-vlc-dialog__cancel').addEventListener('click', close);
    overlay.addEventListener('click', event => {
      if (event.target === overlay) close();
    });
    document.addEventListener('keydown', onKeyDown);
    overlay.querySelector('.jellyfin-vlc-dialog__close').focus();
    return { overlay, close };
  }

  async function openPlaybackDialog(itemId, button) {
    if (bridgeAvailability === 'reload') {
      location.reload();
      return;
    }
    if (bridgeAvailability !== 'ready') {
      openApplicationDownload(button);
      return;
    }

    const dialog = createPlaybackDialog();
    const status = dialog.overlay.querySelector('.jellyfin-vlc-dialog__status');
    const startSection = dialog.overlay.querySelector('.jellyfin-vlc-dialog__start');
    const scopeSection = dialog.overlay.querySelector('.jellyfin-vlc-dialog__scope');
    const scopeOptions = dialog.overlay.querySelector('.jellyfin-vlc-dialog__scope-options');
    const preview = dialog.overlay.querySelector('.jellyfin-vlc-dialog__preview');
    const summary = dialog.overlay.querySelector('.jellyfin-vlc-dialog__summary');
    const items = dialog.overlay.querySelector('.jellyfin-vlc-dialog__items');
    const launch = dialog.overlay.querySelector('.jellyfin-vlc-dialog__launch');
    const remember = dialog.overlay.querySelector('.jellyfin-vlc-dialog__remember');
    const rememberInput = dialog.overlay.querySelector('.jellyfin-vlc-dialog__remember-input');
    let selectedScope = 'auto';
    let selectedItemType = 'video';
    let preferences = BRIDGE.normalizePreferences();
    let preferencesSupported = false;
    let rememberInitialized = false;
    let inspectionRequest = 0;

    const renderInspection = data => {
      const choices = scopeChoices(data.itemType);
      selectedItemType = String(data.itemType || 'video').toLowerCase();
      if (selectedScope === 'auto') selectedScope = BRIDGE.preferredScope(preferences, data.itemType);
      const chosen = choices.some(choice => choice.value === selectedScope) ? selectedScope : choices[0].value;
      selectedScope = chosen;

      dialog.overlay.querySelector('#jellyfin-vlc-dialog-title').textContent = data.title || 'Préparer la lecture';
      status.textContent = data.totalCount
        ? `${data.totalCount} ${data.totalCount > 1 ? 'éléments prêts' : 'élément prêt'}`
        : 'Aucun média lisible dans cette sélection.';
      startSection.hidden = !data.totalCount;
      scopeSection.hidden = choices.length < 2;
      preview.hidden = !data.totalCount;
      remember.hidden = !data.totalCount || !preferencesSupported;
      if (!rememberInitialized) {
        rememberInput.checked = preferences.rememberChoices;
        rememberInitialized = true;
      }

      const resume = dialog.overlay.querySelector('input[value="resume"]');
      const restart = dialog.overlay.querySelector('input[value="restart"]');
      const preferredStart = BRIDGE.preferredStartMode(preferences, data.hasResume);
      resume.disabled = !data.hasResume;
      resume.checked = preferredStart === 'resume';
      restart.checked = preferredStart === 'restart';
      dialog.overlay.querySelector('.jellyfin-vlc-resume-label').textContent = data.hasResume
        ? `Reprendre à ${formatDuration(data.resumeSeconds)}`
        : 'Aucune reprise enregistrée';

      scopeOptions.replaceChildren();
      for (const choice of choices) {
        const label = document.createElement('label');
        const radio = document.createElement('input');
        radio.type = 'radio';
        radio.name = 'jvb-scope';
        radio.value = choice.value;
        radio.checked = choice.value === selectedScope;
        label.append(radio, document.createTextNode(` ${choice.label}`));
        scopeOptions.appendChild(label);
      }

      const duration = formatDuration(data.totalDurationSeconds);
      summary.textContent = `${data.totalCount} ${data.totalCount > 1 ? 'médias' : 'média'}${duration ? ` • environ ${duration}` : ''}`;
      items.replaceChildren();
      for (const item of (data.items || []).slice(0, 10)) {
        const row = document.createElement('li');
        const name = document.createElement('span');
        name.textContent = item.label;
        row.appendChild(name);
        if (item.resumeSeconds > 0) {
          const resumeAt = document.createElement('small');
          resumeAt.textContent = `Reprise à ${formatDuration(item.resumeSeconds)}`;
          row.appendChild(resumeAt);
        }
        items.appendChild(row);
      }
      if (data.totalCount > 10) {
        const remainder = document.createElement('li');
        remainder.className = 'jellyfin-vlc-dialog__remainder';
        remainder.textContent = `… et ${data.totalCount - 10} autres`;
        items.appendChild(remainder);
      }
      launch.disabled = !data.totalCount;
      launch.textContent = data.totalCount > 1 ? `Lancer ${data.totalCount} médias` : 'Lancer dans VLC';
    };

    const refresh = async scope => {
      const request = ++inspectionRequest;
      selectedScope = scope;
      launch.disabled = true;
      status.textContent = 'Actualisation de la liste…';
      try {
        const data = await inspectItem(itemId, scope);
        if (request !== inspectionRequest || !dialog.overlay.isConnected) return;
        renderInspection(data);
      } catch (error) {
        if (request !== inspectionRequest || !dialog.overlay.isConnected) return;
        dialog.close();
        if (isInvalidExtensionContext(error)) {
          showReloadNotice(button);
          return;
        }
        console.warn('Jellyfin VLC Bridge : aperçu indisponible, lecture classique.', error);
        showToast('Aperçu indisponible : lancement avec les réglages habituels.', 'warning');
        playItem(itemId, button);
      }
    };

    scopeOptions.addEventListener('change', event => {
      if (event.target instanceof HTMLInputElement && event.target.name === 'jvb-scope')
        refresh(event.target.value);
    });
    launch.addEventListener('click', () => {
      const startMode = dialog.overlay.querySelector('input[name="jvb-start"]:checked')?.value || 'resume';
      if (preferencesSupported) {
        savePlaybackPreferences({
          rememberChoices: rememberInput.checked,
          startMode,
          itemType: selectedItemType,
          scope: selectedScope
        });
      }
      dialog.close();
      playItem(itemId, button, { scope: selectedScope, startMode });
    });

    try {
      const request = ++inspectionRequest;
      const [data, loadedPreferences] = await Promise.all([
        inspectItem(itemId, 'auto'),
        loadPlaybackPreferences()
      ]);
      if (request !== inspectionRequest || !dialog.overlay.isConnected) return;
      preferencesSupported = loadedPreferences.supported;
      preferences = loadedPreferences.preferences;
      const preferred = BRIDGE.preferredScope(preferences, data.itemType);
      selectedScope = preferred;
      const choices = scopeChoices(data.itemType);
      if (preferences.rememberChoices && preferred !== choices[0].value)
        await refresh(preferred);
      else renderInspection(data);
    } catch (error) {
      if (!dialog.overlay.isConnected) return;
      dialog.close();
      if (isInvalidExtensionContext(error)) {
        showReloadNotice(button);
        return;
      }
      console.warn('Jellyfin VLC Bridge : aperçu indisponible, lecture classique.', error);
      showToast('Mettez à jour le Bridge pour obtenir l’aperçu. Lecture classique lancée.', 'warning');
      playItem(itemId, button);
    }
  }

  function openApplicationDownload(button) {
    bridgeAvailability = 'missing';
    setButtonState(button, 'missing');
    showToast('Installez Jellyfin VLC Bridge pour utiliser VLC.', 'warning');
    try {
      chrome.runtime.sendMessage({ type: 'open-download' }, () => void chrome.runtime.lastError);
    } catch {
      window.open(BRIDGE.links.latestRelease, '_blank', 'noopener,noreferrer');
    }
  }

  function playItem(itemId, button, options = {}) {
    if (button.dataset.state === 'loading') return;
    if (bridgeAvailability !== 'ready') {
      openApplicationDownload(button);
      return;
    }
    setButtonState(button, 'loading');

    try {
      if (!globalThis.chrome?.runtime?.id) {
        showReloadNotice(button);
        return;
      }

      chrome.runtime.sendMessage({
        type: 'play',
        itemId,
        scope: options.scope || 'auto',
        startMode: options.startMode || 'resume'
      }, response => {
        let runtimeError;
        try {
          runtimeError = chrome.runtime.lastError;
        } catch {
          openApplicationDownload(button);
          return;
        }

        if (runtimeError || !response?.ok) {
          console.warn('Jellyfin VLC Bridge : communication directe indisponible.', runtimeError?.message || response?.error);
          if (isInvalidExtensionContext(runtimeError)) {
            showReloadNotice(button);
            return;
          }
          openApplicationDownload(button);
          return;
        }

        setButtonState(button, 'success');
        showToast('Lecture lancée dans VLC.');
        window.setTimeout(() => setButtonState(button, 'ready'), 1800);
      });
    } catch (error) {
      console.warn('Jellyfin VLC Bridge : rechargez la page après une mise à jour de l’extension.', error);
      if (isInvalidExtensionContext(error)) showReloadNotice(button);
      else openApplicationDownload(button);
    }
  }

  function createButton(itemId) {
    const button = document.createElement('button');
    button.id = BUTTON_ID;
    button.type = 'button';
    button.className = 'emby-button button-flat detailButton jellyfin-vlc-button';
    button.dataset.itemId = itemId;
    button.innerHTML = `${iconMarkup()}<span class="jellyfin-vlc-label"></span>`;
    setButtonState(button, bridgeAvailability);
    button.addEventListener('click', () => openPlaybackDialog(button.dataset.itemId, button));
    return button;
  }

  function mountButton() {
    scheduled = false;
    checkBridgeAvailability();
    const itemId = getItemId();
    let button = document.getElementById(BUTTON_ID);

    if (activeItemId && itemId !== activeItemId) closeActiveDialog?.();

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
  window.addEventListener('focus', () => checkBridgeAvailability(true));
  window.setInterval(checkBridgeAvailability, 15000);
  checkBridgeAvailability(true);
  scheduleMount();
})();
