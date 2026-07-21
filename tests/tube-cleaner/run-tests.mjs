// Autonomous WebKit (Safari-engine) test harness for the Tube Cleaner and
// Player Cleaner userscripts.
//
// It loads synthetic pages in Playwright WebKit, injects the REAL bundled
// userscript at document-start in the page world (matching `@run-at` +
// `@inject-into page`), and asserts the player transformation actually happens.
// Scenarios:
//   1. desktop  – Tube Cleaner, macOS Safari-like
//   2. iPhone   – Tube Cleaner, mobile Safari (touch, mobile UA)
//   3. iPad desktop-site – Tube Cleaner, iPadOS requesting www.youtube.com
//   4. Player Cleaner – opaque (blob) source, enhance-in-place + controls guard
//   5. Player Cleaner – clean source, full replacement path (poster/tracks copy)
//   6. Player Cleaner – source discovery across video.js/JW/Plyr/data-attr
//
// Exit code is non-zero if any assertion fails, so this can gate CI.
// Usage: node run-tests.mjs [--filter substring]

import { webkit, devices } from 'playwright';
import { readFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SCRIPT_PATH = join(__dirname, '..', '..', 'wBlockCoreService', 'BundledUserscripts', 'tube-cleaner.user.js');
const PLAYER_SCRIPT_PATH = join(__dirname, '..', '..', 'wBlockCoreService', 'BundledUserscripts', 'player-cleaner.user.js');
const INJECTOR_PATH = join(__dirname, '..', '..', 'wBlock Scripts (iOS)', 'Resources', 'userscript-injector.js');
const FIXTURE_URL = pathToFileURL(join(__dirname, 'fixture.html')).href;
const FIXTURE_NOPI_URL = pathToFileURL(join(__dirname, 'fixture-noplaysinline.html')).href;
const FIXTURE_PLAYER_URL = pathToFileURL(join(__dirname, 'fixture-player-cleaner.html')).href;
const FIXTURE_PLAYER_REPLACE_URL = pathToFileURL(join(__dirname, 'fixture-player-cleaner-replace.html')).href;
const FIXTURE_PLAYER_DISCOVERY_URL = pathToFileURL(join(__dirname, 'fixture-player-cleaner-discovery.html')).href;
const FIXTURE_PLAYER_BARE_URL = pathToFileURL(join(__dirname, 'fixture-player-cleaner-bare.html')).href;
const FIXTURE_PLAYER_RELATIVE_URL = pathToFileURL(join(__dirname, 'fixture-player-cleaner-relative.html')).href;
const FIXTURE_PLAYER_UPGRADE_URL = pathToFileURL(join(__dirname, 'fixture-player-cleaner-upgrade.html')).href;
const FIXTURE_PLAYER_EARLY_URL = pathToFileURL(join(__dirname, 'fixture-player-cleaner-early.html')).href;

const userscript = readFileSync(SCRIPT_PATH, 'utf8');
const playerUserscript = readFileSync(PLAYER_SCRIPT_PATH, 'utf8');
const injectorSource = readFileSync(INJECTOR_PATH, 'utf8');
const filter = (process.argv.find(a => a.startsWith('--filter=')) || '').split('=')[1] || '';

const results = [];
function record(scenario, name, pass, detail = '') {
  results.push({ scenario, name, pass, detail });
  const mark = pass ? 'PASS' : 'FAIL';
  console.log(`  [${mark}] ${name}${detail ? ' — ' + detail : ''}`);
}

// Run an in-page check that returns {pass, detail}. Retries until pass or timeout
// because the userscript transforms the player asynchronously (250ms poll loop).
async function check(page, scenario, name, fn, { timeout = 6000, interval = 150, arg } = {}) {
  const start = Date.now();
  let last = { pass: false, detail: 'timeout' };
  while (Date.now() - start < timeout) {
    try {
      last = await page.evaluate(fn, arg);
      if (last && last.pass) break;
    } catch (e) {
      last = { pass: false, detail: 'eval error: ' + e.message };
    }
    await page.waitForTimeout(interval);
  }
  record(scenario, name, !!(last && last.pass), (last && last.detail) || '');
}

async function waitForTransform(page) {
  // The toolbar is appended last in transformPlayer(); its presence means the
  // transformation ran.
  await page.waitForSelector('.wblock-tc-toolbar', { timeout: 10000 }).catch(() => {});
}

async function runScenario(name, { device, fixture, ua, hasTouch, viewport, scriptSource, readySignal }) {
  console.log(`\n=== Scenario: ${name} ===`);
  const browser = await webkit.launch();
  const ctxOpts = {};
  if (device) Object.assign(ctxOpts, device);
  if (ua) ctxOpts.userAgent = ua;
  if (hasTouch) ctxOpts.hasTouch = true;
  if (viewport) ctxOpts.viewport = viewport;
  const context = await browser.newContext(ctxOpts);
  const page = await context.newPage();

  // Inject the real userscript at document-start in the page world.
  await page.addInitScript(scriptSource || userscript);

  const pageErrors = [];
  page.on('pageerror', e => pageErrors.push(e.message));

  await page.goto(fixture, { waitUntil: 'domcontentloaded' });
  if (readySignal) await page.waitForSelector(readySignal, { timeout: 10000 }).catch(() => {});
  else await waitForTransform(page);

  return { browser, context, page, pageErrors };
}

async function commonChecks(page, scenario) {
  await check(page, scenario, 'injects its stylesheet (#wblock-tc-style)', () => ({
    pass: !!document.getElementById('wblock-tc-style'),
  }));

  await check(page, scenario, 'marks player native (.wblock-tc-native)', () => {
    const p = document.getElementById('movie_player');
    return { pass: !!(p && p.classList.contains('wblock-tc-native')) };
  });

  await check(page, scenario, 'sets data-wblock-tc-cleaned', () => {
    const p = document.getElementById('movie_player');
    return { pass: !!(p && p.hasAttribute('data-wblock-tc-cleaned')) };
  });

  await check(page, scenario, 'forces video.controls === true', () => {
    const v = document.querySelector('#movie_player video');
    return { pass: !!(v && v.controls === true), detail: v ? `controls=${v.controls}` : 'no video' };
  });

  await check(page, scenario, 'builds toolbar with quality+audio buttons', () => {
    const tb = document.querySelector('.wblock-tc-toolbar');
    const btns = tb ? tb.querySelectorAll('button').length : 0;
    return { pass: btns >= 2, detail: `${btns} buttons` };
  });

  await check(page, scenario, 'overrides document.hidden (background playback)', () => {
    const desc = Object.getOwnPropertyDescriptor(document, 'hidden');
    return { pass: !!(desc && typeof desc.get === 'function' && document.hidden === false),
      detail: `hidden=${document.hidden}, overridden=${!!(desc && desc.get)}` };
  });

  await check(page, scenario, 'hooks auto-PiP on the video', () => {
    const v = document.querySelector('#movie_player video');
    return { pass: !!(v && v._wblockAutoPiPHooked === true) };
  });

  await check(page, scenario, 'exposes debug quality API', () => {
    const d = window.__wblockTubeDebug;
    if (!d) return { pass: false, detail: 'no __wblockTubeDebug' };
    const levels = d.getAvailableQualities();
    return { pass: Array.isArray(levels) && levels.includes('hd1080'), detail: `levels=${levels.join(',')}` };
  });
}

// The fixture's mock player fights controls off at 800ms, 2500ms and every 3s.
// A correct implementation must keep native controls ON despite that.
async function controlsSurvivalCheck(page, scenario) {
  await page.waitForTimeout(4200); // let several fightControls rounds run
  await check(page, scenario, 'native controls SURVIVE YouTube turning them off', () => {
    const v = document.querySelector('#movie_player video');
    if (!v) return { pass: false, detail: 'no video' };
    const hasAttr = v.hasAttribute('controls');
    return {
      pass: hasAttr,
      detail: `hasAttribute('controls')=${hasAttr} (JS getter reports controls=${v.controls})`,
    };
  }, { timeout: 1500, interval: 500 });
}

async function audioToggleCheck(page, scenario) {
  await check(page, scenario, 'audio-only toggle injects audio style', async () => {
    const btns = [...document.querySelectorAll('.wblock-tc-toolbar button')];
    const audioBtn = btns.find(b => /audio|video/i.test(b.textContent));
    if (!audioBtn) return { pass: false, detail: 'no audio button' };
    audioBtn.click();
    await new Promise(r => setTimeout(r, 50));
    const on = !!document.getElementById('wblock-tc-style-audio');
    return { pass: on, detail: on ? 'audio style present' : 'audio style missing' };
  });
}

// ---- Scenario 1: desktop -------------------------------------------------
{
  const { browser, page, pageErrors } = await runScenario('desktop (macOS Safari-like)', {
    fixture: FIXTURE_URL,
    viewport: { width: 1280, height: 800 },
  });
  await commonChecks(page, 'desktop');
  await controlsSurvivalCheck(page, 'desktop');
  await audioToggleCheck(page, 'desktop');
  record('desktop', 'no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));
  await browser.close();
}

// ---- Scenario 2: iPhone (mobile Safari) ----------------------------------
{
  const iphone = devices['iPhone 13'];
  const { browser, page, pageErrors } = await runScenario('iPhone (mobile Safari)', {
    device: iphone,
    fixture: FIXTURE_URL,
    hasTouch: true,
  });
  await commonChecks(page, 'iPhone');
  // iOS-specific: toolbar should use larger touch targets (font-size 14px).
  await check(page, 'iPhone', 'iOS toolbar uses enlarged touch targets', () => {
    const tb = document.querySelector('.wblock-tc-toolbar');
    if (!tb) return { pass: false, detail: 'no toolbar' };
    const fs = parseFloat((tb.querySelector('button') || tb).style.fontSize || '0');
    return { pass: fs >= 14, detail: `button font-size=${fs}px` };
  });
  record('iPhone', 'no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));
  await browser.close();
}

// ---- Scenario 3: iPad requesting desktop site (no playsinline) -----------
// iPadOS defaults to the desktop UA, so YouTube serves the desktop player whose
// <video> may lack `playsinline`. Without playsinline iOS jumps to fullscreen
// instead of inline playback. Tube Cleaner reuses that video element, so it must
// ensure playsinline itself.
{
  const ipad = devices['iPad Pro 11'];
  const { browser, page, pageErrors } = await runScenario('iPad desktop-site (no playsinline)', {
    device: ipad,
    fixture: FIXTURE_NOPI_URL,
    hasTouch: true,
  });
  await commonChecks(page, 'iPad-desktop');
  await check(page, 'iPad-desktop', 'ensures playsinline for inline iOS playback', () => {
    const v = document.querySelector('#movie_player video');
    if (!v) return { pass: false, detail: 'no video' };
    const ok = v.hasAttribute('playsinline') || v.playsInline === true;
    return { pass: ok, detail: `playsInline=${v.playsInline}, attr=${v.hasAttribute('playsinline')}` };
  });
  record('iPad-desktop', 'no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));
  await browser.close();
}

// ---- Scenario 4: Player Cleaner on a custom (video.js) player ------------
// Verifies the ported controls guard: Player Cleaner enhances the existing
// <video> in place (opaque blob source) and must keep native controls on even
// though the custom player keeps stripping them.
{
  const { browser, page, pageErrors } = await runScenario('Player Cleaner (custom video.js player)', {
    fixture: FIXTURE_PLAYER_URL,
    scriptSource: playerUserscript,
    readySignal: '[data-wblock-player-cleaner]',
    viewport: { width: 1280, height: 800 },
  });

  await check(page, 'player-cleaner', 'forces video.controls === true', () => {
    const v = document.querySelector('.video-js video');
    return { pass: !!(v && v.controls === true), detail: v ? `controls=${v.controls}` : 'no video' };
  });

  await check(page, 'player-cleaner', 'sets playsinline', () => {
    const v = document.querySelector('.video-js video');
    return { pass: !!(v && (v.playsInline || v.hasAttribute('playsinline'))) };
  });

  await check(page, 'player-cleaner', 'hides custom control overlay', () => {
    const bar = document.querySelector('.vjs-control-bar');
    return { pass: !!(bar && bar.style.display === 'none'), detail: bar ? `display=${bar.style.display}` : 'no bar' };
  });

  await page.waitForTimeout(4200); // let several fightControls rounds run
  await check(page, 'player-cleaner', 'native controls SURVIVE player turning them off', () => {
    const v = document.querySelector('.video-js video');
    if (!v) return { pass: false, detail: 'no video' };
    const hasAttr = v.hasAttribute('controls');
    return { pass: hasAttr, detail: `hasAttribute('controls')=${hasAttr} (getter=${v.controls})` };
  }, { timeout: 1500, interval: 500 });

  record('player-cleaner', 'no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));
  await browser.close();
}

// ---- Scenario 5: Player Cleaner clean-source replacement path ------------
// When the underlying media source is a clean http(s) URL, Player Cleaner keeps
// the original media element (and therefore its buffered state/poster/tracks),
// drops the custom chrome, and defends native controls.
{
  const { browser, page, pageErrors } = await runScenario('Player Cleaner (clean source replacement)', {
    fixture: FIXTURE_PLAYER_REPLACE_URL,
    scriptSource: playerUserscript,
    readySignal: '[data-wblock-player-cleaner]',
    viewport: { width: 1280, height: 800 },
  });
  const S = 'player-cleaner-replace';

  await check(page, S, 'keeps a single original <video>', () => {
    const c = document.getElementById('player-replace');
    const videos = c ? c.querySelectorAll('video') : [];
    const retained = videos.length === 1 && videos[0].hasAttribute('data-test-original');
    return { pass: retained, detail: `${videos.length} video(s), retained=${retained}` };
  });

  await check(page, S, 'resolves and retains the clean source', () => {
    const v = document.querySelector('#player-replace video');
    const source = v && (v.currentSrc || v.getAttribute('src') ||
      (v.querySelector('source') && v.querySelector('source').src));
    const ok = source === 'https://example.com/media/movie.mp4';
    return { pass: ok, detail: v ? `src=${source || ''}` : 'no video' };
  });

  await check(page, S, 'forces video.controls === true', () => {
    const v = document.querySelector('#player-replace video');
    return { pass: !!(v && v.controls === true), detail: v ? `controls=${v.controls}` : 'no video' };
  });

  await check(page, S, 'sets playsinline', () => {
    const v = document.querySelector('#player-replace video');
    return { pass: !!(v && (v.playsInline || v.hasAttribute('playsinline'))) };
  });

  await check(page, S, 'retains the poster attribute', () => {
    const v = document.querySelector('#player-replace video');
    const p = v ? v.getAttribute('poster') : null;
    return { pass: p === 'https://example.com/poster.jpg', detail: `poster=${p}` };
  });

  await check(page, S, 'retains the caption <track>', () => {
    const v = document.querySelector('#player-replace video');
    const t = v ? v.querySelector('track') : null;
    return { pass: !!t, detail: t ? `track src=${t.getAttribute('src')}` : 'no track' };
  });

  await check(page, S, 'removes custom control chrome', () => {
    const c = document.getElementById('player-replace');
    const bar = c ? c.querySelector('.vjs-control-bar') : null;
    const big = c ? c.querySelector('.vjs-big-play-button') : null;
    return { pass: !bar && !big, detail: `bar=${!!bar}, bigPlay=${!!big}` };
  });

  await check(page, S, 'marks container done + drops video-js class', () => {
    const c = document.getElementById('player-replace');
    const done = !!(c && c.hasAttribute('data-wblock-player-cleaner'));
    const declassed = !!(c && !c.classList.contains('video-js'));
    return { pass: done && declassed, detail: `done=${done}, declassed=${declassed}` };
  });

  await check(page, S, 'overrides document.hidden (background playback)', () => {
    const desc = Object.getOwnPropertyDescriptor(document, 'hidden');
    return { pass: !!(desc && typeof desc.get === 'function' && document.hidden === false),
      detail: `hidden=${document.hidden}, overridden=${!!(desc && desc.get)}` };
  });

  await check(page, S, 'hooks auto-PiP on the clean video', () => {
    const v = document.querySelector('#player-replace video');
    return { pass: !!(v && v._wblockAutoPiPHooked === true) };
  });

  // Idempotency: recovery scans and the MutationObserver must never add a
  // second video.
  await page.waitForTimeout(2600);
  await check(page, S, 'stays a single video after rescans (idempotent)', () => {
    const c = document.getElementById('player-replace');
    const vids = c ? c.querySelectorAll('video').length : 0;
    return { pass: vids === 1, detail: `${vids} video(s) after rescans` };
  });

  await page.waitForTimeout(2000); // let several fightControls rounds run
  await check(page, S, 'native controls SURVIVE player turning them off', () => {
    const v = document.querySelector('#player-replace video');
    if (!v) return { pass: false, detail: 'no video' };
    const hasAttr = v.hasAttribute('controls');
    return { pass: hasAttr, detail: `hasAttribute('controls')=${hasAttr} (getter=${v.controls})` };
  }, { timeout: 1500, interval: 500 });

  record(S, 'no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));
  await browser.close();
}

// ---- Scenario 6: Player Cleaner source discovery -------------------------
// Five players, each exposing its media source through a different mechanism.
// Player Cleaner must resolve the right URL for every one and swap in a clean
// native <video> carrying that source.
{
  const { browser, page, pageErrors } = await runScenario('Player Cleaner (source discovery)', {
    fixture: FIXTURE_PLAYER_DISCOVERY_URL,
    scriptSource: playerUserscript,
    readySignal: '[data-wblock-player-cleaner]',
    viewport: { width: 1280, height: 800 },
  });
  const S = 'player-cleaner-discovery';

  const cases = [
    ['p-src', 'https://example.com/a.mp4', 'video.src'],
    ['p-source-child', 'https://example.com/b.mp4', '<source> child'],
    ['p-dom', 'https://example.com/c.mp4', 'descendant data-src'],
    ['p-videojs', 'https://example.com/d.mp4', 'video.js currentSource()'],
    ['p-jwplayer', 'https://example.com/e.mp4', 'JW Player playlist item'],
  ];
  for (const [id, expected, how] of cases) {
    await check(page, S, `resolves source via ${how}`, ({ id, expected }) => {
      const c = document.getElementById(id);
      const v = c ? c.querySelector('video') : null;
      const source = v && (v.currentSrc || v.getAttribute('src') ||
        (v.querySelector('source') && v.querySelector('source').src));
      const ok = source === expected;
      return { pass: ok, detail: v ? `src=${source || ''}` : 'no video' };
    }, { arg: { id, expected } });
  }

  await check(page, S, 'every player replaced with exactly one clean video', (cases) => {
    const bad = cases.filter(([id]) => {
      const c = document.getElementById(id);
      return !c || c.querySelectorAll('video').length !== 1;
    }).map(([id]) => id);
    return { pass: bad.length === 0, detail: bad.length ? `bad: ${bad.join(',')}` : '5/5 single-video' };
  }, { arg: cases });

  await check(page, S, 'all clean videos have native controls', (cases) => {
    const missing = cases.filter(([id]) => {
      const v = document.getElementById(id).querySelector('video');
      return !(v && v.controls === true && v.hasAttribute('controls'));
    }).map(([id]) => id);
    return { pass: missing.length === 0, detail: missing.length ? `missing: ${missing.join(',')}` : '5/5 controls' };
  }, { arg: cases });

  // Idempotency across the boot rescans + observer.
  await page.waitForTimeout(2600);
  await check(page, S, 'no duplicate videos after rescans (idempotent)', (cases) => {
    const bad = cases.filter(([id]) => {
      const c = document.getElementById(id);
      return !c || c.querySelectorAll('video').length !== 1;
    }).map(([id]) => id);
    return { pass: bad.length === 0, detail: bad.length ? `duplicated: ${bad.join(',')}` : '5/5 still single' };
  }, { arg: cases });

  record(S, 'no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));
  await browser.close();
}

{
  const { browser, page, pageErrors } = await runScenario('Player Cleaner (bare/custom players)', {
    fixture: FIXTURE_PLAYER_BARE_URL,
    scriptSource: playerUserscript,
    readySignal: '[data-wblock-player-cleaner]',
    viewport: { width: 1280, height: 800 },
  });
  const S = 'player-cleaner-bare';
  const ATTR = 'data-wblock-player-cleaner';

  // Case 1: modern wrapper not in the recognized library list, opaque source.
  await check(page, S, 'enhances bare video in unrecognized wrapper (controls on)', () => {
    const v = document.querySelector('#bare-enhance video');
    const ok = !!(v && v.controls === true && v.getAttribute('data-wblock-player-cleaner') === '1');
    return { pass: ok, detail: v ? `controls=${v.controls} attr=${v.getAttribute('data-wblock-player-cleaner')}` : 'no video' };
  });

  await check(page, S, 'marks the bare container done', () => {
    const c = document.getElementById('bare-enhance');
    const ok = !!(c && c.getAttribute('data-wblock-player-cleaner') === '1');
    return { pass: ok, detail: c ? `attr=${c.getAttribute('data-wblock-player-cleaner')}` : 'no container' };
  });

  await check(page, S, 'bare enhanced video keeps its (opaque) source', () => {
    const v = document.querySelector('#bare-enhance video');
    const ok = !!(v && (v.src || '').indexOf('blob:') === 0);
    return { pass: ok, detail: v ? `src=${v.src}` : 'no video' };
  });

  await check(page, S, 'bare enhanced controls SURVIVE player turning them off', () => {
    const v = document.querySelector('#bare-enhance video');
    const ok = !!(v && v.controls === true);
    return { pass: ok, detail: v ? `controls=${v.controls}` : 'no video' };
  });

  // Case 2: bare video with a clean source -> enhanced in place, source kept.
  await check(page, S, 'enhances bare clean-source video (controls on, src kept)', () => {
    const v = document.querySelector('#bare-clean video');
    const ok = !!(v && v.controls === true && v.getAttribute('data-wblock-player-cleaner') === '1' && v.src === 'https://example.com/media/movie.mp4');
    return { pass: ok, detail: v ? `controls=${v.controls} src=${v.src}` : 'no video' };
  });

  // Case 3: ambient (autoplay+muted+loop) must be untouched. Gated on the
  // positive case being processed so "untouched" proves the script ran & skipped.
  await check(page, S, 'leaves ambient autoplay-muted video untouched', () => {
    const ev = document.querySelector('#bare-enhance video');
    const ran = !!(ev && ev.getAttribute('data-wblock-player-cleaner') === '1');
    const v = document.querySelector('#bare-ambient video');
    const ok = !!(ran && v && v.controls === false && !v.hasAttribute('data-wblock-player-cleaner'));
    return { pass: ok, detail: `scriptRan=${ran} controls=${v && v.controls} attr=${v && v.getAttribute('data-wblock-player-cleaner')}` };
  });

  // Case 4: already-native video untouched (gated the same way).
  await check(page, S, 'leaves already-native video untouched', () => {
    const ev = document.querySelector('#bare-enhance video');
    const ran = !!(ev && ev.getAttribute('data-wblock-player-cleaner') === '1');
    const v = document.getElementById('bare-native');
    const ok = !!(ran && v && v.controls === true && !v.hasAttribute('data-wblock-player-cleaner'));
    return { pass: ok, detail: `scriptRan=${ran} controls=${v && v.controls} attr=${v && v.getAttribute('data-wblock-player-cleaner')}` };
  });

  // Idempotency across the boot rescans + observer.
  await page.waitForTimeout(2600);
  await check(page, S, 'no duplicate videos after rescans (idempotent)', () => {
    const counts = ['#bare-enhance', '#bare-clean', '#bare-ambient'].map(id => document.querySelectorAll(id + ' video').length);
    const nativeCount = document.querySelectorAll('#bare-native').length;
    const ok = counts.every(n => n === 1) && nativeCount === 1;
    return { pass: ok, detail: `counts=${counts.join(',')} native=${nativeCount}` };
  });

  record(S, 'no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));
  await browser.close();
}

{
  const { browser, page, pageErrors } = await runScenario('Player Cleaner (relative URL sources)', {
    fixture: FIXTURE_PLAYER_RELATIVE_URL,
    scriptSource: playerUserscript,
    readySignal: '[data-wblock-player-cleaner]',
    viewport: { width: 1280, height: 800 },
  });
  const S = 'player-cleaner-relative';

  const cases = [
    ['rel-jw', 'https://example.com/download/item/movie.mp4', 'JW Player root-relative file'],
    ['rel-dom', 'https://example.com/media/dom.mp4', 'data-src root-relative URL'],
  ];
  for (const [id, expected, how] of cases) {
    await check(page, S, `resolves ${how} to absolute`, ({ id, expected }) => {
      const c = document.getElementById(id);
      const v = c ? c.querySelector('video') : null;
      const ok = !!(v && v.src === expected);
      return { pass: ok, detail: v ? `src=${v.src}` : 'no video' };
    }, { arg: { id, expected } });
  }

  await check(page, S, 'relative-source players replaced with a clean video', (cases) => {
    const bad = cases.filter(([id]) => {
      const c = document.getElementById(id);
      return !c || c.querySelectorAll('video').length !== 1 || !c.hasAttribute('data-wblock-player-cleaner');
    }).map(([id]) => id);
    return { pass: bad.length === 0, detail: bad.length ? `bad: ${bad.join(',')}` : '2/2 replaced' };
  }, { arg: cases });

  record(S, 'no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));
  await browser.close();
}

// ---- Scenario 8: Player Cleaner upgrade on loadedmetadata ----------------
// A Plyr-style player exposes only an opaque blob: src at first scan, so Player
// Cleaner can only enhance it in place. Its mock player API appears later without
// mutating the DOM. loadedmetadata must trigger source discovery and structural
// cleanup while retaining the already-buffering media element.
{
  const { browser, page, pageErrors } = await runScenario('Player Cleaner (upgrade on loadedmetadata)', {
    fixture: FIXTURE_PLAYER_UPGRADE_URL,
    scriptSource: playerUserscript,
    readySignal: '#player-upgrade[data-wblock-player-cleaner]',
    viewport: { width: 1280, height: 800 },
  });
  const S = 'player-cleaner-upgrade';

  // First scan: opaque source -> enhanced in place, NOT replaced.
  await check(page, S, 'enhances (does not replace) the opaque video at first scan', () => {
    const v = document.querySelector('#player-upgrade video');
    if (!v) return { pass: false, detail: 'no video' };
    const enhanced = v.controls === true && v.hasAttribute('data-wblock-player-cleaner');
    const notReplaced = v.src.startsWith('blob:');
    return { pass: enhanced && notReplaced, detail: `controls=${v.controls} src=${v.src}` };
  });

  // Tag the original element, then wait until all boot recovery events have
  // passed before exposing a clean source only through the mocked player API.
  await page.waitForLoadState('load');
  await page.evaluate(() => {
    document.querySelector('#player-upgrade video').setAttribute('data-test-original', '1');
    window.jwplayer = function (id) {
      if (id !== 'player-upgrade') return null;
      return { getPlaylistItem: function () {
        return { file: 'https://example.com/media/movie.mp4' };
      } };
    };
  });
  await page.waitForTimeout(700);
  await check(page, S, 'API availability alone does not require polling', () => {
    const c = document.getElementById('player-upgrade');
    const v = c && c.querySelector('video');
    const custom = c && c.querySelector('.plyr__controls');
    return { pass: !!(v && v.src.startsWith('blob:') && custom),
      detail: v ? `src=${v.src} custom=${!!custom}` : 'no video' };
  });

  // Fire loadedmetadata -> the event-driven upgrade should discover the API
  // source, remove custom chrome, and keep the original media element.
  await page.evaluate(() => {
    const v = document.querySelector('#player-upgrade video');
    v.dispatchEvent(new Event('loadedmetadata', { bubbles: false }));
  });

  await check(page, S, 'upgrades the original <video> on loadedmetadata', () => {
    const c = document.getElementById('player-upgrade');
    const v = c ? c.querySelector('video') : null;
    if (!v) return { pass: false, detail: 'no video' };
    const retained = v.hasAttribute('data-test-original');
    const clean = v.src === 'https://example.com/media/movie.mp4';
    return { pass: retained && clean, detail: `retained=${retained} src=${v.src}` };
  });

  await check(page, S, 'cleaned video has native controls + retained poster', () => {
    const v = document.querySelector('#player-upgrade video');
    const ok = !!(v && v.controls === true && v.getAttribute('poster') === 'https://example.com/poster.jpg');
    return { pass: ok, detail: v ? `controls=${v.controls} poster=${v.getAttribute('poster')}` : 'no video' };
  });

  await check(page, S, 'removes the custom control chrome', () => {
    const c = document.getElementById('player-upgrade');
    const bar = c ? c.querySelector('.plyr__controls') : null;
    return { pass: !bar, detail: `plyr__controls present=${!!bar}` };
  });

  await check(page, S, 'exactly one video after upgrade (idempotent)', () => {
    const c = document.getElementById('player-upgrade');
    const n = c ? c.querySelectorAll('video').length : 0;
    return { pass: n === 1, detail: `${n} video(s)` };
  });

  record(S, 'no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));
  await browser.close();
}

// ---- Scenario 9: Player Cleaner transforms before DOMContentLoaded -------
// The player is created by a <head> script. A true document-start cleaner must
// observe and nativeize it at the mutation microtask checkpoint, before the
// parser reaches DOMContentLoaded and without a timer/debounce.
{
  const { browser, page, pageErrors } = await runScenario('Player Cleaner (pre-paint timing)', {
    fixture: FIXTURE_PLAYER_EARLY_URL,
    scriptSource: playerUserscript,
    readySignal: '#early-player[data-wblock-player-cleaner]',
    viewport: { width: 1280, height: 800 },
  });
  const S = 'player-cleaner-timing';

  await check(page, S, 'nativeizes before DOMContentLoaded', () => {
    const t = window.__wblockEarlyPlayerTiming;
    const pass = !!(t && t.nativeAt > 0 && t.domContentLoadedAt > 0 && t.nativeAt <= t.domContentLoadedAt);
    return { pass, detail: t ? `native=${t.nativeAt.toFixed(1)}ms dcl=${t.domContentLoadedAt.toFixed(1)}ms` : 'no timing' };
  });

  await check(page, S, 'nativeizes within one frame of insertion', () => {
    const t = window.__wblockEarlyPlayerTiming;
    const elapsed = t && t.nativeAt ? t.nativeAt - t.createdAt : Infinity;
    return { pass: elapsed >= 0 && elapsed < 50, detail: `latency=${Number.isFinite(elapsed) ? elapsed.toFixed(1) : 'n/a'}ms` };
  });

  await check(page, S, 'shows native controls with custom chrome removed', () => {
    const c = document.getElementById('early-player');
    const v = c && c.querySelector('video');
    const custom = c && c.querySelector('.vjs-control-bar');
    return { pass: !!(v && v.controls && !custom), detail: `controls=${!!(v && v.controls)} custom=${!!custom}` };
  });

  record(S, 'no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));
  await browser.close();
}

// ---- Scenario 10: production injector starts before <html> exists -------
// Playwright init scripts run at Safari's true document_start: readyState is
// "loading" and document.documentElement is null. The production injector must
// start native lookup immediately, wait only for the parser to create <html>,
// then execute a page-world document-start payload before the page's first
// <head> script—not defer the whole engine until DOMContentLoaded.
{
  console.log('\n=== Scenario: Userscript injector (true document-start) ===');
  const S = 'injector-document-start';
  const browser = await webkit.launch();
  const page = await browser.newPage();
  const pageErrors = [];
  page.on('pageerror', e => pageErrors.push(e.message));

  const earlyPayload = `window.__wblockEarlyPayload = {
    readyState: document.readyState,
    hasDocumentElement: !!document.documentElement,
    hasBody: !!document.body,
    time: performance.now()
  };`;
  const descriptor = {
    id: '00000000-0000-0000-0000-000000000001',
    name: 'Document Start Probe',
    namespace: 'com.skula.wblock.tests',
    version: '1.0.0',
    description: '',
    runAt: 'document-start',
    noframes: false,
    injectInto: 'page',
    content: earlyPayload,
    resourceNames: [],
    storageSnapshot: {},
  };
  const mockBridge = `
    globalThis.browser = {
      runtime: {
        onMessage: { addListener: function () {} },
        sendMessage: function (message) {
          if (message && message.action === 'getUserScripts') {
            return Promise.resolve({ userScripts: [${JSON.stringify(descriptor)}] });
          }
          return Promise.resolve({});
        }
      }
    };
  `;
  await page.addInitScript(mockBridge + '\n' + injectorSource);

  const fixture = `<!doctype html><html><head><script>
    window.__firstHeadScript = {
      readyState: document.readyState,
      sawPayload: !!window.__wblockEarlyPayload,
      time: performance.now()
    };
  <\/script></head><body>document-start probe</body></html>`;
  await page.goto('data:text/html;charset=utf-8,' + encodeURIComponent(fixture), { waitUntil: 'load' });

  const state = await page.evaluate(() => ({
    payload: window.__wblockEarlyPayload || null,
    head: window.__firstHeadScript || null,
  }));
  const early = !!(state.payload && state.head &&
    state.payload.readyState === 'loading' &&
    state.payload.hasDocumentElement === true &&
    state.payload.hasBody === false &&
    state.head.sawPayload === true &&
    state.payload.time <= state.head.time);
  record(S, 'executes document-start payload before first page script', early,
    state.payload && state.head
      ? `payload=${state.payload.time.toFixed(1)}ms head=${state.head.time.toFixed(1)}ms state=${state.payload.readyState}`
      : `payload=${!!state.payload} head=${!!state.head}`);
  record(S, 'no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));
  await browser.close();
}

// ---- Summary -------------------------------------------------------------
console.log('\n================ SUMMARY ================');
const byScenario = {};
for (const r of results) {
  byScenario[r.scenario] ??= { pass: 0, fail: 0 };
  byScenario[r.scenario][r.pass ? 'pass' : 'fail']++;
}
let totalPass = 0, totalFail = 0;
for (const [s, c] of Object.entries(byScenario)) {
  console.log(`  ${s}: ${c.pass} passed, ${c.fail} failed`);
  totalPass += c.pass; totalFail += c.fail;
}
console.log(`\n  TOTAL: ${totalPass} passed, ${totalFail} failed`);
if (totalFail > 0) {
  console.log('\n  FAILING CHECKS:');
  for (const r of results.filter(r => !r.pass)) {
    console.log(`   - [${r.scenario}] ${r.name}${r.detail ? ' — ' + r.detail : ''}`);
  }
}
process.exit(totalFail > 0 ? 1 : 0);
