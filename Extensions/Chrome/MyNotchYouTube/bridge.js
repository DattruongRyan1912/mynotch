/*
 * MyNotch YouTube Bridge: native-messaging connection manager used by the service worker.
 *
 * Connects lazily (on the first message), forwards validated protocol messages to the native
 * host, keeps only the latest `captions` per video so they can be resent after a reconnect, and
 * reconnects with exponential backoff (2 s doubling to 60 s) only when new messages arrive.
 * It never schedules timers of its own and logs at most once per minute.
 *
 * Everything Chrome-specific is injected, so the logic runs under Node in the tests.
 */
(function (root) {
  "use strict";

  var HOST_NAME = "io.lucasvu.mynotch.youtube";
  var MIN_BACKOFF_MS = 2000;
  var MAX_BACKOFF_MS = 60000;
  // A connection that lived at least this long counts as a working one: the backoff starts over.
  var STABLE_MS = 10000;
  var LOG_INTERVAL_MS = 60000;
  var MAX_STORED_CAPTIONS = 8;
  var ALLOWED_PAGE_PREFIX = "https://www.youtube.com/";

  /**
   * deps: connectNative(name) -> port, lastError() -> string, now() -> ms, log(text).
   */
  function createBridge(deps) {
    var port = null;
    var connectedAt = 0;
    var failures = 0;
    var retryAt = 0;
    var lastLogAt = -Infinity;
    var storedCaptions = new Map(); // videoId -> latest captions message

    function note(text) {
      var now = deps.now();
      if (now - lastLogAt < LOG_INTERVAL_MS) return;
      lastLogAt = now;
      deps.log(text);
    }

    function scheduleRetry(reason) {
      failures += 1;
      retryAt = deps.now() + Math.min(MIN_BACKOFF_MS * Math.pow(2, failures - 1), MAX_BACKOFF_MS);
      note("native host unavailable" + (reason ? " (" + reason + ")" : ""));
    }

    function dropPort(reason) {
      port = null;
      if (deps.now() - connectedAt >= STABLE_MS) failures = 0;
      scheduleRetry(reason);
    }

    function connect() {
      var opened;
      try {
        opened = deps.connectNative(HOST_NAME);
        opened.onDisconnect.addListener(function () {
          var reason = deps.lastError(); // reading it also clears Chrome's "unchecked lastError"
          if (port === opened) dropPort(reason);
        });
      } catch (e) {
        scheduleRetry(e && e.message);
        return false;
      }
      port = opened;
      connectedAt = deps.now();
      return true;
    }

    function post(message) {
      try {
        port.postMessage(message);
        return true;
      } catch (e) {
        dropPort(e && e.message);
        return false;
      }
    }

    function remember(message) {
      storedCaptions.delete(message.videoId);
      storedCaptions.set(message.videoId, message);
      while (storedCaptions.size > MAX_STORED_CAPTIONS) {
        storedCaptions.delete(storedCaptions.keys().next().value);
      }
    }

    /**
     * Handles one already-validated protocol message. Returns true when it reached the port.
     * While the host is unreachable and the backoff has not elapsed the message is dropped;
     * captions are kept and go out right after the next successful connect.
     */
    function handle(message) {
      if (message.type === "captions") remember(message);
      else if (message.type === "clear") storedCaptions.delete(message.videoId);

      var fresh = false;
      if (!port) {
        if (deps.now() < retryAt) return false;
        if (!connect()) return false;
        fresh = true;
      }
      if (!fresh) return post(message);

      var sent = true;
      storedCaptions.forEach(function (stored) {
        if (sent && port) sent = post(stored);
      });
      if (message.type !== "captions" && sent && port) sent = post(message);
      return sent;
    }

    function state() {
      return {
        connected: port !== null,
        failures: failures,
        retryAt: retryAt,
        storedCaptions: Array.from(storedCaptions.keys())
      };
    }

    return { handle: handle, state: state };
  }

  /** Only messages from this extension's own content scripts on a youtube.com page are relayed. */
  function isTrustedSender(sender, ownId) {
    return Boolean(
      sender &&
        sender.id === ownId &&
        typeof sender.url === "string" &&
        sender.url.indexOf(ALLOWED_PAGE_PREFIX) === 0
    );
  }

  var api = {
    HOST_NAME: HOST_NAME,
    MIN_BACKOFF_MS: MIN_BACKOFF_MS,
    MAX_BACKOFF_MS: MAX_BACKOFF_MS,
    createBridge: createBridge,
    isTrustedSender: isTrustedSender
  };

  if (typeof module === "object" && module !== null && module.exports) {
    module.exports = api;
  } else {
    Object.defineProperty(root, "__mynotchBridge", { value: api, configurable: true, writable: true });
  }
})(typeof globalThis !== "undefined" ? globalThis : self);
