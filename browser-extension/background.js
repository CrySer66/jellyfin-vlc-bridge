'use strict';

importScripts('shared.js');

const NATIVE_HOST = 'local.jellyfin_vlc_bridge';
const EXTENSION_VERSION = chrome.runtime.getManifest().version;
const LINKS = globalThis.JellyfinVlcBridge.links;

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
  if (message?.type === 'heartbeat' || message?.type === 'status') {
    sendHeartbeat(sendResponse);
    return true;
  }
  if (message?.type === 'open-download') {
    chrome.tabs.create({ url: LINKS.latestRelease });
    sendResponse({ ok: true });
    return false;
  }
  if (message?.type === 'open-github') {
    chrome.tabs.create({ url: LINKS.repository });
    sendResponse({ ok: true });
    return false;
  }
  if (message?.type !== 'play' || !message.itemId) return false;
  sendNative({ type: 'play', itemId: message.itemId }, result => {
    sendResponse(result?.ok ? { ok: true } : { ok: false, error: result?.error });
  });
  return true;
});

sendHeartbeat();
