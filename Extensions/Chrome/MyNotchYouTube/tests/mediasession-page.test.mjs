import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { createContext, extensionDir, flush, plain, runScripts } from "./helpers.mjs";

const ORIGIN = "https://site.example";

/** A page with a Media Session like Chrome's: a prototype with setActionHandler, setPositionState and accessors for the rest. */
function makePage({ withSession = true } = {}) {
  const page = {
    posted: [], listeners: new Set(), handlers: {}, metadata: null, playbackState: "none", setterCalls: 0, throwOnAction: null,
    positions: [], throwOnPosition: false
  };
  class MediaSession {
    setActionHandler(action, handler) {
      if (page.throwOnAction === action) throw new TypeError("not a valid action");
      page.handlers[action] = handler;
    }
    setPositionState(state) {
      if (page.throwOnPosition) throw new TypeError("position out of range");
      page.positions.push(state);
    }
    get metadata() {
      return page.metadata;
    }
    set metadata(value) {
      page.setterCalls += 1;
      page.metadata = value;
    }
    get playbackState() {
      return page.playbackState;
    }
    set playbackState(value) {
      page.playbackState = value;
    }
  }
  const session = new MediaSession();
  const globals = {
    location: { origin: ORIGIN },
    navigator: withSession ? { mediaSession: session } : {},
    postMessage: (data, origin) => page.posted.push({ data: plain(data), origin }),
    addEventListener: (type, fn) => type === "message" && page.listeners.add(fn),
    Promise,
    Date: { now: () => page.now ?? 5000 }
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

const EMPTY = {
  source: "k9x2q7", type: "session", title: "", artist: "", album: "", playback: "none", position: null,
  next: false, previous: false, play: false, pause: false, seek: false
};

test("it posts what the Media Session holds, once for the changes of one task", async () => {
  const page = makePage();
  page.start();
  await flush();
  assert.deepEqual(page.posted, [], "nothing until the page uses its Media Session: a page that never does never hears from this script");

  page.session.metadata = { title: "Song", artist: "Artist", album: "Album", artwork: [{ src: "https://cdn.example/a.png" }] };
  page.session.playbackState = "playing";
  page.session.setActionHandler("nexttrack", () => {});
  page.session.setActionHandler("previoustrack", () => {});
  page.session.setActionHandler("play", () => {});
  page.session.setActionHandler("pause", () => {});
  page.session.setActionHandler("seekto", () => {});
  page.session.setActionHandler("stop", () => {}); // not one we call
  await flush();
  assert.deepEqual(page.posted.splice(0), [
    {
      data: { ...EMPTY, title: "Song", artist: "Artist", album: "Album", playback: "playing", next: true, previous: true, play: true, pause: true, seek: true },
      origin: ORIGIN
    }
  ]);
});

test("the position the page says is passed on with the time it said it, and cleared when the page clears it", async () => {
  const page = makePage();
  page.start();
  await flush();
  page.now = 7000;
  page.session.setPositionState({ duration: 200, position: 30, playbackRate: 1.5 });
  await flush();
  assert.deepEqual(page.posted.at(-1).data.position, { position: 30, duration: 200, rate: 1.5, at: 7000 });
  page.session.setPositionState({ duration: Infinity, position: 5, playbackRate: 1 });
  await flush();
  assert.deepEqual(page.posted.at(-1).data.position, { position: 5, duration: null, rate: 1, at: 7000 }, "a live stream has no length");
  page.session.setPositionState();
  await flush();
  assert.equal(page.posted.at(-1).data.position, null);
  assert.deepEqual(page.positions.map((state) => state && state.position), [30, 5, undefined], "and the page's own call went through each time");
});

test("a position the page gets wrong is the page's own exception, and is not recorded", async () => {
  const page = makePage();
  page.start();
  await flush();
  page.throwOnPosition = true;
  assert.throws(() => page.session.setPositionState({ duration: 1, position: 5 }), TypeError);
  await flush();
  assert.deepEqual(page.posted, [], "nothing was set, so nothing is told");
});

test("each change of the playback state is passed on, and the page's setter and getter are the originals", async () => {
  const page = makePage();
  page.start();
  await flush();
  page.session.playbackState = "paused";
  assert.equal(page.session.playbackState, "paused");
  await flush();
  assert.equal(page.posted.at(-1).data.playback, "paused");
  page.session.playbackState = "none";
  await flush();
  assert.equal(page.posted.at(-1).data.playback, "none");
  page.session.playbackState = "nonsense";
  await flush();
  assert.equal(page.posted.at(-1).data.playback, "none", "anything but playing and paused is none");
});

test("nothing but text, numbers and flags leaves the page: no artwork, no URL, long text is cut", async () => {
  const page = makePage();
  page.start();
  page.session.metadata = { title: "t".repeat(1000), artist: 5, album: null, artwork: [{ src: "https://cdn.example/a.png" }], url: "https://x" };
  await flush();
  const { data } = page.posted.at(-1);
  assert.deepEqual(Object.keys(data).sort(), Object.keys(EMPTY).sort());
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
  page.throwOnAction = "play";
  assert.throws(() => page.session.setActionHandler("play", () => {}), TypeError);
  await flush();
  assert.equal(page.posted.at(-1).data.play, false);
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
  for (const action of ["nexttrack", "previoustrack", "play", "pause", "seekto", "stop"]) {
    page.session.setActionHandler(action, (details) => calls.push(plain(details)));
  }
  const invoke = (data, overrides) => page.fire({ source: "k9x2q7", type: "invoke", ...data }, overrides);
  invoke({ action: "next" });
  invoke({ action: "previous" });
  invoke({ action: "play" });
  invoke({ action: "pause" });
  invoke({ action: "seek", seconds: 61.5 });
  assert.deepEqual(calls, [
    { action: "nexttrack" }, { action: "previoustrack" }, { action: "play" }, { action: "pause" }, { action: "seekto", seekTime: 61.5 }
  ]);
  calls.length = 0;
  invoke({ action: "stop" }); // not one it is asked for
  invoke({ action: "seek" }); // a seek says to where
  invoke({ action: "seek", seconds: "5" });
  invoke({ action: "seek", seconds: NaN });
  invoke({ action: "toString" });
  invoke({ action: "__proto__" });
  page.fire({ source: "mynotch-yt", type: "invoke", action: "next" });
  page.fire({ source: "k9x2q7", type: "session", action: "next" });
  invoke({ action: "next" }, { source: {} });
  invoke({ action: "next" }, { origin: "https://evil.example" });
  page.fire("next");
  page.fire(null);
  assert.deepEqual(calls, []);
});

test("a handler that throws, or none at all, never reaches the message listener's caller", () => {
  const page = makePage();
  page.start();
  page.fire({ source: "k9x2q7", type: "invoke", action: "next" }); // no handler
  page.session.setActionHandler("nexttrack", () => {
    throw new Error("the page's own error");
  });
  assert.doesNotThrow(() => page.fire({ source: "k9x2q7", type: "invoke", action: "next" }));
});

test("it wraps once: a second run neither wraps again nor posts twice", async () => {
  const page = makePage();
  page.start();
  const wrapped = page.session.setActionHandler;
  page.start();
  assert.equal(page.session.setActionHandler, wrapped);
  assert.equal(page.listeners.size, 1);
  page.session.metadata = { title: "x" };
  await flush();
  assert.equal(page.posted.length, 1, "one message for one change, not one per copy");
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

test("nothing it defines or posts spells what it is for: the flag and the tag are meaningless words", () => {
  const source = fs.readFileSync(path.join(extensionDir, "mediasession-page.js"), "utf8");
  const code = source.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
  for (const word of ["mynotch", "MyNotch", "lucasvu"]) assert.equal(code.includes(word), false, word);
});
