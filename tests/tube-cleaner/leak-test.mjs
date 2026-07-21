// Leak test for Tube Cleaner: verifies per-video resources (document/window
// listeners, MutationObservers, setInterval timers) do NOT accumulate when the
// player recreates its <video> element, as happens during YouTube SPA navigation.
//
// It instruments document.addEventListener/removeEventListener and
// window.setInterval/clearInterval BEFORE the userscript loads, transforms the
// player, snapshots the active-listener/interval counts, then swaps the <video>
// element several times (triggering the script's re-patch path) and asserts the
// counts stay flat. On the original pre-fix code each swap leaked a
// visibilitychange listener and toolbar/guard intervals, so this fails there
// and passes now (the guard is now observer-only).
//
// Usage: node leak-test.mjs

import { webkit } from 'playwright';
import { readFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SCRIPT_PATH = join(__dirname, '..', '..', 'wBlockCoreService', 'BundledUserscripts', 'tube-cleaner.user.js');
const FIXTURE_URL = pathToFileURL(join(__dirname, 'fixture.html')).href;
const userscript = readFileSync(SCRIPT_PATH, 'utf8');

// Runs before the userscript; counts active listeners/intervals.
const counterPatch = `
(function () {
  var c = { visAdd: 0, visRemove: 0, intervalActive: 0 };
  var dAdd = document.addEventListener.bind(document);
  var dRem = document.removeEventListener.bind(document);
  document.addEventListener = function (t, fn, o) { if (t === 'visibilitychange') c.visAdd++; return dAdd(t, fn, o); };
  document.removeEventListener = function (t, fn, o) { if (t === 'visibilitychange') c.visRemove++; return dRem(t, fn, o); };
  var setI = window.setInterval.bind(window);
  var clrI = window.clearInterval.bind(window);
  window.setInterval = function (fn, ms) { c.intervalActive++; return setI(fn, ms); };
  window.clearInterval = function (id) { c.intervalActive--; return clrI(id); };
  window.__leakCounters = c;
})();
`;

const SWAPS = 6;
const browser = await webkit.launch();
const page = await (await browser.newContext({ viewport: { width: 1280, height: 800 } })).newPage();

await page.addInitScript(counterPatch); // must precede the userscript
await page.addInitScript(userscript);
await page.goto(FIXTURE_URL, { waitUntil: 'domcontentloaded' });
await page.waitForSelector('.wblock-tc-toolbar', { timeout: 10000 });
await page.waitForTimeout(1500); // let initial setup + guards settle

const baseline = await page.evaluate(() => ({ ...window.__leakCounters }));
const activeVisBaseline = baseline.visAdd - baseline.visRemove;

for (let i = 0; i < SWAPS; i++) {
  await page.evaluate(() => {
    const container = document.querySelector('#movie_player .html5-video-container');
    const old = container.querySelector('video');
    const nv = document.createElement('video');
    container.replaceChild(nv, old);
  });
  await page.waitForTimeout(400); // let the MutationObserver re-activate
}

await page.waitForTimeout(500);
const after = await page.evaluate(() => ({ ...window.__leakCounters }));
const activeVisAfter = after.visAdd - after.visRemove;

const results = [];
function record(name, pass, detail) {
  results.push({ name, pass, detail });
  console.log(`  [${pass ? 'PASS' : 'FAIL'}] ${name} — ${detail}`);
}

console.log(`\n=== Leak test (${SWAPS} video-element swaps) ===`);
console.log(`  baseline: active visibilitychange=${activeVisBaseline}, active intervals=${baseline.intervalActive}`);
console.log(`  after:    active visibilitychange=${activeVisAfter}, active intervals=${after.intervalActive}`);

record('document visibilitychange listeners do not accumulate',
  activeVisAfter === activeVisBaseline,
  `baseline=${activeVisBaseline} after=${activeVisAfter} (delta ${activeVisAfter - activeVisBaseline})`);

// Each swap should net ~0 intervals: toolbar/quality timers are cleared before
// replacements create their own. Allow a small slack for timing.
const intervalDelta = after.intervalActive - baseline.intervalActive;
record('setInterval count stays bounded across swaps',
  intervalDelta <= 1,
  `baseline=${baseline.intervalActive} after=${after.intervalActive} (delta ${intervalDelta})`);

// Sanity: the re-patch path actually ran (toolbar still present, controls on).
const sane = await page.evaluate(() => {
  const v = document.querySelector('#movie_player video');
  return { toolbar: !!document.querySelector('.wblock-tc-toolbar'), controls: !!(v && v.controls) };
});
record('player still transformed after swaps', sane.toolbar && sane.controls,
  `toolbar=${sane.toolbar} controls=${sane.controls}`);

await browser.close();

const failed = results.filter(r => !r.pass).length;
console.log(`\n  TOTAL: ${results.length - failed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
