/*
 * MyNotch Web Companion: MAIN-world observer.
 *
 * Runs inside the YouTube page before the page's own scripts. It watches the responses the
 * player already receives for /api/timedtext (fetch and XMLHttpRequest), turns the caption
 * body into protocol events and hands them to the content script with window.postMessage.
 *
 * Safety rules for everything below:
 *  - The page always gets the original behaviour: the wrappers call the original function
 *    first and return its result untouched (same Promise object, same exceptions).
 *  - Observation happens on a clone / a read-only event listener and is wrapped in try/catch.
 *    Nothing observation-related can throw into YouTube's code or leave an unhandled rejection.
 *  - Wrapping is idempotent (a hidden symbol flag), and this script exposes no globals.
 *  - The request URL is only used to read the video id, language and kind; it is never forwarded.
 *
 * It also reports what it sees as `diag` events (wrapper installed, requests seen, format and
 * number of events, parse errors): fixed codes and numbers only, never URLs, ids or text.
 */
(function (root) {
  "use strict";

  var C = root.__mynotchCaptions;
  try {
    delete root.__mynotchCaptions;
  } catch (e) {
    /* nothing to do */
  }
  var FLAG = Symbol.for("io.lucasvu.mynotch.yt.page");
  if (!C || root[FLAG]) return;
  try {
    Object.defineProperty(root, FLAG, { value: true });
  } catch (e) {
    return;
  }

  var MAX_BODY_CHARS = 20000000;
  var DIAG_WINDOW_MS = 5000;
  var allowDiag = C.createDiagLimiter(function () {
    return Date.now();
  }, DIAG_WINDOW_MS);
  var ours = { fetch: null, open: null }; // our wrappers, to notice if someone replaces them later

  function noop() {}

  function post(message) {
    var envelope = { source: C.SOURCE };
    for (var key in message) {
      if (Object.prototype.hasOwnProperty.call(message, key)) envelope[key] = message[key];
    }
    root.postMessage(envelope, root.location.origin);
  }

  /** One diagnostic event for the content script (rate limited, never throws). */
  function diag(event) {
    try {
      if (!allowDiag(event)) return;
      var message = C.buildDiag("page", event);
      if (message) post(message);
    } catch (e) {
      /* diagnostics must never disturb the page */
    }
  }

  /** Turns one observed timedtext body into a `captions` message and posts it. */
  function handleBody(track, body) {
    try {
      if (typeof body === "string" && body.length > MAX_BODY_CHARS) {
        diag("page-timedtext-too-large");
        return;
      }
      var parsed = C.parseBody(body);
      if (parsed.error) {
        diag("page-timedtext-parse-error");
        return;
      }
      diag("page-timedtext " + parsed.format + " events=" + parsed.events.length);
      var message = C.buildCaptionsMessage({
        videoId: track.videoId,
        lang: track.lang,
        kind: track.kind,
        events: parsed.events
      });
      if (message) post(message);
    } catch (e) {
      diag("page-timedtext-parse-error");
    }
  }

  function trackFor(url) {
    return typeof url === "string" ? C.parseTimedTextUrl(url, root.location.href) : null;
  }

  function urlOfFetchInput(input) {
    if (typeof input === "string") return input;
    if (input && typeof input.url === "string") return input.url; // Request
    if (input && typeof input.href === "string") return input.href; // URL
    return null;
  }

  function observeFetch(args, result) {
    var track = trackFor(urlOfFetchInput(args[0]));
    if (!track || !result || typeof result.then !== "function") return;
    diag("page-seen fetch");
    // Registered before the page can attach its own handlers, so the clone is taken before the
    // body is read. The derived promise swallows every outcome.
    result.then(function (response) {
      try {
        if (response && response.ok === false) {
          if (typeof response.status === "number") diag("page-timedtext-status " + response.status);
          return;
        }
        if (!response) return;
        response
          .clone()
          .text()
          .then(function (body) {
            handleBody(track, body);
          }, noop)
          .then(noop, noop);
      } catch (e) {
        /* body already used, opaque response, ... */
      }
    }, function () {
      diag("page-timedtext-failed fetch"); // network error, or blocked by an extension
    });
  }

  /** Returns true when the wrapper was installed. */
  function wrapFetch() {
    var original = root.fetch;
    if (typeof original !== "function") return false;
    ours.fetch = new Proxy(original, {
      apply: function (target, thisArg, args) {
        var result = Reflect.apply(target, thisArg, args);
        try {
          observeFetch(args, result);
        } catch (e) {
          /* never disturb the page */
        }
        return result;
      }
    });
    root.fetch = ours.fetch;
    return true;
  }

  function readXhrBody(xhr) {
    var type = xhr.responseType;
    if (type === "" || type === "text") return xhr.responseText;
    if (type === "json") return xhr.response;
    if (type === "arraybuffer" && typeof TextDecoder === "function" && xhr.response) {
      return new TextDecoder("utf-8").decode(xhr.response);
    }
    return null;
  }

  /** Returns true when the wrapper was installed. */
  function wrapXhr() {
    var Xhr = root.XMLHttpRequest;
    var proto = Xhr && Xhr.prototype;
    if (!proto || typeof proto.open !== "function") return false;
    var tracks = new WeakMap();

    // One shared listener function: addEventListener ignores duplicate registrations of it.
    function onLoad(event) {
      try {
        var xhr = event.currentTarget || event.target;
        var track = tracks.get(xhr);
        if (!track) return;
        if (xhr.status < 200 || xhr.status >= 300) {
          diag("page-timedtext-status " + xhr.status);
          return;
        }
        var body = readXhrBody(xhr);
        if (body !== null && body !== undefined) handleBody(track, body);
      } catch (e) {
        /* never disturb the page */
      }
    }

    function onError(event) {
      try {
        if (tracks.get(event.currentTarget || event.target)) diag("page-timedtext-failed xhr");
      } catch (e) {
        /* never disturb the page */
      }
    }

    ours.open = new Proxy(proto.open, {
      apply: function (target, thisArg, args) {
        var result = Reflect.apply(target, thisArg, args); // throws exactly like the original
        try {
          var track = trackFor(urlOfFetchInput(args[1]));
          if (track) {
            diag("page-seen xhr");
            tracks.set(thisArg, track);
            thisArg.addEventListener("load", onLoad);
            thisArg.addEventListener("error", onError);
          } else {
            tracks.delete(thisArg);
          }
        } catch (e) {
          /* never disturb the page */
        }
        return result;
      }
    });
    proto.open = ours.open;
    return true;
  }

  var fetchWrapped = false;
  var xhrWrapped = false;
  try {
    fetchWrapped = wrapFetch();
  } catch (e) {
    /* leave fetch alone */
  }
  try {
    xhrWrapped = wrapXhr();
  } catch (e) {
    /* leave XMLHttpRequest alone */
  }

  // Reported a little later: the content script has to be listening by then. The second report
  // tells whether another script (an ad blocker, say) replaced our wrappers in the meantime.
  if (typeof root.setTimeout === "function") {
    root.setTimeout(function () {
      diag("page-wrap fetch=" + fetchWrapped + " xhr=" + xhrWrapped);
    }, 1000);
    root.setTimeout(function () {
      var proto = root.XMLHttpRequest && root.XMLHttpRequest.prototype;
      diag(
        "page-wrap-check fetch=" + (fetchWrapped && root.fetch === ours.fetch) + " xhr=" + (xhrWrapped && !!proto && proto.open === ours.open)
      );
    }, 10000);
  }
})(typeof globalThis !== "undefined" ? globalThis : self);
