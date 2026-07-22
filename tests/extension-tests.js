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

console.log('OK  États et liens de l’extension Chrome');
