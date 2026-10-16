/*
 * MyNotch YouTube Bridge: MAIN-world hook of the page's Media Session.
 *
 * Runs in any page before the page's own scripts. The page decides what its Media Session holds (the title and artist it shows in
 * the system's media controls, and whether it can go to the next or the previous track), and a content script cannot call the
 * page's handlers: they are the page's own functions. So this script, which shares the page's world, does two small things:
 *
 *  - It notices the handlers the page sets for the next and the previous track (and each new metadata object) and tells the
 *    content script, with window.postMessage, only the text of the metadata and whether the two handlers exist.
 *  - When the content script asks for it (the user pressed Next or Previous in MyNotch), it calls that handler, which is
 *    what Chrome's own media controls do.
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

  var handlers = { nexttrack: null, previoustrack: null };
  var scheduled = false;

  function text(value) {
    return typeof value === "string" ? value.slice(0, MAX_TEXT) : "";
  }

  /** What the page's Media Session holds now: three strings and the two flags; never artwork or any URL. */
  function snapshot() {
    var metadata = null;
    try {
      metadata = root.navigator.mediaSession.metadata;
    } catch (e) {
      /* no session */
    }
    return {
      source: SOURCE,
      type: "session",
      title: text(metadata && metadata.title),
      artist: text(metadata && metadata.artist),
      album: text(metadata && metadata.album),
      next: typeof handlers.nexttrack === "function",
      previous: typeof handlers.previoustrack === "function"
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
        if (action === "nexttrack" || action === "previoustrack") {
          handlers[action] = typeof handler === "function" ? handler : null;
          schedule();
        }
      } catch (e) {
        /* never disturb the page */
      }
      return result;
    };
  }

  var descriptor = Object.getOwnPropertyDescriptor(proto, "metadata");
  if (descriptor && typeof descriptor.set === "function" && descriptor.configurable) {
    try {
      Object.defineProperty(proto, "metadata", {
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

  /** The content script asks for the next or the previous track: the page's own handler does it. */
  root.addEventListener(
    "message",
    function (event) {
      try {
        if (!event || event.source !== root || event.origin !== root.location.origin) return;
        var data = event.data;
        if (!data || typeof data !== "object" || data.source !== SOURCE || data.type !== "invoke") return;
        var action = data.action === "next" ? "nexttrack" : data.action === "previous" ? "previoustrack" : null;
        var handler = action ? handlers[action] : null;
        if (typeof handler === "function") handler({ action: action });
      } catch (e) {
        /* the page's handler failing is the page's business */
      }
    },
    false
  );

  schedule();
})(typeof globalThis !== "undefined" ? globalThis : self);
