// Node 24 treats a directory argument of `node --test` as a single module to run. This loader
// makes `node --test tests/` work by importing every *.test.mjs file next to it; running
// `node --test tests/*.test.mjs` directly works as well.
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { pathToFileURL } = require("node:url");

(async () => {
  const files = fs
    .readdirSync(__dirname)
    .filter((name) => name.endsWith(".test.mjs"))
    .sort();
  for (const file of files) await import(pathToFileURL(path.join(__dirname, file)).href);
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
