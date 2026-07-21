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
const FIXTURE_TUBE_EARLY_URL = pathToFileURL(join(__dirname, 'fixture-tube-cleaner-early.html')).href;
const FIXTURE_TUBE_MULTIPLE_URL = pathToFileURL(join(__dirname, 'fixture-tube-cleaner-multiple.html')).href;
const FIXTURE_PLAYER_URL = pathToFileURL(join(__dirname, 'fixture-player-cleaner.html')).href;
const FIXTURE_PLAYER_REPLACE_URL = pathToFileURL(join(__dirname, 'fixture-player-cleaner-replace.html')).href;
const FIXTURE_PLAYER_DISCOVERY_URL = pathToFileURL(join(__dirname, 'fixture-player-cleaner-discovery.html')).href;
const FIXTURE_PLAYER_SHADOW_URL = pathToFileURL(join(__dirname, 'fixture-player-cleaner-shadow.html')).href;
const FIXTURE_PLAYER_BARE_URL = pathToFileURL(join(__dirname, 'fixture-player-cleaner-bare.html')).href;
const FIXTURE_PLAYER_RELATIVE_URL = pathToFileURL(join(__dirname, 'fixture-player-cleaner-relative.html')).href;
const FIXTURE_PLAYER_UPGRADE_URL = pathToFileURL(join(__dirname, 'fixture-player-cleaner-upgrade.html')).href;
const FIXTURE_PLAYER_EARLY_URL = pathToFileURL(join(__dirname, 'fixture-player-cleaner-early.html')).href;

const userscript = readFileSync(SCRIPT_PATH, 'utf8');
const playerUserscript = readFileSync(PLAYER_SCRIPT_PATH, 'utf8');
const injectorSource = readFileSync(INJECTOR_PATH, 'utf8');
const filter = (process.argv.find(a => a.startsWith('--filter=')) || '').split('=')[1] || '';

const iosStuckPreferencesPrelude = `
try {
  localStorage.setItem('wblock.tubeCleaner.audioOnly', '1');
  localStorage.setItem('wblock.tubeCleaner.quality', 'hd1080');
  localStorage.setItem('yt-player-quality', JSON.stringify({ quality: 'hd1080', previousQuality: 'auto' }));
} catch (e) {}
`;

const ipadDesktopPrelude = `
Object.defineProperty(Navigator.prototype, 'maxTouchPoints', {
  configurable: true,
  get: function () { return 5; }
});
Object.defineProperty(Navigator.prototype, 'platform', {
  configurable: true,
  get: function () { return 'MacIntel'; }
});
`;

const visibilityPrelude = `
window.__wblockNativeHidden = false;
window.__wblockNativeVisibility = 'visible';
Object.defineProperty(Document.prototype, 'hidden', {
  configurable: true,
  get: function () { return window.__wblockNativeHidden; }
});
Object.defineProperty(Document.prototype, 'visibilityState', {
  configurable: true,
  get: function () { return window.__wblockNativeVisibility; }
});
`;

const resourceCounterPatch = `
(function () {
  var counters = window.__wblockResourceCounters = {
    listeners: 0, intervals: 0, mutationObservers: 0, intersectionObservers: 0
  };
  function patchTarget(target) {
    var add = target.addEventListener.bind(target);
    var remove = target.removeEventListener.bind(target);
    target.addEventListener = function () { counters.listeners++; return add.apply(target, arguments); };
    target.removeEventListener = function () { counters.listeners--; return remove.apply(target, arguments); };
  }
  patchTarget(document);
  patchTarget(window);
  var setIntervalNative = window.setInterval.bind(window);
  var clearIntervalNative = window.clearInterval.bind(window);
  window.setInterval = function () { counters.intervals++; return setIntervalNative.apply(window, arguments); };
  window.clearInterval = function (id) { counters.intervals--; return clearIntervalNative(id); };

  var NativeMutationObserver = window.MutationObserver;
  window.MutationObserver = class extends NativeMutationObserver {
    constructor(callback) { super(callback); this.__wblockActive = false; }
    observe() {
      if (!this.__wblockActive) { this.__wblockActive = true; counters.mutationObservers++; }
      return super.observe(...arguments);
    }
    disconnect() {
      if (this.__wblockActive) { this.__wblockActive = false; counters.mutationObservers--; }
      return super.disconnect();
    }
  };

  var NativeIntersectionObserver = window.IntersectionObserver;
  if (NativeIntersectionObserver) {
    window.IntersectionObserver = class extends NativeIntersectionObserver {
      constructor(callback, options) { super(callback, options); this.__wblockActive = false; }
      observe() {
        if (!this.__wblockActive) { this.__wblockActive = true; counters.intersectionObservers++; }
        return super.observe(...arguments);
      }
      disconnect() {
        if (this.__wblockActive) { this.__wblockActive = false; counters.intersectionObservers--; }
        return super.disconnect();
      }
    };
  }
})();
`;

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
  await page.waitForSelector('.wblock-tc-native', { timeout: 10000 }).catch(() => {});
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

async function commonChecks(page, scenario, { expectToolbar = true } = {}) {
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

  if (expectToolbar) {
    await check(page, scenario, 'builds toolbar with quality+audio buttons', () => {
      const tb = document.querySelector('.wblock-tc-toolbar');
      const btns = tb ? tb.querySelectorAll('button').length : 0;
      return { pass: btns >= 2, detail: `${btns} buttons` };
    });
  } else {
    await check(page, scenario, 'uses only Safari native controls on iOS', () => ({
      pass: !document.querySelector('.wblock-tc-toolbar'),
      detail: `customToolbar=${!!document.querySelector('.wblock-tc-toolbar')}`,
    }));
  }

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

// The fixture's mock player repeatedly removes controls/inline playback and
// reapplies native PiP/AirPlay restrictions. Both platforms restore PiP and
// native controls; iOS must retain the MMS remote-playback safety restriction.
async function controlsSurvivalCheck(page, scenario, { preserveIOSMMSRestrictions = false } = {}) {
  await page.waitForTimeout(4200); // let several fightControls rounds run
  const label = preserveIOSMMSRestrictions
    ? 'native controls survive while iOS MMS safety restrictions remain'
    : 'native media capabilities SURVIVE YouTube restrictions';
  await check(page, scenario, label, (preserveIOSMMSRestrictions) => {
    const v = document.querySelector('#movie_player video');
    if (!v) return { pass: false, detail: 'no video' };
    const state = {
      controls: v.controls && v.hasAttribute('controls'),
      inline: v.playsInline && v.hasAttribute('playsinline') && v.hasAttribute('webkit-playsinline'),
    };
    if (preserveIOSMMSRestrictions) {
      state.pip = !v.disablePictureInPicture && !v.hasAttribute('disablepictureinpicture');
      state.controlsList = !v.hasAttribute('controlslist');
      state.remoteDisabled = v.disableRemotePlayback && v.hasAttribute('disableremoteplayback');
      state.airplayNotForced = v.getAttribute('x-webkit-airplay') !== 'allow';
    } else {
      state.pip = !v.hasAttribute('disablepictureinpicture');
      state.remote = !v.hasAttribute('disableremoteplayback');
      state.controlsList = !v.hasAttribute('controlslist');
      state.airplay = v.getAttribute('x-webkit-airplay') === 'allow';
    }
    return {
      pass: Object.values(state).every(Boolean),
      detail: Object.entries(state).map(([k, value]) => `${k}=${value}`).join(' '),
    };
  }, { timeout: 1500, interval: 500, arg: preserveIOSMMSRestrictions });
}

async function iosNativeControlsChecks(page, scenario) {
  await check(page, scenario, 'clears persisted audio-only mode on iOS', () => {
    const video = document.querySelector('#movie_player video');
    const audioStyle = document.getElementById('wblock-tc-style-audio');
    return { pass: localStorage.getItem('wblock.tubeCleaner.audioOnly') !== '1' &&
      !audioStyle && video && getComputedStyle(video).visibility === 'visible',
      detail: `stored=${localStorage.getItem('wblock.tubeCleaner.audioOnly')} style=${!!audioStyle} visibility=${video && getComputedStyle(video).visibility}` };
  });
  await check(page, scenario, 'restores adaptive quality instead of retrying fixed 1080p', () => {
    const quality = localStorage.getItem('wblock.tubeCleaner.quality');
    const bias = localStorage.getItem('yt-player-quality');
    const settingsClicks = window.__settingsClicks || 0;
    return { pass: quality === 'auto' && bias === null && settingsClicks === 0,
      detail: `quality=${quality} bias=${bias} settingsClicks=${settingsClicks}` };
  });
  await check(page, scenario, 'does not style Safari private media controls', () => {
    const css = document.getElementById('wblock-tc-style')?.textContent || '';
    return { pass: !css.includes('::-webkit-media-controls') && !css.includes('touch-action: manipulation !important; } .wblock-tc-native video') };
  });
  await check(page, scenario, 'keeps mobile YouTube controls behind the native video after unmute', () => {
    const player = document.querySelector('.wblock-tc-native');
    const video = player?.querySelector('video');
    if (!player || !video) return { pass: false, detail: 'missing player or video' };

    const content = document.createElement('div');
    content.className = 'ytp-player-content ytp-timely-actions-content';
    content.style.cssText = 'position:absolute;inset:0;z-index:1000';
    player.appendChild(content);

    const rect = video.getBoundingClientRect();
    const controls = document.createElement('div');
    controls.id = 'player-control-container';
    controls.innerHTML = '<ytm-custom-control><ytm-watch-player-controls><div id="player-control-overlay"></div></ytm-watch-player-controls></ytm-custom-control>';
    controls.style.cssText = `position:fixed;left:${rect.left}px;top:${rect.top}px;width:${rect.width}px;height:${rect.height}px;z-index:2000`;

    // Mobile YouTube adds its separate controls tree when the required
    // "Tap to unmute" action runs. Keep that button usable, then ensure the
    // resulting YouTube overlay cannot cover Safari's controls.
    const unmute = document.createElement('button');
    unmute.className = 'ytp-unmute ytp-popup ytp-button';
    player.appendChild(unmute);
    const unmuteUsable = getComputedStyle(unmute).display !== 'none' &&
      getComputedStyle(unmute).pointerEvents !== 'none';
    unmute.addEventListener('click', () => {
      unmute.remove();
      document.body.appendChild(controls);
    });
    unmute.click();

    const contentPointerEvents = getComputedStyle(content).pointerEvents;
    const controlsDisplay = getComputedStyle(controls).display;
    const hit = document.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2);
    const pass = unmuteUsable && contentPointerEvents === 'none' && controlsDisplay === 'none' && hit === video;
    content.remove();
    controls.remove();
    return { pass, detail: `unmuteUsable=${unmuteUsable} contentPointerEvents=${contentPointerEvents} controlsDisplay=${controlsDisplay} hit=${hit?.tagName}` };
  });
  await check(page, scenario, 'keeps the iOS video visible with a real layout box', () => {
    const video = document.querySelector('#movie_player video');
    const rect = video?.getBoundingClientRect();
    return { pass: !!(video && rect && rect.width > 100 && rect.height > 100 &&
      getComputedStyle(video).display !== 'none' && getComputedStyle(video).visibility !== 'hidden'),
      detail: rect ? `${rect.width.toFixed(0)}x${rect.height.toFixed(0)} visibility=${getComputedStyle(video).visibility}` : 'no video' };
  });
}

async function iosLandscapeCheck(page, scenario) {
  await page.setViewportSize({ width: 844, height: 390 });
  await page.evaluate(() => {
    const wrap = document.getElementById('player-wrap');
    const player = document.querySelector('.wblock-tc-native');
    if (wrap) wrap.style.margin = '0';
    player.style.width = '100vw';
    player.style.height = '100vh';
  });
  await check(page, scenario, 'iOS native video survives landscape rotation', () => {
    const player = document.querySelector('.wblock-tc-native').getBoundingClientRect();
    const video = document.querySelector('.wblock-tc-native video');
    const rect = video.getBoundingClientRect();
    return { pass: video.controls && rect.width > 100 && rect.height > 100 &&
      rect.left >= player.left - 1 && rect.right <= player.right + 1,
      detail: `video=${rect.width.toFixed(0)}x${rect.height.toFixed(0)} viewport=${innerWidth}x${innerHeight}` };
  });
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

async function qualityUISelectionCheck(page, scenario) {
  await page.evaluate(() => window.__wblockTubeDebug.setQuality('hd1080'));
  await page.waitForTimeout(800);
  await check(page, scenario, 'selects quality through YouTube UI without double-toggle', () => ({
    pass: window.__uiSelectedQuality === 'hd1080' && window.__settingsClicks === 2,
    detail: `selected=${window.__uiSelectedQuality} settingsClicks=${window.__settingsClicks}`,
  }));
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
  await qualityUISelectionCheck(page, 'desktop');
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
    scriptSource: iosStuckPreferencesPrelude + '\n' + userscript,
  });
  await commonChecks(page, 'iPhone', { expectToolbar: false });
  await iosNativeControlsChecks(page, 'iPhone');
  await iosLandscapeCheck(page, 'iPhone');
  await controlsSurvivalCheck(page, 'iPhone', { preserveIOSMMSRestrictions: true });
  record('iPhone', 'no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));
  await browser.close();
}

// ---- Scenario 3: iPad mobile UA (no playsinline) -------------------------
// Older iPadOS/mobile-site UAs still need the same inline-playback and touch UI
// defenses as modern iPadOS requesting the desktop site.
{
  const ipad = devices['iPad Pro 11'];
  const { browser, page, pageErrors } = await runScenario('iPad mobile UA (no playsinline)', {
    device: ipad,
    fixture: FIXTURE_NOPI_URL,
    hasTouch: true,
    scriptSource: iosStuckPreferencesPrelude + '\n' + userscript,
  });
  await commonChecks(page, 'iPad-mobile', { expectToolbar: false });
  await check(page, 'iPad-mobile', 'ensures playsinline for inline iOS playback', () => {
    const v = document.querySelector('#movie_player video');
    if (!v) return { pass: false, detail: 'no video' };
    const ok = v.hasAttribute('playsinline') || v.playsInline === true;
    return { pass: ok, detail: `playsInline=${v.playsInline}, attr=${v.hasAttribute('playsinline')}` };
  });
  await iosNativeControlsChecks(page, 'iPad-mobile');
  await controlsSurvivalCheck(page, 'iPad-mobile', { preserveIOSMMSRestrictions: true });
  record('iPad-mobile', 'no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));
  await browser.close();
}

// ---- Scenario 4: modern iPadOS requesting the desktop site --------------
// Current iPadOS identifies as MacIntel with touch points. This is the path that
// historically risks being mistaken for macOS, especially at document-start.
{
  const { browser, page, pageErrors } = await runScenario('iPadOS desktop-site UA', {
    fixture: FIXTURE_NOPI_URL,
    ua: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15',
    hasTouch: true,
    viewport: { width: 1024, height: 768 },
    scriptSource: iosStuckPreferencesPrelude + '\n' + ipadDesktopPrelude + '\n' + userscript,
  });
  const S = 'iPad-desktop';
  await commonChecks(page, S, { expectToolbar: false });
  await check(page, S, 'detects desktop-UA iPadOS as touch Safari', () => ({
    pass: navigator.platform === 'MacIntel' && navigator.maxTouchPoints === 5 &&
      !document.querySelector('.wblock-tc-toolbar'),
    detail: `platform=${navigator.platform} touches=${navigator.maxTouchPoints} customToolbar=${!!document.querySelector('.wblock-tc-toolbar')}`,
  }));
  await iosNativeControlsChecks(page, S);
  await controlsSurvivalCheck(page, S, { preserveIOSMMSRestrictions: true });
  record(S, 'no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));
  await browser.close();
}

// ---- Scenario 5: iPadOS active-player selection (Shorts-style) -----------
{
  const { browser, page, pageErrors } = await runScenario('iPadOS multiple YouTube players', {
    fixture: FIXTURE_TUBE_MULTIPLE_URL,
    ua: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15',
    hasTouch: true,
    viewport: { width: 1024, height: 768 },
    scriptSource: ipadDesktopPrelude + '\n' + userscript,
    readySignal: '#current-short.wblock-tc-native',
  });
  const S = 'iPad-multiple-players';
  await check(page, S, 'nativeizes the visible playing player, not the first DOM match', () => {
    const selected = window.__wblockTubeDebug.getPlayer();
    const video = document.querySelector('#current-short video');
    return { pass: selected?.id === 'current-short' && video.controls &&
      !document.querySelector('.wblock-tc-toolbar') };
  });
  await page.evaluate(() => window.__switchActiveShort());
  await check(page, S, 'moves native enhancements when the active Short changes', () => {
    const selected = window.__wblockTubeDebug.getPlayer();
    const video = document.querySelector('#previous-short video');
    return { pass: selected?.id === 'previous-short' && video.controls &&
      !document.querySelector('.wblock-tc-toolbar'),
      detail: `selected=${selected?.id}` };
  });
  await check(page, S, 'hides chrome on a non-movie_player instance', () => {
    const chrome = document.querySelector('#previous-short .ytp-chrome-bottom');
    return { pass: !!(chrome && getComputedStyle(chrome).display === 'none'),
      detail: chrome ? `display=${getComputedStyle(chrome).display}` : 'no chrome' };
  });
  record(S, 'no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));
  await browser.close();
}

// ---- Scenario 6: Tube Cleaner transforms before DOMContentLoaded ---------
// A <head> script creates the YouTube player. The document observer must install
// anti-flash CSS and nativeize the video in the same pre-paint mutation cycle.
{
  const { browser, page, pageErrors } = await runScenario('Tube Cleaner (pre-paint timing)', {
    fixture: FIXTURE_TUBE_EARLY_URL,
    readySignal: '#movie_player.wblock-tc-native',
    viewport: { width: 1280, height: 800 },
  });
  const S = 'tube-cleaner-timing';

  await check(page, S, 'injects anti-flash CSS before DOMContentLoaded', () => {
    const t = window.__wblockEarlyTubeTiming;
    const pass = !!(t && t.styleAt > 0 && t.domContentLoadedAt > 0 && t.styleAt <= t.domContentLoadedAt);
    return { pass, detail: t ? `style=${t.styleAt.toFixed(1)}ms dcl=${t.domContentLoadedAt.toFixed(1)}ms` : 'no timing' };
  });

  await check(page, S, 'nativeizes before DOMContentLoaded', () => {
    const t = window.__wblockEarlyTubeTiming;
    const pass = !!(t && t.nativeAt > 0 && t.domContentLoadedAt > 0 && t.nativeAt <= t.domContentLoadedAt);
    return { pass, detail: t ? `native=${t.nativeAt.toFixed(1)}ms dcl=${t.domContentLoadedAt.toFixed(1)}ms` : 'no timing' };
  });

  await check(page, S, 'nativeizes within one frame of insertion', () => {
    const t = window.__wblockEarlyTubeTiming;
    const elapsed = t && t.nativeAt ? t.nativeAt - t.createdAt : Infinity;
    return { pass: elapsed >= 0 && elapsed < 50, detail: `latency=${Number.isFinite(elapsed) ? elapsed.toFixed(1) : 'n/a'}ms` };
  });

  await check(page, S, 'keeps YouTube chrome hidden', () => {
    const chrome = document.querySelector('#movie_player .ytp-chrome-bottom');
    return { pass: !!(chrome && getComputedStyle(chrome).display === 'none'),
      detail: chrome ? `display=${getComputedStyle(chrome).display}` : 'no chrome fixture' };
  });

  record(S, 'no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));
  await browser.close();
}

// ---- Scenario 5: Tube Cleaner resource lifecycle ------------------------
{
  const { browser, page, pageErrors } = await runScenario('Tube Cleaner (resource lifecycle)', {
    fixture: FIXTURE_URL,
    scriptSource: resourceCounterPatch + '\n' + userscript,
    readySignal: '.wblock-tc-toolbar',
    viewport: { width: 1280, height: 800 },
  });
  const S = 'tube-cleaner-resources';
  await page.waitForTimeout(300);
  const baseline = await page.evaluate(() => ({ ...window.__wblockResourceCounters }));

  for (let i = 0; i < 6; i++) {
    await page.evaluate(() => {
      const container = document.querySelector('#movie_player .html5-video-container');
      const oldVideo = container.querySelector('video');
      oldVideo.replaceWith(document.createElement('video'));
    });
    await page.waitForTimeout(80);
  }
  const after = await page.evaluate(() => ({ ...window.__wblockResourceCounters }));
  for (const key of ['listeners', 'intervals', 'mutationObservers', 'intersectionObservers']) {
    record(S, `${key} stay flat across video swaps`, after[key] === baseline[key],
      `baseline=${baseline[key]} after=${after[key]}`);
  }
  await check(page, S, 'replacement video remains native', () => {
    const v = document.querySelector('#movie_player video');
    return { pass: !!(v && v.controls && v.hasAttribute('controls')) };
  });
  record(S, 'no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));
  await browser.close();
}

// ---- Scenario 6: Player Cleaner on a custom (video.js) player ------------
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

  await check(page, 'player-cleaner', 'nativeizes MediaElement video in place', () => {
    const v = document.querySelector('#mediaelement-player video');
    return { pass: !!(v && v.controls && v.hasAttribute('data-test-mediaelement') &&
      v.hasAttribute('data-wblock-player-cleaner')) };
  });

  await check(page, 'player-cleaner', 'preserves MediaElement shell and hides its chrome', () => {
    const shell = document.querySelector('#mediaelement-player .mejs__inner');
    const chrome = document.querySelector('#mediaelement-player .mejs__controls');
    return { pass: !!(shell && chrome && chrome.style.display === 'none'),
      detail: `shell=${!!shell} chrome=${!!chrome} display=${chrome && chrome.style.display}` };
  });

  await page.waitForTimeout(4200); // let several fightControls rounds run
  await check(page, 'player-cleaner', 'native controls SURVIVE player turning them off', () => {
    const v = document.querySelector('.video-js video');
    if (!v) return { pass: false, detail: 'no video' };
    const hasAttr = v.hasAttribute('controls');
    return { pass: hasAttr, detail: `hasAttribute('controls')=${hasAttr} (getter=${v.controls})` };
  }, { timeout: 1500, interval: 500 });

  await check(page, 'player-cleaner', 'MediaElement lifecycle remains intact', () => ({
    pass: window.__wblockMediaElementLifecycleIntact === true,
    detail: `lifecycle=${window.__wblockMediaElementLifecycleIntact}`,
  }));

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

  await check(page, S, 'does not mistake poster data-src for media', () => {
    const v = document.querySelector('#p-poster video');
    return { pass: !!(v && v.src.startsWith('blob:') && v.controls),
      detail: v ? `src=${v.src}` : 'no video' };
  });

  await check(page, S, 'keeps DASH manifest on its working MSE/blob pipeline', () => {
    const v = document.querySelector('#p-dash video');
    return { pass: !!(v && v.src.startsWith('blob:') && v.controls),
      detail: v ? `src=${v.src}` : 'no video' };
  });

  // Idempotency across recovery scans + observer.
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

// ---- Player Cleaner: Archive.org-style shadow-root JW Player ------------
{
  const { browser, page, pageErrors } = await runScenario('Player Cleaner (shadow-root JW Player)', {
    fixture: FIXTURE_PLAYER_SHADOW_URL,
    scriptSource: resourceCounterPatch + '\n' + playerUserscript,
    readySignal: 'test-play-av',
    viewport: { width: 1280, height: 800 },
  });
  const S = 'player-cleaner-shadow';

  await check(page, S, 'nativeizes shadow video before DOMContentLoaded', () => {
    const t = window.__wblockShadowTiming;
    const pass = !!(t && t.nativeAt > 0 && t.domContentLoadedAt > 0 && t.nativeAt <= t.domContentLoadedAt);
    return { pass, detail: t ? `native=${t.nativeAt.toFixed(1)}ms dcl=${t.domContentLoadedAt.toFixed(1)}ms` : 'no timing' };
  });

  await check(page, S, 'nativeizes shadow video within one frame', () => {
    const t = window.__wblockShadowTiming;
    const elapsed = t && t.nativeAt ? t.nativeAt - t.createdAt : Infinity;
    return { pass: elapsed >= 0 && elapsed < 50,
      detail: `latency=${Number.isFinite(elapsed) ? elapsed.toFixed(1) : 'n/a'}ms` };
  });

  await check(page, S, 'retains Archive-style media element and absolute source', () => {
    const root = document.querySelector('test-play-av').shadowRoot;
    const videos = root.querySelectorAll('video');
    const v = videos[0];
    const retained = videos.length === 1 && v.hasAttribute('data-test-original');
    return { pass: retained && v.src === 'https://example.com/download/archive/movie.mp4',
      detail: `count=${videos.length} retained=${retained} src=${v.src}` };
  });

  await check(page, S, 'forces native controls inside shadow root', () => {
    const v = document.querySelector('test-play-av').shadowRoot.querySelector('video');
    return { pass: !!(v && v.controls && v.hasAttribute('controls') &&
      v.hasAttribute('data-wblock-player-cleaner')) };
  });

  await check(page, S, 'preserves shadow component but hides JW chrome', () => {
    const root = document.querySelector('test-play-av').shadowRoot;
    const chrome = root.querySelector('.jw-controls');
    return { pass: !!(chrome && chrome.style.display === 'none'),
      detail: `present=${!!chrome} display=${chrome && chrome.style.display}` };
  });

  await page.evaluate(() => {
    document.querySelector('test-play-av').shadowRoot.querySelector('video').removeAttribute('controls');
  });
  await check(page, S, 'shadow controls survive player removal attempts', () => {
    const v = document.querySelector('test-play-av').shadowRoot.querySelector('video');
    return { pass: !!(v && v.hasAttribute('controls')) };
  });

  const baseline = await page.evaluate(() => ({ ...window.__wblockResourceCounters }));
  await page.evaluate(() => {
    const host = document.querySelector('test-play-av');
    host.remove();
    setTimeout(() => document.body.appendChild(host), 50);
  });
  await page.waitForTimeout(200);
  const after = await page.evaluate(() => ({ ...window.__wblockResourceCounters }));
  for (const key of ['listeners', 'intervals', 'mutationObservers', 'intersectionObservers']) {
    record(S, `${key} stay flat after shadow host reattachment`, after[key] === baseline[key],
      `baseline=${baseline[key]} after=${after[key]}`);
  }
  await check(page, S, 'reattached shadow video is native again', () => {
    const v = document.querySelector('test-play-av').shadowRoot.querySelector('video');
    return { pass: !!(v && v.controls && v.hasAttribute('data-wblock-player-cleaner')) };
  });

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

// ---- Scenario 10: Player Cleaner resource lifecycle ---------------------
// SPA/custom players replace their <video> nodes. Per-video listeners and
// observers must be released rather than accumulating for the page lifetime.
{
  const { browser, page, pageErrors } = await runScenario('Player Cleaner (resource lifecycle)', {
    fixture: FIXTURE_PLAYER_URL,
    scriptSource: resourceCounterPatch + '\n' + playerUserscript,
    readySignal: '[data-wblock-player-cleaner]',
    viewport: { width: 1280, height: 800 },
  });
  const S = 'player-cleaner-resources';
  await page.waitForTimeout(300);
  const baseline = await page.evaluate(() => ({ ...window.__wblockResourceCounters }));

  for (let i = 0; i < 6; i++) {
    await page.evaluate(() => {
      const container = document.querySelector('.video-js');
      const oldVideo = container.querySelector('video');
      const video = document.createElement('video');
      video.src = 'blob:https://example.com/00000000-0000-0000-0000-000000000000';
      oldVideo.replaceWith(video);
    });
    await page.waitForTimeout(80);
  }
  const after = await page.evaluate(() => ({ ...window.__wblockResourceCounters }));
  for (const key of ['listeners', 'intervals', 'mutationObservers', 'intersectionObservers']) {
    record(S, `${key} stay flat across video swaps`, after[key] === baseline[key],
      `baseline=${baseline[key]} after=${after[key]}`);
  }
  await check(page, S, 'replacement video remains native', () => {
    const v = document.querySelector('.video-js video');
    return { pass: !!(v && v.controls && v.hasAttribute('controls')) };
  });
  record(S, 'no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));
  await browser.close();
}

// ---- Scenario 11: native visibility survives document shadowing ---------
// Both cleaners override document.hidden/visibilityState so page players keep
// running. Auto-PiP must still read the original prototype getters when the tab
// really hides, not its own forced-visible document properties.
for (const config of [
  { name: 'Tube Cleaner', key: 'tube-cleaner-visibility', fixture: FIXTURE_URL,
    source: visibilityPrelude + '\n' + userscript, selector: '#movie_player video', ready: '.wblock-tc-toolbar' },
  { name: 'Player Cleaner', key: 'player-cleaner-visibility', fixture: FIXTURE_PLAYER_URL,
    source: visibilityPrelude + '\n' + playerUserscript, selector: '.video-js video', ready: '[data-wblock-player-cleaner]' },
]) {
  const { browser, page, pageErrors } = await runScenario(`${config.name} (native visibility)`, {
    fixture: config.fixture,
    scriptSource: config.source,
    readySignal: config.ready,
    viewport: { width: 1280, height: 800 },
  });
  await page.evaluate((selector) => {
    const video = document.querySelector(selector);
    Object.defineProperty(video, 'paused', { configurable: true, get: () => false });
    Object.defineProperty(video, 'ended', { configurable: true, get: () => false });
    video.webkitSupportsPresentationMode = true;
    video.webkitPresentationMode = 'inline';
    video.webkitSetPresentationMode = function (mode) {
      this.webkitPresentationMode = mode;
      window.__wblockPiPMode = mode;
    };
    window.__wblockNativeHidden = true;
    window.__wblockNativeVisibility = 'hidden';
    document.dispatchEvent(new Event('visibilitychange'));
  }, config.selector);
  await check(page, config.key, 'enters PiP from native hidden state while page sees visible', () => ({
    pass: document.hidden === false && document.visibilityState === 'visible' &&
      window.__wblockPiPMode === 'picture-in-picture',
    detail: `pageHidden=${document.hidden} pageState=${document.visibilityState} pip=${window.__wblockPiPMode}`,
  }));
  if (config.name === 'Tube Cleaner') {
    await page.evaluate((selector) => {
      const video = document.querySelector(selector);
      // End the cleaner-owned PiP session, then model the user entering PiP
      // manually from Safari's native controls.
      video.webkitPresentationMode = 'inline';
      video.dispatchEvent(new Event('webkitpresentationmodechanged'));
      video.webkitPresentationMode = 'picture-in-picture';
      video.dispatchEvent(new Event('webkitpresentationmodechanged'));
      window.__wblockPiPMode = 'picture-in-picture';
      window.__wblockNativeHidden = false;
      window.__wblockNativeVisibility = 'visible';
      document.dispatchEvent(new Event('visibilitychange'));
    }, config.selector);
    await check(page, config.key, 'does not close PiP entered manually by the user', () => ({
      pass: window.__wblockPiPMode === 'picture-in-picture',
      detail: `pip=${window.__wblockPiPMode}`,
    }));
  }
  record(config.key, 'no uncaught page errors', pageErrors.length === 0, pageErrors.join(' | '));
  await browser.close();
}

// ---- Scenario 12: production injector starts before <html> exists -------
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
