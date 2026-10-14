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

/** Lets pending promise callbacks run. */
export async function flush(times = 8) {
  for (let i = 0; i < times; i++) await new Promise((resolve) => setImmediate(resolve));
}
