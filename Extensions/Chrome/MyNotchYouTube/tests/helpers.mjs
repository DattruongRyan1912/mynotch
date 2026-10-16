import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

export const extensionDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

export function readSource(name) {
  return fs.readFileSync(path.join(extensionDir, name), "utf8");
}

/**
 * Creates a fresh context holding only what the test hands in, and runs extension scripts in it
 * the way Chrome does (classic scripts, no `module`). Objects created inside have another
 * realm's prototypes, so compare them through plain().
 */
export function createContext(globals = {}) {
  const context = { URL, URLSearchParams, ...globals };
  vm.createContext(context);
  return context;
}

export function runScripts(context, names) {
  for (const name of names) vm.runInContext(readSource(name), context, { filename: name });
  return context;
}

/** Copies a value into this realm so deepStrictEqual can compare it. */
export function plain(value) {
  return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
}

/** Loads a pure script into the test's own realm as a classic script and returns its API. */
export function loadPure(name, exportName) {
  vm.runInThisContext(readSource(name), { filename: name });
  const api = globalThis[exportName];
  delete globalThis[exportName];
  return api;
}

export const loadCaptions = () => loadPure("captions.js", "__mynotchCaptions");
export const loadBridge = () => loadPure("bridge.js", "__mynotchBridge");
export const loadTabs = () => loadPure("tabmessages.js", "__mynotchTabs");

/** Lets pending promise callbacks run. */
export async function flush(times = 8) {
  for (let i = 0; i < times; i++) await new Promise((resolve) => setImmediate(resolve));
}

/** The pattern of a video id as a standalone token: exactly 11 characters of [A-Za-z0-9_-]. */
export const ID_TOKEN = /(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{11}(?![A-Za-z0-9_-])/;

/**
 * What the id-lookalike scan looks at. The arguments of `content-command` and `content-tabcommand` are a closed list of words, one of which
 * ("unavailable") is exactly 11 letters long, so only its code is scanned, as in captions.js and YouTubeDiag.swift.
 */
export const scannedForIds = (event) => (/^content-(?:tab)?command /.test(event) ? event.split(" ")[0] : event);

/**
 * What every diag message must satisfy, wherever it was produced: a valid protocol message with
 * exactly the four fields, and nothing that looks like a URL, an id or free text.
 */
let sharedCaptions = null;
export function assertSafeDiag(message, where) {
  sharedCaptions ??= loadCaptions();
  assert.deepEqual(Object.keys(message).sort(), ["event", "type", "v", "where"], JSON.stringify(message));
  assert.equal(message.v, 1);
  assert.equal(message.type, "diag");
  if (where) assert.equal(message.where, where);
  assert.ok(message.event.length > 0 && message.event.length <= 120, message.event);
  assert.deepEqual(sharedCaptions.validateMessage(message), message, `valid per validateMessage: ${message.event}`);
  assert.match(message.event, /^[a-z0-9][a-z0-9 =_.-]*$/, "lowercase code, numbers and booleans only");
  assert.equal(/[/:?&#]|https?|www|youtube\.|\.com/.test(message.event), false, `no URL: ${message.event}`);
  assert.equal(ID_TOKEN.test(scannedForIds(message.event)), false, `no id-like token: ${message.event}`);
}


/**
 * Injects the manifest's content scripts the way Chrome does, into one context per world, and returns the files
 * that really ran in each world. Chrome keeps one "already injected" set per document for the whole extension: a file
 * that appears in two content_scripts entries runs only for the first entry, in that entry's world, and never in the
 * other (found in Chrome 151 and 155: captions.js listed for both worlds never reached the isolated one).
 */
export function injectLikeChrome(manifest, worlds) {
  const injected = new Set();
  const ran = { MAIN: [], ISOLATED: [] };
  for (const entry of manifest.content_scripts) {
    const world = entry.world === "MAIN" ? "MAIN" : "ISOLATED";
    for (const file of entry.js) {
      if (injected.has(file)) continue;
      injected.add(file);
      if (worlds) runScripts(worlds[world], [file]);
      ran[world].push(file);
    }
  }
  return ran;
}
