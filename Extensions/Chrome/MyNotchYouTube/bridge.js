/*
 * MyNotch YouTube Bridge: native-messaging connection manager used by the service worker.
 *
 * Connects once when the worker starts (start() in createRelay) and again whenever a message
 * arrives while there is no connection, forwards validated protocol messages to the native host,
 * keeps only the latest `captions` per video so they can be resent after a reconnect, and
 * retries with exponential backoff (2 s doubling to 60 s) only when new messages arrive. It never
 * schedules timers of its own and logs at most once per minute. Why the previous connection
 * failed is remembered and reported to the host as a `diag` event once a new connection exists.
 *
 * createRelay() is the message handler of the service worker: it checks the sender, validates,
 * forwards, and reports its own diagnostics (rate limited).
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
  var DIAG_WINDOW_MS = 5000;

  /**
   * deps: connectNative(name) -> port, lastError() -> string, now() -> ms, log(text), and for the
   * diagnostics errorCode(text) -> token and buildDiag(where, event) -> message | null.
   */
  function createBridge(deps) {
    var port = null;
    var connectedAt = 0;
    var failures = 0;
    var retryAt = 0;
    var lastLogAt = -Infinity;
    var storedCaptions = new Map(); // videoId -> latest captions message
    var lastFailure = null; // { reason, failures } of the last failed connection, reported once

    function note(text) {
      var now = deps.now();
      if (now - lastLogAt < LOG_INTERVAL_MS) return;
      lastLogAt = now;
      deps.log(text);
    }

    function scheduleRetry(reason) {
      failures += 1;
      lastFailure = { reason: typeof reason === "string" ? reason : "", failures: failures };
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
      announce();
      return port !== null;
    }

    /** First messages on a new connection: why the last one failed, then the stored captions. */
    function announce() {
      if (lastFailure) {
        var failure = lastFailure;
        lastFailure = null;
        var code = failure.reason && deps.errorCode ? deps.errorCode(failure.reason) : "disconnected";
        var diag = deps.buildDiag ? deps.buildDiag("sw", "sw-reconnect after=" + code + " failures=" + failure.failures) : null;
        if (diag && !post(diag)) return;
      }
      storedCaptions.forEach(function (stored) {
        if (port) post(stored);
      });
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
      if (fresh && message.type === "captions") return true; // sent with the stored captions
      return post(message);
    }

    /** Connects now unless a connection exists or the backoff has not elapsed. */
    function ensureConnected() {
      if (!port && deps.now() >= retryAt) connect();
      return port !== null;
    }

    function state() {
      return {
        connected: port !== null,
        failures: failures,
        retryAt: retryAt,
        storedCaptions: Array.from(storedCaptions.keys())
      };
    }

    return { handle: handle, ensureConnected: ensureConnected, state: state };
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

  /**
   * Message handler of the service worker.
   * deps: bridge, captions (captions.js API), ownId, now() -> ms, version, log(text).
   */
  function createRelay(deps) {
    var C = deps.captions;
    var allow = C.createDiagLimiter(deps.now, DIAG_WINDOW_MS);

    /** The worker's own diagnostics: one event per kind every 5 s. */
    function report(event) {
      if (!allow(event)) return;
      var message = C.buildDiag("sw", event);
      if (message) deps.bridge.handle(message);
    }

    /** Eager connection when the worker starts, then the first diagnostic. */
    function start() {
      deps.bridge.ensureConnected();
      var version = /^[0-9]{1,4}(?:\.[0-9]{1,4}){0,3}$/.test(deps.version) ? deps.version : "unknown";
      report("sw-start v=" + version);
      deps.log("sw-start v=" + version);
    }

    function onMessage(message, sender) {
      if (!isTrustedSender(sender, deps.ownId)) {
        report("sw-reject untrusted");
        return;
      }
      var clean = C.validateMessage(message);
      if (!clean) {
        report("sw-reject invalid " + C.typeWord(message));
        return;
      }
      if (clean.type === "diag") {
        // Content scripts only speak for themselves and the page script; "sw" events are ours.
        if (clean.where === "sw") report("sw-reject invalid diag");
        else if (allow(clean.event)) deps.bridge.handle(clean);
        return;
      }
      report("sw-msg " + clean.type + (clean.type === "captions" ? " events=" + clean.events.length : ""));
      deps.bridge.handle(clean);
    }

    return { start: start, onMessage: onMessage };
  }

  var api = {
    HOST_NAME: HOST_NAME,
    MIN_BACKOFF_MS: MIN_BACKOFF_MS,
    MAX_BACKOFF_MS: MAX_BACKOFF_MS,
    createBridge: createBridge,
    createRelay: createRelay,
    isTrustedSender: isTrustedSender
  };

  if (typeof module === "object" && module !== null && module.exports) {
    module.exports = api;
  } else {
    Object.defineProperty(root, "__mynotchBridge", { value: api, configurable: true, writable: true });
  }
})(typeof globalThis !== "undefined" ? globalThis : self);
