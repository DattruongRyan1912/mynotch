/*
 * MyNotch Web Companion: content script (isolated world).
 *
 *  - Accepts `captions` messages from page.js (same window, same origin, bridge source tag),
 *    re-validates them and relays them to the service worker.
 *  - Tracks the video id and the main <video>, and reports `playback` (on play, pause, seeked,
 *    ratechange, video change and every 5 s while playing) and `clear` (video change, leaving
 *    the watch page, captions button turned off).
 *  - Reports its own health as `diag` events (start, video found/missing, CC state, send errors,
 *    a 30 s "alive" line, exceptions of the 1 s tick) and relays the page script's `diag` events.
 *    Diag events are fixed codes plus numbers and booleans: no titles, URLs or video ids.
 *  - Does nothing outside www.youtube.com (the manifest also runs it on other pages, for the media tab script's sake).
 *  - Carries out the two commands the app can give through the service worker, `next` and `previous`,
 *    the way a user would, and only ever by clicking: next clicks the player's next button, else a link to
 *    another video of YouTube itself (the next button's own, even hidden, the first of "Up next" in the
 *    sidebar, the end screen's); previous clicks the player's previous button, else restarts a video that
 *    is more than 3 s in, else goes back when the page before is a watch page. It never makes up keyboard
 *    events, follows no address that is not another video of this site, and says what happened as a
 *    `content-command` diag (how, or why not: fixed words, never an address or a title).
 *
 * Only the fields of the shared protocol are ever sent; no URLs, no cookies, nothing else.
 */
(function (root) {
  "use strict";

  // The manifest runs the isolated scripts on every page, because the media tab script (tabs.js) shares their entry, but this one
  // is the YouTube bridge's: anywhere else it does nothing, and not even a diagnostic.
  if (!root.location || root.location.origin !== "https://www.youtube.com") return;

  var C = root.__mynotchCaptions;
  var STARTED = Symbol.for("io.lucasvu.mynotch.yt.content");
  // What the media tab script (tabs.js) calls for a next or a previous in a YouTube tab: the clicks below, `(action) => boolean`.
  var SKIP = Symbol.for("io.lucasvu.mynotch.tab.skip");
  if (!C) {
    reportMissingLibrary();
    return;
  }
  // The scripts can run again in a tab that already has a copy: the background script injects them
  // into the open YouTube tabs after the extension is installed, updated or reloaded, because Chrome
  // only injects content scripts into pages that load afterwards. A copy that is still alive keeps
  // the tab (one set of timers, listeners and messages); one whose extension context is gone, or
  // that has shut down, is stopped and replaced. Anything else under the key (a plain `true` left
  // by an older version of this script, which cannot be asked) is treated as an orphan.
  var previous = root[STARTED];
  if (previous && typeof previous.isAlive === "function") {
    if (previous.isAlive()) return;
    previous.stop();
  }

  /**
   * Without the captions library nothing can be validated or built, so this one fixed diagnostic goes
   * out as it is. It exists so that a missing library (Chrome injects a file listed for two worlds
   * only once, so captions.js never reached this world) shows in the bridge log instead of nothing.
   */
  function reportMissingLibrary() {
    try {
      var result = root.chrome.runtime.sendMessage({ v: 1, type: "diag", where: "content", event: "content-no-lib" });
      if (result && typeof result.then === "function") result.then(noop, noop);
    } catch (error) {
      /* the extension context may be gone as well */
    }
  }

  function noop() {}

  var TICK_MS = 1000;
  var NEXT_BUTTON = ".ytp-next-button";
  var PREVIOUS_BUTTON = ".ytp-prev-button";
  // Links to other videos where YouTube lists what follows: "Up next" in the watch page's sidebar (an old and a newer layout), and the end screen.
  var UPNEXT_LINKS =
    'ytd-watch-next-secondary-results-renderer a#thumbnail[href^="/watch"], ' +
    'ytd-watch-next-secondary-results-renderer ytd-compact-video-renderer a[href^="/watch"], ' +
    'ytd-watch-next-secondary-results-renderer yt-lockup-view-model a[href^="/watch"]';
  var ENDSCREEN_LINKS = '.ytp-autonav-endscreen-upnext-container a[href^="/watch"], .ytp-endscreen-content a[href^="/watch"]';
  var WATCH_VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;
  var MAX_HREF = 2048;
  // What YouTube's own "previous" does: past this many seconds it restarts the video instead of going back.
  var RESTART_AFTER_SECONDS = 3;
  var HEARTBEAT_MS = 5000;
  // After a navigation document.title can still hold the previous video's title for a moment.
  var STALE_TITLE_MS = 3000;
  // How long a track for a video other than the page's current one is kept (see onPageMessage).
  var HELD_CAPTIONS_MS = 10000;
  var ALIVE_MS = 30000;
  var DIAG_WINDOW_MS = 5000;
  var VIDEO_EVENTS = ["play", "pause", "seeked", "ratechange", "ended", "playing"];

  var doc = root.document;
  var state = {
    videoId: null,
    video: null,
    cc: "unknown", // "on" | "off" | "unknown", from the captions button
    captions: null, // latest captions message of the current video, resent after a clear
    held: null, // { message, at }: one track that arrived before the page switched to its video
    clearedId: null, // video id whose captions were last cleared and not sent again since
    lastPlaying: null, // the `playing` value of the last playback message
    lastSentAt: 0,
    pending: false, // a playback message is waiting for a usable title
    lastTitle: "",
    staleTitle: "",
    staleUntil: 0,
    videoReported: null, // whether the last diag said the main <video> was found (true) or missing
    lastAliveAt: Date.now(),
    sendErrors: 0, // failed sends since the last report
    sendErrorCode: "", // code of the latest failure, reported once a send works again
    messages: null, // chrome.runtime.onMessage, where the command listener is registered
    timer: 0,
    stopped: false
  };

  var allowDiag = C.createDiagLimiter(function () {
    return Date.now();
  }, DIAG_WINDOW_MS);

  function send(message) {
    var clean = C.validateMessage(message);
    if (clean) transmit(clean, clean.type !== "diag");
  }

  /** Hands a validated message to the service worker; failures are recorded, never thrown. */
  function transmit(clean, regular) {
    try {
      var result = root.chrome.runtime.sendMessage(clean);
      if (result && typeof result.then === "function") {
        result.then(onDelivered, function (error) {
          onSendFailure(error, regular);
        });
      } else {
        onDelivered();
      }
    } catch (error) {
      onSendFailure(error, regular);
    }
  }

  function onSendFailure(error, regular) {
    // "Extension context invalidated" after a reload or update: this copy is orphaned.
    if (!root.chrome || !root.chrome.runtime || !root.chrome.runtime.id) {
      shutdown();
      return;
    }
    if (!regular) return; // a failing channel is not used to report its own failure
    state.sendErrors += 1;
    state.sendErrorCode = C.errorCode(error && error.message);
  }

  /** The channel works again: report what failed in the meantime (once). */
  function onDelivered() {
    if (state.sendErrors === 0) return;
    var event = "content-send-error " + state.sendErrorCode + " count=" + state.sendErrors;
    state.sendErrors = 0;
    state.sendErrorCode = "";
    diag(event);
  }

  /**
   * One of the content script's own diagnostic events (rate limited). The answer to a command is not: the app waits
   * for one per command, and takes the lack of one for a host or an extension that does not know commands.
   */
  function diag(event, answersCommand) {
    if (answersCommand !== true && !allowDiag(event)) return;
    var message = C.buildDiag("content", event);
    if (message) transmit(message, false);
  }

  function sendClear(videoId) {
    if (!videoId) return;
    state.clearedId = videoId;
    send({ v: 1, type: "clear", videoId: videoId });
  }

  function findVideo() {
    return (
      doc.querySelector("video.html5-main-video") ||
      doc.querySelector("#movie_player video") ||
      doc.querySelector("#shorts-player video") ||
      doc.querySelector("video")
    );
  }

  /** An advert runs in the main player: the video time is the ad's time, and the player's buttons are not for the content. */
  function isAdShowing() {
    var player = doc.getElementById("movie_player");
    return Boolean(player && player.classList && player.classList.contains("ad-showing"));
  }

  function isPlaying(video) {
    if (!video || video.paused || video.ended) return false;
    return !isAdShowing();
  }

  function sendPlayback() {
    var video = state.video;
    var videoId = state.videoId;
    if (!video || !videoId) return;
    var time = video.currentTime;
    if (typeof time !== "number" || !isFinite(time)) return;
    var title = C.cleanTitle(doc.title);
    var now = Date.now();
    // Not ready yet: bare "YouTube" is the page shell's title before the video's own title has
    // loaded, and right after a navigation document.title can still be the previous video's.
    var stale = state.staleTitle !== "" && title === state.staleTitle && now < state.staleUntil;
    if (!title || title === "YouTube" || stale) {
      state.pending = true; // the next tick tries again
      return;
    }
    state.pending = false;
    var playing = isPlaying(video);
    state.lastTitle = title;
    state.lastSentAt = now;
    state.lastPlaying = playing;
    send({
      v: 1,
      type: "playback",
      videoId: videoId,
      title: title,
      time: time,
      playing: playing,
      rate: video.playbackRate
    });
  }

  function onVideoChange(videoId) {
    var previous = state.videoId;
    if (previous === videoId) return;
    sendClear(previous);
    state.videoId = videoId;
    state.cc = "unknown";
    state.videoReported = null;
    if (state.captions && state.captions.videoId !== videoId) state.captions = null;
    state.staleTitle = state.lastTitle;
    state.staleUntil = Date.now() + STALE_TITLE_MS;
    sendPlayback();
    releaseHeldCaptions(videoId);
  }

  function deliverCaptions(message) {
    state.captions = message;
    state.clearedId = null;
    send(message);
  }

  /**
   * The held track goes out when the page has switched to its video (and it is not too old),
   * and is discarded when the page switched to a different video. Leaving for a page without a
   * video id (videoId null) keeps it until it expires.
   */
  function releaseHeldCaptions(videoId) {
    var held = state.held;
    if (!held || !videoId) return;
    state.held = null;
    if (held.message.videoId === videoId && Date.now() - held.at <= HELD_CAPTIONS_MS) deliverCaptions(held.message);
  }

  function unbindVideo() {
    var video = state.video;
    if (!video) return;
    for (var i = 0; i < VIDEO_EVENTS.length; i++) video.removeEventListener(VIDEO_EVENTS[i], sendPlayback);
    state.video = null;
  }

  function bindVideo() {
    var video = findVideo();
    if (video === state.video) return;
    unbindVideo();
    state.video = video;
    if (!video) return;
    for (var i = 0; i < VIDEO_EVENTS.length; i++) video.addEventListener(VIDEO_EVENTS[i], sendPlayback);
    sendPlayback();
  }

  function checkCaptionsButton() {
    if (!state.videoId) return;
    var button = doc.querySelector(".ytp-subtitles-button");
    var pressed = button ? button.getAttribute("aria-pressed") : null;
    var next = pressed === "true" ? "on" : pressed === "false" ? "off" : "unknown";
    if (next === "unknown" || next === state.cc) return;
    state.cc = next;
    diag("content-cc " + next);
    if (next === "off") {
      sendClear(state.videoId);
    } else if (state.clearedId === state.videoId && state.captions && state.captions.videoId === state.videoId) {
      // The captions were cleared (CC off, or the page was hidden) and the player may reuse its
      // cached track instead of fetching it again, so send our copy.
      state.clearedId = null;
      send(state.captions);
    }
  }

  function tick() {
    try {
      onVideoChange(C.videoIdFromUrl(root.location.href));
      bindVideo();
      reportVideoPresence();
      checkCaptionsButton();
      if (state.held && Date.now() - state.held.at > HELD_CAPTIONS_MS) state.held = null;
      if (state.video && state.videoId) {
        var playing = isPlaying(state.video);
        var due = playing && Date.now() - state.lastSentAt >= HEARTBEAT_MS;
        // `playing` can change without a media event (the ad-showing class drops after the last one).
        if (state.pending || due || playing !== state.lastPlaying) sendPlayback();
      }
      reportAlive();
    } catch (error) {
      // A failed tick must not stop the next one, but it must not be silent either.
      diag("content-tick-error " + C.errorCode((error && error.name ? error.name + " " : "") + (error && error.message)));
    }
  }

  /** Reports once per video whether the main <video> element was found. */
  function reportVideoPresence() {
    if (!state.videoId) return;
    var present = state.video !== null;
    if (present === state.videoReported) return;
    state.videoReported = present;
    diag(present ? "content-video-found" : "content-video-missing");
  }

  function reportAlive() {
    var now = Date.now();
    if (now - state.lastAliveAt < ALIVE_MS) return;
    state.lastAliveAt = now;
    diag(
      "content-alive videoid-present=" + (state.videoId !== null) + " playing=" + (state.video !== null && isPlaying(state.video))
    );
  }

  // ---- commands from the service worker ---------------------------------------------------------------

  /** A button the user could press: there, not disabled, not hidden (display: none leaves it no boxes at all). */
  function isUsable(button) {
    if (!button) return false;
    if (button.hidden === true || button.disabled === true) return false;
    if (typeof button.getAttribute === "function" && button.getAttribute("aria-disabled") === "true") return false;
    if (typeof button.getClientRects === "function" && button.getClientRects().length === 0) return false;
    return true;
  }

  function clickPlayerButton(selector) {
    var button = doc.querySelector(selector);
    if (!isUsable(button)) return false;
    button.click();
    return true;
  }

  /** How a command went: carried out, and how (a fixed word), or not, and why (a fixed word). */
  function done(via) {
    return { ok: true, via: via };
  }

  function failed(reason) {
    return { ok: false, reason: reason };
  }

  /** The id of the video a watch address is for, when it is one of this site's own (relative addresses are this page's); else null. */
  function watchIdOf(address) {
    if (typeof address !== "string" || address.length === 0 || address.length > MAX_HREF) return null;
    var url;
    try {
      url = new URL(address, root.location.href);
    } catch (error) {
      return null;
    }
    if (url.origin !== root.location.origin || url.pathname !== "/watch") return null;
    var id = url.searchParams.get("v");
    return id !== null && WATCH_VIDEO_ID.test(id) ? id : null;
  }

  /**
   * What clicking `link` would do: "ok" it goes to another video of this site, "same" it goes to the video that plays, "refused" it goes
   * anywhere else (another site, another page, no video id, a new window), "none" it is no link at all.
   */
  function linkKind(link) {
    if (!link || typeof link.getAttribute !== "function") return "none";
    var address = link.getAttribute("href");
    if (typeof address !== "string" || address.length === 0) return "none";
    var target = link.getAttribute("target");
    if (typeof target === "string" && target !== "" && target !== "_self") return "refused";
    var id = watchIdOf(address);
    if (id === null) return "refused";
    return id === watchIdOf(root.location.href) ? "same" : "ok";
  }

  /** The first of the links the selector finds that goes to another video; `scan.refused` says if any went somewhere it must not. */
  function firstVideoLink(selector, scan) {
    var links = doc.querySelectorAll(selector);
    for (var i = 0; i < links.length; i++) {
      var kind = linkKind(links[i]);
      if (kind === "ok") return links[i];
      if (kind === "refused") scan.refused = true;
    }
    return null;
  }

  /**
   * Next: the player's next button; else, when that button (hidden, as it is for a video that is in no playlist) is a link to another
   * video, that link; else the first of "Up next" in the sidebar; else the end screen's. Every step is a click on a link that goes to
   * another video of YouTube itself, which the page follows without loading itself again.
   */
  function goToNext() {
    var button = doc.querySelector(NEXT_BUTTON);
    if (isUsable(button)) {
      button.click();
      return done("button");
    }
    var scan = { refused: false };
    var own = linkKind(button);
    var disabled = button && (button.disabled === true || (typeof button.getAttribute === "function" && button.getAttribute("aria-disabled") === "true"));
    if (own === "ok" && !disabled) {
      button.click();
      return done("href");
    }
    if (own === "refused") scan.refused = true;
    var upNext = firstVideoLink(UPNEXT_LINKS, scan);
    if (upNext) {
      upNext.click();
      return done("upnext");
    }
    var endScreen = firstVideoLink(ENDSCREEN_LINKS, scan);
    if (endScreen) {
      endScreen.click();
      return done("endscreen");
    }
    return failed(scan.refused ? "refused" : "none");
  }

  /** Whether the page before this one in the history is the watch page of another video of this site (the Navigation API tells, for its own origin). */
  function previousEntryIsAnotherVideo() {
    var navigation = root.navigation;
    if (!navigation || navigation.canGoBack !== true || !navigation.currentEntry || typeof navigation.entries !== "function") return false;
    var before = navigation.entries()[navigation.currentEntry.index - 1];
    var id = before ? watchIdOf(before.url) : null;
    return id !== null && id !== watchIdOf(root.location.href);
  }

  /**
   * Previous: the player's previous button; without a usable one, restart a video that is past 3 s (what YouTube's own button does),
   * and go back one page in the history when the video has only just begun and the page before is a watch page.
   */
  function goToPrevious() {
    if (clickPlayerButton(PREVIOUS_BUTTON)) return done("button");
    var video = state.video || findVideo();
    var time = video ? video.currentTime : NaN;
    if (typeof time !== "number" || !isFinite(time)) return failed("none");
    if (time > RESTART_AFTER_SECONDS) {
      video.currentTime = 0;
      return done("restart");
    }
    if (previousEntryIsAnotherVideo() && root.history && typeof root.history.back === "function") {
      root.history.back();
      return done("history");
    }
    return failed("none");
  }

  /** What became of a command. Never throws: a page that changed under us is "unavailable". */
  function carryOut(action) {
    try {
      if (isAdShowing()) return failed("ad");
      return action === "next" ? goToNext() : goToPrevious();
    } catch (error) {
      return failed("error");
    }
  }

  function perform(action) {
    return carryOut(action).ok;
  }

  /**
   * chrome.runtime.onMessage: the service worker passes on a command of the app. Only the extension's own
   * worker (a sender without a tab) is listened to, and only the closed command set; anything else is
   * ignored. The answer is sent at once, so the worker's send always resolves.
   */
  function onRuntimeMessage(message, sender, sendResponse) {
    var own = root.chrome && root.chrome.runtime ? root.chrome.runtime.id : undefined;
    if (!own || !sender || sender.tab || sender.id !== own) return undefined;
    var command = C.validateCommand(message);
    if (!command) return undefined;
    var outcome = carryOut(command.action);
    diag("content-command " + command.action + (outcome.ok ? " ok via=" + outcome.via : " unavailable reason=" + outcome.reason), true);
    try {
      if (typeof sendResponse === "function") sendResponse({ ok: outcome.ok });
    } catch (error) {
      /* the worker stopped waiting */
    }
    return undefined;
  }

  function onPageMessage(event) {
    var message = C.acceptPageMessage(event, root, root.location.origin);
    if (!message) return;
    if (message.type === "diag") {
      if (allowDiag(message.event)) transmit(message, false); // from page.js, already validated
      return;
    }
    // The live URL decides (not state.videoId: the tick may not have run yet). A track for any
    // other video is only held, never relayed: the player can fetch the next video's captions just
    // before the address bar changes, but a late response of the previous video, a preview or
    // miniplayer track or a forged id must not reach the host, which would keep it with no clear
    // to ever remove it. One slot: a newer foreign track replaces the held one.
    if (message.videoId !== C.videoIdFromUrl(root.location.href)) {
      state.held = { message: message, at: Date.now() };
      return;
    }
    deliverCaptions(message);
  }

  function onPageHide() {
    sendClear(state.videoId);
    state.videoId = null;
    state.cc = "unknown";
  }

  /** chrome.runtime.onMessage when there is one to listen to. */
  function runtimeMessages() {
    var runtime = root.chrome && root.chrome.runtime;
    return runtime && runtime.onMessage && typeof runtime.onMessage.addListener === "function" ? runtime.onMessage : null;
  }

  /** Whether this copy still runs and the extension that injected it is still there. */
  function isAlive() {
    return !state.stopped && Boolean(root.chrome && root.chrome.runtime && root.chrome.runtime.id);
  }

  /** The tab script's next and previous: what a command of the app does, for the tab the user chose in MyNotch. */
  function skipHook(action) {
    return perform(action);
  }

  function shutdown() {
    state.stopped = true;
    // Only our own hook: a newer copy that replaced this one has put its own there.
    if (root[SKIP] === skipHook) delete root[SKIP];
    if (state.timer) root.clearInterval(state.timer);
    state.timer = 0;
    unbindVideo();
    root.removeEventListener("message", onPageMessage, false);
    root.removeEventListener("yt-navigate-finish", tick, true);
    root.removeEventListener("pagehide", onPageHide, false);
    try {
      if (state.messages) state.messages.removeListener(onRuntimeMessage);
    } catch (error) {
      /* the extension context is gone, and the listener with it */
    }
    state.messages = null;
  }

  root[STARTED] = { isAlive: isAlive, stop: shutdown };
  root[SKIP] = skipHook;
  state.messages = runtimeMessages();
  if (state.messages) state.messages.addListener(onRuntimeMessage);
  root.addEventListener("message", onPageMessage, false);
  root.addEventListener("yt-navigate-finish", tick, true);
  root.addEventListener("pagehide", onPageHide, false);
  state.timer = root.setInterval(tick, TICK_MS);
  diag("content-start");
  tick();
})(typeof globalThis !== "undefined" ? globalThis : self);
