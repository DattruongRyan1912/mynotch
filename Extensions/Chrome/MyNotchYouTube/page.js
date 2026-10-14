/*
 * MyNotch YouTube Bridge: MAIN-world observer.
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

  function noop() {}

  function post(message) {
    var envelope = { source: C.SOURCE };
    for (var key in message) {
      if (Object.prototype.hasOwnProperty.call(message, key)) envelope[key] = message[key];
    }
    root.postMessage(envelope, root.location.origin);
  }

  /** Turns one observed timedtext body into a `captions` message and posts it. */
  function handleBody(track, body) {
    try {
      if (typeof body === "string" && body.length > MAX_BODY_CHARS) return;
      var message = C.buildCaptionsMessage({
        videoId: track.videoId,
        lang: track.lang,
        kind: track.kind,
        events: C.eventsFromBody(body)
      });
      if (message) post(message);
    } catch (e) {
      /* observation must never disturb the page */
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
    // Registered before the page can attach its own handlers, so the clone is taken before the
    // body is read. The derived promise swallows every outcome.
    result.then(function (response) {
      try {
        if (!response || response.ok === false) return;
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
    }, noop);
  }

  function wrapFetch() {
    var original = root.fetch;
    if (typeof original !== "function") return;
    root.fetch = new Proxy(original, {
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

  function wrapXhr() {
    var Xhr = root.XMLHttpRequest;
    var proto = Xhr && Xhr.prototype;
    if (!proto || typeof proto.open !== "function") return;
    var tracks = new WeakMap();

    // One shared listener function: addEventListener ignores duplicate registrations of it.
    function onLoad(event) {
      try {
        var xhr = event.currentTarget || event.target;
        var track = tracks.get(xhr);
        if (!track || xhr.status < 200 || xhr.status >= 300) return;
        var body = readXhrBody(xhr);
        if (body !== null && body !== undefined) handleBody(track, body);
      } catch (e) {
        /* never disturb the page */
      }
    }

    proto.open = new Proxy(proto.open, {
      apply: function (target, thisArg, args) {
        var result = Reflect.apply(target, thisArg, args); // throws exactly like the original
        try {
          var track = trackFor(urlOfFetchInput(args[1]));
          if (track) {
            tracks.set(thisArg, track);
            thisArg.addEventListener("load", onLoad);
          } else {
            tracks.delete(thisArg);
          }
        } catch (e) {
          /* never disturb the page */
        }
        return result;
      }
    });
  }

  try {
    wrapFetch();
  } catch (e) {
    /* leave fetch alone */
  }
  try {
    wrapXhr();
  } catch (e) {
    /* leave XMLHttpRequest alone */
  }
})(typeof globalThis !== "undefined" ? globalThis : self);
