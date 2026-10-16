/*
 * MyNotch YouTube Bridge: MAIN-world hook of the page's Media Session.
 *
 * Runs in any page before the page's own scripts. The page decides what its Media Session holds (the title and artist it shows in
 * the system's media controls, whether it says it plays, where it says it is, and which actions it can do), and a content script
 * cannot call the page's handlers: they are the page's own functions. Media that is not an element of the document (an `Audio`
 * the page keeps to itself) cannot be seen from the content script either, but its page has a Media Session. So this script,
 * which shares the page's world, does two small things:
 *
 *  - It notices what the page sets (each new metadata object, the playback state, the position state, the handlers for play,
 *    pause, seek and the next and previous track) and tells the content script, with window.postMessage, only text, numbers and
 *    which handlers exist.
 *  - When the content script asks for it (the user pressed a button in MyNotch for that tab), it calls the page's own handler,
 *    which is what Chrome's own media controls do.
 *
 * The page always gets the original behaviour: the wrappers call the original first and return its result untouched, and
 * everything this script does after it is wrapped in try/catch. It exposes no globals and wraps only once (a hidden symbol flag).
 * It reads nothing else of the page and makes no request.
 */
(function (root) {
  "use strict";

  var SOURCE = "mynotch-tab";
  var MAX_TEXT = 300;
  var FLAG = Symbol.for("io.lucasvu.mynotch.tab.page");
  if (root[FLAG]) return;
  try {
    Object.defineProperty(root, FLAG, { value: true });
  } catch (e) {
    return;
  }

  var Session = root.MediaSession;
  var proto = Session && Session.prototype;
  if (!proto) return; // no Media Session in this page: nothing to hook

  // The media session actions we call, by the name of the protocol's invoke.
  var ACTIONS = { next: "nexttrack", previous: "previoustrack", play: "play", pause: "pause", seek: "seekto" };
  var handlers = { nexttrack: null, previoustrack: null, play: null, pause: null, seekto: null };
  var position = null; // what the page last said with setPositionState: { position, duration, rate, at }
  var now = typeof Date.now === "function" ? Date.now.bind(Date) : function () { return 0; };
  var scheduled = false;

  function text(value) {
    return typeof value === "string" ? value.slice(0, MAX_TEXT) : "";
  }

  function finite(value) {
    return typeof value === "number" && isFinite(value) ? value : null;
  }

  function has(name) {
    return typeof handlers[name] === "function";
  }

  /** What the page's Media Session holds now: text, numbers and flags; never artwork or any URL. */
  function snapshot() {
    var session = null;
    var metadata = null;
    var playback = "none";
    try {
      session = root.navigator.mediaSession;
      metadata = session.metadata;
      playback = session.playbackState;
    } catch (e) {
      /* no session */
    }
    return {
      source: SOURCE,
      type: "session",
      title: text(metadata && metadata.title),
      artist: text(metadata && metadata.artist),
      album: text(metadata && metadata.album),
      playback: playback === "playing" || playback === "paused" ? playback : "none",
      position: position,
      next: has("nexttrack"),
      previous: has("previoustrack"),
      play: has("play"),
      pause: has("pause"),
      seek: has("seekto")
    };
  }

  function post() {
    scheduled = false;
    try {
      root.postMessage(snapshot(), root.location.origin);
    } catch (e) {
      /* an opaque origin, a page that is going away: nothing to tell */
    }
  }

  /** One message for any number of changes made in the same task. */
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    try {
      Promise.resolve().then(post);
    } catch (e) {
      scheduled = false;
    }
  }

  var original = proto.setActionHandler;
  if (typeof original === "function") {
    proto.setActionHandler = function (action, handler) {
      var result = original.apply(this, arguments); // throws exactly like the original
      try {
        if (Object.prototype.hasOwnProperty.call(handlers, action)) {
          handlers[action] = typeof handler === "function" ? handler : null;
          schedule();
        }
      } catch (e) {
        /* never disturb the page */
      }
      return result;
    };
  }

  var originalPosition = proto.setPositionState;
  if (typeof originalPosition === "function") {
    proto.setPositionState = function (state) {
      var result = originalPosition.apply(this, arguments); // throws exactly like the original
      try {
        // No argument clears it. An endless duration (a live stream) is no duration.
        position =
          state && typeof state === "object" && finite(state.position) !== null
            ? { position: state.position, duration: finite(state.duration), rate: finite(state.playbackRate), at: now() }
            : null;
        schedule();
      } catch (e) {
        /* never disturb the page */
      }
      return result;
    };
  }

  /** An accessor of the prototype whose setter the page's writes go through: the original runs first, then we look. */
  function watch(name) {
    var descriptor = Object.getOwnPropertyDescriptor(proto, name);
    if (!descriptor || typeof descriptor.set !== "function" || !descriptor.configurable) return;
    try {
      Object.defineProperty(proto, name, {
        configurable: true,
        enumerable: descriptor.enumerable,
        get: descriptor.get,
        set: function (value) {
          descriptor.set.call(this, value); // throws exactly like the original
          try {
            schedule();
          } catch (e) {
            /* never disturb the page */
          }
        }
      });
    } catch (e) {
      /* leave the property alone */
    }
  }

  watch("metadata");
  watch("playbackState");

  /** The content script asks for an action: the page's own handler does it. */
  root.addEventListener(
    "message",
    function (event) {
      try {
        if (!event || event.source !== root || event.origin !== root.location.origin) return;
        var data = event.data;
        if (!data || typeof data !== "object" || data.source !== SOURCE || data.type !== "invoke") return;
        var action = Object.prototype.hasOwnProperty.call(ACTIONS, data.action) ? ACTIONS[data.action] : null;
        var handler = action ? handlers[action] : null;
        if (typeof handler !== "function") return;
        var details = { action: action };
        if (action === "seekto") {
          if (typeof data.seconds !== "number" || !isFinite(data.seconds)) return;
          details.seekTime = data.seconds;
        }
        handler(details);
      } catch (e) {
        /* the page's handler failing is the page's business */
      }
    },
    false
  );

  schedule();
})(typeof globalThis !== "undefined" ? globalThis : self);
