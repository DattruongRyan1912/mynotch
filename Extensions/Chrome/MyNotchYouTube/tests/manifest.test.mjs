import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { extensionDir, readSource } from "./helpers.mjs";

const manifest = JSON.parse(readSource("manifest.json"));

/** Chrome's extension id: SHA-256 of the DER public key, first 32 hex digits mapped 0-9a-f to a-p. */
function idFromKey(base64Key) {
  const hex = crypto.createHash("sha256").update(Buffer.from(base64Key, "base64")).digest("hex").slice(0, 32);
  return [...hex].map((digit) => String.fromCharCode("a".charCodeAt(0) + parseInt(digit, 16))).join("");
}

test("manifest has the expected MV3 fields", () => {
  assert.equal(manifest.manifest_version, 3);
  assert.equal(manifest.name, "MyNotch YouTube Bridge");
  assert.equal(manifest.version, "0.1.0");
  assert.match(manifest.description, /^[\x20-\x7e]+$/, "English (ASCII) description");
  assert.ok(manifest.description.length > 20 && manifest.description.length <= 132);
  assert.deepEqual(manifest.permissions, ["nativeMessaging"]);
  assert.deepEqual(manifest.host_permissions, ["https://www.youtube.com/*"]);
  assert.equal(manifest.background.service_worker, "background.js");
  assert.ok(Number(manifest.minimum_chrome_version) >= 111, "world: MAIN content scripts need Chrome 111");
});

test("content scripts: page.js in the MAIN world, content.js isolated, both at document_start", () => {
  const [main, isolated, ...rest] = manifest.content_scripts;
  assert.deepEqual(rest, []);
  assert.deepEqual(main.matches, ["https://www.youtube.com/*"]);
  assert.deepEqual(main.js, ["captions.js", "page.js"]);
  assert.equal(main.world, "MAIN");
  assert.equal(main.run_at, "document_start");
  assert.deepEqual(isolated.matches, ["https://www.youtube.com/*"]);
  assert.deepEqual(isolated.js, ["captions.js", "content.js"]);
  assert.ok(isolated.world === undefined || isolated.world === "ISOLATED");
  assert.equal(isolated.run_at, "document_start");
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
  for (const file of ["captions.js", "content.js", "background.js", "bridge.js"]) {
    const source = readSource(file);
    assert.equal(/\bfetch\s*\(|XMLHttpRequest|WebSocket|sendBeacon|EventSource/.test(source), false, file);
  }
  // page.js only wraps the page's own fetch/XHR and never calls them with a URL of its own.
  const page = readSource("page.js");
  assert.equal(/\bfetch\s*\(|sendBeacon|WebSocket|new XMLHttpRequest/.test(page), false);
});
