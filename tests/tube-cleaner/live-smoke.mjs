// BEST-EFFORT real-world smoke test for Tube Cleaner against live YouTube.
//
// Unlike run-tests.mjs (deterministic, offline, gates CI), this loads an actual
// YouTube watch page in Playwright WebKit with the real userscript injected and
// reports whether the player transformation happens in the wild. It depends on
// the network and YouTube's current anti-bot/consent behavior, so it NEVER fails
// the build — it prints a verdict for a human/agent to read.
//
// Usage: node live-smoke.mjs [videoId]   (default: dQw4w9WgXcQ)

import { webkit } from 'playwright';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SCRIPT_PATH = join(__dirname, '..', '..', 'wBlockCoreService', 'BundledUserscripts', 'tube-cleaner.user.js');
const userscript = readFileSync(SCRIPT_PATH, 'utf8');
const videoId = process.argv[2] || 'dQw4w9WgXcQ';
const url = `https://www.youtube.com/watch?v=${videoId}`;

console.log(`[live-smoke] loading ${url} in WebKit (best-effort)…`);

const browser = await webkit.launch({ headless: true });
const context = await browser.newContext({
  userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15',
  viewport: { width: 1280, height: 800 },
  locale: 'en-US',
});
// Bypass the EU consent interstitial.
await context.addCookies([
  { name: 'CONSENT', value: 'YES+cb.20210328-17-p0.en+FX+417', domain: '.youtube.com', path: '/' },
  { name: 'SOCS', value: 'CAI', domain: '.youtube.com', path: '/' },
]);

const page = await context.newPage();
await page.addInitScript(userscript);

const pageErrors = [];
page.on('pageerror', e => pageErrors.push(e.message));

try {
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
} catch (e) {
  console.log(`[live-smoke] navigation problem: ${e.message}`);
}

// Give the SPA + userscript time to mount and transform the player.
let verdict = 'no transformation observed';
for (let i = 0; i < 40; i++) {
  await page.waitForTimeout(500);
  const state = await page.evaluate(() => {
    const player = document.getElementById('movie_player');
    const video = player && player.querySelector('video');
    return {
      hasPlayer: !!player,
      hasVideo: !!video,
      native: !!(player && player.classList.contains('wblock-tc-native')),
      toolbar: !!document.querySelector('.wblock-tc-toolbar'),
      controls: video ? video.controls : null,
      title: document.title,
    };
  }).catch(() => null);

  if (state && state.native && state.toolbar) {
    verdict = 'TRANSFORMED ✓ (native class + toolbar present)';
    console.log('[live-smoke] state:', JSON.stringify(state));
    break;
  }
  if (i === 39) {
    console.log('[live-smoke] final state:', JSON.stringify(state));
  }
}

console.log('\n[live-smoke] VERDICT:', verdict);
if (pageErrors.length) {
  console.log('[live-smoke] page errors:', pageErrors.slice(0, 5).join(' | '));
}
console.log('[live-smoke] note: best-effort only. YouTube may serve a consent wall,');
console.log('  a login prompt, or an anti-bot page to headless WebKit; a non-transform');
console.log('  result here is NOT proof the userscript is broken — use run-tests.mjs');
console.log('  for the deterministic gate.');

await browser.close();
