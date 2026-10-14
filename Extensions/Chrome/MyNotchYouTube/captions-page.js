/*
 * MyNotch YouTube Bridge: caption parsing and message validation.
 *
 * Pure functions only: no DOM, no chrome.* and no network. The same file is loaded as a
 * classic script by the page (MAIN world) script, the content script and the service
 * worker, and is required directly by the Node tests.
 *
 * Chrome injects a file once per document, whichever content_scripts entries list it, so the
 * MAIN world loads a byte-identical copy under another name: captions-page.js. After every
 * change run `cp captions.js captions-page.js` (a test fails when they differ).
 *
 * Message shapes and limits follow the shared MyNotch protocol (version 1).
 */
(function (root) {
  "use strict";

  var SOURCE = "mynotch-yt";
  var MAX_EVENTS = 5000;
  var MAX_TEXT = 500;
  var MAX_TITLE = 300;
  // The native host drops frames above 4 MiB, so stay well below that (JSON escapes included).
  var MAX_MESSAGE_BYTES = 3000000;
  var MAX_RATE = 16;
  var VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;
  var LANG = /^[A-Za-z0-9]{1,8}(?:[-_][A-Za-z0-9]{1,8}){0,3}$/;

  function isNumber(value) {
    return typeof value === "number" && isFinite(value);
  }

  function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
  }

  /** Control characters and every kind of whitespace become one space; the result is trimmed. */
  function normalizeText(value) {
    if (typeof value !== "string") return "";
    return value.replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim();
  }

  /** Cuts to at most `max` UTF-16 units without splitting a surrogate pair. */
  function truncate(text, max) {
    if (text.length <= max) return text;
    var cut = text.slice(0, max);
    var last = cut.charCodeAt(max - 1);
    if (last >= 0xd800 && last <= 0xdbff) cut = cut.slice(0, max - 1);
    return cut.replace(/\s+$/, "");
  }

  /** Rough UTF-8 size of the text once JSON-escaped (quotes and backslashes count double). */
  function jsonBytes(text) {
    var bytes = 0;
    for (var i = 0; i < text.length; i++) {
      var c = text.charCodeAt(i);
      if (c === 34 || c === 92) bytes += 2;
      else if (c < 0x80) bytes += 1;
      else if (c < 0x800) bytes += 2;
      else if (c >= 0xd800 && c <= 0xdbff) {
        bytes += 4;
        i++;
      } else bytes += 3;
    }
    return bytes;
  }

  /** One protocol event from millisecond timing and raw text; null when it has no usable text or time. */
  function makeEvent(startMs, durationMs, rawText) {
    if (!isNumber(startMs) || startMs < 0) return null;
    var text = truncate(normalizeText(rawText), MAX_TEXT);
    if (!text) return null;
    return {
      t: Math.round(startMs) / 1000,
      d: isNumber(durationMs) && durationMs > 0 ? Math.round(durationMs) / 1000 : 0,
      text: text
    };
  }

  /** Sorts by start time and applies the event-count and size limits. */
  function finalizeEvents(list) {
    list.sort(function (a, b) {
      return a.t - b.t;
    });
    var out = [];
    var bytes = 0;
    for (var i = 0; i < list.length && out.length < MAX_EVENTS; i++) {
      bytes += jsonBytes(list[i].text) + 48;
      if (bytes > MAX_MESSAGE_BYTES) break;
      out.push(list[i]);
    }
    return out;
  }

  /** json3 body (string or already parsed object) to protocol events. */
  function eventsFromJson3(data) {
    var parsed = data;
    if (typeof data === "string") {
      try {
        parsed = JSON.parse(data);
      } catch (e) {
        return [];
      }
    }
    var raw = parsed && Array.isArray(parsed.events) ? parsed.events : [];
    var out = [];
    for (var i = 0; i < raw.length; i++) {
      var ev = raw[i];
      if (!ev || typeof ev !== "object" || !Array.isArray(ev.segs)) continue;
      var text = "";
      for (var j = 0; j < ev.segs.length; j++) {
        var seg = ev.segs[j];
        if (seg && typeof seg.utf8 === "string") text += seg.utf8;
      }
      var event = makeEvent(ev.tStartMs, ev.dDurationMs, text);
      if (event) out.push(event);
    }
    return finalizeEvents(out);
  }

  var NAMED_ENTITIES = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " };

  function numericEntity(body) {
    var code = body.charAt(1) === "x" ? parseInt(body.slice(2), 16) : parseInt(body.slice(1), 10);
    var valid = code >= 0 && code <= 0x10ffff && !(code >= 0xd800 && code <= 0xdfff);
    return valid ? String.fromCodePoint(code) : "";
  }

  function decodeEntities(text) {
    var once = text.replace(/&(#x[0-9a-fA-F]+|#[0-9]+|[A-Za-z]+);/g, function (whole, body) {
      if (body.charAt(0) === "#") return numericEntity(body);
      return Object.prototype.hasOwnProperty.call(NAMED_ENTITIES, body) ? NAMED_ENTITIES[body] : whole;
    });
    // Some timedtext XML escapes apostrophes twice ("&amp;#39;"): decode numeric entities that are left.
    return once.replace(/&(#x[0-9a-fA-F]+|#[0-9]+);/g, function (whole, body) {
      return numericEntity(body);
    });
  }

  function parseAttributes(source) {
    var attributes = {};
    var re = /([A-Za-z_][\w:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')/g;
    var match;
    while ((match = re.exec(source)) !== null) {
      attributes[match[1]] = match[2] !== undefined ? match[2] : match[3];
    }
    return attributes;
  }

  function numberAttribute(value) {
    return typeof value === "string" && /^\d+(?:\.\d+)?$/.test(value) ? Number(value) : NaN;
  }

  /** srv3 XML body (`<p t="ms" d="ms">` with optional `<s>` children) to protocol events. */
  function eventsFromSrv3(xml) {
    if (typeof xml !== "string") return [];
    var out = [];
    var re = /<p\b([^>]*?)(?:\/>|>([\s\S]*?)<\/p>)/g;
    var match;
    while ((match = re.exec(xml)) !== null) {
      if (match[2] === undefined) continue;
      var attributes = parseAttributes(match[1]);
      var text = decodeEntities(match[2].replace(/<[^>]*>/g, ""));
      var event = makeEvent(numberAttribute(attributes.t), numberAttribute(attributes.d), text);
      if (event) out.push(event);
    }
    return finalizeEvents(out);
  }

  /**
   * Picks the parser from the first non-space character of the body.
   * Returns { format: "json3" | "srv3" | "other", events, error }; `error` is true only when a
   * body that looks like json3 is not valid JSON.
   */
  function parseBody(body) {
    if (body !== null && typeof body === "object") {
      return { format: "json3", events: eventsFromJson3(body), error: false };
    }
    if (typeof body !== "string") return { format: "other", events: [], error: false };
    var i = 0;
    while (i < body.length && i < 64 && /[\s\uFEFF]/.test(body.charAt(i))) i++;
    var first = body.charAt(i);
    if (first === "{") {
      var parsed;
      try {
        parsed = JSON.parse(i > 0 ? body.slice(i) : body);
      } catch (e) {
        return { format: "json3", events: [], error: true };
      }
      return { format: "json3", events: eventsFromJson3(parsed), error: false };
    }
    if (first === "<") return { format: "srv3", events: eventsFromSrv3(body), error: false };
    return { format: "other", events: [], error: false };
  }

  function eventsFromBody(body) {
    return parseBody(body).events;
  }

  function normalizeLang(value) {
    return typeof value === "string" && LANG.test(value) ? value : "und";
  }

  /**
   * Reads the track identity from a timedtext request URL. Returns null for any other URL.
   * The URL itself is never kept or forwarded; only these three small fields leave this function.
   */
  function parseTimedTextUrl(raw, base) {
    var url;
    try {
      url = new URL(raw, base);
    } catch (e) {
      return null;
    }
    if (url.pathname !== "/api/timedtext") return null;
    var query = url.searchParams;
    return {
      videoId: query.get("v") || "",
      lang: query.get("tlang") || query.get("lang") || "",
      kind: query.get("kind") === "asr" ? "asr" : "standard"
    };
  }

  /** A protocol `captions` message, or null when there is nothing valid to send. */
  function buildCaptionsMessage(info) {
    if (!info || typeof info.videoId !== "string" || !VIDEO_ID.test(info.videoId)) return null;
    if (!Array.isArray(info.events) || info.events.length === 0) return null;
    return {
      v: 1,
      type: "captions",
      videoId: info.videoId,
      lang: normalizeLang(info.lang),
      kind: info.kind === "asr" ? "asr" : "standard",
      events: info.events
    };
  }

  /** Video id of a watch, shorts or live URL; null for anything else. */
  function videoIdFromUrl(href) {
    var url;
    try {
      url = new URL(String(href));
    } catch (e) {
      return null;
    }
    if (url.pathname === "/watch") {
      var id = url.searchParams.get("v");
      return id && VIDEO_ID.test(id) ? id : null;
    }
    var match = /^\/(?:shorts|live)\/([A-Za-z0-9_-]{11})\/?$/.exec(url.pathname);
    return match ? match[1] : null;
  }

  /** Document title without the notification counter prefix and the " - YouTube" suffix. */
  function cleanTitle(raw) {
    var title = normalizeText(raw);
    title = title.replace(/^\(\d+\+?\)\s+/, "").replace(/\s+-\s+YouTube$/, "");
    return truncate(title, MAX_TITLE);
  }

  function validVideoId(value) {
    return typeof value === "string" && VIDEO_ID.test(value);
  }

  function round3(value) {
    return Math.round(value * 1000) / 1000;
  }

  function validateCaptions(message) {
    if (!validVideoId(message.videoId)) return null;
    if (typeof message.lang !== "string" || !LANG.test(message.lang)) return null;
    if (message.kind !== "standard" && message.kind !== "asr") return null;
    if (!Array.isArray(message.events) || message.events.length === 0) return null;
    if (message.events.length > MAX_EVENTS) return null;
    var events = [];
    for (var i = 0; i < message.events.length; i++) {
      var ev = message.events[i];
      if (!isObject(ev) || !isNumber(ev.t) || ev.t < 0 || !isNumber(ev.d) || ev.d < 0) return null;
      if (typeof ev.text !== "string") return null;
      var event = makeEvent(ev.t * 1000, ev.d * 1000, ev.text);
      if (event) events.push(event);
    }
    events = finalizeEvents(events);
    if (events.length === 0) return null;
    return { v: 1, type: "captions", videoId: message.videoId, lang: message.lang, kind: message.kind, events: events };
  }

  function validatePlayback(message) {
    if (!validVideoId(message.videoId)) return null;
    if (typeof message.title !== "string") return null;
    var title = truncate(normalizeText(message.title), MAX_TITLE);
    if (!title) return null;
    if (!isNumber(message.time) || message.time < 0) return null;
    if (typeof message.playing !== "boolean") return null;
    if (!isNumber(message.rate) || message.rate <= 0 || message.rate > MAX_RATE) return null;
    return {
      v: 1,
      type: "playback",
      videoId: message.videoId,
      title: title,
      time: round3(message.time),
      playing: message.playing,
      rate: round3(message.rate)
    };
  }

  function validateClear(message) {
    if (!validVideoId(message.videoId)) return null;
    return { v: 1, type: "clear", videoId: message.videoId };
  }

  // ---- diagnostics ("diag" messages) -----------------------------------------------------------
  // A diag event is one fixed code followed by a fixed argument shape: words from a closed list,
  // numbers and booleans. The only free-form part is a lowercase [a-z0-9-] error token (at most 80
  // characters) made by errorCode(). So an event never carries titles, URLs, video ids or caption
  // text, and a standalone 11-character run of video-id characters is refused as well.
  var MAX_DIAG_EVENT = 120;
  var DIAG_WHERE = { sw: true, content: true, page: true };
  var NO_ARGS = /^$/;
  var FETCH_XHR = /^ fetch=(?:true|false) xhr=(?:true|false)$/;
  var DIAG_ARGS = {
    "sw-start": /^ v=(?:[0-9]{1,4}(?:\.[0-9]{1,4}){0,3}|unknown)$/,
    "sw-msg": /^ (?:captions events=[0-9]{1,5}|playback|clear)$/,
    "sw-reject": /^ (?:untrusted|invalid (?:captions|playback|clear|diag|command|unknown))$/,
    "sw-reconnect": /^ after=[a-z0-9-]{1,80} failures=[0-9]{1,6}$/,
    "sw-access": /^ youtube=(?:granted|withheld)$/,
    "sw-inject": /^ tabs=[0-9]{1,6} injected=[0-9]{1,6} failed=[0-9]{1,6}$/,
    "sw-command-no-tab": NO_ARGS,
    "content-start": NO_ARGS,
    "content-no-lib": NO_ARGS,
    "content-command": /^ (?:next|previous) (?:ok|unavailable)$/,
    "content-video-found": NO_ARGS,
    "content-video-missing": NO_ARGS,
    "content-cc": /^ (?:on|off)$/,
    "content-send-error": /^ [a-z0-9-]{1,80} count=[0-9]{1,6}$/,
    "content-alive": /^ videoid-present=(?:true|false) playing=(?:true|false)$/,
    "content-tick-error": /^ [a-z0-9-]{1,80}$/,
    "page-wrap": FETCH_XHR,
    "page-wrap-check": FETCH_XHR,
    "page-seen": /^ (?:fetch|xhr)$/,
    "page-timedtext": /^ (?:json3|srv3|other) events=[0-9]{1,5}$/,
    "page-timedtext-status": /^ [0-9]{3}$/,
    "page-timedtext-parse-error": NO_ARGS,
    "page-timedtext-too-large": NO_ARGS,
    "page-timedtext-failed": /^ (?:fetch|xhr)$/
  };
  // Codes whose arguments are a closed list of words and nothing else. The 11-character scan below does not look at
  // their arguments, because one of the words ("unavailable") is exactly 11 letters long; it still looks at the code.
  var CLOSED_WORDS = { "content-command": true };
  var MESSAGE_TYPES = { captions: true, playback: true, clear: true, diag: true };
  // Known Chrome error texts become fixed codes (none is exactly 11 characters long).
  var ERROR_CODES = [
    [/context invalidated/i, "context-invalidated"],
    [/receiving end does not exist/i, "no-receiving-end"],
    [/message length exceeded|exceeded maximum/i, "message-too-long"],
    [/native messaging host not found/i, "host-not-found"],
    [/native messaging host is forbidden/i, "host-forbidden"],
    [/native host has exited/i, "host-has-exited"],
    [/error when communicating with the native messaging host/i, "host-comm-error"],
    [/failed to start native messaging host/i, "host-start-failed"],
    [/disconnected port/i, "port-disconnected"]
  ];

  // Generic words of JavaScript and Chrome error messages. Any other word of an unknown error text
  // (a property name, a title or URL fragment that ended up in the message) is replaced by "x".
  var ERROR_WORDS = {};
  (
    "a access add allowed an and at attribute be blocked bound call can cannot client connection context could " +
    "denied disconnected document domexception element error event exceeded execute extension failed fetch for " +
    "forbidden found frame from function get has host in invalid is iterable it length listener maximum message " +
    "messaging more must native network new no node not null number object of on or port properties property " +
    "query range rangeerror read reading received referenceerror remove response runtime selector set setting " +
    "size specified stack string syntaxerror tab than that the this timeout to token type typeerror undefined " +
    "unexpected use value was window with"
  )
    .split(" ")
    .forEach(function (word) {
      ERROR_WORDS[word] = true;
    });

  /**
   * One short lowercase token for an error: a fixed code for the known Chrome errors, otherwise the
   * generic words of the text joined by "-" (everything inside quotes and every other word becomes
   * "x"), at most 80 characters and never exactly 11 characters long.
   */
  function errorCode(text) {
    var raw = typeof text === "string" ? text : "";
    for (var i = 0; i < ERROR_CODES.length; i++) {
      if (ERROR_CODES[i][0].test(raw)) return ERROR_CODES[i][1];
    }
    var words = [];
    raw
      .toLowerCase()
      .replace(/'[^']*'|"[^"]*"|`[^`]*`/g, " ")
      .split(/[^a-z0-9]+/)
      .forEach(function (word) {
        if (!word) return;
        var generic = ERROR_WORDS[word] === true ? word : "x";
        if (generic !== "x" || words[words.length - 1] !== "x") words.push(generic);
      });
    var token = words.join("-").slice(0, 80).replace(/-+$/, "");
    if (token.length === 11) token += "-x";
    return token || "unknown";
  }

  /** The message's own type when it is one of the protocol types, else "unknown". */
  function typeWord(message) {
    var type = isObject(message) ? message.type : undefined;
    return typeof type === "string" && MESSAGE_TYPES[type] === true ? type : "unknown";
  }

  function validDiagEvent(where, event) {
    if (typeof event !== "string" || event.length === 0 || event.length > MAX_DIAG_EVENT) return false;
    var space = event.indexOf(" ");
    var code = space < 0 ? event : event.slice(0, space);
    var shape = Object.prototype.hasOwnProperty.call(DIAG_ARGS, code) ? DIAG_ARGS[code] : null;
    if (!shape || code.indexOf(where + "-") !== 0) return false;
    if (!shape.test(event.slice(code.length))) return false;
    var runs = (CLOSED_WORDS[code] === true ? code : event).match(/[a-z0-9_-]+/g) || [];
    for (var i = 0; i < runs.length; i++) {
      if (runs[i].length === 11) return false; // would look like a video id
    }
    return true;
  }

  function validateDiag(message) {
    if (typeof message.where !== "string" || DIAG_WHERE[message.where] !== true) return null;
    if (!validDiagEvent(message.where, message.event)) return null;
    return { v: 1, type: "diag", where: message.where, event: message.event };
  }

  /** A validated diag message, or null when the event is not an allowed one. */
  function buildDiag(where, event) {
    return validateMessage({ v: 1, type: "diag", where: where, event: event });
  }

  /**
   * Rate limiter for diag events: at most one event per key within `windowMs`, where the key is
   * the event without its key=value parts (so "page-timedtext json3 events=3" and "... events=9"
   * are the same kind). The table is bounded, so forged events cannot grow it.
   */
  function createDiagLimiter(now, windowMs) {
    var last = new Map();
    return function allow(event) {
      var key = String(event).replace(/=\S*/g, "");
      var time = now();
      var previous = last.get(key);
      if (previous !== undefined && time >= previous && time - previous < windowMs) return false;
      if (last.size >= 128 && !last.has(key)) {
        last.forEach(function (at, other) {
          if (time < at || time - at >= windowMs) last.delete(other);
        });
        if (last.size >= 128) return false;
      }
      last.set(key, time);
      return true;
    };
  }

  /**
   * Validates a protocol message and returns a fresh object holding only the protocol fields
   * (so nothing extra, such as a URL, can ride along), or null when the message is not valid.
   */
  function validateMessage(message) {
    if (!isObject(message) || message.v !== 1) return null;
    switch (message.type) {
      case "captions":
        return validateCaptions(message);
      case "playback":
        return validatePlayback(message);
      case "clear":
        return validateClear(message);
      case "diag":
        return validateDiag(message);
      default:
        return null;
    }
  }

  // ---- commands (app -> host -> service worker -> content script) -------------------------------
  // The only message that travels the other way: the app asks the page to skip. A closed set: exactly
  // {v: 1, type: "command", action: "next" | "previous"}, no other field and no free text.
  var COMMAND_ACTIONS = { next: true, previous: true };

  /** A fresh command object, or null when the message is not exactly one of the two commands. */
  function validateCommand(message) {
    if (!isObject(message) || message.v !== 1 || message.type !== "command") return null;
    var keys = Object.keys(message);
    if (keys.length !== 3 || !hasOwn(message, "v") || !hasOwn(message, "type") || !hasOwn(message, "action")) return null;
    var action = message.action;
    if (typeof action !== "string" || !hasOwn(COMMAND_ACTIONS, action) || COMMAND_ACTIONS[action] !== true) return null;
    return { v: 1, type: "command", action: action };
  }

  function hasOwn(object, key) {
    return Object.prototype.hasOwnProperty.call(object, key);
  }

  /**
   * Content-script gate for window "message" events: only `captions` and page-side `diag`
   * messages that this very window posted to its own origin with the bridge's source tag are
   * accepted, and they are re-validated before they go any further.
   */
  function acceptPageMessage(event, win, origin) {
    if (!event || event.source !== win || event.origin !== origin) return null;
    var data = event.data;
    if (!isObject(data) || data.source !== SOURCE) return null;
    if (data.type === "captions") return validateMessage(data);
    if (data.type === "diag" && data.where === "page") return validateMessage(data);
    return null;
  }

  var api = {
    SOURCE: SOURCE,
    MAX_EVENTS: MAX_EVENTS,
    MAX_TEXT: MAX_TEXT,
    MAX_TITLE: MAX_TITLE,
    MAX_MESSAGE_BYTES: MAX_MESSAGE_BYTES,
    normalizeText: normalizeText,
    eventsFromJson3: eventsFromJson3,
    eventsFromSrv3: eventsFromSrv3,
    eventsFromBody: eventsFromBody,
    parseBody: parseBody,
    parseTimedTextUrl: parseTimedTextUrl,
    buildCaptionsMessage: buildCaptionsMessage,
    videoIdFromUrl: videoIdFromUrl,
    cleanTitle: cleanTitle,
    validateMessage: validateMessage,
    validateCommand: validateCommand,
    errorCode: errorCode,
    typeWord: typeWord,
    buildDiag: buildDiag,
    createDiagLimiter: createDiagLimiter,
    acceptPageMessage: acceptPageMessage
  };

  if (typeof module === "object" && module !== null && module.exports) {
    module.exports = api;
  } else {
    // Handed to the next script of the same world (page.js, content.js, bridge users) through a
    // hidden global; page.js removes it again so the YouTube page never sees it.
    Object.defineProperty(root, "__mynotchCaptions", { value: api, configurable: true, writable: true });
  }
})(typeof globalThis !== "undefined" ? globalThis : self);
