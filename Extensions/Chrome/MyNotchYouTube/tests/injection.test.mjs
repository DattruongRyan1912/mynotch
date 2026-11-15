import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { assertSafeDiag, createContext, injectLikeChrome, plain, readSource } from "./helpers.mjs";

// The real manifest, injected the way Chrome does it into one isolated and one MAIN world of the same document.
const manifest = JSON.parse(readSource("manifest.json"));
const ORIGIN = "https://www.youtube.com";

class FakeXhr {
  open() {}
  addEventListener() {}
}

function makeWorlds(origin = ORIGIN) {
  const sent = [];
  const posted = [];
  const isolated = createContext({
    document: {
      title: "Placeholder - YouTube",
      querySelector: () => null,
      querySelectorAll: () => [],
      getElementById: () => null,
      addEventListener() {},
      removeEventListener() {}
    },
    location: { href: `${origin}/`, origin, hostname: new URL(origin).hostname },
    chrome: {
      runtime: {
        id: "extension-id",
        sendMessage(message) {
          sent.push(plain(message));
          return Promise.resolve(true);
        }
      }
    },
    addEventListener() {},
    removeEventListener() {},
    setInterval: () => 1,
    clearInterval() {}
  });
  const main = createContext({
    location: { href: `${origin}/`, origin },
    postMessage: (message) => posted.push(plain(message)),
    addEventListener() {},
    setTimeout() {},
    fetch: () => Promise.resolve(),
    XMLHttpRequest: FakeXhr
  });
  return { isolated, main, sent, posted };
}

test("the manifest's scripts start in both worlds: content.js reports content-start, page.js wraps fetch", () => {
  const worlds = makeWorlds();
  const originalFetch = worlds.main.fetch;
  const ran = injectLikeChrome(manifest, { MAIN: worlds.main, ISOLATED: worlds.isolated });

  assert.ok(ran.ISOLATED.includes("content.js") && ran.MAIN.includes("page.js"));
  const events = worlds.sent.filter((message) => message.type === "diag").map((message) => message.event);
  assert.ok(events.includes("content-start"), `content.js started in the isolated world: ${events.join(", ")}`);
  assert.equal(events.includes("content-no-lib"), false);
  for (const message of worlds.sent) if (message.type === "diag") assertSafeDiag(message, "content");

  assert.notEqual(worlds.main.fetch, originalFetch, "page.js wrapped fetch in the MAIN world");
  assert.equal(vm.runInContext("typeof __mynotchCaptions", worlds.main), "undefined", "and left no global behind");
});

test("with a file listed in both entries (the old manifest) content.js says content-no-lib instead of staying silent", () => {
  const old = {
    content_scripts: [
      { js: ["captions.js", "page.js"], world: "MAIN" },
      { js: ["captions.js", "content.js"] }
    ]
  };
  const worlds = makeWorlds();
  injectLikeChrome(old, { MAIN: worlds.main, ISOLATED: worlds.isolated });
  const events = worlds.sent.filter((message) => message.type === "diag").map((message) => message.event);
  assert.deepEqual(events, ["content-no-lib"]);
});

test("on a page that is not YouTube the manifest's scripts leave YouTube's content script silent and start the media tab script", () => {
  const worlds = makeWorlds("https://music.example.com");
  worlds.isolated.chrome.runtime.onMessage = { addListener() {}, removeListener() {} };
  const originalFetch = worlds.main.fetch;
  const ran = injectLikeChrome(
    { content_scripts: manifest.content_scripts.filter((entry) => !entry.matches.includes("https://www.youtube.com/*")) },
    { MAIN: worlds.main, ISOLATED: worlds.isolated }
  );
  assert.deepEqual(ran.ISOLATED, ["captions.js", "tabmessages.js", "content.js", "tabs.js"]);
  assert.deepEqual(ran.MAIN, ["mediasession-page.js"]);
  assert.deepEqual(worlds.sent, [], "nothing is said by a page with no media: no content-start, no content-no-lib");
  assert.equal(worlds.main.fetch, originalFetch, "and nothing wraps fetch");
  assert.equal(vm.runInContext("typeof Symbol.for('io.lucasvu.mynotch.tab.content') + typeof globalThis[Symbol.for('io.lucasvu.mynotch.tab.content')]", worlds.isolated), "symbolobject", "the media tab script is in place");
  assert.equal(vm.runInContext("typeof globalThis[Symbol.for('io.lucasvu.mynotch.yt.content')]", worlds.isolated), "undefined", "and YouTube's is not");
});
