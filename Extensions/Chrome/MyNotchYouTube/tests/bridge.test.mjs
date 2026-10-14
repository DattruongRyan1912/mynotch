import test from "node:test";
import assert from "node:assert/strict";
import { assertSafeDiag, flush, loadBridge, loadCaptions, readSource } from "./helpers.mjs";

const B = loadBridge();
const C = loadCaptions();
const A = "aaaaaaaaaaa";
const Z = "zzzzzzzzzzz";

const captions = (videoId, text = "line one") => ({
  v: 1,
  type: "captions",
  videoId,
  lang: "vi",
  kind: "standard",
  events: [{ t: 1, d: 1, text }]
});
const playback = (videoId = A, time = 1) => ({ v: 1, type: "playback", videoId, title: "Placeholder", time, playing: true, rate: 1 });
const clear = (videoId) => ({ v: 1, type: "clear", videoId });

function harness() {
  const h = { time: 1000000, ports: [], connects: [], logs: [], lastErrorReads: 0, lastError: "", connectError: null, hostMessages: [] };
  h.bridge = B.createBridge({
    connectNative(name) {
      h.connects.push(name);
      if (h.connectError) throw h.connectError;
      const listeners = [];
      const port = {
        posted: [], // protocol messages
        diags: [], // diag messages

        dead: false,
        hostListeners: [],
        onDisconnect: { addListener: (fn) => listeners.push(fn) },
        onMessage: { addListener: (fn) => port.hostListeners.push(fn) },
        /** What the native host writes to its stdout reaches the worker as a port message. */
        receive: (message) => port.hostListeners.forEach((fn) => fn(message)),
        postMessage(message) {
          if (port.dead) throw new Error("Attempting to use a disconnected port object");
          (message.type === "diag" ? port.diags : port.posted).push(message);
        },
        disconnect(reason = "") {
          h.lastError = reason;
          listeners.forEach((fn) => fn());
          h.lastError = "";
        }
      };
      h.ports.push(port);
      return port;
    },
    lastError() {
      h.lastErrorReads += 1;
      return h.lastError;
    },
    now: () => h.time,
    log: (text) => h.logs.push(text),
    errorCode: C.errorCode,
    buildDiag: C.buildDiag,
    onHostMessage: (message) => {
      h.hostMessages.push(message);
      if (h.onHost) h.onHost(message);
    }
  });
  h.advance = (ms) => {
    h.time += ms;
  };
  h.retryIn = () => h.bridge.state().retryAt - h.time;
  return h;
}

test("connects lazily to the fixed host name and forwards messages", () => {
  const h = harness();
  assert.deepEqual(h.connects, [], "nothing is connected before the first message");
  assert.equal(B.HOST_NAME, "io.lucasvu.mynotch.youtube");

  assert.equal(h.bridge.handle(playback()), true);
  assert.deepEqual(h.connects, ["io.lucasvu.mynotch.youtube"]);
  h.bridge.handle(playback(A, 2));
  h.bridge.handle(clear(A));
  assert.equal(h.connects.length, 1, "the same port is reused");
  assert.deepEqual(h.ports[0].posted, [playback(), playback(A, 2), clear(A)]);
  assert.equal(h.bridge.state().connected, true);
});

test("host missing: backoff 2 s doubling to a 60 s cap, and messages inside the window are dropped", () => {
  const h = harness();
  const delays = [];
  for (let attempt = 0; attempt < 8; attempt++) {
    assert.equal(h.bridge.handle(playback()), true, "an attempt is made once the window elapsed");
    h.ports.at(-1).disconnect("Specified native messaging host not found.");
    delays.push(h.retryIn());

    h.advance(h.retryIn() - 1);
    const before = h.connects.length;
    assert.equal(h.bridge.handle(playback()), false);
    assert.equal(h.connects.length, before, "dropped while backing off");
    h.advance(1);
  }
  assert.deepEqual(delays, [2000, 4000, 8000, 16000, 32000, 60000, 60000, 60000]);
  assert.ok(h.lastErrorReads >= 8, "lastError is read in every disconnect callback");
});

test("it never reconnects on its own: only a new message triggers an attempt", () => {
  const h = harness();
  h.bridge.handle(playback());
  h.ports[0].disconnect("host not found");
  h.advance(10 * 60 * 1000);
  assert.equal(h.connects.length, 1);
  assert.equal(h.bridge.state().connected, false);
  h.bridge.handle(playback());
  assert.equal(h.connects.length, 2);
});

test("latest captions per video survive a disconnect and are resent once, before the triggering message", () => {
  const h = harness();
  h.bridge.handle(captions(A, "old text"));
  h.bridge.handle(captions(A, "new text")); // replaces the first
  h.bridge.handle(captions(Z));
  h.bridge.handle(clear(Z)); // forgotten
  assert.deepEqual(h.bridge.state().storedCaptions, [A]);

  h.ports[0].disconnect("host exited");
  h.advance(2000);
  h.bridge.handle(playback());
  assert.deepEqual(h.ports[1].posted, [captions(A, "new text"), playback()]);
});

test("captions that arrive while backing off are kept and sent exactly once on the next connect", () => {
  const h = harness();
  h.bridge.handle(playback());
  h.ports[0].disconnect("host exited");

  assert.equal(h.bridge.handle(captions(A)), false, "dropped inside the window");
  assert.deepEqual(h.bridge.state().storedCaptions, [A]);

  h.advance(2000);
  h.bridge.handle(captions(Z));
  assert.deepEqual(h.ports[1].posted, [captions(A), captions(Z)], "each stored track once, none duplicated");
});

test("a clear removes the stored captions so they are not resent", () => {
  const h = harness();
  h.bridge.handle(captions(A));
  h.bridge.handle(clear(A));
  h.ports[0].disconnect("");
  h.advance(2000);
  h.bridge.handle(playback());
  assert.deepEqual(h.ports[1].posted, [playback()]);
});

test("only the 8 most recent videos are kept", () => {
  const h = harness();
  const ids = Array.from({ length: 10 }, (_, i) => `video${String(i).padStart(6, "0")}`);
  for (const id of ids) h.bridge.handle(captions(id));
  assert.deepEqual(h.bridge.state().storedCaptions, ids.slice(2));
});

test("a connection that lived 10 s or more starts the backoff over", () => {
  const h = harness();
  for (let i = 0; i < 3; i++) {
    h.bridge.handle(playback());
    h.ports.at(-1).disconnect("host not found");
    h.advance(h.retryIn());
  }
  assert.equal(h.bridge.state().failures, 3);

  h.bridge.handle(playback());
  h.advance(10000);
  h.ports.at(-1).disconnect("app quit");
  assert.equal(h.bridge.state().failures, 1);
  assert.equal(h.retryIn(), 2000);

  // a short-lived connection keeps counting
  h.advance(2000);
  h.bridge.handle(playback());
  h.advance(9999);
  h.ports.at(-1).disconnect("again");
  assert.equal(h.bridge.state().failures, 2);
});

test("logs at most once per minute and never logs message content", () => {
  const h = harness();
  for (let i = 0; i < 5; i++) {
    h.bridge.handle(captions(A, "secret caption text"));
    h.ports.at(-1).disconnect("Specified native messaging host not found.");
    h.advance(h.retryIn());
  }
  assert.equal(h.logs.length, 1, "five failures within a minute, one log line");

  h.advance(60000);
  h.bridge.handle(playback());
  h.ports.at(-1).disconnect("Specified native messaging host not found.");
  assert.equal(h.logs.length, 2);
  for (const line of h.logs) {
    assert.equal(line.includes("secret caption text"), false);
    assert.equal(line.includes(A), false);
  }
});

test("a throwing connectNative or a dead port is treated as a failure, never as an exception", () => {
  const h = harness();
  h.connectError = new Error("native messaging unavailable");
  assert.doesNotThrow(() => assert.equal(h.bridge.handle(playback()), false));
  assert.equal(h.bridge.state().failures, 1);
  assert.equal(h.retryIn(), 2000);

  h.connectError = null;
  h.advance(2000);
  h.bridge.handle(playback());
  h.ports.at(-1).dead = true; // Chrome closed the port without telling us yet
  assert.doesNotThrow(() => assert.equal(h.bridge.handle(playback()), false));
  assert.equal(h.bridge.state().connected, false);
  assert.ok(h.retryIn() > 0);
});

test("isTrustedSender accepts only this extension's own scripts on youtube.com pages", () => {
  const own = "abcdefghijklmnopabcdefghijklmnop";
  assert.equal(B.isTrustedSender({ id: own, url: "https://www.youtube.com/watch?v=aaaaaaaaaaa" }, own), true);
  assert.equal(B.isTrustedSender({ id: own, url: "https://www.youtube.com/" }, own), true);
  for (const sender of [
    undefined,
    null,
    {},
    { id: "otherextensionidotherextensionid", url: "https://www.youtube.com/watch" },
    { id: own },
    { id: own, url: "https://evil.example/https://www.youtube.com/" },
    { id: own, url: "https://www.youtube.com.evil.example/" },
    { id: own, url: "http://www.youtube.com/watch" },
    { id: own, url: "https://music.youtube.com/" }
  ]) {
    assert.equal(B.isTrustedSender(sender, own), false, JSON.stringify(sender));
  }
});

// ---- diagnostics: reconnect reasons and the service worker relay ------------------------------------

const OWN = "abcdefghijklmnopabcdefghijklmnop";
const SENDER = { id: OWN, url: "https://www.youtube.com/watch?v=aaaaaaaaaaa" };

/** Every diag a port received must be a safe one from the service worker. */
function swDiags(port) {
  return port.diags.map((message) => {
    assertSafeDiag(message, "sw");
    return message.event;
  });
}

function relayHarness(overrides = {}) {
  const h = harness();
  h.infos = [];
  h.relay = B.createRelay({
    bridge: h.bridge,
    captions: C,
    ownId: OWN,
    now: () => h.time,
    version: "0.1.1",
    log: (text) => h.infos.push(text),
    ...overrides
  });
  return h;
}

test("diag: the reason of a failed connection is kept and reported once the next connection exists", () => {
  const h = harness();
  h.bridge.handle(playback());
  h.ports[0].disconnect("Specified native messaging host not found.");
  assert.deepEqual(swDiags(h.ports[0]), [], "nothing was reported on the failed connection");

  h.advance(2000);
  h.bridge.handle(playback());
  assert.deepEqual(swDiags(h.ports[1]), ["sw-reconnect after=host-not-found failures=1"]);

  h.ports[1].disconnect("");
  h.advance(4000); // the second failure doubles the backoff
  h.bridge.handle(playback());
  assert.deepEqual(swDiags(h.ports[2]), ["sw-reconnect after=disconnected failures=2"]);

  h.advance(60000);
  h.bridge.handle(playback());
  assert.equal(h.ports.length, 3, "no new connection, no new report");
  assert.equal(h.ports[2].diags.length, 1);
});

test("diag: connectNative throwing is reported after the next successful connect, with a safe code", () => {
  const h = harness();
  h.connectError = new Error("Failed for https://www.youtube.com/watch?v=abcdefghijk and My Secret Title");
  assert.equal(h.bridge.handle(playback()), false);
  h.connectError = null;
  h.advance(2000);
  h.bridge.handle(playback());
  assert.deepEqual(swDiags(h.ports[0]), ["sw-reconnect after=failed-for-x-and-x failures=1"]);
  const wire = JSON.stringify(h.ports[0].diags).toLowerCase();
  for (const leak of ["secret", "title", "youtube", "abcdefghijk", "https"]) assert.equal(wire.includes(leak), false, leak);
});

test("diag: the reconnect report comes before the stored captions and the triggering message", () => {
  const h = harness();
  h.bridge.handle(captions(A));
  h.ports[0].disconnect("Native host has exited.");
  h.advance(2000);
  h.bridge.handle(playback());
  assert.deepEqual(swDiags(h.ports[1]), ["sw-reconnect after=host-has-exited failures=1"]);
  assert.deepEqual(h.ports[1].posted, [captions(A), playback()]);
});

test("diag: diag messages are never stored or replayed", () => {
  const h = harness();
  h.bridge.handle({ v: 1, type: "diag", where: "content", event: "content-start" });
  assert.deepEqual(h.bridge.state().storedCaptions, []);
  h.ports[0].disconnect("");
  h.advance(2000);
  h.bridge.handle(playback());
  assert.deepEqual(h.ports[1].diags.map((message) => message.event), ["sw-reconnect after=disconnected failures=1"], "only the reconnect report");
});

test("relay.start connects eagerly and reports the version", () => {
  const h = relayHarness();
  assert.deepEqual(h.connects, []);
  h.relay.start();
  assert.deepEqual(h.connects, ["io.lucasvu.mynotch.youtube"], "connected before any message arrived");
  assert.deepEqual(swDiags(h.ports[0]), ["sw-start v=0.1.1"]);
  assert.deepEqual(h.infos, ["sw-start v=0.1.1"]);
});

test("relay.start with an odd version string reports it as unknown, never as free text", () => {
  for (const version of [undefined, "", "My Secret Title", "1.2.3.4.5", "abcdefghijk"]) {
    const h = relayHarness({ version });
    h.relay.start();
    assert.deepEqual(swDiags(h.ports[0]), ["sw-start v=unknown"], String(version));
  }
});

test("relay.start without a host: the worker keeps going, the backoff applies and the reason is reported later", () => {
  const h = relayHarness();
  h.relay.start();
  h.ports[0].disconnect("Specified native messaging host not found.");
  h.relay.onMessage(playback(), SENDER);
  assert.equal(h.connects.length, 1, "inside the backoff window");

  h.advance(5000); // past the backoff and the 5 s diag window (the dropped one counted)
  h.relay.onMessage(playback(), SENDER);
  assert.equal(h.connects.length, 2);
  assert.deepEqual(swDiags(h.ports[1]), ["sw-reconnect after=host-not-found failures=1", "sw-msg playback"]);
  assert.deepEqual(h.ports[1].posted, [playback()]);
});

test("relay: valid messages are forwarded and reported by type, at most once per type every 5 s", () => {
  const h = relayHarness();
  h.relay.start();
  for (let i = 0; i < 10; i++) {
    h.relay.onMessage(playback(A, i), SENDER);
    h.advance(100);
  }
  h.relay.onMessage(captions(A), SENDER);
  h.relay.onMessage(captions(Z), SENDER);
  h.relay.onMessage(clear(A), SENDER);
  assert.equal(h.ports[0].posted.filter((message) => message.type === "playback").length, 10, "messages are never rate limited");
  assert.deepEqual(swDiags(h.ports[0]), ["sw-start v=0.1.1", "sw-msg playback", "sw-msg captions events=1", "sw-msg clear"]);

  h.advance(5000);
  h.relay.onMessage(playback(), SENDER);
  assert.equal(swDiags(h.ports[0]).at(-1), "sw-msg playback");
  assert.equal(swDiags(h.ports[0]).length, 5);
});

test("relay: untrusted senders are rejected, reported (rate limited) and not forwarded", () => {
  const h = relayHarness();
  h.relay.start();
  const strangers = [undefined, {}, { id: "someotherextensionidsomeotherext", url: SENDER.url }, { id: OWN, url: "https://evil.example/" }, { id: OWN }];
  for (const sender of strangers) h.relay.onMessage(playback(), sender);
  assert.deepEqual(h.ports[0].posted, []);
  assert.deepEqual(swDiags(h.ports[0]), ["sw-start v=0.1.1", "sw-reject untrusted"]);

  h.advance(5000);
  h.relay.onMessage(playback(), strangers[1]);
  assert.equal(swDiags(h.ports[0]).at(-1), "sw-reject untrusted");
  assert.equal(swDiags(h.ports[0]).length, 3);
});

test("relay: invalid messages are rejected by type word only, never echoing their content", () => {
  const h = relayHarness();
  h.relay.start();
  h.relay.onMessage({ v: 1, type: "playback", videoId: "short", title: "My Secret Title", time: 1, playing: true, rate: 1 }, SENDER);
  h.relay.onMessage({ v: 1, type: "captions", videoId: A, lang: "vi", kind: "standard", events: [] }, SENDER);
  h.relay.onMessage({ v: 1, type: "My Secret Title" }, SENDER);
  h.relay.onMessage("My Secret Title", SENDER);
  h.relay.onMessage(null, SENDER);
  h.relay.onMessage({ v: 1, type: "diag", where: "content", event: "my secret title" }, SENDER);
  assert.deepEqual(h.ports[0].posted, []);
  assert.deepEqual(swDiags(h.ports[0]), [
    "sw-start v=0.1.1",
    "sw-reject invalid playback",
    "sw-reject invalid captions",
    "sw-reject invalid unknown",
    "sw-reject invalid diag"
  ]);
  assert.equal(JSON.stringify(h.ports[0].diags).toLowerCase().includes("secret"), false);
});

test("relay: diag events of the content and page scripts are forwarded once per kind every 5 s; sw events cannot be forged", () => {
  const h = relayHarness();
  h.relay.start();
  const content = (event) => ({ v: 1, type: "diag", where: "content", event });
  const page = (event) => ({ v: 1, type: "diag", where: "page", event });

  h.relay.onMessage(content("content-start"), SENDER);
  h.relay.onMessage(content("content-start"), SENDER);
  h.relay.onMessage(page("page-timedtext json3 events=3"), SENDER);
  h.relay.onMessage(page("page-timedtext json3 events=9"), SENDER);
  assert.deepEqual(
    h.ports[0].diags.slice(1).map((message) => [message.where, message.event]),
    [["content", "content-start"], ["page", "page-timedtext json3 events=3"]]
  );

  // a content script cannot speak for the service worker
  h.relay.onMessage({ v: 1, type: "diag", where: "sw", event: "sw-msg playback" }, SENDER);
  const events = h.ports[0].diags.map((message) => message.event);
  assert.equal(events.includes("sw-msg playback"), false);
  assert.equal(events.at(-1), "sw-reject invalid diag");
  assert.equal(h.ports[0].diags.at(-1).where, "sw");
  for (const message of h.ports[0].diags) assertSafeDiag(message);
});

test("relay.start connects even when no diagnostic can be built", () => {
  const h = relayHarness({ captions: { ...C, buildDiag: () => null } });
  h.relay.start();
  assert.deepEqual(h.connects, ["io.lucasvu.mynotch.youtube"]);
  assert.deepEqual(h.ports[0].posted, []);
  assert.deepEqual(h.ports[0].diags, []);
});

// ---- injection into the YouTube tabs that were open before the extension loaded -------------------

const MANIFEST = JSON.parse(readSource("manifest.json"));

/** createInjector against fakes: `tabs` is what the query returns, the rest are the ways a tab can fail. */
function injectorHarness({ tabs = [], rejectFor = [], throwFor = [], rejectIsolatedFor = [], queryError = null, manifest = MANIFEST } = {}) {
  const h = { queries: [], calls: [], events: [], reported: [], logs: [] };
  h.injector = B.createInjector({
    manifest,
    queryTabs(query) {
      h.queries.push(query);
      return queryError ? Promise.reject(queryError) : Promise.resolve(tabs);
    },
    executeScript(injection) {
      const { tabId } = injection.target;
      const label = `${tabId} ${injection.world} ${injection.files.join("+")}`;
      h.calls.push(injection);
      h.events.push(`start ${label}`);
      if (throwFor.includes(tabId)) throw new TypeError("Cannot read properties of undefined (reading 'executeScript')");
      if (rejectFor.includes(tabId)) return Promise.reject(new Error("The tab was discarded."));
      if (injection.world === "ISOLATED" && rejectIsolatedFor.includes(tabId)) return Promise.reject(new Error("The tab was closed."));
      return Promise.resolve().then(() => {
        h.events.push(`end ${label}`);
        return [{ result: null }];
      });
    },
    report: (event) => h.reported.push(event),
    log: (text) => h.logs.push(text)
  });
  return h;
}

test("injector: every YouTube tab gets the manifest's two scripts, in order and worlds, in the top frame only", async () => {
  const h = injectorHarness({ tabs: [{ id: 7 }] });
  const result = await h.injector.injectIntoOpenTabs();

  assert.deepEqual(h.queries, [{ url: ["https://www.youtube.com/*"] }], "matched by URL; no tabs permission needed");
  assert.deepEqual(h.calls, [
    { target: { tabId: 7 }, files: ["captions-page.js", "page.js"], world: "MAIN" },
    { target: { tabId: 7 }, files: ["captions.js", "content.js"], world: "ISOLATED" }
  ]);
  for (const call of h.calls) {
    assert.equal(call.target.allFrames, undefined, "frame 0 only, like the manifest (no all_frames)");
    assert.equal(call.target.frameIds, undefined);
  }
  assert.deepEqual(h.events, [
    "start 7 MAIN captions-page.js+page.js",
    "end 7 MAIN captions-page.js+page.js",
    "start 7 ISOLATED captions.js+content.js",
    "end 7 ISOLATED captions.js+content.js"
  ], "the second injection starts only after the first one finished");
  assert.deepEqual(result, { tabs: 1, injected: 1, failed: 0 });
});

test("injector: no file is injected twice into a tab (Chrome would run it in one world only)", async () => {
  const h = injectorHarness({ tabs: [{ id: 7 }] });
  await h.injector.injectIntoOpenTabs();
  const files = h.calls.flatMap((call) => call.files);
  assert.deepEqual(files, [...new Set(files)], files.join(", "));
  assert.ok(files.length >= 4);
});

test("injector: the scripts, worlds and URLs come from the manifest, not from a copy that could drift", async () => {
  const manifest = {
    content_scripts: [
      { matches: ["https://a.example/*"], js: ["one.js", "two.js"], world: "MAIN" },
      { matches: ["https://a.example/*", "https://b.example/*"], js: ["three.js"] }
    ]
  };
  const h = injectorHarness({ tabs: [{ id: 1 }], manifest });
  await h.injector.injectIntoOpenTabs();
  assert.deepEqual(h.queries, [{ url: ["https://a.example/*", "https://b.example/*"] }]);
  assert.deepEqual(h.calls, [
    { target: { tabId: 1 }, files: ["one.js", "two.js"], world: "MAIN" },
    { target: { tabId: 1 }, files: ["three.js"], world: "ISOLATED" }
  ]);
});

test("injector: one diag after the pass, numbers only, valid for the closed grammar", async () => {
  const h = injectorHarness({ tabs: [{ id: 1 }, { id: 2 }, { id: 3 }] });
  await h.injector.injectIntoOpenTabs();
  assert.deepEqual(h.reported, ["sw-inject tabs=3 injected=3 failed=0"]);
  const message = C.buildDiag("sw", h.reported[0]);
  assert.ok(message, "accepted by captions.js");
  assertSafeDiag(message, "sw");
});

test("injector: a tab that fails (rejection, synchronous throw, no id) is counted, never thrown, and the others still get theirs", async () => {
  const h = injectorHarness({
    tabs: [{ id: 1 }, { id: 2 }, { id: 3 }, { url: "https://www.youtube.com/watch?v=aaaaaaaaaaa" }, { id: 5 }],
    rejectFor: [2],
    throwFor: [3]
  });
  const result = await h.injector.injectIntoOpenTabs();
  assert.deepEqual(result, { tabs: 5, injected: 2, failed: 3 });
  assert.deepEqual(h.reported, ["sw-inject tabs=5 injected=2 failed=3"]);
  const injectedTabs = h.calls.filter((call) => call.world === "ISOLATED").map((call) => call.target.tabId);
  assert.deepEqual(injectedTabs, [1, 5], "the isolated-world script went to the tabs that took the first one");
  assert.equal(JSON.stringify(h.reported).includes("youtube"), false, "no URL in the diag");
});

test("injector: a tab where only the second injection fails counts as failed", async () => {
  const h = injectorHarness({ tabs: [{ id: 1 }, { id: 2 }], rejectIsolatedFor: [1] });
  assert.deepEqual(await h.injector.injectIntoOpenTabs(), { tabs: 2, injected: 1, failed: 1 });
  assert.deepEqual(h.reported, ["sw-inject tabs=2 injected=1 failed=1"]);
});

test("injector: no open YouTube tab is reported as zeros", async () => {
  const h = injectorHarness({ tabs: [] });
  assert.deepEqual(await h.injector.injectIntoOpenTabs(), { tabs: 0, injected: 0, failed: 0 });
  assert.deepEqual(h.reported, ["sw-inject tabs=0 injected=0 failed=0"]);
  assert.deepEqual(h.calls, []);
});

test("injector: a failing tab query is logged, never thrown, and reports nothing", async () => {
  const h = injectorHarness({ queryError: new Error("boom") });
  assert.equal(await h.injector.injectIntoOpenTabs(), null);
  assert.deepEqual(h.reported, []);
  assert.equal(h.logs.length, 1);

  const throwing = B.createInjector({
    manifest: MANIFEST,
    queryTabs: () => {
      throw new TypeError("chrome.tabs is undefined");
    },
    executeScript: () => Promise.resolve([]),
    report: (event) => h.reported.push(event),
    log: (text) => h.logs.push(text)
  });
  assert.equal(await throwing.injectIntoOpenTabs(), null);
  assert.equal(h.logs.length, 2);
});

test("injector: it runs after an install or an update and after nothing else", async () => {
  for (const reason of ["install", "update"]) {
    const h = injectorHarness({ tabs: [{ id: 1 }] });
    await h.injector.onInstalled({ reason });
    assert.equal(h.queries.length, 1, reason);
    assert.deepEqual(h.reported, ["sw-inject tabs=1 injected=1 failed=0"], reason);
  }
  for (const details of [{ reason: "chrome_update" }, { reason: "shared_module_update" }, { reason: "unknown" }, {}, undefined, null]) {
    const h = injectorHarness({ tabs: [{ id: 1 }] });
    assert.equal(h.injector.onInstalled(details), undefined, JSON.stringify(details));
    await flush();
    assert.deepEqual(h.queries, [], JSON.stringify(details));
    assert.deepEqual(h.reported, []);
  }
});

test("relay exposes report() for the worker's own events, rate limited like the others", () => {
  const h = relayHarness();
  h.relay.start();
  h.relay.report("sw-inject tabs=1 injected=1 failed=0");
  h.relay.report("sw-inject tabs=2 injected=2 failed=0"); // same kind within 5 s
  assert.deepEqual(swDiags(h.ports[0]), ["sw-start v=0.1.1", "sw-inject tabs=1 injected=1 failed=0"]);
  h.advance(5000);
  h.relay.report("sw-inject tabs=2 injected=2 failed=0");
  assert.equal(swDiags(h.ports[0]).at(-1), "sw-inject tabs=2 injected=2 failed=0");
});

// ---- site access: Chrome can withhold the extension's host permission ("On click") -------------------

/** createAccessWatcher against fakes: `granted` is what permissions.contains answers right now. */
function accessHarness({ granted = true, containsError = null, containsThrows = null } = {}) {
  const h = { granted, queries: [], reported: [], logs: [], injections: 0 };
  h.watcher = B.createAccessWatcher({
    manifest: MANIFEST,
    contains(query) {
      h.queries.push(query);
      if (containsThrows) throw containsThrows;
      return containsError ? Promise.reject(containsError) : Promise.resolve(h.granted);
    },
    report: (event) => h.reported.push(event),
    onGranted: () => {
      h.injections += 1;
    },
    log: (text) => h.logs.push(text)
  });
  return h;
}

test("access: the start reports granted or withheld for the origins the manifest asks for", async () => {
  const granted = accessHarness({ granted: true });
  await granted.watcher.start();
  assert.deepEqual(granted.queries, [{ origins: ["https://www.youtube.com/*"] }]);
  assert.deepEqual(granted.reported, ["sw-access youtube=granted"]);

  const withheld = accessHarness({ granted: false });
  await withheld.watcher.start();
  assert.deepEqual(withheld.reported, ["sw-access youtube=withheld"]);
  for (const event of [...granted.reported, ...withheld.reported]) {
    const message = C.buildDiag("sw", event);
    assert.ok(message, event);
    assertSafeDiag(message, "sw");
  }
  assert.equal(granted.injections + withheld.injections, 0, "the start itself injects nothing (onInstalled does)");
});

test("access: when it becomes granted the open tabs are injected once; other changes only report", async () => {
  const h = accessHarness({ granted: false });
  await h.watcher.start();

  await h.watcher.onChanged(); // still withheld (some other permission changed)
  assert.equal(h.injections, 0);

  h.granted = true; // the user switched the site access to "On all sites"
  await h.watcher.onChanged();
  assert.equal(h.injections, 1);
  assert.deepEqual(h.reported, ["sw-access youtube=withheld", "sw-access youtube=withheld", "sw-access youtube=granted"]);

  await h.watcher.onChanged(); // granted again with nothing new
  assert.equal(h.injections, 1, "already granted: nothing new to inject");

  h.granted = false; // and back to "On click"
  await h.watcher.onChanged();
  assert.equal(h.injections, 1);
  assert.equal(h.reported.at(-1), "sw-access youtube=withheld");

  h.granted = true;
  await h.watcher.onChanged();
  assert.equal(h.injections, 2, "granted again after being withheld");
});

test("access: granted when nothing was known yet (the first check failed) still injects", async () => {
  const h = accessHarness({ granted: true });
  await h.watcher.onChanged();
  assert.equal(h.injections, 1);
});

test("access: a granted state at the start is not a change", async () => {
  const h = accessHarness({ granted: true });
  await h.watcher.start();
  await h.watcher.onChanged();
  assert.equal(h.injections, 0);
});

test("access: a failing contains() is logged, never thrown, and reports nothing", async () => {
  for (const options of [{ containsError: new Error("boom") }, { containsThrows: new TypeError("chrome.permissions is undefined") }]) {
    const h = accessHarness(options);
    await h.watcher.start();
    await h.watcher.onChanged();
    assert.deepEqual(h.reported, []);
    assert.equal(h.injections, 0);
    assert.equal(h.logs.length, 2);
  }
});

test("relay.reportState sends a state event when its value changes, however soon it flips back, and not when it repeats", () => {
  const h = relayHarness();
  h.relay.start();
  h.relay.reportState("sw-access youtube=withheld");
  h.relay.reportState("sw-access youtube=withheld"); // nothing new
  h.relay.reportState("sw-access youtube=granted"); // changed at once: not held back by the 5 s limit
  h.relay.reportState("sw-access youtube=withheld"); // and back again
  h.relay.reportState("sw-access youtube=withheld");
  assert.deepEqual(swDiags(h.ports[0]), [
    "sw-start v=0.1.1",
    "sw-access youtube=withheld",
    "sw-access youtube=granted",
    "sw-access youtube=withheld"
  ]);

  const restarted = relayHarness(); // a new worker has said nothing yet, so it says its state again
  restarted.relay.start();
  restarted.relay.reportState("sw-access youtube=withheld");
  assert.equal(swDiags(restarted.ports[0]).at(-1), "sw-access youtube=withheld");
});

test("relay.reportState ignores events that are not in the closed grammar", () => {
  const h = relayHarness();
  h.relay.start();
  h.relay.reportState("sw-access youtube=maybe");
  h.relay.reportState("my favourite song");
  assert.deepEqual(swDiags(h.ports[0]), ["sw-start v=0.1.1"]);
});

test("relay.reportState keeps trying while the host cannot be reached: the state counts as sent only once it was", () => {
  const h = relayHarness();
  h.connectError = new Error("Specified native messaging host not found.");
  h.relay.reportState("sw-access youtube=withheld");
  assert.equal(h.ports.length, 0, "nothing could be sent");

  h.connectError = null;
  h.advance(5000);
  h.relay.reportState("sw-access youtube=withheld"); // the same value is tried again, now that the host answers
  assert.deepEqual(swDiags(h.ports[0]).slice(-1), ["sw-access youtube=withheld"]);
  h.relay.reportState("sw-access youtube=withheld");
  assert.equal(swDiags(h.ports[0]).filter((event) => event === "sw-access youtube=withheld").length, 1);
});

// ---- commands from the host: native port -> relay -> the tab that last sent playback -----------------------

const NEXT = { v: 1, type: "command", action: "next" };
const PREVIOUS = { v: 1, type: "command", action: "previous" };
const senderInTab = (tabId) => ({ ...SENDER, tab: { id: tabId } });

test("a message the host writes to its stdout reaches the worker's handler while that port is the current one", () => {
  const h = harness();
  h.bridge.handle(playback());
  h.ports[0].receive(NEXT);
  assert.deepEqual(h.hostMessages, [NEXT]);

  // The port dropped and a new one took its place: a late message of the old one means nothing.
  h.ports[0].disconnect("Native host has exited.");
  h.advance(2000);
  h.bridge.handle(playback());
  h.ports[0].receive(PREVIOUS);
  assert.deepEqual(h.hostMessages, [NEXT]);
  h.ports[1].receive(PREVIOUS);
  assert.deepEqual(h.hostMessages, [NEXT, PREVIOUS]);
});

test("a handler that throws, or a port without onMessage, does not disturb the bridge", () => {
  const h = harness();
  h.onHost = () => {
    throw new Error("handler failed");
  };
  h.bridge.handle(playback());
  assert.doesNotThrow(() => h.ports[0].receive(NEXT));
  assert.equal(h.bridge.handle(playback(A, 2)), true, "the port is still in use");

  const plain = B.createBridge({
    connectNative: () => ({ onDisconnect: { addListener() {} }, postMessage() {} }),
    lastError: () => "",
    now: () => 1000000,
    log() {},
    onHostMessage() {}
  });
  assert.equal(plain.handle(playback()), true);
});

test("a bridge made without a handler does not listen to the host at all", () => {
  let listening = false;
  const bare = B.createBridge({
    connectNative: () => ({
      onDisconnect: { addListener() {} },
      onMessage: { addListener: () => (listening = true) },
      postMessage() {}
    }),
    lastError: () => "",
    now: () => 1000000,
    log() {}
  });
  bare.handle(playback());
  assert.equal(listening, false);
});

function commandHarness({ sendToTab } = {}) {
  const h = relayHarness({
    sendToTab:
      sendToTab ??
      ((tabId, message) => {
        h.toTabs.push({ tabId, message });
        return Promise.resolve({ ok: true });
      })
  });
  h.toTabs = [];
  h.onHost = (message) => h.relay.onHostMessage(message);
  h.relay.start();
  return h;
}

test("command: it goes to the tab that last sent a playback message, as the validated command only", async () => {
  const h = commandHarness();
  h.relay.onMessage(playback(), senderInTab(7));
  h.ports[0].receive(NEXT);
  h.ports[0].receive(PREVIOUS);
  await flush();
  assert.deepEqual(h.toTabs, [
    { tabId: 7, message: NEXT },
    { tabId: 7, message: PREVIOUS }
  ]);
  assert.deepEqual(Object.keys(h.toTabs[0].message), ["v", "type", "action"]);
  assert.deepEqual(swDiags(h.ports[0]), ["sw-start v=0.1.1", "sw-msg playback"], "a delivered command is not reported by the worker");
});

test("command: what reaches the tab is a fresh object built from the checked command, never the host's own", async () => {
  const h = commandHarness();
  h.relay.onMessage(playback(), senderInTab(7));
  const given = { v: 1, type: "command", action: "next" };
  h.ports[0].receive(given);
  await flush();
  assert.equal(h.toTabs.length, 1);
  assert.notEqual(h.toTabs[0].message, given);
  assert.deepEqual(h.toTabs[0].message, given);
  assert.deepEqual(Object.keys(h.toTabs[0].message), ["v", "type", "action"]);
});

test("command: the tab follows the latest playback; captions, clear, diag and rejected messages do not move it", async () => {
  const h = commandHarness();
  h.relay.onMessage(playback(), senderInTab(7));
  h.relay.onMessage(playback(Z), senderInTab(9));
  h.relay.onMessage(captions(A), senderInTab(7));
  h.relay.onMessage(clear(A), senderInTab(7));
  h.relay.onMessage({ v: 1, type: "diag", where: "content", event: "content-start" }, senderInTab(7));
  h.relay.onMessage(playback(), { ...senderInTab(7), id: "someotherextensionidsomeotherext" }); // not ours
  h.relay.onMessage({ ...playback(), rate: 0 }, senderInTab(7)); // invalid
  h.ports[0].receive(NEXT);
  await flush();
  assert.deepEqual(h.toTabs.map((sent) => sent.tabId), [9]);

  h.relay.onMessage(playback(), senderInTab(7));
  h.ports[0].receive(NEXT);
  await flush();
  assert.deepEqual(h.toTabs.map((sent) => sent.tabId), [9, 7]);
});

test("command: without a playback message there is no tab: nothing is sent and the worker says so", async () => {
  const h = commandHarness();
  h.ports[0].receive(NEXT);
  await flush();
  assert.deepEqual(h.toTabs, []);
  assert.deepEqual(swDiags(h.ports[0]), ["sw-start v=0.1.1", "sw-command-no-tab"]);
});

test("command: a sender without a usable tab id is not remembered", async () => {
  const h = commandHarness();
  for (const tab of [undefined, null, {}, { id: -1 }, { id: 1.5 }, { id: "7" }, { id: NaN }, { id: Infinity }, 7]) {
    h.relay.onMessage(playback(), { ...SENDER, tab });
  }
  h.ports[0].receive(NEXT);
  await flush();
  assert.deepEqual(h.toTabs, []);
  assert.equal(swDiags(h.ports[0]).at(-1), "sw-command-no-tab");

  h.relay.onMessage(playback(), senderInTab(0));
  h.ports[0].receive(NEXT);
  await flush();
  assert.deepEqual(h.toTabs.map((sent) => sent.tabId), [0], "tab 0 is a tab");
});

test("command: a tab that is gone (the send fails) is dropped and reported; the next playback sets a tab again", async () => {
  const calls = [];
  const h = commandHarness({
    sendToTab: (tabId) => {
      calls.push(tabId);
      return Promise.reject(new Error("Could not establish connection. Receiving end does not exist."));
    }
  });
  h.relay.onMessage(playback(), senderInTab(7));
  h.ports[0].receive(NEXT);
  await flush();
  assert.deepEqual(calls, [7]);
  assert.equal(swDiags(h.ports[0]).at(-1), "sw-command-no-tab");

  h.advance(5000); // past the diag window
  h.ports[0].receive(NEXT);
  await flush();
  assert.deepEqual(calls, [7], "no second attempt: the tab id was dropped");
  assert.equal(swDiags(h.ports[0]).filter((event) => event === "sw-command-no-tab").length, 2);

  h.relay.onMessage(playback(), senderInTab(8));
  h.ports[0].receive(NEXT);
  await flush();
  assert.deepEqual(calls, [7, 8]);
});

test("command: a failure for a tab that is no longer the current one keeps the current one", async () => {
  const calls = [];
  let failFirst = true;
  const h = commandHarness({
    sendToTab: (tabId) => {
      calls.push(tabId);
      if (failFirst) {
        failFirst = false;
        return new Promise((resolve, reject) => setImmediate(() => reject(new Error("gone"))));
      }
      return Promise.resolve();
    }
  });
  h.relay.onMessage(playback(), senderInTab(7));
  h.ports[0].receive(NEXT);
  h.relay.onMessage(playback(), senderInTab(8)); // before the failure of the first send is known
  await flush();
  h.advance(5000);
  h.ports[0].receive(NEXT);
  await flush();
  assert.deepEqual(calls, [7, 8]);
});

test("command: a send that throws at once is the same as a tab that is gone, and never an exception", async () => {
  const h = commandHarness({
    sendToTab: () => {
      throw new Error("Tabs cannot be edited right now");
    }
  });
  h.relay.onMessage(playback(), senderInTab(7));
  assert.doesNotThrow(() => h.ports[0].receive(NEXT));
  await flush();
  assert.equal(swDiags(h.ports[0]).at(-1), "sw-command-no-tab");
});

test("command: a worker made without a way to reach tabs reports no tab", async () => {
  const h = relayHarness();
  h.onHost = (message) => h.relay.onHostMessage(message);
  h.relay.start();
  h.relay.onMessage(playback(), senderInTab(7));
  assert.doesNotThrow(() => h.ports[0].receive(NEXT));
  await flush();
  assert.equal(swDiags(h.ports[0]).at(-1), "sw-command-no-tab");
});

test("command: anything but the closed command set from the host is rejected, reported once per 5 s, and never sent on", async () => {
  const h = commandHarness();
  h.relay.onMessage(playback(), senderInTab(7));
  const bad = [
    null, undefined, "next", 5, [], {}, ["next"],
    { v: 1, type: "command", action: "skip" },
    { v: 1, type: "command", action: "NEXT" },
    { v: 1, type: "command", action: "next", videoId: A },
    { v: 1, type: "command", action: "next", url: "https://example.invalid/" },
    { v: 2, type: "command", action: "next" },
    { v: 1, type: "playback", videoId: A, title: "x", time: 1, playing: true, rate: 1 },
    { v: 1, type: "diag", where: "sw", event: "sw-msg playback" },
    { v: 1, type: "clear", videoId: A }
  ];
  for (const message of bad) assert.doesNotThrow(() => h.ports[0].receive(message));
  await flush();
  assert.deepEqual(h.toTabs, []);
  assert.deepEqual(swDiags(h.ports[0]), ["sw-start v=0.1.1", "sw-msg playback", "sw-reject invalid command"]);

  h.advance(5000);
  h.ports[0].receive({ v: 1, type: "command", action: "skip" });
  assert.equal(swDiags(h.ports[0]).at(-1), "sw-reject invalid command");
});

test("command: a content script cannot send one through the worker's message handler", async () => {
  const h = commandHarness();
  h.relay.onMessage(playback(), senderInTab(7));
  h.relay.onMessage(NEXT, senderInTab(7));
  await flush();
  assert.deepEqual(h.toTabs, []);
  assert.deepEqual(h.ports[0].posted, [playback()], "and nothing of it goes to the host either");
  assert.equal(swDiags(h.ports[0]).at(-1), "sw-reject invalid unknown");
});

test("command: no diagnostic carries the tab id or anything else of the tab", async () => {
  const h = commandHarness({ sendToTab: () => Promise.reject(new Error("Receiving end does not exist for tab 4242")) });
  h.relay.onMessage(playback(), senderInTab(4242));
  h.ports[0].receive(NEXT);
  await flush();
  assert.equal(JSON.stringify(h.ports[0].diags).includes("4242"), false);
  assert.equal(JSON.stringify(h.infos).includes("4242"), false);
  assert.deepEqual(h.logs, []);
});
