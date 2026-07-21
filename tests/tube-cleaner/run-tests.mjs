// Autonomous WebKit (Safari-engine) test harness for the Tube Cleaner userscript.
//
// It loads a synthetic YouTube watch page (fixture.html) in Playwright WebKit,
// injects the REAL bundled tube-cleaner.user.js at document-start in the page
// world (matching `@run-at document-start` + `@inject-into page`), and asserts
// the player transformation actually happens. It runs three scenarios:
//   1. desktop  – macOS Safari-like
//   2. iPhone   – mobile Safari (touch, mobile UA)
//   3. iPad desktop-site – iPadOS requesting www.youtube.com (no playsinline)
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
const FIXTURE_URL = pathToFileURL(join(__dirname, 'fixture.html')).href;
const FIXTURE_NOPI_URL = pathToFileURL(join(__dirname, 'fixture-noplaysinline.html')).href;
const FIXTURE_PLAYER_URL = pathToFileURL(join(__dirname, 'fixture-player-cleaner.html')).href;

const userscript = readFileSync(SCRIPT_PATH, 'utf8');
const playerUserscript = readFileSync(PLAYER_SCRIPT_PATH, 'utf8');
const filter = (process.argv.find(a => a.startsWith('--filter=')) || '').split('=')[1] || '';

const results = [];
function record(scenario, name, pass, detail = '') {
  results.push({ scenario, name, pass, detail });
  const mark = pass ? 'PASS' : 'FAIL';
  console.log(`  [${mark}] ${name}${detail ? ' — ' + detail : ''}`);
}

// Run an in-page check that returns {pass, detail}. Retries until pass or timeout
// because the userscript transforms the player asynchronously (250ms poll loop).
async function check(page, scenario, name, fn, { timeout = 6000, interval = 150 } = {}) {
  const start = Date.now();
  let last = { pass: false, detail: 'timeout' };
  while (Date.now() - start < timeout) {
    try {
      last = await page.evaluate(fn);
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
