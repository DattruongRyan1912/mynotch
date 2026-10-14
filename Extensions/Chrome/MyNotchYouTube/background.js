/*
 * MyNotch YouTube Bridge: service worker.
 *
 * Receives protocol messages from the content script, validates them once more and passes them
 * to the native host through bridge.js. All connection and relay logic lives in bridge.js; this
 * file only wires it to the chrome.* APIs. The worker connects to the host as soon as it starts
 * and reports short diagnostic events (no titles, URLs or ids) to the host as `diag` messages.
 * After an install or an update it also injects the content scripts into the YouTube tabs that
 * were already open, which Chrome does not do on its own, and it says whether Chrome withholds
 * the extension's access to YouTube (site access "On click"), injecting once that is granted.
 */
importScripts("captions.js", "bridge.js");

(function () {
  "use strict";

  var C = self.__mynotchCaptions;
  var B = self.__mynotchBridge;

  function log(text) {
    console.info("[MyNotch YouTube Bridge] " + text);
  }

  var bridge = B.createBridge({
    connectNative: function (name) {
      return chrome.runtime.connectNative(name);
    },
    lastError: function () {
      var error = chrome.runtime.lastError;
      return error && error.message ? error.message : "";
    },
    now: function () {
      return Date.now();
    },
    log: function (text) {
      console.warn("[MyNotch YouTube Bridge] " + text);
    },
    errorCode: C.errorCode,
    buildDiag: C.buildDiag
  });

  var relay = B.createRelay({
    bridge: bridge,
    captions: C,
    ownId: chrome.runtime.id,
    now: function () {
      return Date.now();
    },
    version: chrome.runtime.getManifest().version,
    log: log
  });

  var injector = B.createInjector({
    manifest: chrome.runtime.getManifest(),
    queryTabs: function (query) {
      return chrome.tabs.query(query);
    },
    executeScript: function (injection) {
      return chrome.scripting.executeScript(injection);
    },
    report: relay.report,
    log: log
  });

  var access = B.createAccessWatcher({
    manifest: chrome.runtime.getManifest(),
    contains: function (query) {
      return chrome.permissions.contains(query);
    },
    report: relay.reportState,
    onGranted: function () {
      injector.injectIntoOpenTabs();
    },
    log: log
  });

  // Registered synchronously, as MV3 requires for events that wake the worker.
  chrome.runtime.onInstalled.addListener(function (details) {
    injector.onInstalled(details);
  });
  chrome.permissions.onAdded.addListener(function () {
    access.onChanged();
  });
  chrome.permissions.onRemoved.addListener(function () {
    access.onChanged();
  });

  chrome.runtime.onMessage.addListener(function (message, sender, sendResponse) {
    relay.onMessage(message, sender);
    // An explicit acknowledgement, so the sender's promise always resolves: a listener that never
    // answers can make Chrome report "message port closed before a response was received", which
    // the content script would then count as a failed send.
    if (typeof sendResponse === "function") sendResponse(true);
  });

  relay.start();
  access.start();
})();
