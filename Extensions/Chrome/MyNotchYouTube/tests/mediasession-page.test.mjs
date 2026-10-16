import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { createContext, flush, plain, runScripts } from "./helpers.mjs";

const ORIGIN = "https://site.example";

/** A page with a Media Session like Chrome's: a prototype with setActionHandler and an accessor for metadata. */
function makePage({ withSession = true } = {}) {
  const page = { posted: [], listeners: new Set(), handlers: {}, metadata: null, setterCalls: 0, throwOnAction: null };
  class MediaSession {
    setActionHandler(action, handler) {
      if (page.throwOnAction === action) throw new TypeError("not a valid action");
      page.handlers[action] = handler;
    }
    get metadata() {
      return page.metadata;
    }
    set metadata(value) {
      page.setterCalls += 1;
      page.metadata = value;
    }
  }
  const session = new MediaSession();
  const globals = {
    location: { origin: ORIGIN },
    navigator: withSession ? { mediaSession: session } : {},
    postMessage: (data, origin) => page.posted.push({ data: plain(data), origin }),
    addEventListener: (type, fn) => type === "message" && page.listeners.add(fn),
    Promise
  };
  if (withSession) globals.MediaSession = MediaSession;
  page.context = createContext(globals);
  page.win = vm.runInContext("globalThis", page.context);
  page.session = session;
  page.start = () => runScripts(page.context, ["mediasession-page.js"]);
  page.fire = (data, overrides = {}) =>
    [...page.listeners].forEach((fn) => fn({ source: page.win, origin: ORIGIN, data, ...overrides }));
  return page;
}

test("it posts the metadata text and the handler flags, once for the changes of one task", async () => {
  const page = makePage();
  page.start();
  await flush();
  assert.deepEqual(page.posted.splice(0), [
    { data: { source: "mynotch-tab", type: "session", title: "", artist: "", album: "", next: false, previous: false }, origin: ORIGIN }
  ]);

  page.session.metadata = { title: "Song", artist: "Artist", album: "Album", artwork: [{ src: "https://cdn.example/a.png" }] };
  page.session.setActionHandler("nexttrack", () => {});
  page.session.setActionHandler("previoustrack", () => {});
  page.session.setActionHandler("play", () => {});
  await flush();
  assert.deepEqual(page.posted.splice(0), [
    { data: { source: "mynotch-tab", type: "session", title: "Song", artist: "Artist", album: "Album", next: true, previous: true }, origin: ORIGIN }
  ]);
});

test("nothing but text and two booleans leaves the page: no artwork, no URL, long text is cut", async () => {
  const page = makePage();
  page.start();
  page.session.metadata = { title: "t".repeat(1000), artist: 5, album: null, artwork: [{ src: "https://cdn.example/a.png" }], url: "https://x" };
  await flush();
  const { data } = page.posted.at(-1);
  assert.deepEqual(Object.keys(data).sort(), ["album", "artist", "next", "previous", "source", "title", "type"]);
  assert.equal(data.title.length, 300);
  assert.equal(data.artist, "");
  assert.equal(data.album, "");
  assert.equal(JSON.stringify(data).includes("cdn.example"), false);
});

test("the page gets the original behaviour: the original runs first, its result and its exceptions are the page's", async () => {
  const page = makePage();
  page.start();
  const handler = () => {};
  page.session.setActionHandler("seekto", handler);
  assert.equal(page.handlers.seekto, handler);
  page.throwOnAction = "bogus";
  assert.throws(() => page.session.setActionHandler("bogus", () => {}), TypeError);
  page.session.metadata = { title: "x" };
  assert.equal(page.setterCalls, 1);
  assert.equal(page.session.metadata.title, "x", "the getter is the original");
  await flush();
  assert.equal(page.posted.at(-1).data.next, false, "a refused action is not recorded");
});

test("clearing a handler with null clears the flag", async () => {
  const page = makePage();
  page.start();
  page.session.setActionHandler("nexttrack", () => {});
  await flush();
  assert.equal(page.posted.at(-1).data.next, true);
  page.session.setActionHandler("nexttrack", null);
  await flush();
  assert.equal(page.posted.at(-1).data.next, false);
});

test("an invoke message calls the page's own handler with the action; anything else does nothing", () => {
  const page = makePage();
  page.start();
  const calls = [];
  page.session.setActionHandler("nexttrack", (details) => calls.push(["next", plain(details)]));
  page.session.setActionHandler("previoustrack", (details) => calls.push(["previous", plain(details)]));
  page.fire({ source: "mynotch-tab", type: "invoke", action: "next" });
  page.fire({ source: "mynotch-tab", type: "invoke", action: "previous" });
  assert.deepEqual(calls, [["next", { action: "nexttrack" }], ["previous", { action: "previoustrack" }]]);
  calls.length = 0;
  page.fire({ source: "mynotch-tab", type: "invoke", action: "play" });
  page.fire({ source: "mynotch-tab", type: "invoke", action: "seek" });
  page.fire({ source: "mynotch-yt", type: "invoke", action: "next" });
  page.fire({ source: "mynotch-tab", type: "session", action: "next" });
  page.fire({ source: "mynotch-tab", type: "invoke", action: "next" }, { source: {} });
  page.fire({ source: "mynotch-tab", type: "invoke", action: "next" }, { origin: "https://evil.example" });
  page.fire("next");
  page.fire(null);
  assert.deepEqual(calls, []);
});

test("a handler that throws, or none at all, never reaches the message listener's caller", () => {
  const page = makePage();
  page.start();
  page.fire({ source: "mynotch-tab", type: "invoke", action: "next" }); // no handler
  page.session.setActionHandler("nexttrack", () => {
    throw new Error("the page's own error");
  });
  assert.doesNotThrow(() => page.fire({ source: "mynotch-tab", type: "invoke", action: "next" }));
});

test("it wraps once: a second run neither wraps again nor posts twice", async () => {
  const page = makePage();
  page.start();
  const wrapped = page.session.setActionHandler;
  page.start();
  assert.equal(page.session.setActionHandler, wrapped);
  assert.equal(page.listeners.size, 1);
  await flush();
  assert.equal(page.posted.length, 1);
});

test("a page without a Media Session is left alone, and it leaves no global behind", () => {
  const page = makePage({ withSession: false });
  page.start();
  assert.equal(page.listeners.size, 0);
  assert.deepEqual(page.posted, []);
  const ok = makePage();
  ok.start();
  assert.equal(vm.runInContext("typeof __mynotchTabs + typeof __mynotchCaptions", ok.context), "undefinedundefined");
});

test("a page that cannot be posted to (an opaque origin) does not break the hook", async () => {
  const page = makePage();
  page.context.postMessage = () => {
    throw new Error("invalid target origin");
  };
  assert.doesNotThrow(() => page.start());
  await flush();
  assert.doesNotThrow(() => page.session.setActionHandler("nexttrack", () => {}));
});
