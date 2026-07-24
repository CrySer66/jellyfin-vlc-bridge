'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
require('../browser-extension/i18n.js');
const bridge = require('../browser-extension/shared.js');

assert.equal(bridge.links.repository, 'https://github.com/CrySer66/jellyfin-vlc-bridge');
assert.equal(bridge.links.latestRelease, 'https://github.com/CrySer66/jellyfin-vlc-bridge/releases/latest');
assert.equal(bridge.availabilityFromResult({ ok: true }), 'ready');
assert.equal(bridge.availabilityFromResult({ ok: false }), 'missing');
assert.equal(bridge.availabilityFromResult(undefined), 'missing');
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
delete globalThis.chrome;

const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'browser-extension', 'manifest.json'), 'utf8'));
assert.equal(manifest.default_locale, 'en');
assert.equal(manifest.version, '1.7.0');
assert.equal(manifest.name, '__MSG_extensionName__');
assert.equal(manifest.content_scripts[0].js[0], 'i18n.js');

console.log('OK  Extension Chrome bilingue français/anglais');
