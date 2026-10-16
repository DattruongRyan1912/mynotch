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
function makePage({ title = "Placeholder page", hostname = "music.example.com", media = [], metadata = null, origin = ORIGIN } = {}) {
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
    sendThrows: null,
    playbackState: "none"
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
    location: { href: `${origin}/album?x=secret#frag`, origin, hostname },
    navigator: {
      get mediaSession() {
        return page.noSession
          ? undefined
          : {
              get metadata() {
                return page.metadata;
              },
              get playbackState() {
                return page.playbackState;
              }
            };
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
    MediaStream: class MediaStream {},
    postMessage: (data, origin) => page.posted.push({ data: plain(data), origin }),
    addEventListener(type, fn) {
      (page.windowListeners[type] ??= new Set()).add(fn);
    },
    removeEventListener(type, fn) {
      page.windowListeners[type]?.delete(fn);
    },
    setInterval(fn, ms) {
      page.intervals.push({ fn, ms, cleared: false, since: 0 });
      return page.intervals.length;
    },
    clearInterval(id) {
      if (page.intervals[id - 1]) page.intervals[id - 1].cleared = true;
    }
  });
  vm.runInContext("Date.now = () => __now", page.context);
  page.win = vm.runInContext("globalThis", page.context);
  page.newStream = () => vm.runInContext("new MediaStream()", page.context);
  page.start = () => runScripts(page.context, SCRIPTS);
  page.live = () => page.intervals.filter((interval) => !interval.cleared);
  /** Seconds go by, and a player that plays moves on with them, as a real one does; a timer fires every `ms` it was set to. */
  page.advance = (ms) => {
    for (let elapsed = 0; elapsed < ms; elapsed += 1000) {
      page.context.__now += 1000;
      for (const el of page.media) if (!el.paused && !el.ended) el.currentTime += 1;
      for (const interval of page.live()) {
        interval.since += 1000;
        if (interval.since >= interval.ms) {
          interval.since = 0;
          interval.fn();
        }
      }
    }
  };
  /** What happens in a real page: its events come some time apart, never within the same millisecond. */
  page.pause = (ms = 300) => {
    page.context.__now += ms;
    for (const el of page.media) if (!el.paused && !el.ended) el.currentTime += ms / 1000;
  };
  page.emit = (el, type) => {
    page.pause();
    [...(page.docListeners[type] ?? [])].forEach(({ fn }) => fn({ type, target: el }));
  };
  page.take = () => page.sent.splice(0);
  page.fire = (type, event = { type }) => [...(page.windowListeners[type] ?? [])].forEach((fn) => fn(event));
  page.session = (data) => {
    page.pause();
    page.fire("message", { source: page.win, origin: ORIGIN, data: { source: "k9x2q7", type: "session", ...data } });
  };
  /** What the page script says of a Media Session that is playing something. */
  page.playSession = (data = {}) =>
    page.session({ title: "Session song", artist: "Session artist", album: "", playback: "playing", play: true, pause: true, seek: true, ...data });
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
  live: false,
  element: true
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
  assert.deepEqual(Object.keys(message).sort(), ["album", "artist", "duration", "element", "live", "rate", "site", "state", "time", "title", "type", "v"]);
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

test("a page whose title is empty says nothing until it has one", () => {
  const el = video();
  const page = makePage({ media: [el], title: "" });
  page.start();
  page.emit(el, "play");
  assert.deepEqual(page.take(), []);
  page.title = "   ";
  page.advance(1000);
  assert.deepEqual(page.take(), []);
  page.title = "Now it has one";
  page.advance(1000);
  assert.equal(page.take()[0].title, "Now it has one");
});

test("on YouTube the title loses the counter and the suffix and the shell's bare name is no title; anywhere else it is what the page says", () => {
  const youtube = makePage({ media: [video()], origin: "https://www.youtube.com", hostname: "www.youtube.com", title: "YouTube" });
  youtube.start();
  youtube.emit(youtube.media[0], "play");
  assert.deepEqual(youtube.take(), [], "the shell before the video's own title");
  youtube.title = "(3) A video - YouTube";
  youtube.advance(1000);
  assert.equal(youtube.take()[0].title, "A video");

  // The system's now playing says the page's own title; a page that is not YouTube must give the same words or it is two chips.
  const other = makePage({ media: [video()], title: "(3) Inbox - Mail - YouTube" });
  other.start();
  other.emit(other.media[0], "play");
  assert.equal(other.take()[0].title, "(3) Inbox - Mail - YouTube");
  const bare = makePage({ media: [video()], title: "YouTube" });
  bare.start();
  bare.emit(bare.media[0], "play");
  assert.equal(bare.take()[0].title, "YouTube", "a page called YouTube that is not YouTube");
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

  page.pause(2000);
  page.emit(el, "seeked"); // where playing from the report puts it: no news
  assert.deepEqual(page.take(), []);

  el.currentTime = 120;
  page.emit(el, "seeked");
  assert.deepEqual(page.take().map((message) => Math.round(message.time)), [120]);

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
  assert.deepEqual(page.take().map((message) => Math.round(message.time)), [78]);
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
  other.paused = true;
  page.advance(2000);
  assert.equal(page.take().some((message) => message.type === "tab-end"), false, "not yet: it may be the next video loading");
  page.advance(1000);
  assert.equal(page.take().filter((message) => message.type === "tab-end").length, 1, "nothing played again in time");

  other.paused = false;
  page.emit(other, "play");
  page.take();
  page.fire("pagehide");
  assert.deepEqual(page.take(), [{ v: 1, type: "tab-end" }]);
  page.fire("pagehide");
  assert.deepEqual(page.take(), [], "nothing to end any more");
});

test("an element that is emptied and plays again at once (the next video) never ends the page, so nothing the user chose is lost", () => {
  const el = video();
  const page = makePage({ media: [el] });
  page.start();
  page.emit(el, "play");
  page.take();
  for (let video = 0; video < 3; video++) {
    page.emit(el, "emptied");
    page.advance(1000);
    page.emit(el, "loadedmetadata");
    page.emit(el, "play");
    page.emit(el, "playing");
    page.advance(1000);
  }
  const sent = page.take();
  assert.equal(sent.some((message) => message.type === "tab-end"), false, JSON.stringify(sent.map((message) => message.type)));
  assert.equal(page.live().length, 1, "and it is still being reported");
  // Long after, nothing is left of the grace either: an emptied player that plays has no end pending.
  page.advance(10000);
  assert.equal(page.take().some((message) => message.type === "tab-end"), false);
});

test("an emptied element that is playing again when the grace is over is not ended", () => {
  const el = video();
  const page = makePage({ media: [el] });
  page.start();
  page.emit(el, "play");
  page.take();
  page.emit(el, "emptied"); // and the next video starts without a play event of its own
  page.advance(3000);
  assert.equal(page.take().some((message) => message.type === "tab-end"), false, "it plays: it is the media");
});

test("leaving the page and an element that is taken out of the document end the page at once, with no grace", () => {
  const el = video();
  const page = makePage({ media: [el] });
  page.start();
  page.emit(el, "play");
  page.take();
  page.emit(el, "emptied");
  page.fire("pagehide");
  assert.deepEqual(page.take().map((message) => message.type), ["tab-end"]);
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
  const page = makePage({ media: [el] });
  page.start();
  page.emit(el, "play");
  Object.defineProperty(el, "currentTime", {
    get: () => 5,
    set() {
      throw new Error("InvalidStateError");
    }
  });
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
  assert.deepEqual(page.posted, [{ data: { source: "k9x2q7", type: "invoke", action: "next" }, origin: ORIGIN }]);
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
  page.fire("message", { source: {}, origin: ORIGIN, data: { source: "k9x2q7", type: "session", title: "Forged" } });
  page.fire("message", { source: page.win, origin: "https://evil.example", data: { source: "k9x2q7", type: "session", title: "Forged" } });
  page.fire("message", { source: page.win, origin: ORIGIN, data: { source: "mynotch-yt", type: "session", title: "Forged" } });
  page.fire("message", { source: page.win, origin: ORIGIN, data: { source: "k9x2q7", type: "invoke", action: "next" } });
  page.advance(1000);
  assert.deepEqual(page.take(), []);
});

test("without the libraries the script does nothing and says nothing", () => {
  const page = makePage();
  runScripts(page.context, ["tabs.js"]);
  assert.deepEqual(page.docListeners, {});
  assert.deepEqual(page.sent, []);
});

// ---- media that is no element of the document: the page's Media Session says it ----------------------------

const SESSION_REPORT = {
  v: 1,
  type: "tab-report",
  site: "music.example.com",
  title: "Session song",
  artist: "Session artist",
  album: "",
  state: "playing",
  time: 0,
  duration: null,
  rate: 1,
  live: false,
  element: false
};

test("a page whose Media Session says it plays, with no element of ours, is reported from the session, with a tick", () => {
  const page = makePage();
  page.start();
  assert.deepEqual(page.sent, []);
  page.playSession();
  assert.deepEqual(page.take(), [SESSION_REPORT]);
  assert.deepEqual(page.live().map((interval) => interval.ms), [1000]);
});

test("the position the session gave carries on at its speed while it plays, and stops at its length", () => {
  const page = makePage();
  page.start();
  page.context.__now = 10000;
  page.playSession({ position: { position: 30, duration: 200, rate: 1.5, at: 10300 } }); // said as it arrives
  assert.deepEqual(page.take().map(({ time, duration, rate }) => [time, duration, rate]), [[30, 200, 1.5]]);
  page.advance(5000);
  assert.deepEqual(page.take().map(({ time }) => time), [37.5], "five seconds at one and a half");
  page.playSession({ position: { position: 199, duration: 200, rate: 1, at: 15300 } });
  page.take();
  page.advance(30000);
  assert.ok(page.take().every(({ time }) => time <= 200), "never past the end");
});

test("a paused session does not carry its position on", () => {
  const page = makePage();
  page.start();
  page.context.__now = 10000;
  page.playSession({ playback: "paused", position: { position: 30, duration: 200, rate: 1, at: 10000 } });
  assert.deepEqual(page.take().map(({ state, time }) => [state, time]), [["paused", 30]]);
  page.advance(30000);
  assert.deepEqual(page.take().map(({ state, time }) => [state, time]), [["paused", 30]], "its heartbeat, still where it was");
});

test("a session with no position is reported at zero with no length, and the session's title and artist are the report's", () => {
  const page = makePage({ title: "Document title" });
  page.start();
  page.playSession({ title: "From the session", artist: "Someone", album: "Record" });
  assert.deepEqual(page.take().map(({ title, artist, album, time, duration }) => [title, artist, album, time, duration]), [
    ["From the session", "Someone", "Record", 0, null]
  ]);
});

test("the session's heartbeat is every 5 s while it plays and every 30 s while it is paused", () => {
  const page = makePage();
  page.start();
  page.playSession({ position: { position: 10, duration: 200, rate: 1, at: page.context.__now } });
  page.take();
  const run = (seconds) => {
    const sent = [];
    for (let second = 0; second < seconds; second++) {
      page.advance(1000);
      sent.push(...page.take());
    }
    return sent;
  };
  assert.equal(run(4).length, 0);
  assert.equal(run(1).length, 1);
  page.playSession({ playback: "paused", position: { position: 20, duration: 200, rate: 1, at: page.context.__now } });
  page.take();
  assert.equal(run(29).length, 0);
  assert.equal(run(1).length, 1);
});

test("a session with no title, or that says it is not playing at all, is nothing to show", () => {
  const page = makePage();
  page.start();
  page.playSession({ title: "" });
  page.playSession({ playback: "none" });
  assert.deepEqual(page.sent, []);
  assert.deepEqual(page.intervals, []);
});

test("when the session says it no longer plays the page says it has no media, once", () => {
  const page = makePage();
  page.start();
  page.playSession();
  page.take();
  page.session({ title: "Session song", playback: "none" });
  assert.deepEqual(page.take(), [{ v: 1, type: "tab-end" }]);
  assert.deepEqual(page.live(), []);
  page.session({ title: "Session song", playback: "none" });
  assert.deepEqual(page.take(), []);
});

test("the page's Media Session can be read from here too, and what it says live is believed over what was passed on", () => {
  const page = makePage({ metadata: { title: "Read live", artist: "Live artist", album: "" } });
  page.start();
  page.playbackState = "paused";
  page.session({ title: "", playback: "none" }); // the page script's last word is stale or empty
  assert.deepEqual(page.take().map(({ title, state }) => [title, state]), [["Read live", "paused"]]);
  page.playbackState = "playing";
  page.advance(5000);
  assert.deepEqual(page.take().map(({ title, state }) => [title, state]), [["Read live", "playing"]]);
});

test("a session that was already playing when the script came is reported at once", () => {
  const page = makePage({ metadata: { title: "Already", artist: "", album: "" } });
  page.playbackState = "playing";
  page.start();
  assert.deepEqual(page.take().map(({ title, state }) => [title, state]), [["Already", "playing"]]);
  assert.equal(page.live().length, 1);
});

test("an element wins over the session, which then adds no second report", () => {
  const el = video();
  const page = makePage({ media: [el] });
  page.start();
  page.emit(el, "play");
  page.take();
  page.playSession({ title: "Session song" });
  const sent = page.take();
  assert.equal(sent.length, 1, "the title changed, and the element's own report says so");
  assert.ok(sent[0].time >= 30, "from the element: its position, not the session's zero");
  page.advance(5000);
  assert.ok(page.take().every((message) => message.time >= 30));
});

test("when the element goes and the session still says it plays, the session is what the page shows", () => {
  const el = video();
  const page = makePage({ media: [el] });
  page.start();
  page.emit(el, "play");
  page.take();
  page.playSession({ title: "Session song", position: { position: 12, duration: 100, rate: 1, at: page.context.__now } });
  page.take();
  page.emit(el, "emptied");
  el.paused = true;
  page.advance(3000);
  const sent = page.take();
  const types = sent.map((message) => message.type);
  assert.equal(types.filter((type) => type === "tab-end").length, 1, "the element's end, once its grace is over");
  assert.equal(types.at(-1), "tab-report", "then the session's report");
  assert.equal(sent.at(-1).title, "Session song");
  assert.ok(sent.at(-1).time >= 12, "from where the session said it was");
  assert.equal(page.live().length, 1);

  el.isConnected = false; // a removed element behaves alike
  const other = video();
  page.media.push(other);
  page.emit(other, "play");
  page.take();
  other.isConnected = false;
  page.advance(1000);
  assert.deepEqual(page.take().map((message) => message.type), ["tab-end", "tab-report"]);
});

test("commands go through the page's Media Session handlers when there is no element: play, pause, toggle, seek, next, previous", () => {
  const page = makePage();
  page.start();
  page.playSession({ next: true, previous: true });
  const invoked = () => page.posted.splice(0).map((post) => post.data);
  assert.deepEqual(page.command(command("pause")).responses, [{ ok: true }]);
  assert.deepEqual(invoked(), [{ source: "k9x2q7", type: "invoke", action: "pause" }]);
  page.command(command("play"));
  page.command(command("toggle")); // it plays: toggle pauses
  page.command(command("seek", { seconds: 61.5 }));
  page.command(command("next"));
  page.command(command("previous"));
  assert.deepEqual(invoked(), [
    { source: "k9x2q7", type: "invoke", action: "play" },
    { source: "k9x2q7", type: "invoke", action: "pause" },
    { source: "k9x2q7", type: "invoke", action: "seek", seconds: 61.5 },
    { source: "k9x2q7", type: "invoke", action: "next" },
    { source: "k9x2q7", type: "invoke", action: "previous" }
  ]);
  page.playSession({ playback: "paused", next: false, previous: false });
  page.command(command("toggle")); // it is paused: toggle plays
  assert.deepEqual(invoked(), [{ source: "k9x2q7", type: "invoke", action: "play" }]);
  assert.deepEqual(page.diags.map((message) => message.event).slice(0, 2), ["content-tabcommand pause ok", "content-tabcommand play ok"]);
});

test("a command the page has no handler for is unavailable, and nothing is asked of the page", () => {
  const page = makePage();
  page.start();
  page.playSession({ play: false, pause: false, seek: false, next: false, previous: false });
  page.posted.length = 0;
  for (const action of ["play", "pause", "toggle", "next", "previous"]) {
    assert.deepEqual(page.command(command(action)).responses, [{ ok: false }], action);
  }
  assert.deepEqual(page.command(command("seek", { seconds: 5 })).responses, [{ ok: false }]);
  assert.deepEqual(page.posted, []);
});

test("with nothing playing in either way a command is unavailable", () => {
  const page = makePage();
  page.start();
  assert.deepEqual(page.command(command("pause")).responses, [{ ok: false }]);
  page.playSession({ playback: "none" });
  assert.deepEqual(page.command(command("play")).responses, [{ ok: false }]);
});

test("next and previous in a session go to YouTube's button clicks when that script has left them", () => {
  const page = makePage();
  page.start();
  page.playSession({ next: false, previous: false });
  vm.runInContext(`globalThis[${SKIP}] = (action) => action === "next"`, page.context);
  assert.deepEqual(page.command(command("next")).responses, [{ ok: true }]);
  assert.deepEqual(page.command(command("previous")).responses, [{ ok: false }]);
  assert.deepEqual(page.posted, []);
});

// ---- what a page can make this script do: nothing at the rate it likes -------------------------------------------

test("10 000 forged session messages in one tick make no report beyond the floor, and the next tick sends the newest state once", () => {
  const page = makePage();
  page.start();
  page.playSession({ title: "first" });
  page.take();
  for (let index = 0; index < 10000; index++) {
    page.fire("message", {
      source: page.win,
      origin: ORIGIN,
      data: { source: "k9x2q7", type: "session", title: `t${index}`, artist: "a", album: "", playback: "playing", play: true, pause: true, seek: true, position: null }
    });
  }
  assert.deepEqual(page.take(), [], "all within the floor of the report before");
  page.advance(1000);
  const sent = page.take();
  assert.equal(sent.length, 1, "the newest, once");
  assert.equal(sent[0].title, "t9999");
  page.advance(10000);
  assert.ok(page.take().length <= 2, "and nothing more than a heartbeat");
});

test("a page that changes its title as fast as it can is reported at most four times a second", () => {
  const page = makePage({ media: [video()], metadata: { title: "t", artist: "", album: "" } });
  page.start();
  page.take();
  let reports = 0;
  for (let step = 0; step < 4000; step++) {
    page.metadata = { title: `title ${step}`, artist: "", album: "" };
    page.pause(5); // 5 ms of a page that never rests: 20 seconds in all
    page.fire("message", { source: page.win, origin: ORIGIN, data: { source: "k9x2q7", type: "session", title: `title ${step}`, playback: "playing" } });
    if (step % 200 === 199) page.advance(0);
    reports += page.take().length;
  }
  assert.ok(reports <= 4 * 20 + 2, `${reports} reports in 20 s`);
  assert.ok(reports >= 10, "but it is not silenced");
});

test("a report held back by the floor is sent by the tick with what is newest, a state flip included", () => {
  const el = video();
  const page = makePage({ media: [el] });
  page.start();
  page.take();
  el.paused = true;
  page.context.__now += 100; // a pause within the floor of the report made at the start
  page.fire("pause");
  for (const { fn } of page.docListeners.pause ?? []) fn({ type: "pause", target: el });
  assert.deepEqual(page.take(), [], "held back");
  assert.equal(page.live().at(-1).ms, 1000, "and the tick is at its quick pace for it");
  page.advance(1000);
  assert.deepEqual(page.take().map((message) => message.state), ["paused"]);
});

test("two reports further apart than the floor both go out; the end of the page is never held back", () => {
  const el = video();
  const page = makePage({ media: [el] });
  page.start();
  page.take();
  el.paused = true;
  page.emit(el, "pause");
  assert.deepEqual(page.take().map((message) => message.state), ["paused"]);
  page.context.__now += 10;
  page.fire("pagehide");
  assert.deepEqual(page.take(), [{ v: 1, type: "tab-end" }], "within the floor, and at once");
});

test("while paused with nothing waiting the tick slows to five seconds, and is quick again while something plays or waits", () => {
  const el = video();
  const page = makePage({ media: [el] });
  page.start();
  assert.equal(page.live().at(-1).ms, 1000, "playing");
  el.paused = true;
  page.emit(el, "pause");
  page.advance(1000);
  assert.deepEqual(page.live().map((interval) => interval.ms), [5000]);
  el.paused = false;
  page.emit(el, "play");
  assert.deepEqual(page.live().map((interval) => interval.ms), [1000]);
  el.paused = true;
  page.emit(el, "pause");
  page.advance(1000);
  page.emit(el, "emptied"); // something waits
  assert.deepEqual(page.live().map((interval) => interval.ms), [1000]);
});

test("a paused page is still reported every 30 s with the slower tick, and a held-back state is not left for five seconds", () => {
  const el = video({ paused: true });
  const page = makePage({ media: [el], metadata: { title: "T", artist: "", album: "" } });
  page.start();
  page.emit(el, "play");
  el.paused = true;
  page.emit(el, "pause");
  page.take();
  page.advance(5000);
  assert.deepEqual(page.live().map((interval) => interval.ms), [5000]);
  let sent = 0;
  for (let second = 0; second < 30; second++) {
    page.advance(1000);
    sent += page.take().length;
  }
  assert.equal(sent, 1, "one heartbeat in 30 s");
});

// ---- calls and live feeds are no media sources -----------------------------------------------------------------

test("a call page's voices are not reported: by the site, and by what feeds the element", () => {
  for (const hostname of ["meet.google.com", "zoom.us", "us02web.zoom.us", "teams.microsoft.com", "whereby.com", "meet.jit.si", "acme.webex.com"]) {
    const el = video({ duration: Infinity });
    const page = makePage({ media: [el], hostname, title: "Weekly sync" });
    page.start();
    page.emit(el, "play");
    assert.deepEqual(page.take(), [], hostname);
    assert.deepEqual(page.intervals, [], `${hostname}: no tick either`);
  }
  // Another site whose name merely ends alike is a site like any other.
  const other = video();
  const page = makePage({ media: [other], hostname: "notzoom.us" });
  page.start();
  page.emit(other, "play");
  assert.equal(page.take().length, 1);
});

test("an element fed by a live camera or microphone is not reported unless the page names itself in its Media Session", () => {
  const page = makePage();
  page.start();
  const el = video({ duration: Infinity });
  el.srcObject = page.newStream();
  page.media.push(el);
  page.emit(el, "play");
  assert.deepEqual(page.take(), [], "a MediaStream and no title of its own");

  const file = video({ srcObject: null });
  page.media.push(file);
  page.emit(file, "play");
  assert.equal(page.take().length, 1, "an element with a file or a stream of data is another thing");
});

test("a call page, or a live feed, that names itself in its Media Session is believed", () => {
  const meet = video({ duration: Infinity });
  const call = makePage({ media: [meet], hostname: "meet.google.com", metadata: { title: "A broadcast", artist: "", album: "" } });
  call.start();
  call.emit(meet, "play");
  assert.deepEqual(call.take().map((message) => message.title), ["A broadcast"]);

  const page = makePage({ metadata: { title: "Radio", artist: "", album: "" } });
  page.start();
  const feed = video({ duration: Infinity });
  feed.srcObject = page.newStream();
  page.media.push(feed);
  page.emit(feed, "play");
  assert.deepEqual(page.take().map(({ title, live, element }) => [title, live, element]), [["Radio", true, true]]);
});

test("a session-only report says so: element is false, and an element's report says true", () => {
  const page = makePage();
  page.start();
  page.playSession();
  assert.equal(page.take()[0].element, false);
  const el = video();
  const other = makePage({ media: [el] });
  other.start();
  assert.equal(other.take()[0].element, true);
});
