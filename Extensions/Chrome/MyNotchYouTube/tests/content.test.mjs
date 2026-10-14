import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { assertSafeDiag, createContext, flush, plain, runScripts } from "./helpers.mjs";

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
    sent: [], // protocol messages (captions, playback, clear)
    diags: [], // diag messages, kept apart so the protocol tests stay readable
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
      if (page.queryThrows) throw page.queryThrows;
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
          (message.type === "diag" ? page.diags : page.sent).push(plain(message));
          return page.sendResult ? page.sendResult(message) : Promise.resolve();
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

  // and once the held late track has expired, coming back to the first video does not bring it back
  page.advance(11000);
  page.take();
  page.navigate(watch(ID), "Placeholder title - YouTube");
  page.take();
  page.button.pressed = "false";
  page.advance(1000);
  page.take();
  page.button.pressed = "true";
  page.advance(1000);
  assert.deepEqual(page.take().filter((message) => message.type === "captions"), []);
});

const ID3 = "wxyzabcdefg";
const kinds = (messages) => messages.map((message) => message.type);

test("a track that arrives before the page switches videos is held and relayed once the video matches", () => {
  const page = pausedPage();
  page.start();
  page.take();

  page.postFromPage(captionsMessage(ID2, "early line")); // the player asked for it before the URL changed
  assert.deepEqual(page.take(), [], "held, not relayed");

  page.navigate(watch(ID2), "Another placeholder - YouTube");
  const sent = page.take();
  assert.deepEqual(kinds(sent), ["clear", "playback", "captions"], "clear(old), playback(new), then the held captions");
  assert.deepEqual(sent[0], { v: 1, type: "clear", videoId: ID });
  assert.deepEqual(sent[2], captionsMessage(ID2, "early line"));

  page.advance(3000);
  assert.deepEqual(page.take(), [], "relayed once, not repeated");

  // it is cached like any relayed track: a CC off/on cycle replays it
  page.button.pressed = "false";
  page.advance(1000);
  page.take();
  page.button.pressed = "true";
  page.advance(1000);
  assert.deepEqual(page.take(), [captionsMessage(ID2, "early line")]);
});

test("a held track survives a visit to a page without a video id", () => {
  const page = pausedPage();
  page.start();
  page.navigate(`${ORIGIN}/feed/subscriptions`, "Subscriptions - YouTube");
  page.take();

  page.postFromPage(captionsMessage(ID2));
  page.advance(2000);
  assert.deepEqual(page.take(), []);

  page.navigate(watch(ID2), "Another placeholder - YouTube");
  assert.deepEqual(page.take().filter((message) => message.type === "captions"), [captionsMessage(ID2)]);
});

test("a track already held when the page leaves for a page without a video id is kept", () => {
  const page = pausedPage();
  page.start();
  page.take();

  page.postFromPage(captionsMessage(ID2)); // held while still on the first video
  page.navigate(`${ORIGIN}/`, "YouTube"); // home page: no video id, nothing to discard against
  page.take();
  page.navigate(watch(ID2), "Another placeholder - YouTube");
  assert.deepEqual(page.take().filter((message) => message.type === "captions"), [captionsMessage(ID2)]);
});

test("a held track is relayed up to 10 s after it arrived and never after that", () => {
  const inTime = pausedPage();
  inTime.start();
  inTime.take();
  inTime.postFromPage(captionsMessage(ID2));
  inTime.advance(10000);
  inTime.navigate(watch(ID2), "Another placeholder - YouTube");
  assert.deepEqual(inTime.take().filter((message) => message.type === "captions"), [captionsMessage(ID2)]);

  const expired = pausedPage();
  expired.start();
  expired.take();
  expired.postFromPage(captionsMessage(ID2));
  expired.advance(11000);
  expired.navigate(watch(ID2), "Another placeholder - YouTube");
  assert.deepEqual(expired.take().filter((message) => message.type === "captions"), []);
  expired.button.pressed = "false";
  expired.advance(1000);
  expired.take();
  expired.button.pressed = "true";
  expired.advance(1000);
  assert.deepEqual(expired.take(), [], "nothing was cached either");
});

test("expiry is judged by the clock even if no tick ran in between", () => {
  const page = pausedPage();
  page.start();
  page.take();
  page.postFromPage(captionsMessage(ID2));
  page.context.__now += 60000; // the tab was throttled: the interval did not fire
  page.navigate(watch(ID2), "Another placeholder - YouTube");
  assert.deepEqual(page.take().filter((message) => message.type === "captions"), []);
});

test("a held track for another id than the one navigated to is discarded for good", () => {
  const page = pausedPage();
  page.start();
  page.take();

  page.postFromPage(captionsMessage(ID2));
  page.navigate(watch(ID3), "Third placeholder - YouTube");
  assert.deepEqual(page.take().filter((message) => message.type === "captions"), []);

  // it is gone: navigating to its video later (still inside 10 s) does not resurrect it
  page.navigate(watch(ID2), "Another placeholder - YouTube");
  assert.deepEqual(page.take().filter((message) => message.type === "captions"), []);
});

test("only the most recent held track is kept", () => {
  const replaced = pausedPage();
  replaced.start();
  replaced.take();
  replaced.postFromPage(captionsMessage(ID2, "first held"));
  replaced.postFromPage(captionsMessage(ID3, "second held"));
  replaced.navigate(watch(ID2), "Another placeholder - YouTube");
  assert.deepEqual(replaced.take().filter((message) => message.type === "captions"), [], "the older held track was replaced");

  const newest = pausedPage();
  newest.start();
  newest.take();
  newest.postFromPage(captionsMessage(ID2, "first held"));
  newest.postFromPage(captionsMessage(ID3, "second held"));
  newest.navigate(watch(ID3), "Third placeholder - YouTube");
  assert.deepEqual(newest.take().filter((message) => message.type === "captions"), [captionsMessage(ID3, "second held")]);
});

test("a track for the current video does not disturb a track held for the next one", () => {
  const page = pausedPage();
  page.start();
  page.take();
  page.postFromPage(captionsMessage(ID2, "next video"));
  page.postFromPage(captionsMessage(ID, "current video"));
  assert.deepEqual(page.take(), [captionsMessage(ID, "current video")], "the current one is relayed at once");

  page.navigate(watch(ID2), "Another placeholder - YouTube");
  const captions = page.take().filter((message) => message.type === "captions");
  assert.deepEqual(captions, [captionsMessage(ID2, "next video")]);
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

// ---- diagnostics --------------------------------------------------------------------------------

/** The diag events the content script sent, each checked to be a safe diag message. */
function diagEvents(page) {
  return page.diags.map((message) => {
    assertSafeDiag(message, "content");
    return message.event;
  });
}

test("diag: start and the main video being found are reported", () => {
  const page = pausedPage();
  page.start();
  assert.deepEqual(diagEvents(page), ["content-start", "content-video-found", "content-cc on"]);
  page.advance(10000);
  assert.deepEqual(diagEvents(page).slice(3), [], "reported once, not on every tick");
});

test("diag: a missing main video on a watch page is reported once, and again when it shows up", () => {
  const page = makePage({ video: null, pressed: null });
  page.start();
  page.advance(10000);
  assert.deepEqual(diagEvents(page), ["content-start", "content-video-missing"]);

  page.setVideo(fakeVideo());
  page.advance(1000);
  assert.deepEqual(diagEvents(page).slice(2), ["content-video-found"]);
});

test("diag: pages without a video id report neither found nor missing", () => {
  const page = makePage({ url: `${ORIGIN}/feed/subscriptions`, video: null });
  page.start();
  page.advance(10000);
  assert.deepEqual(diagEvents(page), ["content-start"]);
});

test("diag: found/missing is reported again for the next video", () => {
  const page = pausedPage();
  page.start();
  const before = diagEvents(page).length;
  page.advance(5000);
  page.navigate(watch(ID2), "Another placeholder - YouTube");
  assert.deepEqual(diagEvents(page).slice(before).filter((event) => event.startsWith("content-video")), ["content-video-found"]);
});

test("diag: captions button state changes are reported", () => {
  const page = pausedPage();
  page.start();
  page.advance(5000);
  page.button.pressed = "false";
  page.advance(1000);
  page.advance(4000);
  page.button.pressed = "true";
  page.advance(1000);
  assert.deepEqual(diagEvents(page).filter((event) => event.startsWith("content-cc")), ["content-cc on", "content-cc off", "content-cc on"]);
});

test("diag: an alive line every 30 s with presence and playing flags", () => {
  const page = makePage();
  page.start();
  page.advance(29000);
  assert.deepEqual(diagEvents(page).filter((event) => event.startsWith("content-alive")), []);
  page.advance(1000);
  page.video.paused = true;
  page.advance(30000);
  page.navigate(`${ORIGIN}/`, "YouTube");
  page.advance(30000);
  assert.deepEqual(diagEvents(page).filter((event) => event.startsWith("content-alive")), [
    "content-alive videoid-present=true playing=true",
    "content-alive videoid-present=true playing=false",
    "content-alive videoid-present=false playing=false"
  ]);
});

test("diag: send failures are kept and reported once the channel works again", async () => {
  const page = makePage();
  page.start();
  await flush();
  page.diags.length = 0;

  const failure = (message) =>
    message.type === "diag" ? Promise.resolve() : Promise.reject(new Error("Could not establish connection. Receiving end does not exist."));
  page.sendResult = failure;
  page.video.emit("play");
  page.video.emit("pause");
  await flush();
  assert.deepEqual(diagEvents(page), [], "nothing can be reported through the failing channel yet");

  page.sendResult = null;
  page.video.emit("seeked");
  await flush();
  assert.deepEqual(diagEvents(page), ["content-send-error no-receiving-end count=2"]);

  page.video.emit("seeked");
  await flush();
  assert.equal(diagEvents(page).length, 1, "reported once");
});

test("diag: a synchronous send error on a healthy context is reported afterwards too", async () => {
  const page = makePage();
  page.start();
  await flush();
  page.diags.length = 0;

  page.sendThrows = new Error("Message length exceeded maximum allowed length.");
  page.video.emit("play");
  page.sendThrows = null;
  page.video.emit("pause");
  await flush();
  assert.deepEqual(diagEvents(page), ["content-send-error message-too-long count=1"]);
});

test("diag: a channel that keeps failing does not loop or report itself", async () => {
  const page = makePage();
  page.sendResult = () => Promise.reject(new Error("Could not establish connection. Receiving end does not exist."));
  page.start();
  for (let i = 0; i < 20; i++) {
    page.advance(5000);
    await flush(2);
  }
  assert.equal(diagEvents(page).some((event) => event.startsWith("content-send-error")), false);
  assert.ok(page.diags.length < 60, "bounded by the rate limit");
});

test("diag: an exception in the tick is reported and the next tick still runs", () => {
  const page = pausedPage();
  page.start();
  page.take();
  page.queryThrows = new TypeError("Cannot read properties of null (reading 'foo')");
  page.advance(1000);
  assert.deepEqual(diagEvents(page).filter((event) => event.startsWith("content-tick-error")), [
    "content-tick-error typeerror-cannot-read-properties-of-null-reading"
  ]);

  page.advance(10000);
  assert.ok(diagEvents(page).filter((event) => event.startsWith("content-tick-error")).length <= 3, "rate limited");

  page.queryThrows = null;
  page.video.paused = false;
  page.advance(1000);
  assert.ok(page.take().some((message) => message.type === "playback"), "the tick works again");
});

test("diag: page-side diag events are relayed (clean, rate limited); forged ones are not", () => {
  const page = pausedPage();
  page.start();
  page.advance(1000);
  page.diags.length = 0;
  page.take();
  const pageDiag = (event) => ({ v: 1, type: "diag", where: "page", event });

  page.postFromPage(pageDiag("page-timedtext json3 events=3"));
  page.postFromPage({ ...pageDiag("page-timedtext json3 events=9"), url: "https://example.invalid/?pot=SECRET" });
  assert.deepEqual(page.diags, [pageDiag("page-timedtext json3 events=3")], "same kind twice within 5 s: once");
  assert.deepEqual(page.sent, []);

  page.advance(5000);
  page.postFromPage(pageDiag("page-timedtext json3 events=9"));
  assert.equal(page.diags.at(-1).event, "page-timedtext json3 events=9");

  const before = page.diags.length;
  page.postFromPage({ v: 1, type: "diag", where: "sw", event: "sw-start v=0.1.1" });
  page.postFromPage({ v: 1, type: "diag", where: "content", event: "content-start" });
  page.postFromPage(pageDiag("page-seen https://www.youtube.com/"));
  page.postFromPage(pageDiag("page-timedtext json3 events=1 abcdefghijk"));
  page.postFromPage(pageDiag("page-seen fetch"), { origin: "https://evil.example" });
  page.postFromPage(pageDiag("page-seen fetch"), { source: {} });
  assert.equal(page.diags.length, before);
});

test("diag: a flood of forged page events is bounded", () => {
  const page = pausedPage();
  page.start();
  page.diags.length = 0;
  for (let i = 0; i < 2000; i++) page.postFromPage({ v: 1, type: "diag", where: "page", event: `page-timedtext-status ${100 + (i % 900)}` });
  assert.ok(page.diags.length <= 128, "the table of kinds is bounded");
  const afterFirst = page.diags.length;
  for (let i = 0; i < 2000; i++) page.postFromPage({ v: 1, type: "diag", where: "page", event: i % 2 ? "page-seen fetch" : "page-seen xhr" });
  assert.ok(page.diags.length - afterFirst <= 2, "two more kinds, once each");
  page.advance(5000);
  page.postFromPage({ v: 1, type: "diag", where: "page", event: "page-seen fetch" });
  assert.ok(page.diags.length - afterFirst <= 3, "a new window lets one through again");
});

test("diag: nothing a user could recognise ever appears: no title, URL or video id", async () => {
  const page = makePage({ title: "Secret Placeholder Title - YouTube" });
  page.start();
  page.postFromPage(captionsMessage(ID, "secret caption words"));
  page.video.emit("play");
  page.button.pressed = "false";
  page.advance(6000);
  page.sendResult = () => Promise.reject(new Error(`Failed for ${watch(ID)} and Secret Placeholder Title`));
  page.video.emit("seeked");
  await flush();
  page.sendResult = null;
  page.video.emit("seeked");
  await flush();
  page.queryThrows = new Error(`bad ${watch(ID2)} Secret Placeholder Title ${ID}`);
  page.advance(6000);
  page.queryThrows = null;
  page.navigate(watch(ID2), "Another Secret Title - YouTube");
  page.advance(60000);
  await flush();

  assert.ok(page.diags.length >= 8, `enough diag traffic to be meaningful (${page.diags.length})`);
  const wire = JSON.stringify(page.diags);
  for (const secret of [ID, ID2, "Secret", "secret", "Placeholder", "placeholder", "caption words", "http", "youtube.com", "watch?v="]) {
    assert.equal(wire.includes(secret), false, secret);
  }
  diagEvents(page);
});

test("diag: a failing diagnostic is not reported as a send error of the protocol messages", async () => {
  const page = makePage();
  page.start();
  await flush();
  page.diags.length = 0;

  page.sendResult = (message) => (message.type === "diag" ? Promise.reject(new Error("Could not establish connection. Receiving end does not exist.")) : Promise.resolve());
  page.button.pressed = "false"; // a diag attempt that fails ("content-cc off")
  page.advance(1000);
  page.video.emit("seeked"); // a protocol message that succeeds
  await flush();
  page.video.emit("seeked");
  await flush();
  assert.equal(page.diags.some((message) => message.event.startsWith("content-send-error")), false);
});
