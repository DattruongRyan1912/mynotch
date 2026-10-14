import test from "node:test";
import assert from "node:assert/strict";
import { loadCaptions } from "./helpers.mjs";

const C = loadCaptions();
const ID = "abcdefghijk";

const captions = (overrides = {}) => ({
  v: 1,
  type: "captions",
  videoId: ID,
  lang: "vi",
  kind: "standard",
  events: [
    { t: 1, d: 1.5, text: "line one" },
    { t: 2.5, d: 2, text: "line two" }
  ],
  ...overrides
});

const playback = (overrides = {}) => ({
  v: 1,
  type: "playback",
  videoId: ID,
  title: "Placeholder title",
  time: 12.3,
  playing: true,
  rate: 1,
  ...overrides
});

test("validateMessage accepts well-formed captions, playback and clear", () => {
  assert.deepEqual(C.validateMessage(captions()), captions());
  assert.deepEqual(C.validateMessage(playback()), playback());
  assert.deepEqual(C.validateMessage({ v: 1, type: "clear", videoId: ID }), { v: 1, type: "clear", videoId: ID });
});

test("validateMessage returns a fresh object with protocol fields only", () => {
  const dirty = captions({ url: "https://example.invalid/?token=secret", cookie: "x" });
  dirty.events[0].extra = "x";
  const clean = C.validateMessage(dirty);
  assert.deepEqual(Object.keys(clean).sort(), ["events", "kind", "lang", "type", "v", "videoId"]);
  assert.deepEqual(Object.keys(clean.events[0]).sort(), ["d", "t", "text"]);
  assert.notEqual(clean, dirty);

  const clear = C.validateMessage({ v: 1, type: "clear", videoId: ID, url: "https://example.invalid/" });
  assert.deepEqual(Object.keys(clear).sort(), ["type", "v", "videoId"]);
  const pb = C.validateMessage(playback({ href: "https://example.invalid/" }));
  assert.equal("href" in pb, false);
});

test("validateMessage rejects wrong envelope", () => {
  for (const value of [null, undefined, 5, "text", [], {}, { type: "clear", videoId: ID }, { v: 2, type: "clear", videoId: ID }, { v: "1", type: "clear", videoId: ID }, { v: 1, type: "other", videoId: ID }, { v: 1, videoId: ID }]) {
    assert.equal(C.validateMessage(value), null, JSON.stringify(value));
  }
});

test("validateMessage rejects bad video ids on every type", () => {
  for (const videoId of ["", "short", "waytoolongvideoid", "bad id here", "bad/id/here", "aaaaaaaaaa!", 12345678901, null, undefined]) {
    assert.equal(C.validateMessage(captions({ videoId })), null, String(videoId));
    assert.equal(C.validateMessage(playback({ videoId })), null, String(videoId));
    assert.equal(C.validateMessage({ v: 1, type: "clear", videoId }), null, String(videoId));
  }
  assert.ok(C.validateMessage({ v: 1, type: "clear", videoId: "A-_09zZ0123" }));
});

test("captions: language and kind are validated", () => {
  assert.ok(C.validateMessage(captions({ lang: "pt-BR" })));
  assert.ok(C.validateMessage(captions({ lang: "zh-Hans" })));
  assert.ok(C.validateMessage(captions({ lang: "und", kind: "asr" })));
  for (const lang of ["", "toolonglanguagecode", "en US", "../x", 5, null]) {
    assert.equal(C.validateMessage(captions({ lang })), null, String(lang));
  }
  for (const kind of ["", "ASR", "auto", 1, null]) {
    assert.equal(C.validateMessage(captions({ kind })), null, String(kind));
  }
});

test("captions: events are re-validated, sorted and clamped", () => {
  const clean = C.validateMessage(
    captions({
      events: [
        { t: 5, d: 1, text: "  later \n line " },
        { t: 1, d: 1, text: "w".repeat(900) },
        { t: 3, d: 1, text: "   " }
      ]
    })
  );
  assert.deepEqual(
    clean.events.map((event) => event.t),
    [1, 5]
  );
  assert.equal(clean.events[0].text.length, 500);
  assert.equal(clean.events[1].text, "later line");

  for (const bad of [
    [],
    "nope",
    [{ t: -1, d: 1, text: "x" }],
    [{ t: 1, d: -1, text: "x" }],
    [{ t: NaN, d: 1, text: "x" }],
    [{ t: Infinity, d: 1, text: "x" }],
    [{ t: "1", d: 1, text: "x" }],
    [{ t: 1, d: 1, text: 5 }],
    [{ t: 1, d: 1 }],
    [null],
    [{ t: 1, d: 1, text: "ok" }, 7],
    [{ t: 1, d: 1, text: "   " }] // nothing usable is left
  ]) {
    assert.equal(C.validateMessage(captions({ events: bad })), null, JSON.stringify(bad));
  }
});

test("captions: more than 5000 events is rejected, exactly 5000 is accepted", () => {
  const make = (count) => Array.from({ length: count }, (_, i) => ({ t: i, d: 1, text: `w${i}` }));
  assert.equal(C.validateMessage(captions({ events: make(5001) })), null);
  assert.equal(C.validateMessage(captions({ events: make(5000) })).events.length, 5000);
});

test("playback: fields are validated and normalised", () => {
  assert.deepEqual(C.validateMessage(playback({ time: 12.34567, rate: 1.25, playing: false, title: "  two \n words " })), {
    v: 1,
    type: "playback",
    videoId: ID,
    title: "two words",
    time: 12.346,
    playing: false,
    rate: 1.25
  });
  assert.equal(C.validateMessage(playback({ title: "t".repeat(900) })).title.length, 300);
  assert.ok(C.validateMessage(playback({ time: 0 })));
  assert.ok(C.validateMessage(playback({ rate: 0.25 })));
  assert.ok(C.validateMessage(playback({ rate: 16 })));
  const rejected = [
    { title: "" },
    { title: "   " },
    { title: 5 },
    { time: -0.1 },
    { time: NaN },
    { time: "3" },
    { time: null },
    { playing: "true" },
    { playing: 1 },
    { rate: 0 },
    { rate: -1 },
    { rate: 17 },
    { rate: Infinity },
    { rate: "1" }
  ];
  for (const overrides of rejected) assert.equal(C.validateMessage(playback(overrides)), null, JSON.stringify(overrides));
});

function pageEvent(data, overrides = {}) {
  const win = {};
  return { win, event: { source: win, origin: "https://www.youtube.com", data, ...overrides } };
}

test("acceptPageMessage: only same-window, same-origin, tagged captions pass", () => {
  const origin = "https://www.youtube.com";
  const good = { source: "mynotch-yt", ...captions() };

  const { win, event } = pageEvent(good);
  assert.deepEqual(C.acceptPageMessage(event, win, origin), captions());

  const other = pageEvent(good);
  assert.equal(C.acceptPageMessage({ ...other.event, source: {} }, other.win, origin), null, "another window");
  assert.equal(C.acceptPageMessage({ ...other.event, source: null }, other.win, origin), null, "no source");
  assert.equal(C.acceptPageMessage({ ...other.event, origin: "https://evil.example" }, other.win, origin), null, "another origin");
  assert.equal(C.acceptPageMessage({ ...other.event, origin: "null" }, other.win, origin), null, "opaque origin");

  for (const data of [
    { ...captions() }, // missing source tag
    { source: "other", ...captions() },
    { source: "mynotch-yt", ...playback() }, // only captions may come from the page
    { source: "mynotch-yt", v: 1, type: "clear", videoId: ID },
    { source: "mynotch-yt", ...captions({ events: [] }) },
    { source: "mynotch-yt", ...captions({ videoId: "bad" }) },
    "mynotch-yt",
    null,
    [good]
  ]) {
    const attempt = pageEvent(data);
    assert.equal(C.acceptPageMessage(attempt.event, attempt.win, origin), null, JSON.stringify(data));
  }
  assert.equal(C.acceptPageMessage(null, win, origin), null);
});

test("acceptPageMessage strips the source tag and anything unknown", () => {
  const { win, event } = pageEvent({ source: "mynotch-yt", ...captions(), url: "https://example.invalid/?pot=secret" });
  const accepted = C.acceptPageMessage(event, win, "https://www.youtube.com");
  assert.equal("source" in accepted, false);
  assert.equal("url" in accepted, false);
});

test("videoIdFromUrl: watch, shorts, live and missing", () => {
  const id = "dQw4w9WgXcQ";
  assert.equal(C.videoIdFromUrl(`https://www.youtube.com/watch?v=${id}`), id);
  assert.equal(C.videoIdFromUrl(`https://www.youtube.com/watch?list=abc&v=${id}&t=30s`), id);
  assert.equal(C.videoIdFromUrl(`https://www.youtube.com/shorts/${id}`), id);
  assert.equal(C.videoIdFromUrl(`https://www.youtube.com/shorts/${id}/`), id);
  assert.equal(C.videoIdFromUrl(`https://www.youtube.com/shorts/${id}?feature=share`), id);
  assert.equal(C.videoIdFromUrl(`https://www.youtube.com/live/${id}`), id);

  for (const href of [
    "https://www.youtube.com/",
    "https://www.youtube.com/feed/subscriptions",
    "https://www.youtube.com/results?search_query=placeholder",
    "https://www.youtube.com/watch",
    "https://www.youtube.com/watch?v=",
    "https://www.youtube.com/watch?v=short",
    `https://www.youtube.com/watch?v=${id}extra`,
    `https://www.youtube.com/watch/${id}`,
    "https://www.youtube.com/shorts/",
    "https://www.youtube.com/shorts/short",
    `https://www.youtube.com/shorts/${id}/more`,
    `https://www.youtube.com/channel/${id}`,
    "not a url",
    "",
    null,
    undefined
  ]) {
    assert.equal(C.videoIdFromUrl(href), null, String(href));
  }
});

test("cleanTitle strips the YouTube suffix and the notification counter", () => {
  assert.equal(C.cleanTitle("Placeholder title - YouTube"), "Placeholder title");
  assert.equal(C.cleanTitle("(3) Placeholder title - YouTube"), "Placeholder title");
  assert.equal(C.cleanTitle("(12+) Placeholder - title - YouTube"), "Placeholder - title");
  assert.equal(C.cleanTitle("  Placeholder \n title  "), "Placeholder title");
  assert.equal(C.cleanTitle("Placeholder title"), "Placeholder title");
  assert.equal(C.cleanTitle("YouTube"), "YouTube");
  assert.equal(C.cleanTitle("Mentions YouTube - Music"), "Mentions YouTube - Music");
  assert.equal(C.cleanTitle(""), "");
  assert.equal(C.cleanTitle(undefined), "");
  assert.equal(C.cleanTitle("t".repeat(900) + " - YouTube").length, 300);
});
