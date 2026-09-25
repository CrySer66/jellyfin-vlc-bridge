'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
require('../browser-extension/i18n.js');
const bridge = require('../browser-extension/shared.js');

assert.equal(bridge.links.repository, 'https://github.com/CrySer66/jellyfin-vlc-bridge');
assert.equal(bridge.links.latestRelease, 'https://github.com/CrySer66/jellyfin-vlc-bridge/releases/latest');
assert.equal(bridge.availabilityFromResult({ ok: true }), 'ready');
assert.equal(bridge.availabilityFromResult({ ok: false }), 'unavailable');
assert.equal(bridge.availabilityFromResult(undefined), 'unavailable');
assert.equal(bridge.availabilityFromResult({ ok: false, errorCode: 'native_missing' }), 'missing');
assert.equal(bridge.availabilityFromResult({ ok: false, errorCode: 'native_transport' }), 'unavailable');
assert.equal(bridge.availabilityFromResult({ ok: false, errorCode: 'native_timeout' }), 'unavailable');
assert.equal(bridge.nativeErrorCode('Specified native messaging host not found.'), 'native_missing');
assert.equal(bridge.nativeErrorCode('Native messaging host local.jellyfin_vlc_bridge is not registered.'), 'native_missing');
assert.equal(bridge.nativeErrorCode('Native host has exited.'), 'native_transport');
assert.equal(bridge.nativeErrorCode('Access to the specified native messaging host is forbidden.'), 'native_transport');
assert.equal(bridge.nativeErrorCode('Le programme ne répond pas.'), 'native_transport');
assert.equal(bridge.supportsInspection('1.9.0'), false);
assert.equal(bridge.supportsInspection('1.10.0'), true);
assert.equal(bridge.supportsInspection('1.18.1'), true);
assert.equal(bridge.supportsInspection('2.0.0'), true);
assert.equal(bridge.supportsInspection(null), null);
assert.equal(bridge.canPlayWithoutPreview({ errorCode: 'unsupported_request' }, '1.18.1'), true);
assert.equal(bridge.canPlayWithoutPreview({ errorCode: 'native_transport' }, '1.9.0'), true);
assert.equal(bridge.canPlayWithoutPreview({}, '1.9.0'), true);
assert.equal(bridge.canPlayWithoutPreview({ errorCode: 'authentication_required' }, '1.9.0'), false);
assert.equal(bridge.canPlayWithoutPreview({ errorCode: 'native_transport' }, '1.18.1'), false);
assert.equal(bridge.canPlayWithoutPreview({}, null), false);
assert.match(bridge.requestErrorMessage({ errorCode: 'authentication_required' }), /Reconnect your account/);
assert.match(bridge.requestErrorMessage({ errorCode: 'access_denied' }), /account permissions/);
assert.match(bridge.requestErrorMessage({ errorCode: 'item_not_found' }), /no longer available/);
assert.match(bridge.requestErrorMessage({ errorCode: 'native_transport' }), /Communication/);
assert.match(bridge.requestErrorMessage({ error: 'secret diagnostic text' }), /diagnostics/);
assert.equal(bridge.buttonPresentation('ready').label, 'Play with VLC');
assert.equal(bridge.buttonPresentation('missing').label, 'Application not found');
assert.equal(bridge.buttonPresentation('unavailable').label, 'Check the connection');
assert.equal(bridge.buttonPresentation('unavailable').disabled, false);
assert.equal(bridge.buttonPresentation('missing').disabled, false);
assert.equal(bridge.buttonPresentation('checking').disabled, true);
assert.equal(bridge.buttonPresentation('reload').label, 'Reload Jellyfin');
assert.equal(bridge.formatDuration(42 * 60), '42 min');
assert.equal(bridge.formatDuration(2 * 3600 + 13 * 60), '2 h 13 min');
assert.equal(bridge.formatDuration(59 * 60 + 40), '1 h');
assert.deepEqual(bridge.scopeChoices('Episode').map(choice => choice.value), ['following', 'single']);
assert.deepEqual(bridge.scopeChoices('Series').map(choice => choice.value), ['following', 'all']);
assert.deepEqual(bridge.scopeChoices('BoxSet').map(choice => choice.value), ['following', 'all']);
assert.deepEqual(bridge.scopeChoices('Movie').map(choice => choice.value), ['single']);

assert.deepEqual(bridge.normalizePreferences(), {
  rememberChoices: false,
  startMode: 'resume',
  scopes: {}
});
const remembered = bridge.normalizePreferences({
  rememberChoices: true,
  startMode: 'restart',
  scopes: { Series: 'all', invalid: 'anything' }
});
assert.equal(remembered.rememberChoices, true);
assert.equal(remembered.startMode, 'restart');
assert.equal(remembered.scopes.series, 'all');
assert.equal(bridge.preferredScope(remembered, 'Series'), 'all');
assert.equal(bridge.preferredScope(remembered, 'Episode'), 'following');
assert.equal(bridge.preferredStartMode(remembered, true), 'restart');
assert.equal(bridge.preferredStartMode(remembered, false), 'restart');
assert.equal(bridge.preferredStartMode({}, true), 'resume');
assert.equal(bridge.preferredStartMode({}, true, 'restart'), 'restart');
assert.equal(bridge.preferredStartMode(remembered, true, 'resume'), 'resume');
assert.equal(bridge.preferredStartMode(remembered, false, 'resume'), 'restart');

const localesRoot = path.join(__dirname, '..', 'browser-extension', '_locales');
const english = JSON.parse(fs.readFileSync(path.join(localesRoot, 'en', 'messages.json'), 'utf8'));
const french = JSON.parse(fs.readFileSync(path.join(localesRoot, 'fr', 'messages.json'), 'utf8'));
assert.deepEqual(Object.keys(french).sort(), Object.keys(english).sort());
assert.equal(english.playWithVlc.message, 'Play with VLC');
assert.equal(french.playWithVlc.message, 'Lire avec VLC');
globalThis.chrome = {
  i18n: {
    getMessage(key) {
      return french[key]?.message || '';
    }
  }
};
assert.equal(bridge.buttonPresentation('ready').label, 'Lire avec VLC');
assert.equal(bridge.buttonPresentation('missing').label, 'Application introuvable');
assert.equal(bridge.buttonPresentation('unavailable').label, 'Vérifier la connexion');
assert.match(bridge.requestErrorMessage({ errorCode: 'authentication_required' }), /Reconnectez votre compte/);
delete globalThis.chrome;

const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'browser-extension', 'manifest.json'), 'utf8'));
assert.equal(manifest.default_locale, 'en');
assert.match(manifest.version, /^\d+\.\d+\.\d+$/);
assert.equal(manifest.name, '__MSG_extensionName__');
assert.equal(manifest.content_scripts[0].js[0], 'i18n.js');
const contentScript = fs.readFileSync(path.join(__dirname, '..', 'browser-extension', 'content.js'), 'utf8');
const backgroundScript = fs.readFileSync(path.join(__dirname, '..', 'browser-extension', 'background.js'), 'utf8');
assert.match(contentScript, /jellyfin-vlc-dialog__source/);
assert.match(contentScript, /mediaSourceId/);
assert.match(backgroundScript, /mediaSourceId/);
assert.equal(english.mediaVersion.message, 'Media version');
assert.equal(french.mediaVersion.message, 'Version du média');

// Execute the real background listener against native messaging responses.
// Application errors must survive the relay instead of becoming "not installed".
let onMessage;
let nativeResponse = { accepted: true, type: 'pong', bridgeVersion: '1.18.1' };
let transportError = null;
let nativeException = null;
let deferNative = false;
let pendingNativeCallback;
let timerId = 0;
const timers = new Map();
const nativePayloads = [];
const runtime = {
  getManifest: () => manifest,
  onInstalled: { addListener() {} },
  onStartup: { addListener() {} },
  onMessage: { addListener(listener) { onMessage = listener; } },
  sendNativeMessage(host, payload, callback) {
    assert.equal(host, 'local.jellyfin_vlc_bridge');
    nativePayloads.push(payload);
    if (nativeException) throw nativeException;
    if (deferNative) {
      pendingNativeCallback = callback;
      return;
    }
    this.lastError = transportError;
    callback(nativeResponse);
    this.lastError = null;
  }
};
vm.runInNewContext(backgroundScript, {
  JellyfinVlcBridge: bridge,
  importScripts() {},
  setTimeout(callback, milliseconds) {
    assert.equal(milliseconds, 10000);
    timers.set(++timerId, callback);
    return timerId;
  },
  clearTimeout(id) { timers.delete(id); },
  chrome: { runtime, tabs: { create() { throw new Error('Unexpected download tab'); } } }
});
function relay(message) {
  let result;
  assert.equal(onMessage(message, {}, response => { result = response; }), true);
  assert.ok(result, 'The native result must reach the content script');
  return result;
}
assert.equal(relay({ type: 'status' }).response.bridgeVersion, '1.18.1');
assert.equal(timers.size, 0, 'Successful pings clear their timeout');
transportError = { message: 'Specified native messaging host not found.' };
assert.equal(relay({ type: 'status' }).errorCode, 'native_missing');
transportError = { message: 'Access to the specified native messaging host is forbidden.' };
assert.equal(relay({ type: 'status' }).errorCode, 'native_transport');
transportError = null;
nativeException = new Error('Native messaging is temporarily unavailable');
assert.equal(relay({ type: 'status' }).errorCode, 'native_transport');
assert.equal(timers.size, 0, 'Synchronous failures clear their timeout');
nativeException = null;
deferNative = true;
const delayedResults = [];
assert.equal(onMessage({ type: 'status' }, {}, result => delayedResults.push(result)), true);
assert.equal(timers.size, 1);
[...timers.values()][0]();
assert.equal(delayedResults[0].errorCode, 'native_timeout');
pendingNativeCallback({ accepted: true });
assert.equal(delayedResults.length, 1, 'Late native replies must not overwrite the timeout result');
assert.equal(timers.size, 0);
const delayedPlayback = [];
assert.equal(onMessage({ type: 'play', itemId: 'media-id' }, {}, result => delayedPlayback.push(result)), true);
assert.equal(timers.size, 0, 'A slow launch must not time out and invite duplicate playback');
pendingNativeCallback({ accepted: true });
assert.equal(delayedPlayback[0].ok, true);
deferNative = false;
for (const type of ['inspect', 'play', 'preferences-get', 'preferences-save']) {
  nativeResponse = { accepted: false, errorCode: 'authentication_required', error: 'Jellyfin rejected the connection' };
  const failed = relay({ type, itemId: 'media-id' });
  assert.equal(failed.ok, false);
  assert.equal(failed.errorCode, 'authentication_required');
  assert.equal(failed.error, nativeResponse.error);
}
nativeResponse = { accepted: false, errorCode: 'unsupported_request', error: 'Unsupported request' };
assert.equal(relay({ type: 'inspect', itemId: 'media-id' }).errorCode, 'unsupported_request');
transportError = { message: 'Native host has exited.' };
assert.equal(relay({ type: 'inspect', itemId: 'media-id' }).errorCode, 'native_transport');
transportError = null;
nativeResponse = { accepted: true, totalCount: 1, itemType: 'Movie', mediaSources: [] };
assert.equal(relay({ type: 'inspect', itemId: 'media-id' }).inspection, nativeResponse);
nativeResponse = { accepted: true };
assert.equal(relay({ type: 'play', itemId: 'media-id', scope: 'single', startMode: 'restart', mediaSourceId: 'source-id' }).ok, true);
assert.equal(nativePayloads.at(-1).mediaSourceId, 'source-id');
assert.equal(nativePayloads.at(-1).extensionVersion, manifest.version);

// Run the popup itself: a broken connection should offer Retry, not an
// installation prompt; recovery must show a concrete Jellyfin playback step.
const popupElements = new Map();
for (const id of ['status', 'status-title', 'status-detail', 'version', 'retry', 'download', 'github', 'support']) {
  popupElements.set(id, { hidden: false, listeners: {}, addEventListener(type, listener) { this.listeners[type] = listener; } });
}
let popupResponse = { ok: false, errorCode: 'native_transport' };
let popupThrows = false;
const popupRuntime = {
  getManifest: () => manifest,
  sendMessage(message, callback) {
    assert.equal(message.type, 'status');
    if (popupThrows) throw new Error('Disconnected extension');
    callback(popupResponse);
  }
};
vm.runInNewContext(fs.readFileSync(path.join(__dirname, '..', 'browser-extension', 'popup.js'), 'utf8'), {
  JellyfinVlcBridge: bridge,
  JellyfinVlcBridgeI18n: globalThis.JellyfinVlcBridgeI18n,
  chrome: { runtime: popupRuntime },
  document: {
    documentElement: {},
    getElementById(id) { return popupElements.get(id); },
    querySelectorAll() { return ['download', 'github', 'support'].map(id => popupElements.get(id)); }
  }
});
assert.equal(popupElements.get('status').className, 'status status--unavailable');
assert.equal(popupElements.get('download').hidden, true);
assert.equal(popupElements.get('retry').hidden, false);
assert.equal(popupElements.get('retry').disabled, false);
popupResponse = { ok: false, errorCode: 'native_missing' };
popupElements.get('retry').listeners.click();
assert.equal(popupElements.get('status').className, 'status status--missing');
assert.equal(popupElements.get('download').hidden, false);
popupResponse = { ok: true };
popupElements.get('retry').listeners.click();
assert.equal(popupElements.get('status-title').textContent, 'Application connected');
assert.match(popupElements.get('status-detail').textContent, /Open a movie or episode/);
assert.equal(popupElements.get('download').hidden, true);
assert.equal(popupElements.get('retry').hidden, true);
popupThrows = true;
popupElements.get('retry').listeners.click();
assert.equal(popupElements.get('status').className, 'status status--unavailable');
assert.equal(popupElements.get('retry').disabled, false);

// The page can issue a new check when it regains focus. An older failed ping
// must not overwrite the result of a newer successful check.
const statusCallbacks = [];
const pageEvents = {};
const pageLabel = {};
const pageButton = {
  dataset: { state: 'checking' },
  setAttribute() {},
  querySelector() { return pageLabel; }
};
vm.runInNewContext(contentScript, {
  JellyfinVlcBridge: bridge,
  JellyfinVlcBridgeI18n: globalThis.JellyfinVlcBridgeI18n,
  chrome: {
    runtime: {
      id: 'fixture-extension',
      sendMessage(message, callback) {
        assert.equal(message.type, 'status');
        statusCallbacks.push(callback);
      }
    }
  },
  document: { documentElement: {}, getElementById() { return pageButton; } },
  window: {
    setTimeout() {},
    setInterval() {},
    addEventListener(name, listener) { pageEvents[name] = listener; }
  },
  MutationObserver: class { observe() {} }
});
pageEvents.focus();
statusCallbacks[1]({ ok: true });
assert.equal(pageButton.dataset.state, 'ready');
statusCallbacks[0]({ ok: false, errorCode: 'native_missing' });
assert.equal(pageButton.dataset.state, 'ready');
pageEvents.focus();
statusCallbacks[2]({ ok: false, errorCode: 'native_transport' });
assert.equal(pageButton.dataset.state, 'unavailable');
assert.equal(pageLabel.textContent, 'Check the connection');

console.log('OK  Extension Chrome bilingue avec choix de version du média');
