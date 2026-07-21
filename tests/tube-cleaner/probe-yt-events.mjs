// Probe: which document-level 'yt-*' events does YouTube actually dispatch?
// Determines whether Tube Cleaner's yt-player-state-change hook is dead code.
// Best-effort (network/autoplay dependent). Usage: node probe-yt-events.mjs
import { webkit } from 'playwright';

const url = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
const browser = await webkit.launch();
const ctx = await browser.newContext({
  userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15',
  viewport: { width: 1280, height: 800 }, locale: 'en-US',
});
await ctx.addCookies([
  { name: 'CONSENT', value: 'YES+cb.20210328-17-p0.en+FX+417', domain: '.youtube.com', path: '/' },
  { name: 'SOCS', value: 'CAI', domain: '.youtube.com', path: '/' },
]);
const page = await ctx.newPage();
await page.addInitScript(`
  window.__ytEvents = {};
  ['yt-navigate-finish','yt-page-data-updated','yt-player-state-change',
   'yt-state-change','yt-video-load','yt-play','yt-pause','yt-timeupdate',
   'yt-player-updated','yt-navigate-start','yt-navigate-cache'].forEach(function (t) {
    document.addEventListener(t, function () {
      window.__ytEvents[t] = (window.__ytEvents[t] || 0) + 1;
    }, true);
  });
`);
try { await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 }); } catch (e) { console.log('nav:', e.message); }
// Try to start playback so state changes occur.
await page.waitForTimeout(3000);
await page.evaluate(() => {
  const v = document.querySelector('#movie_player video');
  if (v) { v.muted = true; v.play().catch(() => {}); }
}).catch(() => {});
await page.waitForTimeout(12000);
const events = await page.evaluate(() => window.__ytEvents).catch(() => ({}));
console.log('Observed document-level yt-* events:', JSON.stringify(events, null, 2));
console.log(events['yt-player-state-change']
  ? '\n=> yt-player-state-change FIRES — hook is live, keep it.'
  : '\n=> yt-player-state-change did NOT fire — hook is likely dead.');
await browser.close();
