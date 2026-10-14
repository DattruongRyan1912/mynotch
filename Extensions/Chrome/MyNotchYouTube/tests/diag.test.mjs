import test from "node:test";
import assert from "node:assert/strict";
import { ID_TOKEN, assertSafeDiag, loadCaptions, scannedForIds } from "./helpers.mjs";

const C = loadCaptions();

const diag = (where, event) => ({ v: 1, type: "diag", where, event });

const GOOD = [
  ["sw", "sw-start v=0.1.1"],
  ["sw", "sw-start v=unknown"],
  ["sw", "sw-msg playback"],
  ["sw", "sw-msg clear"],
  ["sw", "sw-msg captions events=123"],
  ["sw", "sw-reject untrusted"],
  ["sw", "sw-reject invalid playback"],
  ["sw", "sw-reject invalid unknown"],
  ["sw", "sw-reconnect after=host-not-found failures=3"],
  ["sw", "sw-access youtube=granted"],
  ["sw", "sw-access youtube=withheld"],
  ["sw", "sw-inject tabs=3 injected=2 failed=1"],
  ["sw", "sw-inject tabs=0 injected=0 failed=0"],
  ["sw", "sw-inject tabs=999999 injected=999999 failed=0"],
  ["sw", "sw-reject invalid command"],
  ["sw", "sw-command-no-tab"],
  ["content", "content-command next ok"],
  ["content", "content-command next unavailable"],
  ["content", "content-command previous ok"],
  ["content", "content-command previous unavailable"],
  ["content", "content-start"],
  ["content", "content-no-lib"],
  ["content", "content-video-found"],
  ["content", "content-video-missing"],
  ["content", "content-cc on"],
  ["content", "content-cc off"],
  ["content", "content-send-error no-receiving-end count=2"],
  ["content", "content-alive videoid-present=true playing=false"],
  ["content", "content-tick-error typeerror-cannot-read-properties-of-null"],
  ["page", "page-wrap fetch=true xhr=false"],
  ["page", "page-wrap-check fetch=false xhr=false"],
  ["page", "page-seen fetch"],
  ["page", "page-seen xhr"],
  ["page", "page-timedtext json3 events=123"],
  ["page", "page-timedtext srv3 events=0"],
  ["page", "page-timedtext other events=0"],
  ["page", "page-timedtext-status 404"],
  ["page", "page-timedtext-parse-error"],
  ["page", "page-timedtext-too-large"],
  ["page", "page-timedtext-failed fetch"]
];

test("validateMessage accepts every documented diag event and keeps only the four fields", () => {
  for (const [where, event] of GOOD) {
    const message = diag(where, event);
    assertSafeDiag(message, where);
    assert.deepEqual(C.validateMessage({ ...message, extra: "x", url: "https://example.invalid/" }), message);
    assert.deepEqual(C.buildDiag(where, event), message);
  }
});

test("validateMessage rejects titles, URLs, ids, free text and malformed shapes", () => {
  const bad = [
    ["sw", "sw-msg my favourite song"], // free text after a known code
    ["sw", "sw-msg playback my favourite song"],
    ["sw", "my favourite song"],
    ["sw", "sw-unknown"],
    ["sw", "sw-start"],
    ["sw", "sw-start v=0.1.1 extra"],
    ["sw", "sw-start v=abcdefghijk"],
    ["sw", "sw-msg playback abcdefghijk"],
    ["sw", "sw-msg captions events=-1"],
    ["sw", "sw-msg captions events=1000000"],
    ["sw", "sw-reject invalid abcdefghijk"],
    ["sw", "sw-reconnect after=https://www.youtube.com failures=1"],
    ["sw", "sw-reconnect after=abcdefghijk failures=1"], // an id-like token as the error token
    ["sw", "sw-reconnect after=Host failures=1"],
    ["sw", "sw-access"],
    ["sw", "sw-access youtube"],
    ["sw", "sw-access youtube="],
    ["sw", "sw-access youtube=maybe"],
    ["sw", "sw-access youtube=GRANTED"],
    ["sw", "sw-access youtube=granted extra"],
    ["sw", "sw-access  youtube=granted"],
    ["sw", "sw-access site=granted"],
    ["sw", "sw-access https://www.youtube.com/*"],
    ["content", "sw-access youtube=granted"], // only the service worker knows
    ["content", "content-access youtube=granted"],
    ["sw", "sw-inject"],
    ["sw", "sw-inject tabs=1"],
    ["sw", "sw-inject tabs=1 injected=1"],
    ["sw", "sw-inject tabs=1 failed=0 injected=1"], // the order is fixed
    ["sw", "sw-inject tabs=1 injected=1 failed=0 extra"],
    ["sw", "sw-inject tabs=1  injected=1 failed=0"],
    ["sw", "sw-inject tabs=-1 injected=0 failed=0"],
    ["sw", "sw-inject tabs=1000000 injected=0 failed=0"], // at most six digits
    ["sw", "sw-inject tabs=x injected=1 failed=0"],
    ["sw", "sw-inject tabs=1 injected=1 failed=abcdefghijk"],
    ["sw", "sw-inject tabs=1 injected=1 failed=0 https://www.youtube.com/watch"],
    ["content", "sw-inject tabs=1 injected=1 failed=0"], // only the service worker injects
    ["content", "content-inject tabs=1 injected=1 failed=0"],
    ["content", "content-cc maybe"],
    ["content", "content-send-error www.youtube.com count=1"],
    ["content", "content-send-error x count=1 extra"],
    ["content", "content-tick-error " + "a".repeat(81)],
    ["content", "content-alive videoid-present=maybe playing=false"],
    ["content", "content-alive  videoid-present=true playing=false"],
    ["content", "content-no-lib extra"],
    ["content", "content-command"],
    ["content", "content-command next"],
    ["content", "content-command ok"],
    ["content", "content-command skip ok"],
    ["content", "content-command next maybe"],
    ["content", "content-command next failed"],
    ["content", "content-command NEXT ok"],
    ["content", "content-command next OK"],
    ["content", "content-command ok next"], // the order is fixed
    ["content", "content-command next ok extra"],
    ["content", "content-command next  ok"],
    ["content", "content-command next ok "],
    ["content", "content-command next ok abcdefghijk"],
    ["content", "content-command next=ok"],
    ["content", "content-command next ok https://www.youtube.com/watch"],
    ["sw", "content-command next ok"], // only the content script performs commands
    ["page", "content-command next ok"],
    ["sw", "sw-command-no-tab extra"],
    ["sw", "sw-command-no-tab "],
    ["sw", "sw-command-no-tab tab=1"],
    ["content", "sw-command-no-tab"], // only the service worker knows whether a tab is there
    ["page", "sw-command-no-tab"],
    // "unavailable" has eleven letters: it is allowed in content-command's closed list and nowhere else
    ["sw", "sw-reconnect after=unavailable failures=1"],
    ["content", "content-send-error unavailable count=1"],
    ["content", "content-tick-error unavailable"],
    ["content", "content-command unavailable ok"],
    ["content", "content-command next unavailable unavailable"],
    ["sw", "sw-reject invalid unavailable"],
    ["sw", "sw-reject invalid commands"],
    ["sw", "sw-reject invalid Command"],
    ["content", "content-no-lib "],
    ["page", "content-no-lib"],
    ["sw", "content-no-lib"],
    ["content", "content-start "],
    ["content", " content-start"],
    ["content", "CONTENT-START"],
    ["page", "page-timedtext json3 events=12 https://www.youtube.com/api/timedtext?v=abcdefghijk"],
    ["page", "page-timedtext json3 events=123\nsecond line"],
    ["page", "page-timedtext vtt events=1"],
    ["page", "page-timedtext-status 4040"],
    ["page", "page-seen https"],
    ["page", "page-wrap fetch=true"],
    // the code must belong to the sender's own part
    ["sw", "content-start"],
    ["content", "sw-msg playback"],
    ["page", "content-start"],
    ["content", "page-seen fetch"],
    // wrong where / event types
    ["extension", "sw-start v=0.1.1"],
    ["", "sw-start v=0.1.1"],
    [undefined, "sw-start v=0.1.1"],
    ["sw", ""],
    ["sw", undefined],
    ["sw", 5],
    ["sw", null],
    ["sw", "sw-start v=0.1.1".padEnd(121, "1")]
  ];
  for (const [where, event] of bad) {
    assert.equal(C.validateMessage(diag(where, event)), null, JSON.stringify([where, event]));
    assert.equal(C.buildDiag(where, event), null, JSON.stringify([where, event]));
  }
  assert.equal(C.validateMessage({ v: 1, type: "diag", event: "sw-start v=0.1.1" }), null);
  assert.equal(C.validateMessage({ v: 1, type: "diag", where: "sw" }), null);
  assert.equal(C.validateMessage({ v: 2, type: "diag", where: "sw", event: "sw-start v=0.1.1" }), null);
});

test("no event of the closed list can be exactly 11 characters long as a token (id lookalike)", () => {
  // The code names themselves never trip the id-lookalike rule.
  for (const [where, event] of GOOD) assert.equal(ID_TOKEN.test(scannedForIds(event)), false, event);
});

test("errorCode: known Chrome errors become fixed codes, everything else a safe token", () => {
  const known = {
    "Extension context invalidated.": "context-invalidated",
    "Could not establish connection. Receiving end does not exist.": "no-receiving-end",
    "Message length exceeded maximum allowed length.": "message-too-long",
    "Specified native messaging host not found.": "host-not-found",
    "Access to the specified native messaging host is forbidden.": "host-forbidden",
    "Native host has exited.": "host-has-exited",
    "Error when communicating with the native messaging host.": "host-comm-error",
    "Failed to start native messaging host.": "host-start-failed",
    "Attempting to use a disconnected port object": "port-disconnected"
  };
  for (const [text, code] of Object.entries(known)) {
    assert.equal(C.errorCode(text), code);
    assert.ok(C.buildDiag("sw", `sw-reconnect after=${code} failures=1`), code);
  }

  // unknown errors: generic words only; quoted parts and every other word become "x"
  assert.equal(C.errorCode("Cannot read properties of null (reading 'foo')"), "cannot-read-properties-of-null-reading");
  assert.equal(C.errorCode("TypeError: x is not a function"), "typeerror-x-is-not-a-function");
  assert.equal(C.errorCode("Some Weird (reading 'x')!"), "x-reading");
  assert.equal(C.errorCode("x x x x"), "x");
  assert.equal(C.errorCode(""), "unknown");
  assert.equal(C.errorCode(undefined), "unknown");
  assert.equal(C.errorCode(42), "unknown");
  assert.equal(C.errorCode("***"), "unknown");
  assert.ok(C.errorCode("read ".repeat(100)).length <= 80);
  assert.ok(C.errorCode("read ".repeat(100)).length > 70);
  // never exactly 11 characters (it would look like a video id)
  assert.equal(C.errorCode("cannot read"), "cannot-read-x");
  assert.notEqual(C.errorCode("cannot read").length, 11);
  for (const text of ["invalidated", "abcdefghijk", "no node", "set value", "read read"]) {
    assert.notEqual(C.errorCode(text).length, 11, text);
    assert.ok(C.buildDiag("content", `content-tick-error ${C.errorCode(text)}`), text);
  }
  assert.ok(C.buildDiag("content", `content-tick-error ${C.errorCode("read ".repeat(500))}`));
});

test("errorCode never lets a title, a URL, an id or a property name through", () => {
  const text = "Failed for https://www.youtube.com/watch?v=abcdefghijk and My Secret Title (reading 'someProperty') abcdefghijk";
  const code = C.errorCode(text);
  assert.match(code, /^[a-z0-9-]+$/);
  for (const leak of ["abcdefghijk", "secret", "title", "youtube", "https", "someproperty", "my"]) {
    assert.equal(code.includes(leak), false, `${leak} in ${code}`);
  }
});

test("typeWord only ever returns a protocol type or 'unknown'", () => {
  for (const type of ["captions", "playback", "clear", "diag"]) assert.equal(C.typeWord({ type }), type);
  for (const value of [{ type: "My Title" }, { type: 5 }, {}, null, undefined, "playback", [], { type: "__proto__" }, { type: "constructor" }]) {
    assert.equal(C.typeWord(value), "unknown", JSON.stringify(value));
  }
});

test("rate limiter: one event per kind every 5 s, the numbers do not make a new kind", () => {
  let time = 1000;
  const allow = C.createDiagLimiter(() => time, 5000);
  assert.equal(allow("sw-msg playback"), true);
  assert.equal(allow("sw-msg playback"), false);
  assert.equal(allow("sw-msg captions events=3"), true, "another kind");
  assert.equal(allow("sw-msg captions events=99"), false, "same kind, other number");
  time += 4999;
  assert.equal(allow("sw-msg playback"), false);
  time += 1;
  assert.equal(allow("sw-msg playback"), true, "5 s later");
  assert.equal(allow("sw-msg captions events=7"), true);
  assert.equal(allow("content-alive videoid-present=true playing=true"), true);
  assert.equal(allow("content-alive videoid-present=false playing=false"), false);
});

test("rate limiter: survives clock changes and a bounded table", () => {
  let time = 1000000;
  const allow = C.createDiagLimiter(() => time, 5000);
  assert.equal(allow("a"), true);
  time -= 60000; // the clock moved back
  assert.equal(allow("a"), true);

  // forged distinct events cannot grow the table beyond its bound
  const bounded = C.createDiagLimiter(() => time, 5000);
  let accepted = 0;
  for (let i = 0; i < 1000; i++) if (bounded(`kind${i}`)) accepted++;
  assert.equal(accepted, 128);
  time += 5000; // everything expired: room again
  assert.equal(bounded("kind-new"), true);
});

test("parseBody reports the format and distinguishes a parse error from an empty track", () => {
  const json3 = JSON.stringify({ events: [{ tStartMs: 1000, dDurationMs: 500, segs: [{ utf8: "line one" }] }] });
  assert.deepEqual(C.parseBody(json3), { format: "json3", events: [{ t: 1, d: 0.5, text: "line one" }], error: false });
  assert.deepEqual(C.parseBody({ events: [] }), { format: "json3", events: [], error: false });
  assert.deepEqual(C.parseBody('<p t="1000" d="500">line one</p>'), { format: "srv3", events: [{ t: 1, d: 0.5, text: "line one" }], error: false });
  assert.deepEqual(C.parseBody("{broken"), { format: "json3", events: [], error: true });
  assert.deepEqual(C.parseBody("WEBVTT"), { format: "other", events: [], error: false });
  assert.deepEqual(C.parseBody(""), { format: "other", events: [], error: false });
  assert.deepEqual(C.parseBody(undefined), { format: "other", events: [], error: false });
  assert.deepEqual(C.parseBody("﻿ \n" + json3).format, "json3");
});

test("acceptPageMessage lets only page-side diag through, as a clean message", () => {
  const win = {};
  const origin = "https://www.youtube.com";
  const event = (data, overrides = {}) => ({ source: win, origin, data: { source: "mynotch-yt", ...data }, ...overrides });

  const accepted = C.acceptPageMessage(event({ ...diag("page", "page-seen fetch"), url: "https://example.invalid/" }), win, origin);
  assert.deepEqual(accepted, diag("page", "page-seen fetch"));

  for (const candidate of [
    event(diag("sw", "sw-start v=0.1.1")),
    event(diag("content", "content-start")),
    event(diag("page", "page-seen fetch"), { source: {} }),
    event(diag("page", "page-seen fetch"), { origin: "https://evil.example" }),
    event(diag("page", "page-seen https")),
    event(diag("page", "page-timedtext json3 events=1 abcdefghijk")),
    { source: win, origin, data: diag("page", "page-seen fetch") } // no source tag
  ]) {
    assert.equal(C.acceptPageMessage(candidate, win, origin), null, JSON.stringify(candidate.data));
  }
});
