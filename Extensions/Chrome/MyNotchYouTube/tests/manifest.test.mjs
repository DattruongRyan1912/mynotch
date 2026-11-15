import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { extensionDir, injectLikeChrome, readSource } from "./helpers.mjs";

const manifest = JSON.parse(readSource("manifest.json"));

/** Chrome's extension id: SHA-256 of the DER public key, first 32 hex digits mapped 0-9a-f to a-p. */
function idFromKey(base64Key) {
  const hex = crypto.createHash("sha256").update(Buffer.from(base64Key, "base64")).digest("hex").slice(0, 32);
  return [...hex].map((digit) => String.fromCharCode("a".charCodeAt(0) + parseInt(digit, 16))).join("");
}

test("manifest has the expected MV3 fields", () => {
  assert.equal(manifest.manifest_version, 3);
  assert.equal(manifest.name, "MyNotch Web Companion");
  assert.equal(manifest.version, "0.2.6");
  assert.match(manifest.description, /^[\x20-\x7e]+$/, "English (ASCII) description");
  assert.ok(manifest.description.length > 20 && manifest.description.length <= 132);
  // `scripting` is for injecting the content scripts into the tabs that were open before the extension loaded;
  // the host permissions below are what let it do so (and match them by URL), so there is no `tabs` permission.
  // Web pages need them because any page may play media that MyNotch shows; it is only ever text that leaves a page.
  assert.deepEqual(manifest.permissions, ["nativeMessaging", "scripting"]);
  // Plain http only for this Mac's own players (localhost, any port): an http page can be changed on its way, and the media this is for is on https.
  assert.deepEqual(manifest.host_permissions, ["https://*/*", "http://localhost/*"]);
  assert.equal(manifest.background.service_worker, "background.js");
  assert.ok(Number(manifest.minimum_chrome_version) >= 111, "world: MAIN content scripts need Chrome 111");
});

test("content scripts: page.js in the MAIN world on YouTube only; on every web page the media tab scripts in every frame, YouTube's content script and the Media Session hook in the top frame; all at document_start", () => {
  const [main, frames, content, session, ...rest] = manifest.content_scripts;
  assert.deepEqual(rest, []);
  assert.deepEqual(main.matches, ["https://www.youtube.com/*"]);
  assert.deepEqual(main.js, ["captions-page.js", "page.js"]);
  assert.equal(main.world, "MAIN");
  // A film site's player is often a frame of another site: the media tab script runs in every frame, its report is the page's.
  assert.deepEqual(frames.matches, ["https://*/*", "http://localhost/*"]);
  assert.deepEqual(frames.js, ["captions.js", "tabmessages.js", "tabs.js"]);
  assert.equal(frames.all_frames, true);
  // content.js is YouTube's, and does nothing on any other page (it checks the origin); it comes after the captions API it needs,
  // in the same world, and Chrome runs a file once per document, so it is not listed again.
  assert.deepEqual(content.matches, ["https://*/*", "http://localhost/*"]);
  assert.deepEqual(content.js, ["content.js"]);
  assert.deepEqual(session.matches, ["https://*/*", "http://localhost/*"]);
  assert.deepEqual(session.js, ["mediasession-page.js"]);
  assert.equal(session.world, "MAIN");
  for (const entry of [frames, content]) assert.ok(entry.world === undefined || entry.world === "ISOLATED");
  for (const entry of manifest.content_scripts) {
    assert.equal(entry.run_at, "document_start");
    if (entry !== frames) assert.equal(entry.all_frames, undefined, "the top frame only");
    assert.equal(entry.match_about_blank, undefined);
    assert.equal(entry.match_origin_as_fallback, undefined);
  }
});

test("the extension's id and the host's allowed origin are untouched by the change of permissions", () => {
  assert.equal(manifest.key.length, 392);
  assert.ok(manifest.key.startsWith("MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEArhpwZaHc"));
});

test("every file the manifest and the service worker reference exists", () => {
  const files = [manifest.background.service_worker, ...manifest.content_scripts.flatMap((entry) => entry.js)];
  for (const importScriptsName of readSource("background.js").matchAll(/importScripts\(([^)]*)\)/g)) {
    files.push(...[...importScriptsName[1].matchAll(/"([^"]+)"/g)].map((match) => match[1]));
  }
  assert.ok(files.includes("bridge.js"));
  for (const file of new Set(files)) assert.ok(fs.existsSync(path.join(extensionDir, file)), file);
});

test("manifest key is a 2048-bit RSA public key (SubjectPublicKeyInfo)", () => {
  const key = crypto.createPublicKey({ key: Buffer.from(manifest.key, "base64"), format: "der", type: "spki" });
  assert.equal(key.asymmetricKeyType, "rsa");
  assert.equal(key.asymmetricKeyDetails.modulusLength, 2048);
  assert.equal(manifest.key, Buffer.from(manifest.key, "base64").toString("base64"), "plain base64, no line breaks");
});

test("EXTENSION_ID is one line without a newline and matches the id computed from the key", () => {
  const raw = fs.readFileSync(path.join(extensionDir, "EXTENSION_ID"), "utf8");
  assert.match(raw, /^[a-p]{32}$/);
  assert.equal(raw, idFromKey(manifest.key));
});

test("no private key or other secret material is part of the extension folder", () => {
  const walk = (dir) =>
    fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
      const full = path.join(dir, entry.name);
      return entry.isDirectory() ? walk(full) : [full];
    });
  for (const file of walk(extensionDir)) {
    assert.equal(/\.(pem|key|crx|der|p12|pfx)$/i.test(file), false, file);
    const text = fs.readFileSync(file, "utf8");
    assert.equal(/-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(text), false, file);
  }
});

test("the scripts never touch the network themselves", () => {
  for (const file of ["captions.js", "content.js", "background.js", "bridge.js", "tabmessages.js", "tabs.js", "mediasession-page.js"]) {
    const source = readSource(file);
    assert.equal(/\bfetch\s*\(|XMLHttpRequest|WebSocket|sendBeacon|EventSource/.test(source), false, file);
  }
  // page.js only wraps the page's own fetch/XHR and never calls them with a URL of its own.
  const page = readSource("page.js");
  assert.equal(/\bfetch\s*\(|sendBeacon|WebSocket|new XMLHttpRequest/.test(page), false);
});

test("no script file is listed in more than one content_scripts entry (Chrome injects it once per document, in one world)", () => {
  const files = manifest.content_scripts.flatMap((entry) => entry.js);
  assert.deepEqual(files, [...new Set(files)], `a file is listed twice: ${files.join(", ")}`);
});

test("every world gets all the files its entry lists, with Chrome's one-injection-per-file rule applied", () => {
  const ran = injectLikeChrome(manifest, null);
  for (const entry of manifest.content_scripts) {
    const world = entry.world === "MAIN" ? "MAIN" : "ISOLATED";
    assert.deepEqual(ran[world].filter((file) => entry.js.includes(file)), entry.js, `${world} world`);
  }
  assert.ok(ran.ISOLATED.includes("captions.js") && ran.ISOLATED.includes("content.js"), "the isolated world has the captions API and content.js");
  assert.ok(ran.MAIN.includes("page.js"));
});

test("injectLikeChrome reproduces the old manifest's bug: the shared file never reaches the second world", () => {
  const old = {
    content_scripts: [
      { js: ["captions.js", "page.js"], world: "MAIN" },
      { js: ["captions.js", "content.js"] }
    ]
  };
  assert.deepEqual(injectLikeChrome(old, null), { MAIN: ["captions.js", "page.js"], ISOLATED: ["content.js"] });
});

test("captions-page.js (the MAIN world's copy of captions.js) is byte-identical; refresh it with: cp captions.js captions-page.js", () => {
  const a = fs.readFileSync(path.join(extensionDir, "captions.js"));
  const b = fs.readFileSync(path.join(extensionDir, "captions-page.js"));
  assert.ok(a.equals(b), "captions-page.js differs from captions.js");
});
