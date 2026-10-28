// Writes one self-contained file per uBO scriptlet (resources/resources.json)
// into OUT_DIR, for wBlock Scripts to inject with
// `scripting.executeScript({ files, world: 'MAIN' })`, which page CSP does not
// block. Each file runs every call queued for it under
// `globalThis.__wbeScriptletCalls[name]` (set by background.js just before)
// and removes the queue.
//
//   node build-scriptlets.mjs OUT_DIR
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const out = process.argv[2];
if (!out) {
  console.error('usage: node build-scriptlets.mjs OUT_DIR');
  process.exit(2);
}
const resources = JSON.parse(readFileSync(path.join(here, '../resources/resources.json'), 'utf8'));
const byName = new Map(resources.map(r => [r.name, r]));
const source = r => (/^[A-Za-z0-9+/=\s]+$/.test(r.content) ? Buffer.from(r.content, 'base64').toString('utf8') : r.content);

// Dependencies first, each once.
function withDependencies(name, seen = new Set(), parts = []) {
  if (seen.has(name)) return parts;
  seen.add(name);
  const resource = byName.get(name);
  if (!resource) throw new Error(`missing resource ${name}`);
  for (const dependency of resource.dependencies ?? []) withDependencies(dependency, seen, parts);
  parts.push(source(resource));
  return parts;
}

rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });
let count = 0;
for (const resource of resources) {
  // Scriptlets are `name.js` functions; redirect stand-ins have no function.
  if (!resource.name.endsWith('.js')) continue;
  const fn = /^\s*function\s+([A-Za-z_$][\w$]*)\s*\(/.exec(source(resource));
  if (!fn) continue;
  const name = resource.name.slice(0, -'.js'.length);
  const body = withDependencies(resource.name).join('\n');
  const file = `(function () {
const queue = globalThis.__wbeScriptletCalls;
const calls = queue && queue[${JSON.stringify(name)}];
if (!calls) return;
delete queue[${JSON.stringify(name)}];
${body}
for (const args of calls) {
try { ${fn[1]}(...args); } catch (_) {}
}
})();
`;
  writeFileSync(path.join(out, `${name}.js`), file);
  count++;
}
console.log(`wrote ${count} scriptlets to ${out}`);
