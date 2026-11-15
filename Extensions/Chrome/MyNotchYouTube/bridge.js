/*
 * MyNotch Web Companion: native-messaging connection manager used by the service worker.
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
 * Pages other than YouTube report their media too (tabs.js): the relay trusts such a report from this extension's own content
 * script in the top frame of any http(s) tab, adds the tab's id, and passes it on as `tab`; `tabgone` follows when the page
 * says it has no media or the tab is closed. The app's `tabcommand` goes to the tab it names, as the validated command.
 *
 * createInjector() runs the manifest's content scripts in the tabs that were already open
 * when the extension was installed, updated or reloaded (Chrome only injects into pages that load
 * afterwards), each entry only into the tabs its own match patterns name.
 *
 * createAccessWatcher() reports whether Chrome granted the extension access to YouTube (only YouTube: the captions and the
 * skip buttons need it, and the notice in MyNotch's settings is about that). The user
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
  // What the access notice is about: the extension's access to YouTube, whatever it has on other sites.
  var WATCHED_ORIGINS = ["https://www.youtube.com/*"];
  // The tabs with media the worker tells the app about at one time; a page beyond this is not shown.
  var MAX_TABS = 64;
  // A report from the same tab sooner than this after the last is dropped: the page's script already keeps a floor of 250 ms, and a
  // page can post to it as fast as it likes, so this is the second hop's own bound, whatever arrives.
  var MIN_TAB_GAP_MS = 200;
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

  function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
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
   * A report about media may come from this extension's own content script in any frame of a web page: a tab and an http(s)
   * address. A film site's player is often a frame of another site. The page itself cannot send one.
   */
  function isTrustedTabSender(sender, ownId) {
    return Boolean(
      sender &&
        sender.id === ownId &&
        typeof sender.url === "string" &&
        /^https?:\/\//.test(sender.url) &&
        tabIdOf(sender) !== null &&
        frameIdOf(sender) !== null
    );
  }

  /** The frame of its tab a message came from: 0 for the top frame (and for a sender that does not say). */
  function frameIdOf(sender) {
    var id = sender ? sender.frameId : undefined;
    if (id === undefined) return 0;
    return typeof id === "number" && isFinite(id) && id >= 0 && Math.floor(id) === id ? id : null;
  }

  /** The id of the tab a message came from, or null when it did not come from one. */
  function tabIdOf(sender) {
    var id = sender && sender.tab ? sender.tab.id : undefined;
    return typeof id === "number" && isFinite(id) && id >= 0 && Math.floor(id) === id ? id : null;
  }

  /**
   * Message handler of the service worker.
   * deps: bridge, captions (captions.js API), tabs (tabmessages.js API), ownId, now() -> ms, version, log(text), for commands
   * sendToTab(tabId, message) -> Promise (chrome.tabs.sendMessage to the tab's top frame) and for the sound getTab(tabId) -> Promise
   * (chrome.tabs.get; `audible` is not a field the `tabs` permission gates).
   */
  function createRelay(deps) {
    var C = deps.captions;
    var T = deps.tabs;
    var allow = C.createDiagLimiter(deps.now, DIAG_WINDOW_MS);
    var states = {}; // kind -> the last state event sent by reportState
    var playbackTab = null; // the tab that last sent a playback message; in memory only, never stored
    var mediaTabs = new Set(); // the tabs the app has been told about with `tab` and not yet `tabgone`; in memory only
    var lastTabAt = new Map(); // tabId -> when its latest report was passed on (the limiter's memory)
    var lastReports = new Map(); // tabId -> its latest valid report, to say again when Chrome says the tab is audible or not
    var audibleTabs = new Map(); // tabId -> whether Chrome says the tab makes sound; unknown until it says
    var mediaFrames = new Map(); // tabId -> the frame whose media the tab's reports are about (0, the top frame, for most pages)
    var pages = new Map(); // tabId -> { title, names, site } of the top frame, for the reports of a player in a frame of another site
    var waiting = new Map(); // tabId -> a frame's report held until the top frame says what the page is

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

    /** A tab's report that it has media, or none any more; never throws. */
    function onTabMessage(message, sender) {
      if (!isTrustedTabSender(sender, deps.ownId)) {
        report("sw-reject untrusted");
        return;
      }
      var tabId = tabIdOf(sender);
      var frameId = frameIdOf(sender);
      if (message.type === "tab-end") {
        if (!T.validateEnd(message)) report("sw-reject invalid tab");
        else if (!mediaFrames.has(tabId) || mediaFrames.get(tabId) === frameId) forgetTab(tabId);
        else if (waiting.has(tabId) && waiting.get(tabId).frameId === frameId) waiting.delete(tabId);
        return;
      }
      // Another frame of a tab whose media plays (an advert's frame next to the film's) takes the tab only when it plays and the
      // frame shown does not.
      var shown = mediaFrames.get(tabId);
      if (shown !== undefined && shown !== frameId) {
        var current = lastReports.get(tabId);
        if (!isObject(message) || message.state !== "playing" || (current && current.state === "playing")) return;
      }
      reportFrom(tabId, frameId, message);
    }

    function reportFrom(tabId, frameId, message) {
      if (frameId !== 0) {
        // A player in a frame: the page is the top frame's, its title (the one Chrome gives the system), names and site.
        var page = pages.get(tabId);
        if (!page) {
          var first = !waiting.has(tabId);
          waiting.set(tabId, { message: message, frameId: frameId });
          if (first) askPage(tabId);
          return;
        }
        message = Object.assign({}, message, { site: page.site, names: page.names, title: message.title || page.title });
      }
      acceptReport(tabId, frameId, message);
    }

    function acceptReport(tabId, frameId, message) {
      var clean = T.validateReport(message);
      if (!clean || !T.buildTab(tabId, clean, false)) {
        report("sw-reject invalid tab");
        return;
      }
      if (!mediaTabs.has(tabId) && mediaTabs.size >= MAX_TABS) return;
      // One report in a few hundred milliseconds from one tab; the page's script sends the newest state again at its next tick.
      var now = deps.now();
      var last = lastTabAt.get(tabId);
      if (last !== undefined && now >= last && now - last < MIN_TAB_GAP_MS) return;
      lastTabAt.set(tabId, now);
      mediaTabs.add(tabId);
      mediaFrames.set(tabId, frameId);
      lastReports.set(tabId, clean);
      if (!audibleTabs.has(tabId)) learnAudible(tabId);
      report("sw-msg tab");
      sendTab(tabId);
    }

    /**
     * Passes the tab's latest report on. A page that has no element of ours and only says through its Media Session that it plays is
     * not believed unless Chrome says the tab makes sound: any page can say that, and the one that says it last would take the
     * notch from the music the user is listening to. Without the sound it is told as paused.
     */
    function sendTab(tabId) {
      var clean = lastReports.get(tabId);
      if (!clean) return;
      var audible = audibleTabs.get(tabId) === true;
      var told = clean.element === false && !audible && clean.state === "playing" ? Object.assign({}, clean, { state: "paused" }) : clean;
      var tab = T.buildTab(tabId, told, audible);
      if (tab) deps.bridge.handle(tab);
    }

    /** What Chrome says of the tab's sound, asked once for a tab it has not said anything of yet (the answer after a restart of the worker too). */
    function learnAudible(tabId) {
      audibleTabs.set(tabId, false);
      if (typeof deps.getTab !== "function") return;
      new Promise(function (resolve) {
        resolve(deps.getTab(tabId));
      }).then(function (tab) {
        if (tab && typeof tab.audible === "boolean") onTabAudible(tabId, tab.audible);
      }, function () {
        /* a tab that is gone: the removal says so */
      });
    }

    /** chrome.tabs.onUpdated's `audible`, or the answer to `learnAudible`: the tab starts or stops making sound. */
    function onTabAudible(tabId, audible) {
      if (typeof tabId !== "number" || typeof audible !== "boolean") return;
      if (!mediaTabs.has(tabId)) {
        // Not a tab with media: what Chrome says of it is not kept (the map is bounded by the tabs the app has been told of).
        if (audible) askPage(tabId);
        return;
      }
      if (audibleTabs.get(tabId) === audible) return;
      audibleTabs.set(tabId, audible);
      sendTab(tabId);
    }

    /**
     * Asks the top frame of a tab what the page shows: its title, other names and site. Kept for the reports of a player in a frame
     * of another site, and told to the app for a tab that makes sound with no media of ours in it (for the search of a film's
     * subtitles by its original title).
     */
    function askPage(tabId) {
      if (typeof deps.sendToTab !== "function") return;
      new Promise(function (resolve) {
        resolve(deps.sendToTab(tabId, T.buildNamesRequest(), 0));
      }).then(function (answer) {
        var named = T.buildPageNames(tabId, answer);
        var title = isObject(answer) ? T.cleanText(answer.title, T.MAX_TITLE) : "";
        var held = waiting.get(tabId);
        waiting.delete(tabId);
        if (title) pages.set(tabId, { title: title, names: named ? named.names : "", site: T.cleanSite(answer.site) });
        if (named && !held) deps.bridge.handle(named);
        if (held && pages.has(tabId)) reportFrom(tabId, held.frameId, held.message);
      }, function () {
        waiting.delete(tabId); /* a page without the script (not http, or loading): nothing to say */
      });
    }

    /** The tab has no media any more, or is closed: the app is told once, and only about a tab it was told of. */
    function forgetTab(tabId) {
      lastTabAt.delete(tabId);
      lastReports.delete(tabId);
      audibleTabs.delete(tabId);
      mediaFrames.delete(tabId);
      pages.delete(tabId);
      waiting.delete(tabId);
      if (mediaTabs.delete(tabId)) tellGone(tabId);
    }

    function tellGone(tabId) {
      var gone = T.buildGone(tabId);
      if (gone) deps.bridge.handle(gone);
    }

    /** chrome.tabs.onRemoved. */
    function onTabRemoved(tabId) {
      if (typeof tabId === "number") forgetTab(tabId);
    }

    function isTabCommandAnswer(message) {
      return isObject(message) && message.type === "diag" && typeof message.event === "string" && message.event.indexOf("content-tabcommand ") === 0;
    }

    function onMessage(message, sender) {
      if (isObject(message) && (message.type === "tab-report" || message.type === "tab-end")) {
        onTabMessage(message, sender);
        return;
      }
      // What a media tab's script says of a command it was given may come from any page, and is not rate limited.
      if (isTabCommandAnswer(message) && isTrustedTabSender(sender, deps.ownId)) {
        var answered = C.validateMessage(message);
        if (answered && answered.where === "content") deps.bridge.handle(answered);
        else report("sw-reject invalid diag");
        return;
      }
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
      if (isObject(message) && message.type === "tabcommand") {
        onTabCommand(message);
        return;
      }
      if (isObject(message) && message.type === "subtitle") {
        onSubtitle(message);
        return;
      }
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

    /**
     * The app asks a tab to play, pause, seek or skip. The app only names tabs it was told about, so the worker does not
     * keep a list to check them against (it forgets everything when it restarts); the tab either has the media script,
     * which does it, or does not, and then the app is told that nothing took it and the tab is forgotten.
     */
    function onTabCommand(message) {
      var command = T.validateTabCommand(message);
      if (!command) {
        answer("sw-reject invalid tabcommand");
        return;
      }
      if (typeof deps.sendToTab !== "function") {
        answer("sw-tabcommand-no-tab");
        return;
      }
      if (command.tab === 0) {
        var targets = new Set(mediaTabs);
        if (typeof playbackTab === "number") targets.add(playbackTab);
        targets.forEach(function (tabId) {
          try {
            deps.sendToTab(tabId, command, mediaFrames.get(tabId) || 0);
          } catch (e) {}
        });
        return;
      }
      new Promise(function (resolve) {
        resolve(deps.sendToTab(command.tab, command, mediaFrames.get(command.tab) || 0));
      }).then(undefined, function () {
        // Only the answer: a tab that is frozen, discarded or loading may be fine, and the page says by itself when it is not (its next
        // report, or the tab's removal); dropping the chip for it would drop what the user pinned too.
        answer("sw-tabcommand-no-tab");
      });
    }

    /**
     * The app's subtitle line for a tab's film goes to the frame whose media the tab's reports are about, as the checked line only. A
     * tab the worker was not told of, or that cannot take it, is skipped: the line has a lifetime, the next one says it again.
     */
    function onSubtitle(message) {
      var line = T.validateSubtitle(message);
      if (!line) {
        answer("sw-reject invalid subtitle");
        return;
      }
      if (!mediaTabs.has(line.tab) || typeof deps.sendToTab !== "function") return;
      new Promise(function (resolve) {
        resolve(deps.sendToTab(line.tab, line, mediaFrames.get(line.tab) || 0));
      }).then(undefined, function () {
        /* a frame that is gone or loading */
      });
    }

    return {
      start: start,
      onMessage: onMessage,
      onHostMessage: onHostMessage,
      onTabRemoved: onTabRemoved,
      onTabAudible: onTabAudible,
      report: report,
      reportState: reportState
    };
  }

  /** The manifest's content scripts as executeScript injections, in their declared order and worlds, each with its own match patterns. */
  function injectionsOf(manifest) {
    var entries = (manifest && manifest.content_scripts) || [];
    return entries.map(function (entry) {
      return {
        files: entry.js.slice(),
        world: entry.world === "MAIN" ? "MAIN" : "ISOLATED",
        matches: entry.matches.slice(),
        allFrames: entry.all_frames === true
      };
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

  function escapeRegExp(text) {
    return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  }

  /**
   * Whether a Chrome match pattern (`<all_urls>`, or scheme://host/path with `*` for a scheme, a host or a run of the path,
   * and `*.` for a host and its subdomains) names `url`. The port and the fragment do not count, as in Chrome.
   */
  function matchesPattern(pattern, url) {
    var target;
    try {
      var parsed = new URL(url);
      target = { scheme: parsed.protocol.slice(0, -1), host: parsed.hostname, path: parsed.pathname + parsed.search };
    } catch (e) {
      return false;
    }
    if (pattern === "<all_urls>") return /^(?:https?|ftp|file)$/.test(target.scheme);
    var parts = /^(\*|https?|ftp|file):\/\/(\*|\*\.[^/*]+|[^/*]*)(\/.*)$/.exec(pattern);
    if (!parts) return false;
    if (parts[1] === "*" ? !/^https?$/.test(target.scheme) : parts[1] !== target.scheme) return false;
    var host = parts[2];
    if (host.indexOf("*.") === 0) {
      var base = host.slice(2);
      if (target.host !== base && !target.host.endsWith("." + base)) return false;
    } else if (host !== "*" && host !== target.host) {
      return false;
    }
    return new RegExp("^" + escapeRegExp(parts[3]).replace(/\\\*/g, ".*") + "$").test(target.path);
  }

  function matchesAny(patterns, url) {
    return patterns.some(function (pattern) {
      return matchesPattern(pattern, url);
    });
  }

  /**
   * Injects the content scripts into the matching tabs that are already open, so the bridge does not
   * wait for the user to reload each tab after the extension was installed, updated or
   * reloaded. Each entry of the manifest goes only into the tabs its own patterns name (the YouTube
   * scripts into YouTube tabs, the media tab scripts into any web page). The scripts guard themselves
   * against running twice (content.js, tabs.js and page.js).
   * deps: manifest, queryTabs(query) -> Promise<tab[]>, executeScript(injection) -> Promise,
   * report(event) for the `sw-inject` diagnostic, log(text).
   */
  function createInjector(deps) {
    var injections = injectionsOf(deps.manifest);

    /** The tab's scripts one after the other (the page's observer first); never rejects. */
    function injectTab(tab) {
      if (!tab || typeof tab.id !== "number") return Promise.resolve(false);
      // A tab whose address is not known (no access to it) cannot be told apart, so it gets what the manifest has.
      var mine = injections.filter(function (injection) {
        return typeof tab.url !== "string" || matchesAny(injection.matches, tab.url);
      });
      return mine
        .reduce(function (previous, injection) {
          return previous.then(function () {
            // The top frame only, or every frame where the manifest says so (all_frames).
            var target = injection.allFrames ? { tabId: tab.id, allFrames: true } : { tabId: tab.id };
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
          deps.log("sw-inject could not list the open tabs");
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
   * deps: contains(query) -> Promise<boolean> (chrome.permissions.contains),
   * report(event), onGranted() for access that was not there before, log(text).
   */
  function createAccessWatcher(deps) {
    var granted = null; // the last known answer: true, false, or null while unknown

    /** Reads the access and reports it. Resolves to true when it was not granted before and is now, null when unreadable. */
    function update() {
      return new Promise(function (resolve) {
        resolve(deps.contains({ origins: WATCHED_ORIGINS.slice() }));
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
    WATCHED_ORIGINS: WATCHED_ORIGINS,
    matchesPattern: matchesPattern,
    isTrustedSender: isTrustedSender,
    isTrustedTabSender: isTrustedTabSender
  };

  if (typeof module === "object" && module !== null && module.exports) {
    module.exports = api;
  } else {
    Object.defineProperty(root, "__mynotchBridge", { value: api, configurable: true, writable: true });
  }
})(typeof globalThis !== "undefined" ? globalThis : self);
