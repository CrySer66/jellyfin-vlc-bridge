'use strict';

const NATIVE_HOST = 'local.jellyfin_vlc_bridge';
const EXTENSION_VERSION = chrome.runtime.getManifest().version;

function sendNative(payload, callback) {
  chrome.runtime.sendNativeMessage(
    NATIVE_HOST,
    { ...payload, extensionVersion: EXTENSION_VERSION },
    response => {
      const error = chrome.runtime.lastError?.message;
      callback?.(error ? { ok: false, error } : { ok: Boolean(response?.accepted), response });
    }
  );
}

function sendHeartbeat(callback) {
  sendNative({ type: 'ping' }, callback);
}

chrome.runtime.onInstalled.addListener(() => sendHeartbeat());
chrome.runtime.onStartup.addListener(() => sendHeartbeat());

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === 'heartbeat') {
    sendHeartbeat(sendResponse);
    return true;
  }
  if (message?.type !== 'play' || !message.itemId) return false;
  sendNative({ type: 'play', itemId: message.itemId }, result => {
    sendResponse(result?.ok ? { ok: true } : { ok: false, error: result?.error });
  });
  return true;
});

sendHeartbeat();
