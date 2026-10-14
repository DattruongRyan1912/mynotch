/*
 * MyNotch YouTube Bridge: content script (isolated world).
 *
 *  - Accepts `captions` messages from page.js (same window, same origin, bridge source tag),
 *    re-validates them and relays them to the service worker.
 *  - Tracks the video id and the main <video>, and reports `playback` (on play, pause, seeked,
 *    ratechange, video change and every 5 s while playing) and `clear` (video change, leaving
 *    the watch page, captions button turned off).
 *
 * Only the fields of the shared protocol are ever sent; no URLs, no cookies, nothing else.
 */
(function (root) {
  "use strict";

  var C = root.__mynotchCaptions;
  var STARTED = Symbol.for("io.lucasvu.mynotch.yt.content");
  if (!C || root[STARTED]) return;
  root[STARTED] = true;

  var TICK_MS = 1000;
  var HEARTBEAT_MS = 5000;
  // After a navigation document.title can still hold the previous video's title for a moment.
  var STALE_TITLE_MS = 3000;
  var VIDEO_EVENTS = ["play", "pause", "seeked", "ratechange", "ended", "playing"];

  var doc = root.document;
  var state = {
    videoId: null,
    video: null,
    cc: "unknown", // "on" | "off" | "unknown", from the captions button
    captions: null, // latest captions message of the current video, resent after a clear
    clearedId: null, // video id whose captions were last cleared and not sent again since
    lastPlaying: null, // the `playing` value of the last playback message
    lastSentAt: 0,
    pending: false, // a playback message is waiting for a usable title
    lastTitle: "",
    staleTitle: "",
    staleUntil: 0,
    timer: 0
  };

  function send(message) {
    var clean = C.validateMessage(message);
    if (!clean) return;
    try {
      var result = root.chrome.runtime.sendMessage(clean);
      if (result && typeof result.catch === "function") result.catch(function () {});
    } catch (e) {
      // "Extension context invalidated" after a reload or update: this copy is orphaned.
      if (!root.chrome || !root.chrome.runtime || !root.chrome.runtime.id) shutdown();
    }
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

  function isPlaying(video) {
    if (!video || video.paused || video.ended) return false;
    // While an ad runs in the main player, the video time is the ad's time, not the content's.
    var player = doc.getElementById("movie_player");
    return !(player && player.classList && player.classList.contains("ad-showing"));
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
    if (state.captions && state.captions.videoId !== videoId) state.captions = null;
    state.staleTitle = state.lastTitle;
    state.staleUntil = Date.now() + STALE_TITLE_MS;
    sendPlayback();
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
      checkCaptionsButton();
      if (state.video && state.videoId) {
        var playing = isPlaying(state.video);
        var due = playing && Date.now() - state.lastSentAt >= HEARTBEAT_MS;
        // `playing` can change without a media event (the ad-showing class drops after the last one).
        if (state.pending || due || playing !== state.lastPlaying) sendPlayback();
      }
    } catch (e) {
      /* a failed tick must not stop the next one */
    }
  }

  function onPageMessage(event) {
    var message = C.acceptPageMessage(event, root, root.location.origin);
    // Only the video of the page's live URL (not state.videoId: the tick may not have run yet).
    // A late response of the previous video, a preview or miniplayer track, or a forged id would
    // otherwise be cached and replayed although no clear for it would ever be sent.
    if (!message || message.videoId !== C.videoIdFromUrl(root.location.href)) return;
    state.captions = message;
    state.clearedId = null;
    send(message);
  }

  function onPageHide() {
    sendClear(state.videoId);
    state.videoId = null;
    state.cc = "unknown";
  }

  function shutdown() {
    if (state.timer) root.clearInterval(state.timer);
    state.timer = 0;
    unbindVideo();
    root.removeEventListener("message", onPageMessage, false);
    root.removeEventListener("yt-navigate-finish", tick, true);
    root.removeEventListener("pagehide", onPageHide, false);
  }

  root.addEventListener("message", onPageMessage, false);
  root.addEventListener("yt-navigate-finish", tick, true);
  root.addEventListener("pagehide", onPageHide, false);
  state.timer = root.setInterval(tick, TICK_MS);
  tick();
})(typeof globalThis !== "undefined" ? globalThis : self);
