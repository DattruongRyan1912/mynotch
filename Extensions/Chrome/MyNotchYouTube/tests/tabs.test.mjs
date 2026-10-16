import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { assertSafeDiag, createContext, plain, runScripts } from "./helpers.mjs";

const ORIGIN = "https://music.example.com";
const SCRIPTS = ["captions.js", "tabmessages.js", "tabs.js"];
const MEDIA_EVENTS = ["play", "playing", "pause", "ended", "emptied", "seeked", "ratechange", "loadedmetadata", "durationchange"];
const SKIP = "Symbol.for('io.lucasvu.mynotch.tab.skip')";

function fakeMedia(overrides = {}) {
  const media = {
    tagName: "VIDEO",
    paused: false,
    ended: false,
    muted: false,
    volume: 1,
    duration: 200,
    currentTime: 30,
    playbackRate: 1,
    isConnected: true,
    playCalls: 0,
    pauseCalls: 0,
    play() {
      media.playCalls += 1;
      media.paused = false;
      return Promise.resolve();
    },
    pause() {
      media.pauseCalls += 1;
      media.paused = true;
    },
    ...overrides
  };
  return media;
}

/** A page with just enough DOM for tabs.js, a manual clock and a manual interval. */
function makePage({ title = "Placeholder page", hostname = "music.example.com", media = [], metadata = null } = {}) {
  const page = {
    sent: [],
    diags: [],
    media,
    title,
    metadata,
    docListeners: {},
    windowListeners: {},
    intervals: [],
    posted: [],
    runtime: { id: "extension-id" },
    runtimeListeners: [],
    removedRuntimeListeners: [],
    sendThrows: null
  };
  const document = {
    get title() {
      return page.title;
    },
    addEventListener(type, fn, capture) {
      (page.docListeners[type] ??= new Set()).add({ fn, capture });
    },
    removeEventListener(type, fn, capture) {
      for (const entry of page.docListeners[type] ?? []) if (entry.fn === fn && entry.capture === capture) page.docListeners[type].delete(entry);
    },
    querySelectorAll: () => page.media
  };
  page.context = createContext({
    __now: 1000000,
    document,
    location: { href: `${ORIGIN}/album?x=secret#frag`, origin: ORIGIN, hostname },
    navigator: {
      get mediaSession() {
        return page.noSession ? undefined : { get metadata() { return page.metadata; } };
      }
    },
    chrome: {
      runtime: {
        get id() {
          return page.runtime.id;
        },
        sendMessage(message) {
          if (page.sendThrows) throw page.sendThrows;
          (message.type === "diag" ? page.diags : page.sent).push(plain(message));
          return Promise.resolve();
        },
        onMessage: {
          addListener: (fn) => page.runtimeListeners.push(fn),
          removeListener: (fn) => page.removedRuntimeListeners.push(fn)
        }
      }
    },
    postMessage: (data, origin) => page.posted.push({ data: plain(data), origin }),
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
  page.live = () => page.intervals.filter((interval) => !interval.cleared);
  /** Seconds go by, and a player that plays moves on with them, as a real one does. */
  page.advance = (ms) => {
    for (let elapsed = 0; elapsed < ms; elapsed += 1000) {
      page.context.__now += 1000;
      for (const el of page.media) if (!el.paused && !el.ended) el.currentTime += 1;
      for (const interval of page.live()) interval.fn();
    }
  };
  page.emit = (el, type) => [...(page.docListeners[type] ?? [])].forEach(({ fn }) => fn({ type, target: el }));
  page.take = () => page.sent.splice(0);
  page.fire = (type, event = { type }) => [...(page.windowListeners[type] ?? [])].forEach((fn) => fn(event));
  page.session = (data) =>
    page.fire("message", { source: page.win, origin: ORIGIN, data: { source: "mynotch-tab", type: "session", ...data } });
  page.command = (message, ...rest) => {
    const sender = rest.length > 0 ? rest[0] : { id: page.runtime.id };
    const responses = [];
    const results = page.runtimeListeners.map((fn) => fn(message, sender, (value) => responses.push(plain(value))));
    return { responses, results };
  };
  return page;
}

const video = (overrides) => fakeMedia(overrides);
const REPORT = {
  v: 1,
  type: "tab-report",
  site: "music.example.com",
  title: "Placeholder page",
  artist: "",
  album: "",
  state: "playing",
  time: 30,
  duration: 200,
  rate: 1,
  live: false
};

test("a page with no media costs listeners and nothing else: no message, no timer", () => {
  const page = makePage();
  page.start();
  assert.deepEqual(page.sent, []);
  assert.deepEqual(page.diags, []);
  assert.deepEqual(page.intervals, []);
  for (const type of MEDIA_EVENTS) {
    assert.equal([...page.docListeners[type]].length, 1, type);
    assert.equal([...page.docListeners[type]][0].capture, true, `${type} is heard in the capture phase, so the page's own listeners cannot hide it`);
  }
  assert.equal(page.windowListeners.message.size, 1);
  assert.equal(page.windowListeners.pagehide.size, 1);
  assert.equal(page.runtimeListeners.length, 1);
});

test("the first play of a real player is reported at once, with a one-second tick from then on", () => {
  const el = video();
  const page = makePage({ media: [el] });
  page.start();
  page.emit(el, "play");
  assert.deepEqual(page.take(), [REPORT]);
  assert.deepEqual(page.live().map((interval) => interval.ms), [1000]);
});

test("only the fields of the protocol leave the page, and the site is the host name alone", () => {
  const el = video();
  const page = makePage({
    media: [el],
    metadata: { title: "Song", artist: "Artist", album: "Album", artwork: [{ src: "https://cdn.example/cover.png" }] }
  });
  page.start();
  page.emit(el, "play");
  const [message] = page.take();
  assert.deepEqual(Object.keys(message).sort(), ["album", "artist", "duration", "live", "rate", "site", "state", "time", "title", "type", "v"]);
  assert.equal(message.site, "music.example.com");
  const text = JSON.stringify(message);
  for (const secret of ["secret", "frag", "album?", "cdn.example", "cover.png", "https"]) assert.equal(text.includes(secret), false, secret);
});

test("the title is the Media Session's, else what its page script last said, else the document's", () => {
  const el = video();
  const page = makePage({ media: [el], title: "Document title - Site", metadata: { title: "Session title", artist: "A", album: "B" } });
  page.start();
  page.emit(el, "play");
  assert.deepEqual(page.take().map(({ title, artist, album }) => [title, artist, album]), [["Session title", "A", "B"]]);

  // A page whose Media Session cannot be read from here: the page script's snapshot stands in.
  page.metadata = null;
  page.session({ title: "From the page script", artist: "C", album: "", next: false, previous: false });
  assert.deepEqual(page.take().map(({ title, artist }) => [title, artist]), [["From the page script", "C"]]);

  page.session({ title: "", artist: "", album: "", next: false, previous: false });
  assert.deepEqual(page.take().map(({ title, artist }) => [title, artist]), [["Document title - Site", ""]]);

  page.noSession = true; // no navigator.mediaSession at all
  page.title = "Other - Site";
  page.advance(5000);
  assert.equal(page.take().at(-1).title, "Other - Site");
});

test("a page whose title is empty, or is only YouTube's shell, says nothing until it has one", () => {
  const el = video();
  const page = makePage({ media: [el], title: "" });
  page.start();
  page.emit(el, "play");
  assert.deepEqual(page.take(), []);
  page.title = "YouTube";
  page.advance(1000);
  assert.deepEqual(page.take(), []);
  page.title = "Now it has one";
  page.advance(1000);
  assert.equal(page.take()[0].title, "Now it has one");
});

test("a muted loop, a silent element and a very short clip are not shown, unless the page says it is a player", () => {
  const page = makePage();
  page.start();
  for (const overrides of [{ muted: true }, { volume: 0 }, { duration: 3 }]) {
    const el = video(overrides);
    page.media.push(el);
    page.emit(el, "play");
    assert.deepEqual(page.take(), [], JSON.stringify(overrides));
  }
  assert.deepEqual(page.intervals, [], "and no timer is started for them");

  page.metadata = { title: "A real player", artist: "", album: "" };
  const el = video({ muted: true, duration: 3 });
  page.emit(el, "play");
  assert.equal(page.take()[0].title, "A real player");
});

test("a clip whose length is not known yet is shown, and dropped when it turns out to be a short one", () => {
  const el = video({ duration: NaN });
  const page = makePage({ media: [el] });
  page.start();
  page.emit(el, "play");
  assert.equal(page.take().length, 1);
  assert.equal(page.take().length, 0);
  el.duration = 2;
  page.emit(el, "durationchange");
  assert.deepEqual(page.take(), [{ v: 1, type: "tab-end" }]);
  assert.deepEqual(page.live(), []);
});

test("a stream with no end is live: no duration, live is true", () => {
  const el = video({ duration: Infinity });
  const page = makePage({ media: [el] });
  page.start();
  page.emit(el, "play");
  assert.deepEqual(page.take().map(({ duration, live }) => [duration, live]), [[null, true]]);
});

test("pause and play are reported as they happen; the same state is not sent twice", () => {
  const el = video();
  const page = makePage({ media: [el] });
  page.start();
  page.emit(el, "play");
  page.emit(el, "playing"); // the same state straight after
  assert.equal(page.take().length, 1);

  el.paused = true;
  page.emit(el, "pause");
  assert.deepEqual(page.take().map((message) => message.state), ["paused"]);
  page.emit(el, "pause");
  assert.deepEqual(page.take(), []);

  el.paused = false;
  page.emit(el, "play");
  assert.deepEqual(page.take().map((message) => message.state), ["playing"]);
});

test("a seek, a new speed and a new length are reported; the position drifting along with the clock is not", () => {
  const el = video();
  const page = makePage({ media: [el] });
  page.start();
  page.emit(el, "play");
  page.take();

  page.context.__now += 2000;
  el.currentTime = 32; // exactly where playing from the report puts it
  page.emit(el, "seeked");
  assert.deepEqual(page.take(), []);

  el.currentTime = 120;
  page.emit(el, "seeked");
  assert.deepEqual(page.take().map((message) => message.time), [120]);

  el.playbackRate = 1.5;
  page.emit(el, "ratechange");
  assert.deepEqual(page.take().map((message) => message.rate), [1.5]);

  el.duration = 240;
  page.emit(el, "durationchange");
  assert.deepEqual(page.take().map((message) => message.duration), [240]);
});

test("while it plays the report repeats every 5 seconds, while it is paused every 30", () => {
  const el = video();
  const page = makePage({ media: [el] });
  page.start();
  page.emit(el, "play");
  page.take();
  const run = (seconds) => {
    const sent = [];
    for (let second = 0; second < seconds; second++) {
      page.advance(1000);
      sent.push(...page.take());
    }
    return sent;
  };
  assert.deepEqual(run(4), [], "nothing in the first 4 s");
  assert.equal(run(1).length, 1, "one at 5 s");
  assert.equal(run(10).length, 2);

  el.paused = true;
  page.emit(el, "pause");
  page.take();
  assert.equal(run(29).length, 0);
  assert.equal(run(1).length, 1, "a paused page still says so every 30 s, so that the app keeps it");
});

test("a track change that comes with no media event (a new title) is noticed by the next tick", () => {
  const el = video();
  const page = makePage({ media: [el], metadata: { title: "One", artist: "A", album: "" } });
  page.start();
  page.emit(el, "play");
  page.take();
  page.metadata = { title: "Two", artist: "A", album: "" };
  page.advance(1000);
  assert.deepEqual(page.take().map((message) => message.title), ["Two"]);
});

test("the latest player to play is the one shown; a player that is not shown does not move it", () => {
  const first = video();
  const second = video({ currentTime: 77 });
  const page = makePage({ media: [first, second] });
  page.start();
  page.emit(first, "play");
  page.take();
  page.emit(second, "play");
  assert.deepEqual(page.take().map((message) => message.time), [77]);
  first.paused = true;
  page.emit(first, "pause");
  assert.deepEqual(page.take(), [], "the first is no longer the one shown");
  second.paused = true;
  page.emit(second, "pause");
  assert.deepEqual(page.take().map((message) => message.state), ["paused"]);
});

test("an element that is not video or audio, or has no play, is ignored", () => {
  const page = makePage();
  page.start();
  page.emit({ tagName: "DIV", play() {} }, "play");
  page.emit({ tagName: "VIDEO" }, "play");
  page.emit(null, "play");
  assert.deepEqual(page.sent, []);
  const audio = fakeMedia({ tagName: "audio" });
  page.emit(audio, "play");
  assert.equal(page.take().length, 1, "audio, whatever the case of its tag name");
});

test("the page has no media any more: it says so once, when the element leaves, is emptied or the page is left", () => {
  const el = video();
  const page = makePage({ media: [el] });
  page.start();
  page.emit(el, "play");
  page.take();
  el.isConnected = false; // taken out of the document
  page.advance(1000);
  assert.deepEqual(page.take(), [{ v: 1, type: "tab-end" }]);
  assert.deepEqual(page.live(), [], "the tick stops with it");
  page.advance(5000);
  assert.deepEqual(page.take(), []);

  const other = video();
  page.media.push(other);
  page.emit(other, "play");
  page.take();
  page.emit(other, "emptied");
  assert.deepEqual(page.take(), [{ v: 1, type: "tab-end" }]);

  page.emit(other, "play");
  page.take();
  page.fire("pagehide");
  assert.deepEqual(page.take(), [{ v: 1, type: "tab-end" }]);
  page.fire("pagehide");
  assert.deepEqual(page.take(), [], "nothing to end any more");
});

test("a pagehide with nothing to end sends nothing", () => {
  const page = makePage();
  page.start();
  page.fire("pagehide");
  assert.deepEqual(page.sent, []);
});

test("a page whose media was already playing when the script came is claimed at once", () => {
  const el = video();
  const idle = video({ paused: true });
  const muted = video({ muted: true });
  const page = makePage({ media: [idle, muted, el] });
  page.start();
  assert.deepEqual(page.take(), [REPORT]);
  assert.equal(page.live().length, 1);
});

test("nothing is reported when no media plays at the start", () => {
  const page = makePage({ media: [video({ paused: true })] });
  page.start();
  assert.deepEqual(page.sent, []);
});

test("a host name that is not plain is not sent as a site", () => {
  const el = video();
  const page = makePage({ media: [el], hostname: "[::1]" });
  page.start();
  page.emit(el, "play");
  assert.equal(page.take()[0].site, "");
});

// ---- commands ---------------------------------------------------------------------------------------------

const command = (action, extra = {}) => ({ v: 1, type: "tabcommand", tab: 5, action, ...extra });

test("play, pause, toggle and seek act on the player that is shown, answer at once and leave a diagnostic", () => {
  const el = video({ paused: true, duration: 200 });
  const page = makePage({ media: [el] });
  page.start();
  el.paused = false;
  page.emit(el, "play");
  page.take();

  let outcome = page.command(command("pause"));
  assert.deepEqual(outcome.responses, [{ ok: true }]);
  assert.equal(el.pauseCalls, 1);
  assert.equal(el.paused, true);

  page.command(command("play"));
  assert.equal(el.playCalls, 1);
  page.command(command("toggle")); // playing: it pauses
  assert.equal(el.pauseCalls, 2);
  page.command(command("toggle")); // paused: it plays
  assert.equal(el.playCalls, 2);

  page.command(command("seek", { seconds: 90.5 }));
  assert.equal(el.currentTime, 90.5);
  page.command(command("seek", { seconds: 5000 })); // past the end: the end
  assert.equal(el.currentTime, 200);

  assert.deepEqual(
    page.diags.map((message) => message.event),
    ["content-tabcommand pause ok", "content-tabcommand play ok", "content-tabcommand toggle ok", "content-tabcommand toggle ok", "content-tabcommand seek ok", "content-tabcommand seek ok"]
  );
  for (const message of page.diags) assertSafeDiag(message, "content");
  assert.equal(outcome.results.every((result) => result === undefined), true, "the channel is not kept open");
});

test("a play that the page refuses is still answered, and a failing play never throws into the page", async () => {
  const el = video({ paused: true });
  el.play = () => Promise.reject(new Error("NotAllowedError"));
  const page = makePage({ media: [el] });
  page.start();
  el.paused = false;
  page.emit(el, "play");
  const outcome = page.command(command("play"));
  assert.deepEqual(outcome.responses, [{ ok: true }]);
});

test("a command with no player shown, or one that was removed, is unavailable", () => {
  const el = video({ paused: true });
  const page = makePage({ media: [el] });
  page.start();
  assert.deepEqual(page.command(command("pause")).responses, [{ ok: false }]);
  assert.equal(page.diags.at(-1).event, "content-tabcommand pause unavailable");
  el.paused = false;
  page.emit(el, "play");
  el.isConnected = false;
  assert.deepEqual(page.command(command("seek", { seconds: 1 })).responses, [{ ok: false }]);
});

test("a seek on a stream that cannot be seeked is unavailable, never an exception", () => {
  const el = video({ duration: Infinity });
  Object.defineProperty(el, "currentTime", {
    get: () => 5,
    set() {
      throw new Error("InvalidStateError");
    }
  });
  const page = makePage({ media: [el] });
  page.start();
  page.emit(el, "play");
  assert.deepEqual(page.command(command("seek", { seconds: 1 })).responses, [{ ok: false }]);
});

test("next and previous go to YouTube's button clicks when that script has left them, whatever it answers", () => {
  const el = video();
  const page = makePage({ media: [el] });
  page.start();
  page.emit(el, "play");
  const calls = [];
  vm.runInContext(`globalThis[${SKIP}] = (action) => { __skip(action); return action === "next"; }`, Object.assign(page.context, { __skip: (action) => calls.push(action) }));
  assert.deepEqual(page.command(command("next")).responses, [{ ok: true }]);
  assert.deepEqual(page.command(command("previous")).responses, [{ ok: false }]);
  assert.deepEqual(calls, ["next", "previous"]);
  assert.deepEqual(page.posted, [], "and the page's own handler is not asked as well");
  assert.deepEqual(page.diags.map((message) => message.event), ["content-tabcommand next ok", "content-tabcommand previous unavailable"]);
});

test("next and previous go to the page's own handler, asked through the page script, when the page has one", () => {
  const el = video();
  const page = makePage({ media: [el] });
  page.start();
  page.emit(el, "play");
  assert.deepEqual(page.command(command("next")).responses, [{ ok: false }], "no handler known yet");
  assert.deepEqual(page.posted, []);

  page.session({ title: "", artist: "", album: "", next: true, previous: false });
  assert.deepEqual(page.command(command("next")).responses, [{ ok: true }]);
  assert.deepEqual(page.command(command("previous")).responses, [{ ok: false }]);
  assert.deepEqual(page.posted, [{ data: { source: "mynotch-tab", type: "invoke", action: "next" }, origin: ORIGIN }]);
});

test("only the extension's own worker may give a command, and only the closed set", () => {
  const el = video();
  const page = makePage({ media: [el] });
  page.start();
  page.emit(el, "play");
  page.take();
  const bad = [
    [command("pause"), { id: "another" }],
    [command("pause"), { id: "extension-id", tab: { id: 9 } }], // a content script's message
    [command("pause"), undefined],
    [command("pause"), null],
    [{ ...command("pause"), url: "https://example.invalid/" }, { id: "extension-id" }],
    [command("stop"), { id: "extension-id" }],
    [{ v: 1, type: "command", action: "next" }, { id: "extension-id" }], // YouTube's own commands are not these
    [command("seek"), { id: "extension-id" }],
    ["pause", { id: "extension-id" }]
  ];
  for (const [message, sender] of bad) {
    const outcome = page.command(message, sender);
    assert.deepEqual(outcome.responses, [], JSON.stringify([message, sender]));
  }
  assert.equal(el.pauseCalls, 0);
  assert.deepEqual(page.diags, []);
  page.runtime.id = undefined;
  assert.deepEqual(page.command(command("pause")).responses, []);
});

// ---- guards ------------------------------------------------------------------------------------------------

test("a copy that is alive keeps the tab, and a second injection does nothing", () => {
  const page = makePage();
  page.start();
  const listeners = page.runtimeListeners.length;
  page.start();
  assert.equal(page.runtimeListeners.length, listeners);
  assert.equal(page.docListeners.play.size, 1);
  assert.equal(page.windowListeners.message.size, 1);
});

test("a copy whose extension is gone is stopped and replaced, and leaves nothing behind", () => {
  const el = video();
  const page = makePage({ media: [el] });
  page.start();
  page.emit(el, "play");
  page.take();
  page.runtime.id = undefined; // the extension was reloaded: this copy is an orphan
  page.runtime.id = "extension-id"; // ... and the new extension's copy starts in the same world
  vm.runInContext("globalThis[Symbol.for('io.lucasvu.mynotch.tab.content')].stop()", page.context);
  assert.equal(page.removedRuntimeListeners.length, 1);
  assert.deepEqual(page.live(), [], "the old copy's tick is gone");
  assert.equal(page.docListeners.play.size, 0);
  page.start();
  assert.equal(page.docListeners.play.size, 1);
  assert.equal(page.runtimeListeners.length, 2, "the new copy's listener");
  page.emit(el, "play");
  assert.equal(page.take().length, 1, "and only one copy reports");
});

test("a copy of an older run that is orphaned (its extension context invalidated) is replaced by the next injection", () => {
  const page = makePage();
  page.start();
  page.runtime.id = undefined;
  page.start(); // not alive: stopped and replaced
  page.runtime.id = "extension-id";
  assert.equal(page.docListeners.play.size, 1);
  assert.equal(page.windowListeners.message.size, 1);
});

test("a failing send never throws into the page; once the extension is gone the copy shuts down", async () => {
  const el = video();
  const page = makePage({ media: [el] });
  page.start();
  page.sendThrows = new Error("Extension context invalidated.");
  assert.doesNotThrow(() => page.emit(el, "play"));
  assert.equal(page.docListeners.play.size, 1, "a failure with the extension still there changes nothing");
  page.runtime.id = undefined;
  el.paused = true;
  assert.doesNotThrow(() => page.emit(el, "pause"));
  assert.equal(page.docListeners.play.size, 0, "the copy shut down");
  assert.deepEqual(page.live(), []);
  assert.equal(page.removedRuntimeListeners.length, 1);
});

test("a session message from a page, a stranger or another source is not taken for the page script's", () => {
  const el = video();
  const page = makePage({ media: [el], title: "Doc" });
  page.start();
  page.emit(el, "play");
  page.take();
  page.fire("message", { source: {}, origin: ORIGIN, data: { source: "mynotch-tab", type: "session", title: "Forged" } });
  page.fire("message", { source: page.win, origin: "https://evil.example", data: { source: "mynotch-tab", type: "session", title: "Forged" } });
  page.fire("message", { source: page.win, origin: ORIGIN, data: { source: "mynotch-yt", type: "session", title: "Forged" } });
  page.fire("message", { source: page.win, origin: ORIGIN, data: { source: "mynotch-tab", type: "invoke", action: "next" } });
  page.advance(1000);
  assert.deepEqual(page.take(), []);
});

test("without the libraries the script does nothing and says nothing", () => {
  const page = makePage();
  runScripts(page.context, ["tabs.js"]);
  assert.deepEqual(page.docListeners, {});
  assert.deepEqual(page.sent, []);
});
