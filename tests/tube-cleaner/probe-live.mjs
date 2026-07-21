// Live-site diagnostic probe for Player Cleaner.
//
// Loads real pages in Playwright WebKit, injects the REAL bundled userscript
// at document-start in the page world (matching `@inject-into page`) with
// `__wblockPlayerCleanerDebug` enabled, captures the script's console output,
// and reports the resulting <video> DOM state so we can see whether the player
// was replaced, enhanced in place, or left untouched — and why.
//
// Usage: node probe-live.mjs [url ...]   (defaults to a couple of known sites)

import { webkit } from 'playwright';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PLAYER_SCRIPT_PATH = join(__dirname, '..', '..', 'wBlockCoreService', 'BundledUserscripts', 'player-cleaner.user.js');
const playerUserscript = readFileSync(PLAYER_SCRIPT_PATH, 'utf8');

const DEFAULT_URLS = [
  'https://videojs.org/',
  'https://archive.org/details/gov.ntis.ava15996vnb1',
  'https://test-videos.co.uk/',
];

const urls = process.argv.slice(2).filter(a => /^[a-z]+:\/\//i.test(a));
const targets = urls.length ? urls : DEFAULT_URLS;

async function probe(url) {
  console.log(`\n==================== ${url} ====================`);
  const browser = await webkit.launch();
  const ctx = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15',
  });

  const wbLogs = [];
  // Enable debug + inject the real userscript before page scripts run.
  await ctx.addInitScript(`window.__wblockPlayerCleanerDebug = true;\n${playerUserscript}`);

  const page = await ctx.newPage();
  page.on('console', msg => {
    const text = msg.text();
    if (text.includes('wBlock') || text.includes('Player Cleaner')) wbLogs.push(`[${msg.type()}] ${text}`);
  });

  try {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
  } catch (e) {
    console.log('  navigation error:', e.message);
  }
  // Give the player + the script's poll loop time to settle.
  await page.waitForTimeout(9000);

  const state = await page.evaluate(() => {
    const vids = Array.from(document.querySelectorAll('video')).map(v => ({
      srcAttr: v.getAttribute('src'),
      currentSrc: v.currentSrc || null,
      protocol: (v.currentSrc || v.getAttribute('src') || '').split(':')[0] || '(none)',
      controls: v.controls,
      autoplay: v.autoplay,
      muted: v.muted,
      loop: v.loop,
      paused: v.paused,
      readyState: v.readyState,
      w: v.offsetWidth,
      h: v.offsetHeight,
      done: v.getAttribute('data-wblock-player-cleaner'),
      parentClass: v.parentElement ? v.parentElement.className : null,
      ancestors: (function () {
        var out = []; var el = v.parentElement;
        for (var i = 0; el && i < 5; i++) { out.push((el.tagName.toLowerCase()) + (el.className && typeof el.className === 'string' ? '.' + el.className.trim().split(/\s+/).slice(0, 2).join('.') : '')); el = el.parentElement; }
        return out;
      })(),
      isClean: !!(v.closest && v.closest('[data-wblock-player-cleaner]')),
    }));
    const doneContainers = Array.from(document.querySelectorAll('[data-wblock-player-cleaner]')).length;
    return {
      videoCount: vids.length,
      vids,
      doneContainers,
      hasVideojs: typeof window.videojs !== 'undefined',
      hasJwplayer: typeof window.jwplayer !== 'undefined',
    };
  }).catch(e => ({ error: e.message }));

  console.log('  --- [wBlock] console output ---');
  if (wbLogs.length) wbLogs.forEach(l => console.log('  ' + l));
  else console.log('  (none — script produced no logs)');

  console.log('  --- DOM state ---');
  console.log('  ' + JSON.stringify(state, null, 2).split('\n').join('\n  '));

  await browser.close();
}

for (const url of targets) {
  await probe(url);
}
