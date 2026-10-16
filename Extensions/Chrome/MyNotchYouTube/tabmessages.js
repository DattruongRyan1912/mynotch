/*
 * MyNotch YouTube Bridge: the messages about media tabs (any page that plays or has paused media).
 *
 * Pure functions only: no DOM, no chrome.* and no network. Loaded as a classic script by the content script (isolated
 * world) and the service worker, and required directly by the Node tests.
 *
 * Three kinds of message, all closed sets (a fresh object with these fields and nothing else):
 *  - what a page says about its media, content script -> service worker: `tab-report` (no tab id: the worker takes it from
 *    the sender) and `tab-end` (the page has no media any more);
 *  - what the worker passes on to the app: `tab` (the report plus the tab id) and `tabgone`;
 *  - what the app asks of a tab, the only message that travels the other way for tabs: `tabcommand`
 *    {tab, action: play|pause|toggle|next|previous|seek, seconds (only with seek)}.
 *
 * Never carried: a URL, a path, cookies, artwork or an icon (the extension makes no request of its own). The site is the host
 * name alone.
 */
(function (root) {
  "use strict";

  var SOURCE = "mynotch-tab";
  var MAX_TITLE = 300;
  var MAX_NAME = 200;
  var MAX_RATE = 16;
  var MAX_SECONDS = 10000000;
  var MAX_TAB_ID = 2147483647;
  var SITE = /^[a-z0-9](?:[a-z0-9.-]{0,98}[a-z0-9])?$/;
  var ACTIONS = { play: true, pause: true, toggle: true, next: true, previous: true, seek: true };

  function isNumber(value) {
    return typeof value === "number" && isFinite(value);
  }

  function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
  }

  function hasOwn(object, key) {
    return Object.prototype.hasOwnProperty.call(object, key);
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

  function clean(value, max) {
    return truncate(normalizeText(value), max);
  }

  function round3(value) {
    return Math.round(value * 1000) / 1000;
  }

  function validTabId(value) {
    return isNumber(value) && Math.floor(value) === value && value >= 0 && value <= MAX_TAB_ID;
  }

  /** A host name as the page's location gives it (lowercase letters, digits, dots, dashes), or "" for anything else (an IP v6 address). */
  function cleanSite(hostname) {
    return typeof hostname === "string" && SITE.test(hostname) ? hostname : "";
  }

  /** The fields a report and a `tab` share, or null when they are not valid. */
  function fieldsOf(message) {
    var title = clean(message.title, MAX_TITLE);
    if (!title) return null;
    var artist = message.artist === undefined ? "" : clean(message.artist, MAX_NAME);
    var album = message.album === undefined ? "" : clean(message.album, MAX_NAME);
    if (typeof message.site !== "string" || (message.site !== "" && !SITE.test(message.site))) return null;
    if (message.state !== "playing" && message.state !== "paused") return null;
    if (!isNumber(message.time) || message.time < 0 || message.time > MAX_SECONDS) return null;
    var duration = message.duration;
    if (duration !== null && (!isNumber(duration) || duration < 0 || duration > MAX_SECONDS)) return null;
    if (!isNumber(message.rate) || message.rate <= 0 || message.rate > MAX_RATE) return null;
    if (typeof message.live !== "boolean") return null;
    return {
      site: message.site,
      title: title,
      artist: artist,
      album: album,
      state: message.state,
      time: round3(message.time),
      duration: duration === null ? null : round3(duration),
      rate: round3(message.rate),
      live: message.live
    };
  }

  /** content script -> service worker: what the page's media is doing. */
  function validateReport(message) {
    if (!isObject(message) || message.v !== 1 || message.type !== "tab-report") return null;
    var fields = fieldsOf(message);
    if (!fields) return null;
    return {
      v: 1,
      type: "tab-report",
      site: fields.site,
      title: fields.title,
      artist: fields.artist,
      album: fields.album,
      state: fields.state,
      time: fields.time,
      duration: fields.duration,
      rate: fields.rate,
      live: fields.live
    };
  }

  /** content script -> service worker: the page has no media to show any more. */
  function validateEnd(message) {
    if (!isObject(message) || message.v !== 1 || message.type !== "tab-end") return null;
    return { v: 1, type: "tab-end" };
  }

  /** service worker -> app: the report with the tab it came from; null when either is not valid. */
  function buildTab(tabId, report) {
    if (!validTabId(tabId)) return null;
    var checked = validateReport(report);
    if (!checked) return null;
    return {
      v: 1,
      type: "tab",
      tab: tabId,
      site: checked.site,
      title: checked.title,
      artist: checked.artist,
      album: checked.album,
      state: checked.state,
      time: checked.time,
      duration: checked.duration,
      rate: checked.rate,
      live: checked.live
    };
  }

  /** service worker -> app: the tab has no media any more (or is closed). */
  function buildGone(tabId) {
    return validTabId(tabId) ? { v: 1, type: "tabgone", tab: tabId } : null;
  }

  /**
   * app -> host -> service worker -> content script. A closed set: exactly {v, type, tab, action} and, for seek only,
   * seconds. A fresh object, or null when the message is anything else.
   */
  function validateTabCommand(message) {
    if (!isObject(message) || message.v !== 1 || message.type !== "tabcommand") return null;
    if (!validTabId(message.tab)) return null;
    var action = message.action;
    if (typeof action !== "string" || !hasOwn(ACTIONS, action) || ACTIONS[action] !== true) return null;
    var keys = Object.keys(message);
    var expected = action === "seek" ? 5 : 4;
    if (keys.length !== expected) return null;
    for (var i = 0; i < keys.length; i++) {
      var key = keys[i];
      if (key !== "v" && key !== "type" && key !== "tab" && key !== "action" && !(action === "seek" && key === "seconds")) return null;
    }
    if (action !== "seek") return { v: 1, type: "tabcommand", tab: message.tab, action: action };
    if (!isNumber(message.seconds) || message.seconds < 0 || message.seconds > MAX_SECONDS) return null;
    return { v: 1, type: "tabcommand", tab: message.tab, action: action, seconds: round3(message.seconds) };
  }

  /**
   * The page script (MAIN world) tells the content script what the page's Media Session holds: the metadata the page set, whether
   * it says it plays or is paused, where it says it is (`setPositionState`), and which actions it has handlers for. That is how a
   * page is known whose media is not an element of the document (an `Audio` the page keeps to itself) and how it is controlled:
   * the page's own handlers are what Chrome's media controls call. Only text, numbers and booleans cross, whatever the page put
   * in them. Gate for window "message" events: this very window, its own origin and the tag.
   */
  function acceptSessionMessage(event, win, origin) {
    if (!event || event.source !== win || event.origin !== origin) return null;
    var data = event.data;
    if (!isObject(data) || data.source !== SOURCE || data.type !== "session") return null;
    var position = null;
    var given = data.position;
    if (isObject(given) && isNumber(given.position) && given.position >= 0 && given.position <= MAX_SECONDS) {
      position = {
        position: given.position,
        duration: isNumber(given.duration) && given.duration > 0 && given.duration <= MAX_SECONDS ? given.duration : null,
        rate: isNumber(given.rate) && given.rate > 0 && given.rate <= MAX_RATE ? given.rate : 1,
        // When the page said it, on the clock the page's and the content script's worlds share; null when it did not say.
        at: isNumber(given.at) ? given.at : null
      };
    }
    return {
      title: clean(data.title, MAX_TITLE),
      artist: clean(data.artist, MAX_NAME),
      album: clean(data.album, MAX_NAME),
      playback: data.playback === "playing" || data.playback === "paused" ? data.playback : "none",
      position: position,
      next: data.next === true,
      previous: data.previous === true,
      play: data.play === true,
      pause: data.pause === true,
      seek: data.seek === true
    };
  }

  /**
   * The content script's request to the page script: call the page's own handler for this action. A seek says to where, in seconds.
   * Null for anything else.
   */
  function buildInvoke(action, seconds) {
    if (action === "seek") {
      return isNumber(seconds) && seconds >= 0 && seconds <= MAX_SECONDS
        ? { source: SOURCE, type: "invoke", action: "seek", seconds: round3(seconds) }
        : null;
    }
    if (action === "next" || action === "previous" || action === "play" || action === "pause") {
      return { source: SOURCE, type: "invoke", action: action };
    }
    return null;
  }

  var api = {
    SOURCE: SOURCE,
    MAX_TITLE: MAX_TITLE,
    MAX_NAME: MAX_NAME,
    MAX_SECONDS: MAX_SECONDS,
    cleanSite: cleanSite,
    cleanText: clean,
    validateReport: validateReport,
    validateEnd: validateEnd,
    buildTab: buildTab,
    buildGone: buildGone,
    validateTabCommand: validateTabCommand,
    acceptSessionMessage: acceptSessionMessage,
    buildInvoke: buildInvoke
  };

  if (typeof module === "object" && module !== null && module.exports) {
    module.exports = api;
  } else {
    Object.defineProperty(root, "__mynotchTabs", { value: api, configurable: true, writable: true });
  }
})(typeof globalThis !== "undefined" ? globalThis : self);
