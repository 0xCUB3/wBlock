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

let stripped = source.slice(0, start) + source.slice(end);
if (stripped.includes("scriptletsMap") || stripped.includes("getScriptletFunction")) {
  fail("registry symbols remain outside the removed registry boundaries");
}
if (!stripped.includes("class ContentScript")) {
  fail("content script boundary was not preserved");
}

const replaceExactly = (input, oldText, newText, label) => {
  const occurrences = input.split(oldText).length - 1;
  if (occurrences !== 1) {
    fail(`expected exactly one ${label}, found ${occurrences}`);
  }
  return input.replace(oldText, newText);
};

// The content fallback receives precompiled source from wBlock's background
// script, so remove upstream's remaining registry call site as well.
stripped = replaceExactly(
  stripped,
  "  /**\n   * Name of the engine used to run scriptlets.\n   */\n  const SCRIPTLET_ENGINE_NAME = 'safari-extension';\n",
  "",
  "scriptlet engine constant",
);
stripped = replaceExactly(
  stripped,
  "  /**\n   * Converts scriptlet to the code that can be executed.\n   *\n   * @param {Scriptlet} scriptlet Scriptlet data (name and arguments)\n   * @param {boolean} verbose Whether to log verbose output\n   * @returns {string} Scriptlet code\n   */\n  const getScriptletCode = (scriptlet, verbose) => {\n    try {\n      const scriptletSource = {\n        engine: SCRIPTLET_ENGINE_NAME,\n        name: scriptlet.name,\n        args: scriptlet.args,\n        version: version,\n        verbose\n      };\n      return scriptlets.invoke(scriptletSource);\n    } catch (e) {\n      log$1.error('Failed to get scriptlet code', scriptlet.name, e);\n    }\n    return '';\n  };",
  "  /**\n   * Runs precompiled scriptlet source supplied by the background script.\n   *\n   * Compilation stays in the background because this content runtime does not\n   * carry the generated scriptlet registry.\n   */",
  "content scriptlet compiler",
);
stripped = replaceExactly(
  stripped,
  "    runScriptlets(scriptlets, verbose) {\n      if (!scriptlets || !scriptlets.length) {\n        return;\n      }\n      const getCode = scriptlet => getScriptletCode(scriptlet, verbose);\n      const scripts = scriptlets.map(getCode);\n      executeScripts(scripts);\n    }",
  "    runScriptlets(scriptlets) {\n      if (!scriptlets || !scriptlets.length) {\n        return;\n      }\n      for (const scriptlet of scriptlets) {\n        if (!scriptlet || typeof scriptlet.code !== 'string' || !scriptlet.code) {\n          log$1.error('Missing precompiled scriptlet source', scriptlet && scriptlet.name);\n          continue;\n        }\n        executeScripts([scriptlet.code]);\n      }\n    }",
  "content runScriptlets implementation",
);

// Preserve wBlock's stable one-line native log formatting and its injection
// fallback behavior while refreshing the upstream SafariExtension section.
stripped = replaceExactly(
  stripped,
  "  const getTimestamp = () => `[${new Date().toISOString()}]`;\n",
  "  const getTimestamp = () => `[${new Date().toISOString()}]`;\n  const formatLogValue = value => {\n    if (value instanceof Error) {\n      return value.stack || value.message || String(value);\n    }\n    if (typeof value === 'string') {\n      return value;\n    }\n    try {\n      return JSON.stringify(value);\n    } catch (_error) {\n      return String(value);\n    }\n  };\n  const formatLogLine = (prefix, args) => [getTimestamp(), prefix, ...args.map(formatLogValue)].join(' ');\n",
  "logger timestamp helper",
);
for (const level of ["debug", "info", "error"]) {
  stripped = replaceExactly(
    stripped,
    `        console.${level}(getTimestamp(), this.prefix, ...args);`,
    `        console.${level}(formatLogLine(this.prefix, args));`,
    `${level} logger call`,
  );
}
stripped = replaceExactly(
  stripped,
  "    scripts.push(';document.currentScript.remove();');",
  "    scripts.push(';document.currentScript && document.currentScript.remove();');",
  "currentScript cleanup",
);
stripped = replaceExactly(
  stripped,
  "        log$1.error('Failed to execute scripts');",
  "        console.warn('[wBlock] Page script injection was blocked; continuing without page-context scripts.');",
  "page injection fallback log",
);

// wBlock deliberately avoids delaying or synthesizing page lifecycle events.
const lifecycleStart = "  /**\n   * @file Handles delaying and dispatching of DOMContentLoaded and load events.\n   */";
const messageStart = "  /**\n   * @file Defines message interface.\n   */";
if (stripped.split(lifecycleStart).length - 1 !== 1 || stripped.split(messageStart).length - 1 !== 1) {
  fail("expected one lifecycle dispatcher and one message interface boundary");
}
const lifecycleStartIndex = stripped.indexOf(lifecycleStart);
const messageStartIndex = stripped.indexOf(messageStart);
if (lifecycleStartIndex >= messageStartIndex) {
  fail("lifecycle dispatcher boundaries are not in the expected order");
}
stripped = stripped.slice(0, lifecycleStartIndex) + stripped.slice(messageStartIndex);

if (stripped.includes("scriptlets.invoke") || stripped.includes("setupDelayedEventDispatcher")) {
  fail("content-only scriptlet or lifecycle runtime remains after stripping");
}

writeFileSync(file, stripped);
console.log(`[ok] removed generated scriptlet registry and patched content fallback in ${file}`);
