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
 * forwards, and reports its own diagnostics (rate limited). It also takes the one message that
 * travels the other way, a command from the app (next or previous) that the native host writes to
 * its stdout, and passes it to the tab that last sent a playback message.
 *
 * createInjector() runs the manifest's content scripts in the YouTube tabs that were already open
 * when the extension was installed, updated or reloaded (Chrome only injects into pages that load
 * afterwards).
 *
 * createAccessWatcher() reports whether Chrome granted the extension access to YouTube. The user
 * can set the extension's site access to "On click", which withholds the host permission: Chrome
 * then injects no content script and the extension is silent. It also tells when that changes.
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
   * diagnostics errorCode(text) -> token and buildDiag(where, event) -> message | null. When
   * onHostMessage(message) is given, what the host writes to the current port is handed to it
   * (unchecked: the handler validates).
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
        if (deps.onHostMessage && opened.onMessage && typeof opened.onMessage.addListener === "function") {
          opened.onMessage.addListener(function (message) {
            if (port !== opened) return; // a late message of a port that was replaced
            try {
              deps.onHostMessage(message);
            } catch (e) {
              /* a failing handler must not disturb the connection */
            }
          });
        }
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

  /** The id of the tab a message came from, or null when it did not come from one. */
  function tabIdOf(sender) {
    var id = sender && sender.tab ? sender.tab.id : undefined;
    return typeof id === "number" && isFinite(id) && id >= 0 && Math.floor(id) === id ? id : null;
  }

  /**
   * Message handler of the service worker.
   * deps: bridge, captions (captions.js API), ownId, now() -> ms, version, log(text), and for commands
   * sendToTab(tabId, message) -> Promise (chrome.tabs.sendMessage to the tab's top frame).
   */
  function createRelay(deps) {
    var C = deps.captions;
    var allow = C.createDiagLimiter(deps.now, DIAG_WINDOW_MS);
    var states = {}; // kind -> the last state event sent by reportState
    var playbackTab = null; // the tab that last sent a playback message; in memory only, never stored

    /**
     * The answer to a command, as a diagnostic that is never rate limited: the app waits for one per command and
     * uses MediaRemote for a press that gets none.
     */
    function answer(event) {
      var message = C.buildDiag("sw", event);
      if (message) deps.bridge.handle(message);
    }

    /** The worker's own diagnostics: one event per kind every 5 s. */
    function report(event) {
      if (!allow(event)) return;
      var message = C.buildDiag("sw", event);
      if (message) deps.bridge.handle(message);
    }

    /**
     * A state report instead of an event: sent whenever its value differs from the last one sent,
     * with no 5 s limit, so a state that changes and changes back quickly is never left stale.
     * Repeating a value that reached the host sends nothing; one that could not be sent is tried again.
     */
    function reportState(event) {
      var kind = String(event).replace(/=\S*/g, "");
      if (states[kind] === event) return;
      var message = C.buildDiag("sw", event);
      if (!message) return;
      if (deps.bridge.handle(message)) states[kind] = event;
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
        else if (clean.event.indexOf("content-command ") === 0 || allow(clean.event)) deps.bridge.handle(clean);
        return;
      }
      report("sw-msg " + clean.type + (clean.type === "captions" ? " events=" + clean.events.length : ""));
      if (clean.type === "playback") {
        var tabId = tabIdOf(sender);
        if (tabId !== null) playbackTab = tabId;
      }
      deps.bridge.handle(clean);
    }

    /**
     * A message the native host wrote: the only thing it may say is a command from the app. It goes, as
     * the validated command and nothing else, to the tab that last sent playback; a tab that is gone
     * (or none yet) is dropped and reported, and nothing else is tried.
     */
    function onHostMessage(message) {
      var command = C.validateCommand(message);
      if (!command) {
        answer("sw-reject invalid command");
        return;
      }
      var tabId = playbackTab;
      if (tabId === null || typeof deps.sendToTab !== "function") {
        answer("sw-command-no-tab");
        return;
      }
      new Promise(function (resolve) {
        resolve(deps.sendToTab(tabId, command));
      }).then(undefined, function () {
        if (playbackTab === tabId) playbackTab = null;
        answer("sw-command-no-tab");
      });
    }

    return { start: start, onMessage: onMessage, onHostMessage: onHostMessage, report: report, reportState: reportState };
  }

  /** The manifest's content scripts as executeScript injections, in their declared order and worlds. */
  function injectionsOf(manifest) {
    var entries = (manifest && manifest.content_scripts) || [];
    return entries.map(function (entry) {
      return { files: entry.js.slice(), world: entry.world === "MAIN" ? "MAIN" : "ISOLATED" };
    });
  }

  /** Every URL pattern the manifest's content scripts match, once each. */
  function matchesOf(manifest) {
    var patterns = [];
    ((manifest && manifest.content_scripts) || []).forEach(function (entry) {
      entry.matches.forEach(function (pattern) {
        if (patterns.indexOf(pattern) < 0) patterns.push(pattern);
      });
    });
    return patterns;
  }

  /**
   * Injects the content scripts into the matching tabs that are already open, so the bridge does not
   * wait for the user to reload each YouTube tab after the extension was installed, updated or
   * reloaded. The scripts guard themselves against running twice (content.js and page.js).
   * deps: manifest, queryTabs(query) -> Promise<tab[]>, executeScript(injection) -> Promise,
   * report(event) for the `sw-inject` diagnostic, log(text).
   */
  function createInjector(deps) {
    var injections = injectionsOf(deps.manifest);

    /** The tab's scripts one after the other (the page's observer first); never rejects. */
    function injectTab(tab) {
      if (!tab || typeof tab.id !== "number") return Promise.resolve(false);
      var target = { tabId: tab.id }; // the top frame only, like the manifest (no all_frames)
      return injections
        .reduce(function (previous, injection) {
          return previous.then(function () {
            return deps.executeScript({ target: target, files: injection.files, world: injection.world });
          });
        }, Promise.resolve())
        .then(
          function () {
            return true;
          },
          function () {
            return false; // discarded tab, error page, tab closed in the meantime, ...
          }
        );
    }

    /** Resolves to { tabs, injected, failed }, or to null when the tabs could not be listed. */
    function injectIntoOpenTabs() {
      return new Promise(function (resolve) {
        resolve(deps.queryTabs({ url: matchesOf(deps.manifest) }));
      })
        .then(function (tabs) {
          return Promise.all(tabs.map(injectTab)).then(function (outcomes) {
            var injected = outcomes.filter(Boolean).length;
            var result = { tabs: tabs.length, injected: injected, failed: tabs.length - injected };
            deps.report("sw-inject tabs=" + result.tabs + " injected=" + result.injected + " failed=" + result.failed);
            return result;
          });
        })
        .catch(function () {
          deps.log("sw-inject could not list the open YouTube tabs");
          return null;
        });
    }

    /** chrome.runtime.onInstalled: only a new install or an update leaves tabs without the scripts. */
    function onInstalled(details) {
      var reason = details && details.reason;
      if (reason === "install" || reason === "update") return injectIntoOpenTabs();
      return undefined;
    }

    return { injectIntoOpenTabs: injectIntoOpenTabs, onInstalled: onInstalled };
  }

  /**
   * Reports `sw-access youtube=granted|withheld` and notices when access is granted later.
   * deps: manifest, contains(query) -> Promise<boolean> (chrome.permissions.contains),
   * report(event), onGranted() for access that was not there before, log(text).
   */
  function createAccessWatcher(deps) {
    var granted = null; // the last known answer: true, false, or null while unknown

    /** Reads the access and reports it. Resolves to true when it was not granted before and is now, null when unreadable. */
    function update() {
      return new Promise(function (resolve) {
        resolve(deps.contains({ origins: matchesOf(deps.manifest) }));
      }).then(
        function (answer) {
          var now = answer === true;
          var newlyGranted = now && granted !== true;
          granted = now;
          deps.report("sw-access youtube=" + (now ? "granted" : "withheld"));
          return newlyGranted;
        },
        function () {
          deps.log("sw-access could not read the site access");
          return null;
        }
      );
    }

    /** When the worker starts. */
    function start() {
      return update().then(function () {});
    }

    /** chrome.permissions.onAdded / onRemoved: the open tabs get the scripts as soon as access appears. */
    function onChanged() {
      return update().then(function (newlyGranted) {
        if (newlyGranted === true) deps.onGranted();
      });
    }

    return { start: start, onChanged: onChanged };
  }

  var api = {
    HOST_NAME: HOST_NAME,
    MIN_BACKOFF_MS: MIN_BACKOFF_MS,
    MAX_BACKOFF_MS: MAX_BACKOFF_MS,
    createBridge: createBridge,
    createRelay: createRelay,
    createInjector: createInjector,
    createAccessWatcher: createAccessWatcher,
    isTrustedSender: isTrustedSender
  };

  if (typeof module === "object" && module !== null && module.exports) {
    module.exports = api;
  } else {
    Object.defineProperty(root, "__mynotchBridge", { value: api, configurable: true, writable: true });
  }
})(typeof globalThis !== "undefined" ? globalThis : self);
