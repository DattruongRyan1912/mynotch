import test from "node:test";
import assert from "node:assert/strict";
import { assertSafeDiag, loadBridge, loadCaptions } from "./helpers.mjs";

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
  const h = { time: 1000000, ports: [], connects: [], logs: [], lastErrorReads: 0, lastError: "", connectError: null };
  h.bridge = B.createBridge({
    connectNative(name) {
      h.connects.push(name);
      if (h.connectError) throw h.connectError;
      const listeners = [];
      const port = {
        posted: [], // protocol messages
        diags: [], // diag messages

        dead: false,
        onDisconnect: { addListener: (fn) => listeners.push(fn) },
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
    buildDiag: C.buildDiag
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
