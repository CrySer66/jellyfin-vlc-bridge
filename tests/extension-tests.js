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
assert.equal(bridge.availabilityFromResult({ ok: false }), 'missing');
assert.equal(bridge.availabilityFromResult(undefined), 'missing');
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
assert.equal(bridge.buttonPresentation('missing').label, 'Application not installed');
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
assert.equal(bridge.buttonPresentation('missing').label, 'Application non installée');
assert.match(bridge.requestErrorMessage({ errorCode: 'authentication_required' }), /Reconnectez votre compte/);
delete globalThis.chrome;

const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'browser-extension', 'manifest.json'), 'utf8'));
assert.equal(manifest.default_locale, 'en');
assert.equal(manifest.version, '1.8.1');
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
const nativePayloads = [];
const runtime = {
  getManifest: () => manifest,
  onInstalled: { addListener() {} },
  onStartup: { addListener() {} },
  onMessage: { addListener(listener) { onMessage = listener; } },
  sendNativeMessage(host, payload, callback) {
    assert.equal(host, 'local.jellyfin_vlc_bridge');
    nativePayloads.push(payload);
    this.lastError = transportError;
    callback(nativeResponse);
    this.lastError = null;
  }
};
vm.runInNewContext(backgroundScript, {
  JellyfinVlcBridge: bridge,
  importScripts() {},
  chrome: { runtime, tabs: { create() { throw new Error('Unexpected download tab'); } } }
});
function relay(message) {
  let result;
  assert.equal(onMessage(message, {}, response => { result = response; }), true);
  assert.ok(result, 'The native result must reach the content script');
  return result;
}
assert.equal(relay({ type: 'status' }).response.bridgeVersion, '1.18.1');
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
assert.equal(nativePayloads.at(-1).extensionVersion, '1.8.1');

console.log('OK  Extension Chrome bilingue avec choix de version du média');
