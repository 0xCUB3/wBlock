import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { webkit } from 'playwright';

const dir = dirname(fileURLToPath(import.meta.url));
const fixture = readFileSync(join(dir, 'fixture-facebook-reel.html'), 'utf8');
const playerCleaner = readFileSync(join(dir, '..', '..', 'wBlockCoreService', 'BundledUserscripts', 'player-cleaner.user.js'), 'utf8');
const url = 'https://www.facebook.com/reel/wblock-audio-test';

const browser = await webkit.launch();
try {
  const context = await browser.newContext({ viewport: { width: 800, height: 500 } });
  await context.route(url, route => route.fulfill({
    status: 200,
    contentType: 'text/html',
    body: fixture,
  }));
  const page = await context.newPage();
  await page.addInitScript(playerCleaner);
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => {
    const video = document.querySelector('video');
    return video && video.hasAttribute('data-wblock-player-cleaner');
  });
  await page.waitForTimeout(300);

  const beforeClick = await page.evaluate(() => {
    const player = document.getElementById('facebook-reel');
    const video = player.querySelector('video');
    const button = player.querySelector('button');
    const path = button && button.closest('.audio-control-path');
    return {
      enhanced: video.controls === true,
      retained: !!player.querySelector('[data-audio-state]'),
      notDestructivelyCleaned: !video._wblockCleaned,
      remutedByApp: video.muted,
      rendered: window.__facebookReelRendered,
      buttonVisible: !!button && getComputedStyle(button).display !== 'none',
      pathVisible: !!path && getComputedStyle(path).display !== 'none',
    };
  });
  assert.equal(beforeClick.enhanced, true, 'muted autoplay Reel is enhanced');
  assert.equal(beforeClick.retained, true, 'Facebook audio state remains mounted');
  assert.equal(beforeClick.notDestructivelyCleaned, true, 'Reel wrapper is not structurally cleaned');
  assert.equal(beforeClick.remutedByApp, true, 'Facebook rerender restores its muted app state');
  assert.equal(beforeClick.rendered, 1, 'Facebook rerendered the accessible control');
  assert.equal(beforeClick.buttonVisible, true, 'accessible mute control survives suppression');
  assert.equal(beforeClick.pathVisible, true, 'mute control ancestor path survives suppression');

  await page.locator('#facebook-reel button').click();
  await page.waitForTimeout(120);
  const afterClick = await page.evaluate(() => ({
    muted: document.querySelector('#facebook-reel video').muted,
    appState: document.querySelector('[data-audio-state]').getAttribute('data-audio-state'),
  }));
  assert.deepEqual(afterClick, { muted: false, appState: 'unmuted' },
    'preserved Unmute button updates Facebook state and leaves video unmuted');
  console.log('PASS Facebook Reel audio safeguard');
} finally {
  await browser.close();
}
