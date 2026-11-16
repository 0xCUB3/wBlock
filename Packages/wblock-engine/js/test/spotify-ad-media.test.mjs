import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import assert from 'node:assert/strict';
import test from 'node:test';
import { JSDOM } from 'jsdom';

// Build the scriptlet the way the extension ships it, and run that output.
const dir = mkdtempSync(join(tmpdir(), 'spotify-ad-media-'));
execFileSync(process.execPath, [new URL('../build-scriptlets.mjs', import.meta.url).pathname, dir]);
const shipped = readFileSync(join(dir, 'trusted-spotify-ad-media.js'), 'utf8');
rmSync(dir, { recursive: true, force: true });

const redirects = new URL('../../../../wBlock Scripts (iOS)/Resources/redirects/', import.meta.url);
const mp4 = readFileSync(new URL('noopmp4.mp4', redirects));
const mp3 = readFileSync(new URL('noopmp3.mp3', redirects));
const dataURI = (type, bytes) => `data:${type};base64,${bytes.toString('base64')}`;
const cdn = 'https://adstudio-assets.scdn.co/mp3/c4a0aa2af6fb7edb210cf4e54ef8294f60652b48.mp3';
const approach = value => () => value;
const typedMP3 = approach({ approach: 'source', type: 'audio/mp3' });
const direct = approach({ approach: 'src' });
const hls = approach({ approach: 'source', type: 'application/x-mpegURL' });
const throwing = () => { throw new Error('no approach'); };

// Shaped like the web player's content loader: the CDN URL is assigned in load(),
// and the consumer callback calls this._getCacheKey, which the hook keys on.
const player = `
class Content {
  constructor(uri, cdn, approach) { this._uri = uri; this._url = ''; this._cdn = cdn; this._approach = approach; this.loads = 0; }
  getLoadingApproach() { this.loads++; return this._approach(); }
  load() { return Promise.resolve().then(() => { this._url = this._cdn; return this; }); }
}
class Player {
  _getCacheKey({ fileId }) { return fileId; }
  play(uri, cdn, approach) {
    return new Content(uri, cdn, approach).load().then(o => { this._getCacheKey({ fileId: 'f' }); return o; });
  }
}
globalThis.player = new Player();
`;

function setup(url = 'https://open.spotify.com/') {
  const dom = new JSDOM('', { url, runScripts: 'outside-only' });
  const w = dom.window;
  w.__wbeScriptletCalls = { 'trusted-spotify-ad-media': [[]] };
  w.eval(shipped);
  w.eval(player);
  return { dom, w };
}

function run(name, fn, url) {
  test(name, async () => {
    const state = setup(url);
    try { await fn(state.w, state.dom); } finally { state.dom.window.close(); }
  });
}

run('a typed audio/mp3 ad loads the bundled silent MP3', async w => {
  const content = await w.player.play('spotify:ad:abc', cdn, typedMP3);
  assert.equal(content._url, dataURI('audio/mp3', mp3));
});

run('a direct src ad loads the bundled silent MP4', async w => {
  const content = await w.player.play('spotify:ad:abc', cdn, direct);
  assert.equal(content._url, dataURI('video/mp4', mp4));
});

run('an ad with another declared type keeps its CDN URL', async w => {
  const content = await w.player.play('spotify:ad:abc', cdn, hls);
  assert.equal(content._url, cdn);
});

run('an ad whose approach is unknown keeps its CDN URL', async w => {
  const thrown = await w.player.play('spotify:ad:abc', cdn, throwing);
  assert.equal(thrown._url, cdn);
  const missing = await w.player.play('spotify:ad:abc', cdn, approach(undefined));
  assert.equal(missing._url, cdn);
});

run('songs keep their CDN URL and never ask for an approach', async w => {
  for (const loading of [typedMP3, direct, hls]) {
    const content = await w.player.play('spotify:track:xyz', cdn, loading);
    assert.equal(content._url, cdn);
    assert.equal(content.loads, 0);
  }
});

test('the hook is limited to open.spotify.com', async () => {
  // Same page script, same ad URI, on another host: nothing is replaced.
  const { dom, w } = setup('https://example.com/');
  try {
    assert.equal((await w.player.play('spotify:ad:abc', cdn, typedMP3))._url, cdn);
    assert.equal((await w.player.play('spotify:ad:abc', cdn, direct))._url, cdn);
  } finally {
    dom.window.close();
  }
});

run('then keeps native Promise semantics', async w => {
  assert.equal(await Promise.resolve(2).then(v => v * 2), 4);
  assert.equal(await Promise.resolve(3).then(null, null), 3);
  await assert.rejects(Promise.reject(new Error('boom')).then(() => 1), /boom/);
  class Sub extends Promise {}
  assert.ok(Sub.resolve(1).then(v => v) instanceof Sub);
  assert.throws(() => Promise.prototype.then.call({}, () => {}), TypeError);
  assert.equal(Promise.prototype.then.name, 'then');
});

run('injecting the scriptlet twice wraps each loader callback once', async w => {
  w.__wbeScriptletCalls = { 'trusted-spotify-ad-media': [[]] };
  w.eval(shipped);
  const content = await w.player.play('spotify:ad:abc', cdn, typedMP3);
  assert.equal(content._url, dataURI('audio/mp3', mp3));
  assert.equal(content.loads, 1);
});
