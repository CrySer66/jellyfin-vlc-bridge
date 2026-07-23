'use strict';

const assert = require('node:assert/strict');
const bridge = require('../browser-extension/shared.js');

assert.equal(bridge.links.repository, 'https://github.com/CrySer66/jellyfin-vlc-bridge');
assert.equal(bridge.links.latestRelease, 'https://github.com/CrySer66/jellyfin-vlc-bridge/releases/latest');
assert.equal(bridge.availabilityFromResult({ ok: true }), 'ready');
assert.equal(bridge.availabilityFromResult({ ok: false }), 'missing');
assert.equal(bridge.availabilityFromResult(undefined), 'missing');
assert.equal(bridge.buttonPresentation('ready').label, 'Lire avec VLC');
assert.equal(bridge.buttonPresentation('missing').label, 'Application non installée');
assert.equal(bridge.buttonPresentation('missing').disabled, false);
assert.equal(bridge.buttonPresentation('checking').disabled, true);
assert.equal(bridge.buttonPresentation('reload').label, 'Recharger Jellyfin');
assert.equal(bridge.formatDuration(42 * 60), '42 min');
assert.equal(bridge.formatDuration(2 * 3600 + 13 * 60), '2 h 13 min');
assert.equal(bridge.formatDuration(59 * 60 + 40), '1 h');
assert.deepEqual(bridge.scopeChoices('Episode').map(choice => choice.value), ['following', 'single']);
assert.deepEqual(bridge.scopeChoices('Series').map(choice => choice.value), ['following', 'all']);
assert.deepEqual(bridge.scopeChoices('BoxSet').map(choice => choice.value), ['following', 'all']);
assert.deepEqual(bridge.scopeChoices('Movie').map(choice => choice.value), ['single']);

console.log('OK  États et liens de l’extension Chrome');
