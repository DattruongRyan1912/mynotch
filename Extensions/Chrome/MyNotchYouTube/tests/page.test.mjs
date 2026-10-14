import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { createContext, flush, plain, runScripts } from "./helpers.mjs";

const SCRIPTS = ["captions.js", "page.js"];
const ORIGIN = "https://www.youtube.com";
const TIMEDTEXT = `${ORIGIN}/api/timedtext?v=abcdefghijk&lang=vi&fmt=json3&pot=SECRET_TOKEN&sig=SECRET_SIG`;

// Synthetic placeholder captions.
const json3 = JSON.stringify({
  events: [
    { tStartMs: 2000, dDurationMs: 1000, segs: [{ utf8: "line two" }] },
    { tStartMs: 500, dDurationMs: 1000, segs: [{ utf8: "line one" }] }
  ]
});
const srv3 = '<timedtext format="3"><body><p t="500" d="1000"><s>line one</s></p><p t="2000" d="1000">line two</p></body></timedtext>';
const expectedEvents = [
  { t: 0.5, d: 1, text: "line one" },
  { t: 2, d: 1, text: "line two" }
];

class FakeXhr {
  constructor() {
    this.listeners = {};
    this.responseType = "";
    this.status = 0;
    this.responseText = "";
    this.response = null;
  }
  open(method, url) {
    if (url === "bad") throw new SyntaxError("bad url");
    this.url = url;
    return "open-result";
  }
  addEventListener(type, listener) {
    (this.listeners[type] ??= new Set()).add(listener);
  }
  finish(status, body, { responseType = "", response = null } = {}) {
    this.status = status;
    this.responseText = body;
    this.responseType = responseType;
    this.response = response;
    for (const listener of this.listeners.load ?? []) listener({ target: this, currentTarget: this });
  }
}

function makePage() {
  const page = { posted: [], fetchCalls: [], nextFetch: null, fetchThrows: null };
  page.window = createContext({
    location: { origin: ORIGIN, href: `${ORIGIN}/watch?v=abcdefghijk` },
    postMessage(message, origin) {
      page.posted.push({ message: plain(message), origin });
    },
    fetch(...args) {
      page.fetchCalls.push(args);
      if (page.fetchThrows) throw page.fetchThrows;
      return page.nextFetch;
    },
    XMLHttpRequest: class extends FakeXhr {}, // own prototype per page: page.js patches it
    TextDecoder,
    Response
  });
  runScripts(page.window, SCRIPTS);
  page.run = () => runScripts(page.window, SCRIPTS);
  return page;
}

const respond = (body, init = { status: 200 }) => Promise.resolve(new Response(body, init));

test("fetch: the page gets the very same promise and body; captions are posted to our own origin", async () => {
  const page = makePage();
  const promise = respond(json3);
  page.nextFetch = promise;

  const returned = page.window.fetch(TIMEDTEXT, { credentials: "include" });
  assert.equal(returned, promise);
  assert.deepEqual(page.fetchCalls, [[TIMEDTEXT, { credentials: "include" }]]);

  assert.equal(await (await returned).text(), json3, "the page can still read the whole body");
  await flush();
  assert.deepEqual(page.posted, [
    {
      message: { source: "mynotch-yt", v: 1, type: "captions", videoId: "abcdefghijk", lang: "vi", kind: "standard", events: expectedEvents },
      origin: ORIGIN
    }
  ]);
});

test("fetch: the request URL and its tokens never leave the page script", async () => {
  const page = makePage();
  page.nextFetch = respond(json3);
  await page.window.fetch(TIMEDTEXT);
  await flush();
  assert.equal(page.posted.length, 1);
  const wire = JSON.stringify(page.posted[0].message);
  for (const secret of ["SECRET_TOKEN", "SECRET_SIG", "timedtext", "pot=", "https://"]) {
    assert.equal(wire.includes(secret), false, secret);
  }
});

test("fetch: srv3 bodies, asr kind and Request / URL inputs", async () => {
  const page = makePage();
  page.nextFetch = respond(srv3);
  await page.window.fetch(new Request(`${ORIGIN}/api/timedtext?v=abcdefghijk&lang=en&kind=asr&fmt=srv3`));
  page.nextFetch = respond(json3);
  await page.window.fetch(new URL(`${ORIGIN}/api/timedtext?v=lmnopqrstuv&lang=fr&fmt=json3`));
  page.nextFetch = respond(json3);
  await page.window.fetch("/api/timedtext?v=abcdefghijk&lang=de&fmt=json3"); // relative URL
  await flush();
  assert.deepEqual(
    page.posted.map(({ message }) => [message.videoId, message.lang, message.kind, message.events.length]),
    [
      ["abcdefghijk", "en", "asr", 2],
      ["lmnopqrstuv", "fr", "standard", 2],
      ["abcdefghijk", "de", "standard", 2]
    ]
  );
  assert.deepEqual(page.posted[0].message.events, expectedEvents);
});

test("fetch: other requests are not observed", async () => {
  const page = makePage();
  for (const url of [
    `${ORIGIN}/youtubei/v1/player?v=abcdefghijk`,
    `${ORIGIN}/api/timedtext/extra?v=abcdefghijk`,
    `${ORIGIN}/watch?v=abcdefghijk&x=/api/timedtext`
  ]) {
    const promise = respond(json3);
    page.nextFetch = promise;
    assert.equal(page.window.fetch(url), promise);
    await promise;
  }
  await flush();
  assert.deepEqual(page.posted, []);
});

test("fetch: bodies that are not captions, empty or without a video id post nothing", async () => {
  const page = makePage();
  for (const [url, body] of [
    [TIMEDTEXT, ""],
    [TIMEDTEXT, "WEBVTT\n\n00:00.500 --> 00:01.500\nline one"],
    [TIMEDTEXT, "{broken json"],
    [TIMEDTEXT, JSON.stringify({ events: [] })],
    [`${ORIGIN}/api/timedtext?lang=vi&fmt=json3`, json3],
    [`${ORIGIN}/api/timedtext?v=short&lang=vi&fmt=json3`, json3]
  ]) {
    page.nextFetch = respond(body);
    await page.window.fetch(url);
  }
  page.nextFetch = respond(json3, { status: 500 });
  await page.window.fetch(TIMEDTEXT);
  await flush();
  assert.deepEqual(page.posted, []);
});

test("fetch: a failing clone, a used body or a throwing postMessage never reaches the page", async () => {
  const rejections = [];
  const onRejection = (reason) => rejections.push(reason);
  process.on("unhandledRejection", onRejection);
  try {
    const page = makePage();

    const fake = { ok: true, clone() { throw new Error("boom"); }, text: async () => "body" };
    page.nextFetch = Promise.resolve(fake);
    assert.equal(await page.window.fetch(TIMEDTEXT), fake);

    const used = new Response(json3);
    await used.text();
    page.nextFetch = Promise.resolve(used);
    assert.equal(await page.window.fetch(TIMEDTEXT), used);

    const failingText = { ok: true, clone: () => ({ text: () => Promise.reject(new Error("read failed")) }) };
    page.nextFetch = Promise.resolve(failingText);
    assert.equal(await page.window.fetch(TIMEDTEXT), failingText);

    page.window.postMessage = () => {
      throw new Error("post failed");
    };
    page.nextFetch = respond(json3);
    await page.window.fetch(TIMEDTEXT);

    await flush();
    assert.deepEqual(page.posted, []);
  } finally {
    process.off("unhandledRejection", onRejection);
  }
  assert.deepEqual(rejections, []);
});

test("fetch: rejections and synchronous errors of the original propagate unchanged", async () => {
  const rejections = [];
  const onRejection = (reason) => rejections.push(reason);
  process.on("unhandledRejection", onRejection);
  try {
    const page = makePage();
    const failure = new TypeError("network down");
    const rejected = Promise.reject(failure);
    page.nextFetch = rejected;
    const returned = page.window.fetch(TIMEDTEXT);
    assert.equal(returned, rejected);
    await assert.rejects(returned, (error) => error === failure);

    const thrown = new RangeError("sync failure");
    page.fetchThrows = thrown;
    assert.throws(() => page.window.fetch(TIMEDTEXT), (error) => error === thrown);
    await flush();
  } finally {
    process.off("unhandledRejection", onRejection);
  }
  assert.deepEqual(rejections, []);
});

test("fetch: inputs without a usable URL are passed through", async () => {
  const page = makePage();
  for (const input of [undefined, null, 42, {}, { url: 5 }]) {
    page.nextFetch = respond("x");
    assert.equal(page.window.fetch(input), page.nextFetch);
  }
  await flush();
  assert.deepEqual(page.posted, []);
});

test("xhr: open/send behave like the original and the response is observed on load", () => {
  const page = makePage();
  const xhr = new page.window.XMLHttpRequest();
  assert.equal(xhr.open("GET", TIMEDTEXT, true), "open-result");
  assert.equal(xhr.url, TIMEDTEXT);
  xhr.finish(200, json3);
  assert.deepEqual(page.posted, [
    {
      message: { source: "mynotch-yt", v: 1, type: "captions", videoId: "abcdefghijk", lang: "vi", kind: "standard", events: expectedEvents },
      origin: ORIGIN
    }
  ]);
  assert.equal(page.window.XMLHttpRequest.prototype.open.name, "open");
});

test("xhr: reuse, other URLs, bad status, json and arraybuffer response types, throwing open", () => {
  const page = makePage();

  const reused = new page.window.XMLHttpRequest();
  reused.open("GET", TIMEDTEXT);
  reused.open("GET", TIMEDTEXT); // the listener is registered once
  reused.finish(200, json3);
  assert.equal(page.posted.length, 1);

  reused.open("GET", `${ORIGIN}/youtubei/v1/player`); // same object, no longer timedtext
  reused.finish(200, json3);
  assert.equal(page.posted.length, 1);

  const other = new page.window.XMLHttpRequest();
  other.open("GET", `${ORIGIN}/watch`);
  assert.deepEqual(Object.keys(other.listeners), [], "no listener for unrelated requests");

  const failed = new page.window.XMLHttpRequest();
  failed.open("GET", TIMEDTEXT);
  failed.finish(404, json3);
  assert.equal(page.posted.length, 1);

  const asJson = new page.window.XMLHttpRequest();
  asJson.open("GET", TIMEDTEXT);
  asJson.finish(200, "", { responseType: "json", response: JSON.parse(json3) });
  assert.equal(page.posted.length, 2);

  const asBuffer = new page.window.XMLHttpRequest();
  asBuffer.open("GET", `${ORIGIN}/api/timedtext?v=abcdefghijk&lang=vi&fmt=srv3`);
  asBuffer.finish(200, "", { responseType: "arraybuffer", response: new TextEncoder().encode(srv3).buffer });
  assert.equal(page.posted.length, 3);
  assert.deepEqual(page.posted[2].message.events, expectedEvents);

  const asBlob = new page.window.XMLHttpRequest();
  asBlob.open("GET", TIMEDTEXT);
  asBlob.finish(200, "", { responseType: "blob", response: {} });
  assert.equal(page.posted.length, 3);

  const broken = new page.window.XMLHttpRequest();
  assert.throws(() => broken.open("GET", "bad"), (error) => error instanceof SyntaxError && error.message === "bad url");
  assert.deepEqual(Object.keys(broken.listeners), []);
});

test("xhr: a throwing postMessage does not break the page's load handlers", () => {
  const page = makePage();
  page.window.postMessage = () => {
    throw new Error("post failed");
  };
  const xhr = new page.window.XMLHttpRequest();
  xhr.open("GET", TIMEDTEXT);
  assert.doesNotThrow(() => xhr.finish(200, json3));
});

test("wrapping is idempotent: running the scripts again does not wrap or post twice", async () => {
  const page = makePage();
  const wrappedFetch = page.window.fetch;
  const wrappedOpen = page.window.XMLHttpRequest.prototype.open;

  page.run();
  page.run();
  assert.equal(page.window.fetch, wrappedFetch);
  assert.equal(page.window.XMLHttpRequest.prototype.open, wrappedOpen);

  page.nextFetch = respond(json3);
  await page.window.fetch(TIMEDTEXT);
  await flush();
  assert.equal(page.posted.length, 1);

  const xhr = new page.window.XMLHttpRequest();
  xhr.open("GET", TIMEDTEXT);
  xhr.finish(200, json3);
  assert.equal(page.posted.length, 2);
});

test("the page script leaves no visible globals behind", () => {
  const page = makePage();
  assert.equal(vm.runInContext("typeof __mynotchCaptions", page.window), "undefined");
  assert.equal(vm.runInContext("typeof __mynotchBridge", page.window), "undefined");
  assert.deepEqual(
    Object.keys(page.window).filter((key) => /mynotch/i.test(key)),
    []
  );
});

test("a page without fetch or XMLHttpRequest is left alone", () => {
  const window = createContext({ location: { origin: ORIGIN, href: ORIGIN }, postMessage() {} });
  assert.doesNotThrow(() => runScripts(window, SCRIPTS));
  assert.equal(window.fetch, undefined);
  assert.equal(window.XMLHttpRequest, undefined);
});
