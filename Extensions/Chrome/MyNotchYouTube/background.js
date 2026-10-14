/*
 * MyNotch YouTube Bridge: service worker.
 *
 * Receives protocol messages from the content script, validates them once more and passes them
 * to the native host through bridge.js. All connection and relay logic lives in bridge.js; this
 * file only wires it to the chrome.* APIs. The worker connects to the host as soon as it starts
 * and reports short diagnostic events (no titles, URLs or ids) to the host as `diag` messages.
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

  chrome.runtime.onMessage.addListener(function (message, sender, sendResponse) {
    relay.onMessage(message, sender);
    // An explicit acknowledgement, so the sender's promise always resolves: a listener that never
    // answers can make Chrome report "message port closed before a response was received", which
    // the content script would then count as a failed send.
    if (typeof sendResponse === "function") sendResponse(true);
  });

  relay.start();
})();
