/*
 * MyNotch YouTube Bridge: media tabs (content script, isolated world, any http or https page, top frame).
 *
 * Tells the service worker what the page's media is doing, so that MyNotch can show it next to the other sources that play
 * (Music, Spotify, other tabs) and control it. A page's media is known in one of two ways:
 *
 *  - As an element. The script listens for the media events of the document (play, pause, seeked, ...) in the capture phase, so a
 *    page with no media costs a few listeners and no timer. A media element counts when it plays and is not a muted or very short
 *    clip (autoplay banners, interface sounds), unless the page has put a title in its Media Session, which is a page saying
 *    "this is a player". It keeps counting while it is paused.
 *  - As a Media Session, for media that is no element of the document (an `Audio` the page keeps to itself, which no event of the
 *    document ever shows): a page whose Media Session has a title and says it plays or is paused. The page script (MAIN world)
 *    passes on what the session says, including where it says it is, and an element, when there is one, wins.
 *
 * It reports the title (the Media Session's, else the document's), the artist and album the Media Session names, the site (the host
 * name only, never a path or a URL), whether it plays, its position and length, its speed, and whether it is live. On a state
 * change at once, then every 5 s while it plays and every 30 s while it is paused (the app keeps a tab for a few minutes without
 * news, and expects a paused one to keep telling it so). A one-second tick runs only while something is being reported.
 *
 * It carries out the six commands of the app (play, pause, toggle, seek, next, previous): on the element when there is one, else
 * through the page's own Media Session handlers, which the page script calls. Next and previous are the page's own business: the
 * YouTube script offers its button clicks, and for any other page the page's handler is called, when the page has one.
 *
 * No artwork, no URL, no request of its own. Only the fields of `tab-report` (see tabmessages.js) are ever sent.
 */
(function (root) {
  "use strict";

  var C = root.__mynotchCaptions;
  var T = root.__mynotchTabs;
  var STARTED = Symbol.for("io.lucasvu.mynotch.tab.content");
  // The YouTube script (content.js) leaves its next/previous behind here: `(action) => boolean`.
  var SKIP = Symbol.for("io.lucasvu.mynotch.tab.skip");
  if (!C || !T) return;
  // Chrome can inject this again into a tab that has a copy (after the extension was updated or reloaded). A copy that is
  // alive keeps the tab; one whose extension is gone, or that has shut down, is stopped and replaced.
  var previous = root[STARTED];
  if (previous && typeof previous.isAlive === "function") {
    if (previous.isAlive()) return;
    previous.stop();
  }

  var TICK_MS = 1000;
  var PLAYING_HEARTBEAT_MS = 5000;
  var PAUSED_HEARTBEAT_MS = 30000;
  // A clip shorter than this is an interface sound or a loop, unless the page says it is a player.
  var MIN_SECONDS = 5;
  // A repeat of the same state is not sent again while the position is where it should be, within this many seconds.
  var SAME_POSITION_SECONDS = 0.5;
  var MEDIA_EVENTS = ["play", "playing", "pause", "ended", "emptied", "seeked", "ratechange", "loadedmetadata", "durationchange"];

  var doc = root.document;
  var state = {
    el: null, // the element being reported
    reported: false, // a report went out and no end since
    last: null, // { key, time, at } of the last report
    session: null, // what the page script last said of the Media Session, and when (see onPageMessage)
    timer: 0,
    messages: null, // chrome.runtime.onMessage, where the command listener is registered
    stopped: false
  };

  function noop() {}

  function isMedia(el) {
    var name = el && typeof el.tagName === "string" ? el.tagName.toUpperCase() : "";
    return (name === "VIDEO" || name === "AUDIO") && typeof el.play === "function";
  }

  function isPlaying(el) {
    return Boolean(el) && !el.paused && !el.ended;
  }

  function isConnected(el) {
    return el.isConnected !== false;
  }

  /** What the page's Media Session says, read live; else what the page script last told us. null when the page has no title in it. */
  function readSession() {
    try {
      var metadata = root.navigator && root.navigator.mediaSession ? root.navigator.mediaSession.metadata : null;
      var title = metadata ? T.cleanText(metadata.title, T.MAX_TITLE) : "";
      if (title) {
        return { title: title, artist: T.cleanText(metadata.artist, T.MAX_NAME), album: T.cleanText(metadata.album, T.MAX_NAME) };
      }
    } catch (error) {
      /* a page whose Media Session cannot be read */
    }
    return state.session && state.session.title ? state.session : null;
  }

  /** What the page says its media is doing: read live when it says so, else what the page script last told us ("playing", "paused" or "none"). */
  function sessionPlayback() {
    try {
      var live = root.navigator && root.navigator.mediaSession ? root.navigator.mediaSession.playbackState : "none";
      if (live === "playing" || live === "paused") return live;
    } catch (error) {
      /* a page whose Media Session cannot be read from here */
    }
    return state.session ? state.session.playback : "none";
  }

  /** The page's media is not an element we know, and its Media Session has a title and says it plays or is paused. */
  function isSessionActive() {
    return !state.el && readSession() !== null && sessionPlayback() !== "none";
  }

  /** Whether a media element is one to show: see the header. */
  function isEligible(el) {
    if (readSession()) return true;
    if (el.muted === true || el.volume === 0) return false;
    var duration = el.duration;
    return !(typeof duration === "number" && isFinite(duration) && duration < MIN_SECONDS);
  }

  function finite(value, fallback) {
    return typeof value === "number" && isFinite(value) ? value : fallback;
  }

  /** The report for the element, or null while there is no title to give (the page has not set one yet). */
  function buildElement(el) {
    var session = readSession();
    var title = session ? session.title : C.cleanTitle(doc.title);
    if (!title || title === "YouTube") return null;
    var duration = el.duration;
    var rate = finite(el.playbackRate, 1);
    return {
      v: 1,
      type: "tab-report",
      site: T.cleanSite(root.location.hostname),
      title: title,
      artist: session ? session.artist || "" : "",
      album: session ? session.album || "" : "",
      state: isPlaying(el) ? "playing" : "paused",
      time: Math.max(finite(el.currentTime, 0), 0),
      duration: typeof duration === "number" && isFinite(duration) && duration >= 0 ? duration : null,
      rate: rate > 0 && rate <= 16 ? rate : 1,
      live: duration === Infinity
    };
  }

  /**
   * The report for the page's Media Session: the position it last gave, carried on at the speed it gave while it plays, since the
   * session says it only when it changes. Without a position (many pages never set one) it is 0 of no length.
   */
  function buildSession() {
    var session = readSession();
    var playback = sessionPlayback();
    if (!session || playback === "none") return null;
    var given = state.session && state.session.position;
    var rate = given ? given.rate : 1;
    var time = 0;
    var duration = null;
    if (given) {
      duration = given.duration;
      var since = given.at !== null ? given.at : state.session.receivedAt;
      var elapsed = playback === "playing" ? Math.min(Math.max((Date.now() - since) / 1000, 0), T.MAX_SECONDS) * rate : 0;
      time = given.position + elapsed;
      if (duration !== null) time = Math.min(time, duration);
    }
    return {
      v: 1,
      type: "tab-report",
      site: T.cleanSite(root.location.hostname),
      title: session.title,
      artist: session.artist || "",
      album: session.album || "",
      state: playback,
      time: time,
      duration: duration,
      rate: rate,
      live: false
    };
  }

  /** Hands a validated message to the service worker; a failure is never thrown, and a gone extension ends this copy. */
  function transmit(clean) {
    try {
      var result = root.chrome.runtime.sendMessage(clean);
      if (result && typeof result.then === "function") result.then(noop, onSendFailure);
    } catch (error) {
      onSendFailure(error);
    }
  }

  function onSendFailure() {
    // "Extension context invalidated" after a reload or an update: this copy is orphaned.
    if (!root.chrome || !root.chrome.runtime || !root.chrome.runtime.id) shutdown();
  }

  /** What happened to a command, for the log. The only diagnostic this script sends, one per command, so it needs no rate limit. */
  function diag(event) {
    var message = C.buildDiag("content", event);
    if (message) transmit(message);
  }

  function expectedTime(last, now) {
    return last.time + (last.playing ? ((now - last.at) / 1000) * last.rate : 0);
  }

  function heartbeat(report) {
    return report.state === "playing" ? PLAYING_HEARTBEAT_MS : PAUSED_HEARTBEAT_MS;
  }

  /** Sends the element's report when something changed, the position is not where the last report put it, or a heartbeat is due. */
  function report(force) {
    var el = state.el;
    var message;
    if (el) {
      if (!isConnected(el)) {
        end();
        afterElementGone();
        return;
      }
      message = buildElement(el);
    } else if (isSessionActive()) {
      message = buildSession();
    } else {
      // Nothing left to show: say so, if anything was shown.
      if (state.reported) end();
      else stopTimer();
      return;
    }
    if (!message) return;
    var now = Date.now();
    var key = [message.title, message.artist, message.album, message.site, message.state, message.duration, message.rate, message.live].join("\u0001");
    var last = state.last;
    // A session that never said where it is has no position to be off: only its heartbeat is news.
    var positionKnown = Boolean(el) || Boolean(state.session && state.session.position);
    if (!force && last && last.key === key && now - last.at < heartbeat(message)) {
      if (!positionKnown || Math.abs(message.time - expectedTime(last, now)) < SAME_POSITION_SECONDS) return;
    }
    var clean = T.validateReport(message);
    if (!clean) return;
    state.last = { key: key, time: message.time, at: now, playing: message.state === "playing", rate: message.rate };
    state.reported = true;
    transmit(clean);
  }

  /** The page has no media to show any more: say so once, and stop ticking. */
  function end() {
    var reported = state.reported;
    state.el = null;
    state.last = null;
    state.reported = false;
    stopTimer();
    if (reported) transmit(T.validateEnd({ v: 1, type: "tab-end" }));
  }

  /** The element is gone, and the page's Media Session may still say that it plays: then that is what the page shows now. */
  function afterElementGone() {
    if (!isSessionActive()) return;
    startTimer();
    report(true);
  }

  function startTimer() {
    if (!state.timer && !state.stopped) state.timer = root.setInterval(tick, TICK_MS);
  }

  function stopTimer() {
    if (state.timer) root.clearInterval(state.timer);
    state.timer = 0;
  }

  function claim(el) {
    state.el = el;
    startTimer();
    report(true);
  }

  function tick() {
    try {
      report(false);
    } catch (error) {
      /* the next tick tries again */
    }
  }

  function onMedia(event) {
    try {
      var el = event && event.target;
      if (!isMedia(el)) return;
      if (event.type === "play" || event.type === "playing") {
        // The latest to play is the one shown, and a player that was already shown keeps its place.
        if (el === state.el) report(false);
        else if (isEligible(el)) claim(el);
        return;
      }
      if (el !== state.el) return;
      // What the report left out of a change, it sends only when it is one: a repeat of the same state is not sent again.
      if (event.type === "emptied" || ((event.type === "durationchange" || event.type === "loadedmetadata") && !isEligible(el))) {
        end();
        afterElementGone();
      } else {
        report(false);
      }
    } catch (error) {
      /* a failing handler must not reach the page */
    }
  }

  /** What the page script told us about the Media Session. */
  function onPageMessage(event) {
    var message = T.acceptSessionMessage(event, root, root.location.origin);
    if (!message) return;
    message.receivedAt = Date.now();
    state.session = message;
    try {
      if (state.el) {
        report(false);
      } else if (isSessionActive()) {
        startTimer();
        report(false);
      } else if (state.reported) {
        end();
      }
    } catch (error) {
      /* the next tick tries again */
    }
  }

  function onPageHide() {
    end();
  }

  // ---- commands from the service worker --------------------------------------------------------------------

  function play(el) {
    var result = el.play();
    if (result && typeof result.then === "function") result.then(noop, noop);
  }

  /** Next or previous: the YouTube script's button clicks, or the page's own Media Session handler when it has one. */
  function skip(action) {
    var hook = root[SKIP];
    if (typeof hook === "function") {
      try {
        return hook(action) === true;
      } catch (error) {
        return false;
      }
    }
    var known = state.session ? (action === "next" ? state.session.next : state.session.previous) : false;
    return known && invoke(action);
  }

  /** Asks the page script to call the page's own handler for the action; false when there is nothing valid to ask. */
  function invoke(action, seconds) {
    var request = T.buildInvoke(action, seconds);
    if (!request) return false;
    root.postMessage(request, root.location.origin);
    return true;
  }

  /** The same six commands through the page's Media Session handlers, for media that is no element of ours. */
  function performThroughSession(command) {
    var session = state.session;
    switch (command.action) {
      case "play":
        return session.play && invoke("play");
      case "pause":
        return session.pause && invoke("pause");
      case "toggle":
        return sessionPlayback() === "playing" ? session.pause && invoke("pause") : session.play && invoke("play");
      case "seek":
        return session.seek && invoke("seek", command.seconds);
      case "next":
      case "previous":
        return skip(command.action);
      default:
        return false;
    }
  }

  /** Whether the command could be carried out. Never throws: a page that changed under us is "unavailable". */
  function perform(command) {
    try {
      var el = state.el;
      if (!el && isSessionActive()) return performThroughSession(command) === true;
      if (!el || !isConnected(el)) return false;
      switch (command.action) {
        case "play":
          play(el);
          return true;
        case "pause":
          el.pause();
          return true;
        case "toggle":
          if (el.paused || el.ended) play(el);
          else el.pause();
          return true;
        case "seek": {
          var seconds = command.seconds;
          var duration = el.duration;
          if (typeof duration === "number" && isFinite(duration)) seconds = Math.min(seconds, duration);
          el.currentTime = seconds;
          return true;
        }
        case "next":
        case "previous":
          return skip(command.action);
        default:
          return false;
      }
    } catch (error) {
      return false;
    }
  }

  /**
   * chrome.runtime.onMessage: the service worker passes on a command of the app. Only the extension's own worker (a sender
   * without a tab) is listened to, and only the closed command set; anything else is ignored. The answer is sent at once, so
   * the worker's send always resolves.
   */
  function onRuntimeMessage(message, sender, sendResponse) {
    var own = root.chrome && root.chrome.runtime ? root.chrome.runtime.id : undefined;
    if (!own || !sender || sender.tab || sender.id !== own) return undefined;
    var command = T.validateTabCommand(message);
    if (!command) return undefined;
    var ok = perform(command);
    diag("content-tabcommand " + command.action + " " + (ok ? "ok" : "unavailable"));
    try {
      if (typeof sendResponse === "function") sendResponse({ ok: ok });
    } catch (error) {
      /* the worker stopped waiting */
    }
    return undefined;
  }

  function runtimeMessages() {
    var runtime = root.chrome && root.chrome.runtime;
    return runtime && runtime.onMessage && typeof runtime.onMessage.addListener === "function" ? runtime.onMessage : null;
  }

  function isAlive() {
    return !state.stopped && Boolean(root.chrome && root.chrome.runtime && root.chrome.runtime.id);
  }

  function shutdown() {
    state.stopped = true;
    stopTimer();
    for (var i = 0; i < MEDIA_EVENTS.length; i++) doc.removeEventListener(MEDIA_EVENTS[i], onMedia, true);
    root.removeEventListener("message", onPageMessage, false);
    root.removeEventListener("pagehide", onPageHide, false);
    try {
      if (state.messages) state.messages.removeListener(onRuntimeMessage);
    } catch (error) {
      /* the extension context is gone, and the listener with it */
    }
    state.messages = null;
    state.el = null;
  }

  /** A page whose media was already playing when this script came (an injection after an install or an update). */
  function claimPlaying() {
    var list = doc.querySelectorAll ? doc.querySelectorAll("video, audio") : [];
    for (var i = 0; i < list.length; i++) {
      var el = list[i];
      if (isMedia(el) && isPlaying(el) && isEligible(el)) {
        claim(el);
        return;
      }
    }
  }

  root[STARTED] = { isAlive: isAlive, stop: shutdown };
  for (var i = 0; i < MEDIA_EVENTS.length; i++) doc.addEventListener(MEDIA_EVENTS[i], onMedia, true);
  root.addEventListener("message", onPageMessage, false);
  root.addEventListener("pagehide", onPageHide, false);
  state.messages = runtimeMessages();
  if (state.messages) state.messages.addListener(onRuntimeMessage);
  try {
    claimPlaying();
    // A page that was already playing through its Media Session alone (no element of the document) when the script came.
    if (!state.el && isSessionActive()) {
      startTimer();
      report(true);
    }
  } catch (error) {
    /* the first media event finds it */
  }
})(typeof globalThis !== "undefined" ? globalThis : self);
