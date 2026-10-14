import test from "node:test";
import assert from "node:assert/strict";
import { loadBridge } from "./helpers.mjs";

const B = loadBridge();
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
        posted: [],
        dead: false,
        onDisconnect: { addListener: (fn) => listeners.push(fn) },
        postMessage(message) {
          if (port.dead) throw new Error("Attempting to use a disconnected port object");
          port.posted.push(message);
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
    log: (text) => h.logs.push(text)
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
