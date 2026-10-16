import test from "node:test";
import assert from "node:assert/strict";
import { loadTabs } from "./helpers.mjs";

const T = loadTabs();

const report = (overrides = {}) => ({
  v: 1,
  type: "tab-report",
  site: "music.example.com",
  title: "Song",
  artist: "Artist",
  album: "Album",
  state: "playing",
  time: 12.3456,
  duration: 200,
  rate: 1,
  live: false,
  ...overrides
});

test("a report is a fresh object with exactly the protocol fields, and the numbers are rounded to milliseconds", () => {
  const dirty = report({ url: "https://example.invalid/?token=secret", cookie: "x", artwork: "https://example.invalid/a.png" });
  const clean = T.validateReport(dirty);
  assert.deepEqual(Object.keys(clean).sort(), ["album", "artist", "duration", "live", "rate", "site", "state", "time", "title", "type", "v"]);
  assert.notEqual(clean, dirty);
  assert.equal(clean.time, 12.346);
});

test("a report without artist, album or duration still validates: the text is empty, the duration is null", () => {
  const clean = T.validateReport(report({ artist: undefined, album: undefined, duration: null, live: true }));
  assert.equal(clean.artist, "");
  assert.equal(clean.album, "");
  assert.equal(clean.duration, null);
  assert.equal(clean.live, true);
  assert.equal(T.validateReport(report({ site: "" })).site, "");
});

test("a report is refused when its envelope, text, numbers or flags are wrong", () => {
  const bad = [
    null, undefined, 5, "x", [], {},
    report({ v: 2 }), report({ v: "1" }), report({ type: "tab" }), report({ type: "tabgone" }),
    report({ title: "" }), report({ title: "   \n " }), report({ title: 5 }), report({ title: undefined }),
    report({ site: undefined }), report({ site: "Example.COM" }), report({ site: "a b" }), report({ site: "x/y" }),
    report({ site: "https://example.com" }), report({ site: "a:80" }), report({ site: "-a.com" }), report({ site: "a".repeat(101) }),
    report({ state: "stopped" }), report({ state: "PLAYING" }), report({ state: true }), report({ state: undefined }),
    report({ time: -1 }), report({ time: NaN }), report({ time: Infinity }), report({ time: "1" }), report({ time: 1e8 }),
    report({ duration: -1 }), report({ duration: Infinity }), report({ duration: "3" }), report({ duration: undefined }),
    report({ rate: 0 }), report({ rate: -1 }), report({ rate: 17 }), report({ rate: NaN }), report({ rate: "1" }),
    report({ live: "false" }), report({ live: undefined }), report({ live: 0 })
  ];
  for (const value of bad) assert.equal(T.validateReport(value), null, JSON.stringify(value));
});

test("report text is cleaned and cut: control characters and runs of spaces collapse, a title is at most 300 units, other names 200", () => {
  const clean = T.validateReport(report({ title: "  A\u0000\n  B\t C ", artist: "x".repeat(500), album: "😀".repeat(150) }));
  assert.equal(clean.title, "A B C");
  assert.equal(clean.artist.length, 200);
  assert.ok(clean.album.length <= 200 && !/[\ud800-\udbff]$/.test(clean.album), "no split surrogate pair");
  assert.equal(T.validateReport(report({ title: "t".repeat(400) })).title.length, 300);
});

test("tab-end is exactly {v, type}; anything else is refused", () => {
  assert.deepEqual(T.validateEnd({ v: 1, type: "tab-end", extra: 1 }), { v: 1, type: "tab-end" });
  for (const value of [null, {}, { v: 1 }, { v: 2, type: "tab-end" }, { v: 1, type: "tabgone" }, { v: 1, type: "tab-report" }]) {
    assert.equal(T.validateEnd(value), null, JSON.stringify(value));
  }
});

test("buildTab puts the tab id on a valid report and nothing else; a bad id or report gives nothing", () => {
  const message = T.buildTab(7, report({ url: "https://example.invalid/" }));
  assert.deepEqual(message, {
    v: 1,
    type: "tab",
    tab: 7,
    site: "music.example.com",
    title: "Song",
    artist: "Artist",
    album: "Album",
    state: "playing",
    time: 12.346,
    duration: 200,
    rate: 1,
    live: false
  });
  assert.ok(T.buildTab(0, report()));
  assert.ok(T.buildTab(2147483647, report()));
  for (const id of [-1, 1.5, NaN, Infinity, "7", null, undefined, 2147483648]) assert.equal(T.buildTab(id, report()), null, String(id));
  assert.equal(T.buildTab(7, report({ title: "" })), null);
  assert.equal(T.buildTab(7, { v: 1, type: "tab", tab: 7 }), null, "a tab message is not a report");
});

test("buildGone", () => {
  assert.deepEqual(T.buildGone(3), { v: 1, type: "tabgone", tab: 3 });
  for (const id of [-1, 0.5, NaN, "3", null, undefined]) assert.equal(T.buildGone(id), null, String(id));
});

test("cleanSite keeps a plain host name and drops anything else", () => {
  assert.equal(T.cleanSite("music.youtube.com"), "music.youtube.com");
  assert.equal(T.cleanSite("localhost"), "localhost");
  assert.equal(T.cleanSite("xn--bcher-kva.example"), "xn--bcher-kva.example");
  for (const value of ["", "UPPER.com", "[::1]", "a b", "a/b", "a:1", "a?b", undefined, null, 5, "a".repeat(101)]) {
    assert.equal(T.cleanSite(value), "", String(value));
  }
});

test("validateTabCommand accepts the six actions as a fresh closed object, seek with seconds", () => {
  for (const action of ["play", "pause", "toggle", "next", "previous"]) {
    const input = { v: 1, type: "tabcommand", tab: 5, action };
    const clean = T.validateTabCommand(input);
    assert.deepEqual(clean, input);
    assert.notEqual(clean, input);
    assert.deepEqual(Object.keys(clean), ["v", "type", "tab", "action"]);
  }
  const seek = T.validateTabCommand({ v: 1, type: "tabcommand", tab: 5, action: "seek", seconds: 61.23456 });
  assert.deepEqual(seek, { v: 1, type: "tabcommand", tab: 5, action: "seek", seconds: 61.235 });
  assert.equal(T.validateTabCommand({ v: 1, type: "tabcommand", tab: 0, action: "seek", seconds: 0 }).seconds, 0);
});

test("validateTabCommand is closed: another action, field, type, tab id or seconds is refused", () => {
  const ok = { v: 1, type: "tabcommand", tab: 5, action: "play" };
  const bad = [
    null, undefined, 5, "play", [], {},
    { ...ok, v: 2 }, { ...ok, v: "1" }, { ...ok, type: "command" }, { ...ok, type: "TabCommand" },
    { ...ok, action: "stop" }, { ...ok, action: "PLAY" }, { ...ok, action: " play" }, { ...ok, action: "" }, { ...ok, action: null },
    { ...ok, action: ["play"] }, { ...ok, action: "toString" }, { ...ok, action: "__proto__" }, { ...ok, action: "constructor" },
    { ...ok, tab: -1 }, { ...ok, tab: 1.5 }, { ...ok, tab: "5" }, { ...ok, tab: NaN }, { ...ok, tab: 2147483648 }, { v: 1, type: "tabcommand", action: "play" },
    { ...ok, url: "https://example.invalid/" }, { ...ok, seconds: 5 },
    { v: 1, type: "tabcommand", tab: 5, action: "seek" },
    { v: 1, type: "tabcommand", tab: 5, action: "seek", seconds: -1 },
    { v: 1, type: "tabcommand", tab: 5, action: "seek", seconds: NaN },
    { v: 1, type: "tabcommand", tab: 5, action: "seek", seconds: "5" },
    { v: 1, type: "tabcommand", tab: 5, action: "seek", seconds: 1e8 },
    { v: 1, type: "tabcommand", tab: 5, action: "seek", seconds: 5, url: "x" },
    Object.assign(Object.create({ type: "tabcommand" }), { v: 1, tab: 5, action: "play", extra: 1 })
  ];
  for (const value of bad) assert.equal(T.validateTabCommand(value), null, JSON.stringify(value));
});

test("a session message from the page script is read as text and two booleans, and only from this window with the tag", () => {
  const win = {};
  const event = (data, overrides = {}) => ({ source: win, origin: "https://site.example", data: { source: "mynotch-tab", ...data }, ...overrides });
  const accepted = T.acceptSessionMessage(
    event({ type: "session", title: " Song\n", artist: "A", album: "B", next: true, previous: false, extra: "https://example.invalid/", url: "x" }),
    win,
    "https://site.example"
  );
  assert.deepEqual(accepted, { title: "Song", artist: "A", album: "B", next: true, previous: false });
  assert.deepEqual(
    T.acceptSessionMessage(event({ type: "session", title: 5, next: "yes" }), win, "https://site.example"),
    { title: "", artist: "", album: "", next: false, previous: false }
  );
  assert.equal(T.acceptSessionMessage(event({ type: "session", title: "x" }, { source: {} }), win, "https://site.example"), null);
  assert.equal(T.acceptSessionMessage(event({ type: "session", title: "x" }, { origin: "https://evil.example" }), win, "https://site.example"), null);
  assert.equal(T.acceptSessionMessage(event({ type: "session", title: "x", source: "mynotch-yt" }), win, "https://site.example"), null);
  assert.equal(T.acceptSessionMessage(event({ type: "invoke", action: "next" }), win, "https://site.example"), null);
  assert.equal(T.acceptSessionMessage(event({ type: "captions" }), win, "https://site.example"), null);
  assert.equal(T.acceptSessionMessage({ source: win, origin: "https://site.example", data: "text" }, win, "https://site.example"), null);
  assert.equal(T.acceptSessionMessage(null, win, "https://site.example"), null);
});

test("buildInvoke names only the next and the previous track", () => {
  assert.deepEqual(T.buildInvoke("next"), { source: "mynotch-tab", type: "invoke", action: "next" });
  assert.deepEqual(T.buildInvoke("previous"), { source: "mynotch-tab", type: "invoke", action: "previous" });
  for (const action of ["play", "seek", "", null, undefined, "Next"]) assert.equal(T.buildInvoke(action), null, String(action));
});
