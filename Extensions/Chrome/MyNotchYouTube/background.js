/*
 * MyNotch YouTube Bridge: service worker.
 *
 * Receives protocol messages from the content script, validates them once more and passes them
 * to the native host through bridge.js. All connection logic lives in bridge.js.
 */
importScripts("captions.js", "bridge.js");

(function () {
  "use strict";

  var C = self.__mynotchCaptions;
  var B = self.__mynotchBridge;

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
    }
  });

  chrome.runtime.onMessage.addListener(function (message, sender) {
    if (!B.isTrustedSender(sender, chrome.runtime.id)) return;
    var clean = C.validateMessage(message);
    if (clean) bridge.handle(clean);
  });
})();
