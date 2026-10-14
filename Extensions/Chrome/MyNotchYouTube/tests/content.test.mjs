import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { createContext, plain, runScripts } from "./helpers.mjs";

const ORIGIN = "https://www.youtube.com";
const ID = "abcdefghijk";
const ID2 = "lmnopqrstuv";
const watch = (id) => `${ORIGIN}/watch?v=${id}`;
const SCRIPTS = ["captions.js", "content.js"];

const captionsMessage = (videoId = ID, text = "line one") => ({
  v: 1,
  type: "captions",
  videoId,
  lang: "vi",
  kind: "standard",
  events: [{ t: 1, d: 1, text }]
});

function fakeVideo() {
  const video = {
    paused: false,
    ended: false,
    currentTime: 12.3,
    playbackRate: 1,
    listeners: {},
    addEventListener(name, fn) {
      (video.listeners[name] ??= new Set()).add(fn);
    },
    removeEventListener(name, fn) {
      video.listeners[name]?.delete(fn);
    },
    emit(name) {
      for (const fn of [...(video.listeners[name] ?? [])]) fn({ type: name });
    },
    listenerCount: () => Object.values(video.listeners).reduce((sum, set) => sum + set.size, 0)
  };
  return video;
}

/** A page with just enough DOM for content.js, plus a manual clock and interval. */
function makePage({ url = watch(ID), title = "Placeholder title - YouTube", pressed = "true", video = fakeVideo() } = {}) {
  const page = {
    sent: [],
    video,
    title,
    ad: false,
    button: pressed === null ? null : { pressed, getAttribute: (name) => (name === "aria-pressed" ? page.button.pressed : null) },
    windowListeners: {},
    intervals: [],
    sendThrows: null,
    location: { href: url, origin: ORIGIN },
    runtime: { id: "extension-id" }
  };
  page.setVideo = (next) => {
    page.video = next;
  };
  const document = {
    get title() {
      return page.title;
    },
    querySelector(selector) {
      if (selector === ".ytp-subtitles-button") return page.button;
      return selector.includes("video") ? page.video : null;
    },
    getElementById: (id) => (id === "movie_player" ? { classList: { contains: (name) => page.ad && name === "ad-showing" } } : null)
  };
  page.context = createContext({
    __now: 1000000,
    document,
    location: page.location,
    chrome: {
      runtime: {
        get id() {
          return page.runtime.id;
        },
        sendMessage(message) {
          if (page.sendThrows) throw page.sendThrows;
          page.sent.push(plain(message));
          return Promise.resolve();
        }
      }
    },
    addEventListener(type, fn) {
      (page.windowListeners[type] ??= new Set()).add(fn);
    },
    removeEventListener(type, fn) {
      page.windowListeners[type]?.delete(fn);
    },
    setInterval(fn, ms) {
      page.intervals.push({ fn, ms, cleared: false });
      return page.intervals.length;
    },
    clearInterval(id) {
      if (page.intervals[id - 1]) page.intervals[id - 1].cleared = true;
    }
  });
  vm.runInContext("Date.now = () => __now", page.context);
  page.win = vm.runInContext("globalThis", page.context);
  page.start = () => runScripts(page.context, SCRIPTS);
  page.tick = () => page.intervals.filter((i) => !i.cleared).forEach((i) => i.fn());
  page.advance = (ms) => {
    for (let elapsed = 0; elapsed < ms; elapsed += 1000) {
      page.context.__now += 1000;
      page.tick();
    }
  };
  page.take = () => page.sent.splice(0);
  page.fire = (type, event = { type }) => [...(page.windowListeners[type] ?? [])].forEach((fn) => fn(event));
  page.postFromPage = (data, overrides = {}) =>
    page.fire("message", { source: page.win, origin: ORIGIN, data: { source: "mynotch-yt", ...data }, ...overrides });
  page.navigate = (href, nextTitle) => {
    page.location.href = href;
    if (nextTitle !== undefined) page.title = nextTitle;
    page.fire("yt-navigate-finish");
  };
  return page;
}

const playbackOf = (videoId, overrides = {}) => ({
  v: 1,
  type: "playback",
  videoId,
  title: "Placeholder title",
  time: 12.3,
  playing: true,
  rate: 1,
  ...overrides
});

test("starting on a watch page reports the playback state once", () => {
  const page = makePage();
  page.start();
  assert.deepEqual(page.take(), [playbackOf(ID)]);
  assert.equal(page.intervals.length, 1);
  assert.equal(page.intervals[0].ms, 1000, "1 s URL check");
  assert.ok(page.windowListeners["yt-navigate-finish"]?.size, "yt-navigate-finish is observed");
});

test("heartbeat: every 5 s while playing, none while paused", () => {
  const page = makePage();
  page.start();
  page.take();
  page.advance(4000);
  assert.deepEqual(page.take(), []);
  page.advance(1000);
  assert.deepEqual(page.take(), [playbackOf(ID)]);
  page.advance(10000);
  assert.equal(page.take().length, 2);

  page.video.paused = true;
  page.video.emit("pause");
  assert.deepEqual(page.take(), [playbackOf(ID, { playing: false })]);
  page.advance(20000);
  assert.deepEqual(page.take(), [], "no heartbeat while paused");
});

test("play, pause, seeked, ratechange and ended send a playback message with the new state", () => {
  const page = makePage();
  page.start();
  page.take();

  page.video.paused = true;
  page.video.emit("pause");
  page.video.paused = false;
  page.video.currentTime = 99.5;
  page.video.emit("seeked");
  page.video.playbackRate = 1.5;
  page.video.emit("ratechange");
  page.video.emit("play");
  page.video.ended = true;
  page.video.emit("ended");
  assert.deepEqual(page.take(), [
    playbackOf(ID, { playing: false }),
    playbackOf(ID, { time: 99.5 }),
    playbackOf(ID, { time: 99.5, rate: 1.5 }),
    playbackOf(ID, { time: 99.5, rate: 1.5 }),
    playbackOf(ID, { time: 99.5, rate: 1.5, playing: false })
  ]);
});

test("an advert in the main player is reported as not playing", () => {
  const page = makePage();
  page.ad = true;
  page.start();
  assert.deepEqual(page.take(), [playbackOf(ID, { playing: false })]);
});

test("the main video is picked up when it appears later and when it is replaced", () => {
  const page = makePage({ video: null });
  page.start();
  assert.deepEqual(page.take(), [], "no video yet, nothing to report");

  const first = fakeVideo();
  page.setVideo(first);
  page.advance(1000);
  assert.deepEqual(page.take(), [playbackOf(ID)]);
  assert.ok(first.listenerCount() > 0);

  const second = fakeVideo();
  second.currentTime = 3;
  page.setVideo(second);
  page.advance(1000);
  assert.equal(first.listenerCount(), 0, "listeners are removed from the old element");
  assert.deepEqual(page.take(), [playbackOf(ID, { time: 3 })]);
  second.emit("play");
  assert.equal(page.take().length, 1);
});

test("captions from the page are relayed after re-validation, without the source tag", () => {
  const page = makePage();
  page.start();
  page.take();
  page.postFromPage(captionsMessage());
  assert.deepEqual(page.take(), [captionsMessage()]);

  page.postFromPage({ ...captionsMessage(), url: "https://example.invalid/?pot=SECRET" });
  const [relayed] = page.take();
  assert.equal(JSON.stringify(relayed).includes("SECRET"), false);
  assert.equal("source" in relayed, false);
});

function pausedPage(options = {}) {
  const video = fakeVideo();
  video.paused = true; // keeps the 5 s heartbeat out of the way
  return makePage({ video, ...options });
}

test("captions of another video id are neither relayed nor cached", () => {
  const page = pausedPage();
  page.start();
  page.take();

  page.postFromPage(captionsMessage(ID2));
  assert.deepEqual(page.take(), []);

  // nothing was cached either: a CC off/on cycle has nothing to replay
  page.button.pressed = "false";
  page.advance(1000);
  assert.deepEqual(page.take(), [{ v: 1, type: "clear", videoId: ID }]);
  page.button.pressed = "true";
  page.advance(1000);
  assert.deepEqual(page.take(), []);
});

test("captions are ignored on pages without a current video (feed, preview, miniplayer)", () => {
  const page = pausedPage();
  page.start();
  page.navigate(`${ORIGIN}/feed/subscriptions`, "Subscriptions - YouTube");
  page.take();

  page.postFromPage(captionsMessage(ID));
  page.postFromPage(captionsMessage(ID2));
  assert.deepEqual(page.take(), []);
});

test("after a navigation the old captions are gone: a late response of the old video is dropped", () => {
  const page = pausedPage();
  page.start();
  page.postFromPage(captionsMessage(ID));
  page.take();

  page.navigate(watch(ID2), "Another placeholder - YouTube");
  assert.deepEqual(page.take().filter((message) => message.type !== "playback"), [{ v: 1, type: "clear", videoId: ID }]);

  page.postFromPage(captionsMessage(ID, "late old line")); // arrives after the URL moved on
  assert.deepEqual(page.take(), []);

  // the new video has no captions, and the old ones are not replayed for it
  page.button.pressed = "false";
  page.advance(1000);
  page.take();
  page.button.pressed = "true";
  page.advance(1000);
  assert.deepEqual(page.take(), []);

  // and coming back to the first video does not bring them back either
  page.navigate(watch(ID), "Placeholder title - YouTube");
  page.take();
  page.button.pressed = "false";
  page.advance(1000);
  page.take();
  page.button.pressed = "true";
  page.advance(1000);
  assert.deepEqual(page.take().filter((message) => message.type === "captions"), []);
});

test("captions that arrive right after the URL changed, before the next tick, are kept for the new video", () => {
  const page = pausedPage();
  page.start();
  page.take();

  page.location.href = watch(ID2); // the 1 s tick has not noticed yet
  page.title = "Another placeholder - YouTube";
  page.postFromPage(captionsMessage(ID2));
  assert.deepEqual(page.take(), [captionsMessage(ID2)]);

  page.advance(1000);
  const afterTick = page.take();
  assert.deepEqual(afterTick.filter((message) => message.type === "captions"), [], "not sent twice");
  assert.deepEqual(afterTick.filter((message) => message.type === "clear"), [{ v: 1, type: "clear", videoId: ID }]);

  // still cached for the new video
  page.button.pressed = "false";
  page.advance(1000);
  page.take();
  page.button.pressed = "true";
  page.advance(1000);
  assert.deepEqual(page.take(), [captionsMessage(ID2)]);
});

test("captions replay after pagehide and a back/forward cache restore", () => {
  const page = pausedPage();
  page.start();
  page.postFromPage(captionsMessage());
  page.take();

  page.fire("pagehide");
  assert.deepEqual(page.take(), [{ v: 1, type: "clear", videoId: ID }]);

  page.advance(1000); // the page is back: the tick finds the video id again
  const restored = page.take();
  assert.deepEqual(restored.filter((message) => message.type === "captions"), [captionsMessage()]);
});

test("captions that arrive again after CC is switched back on are not sent twice", () => {
  const page = pausedPage();
  page.start();
  page.postFromPage(captionsMessage());
  page.take();

  page.button.pressed = "false";
  page.advance(1000);
  assert.deepEqual(page.take(), [{ v: 1, type: "clear", videoId: ID }]);

  page.button.pressed = "true";
  page.postFromPage(captionsMessage(ID, "refetched line")); // the player fetched the track again
  assert.equal(page.take().length, 1);
  page.advance(1000);
  assert.deepEqual(page.take(), [], "the tick must not replay the older copy");
});

test("playing changes without a media event (ad ends or starts) are reported on the next tick", () => {
  const page = makePage();
  page.ad = true;
  page.start();
  assert.deepEqual(page.take(), [playbackOf(ID, { playing: false })]);

  page.ad = false; // the ad-showing class drops after the last media event
  page.advance(1000);
  assert.deepEqual(page.take(), [playbackOf(ID)]);

  page.advance(2000);
  assert.deepEqual(page.take(), [], "nothing new, nothing sent");

  page.ad = true;
  page.advance(1000);
  assert.deepEqual(page.take(), [playbackOf(ID, { playing: false })]);
});

test("forged or malformed page messages are ignored", () => {
  const page = makePage();
  page.start();
  page.take();

  page.postFromPage(captionsMessage(), { source: {} });
  page.postFromPage(captionsMessage(), { source: null });
  page.postFromPage(captionsMessage(), { origin: "https://evil.example" });
  page.postFromPage(captionsMessage(), { origin: "null" });
  page.postFromPage(captionsMessage(), { data: captionsMessage() }); // no source tag
  page.postFromPage(captionsMessage(), { data: { source: "other", ...captionsMessage() } });
  page.postFromPage({ v: 1, type: "clear", videoId: ID }); // the page may only send captions
  page.postFromPage({ ...playbackOf(ID) });
  page.postFromPage({ ...captionsMessage(), videoId: "bad" });
  page.postFromPage({ ...captionsMessage(), events: [] });
  page.postFromPage({ ...captionsMessage(), events: Array.from({ length: 5001 }, (_, i) => ({ t: i, d: 1, text: "x" })) });
  page.fire("message", { source: page.win, origin: ORIGIN, data: "mynotch-yt" });
  page.fire("message", { source: page.win, origin: ORIGIN, data: null });
  assert.deepEqual(page.take(), []);
});

test("video change: clear for the old video, playback for the new one once its title is up", () => {
  const page = makePage();
  page.start();
  page.take();

  // The URL changes before document.title does: the stale title is not reported for the new id.
  page.navigate(watch(ID2));
  assert.deepEqual(page.take(), [{ v: 1, type: "clear", videoId: ID }]);

  page.title = "Another placeholder - YouTube";
  page.advance(1000);
  assert.deepEqual(page.take(), [playbackOf(ID2, { title: "Another placeholder" })]);
});

test("video change: a title that never changes is reported after a short grace period", () => {
  const page = makePage();
  page.start();
  page.take();
  page.navigate(watch(ID2));
  page.take();
  page.advance(2000);
  assert.deepEqual(page.take(), []);
  page.advance(2000);
  assert.deepEqual(page.take(), [playbackOf(ID2)]);
});

test("a navigation noticed by the 1 s URL check alone behaves the same", () => {
  const page = makePage();
  page.start();
  page.take();
  page.location.href = watch(ID2);
  page.title = "Another placeholder - YouTube";
  page.advance(1000);
  assert.deepEqual(page.take(), [{ v: 1, type: "clear", videoId: ID }, playbackOf(ID2, { title: "Another placeholder" })]);
});

test("leaving the watch page clears once and stops reporting; shorts URLs are tracked", () => {
  const page = makePage();
  page.start();
  page.take();

  page.navigate(`${ORIGIN}/feed/subscriptions`, "Subscriptions - YouTube");
  assert.deepEqual(page.take(), [{ v: 1, type: "clear", videoId: ID }]);
  page.advance(20000);
  assert.deepEqual(page.take(), []);

  page.navigate(`${ORIGIN}/shorts/${ID2}`, "Short placeholder - YouTube");
  page.advance(1000);
  assert.deepEqual(page.take(), [playbackOf(ID2, { title: "Short placeholder" })]);
});

test("generic and empty titles are not reported", () => {
  const page = makePage({ title: "YouTube" });
  page.start();
  assert.deepEqual(page.take(), []);
  page.title = "(2) Placeholder title - YouTube";
  page.advance(1000);
  assert.deepEqual(page.take(), [playbackOf(ID)]);
});

test("captions button off sends a clear; back on resends the cached captions of this video", () => {
  const paused = fakeVideo();
  paused.paused = true; // keeps the 5 s heartbeat out of the way
  const page = makePage({ video: paused });
  page.start();
  page.postFromPage(captionsMessage());
  page.take();

  page.button.pressed = "false";
  page.advance(1000);
  assert.deepEqual(page.take(), [{ v: 1, type: "clear", videoId: ID }]);
  page.advance(3000);
  assert.deepEqual(page.take(), [], "reported once, not on every tick");

  page.button.pressed = "true";
  page.advance(1000);
  assert.deepEqual(page.take(), [captionsMessage()]);
  page.advance(1000);
  assert.deepEqual(page.take(), []);
});

test("cached captions of an earlier video are never resent for another video", () => {
  const page = makePage();
  page.start();
  page.postFromPage(captionsMessage(ID));
  page.take();

  page.navigate(watch(ID2), "Another placeholder - YouTube");
  page.take();
  page.button.pressed = "false";
  page.advance(1000);
  page.take();
  page.button.pressed = "true";
  page.advance(1000);
  assert.deepEqual(page.take().filter((message) => message.type === "captions"), []);
});

test("a captions button that is missing or in an unknown state changes nothing", () => {
  const page = makePage({ pressed: null });
  page.start();
  page.take();
  page.advance(3000);
  assert.deepEqual(page.take(), []);
  page.button = { getAttribute: () => null };
  page.advance(1000);
  assert.deepEqual(page.take(), []);
});

test("pagehide clears the current video", () => {
  const page = makePage();
  page.start();
  page.take();
  page.fire("pagehide");
  assert.deepEqual(page.take(), [{ v: 1, type: "clear", videoId: ID }]);
});

test("only protocol fields are ever sent: no URLs, nothing else", () => {
  const page = makePage();
  page.start();
  page.postFromPage(captionsMessage());
  page.video.emit("seeked");
  page.navigate(watch(ID2), "Another placeholder - YouTube");
  page.advance(10000);
  const sent = page.take();
  assert.ok(sent.length >= 5);
  for (const message of sent) {
    assert.equal(message.v, 1);
    assert.ok(["captions", "playback", "clear"].includes(message.type));
    assert.equal(JSON.stringify(message).includes("http"), false);
    assert.equal(JSON.stringify(message).includes("youtube.com"), false);
  }
});

test("starting twice installs nothing twice", () => {
  const page = makePage();
  page.start();
  page.start();
  assert.equal(page.intervals.length, 1);
  assert.equal(page.windowListeners.message.size, 1);
  assert.equal(page.take().length, 1);
});

test("an invalidated extension context shuts the script down quietly", () => {
  const page = makePage();
  page.start();
  page.take();
  page.runtime.id = undefined;
  page.sendThrows = new Error("Extension context invalidated.");
  assert.doesNotThrow(() => page.video.emit("play"));
  assert.equal(page.intervals[0].cleared, true);
  assert.equal(page.video.listenerCount(), 0);
  assert.equal(page.windowListeners.message.size, 0);
  assert.equal(page.windowListeners["yt-navigate-finish"].size, 0);
});

test("a send error on a healthy context does not shut the script down", () => {
  const page = makePage();
  page.start();
  page.take();
  page.sendThrows = new Error("Message length exceeded maximum allowed length.");
  assert.doesNotThrow(() => page.video.emit("play"));
  assert.equal(page.intervals[0].cleared, false);
  page.sendThrows = null;
  page.video.emit("play");
  assert.equal(page.take().length, 1);
});
