#!/usr/bin/env node

import { readFileSync, writeFileSync } from "node:fs";

const file = process.argv[2];
if (!file) {
  console.error("Usage: remove-content-scriptlet-registry.mjs <content-source.js>");
  process.exit(2);
}

const source = readFileSync(file, "utf8");
const startMarker = "  function AmazonApstag(source, args) {";
const mapMarker = "  var scriptletsMap = {";
const getterMarker = "  var getScriptletFunction = function getScriptletFunction(name) {\n    return scriptletsMap[name];\n  };";
const registryEnd = "  var scriptlets = {\n    invoke: getScriptletCode$1,\n    getScriptletFunction: getScriptletFunction\n  };";

const count = marker => source.split(marker).length - 1;
const fail = message => {
  console.error(`[error] ${message}: ${file}`);
  process.exit(1);
};

const markerCounts = [startMarker, mapMarker, getterMarker, registryEnd].map(count);
if (markerCounts.every(value => value === 0)) {
  if (!source.includes("class ContentScript") || source.includes("scriptletsMap") || source.includes("getScriptletFunction")) {
    fail("content source is neither an intact nor a safely stripped bundle");
  }
  console.log(`[ok] generated scriptlet registry already absent from ${file}`);
  process.exit(0);
}
if (count(startMarker) !== 1) {
  fail(`expected exactly one registry start marker, found ${count(startMarker)}`);
}
if (count(mapMarker) !== 1) {
  fail(`expected exactly one scriptlet map, found ${count(mapMarker)}`);
}
if (count(getterMarker) !== 1) {
  fail("expected the known scriptlet getter shape exactly once");
}
if (count(registryEnd) !== 1) {
  fail("expected the known scriptlet registry export shape exactly once");
}

const start = source.indexOf(startMarker);
const map = source.indexOf(mapMarker);
const getter = source.indexOf(getterMarker);
const end = source.indexOf(registryEnd) + registryEnd.length;
if (start >= map || map >= getter || getter >= end) {
  fail("scriptlet registry boundaries are not in the expected order");
}

const stripped = source.slice(0, start) + source.slice(end);
if (stripped.includes("scriptletsMap") || stripped.includes("getScriptletFunction")) {
  fail("registry symbols remain outside the removed registry boundaries");
}
if (!stripped.includes("class ContentScript")) {
  fail("content script boundary was not preserved");
}

writeFileSync(file, stripped);
console.log(`[ok] removed generated scriptlet registry from ${file}`);
