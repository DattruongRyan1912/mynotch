import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { extensionDir, loadCaptions } from "./helpers.mjs";

const C = loadCaptions();

// All fixtures are synthetic placeholder text.
const json3Body = {
  wireMagic: "pb3",
  events: [
    { tStartMs: 0, dDurationMs: 1500, id: 1, wpWinPosId: 1 }, // window definition, no segs
    { tStartMs: 2500, dDurationMs: 2000, segs: [{ utf8: "line two" }] },
    { tStartMs: 1000, dDurationMs: 1500, segs: [{ utf8: "line" }, { utf8: " one" }] },
    { tStartMs: 5000, dDurationMs: 800, segs: [{ utf8: "\n" }] }, // only a line break
    { tStartMs: 6000, dDurationMs: 1000, segs: [{ utf8: "  spaced \n  out  " }, { utf8: "words" }] },
    { tStartMs: 8000, segs: [{ utf8: "[Music]" }] }
  ]
};

test("json3: events are mapped to seconds, sorted, joined and cleaned", () => {
  assert.deepEqual(C.eventsFromJson3(json3Body), [
    { t: 1, d: 1.5, text: "line one" },
    { t: 2.5, d: 2, text: "line two" },
    { t: 6, d: 1, text: "spaced out words" },
    { t: 8, d: 0, text: "[Music]" }
  ]);
});

test("json3: accepts a JSON string and survives garbage", () => {
  assert.equal(C.eventsFromJson3(JSON.stringify(json3Body)).length, 4);
  assert.deepEqual(C.eventsFromJson3("not json"), []);
  assert.deepEqual(C.eventsFromJson3({}), []);
  assert.deepEqual(C.eventsFromJson3({ events: "nope" }), []);
  assert.deepEqual(C.eventsFromJson3(null), []);
  assert.deepEqual(
    C.eventsFromJson3({
      events: [
        null,
        42,
        { tStartMs: -5, segs: [{ utf8: "negative" }] },
        { tStartMs: "1000", segs: [{ utf8: "string time" }] },
        { tStartMs: 1000, segs: [null, { utf8: 7 }, { utf8: "ok" }] }
      ]
    }),
    [{ t: 1, d: 0, text: "ok" }]
  );
});

const srv3Body = [
  '<?xml version="1.0" encoding="utf-8" ?>',
  '<timedtext format="3"><head><pen id="1"/></head><body>',
  '<p t="2500" d="2000" w="1">line two</p>',
  '<p t="1000" d="1500"><s>line</s><s t="400"> one</s></p>',
  '<p t="4000" d="500">fish &amp; chips &lt;3 &#39;quoted&#39; &#x41;</p>',
  '<p t="5000" d="500">   </p>',
  '<p t="5500" d="500"/>',
  '<p t="6000" d="700">first\nsecond</p>',
  "</body></timedtext>"
].join("\n");

test("srv3: <p t d> with <s> children is parsed, entities decoded, sorted", () => {
  assert.deepEqual(C.eventsFromSrv3(srv3Body), [
    { t: 1, d: 1.5, text: "line one" },
    { t: 2.5, d: 2, text: "line two" },
    { t: 4, d: 0.5, text: "fish & chips <3 'quoted' A" },
    { t: 6, d: 0.7, text: "first second" }
  ]);
});

test("srv3: malformed input yields no events and never throws", () => {
  assert.deepEqual(C.eventsFromSrv3(""), []);
  assert.deepEqual(C.eventsFromSrv3("<timedtext><body><p t='x' d='1'>bad time</p></body></timedtext>"), []);
  assert.deepEqual(C.eventsFromSrv3("<p t='1000'>"), []);
  assert.deepEqual(C.eventsFromSrv3(null), []);
  // single-quoted attributes and an invalid numeric entity
  assert.deepEqual(C.eventsFromSrv3("<p t='1000' d='500'>a&#1114112;b</p>"), [{ t: 1, d: 0.5, text: "ab" }]);
});

test("srv3: numeric entities are decoded even when the text was escaped twice", () => {
  assert.deepEqual(C.eventsFromSrv3("<p t='1000' d='500'>it&amp;#39;s &amp;#x41;&#66;</p>"), [{ t: 1, d: 0.5, text: "it's AB" }]);
  // named entities are decoded once: this is literal text that looks like an entity
  assert.deepEqual(C.eventsFromSrv3("<p t='1000' d='500'>fish &amp;amp; chips</p>"), [{ t: 1, d: 0.5, text: "fish &amp; chips" }]);
});

test("srv3: &nbsp; becomes a space and unknown entities stay literal", () => {
  assert.deepEqual(C.eventsFromSrv3("<p t='1000' d='500'>a&nbsp;b &unknown; c</p>"), [{ t: 1, d: 0.5, text: "a b &unknown; c" }]);
});

test("json3: ASR-shaped tracks keep one event per segs, ignoring aAppend, tOffsetMs and overlap", () => {
  const asr = {
    wireMagic: "pb3",
    events: [
      { tStartMs: 0, dDurationMs: 4000, wWinId: 1, segs: [{ utf8: "first" }, { utf8: " words", tOffsetMs: 400 }, { utf8: " here", tOffsetMs: 800 }] },
      { tStartMs: 3000, dDurationMs: 1000, wWinId: 1, aAppend: 1, segs: [{ utf8: "\n" }] },
      { tStartMs: 3000, dDurationMs: 4000, wWinId: 1, segs: [{ utf8: "second", acAsrConf: 0 }, { utf8: " line", tOffsetMs: 300, acAsrConf: 0 }] }
    ]
  };
  assert.deepEqual(C.eventsFromJson3(asr), [
    { t: 0, d: 4, text: "first words here" },
    { t: 3, d: 4, text: "second line" }
  ]);
});

test("eventsFromBody sniffs json3, srv3 and ignores everything else", () => {
  assert.equal(C.eventsFromBody(JSON.stringify(json3Body)).length, 4);
  assert.equal(C.eventsFromBody("﻿  \n" + JSON.stringify(json3Body)).length, 4);
  assert.equal(C.eventsFromBody(json3Body).length, 4);
  assert.equal(C.eventsFromBody(srv3Body).length, 4);
  assert.deepEqual(C.eventsFromBody("WEBVTT\n\n00:01.000 --> 00:02.000\nline one"), []);
  assert.deepEqual(C.eventsFromBody(""), []);
  assert.deepEqual(C.eventsFromBody(undefined), []);
  assert.deepEqual(C.eventsFromBody(12), []);
});

test("normalizeText: newlines to spaces, collapsed, trimmed, control characters removed", () => {
  assert.equal(C.normalizeText("  a\nb\r\n\tc   d  "), "a b c d");
  assert.equal(C.normalizeText("x\u0000y\u007fz"), "x y z");
  assert.equal(C.normalizeText("[Music]"), "[Music]");
  assert.equal(C.normalizeText("\n \t"), "");
  assert.equal(C.normalizeText(null), "");
  assert.equal(C.normalizeText(5), "");
});

test("limits: text is cut at 500 characters, never inside a surrogate pair", () => {
  const long = "w".repeat(900);
  const [event] = C.eventsFromJson3({ events: [{ tStartMs: 0, segs: [{ utf8: long }] }] });
  assert.equal(event.text.length, 500);

  // 499 plain characters then an astral character: the pair would straddle the cut.
  const astral = "a".repeat(499) + "\u{1F600}tail";
  const [cut] = C.eventsFromJson3({ events: [{ tStartMs: 0, segs: [{ utf8: astral }] }] });
  assert.equal(cut.text, "a".repeat(499));

  // trailing space at the cut point is trimmed
  const spaced = "b".repeat(499) + " c";
  const [trimmed] = C.eventsFromJson3({ events: [{ tStartMs: 0, segs: [{ utf8: spaced }] }] });
  assert.equal(trimmed.text, "b".repeat(499));
});

test("limits: at most 5000 events, the earliest ones are kept", () => {
  const events = [];
  for (let i = 0; i < 6200; i++) events.push({ tStartMs: (6200 - i) * 10, dDurationMs: 5, segs: [{ utf8: `w${i}` }] });
  const parsed = C.eventsFromJson3({ events });
  assert.equal(parsed.length, C.MAX_EVENTS);
  assert.equal(parsed.length, 5000);
  assert.equal(parsed[0].t, 0.01);
  assert.ok(parsed.every((event, i) => i === 0 || parsed[i - 1].t <= event.t));
  assert.equal(parsed[4999].t, 50);

  const xml = "<body>" + events.map((e) => `<p t="${e.tStartMs}" d="5">x</p>`).join("") + "</body>";
  assert.equal(C.eventsFromSrv3(xml).length, 5000);
});

test("limits: the serialized message stays below the 4 MiB host frame", () => {
  const events = [];
  for (let i = 0; i < 5000; i++) events.push({ tStartMs: i, segs: [{ utf8: '"'.repeat(500) }] });
  const message = C.buildCaptionsMessage({ videoId: "aaaaaaaaaaa", lang: "en", kind: "standard", events: C.eventsFromJson3({ events }) });
  assert.ok(message.events.length < 5000);
  assert.ok(Buffer.byteLength(JSON.stringify(message)) < 4 * 1024 * 1024);
});

test("parseTimedTextUrl reads video id, language and kind and ignores other URLs", () => {
  const base = "https://www.youtube.com/watch?v=aaaaaaaaaaa";
  assert.deepEqual(
    C.parseTimedTextUrl("https://www.youtube.com/api/timedtext?v=abcdefghijk&lang=vi&fmt=json3&pot=secret&sig=secret", base),
    { videoId: "abcdefghijk", lang: "vi", kind: "standard" }
  );
  assert.deepEqual(C.parseTimedTextUrl("/api/timedtext?v=abcdefghijk&lang=en&kind=asr", base), {
    videoId: "abcdefghijk",
    lang: "en",
    kind: "asr"
  });
  assert.equal(C.parseTimedTextUrl("/api/timedtext?v=abcdefghijk&lang=en&tlang=fr", base).lang, "fr");
  assert.equal(C.parseTimedTextUrl("/api/timedtext?v=abcdefghijk&kind=other", base).kind, "standard");
  assert.equal(C.parseTimedTextUrl("https://www.youtube.com/api/timedtext/other?v=abcdefghijk", base), null);
  assert.equal(C.parseTimedTextUrl("https://www.youtube.com/youtubei/v1/player?v=abcdefghijk", base), null);
  assert.equal(C.parseTimedTextUrl("http://[bad", base), null);
});

test("buildCaptionsMessage builds the protocol message and refuses unusable input", () => {
  const events = [{ t: 1, d: 1, text: "line one" }];
  assert.deepEqual(C.buildCaptionsMessage({ videoId: "abcdefghijk", lang: "vi", kind: "asr", events }), {
    v: 1,
    type: "captions",
    videoId: "abcdefghijk",
    lang: "vi",
    kind: "asr",
    events
  });
  assert.equal(C.buildCaptionsMessage({ videoId: "abcdefghijk", lang: "", kind: "x", events }).lang, "und");
  assert.equal(C.buildCaptionsMessage({ videoId: "abcdefghijk", lang: "en", kind: "x", events }).kind, "standard");
  assert.equal(C.buildCaptionsMessage({ videoId: "short", lang: "en", kind: "asr", events }), null);
  assert.equal(C.buildCaptionsMessage({ videoId: "abcdefghijk", lang: "en", kind: "asr", events: [] }), null);
  assert.equal(C.buildCaptionsMessage(null), null);
});

test("captions.js also works through require()", () => {
  const api = createRequire(import.meta.url)(`${extensionDir}/captions.js`);
  assert.equal(typeof api.validateMessage, "function");
  assert.equal(api.MAX_EVENTS, 5000);
  assert.equal(api.MAX_TEXT, 500);
});
