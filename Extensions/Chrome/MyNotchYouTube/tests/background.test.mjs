import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { assertSafeDiag, createContext, flush, plain, readSource, runScripts } from "./helpers.mjs";

const OWN = "cccjddkmjjmnnccbgokidgbkpblogbnp";
const VERSION = JSON.parse(readSource("manifest.json")).version;
const SENDER = { id: OWN, url: "https://www.youtube.com/watch?v=aaaaaaaaaaa" };
const PLAYBACK = { v: 1, type: "playback", videoId: "aaaaaaaaaaa", title: "Placeholder title", time: 1, playing: true, rate: 1 };

/** Runs background.js the way the service worker does, against a fake chrome object. */
function startWorker({ connectThrows = null, tabs = [], rejectFor = [], queryThrows = null, access = true, noTabs = [] } = {}) {
  const worker = {
    connects: [], ports: [], listeners: [], installedListeners: [], addedListeners: [], removedListeners: [], infos: [],
    warnings: [], now: 1000000, queries: [], injections: [], accessQueries: [], access, tabMessages: [], noTabs, removedTabListeners: []
  };
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
          hostListeners: [],
          onDisconnect: { addListener: (fn) => disconnectListeners.push(fn) },
          onMessage: { addListener: (fn) => port.hostListeners.push(fn) },
          /** What the native host writes to its stdout. */
          receive: (message) => port.hostListeners.forEach((fn) => fn(message)),
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
      onMessage: { addListener: (fn) => worker.listeners.push(fn) },
      onInstalled: { addListener: (fn) => worker.installedListeners.push(fn) }
    },
    permissions: {
      contains(query) {
        worker.accessQueries.push(plain(query));
        return Promise.resolve(worker.access);
      },
      onAdded: { addListener: (fn) => worker.addedListeners.push(fn) },
      onRemoved: { addListener: (fn) => worker.removedListeners.push(fn) }
    },
    tabs: {
      onRemoved: { addListener: (fn) => worker.removedTabListeners.push(fn) },
      sendMessage(tabId, message, options) {
        worker.tabMessages.push(plain({ tabId, message, options }));
        if (worker.noTabs.includes(tabId)) return Promise.reject(new Error("Could not establish connection. Receiving end does not exist."));
        return Promise.resolve({ ok: true });
      },
      query(query) {
        worker.queries.push(plain(query));
        if (queryThrows) return Promise.reject(queryThrows);
        return Promise.resolve(tabs);
      }
    },
    scripting: {
      executeScript(injection) {
        worker.injections.push(plain(injection));
        if (rejectFor.includes(injection.target.tabId)) return Promise.reject(new Error("The tab was discarded."));
        return Promise.resolve([{ result: null }]);
      }
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
  assert.deepEqual(worker.diags().map((message) => message.event), [`sw-start v=${VERSION}`]);
  for (const message of worker.diags()) assertSafeDiag(message, "sw");
  assert.deepEqual(worker.infos, [`[MyNotch YouTube Bridge] sw-start v=${VERSION}`]);
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
  assert.deepEqual(worker.diags().map((message) => message.event), [`sw-start v=${VERSION}`, "sw-msg playback"]);

  worker.listeners[0]({ v: 1, type: "diag", where: "content", event: "content-start" }, SENDER);
  assert.equal(worker.diags().at(-1).event, "content-start");
  assert.equal(worker.diags().at(-1).where, "content");
});

test("untrusted senders and invalid messages are reported and never forwarded", () => {
  const worker = startWorker();
  worker.listeners[0](PLAYBACK, { id: "another", url: SENDER.url });
  worker.listeners[0]({ ...PLAYBACK, rate: 0 }, SENDER);
  assert.deepEqual(worker.protocol(), []);
  assert.deepEqual(worker.diags().map((message) => message.event), [`sw-start v=${VERSION}`, "sw-reject untrusted", "sw-reject invalid playback"]);
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

// ---- injection into the tabs that were open before the extension loaded -----------------------------

const YOUTUBE_TAB = (id) => ({ id, url: "https://www.youtube.com/watch?v=aaaaaaaaaaa" });
const MAIN_INJECTION = { files: ["captions-page.js", "page.js"], world: "MAIN" };
const ISOLATED_INJECTION = { files: ["captions.js", "tabmessages.js", "content.js", "tabs.js"], world: "ISOLATED" };
const SESSION_INJECTION = { files: ["mediasession-page.js"], world: "MAIN" };
const ALL_URLS = ["https://www.youtube.com/*", "http://*/*", "https://*/*"];

test("the worker listens for onInstalled from the moment it starts, and injects nothing before it fires", () => {
  const worker = startWorker({ tabs: [{ id: 1 }] });
  assert.equal(worker.installedListeners.length, 1, "registered synchronously, as MV3 requires");
  assert.deepEqual(worker.queries, []);
  assert.deepEqual(worker.injections, []);
});

test("after an update the open tabs get the scripts that name them and the host gets one sw-inject diag", async () => {
  const worker = startWorker({ tabs: [YOUTUBE_TAB(11), YOUTUBE_TAB(12), YOUTUBE_TAB(13)], rejectFor: [12] });
  worker.installedListeners[0]({ reason: "update", previousVersion: "0.1.1" });
  await flush();

  assert.deepEqual(worker.queries, [{ url: ALL_URLS }]);
  const of = (tabId) => worker.injections.filter(({ target }) => target.tabId === tabId).map(({ target, ...rest }) => rest);
  assert.deepEqual(of(11), [MAIN_INJECTION, ISOLATED_INJECTION, SESSION_INJECTION]);
  assert.deepEqual(of(12), [MAIN_INJECTION], "the first injection failed, so the others are not tried");
  assert.deepEqual(of(13), [MAIN_INJECTION, ISOLATED_INJECTION, SESSION_INJECTION]);
  assert.deepEqual(worker.diags().map((message) => message.event), [
    `sw-start v=${VERSION}`,
    "sw-access youtube=granted",
    "sw-inject tabs=3 injected=2 failed=1"
  ]);
  for (const message of worker.diags()) assertSafeDiag(message, "sw");
  assert.deepEqual(worker.warnings, []);
});

test("after an install the open tabs are injected too, a page that is not YouTube without the YouTube page's scripts", async () => {
  const worker = startWorker({ tabs: [{ id: 5, url: "https://music.example.com/" }] });
  worker.installedListeners[0]({ reason: "install" });
  await flush();
  assert.deepEqual(worker.injections.map(({ target, ...rest }) => rest), [ISOLATED_INJECTION, SESSION_INJECTION]);
  assert.equal(worker.diags().at(-1).event, "sw-inject tabs=1 injected=1 failed=0");
});

test("other onInstalled reasons inject nothing", async () => {
  const worker = startWorker({ tabs: [{ id: 5 }] });
  worker.installedListeners[0]({ reason: "chrome_update" });
  worker.installedListeners[0]({ reason: "shared_module_update" });
  await flush();
  assert.deepEqual(worker.queries, []);
  assert.deepEqual(worker.injections, []);
});

test("a failing tab query does not break the worker and reports nothing", async () => {
  const worker = startWorker({ queryThrows: new Error("boom") });
  assert.doesNotThrow(() => worker.installedListeners[0]({ reason: "update" }));
  await flush();
  assert.deepEqual(worker.diags().map((message) => message.event), [`sw-start v=${VERSION}`, "sw-access youtube=granted"]);
  assert.doesNotThrow(() => worker.listeners[0](PLAYBACK, SENDER));
});

test("no tab permission is used: the worker only reads tab ids", async () => {
  const worker = startWorker({ tabs: [{ id: 3, url: "https://www.youtube.com/watch?v=aaaaaaaaaaa", title: "A Secret Title" }] });
  worker.installedListeners[0]({ reason: "update" });
  await flush();
  assert.equal(JSON.stringify(worker.injections).includes("Secret"), false);
  assert.equal(JSON.stringify(worker.ports[0].messages).includes("Secret"), false);
  assert.equal(JSON.stringify(worker.ports[0].messages).includes("watch"), false);
});

// ---- site access ------------------------------------------------------------------------------------

test("the worker reports whether Chrome granted it access to YouTube right after sw-start", async () => {
  const granted = startWorker({ access: true });
  await flush();
  assert.deepEqual(granted.accessQueries, [{ origins: ["https://www.youtube.com/*"] }]);
  assert.deepEqual(granted.diags().map((message) => message.event), [`sw-start v=${VERSION}`, "sw-access youtube=granted"]);

  const withheld = startWorker({ access: false });
  await flush();
  assert.deepEqual(withheld.diags().map((message) => message.event), [`sw-start v=${VERSION}`, "sw-access youtube=withheld"]);
  for (const message of withheld.diags()) assertSafeDiag(message, "sw");
});

test("permission changes are listened for from the start, and a grant injects the tabs that were waiting", async () => {
  const worker = startWorker({ access: false, tabs: [YOUTUBE_TAB(21), YOUTUBE_TAB(22)] });
  assert.equal(worker.addedListeners.length, 1, "onAdded registered synchronously");
  assert.equal(worker.removedListeners.length, 1, "onRemoved registered synchronously");
  await flush();
  assert.deepEqual(worker.injections, [], "nothing is injected while the access is withheld");

  worker.access = true; // Site access switched to "On all sites" in chrome://extensions
  worker.addedListeners[0]({ origins: ["https://www.youtube.com/*"] });
  await flush();
  assert.deepEqual(
    worker.injections.filter(({ target }) => target.tabId === 21).map(({ world }) => world),
    ["MAIN", "ISOLATED", "MAIN"]
  );
  assert.deepEqual(worker.injections.filter(({ target }) => target.tabId === 22).length, 3);
  assert.deepEqual(
    worker.diags().map((message) => message.event).slice(1),
    ["sw-access youtube=withheld", "sw-access youtube=granted", "sw-inject tabs=2 injected=2 failed=0"],
    "a quick change is reported, not held back by the rate limit"
  );
});

test("withdrawing the access is reported and injects nothing", async () => {
  const worker = startWorker({ access: true, tabs: [{ id: 1 }] });
  await flush();
  worker.access = false;
  worker.removedListeners[0]({ origins: ["https://www.youtube.com/*"] });
  await flush();
  assert.equal(worker.diags().at(-1).event, "sw-access youtube=withheld");
  assert.deepEqual(worker.injections, []);
});

// ---- commands from the app: host -> worker -> the tab that last sent playback ------------------------------

const TAB_SENDER = (tabId) => ({ ...SENDER, tab: { id: tabId } });
const NEXT = { v: 1, type: "command", action: "next" };
const PREVIOUS = { v: 1, type: "command", action: "previous" };

test("a command the host writes goes to the top frame of the tab that last sent playback, nothing else", async () => {
  const worker = startWorker();
  worker.listeners[0](PLAYBACK, TAB_SENDER(31));
  worker.ports[0].receive(NEXT);
  worker.ports[0].receive(PREVIOUS);
  await flush();
  assert.deepEqual(worker.tabMessages, [
    { tabId: 31, message: NEXT, options: { frameId: 0 } },
    { tabId: 31, message: PREVIOUS, options: { frameId: 0 } }
  ]);
  assert.deepEqual(worker.warnings, []);
});

test("a tab that is gone: the command is dropped and the worker reports sw-command-no-tab", async () => {
  const worker = startWorker({ noTabs: [31] });
  await flush();
  worker.listeners[0](PLAYBACK, TAB_SENDER(31));
  worker.ports[0].receive(NEXT);
  await flush();
  assert.equal(worker.diags().at(-1).event, "sw-command-no-tab");
  assertSafeDiag(worker.diags().at(-1), "sw");
  worker.advance(5000);
  worker.ports[0].receive(NEXT);
  await flush();
  assert.equal(worker.tabMessages.length, 1, "no second try at a tab that is gone");
});

test("a worker that has seen no playback has no tab to give a command to", async () => {
  const worker = startWorker();
  await flush();
  worker.ports[0].receive(NEXT);
  await flush();
  assert.deepEqual(worker.tabMessages, []);
  assert.equal(worker.diags().at(-1).event, "sw-command-no-tab");
});

test("commands arrive only from the native port: a content script's message is not one", async () => {
  const worker = startWorker();
  await flush();
  worker.listeners[0](PLAYBACK, TAB_SENDER(31));
  worker.listeners[0](NEXT, TAB_SENDER(31));
  await flush();
  assert.deepEqual(worker.tabMessages, []);
  assert.equal(worker.diags().at(-1).event, "sw-reject invalid unknown");
});

test("a command the host writes after it has gone is ignored, and the tab id is kept in memory only", async () => {
  const worker = startWorker();
  worker.listeners[0](PLAYBACK, TAB_SENDER(31));
  worker.ports[0].disconnect("Native host has exited.");
  worker.advance(5000);
  worker.ports[0].receive(NEXT);
  await flush();
  assert.deepEqual(worker.tabMessages, []);
  // Nothing of the tab is written anywhere: the worker has no storage API to write it to.
  const source = readSource("background.js") + readSource("bridge.js");
  assert.equal(/chrome\.storage|localStorage|indexedDB|sessionStorage/.test(source), false);
});

test("an invalid command from the host is reported as such and never reaches the tab", async () => {
  const worker = startWorker();
  await flush();
  worker.listeners[0](PLAYBACK, TAB_SENDER(31));
  worker.ports[0].receive({ v: 1, type: "command", action: "seek" });
  worker.ports[0].receive("next");
  await flush();
  assert.deepEqual(worker.tabMessages, []);
  assert.equal(worker.diags().at(-1).event, "sw-reject invalid command");
});


// ---- media tabs: the pages report, the app asks --------------------------------------------------------

const WEB_SENDER = (tabId, url = "https://music.example.com/album") => ({ id: OWN, url, tab: { id: tabId }, frameId: 0 });
const REPORT = {
  v: 1, type: "tab-report", site: "music.example.com", title: "Song", artist: "Artist", album: "", state: "playing",
  time: 12.5, duration: 200, rate: 1, live: false
};

test("the worker listens for closed tabs from the moment it starts (no permission is needed for it)", () => {
  const worker = startWorker();
  assert.equal(worker.removedTabListeners.length, 1, "registered synchronously, as MV3 requires");
  assert.equal(readSource("manifest.json").includes('"tabs"'), false);
});

test("a report from a page on any site reaches the host as `tab` with the tab's id, and closing the tab says it is gone", async () => {
  const worker = startWorker();
  await flush(); // the access report is on its way as the worker starts
  worker.listeners[0](REPORT, WEB_SENDER(41, "https://music.example.com/private-path?token=xyz"));
  worker.removedTabListeners[0](41);
  worker.removedTabListeners[0](42); // a tab that never had media
  await flush();
  assert.deepEqual(worker.protocol().map((message) => [message.type, message.tab]), [["tab", 41], ["tabgone", 41]]);
  assert.equal(worker.protocol()[0].title, "Song");
  assert.deepEqual(worker.diags().map((message) => message.event), [`sw-start v=${VERSION}`, "sw-access youtube=granted", "sw-msg tab"]);
  for (const message of worker.diags()) assertSafeDiag(message, "sw");
  // The host gets the site's host name and nothing of the page's address.
  for (const secret of ["private-path", "token", "xyz", "https", "://"]) {
    assert.equal(JSON.stringify(worker.ports[0].messages).includes(secret), false, secret);
  }
});

test("a tabcommand the host writes goes to the top frame of the tab it names, and what a tab says of it reaches the host", async () => {
  const worker = startWorker();
  worker.ports[0].receive({ v: 1, type: "tabcommand", tab: 41, action: "seek", seconds: 30 });
  await flush();
  assert.deepEqual(worker.tabMessages, [
    { tabId: 41, message: { v: 1, type: "tabcommand", tab: 41, action: "seek", seconds: 30 }, options: { frameId: 0 } }
  ]);
  worker.listeners[0]({ v: 1, type: "diag", where: "content", event: "content-tabcommand seek ok" }, WEB_SENDER(41));
  assert.equal(worker.diags().at(-1).event, "content-tabcommand seek ok");
  assertSafeDiag(worker.diags().at(-1), "content");
});

test("a tab that is gone: the command is dropped, the app is told the tab is gone, and the worker reports sw-tabcommand-no-tab", async () => {
  const worker = startWorker({ noTabs: [41] });
  await flush();
  worker.ports[0].receive({ v: 1, type: "tabcommand", tab: 41, action: "play" });
  await flush();
  assert.deepEqual(worker.protocol().map((message) => [message.type, message.tab]), [["tabgone", 41]]);
  assert.equal(worker.diags().at(-1).event, "sw-tabcommand-no-tab");
  assertSafeDiag(worker.diags().at(-1), "sw");
});

test("a page's script cannot send a command, nor can a page pose as the worker", async () => {
  const worker = startWorker();
  await flush();
  worker.listeners[0]({ v: 1, type: "tabcommand", tab: 41, action: "play" }, WEB_SENDER(41));
  worker.listeners[0]({ v: 1, type: "diag", where: "sw", event: "sw-tabcommand-no-tab" }, WEB_SENDER(41));
  await flush();
  assert.deepEqual(worker.tabMessages, []);
  assert.deepEqual(worker.protocol(), []);
  assert.equal(worker.diags().at(-1).event, "sw-reject untrusted", "an unknown message from a web page is not trusted");
});
