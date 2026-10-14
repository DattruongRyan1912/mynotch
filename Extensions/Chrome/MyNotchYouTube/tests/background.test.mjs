import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { assertSafeDiag, createContext, plain, readSource, runScripts } from "./helpers.mjs";

const OWN = "cccjddkmjjmnnccbgokidgbkpblogbnp";
const SENDER = { id: OWN, url: "https://www.youtube.com/watch?v=aaaaaaaaaaa" };
const PLAYBACK = { v: 1, type: "playback", videoId: "aaaaaaaaaaa", title: "Placeholder title", time: 1, playing: true, rate: 1 };

/** Runs background.js the way the service worker does, against a fake chrome object. */
function startWorker({ connectThrows = null } = {}) {
  const worker = { connects: [], ports: [], listeners: [], infos: [], warnings: [], now: 1000000 };
  const chrome = {
    runtime: {
      id: OWN,
      lastError: undefined,
      getManifest: () => JSON.parse(readSource("manifest.json")),
      connectNative(name) {
        worker.connects.push(name);
        if (connectThrows) throw connectThrows;
        const disconnectListeners = [];
        const port = {
          messages: [],
          onDisconnect: { addListener: (fn) => disconnectListeners.push(fn) },
          postMessage: (message) => port.messages.push(plain(message)),
          disconnect(reason) {
            chrome.runtime.lastError = reason ? { message: reason } : undefined;
            disconnectListeners.forEach((fn) => fn());
            chrome.runtime.lastError = undefined;
          }
        };
        worker.ports.push(port);
        return port;
      },
      onMessage: { addListener: (fn) => worker.listeners.push(fn) }
    }
  };
  const context = createContext({
    chrome,
    console: { info: (text) => worker.infos.push(text), warn: (text) => worker.warnings.push(text) },
    importScripts: (...names) => runScripts(context, names)
  });
  vm.runInContext("self = globalThis; Date.now = () => __now", context);
  context.__now = worker.now;
  worker.context = context;
  worker.advance = (ms) => {
    context.__now += ms;
  };
  runScripts(context, ["background.js"]);
  worker.diags = (index = 0) => worker.ports[index].messages.filter((message) => message.type === "diag");
  worker.protocol = (index = 0) => worker.ports[index].messages.filter((message) => message.type !== "diag");
  return worker;
}

test("the worker registers its message listener and connects to the native host as soon as it starts", () => {
  const worker = startWorker();
  assert.equal(worker.listeners.length, 1, "onMessage listener registered synchronously");
  assert.deepEqual(worker.connects, ["io.lucasvu.mynotch.youtube"], "no message was needed to connect");
  assert.deepEqual(worker.diags().map((message) => message.event), ["sw-start v=0.1.1"]);
  for (const message of worker.diags()) assertSafeDiag(message, "sw");
  assert.deepEqual(worker.infos, ["[MyNotch YouTube Bridge] sw-start v=0.1.1"]);
  assert.deepEqual(worker.warnings, []);
});

test("the version in sw-start is the manifest's version", () => {
  const manifest = JSON.parse(readSource("manifest.json"));
  const worker = startWorker();
  assert.equal(worker.diags()[0].event, `sw-start v=${manifest.version}`);
});

test("messages from the content script are validated, reported and forwarded to the host", () => {
  const worker = startWorker();
  worker.listeners[0](PLAYBACK, SENDER);
  assert.deepEqual(worker.protocol(), [PLAYBACK]);
  assert.deepEqual(worker.diags().map((message) => message.event), ["sw-start v=0.1.1", "sw-msg playback"]);

  worker.listeners[0]({ v: 1, type: "diag", where: "content", event: "content-start" }, SENDER);
  assert.equal(worker.diags().at(-1).event, "content-start");
  assert.equal(worker.diags().at(-1).where, "content");
});

test("untrusted senders and invalid messages are reported and never forwarded", () => {
  const worker = startWorker();
  worker.listeners[0](PLAYBACK, { id: "another", url: SENDER.url });
  worker.listeners[0]({ ...PLAYBACK, rate: 0 }, SENDER);
  assert.deepEqual(worker.protocol(), []);
  assert.deepEqual(worker.diags().map((message) => message.event), ["sw-start v=0.1.1", "sw-reject untrusted", "sw-reject invalid playback"]);
});

test("a host that is not installed: no exception, no spam, the reason is reported after the next connect", () => {
  const worker = startWorker();
  worker.ports[0].disconnect("Specified native messaging host not found.");
  assert.equal(worker.warnings.length, 1, "one warning for the failure");

  worker.listeners[0](PLAYBACK, SENDER); // inside the backoff window
  assert.equal(worker.connects.length, 1);
  assert.equal(worker.warnings.length, 1);

  worker.advance(5000);
  worker.listeners[0](PLAYBACK, SENDER);
  assert.equal(worker.connects.length, 2);
  assert.deepEqual(worker.diags(1).map((message) => message.event), ["sw-reconnect after=host-not-found failures=1", "sw-msg playback"]);
  assert.deepEqual(worker.protocol(1), [PLAYBACK]);
});

test("connectNative throwing at start does not break the worker", () => {
  const worker = startWorker({ connectThrows: new Error("Native messaging is not available") });
  assert.equal(worker.listeners.length, 1);
  assert.equal(worker.connects.length, 1);
  assert.equal(worker.warnings.length, 1);
  assert.doesNotThrow(() => worker.listeners[0](PLAYBACK, SENDER));
});

test("every message is acknowledged so the sender's promise resolves", () => {
  const worker = startWorker();
  const acks = [];
  worker.listeners[0](PLAYBACK, SENDER, (value) => acks.push(value));
  worker.listeners[0](PLAYBACK, { id: "another", url: SENDER.url }, (value) => acks.push(value));
  worker.listeners[0]({ garbage: true }, SENDER, (value) => acks.push(value));
  assert.deepEqual(acks, [true, true, true]);
  assert.equal(worker.listeners[0](PLAYBACK, SENDER), undefined, "and it does not keep the channel open");
});
