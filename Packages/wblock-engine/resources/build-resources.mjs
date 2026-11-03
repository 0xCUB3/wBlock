// Builds resources.json: brave/adblock-resources redirect resources plus the
// uBlock Origin scriptlets, in the adblock-rust Resource format.
// Usage: node build-resources.mjs BRAVE_DIST_RESOURCES_JSON UBO_SCRIPTLETS_JS > resources.json
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const [braveFile, scriptletsFile] = process.argv.slice(2);
const { builtinScriptlets } = await import(pathToFileURL(scriptletsFile).href);

const GLOBALS = 'wbe-scriptlet-globals.fn';
const b64 = (text) => Buffer.from(text, 'utf8').toString('base64');
const js = (name, aliases, content, dependencies) => ({
  name,
  aliases,
  kind: { mime: 'application/javascript' },
  content: b64(content),
  dependencies,
});

// uBO's framework defines scriptletGlobals per injected script. Safe-self and
// a few helpers read it, so it is an explicit dependency of every scriptlet.
const out = JSON.parse(readFileSync(braveFile, 'utf8'));
out.push(js(GLOBALS, [], 'var scriptletGlobals = {};', []));
for (const d of builtinScriptlets) {
  out.push(js(d.name, d.aliases ?? [], d.fn.toString(), [...(d.dependencies ?? []), GLOBALS]));
}
process.stdout.write(JSON.stringify(out) + '\n');
