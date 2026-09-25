'use strict';

importScripts('shared.js');

const NATIVE_HOST = 'local.jellyfin_vlc_bridge';
const EXTENSION_VERSION = chrome.runtime.getManifest().version;
const LINKS = globalThis.JellyfinVlcBridge.links;

function sendNative(payload, callback) {
  let finished = false;
  let timer;
  const finish = result => {
    if (finished) return;
    finished = true;
    if (timer) clearTimeout(timer);
    callback?.(result);
  };
  // A ping should be quick even when the native process fails to reply.
  // Playback requests are deliberately not timed out: a late launch must not
  // invite a second click and create duplicate VLC playback.
  if (payload.type === 'ping') {
    timer = setTimeout(() => finish({ ok: false, errorCode: 'native_timeout' }), 10000);
  }
  try {
    chrome.runtime.sendNativeMessage(
      NATIVE_HOST,
      { ...payload, extensionVersion: EXTENSION_VERSION },
      response => {
        const error = chrome.runtime.lastError?.message;
        finish(error
          ? { ok: false, error, errorCode: globalThis.JellyfinVlcBridge.nativeErrorCode(error) }
          : {
            ok: response?.accepted === true,
            response,
            error: response?.error,
            errorCode: response?.errorCode
          });
      }
    );
  } catch (error) {
    finish({ ok: false, error: error.message, errorCode: globalThis.JellyfinVlcBridge.nativeErrorCode(error) });
  }
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
  if (message?.type === 'inspect' && message.itemId) {
    sendNative({ type: 'inspect', itemId: message.itemId, scope: message.scope || 'auto' }, result => {
      sendResponse(result?.ok
        ? { ok: true, inspection: result.response }
        : { ok: false, error: result?.error, errorCode: result?.errorCode });
    });
    return true;
  }
  if (message?.type === 'preferences-get') {
    sendNative({ type: 'preferences-get' }, result => {
      sendResponse(result?.ok
        ? { ok: true, preferences: result.response }
        : { ok: false, error: result?.error, errorCode: result?.errorCode });
    });
    return true;
  }
  if (message?.type === 'preferences-save') {
    sendNative({
      type: 'preferences-save',
      rememberChoices: Boolean(message.rememberChoices),
      startMode: message.startMode,
      itemType: message.itemType,
      scope: message.scope
    }, result => {
      sendResponse(result?.ok
        ? { ok: true, preferences: result.response }
        : { ok: false, error: result?.error, errorCode: result?.errorCode });
    });
    return true;
  }
  if (message?.type !== 'play' || !message.itemId) return false;
  sendNative({
    type: 'play',
    itemId: message.itemId,
    scope: message.scope || 'auto',
    startMode: message.startMode || 'resume',
    mediaSourceId: message.mediaSourceId || ''
  }, result => {
    sendResponse(result?.ok ? { ok: true } : { ok: false, error: result?.error, errorCode: result?.errorCode });
  });
  return true;
});

sendHeartbeat();
