import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../youtube-backoff-recovery.js', import.meta.url), 'utf8');
const shipped = readFileSync(new URL('../../../../wBlock Scripts (iOS)/Resources/scriptlets/trusted-youtube-backoff-recovery.js', import.meta.url), 'utf8');
function setup(readyState = 'loading') {
    let now = 0, next = 0;
    const timers = new Map(), listeners = new Map(), reloads = [];
    const media = { paused: false, currentTime: 0, readyState: 1 };
    const player = { getPlayerState: () => 3, querySelector: () => media };
    const context = vm.createContext({
        location: { hostname: 'www.youtube.com', search: '?v=video&t=12' },
        document: { readyState, querySelector: () => player }, URLSearchParams,
        setTimeout(fn, delay) { const id = ++next; timers.set(id, { fn, at: now + delay }); return id; },
        clearTimeout(id) { timers.delete(id); },
        Date: class extends Date { static now() { return now; } },
    });
    vm.runInContext('window = globalThis; originalCall = Function.prototype.call', context);
    context.addEventListener = (name, fn) => listeners.set(name, fn);
    const run = code => vm.runInContext(code, context);
    const install = () => run(process.env.WBLOCK_TEST_SHIPPED
        ? "globalThis.__wbeScriptletCalls = {'trusted-youtube-backoff-recovery': [[]]};\n" + shipped
        : source + '\nyoutubeBackoffRecovery()');
    const snapshot = value => { context.value = value; run('Reflect.apply(Function.prototype.call, function () {}, [{requestNumber: 1, snapshot: value}])'); };
    const ready = () => { context.document.readyState = 'interactive'; const fn = listeners.get('DOMContentLoaded'); listeners.delete('DOMContentLoaded'); fn?.(); };
    const advance = async ms => {
        const end = now + ms;
        while (true) {
            const entry = [...timers].sort((a, b) => a[1].at - b[1].at)[0];
            if (!entry || entry[1].at > end) break;
            timers.delete(entry[0]); now = entry[1].at; entry[1].fn(); await Promise.resolve();
        }
        now = end; await Promise.resolve();
    };
    const api = () => { player.loadVideoById = (...args) => reloads.push(args); };
    const resume = ms => {
        now += ms;
        for (const [id, timer] of [...timers]) if (timer.at <= now) { timers.delete(id); timer.fn(); }
    };
    return { run, install, snapshot, ready, advance, api, reloads, player, context, media, resume };
}

test('late installation times out its hook without restarting a video', async () => {
    const s = setup('complete'); s.api(); s.install();
    await s.advance(11000);
    assert.equal(s.run('Function.prototype.call === originalCall'), true);
    assert.deepEqual(s.reloads, []);
});
test('early recovery waits for the player API, not merely the element', async () => {
    const s = setup(); s.install(); s.ready(); await s.advance(400); s.api(); await s.advance(200);
    assert.deepEqual(s.reloads, [['video', 12]]);
});

test('early clean snapshot restores the original call and does not reload', async () => {
    const s = setup(); s.api(); s.install(); s.snapshot({ clean: true }); s.ready(); await s.advance(0);
    assert.equal(s.run('Function.prototype.call === originalCall'), true);
    assert.deepEqual(s.reloads, []);
});
test('early backoff and absent snapshots each recover once', async () => {
    for (const evidence of ['backoff', 'none']) {
        const s = setup(); s.api(); s.install(); s.install();
        if (evidence === 'backoff') s.snapshot({ backoffTimeMs: 1000 });
        s.ready(); await s.advance(0); s.install(); s.ready(); await s.advance(0);
        assert.equal(s.run('Function.prototype.call === originalCall'), true);
        assert.deepEqual(s.reloads, [['video', 12]]);
    }
});
test('late backoff recovers once, including when the API appears later', async () => {
    const s = setup('interactive'); s.install(); s.install(); s.snapshot({ backoffTimeMs: 1 });
    await s.advance(400); s.api(); await s.advance(200); s.install(); s.snapshot({ backoffTimeMs: 2 }); await s.advance(0);
    assert.equal(s.run('Function.prototype.call === originalCall'), true);
    assert.deepEqual(s.reloads, [['video', 12]]);
});
test('late clean and undefined backoff snapshots do not reload', async () => {
    for (const value of [{ clean: true }, { backoffTimeMs: undefined }]) {
        const s = setup('complete'); s.api(); s.install(); s.snapshot(value); await s.advance(11000);
        assert.equal(s.run('Function.prototype.call === originalCall'), true);
        assert.deepEqual(s.reloads, []);
    }
});
test('cleanup preserves a later wrapper and leaves its captured hook inert', async () => {
    for (const late of [false, true]) {
        const s = setup(late ? 'complete' : 'loading'); s.api(); s.install();
        s.run('capturedCall = Function.prototype.call; laterCall = new Proxy(capturedCall, { apply: (target, self, args) => Reflect.apply(target, self, args) }); Function.prototype.call = laterCall');
        if (late) await s.advance(11000); else { s.snapshot({ clean: true }); s.ready(); }
        assert.equal(s.run('Function.prototype.call === laterCall'), true);
        s.snapshot({ backoffTimeMs: 1 }); await s.advance(0);
        assert.deepEqual(s.reloads, []);
    }
});
test('early hook expires even if DOM ready never arrives', async () => {
    const s = setup(); s.install(); await s.advance(11000);
    assert.equal(s.run('Function.prototype.call === originalCall'), true);
});
test('a missing player API stops polling after the existing deadline', async () => {
    const s = setup('complete'); s.install(); s.snapshot({ backoffTimeMs: 1 }); await s.advance(11000); s.api(); await s.advance(1000);
    assert.deepEqual(s.reloads, []);
});

test('zero, negative and invalid backoffs are not recovery evidence', async () => {
    for (const value of [0, -1, '1000', NaN, Infinity, null]) {
        const s = setup(); s.api(); s.install(); s.snapshot({ backoffTimeMs: value }); s.ready();
        await s.advance(11000); assert.deepEqual(s.reloads, []);
    }
});
test('healthy, paused, ended, gated and replaced players are never restarted', async () => {
    const states = [
        { getPlayerState: () => 2 }, { getPlayerState: () => 0 },
        ...['LOGIN_REQUIRED', 'CONTENT_CHECK_REQUIRED', 'UNPLAYABLE'].map(status => ({
            getPlayerResponse: () => ({ playabilityStatus: { status } }),
        })),
        { getVideoData: () => ({ video_id: 'another-video' }) },
    ];
    for (const evidence of [true, false]) for (const player of states) {
        const s = setup(); s.api(); Object.assign(s.player, player); s.install();
        if (evidence) s.snapshot({ backoffTimeMs: 1000 });
        s.ready(); await s.advance(11000); assert.deepEqual(s.reloads, []);
    }
});
test('advancing media is not restarted even without player progress stats', async () => {
    const s = setup(); s.api();
    s.media.currentTime = 13;
    s.install(); s.ready(); await s.advance(11000); assert.deepEqual(s.reloads, []);
});
test('navigation before readiness or while waiting for the API cancels recovery', async () => {
    for (const duringPoll of [false, true]) {
        const s = setup(); s.install();
        if (duringPoll) { s.ready(); await s.advance(200); }
        s.context.location.search = '?v=another-video';
        s.api(); if (!duringPoll) s.ready();
        await s.advance(11000); assert.deepEqual(s.reloads, []);
    }
});
test('recovery preserves numeric and compound start times', async () => {
    for (const [time, seconds] of [['1m30s', 90], ['1h2m3s', 3723], ['90', 90], ['2.5', 2.5], ['oops', 0]]) {
        const s = setup(); s.context.location.search = '?v=video&t=' + time;
        s.api(); s.install(); s.ready(); await s.advance(0);
        assert.deepEqual(s.reloads, [['video', seconds]]);
    }
});

test('late backoff cannot rewind progressed but currently buffering media', async () => {
    const s = setup('complete'); s.api(); s.media.currentTime = 120;
    s.install(); s.snapshot({ backoffTimeMs: 10000 }); await s.advance(11000);
    assert.deepEqual(s.reloads, []);
});
test('cued, unstarted, paused and unknown media cannot acquire autoplay', async () => {
    for (const state of [-1, 5, undefined, 1, 3]) {
        const s = setup(); s.api(); s.player.getPlayerState = () => state; s.media.paused = true;
        s.install(); s.ready(); await s.advance(11000); assert.deepEqual(s.reloads, []);
    }
    const s = setup(); s.api(); s.player.getPlayerState = () => undefined;
    s.install(); s.ready(); await s.advance(11000); assert.deepEqual(s.reloads, []);
});
test('throwing snapshot getters do not intercept the original function', () => {
    const s = setup(); s.install();
    for (const name of ['requestNumber', 'snapshot']) {
        s.context.name = name;
        assert.equal(s.run(`var input = {requestNumber: 1, snapshot: {}};
            Object.defineProperty(input, name, {get() {throw Error('page getter')}});
            Reflect.apply(Function.prototype.call, function () {return 42}, [input]);`), 42);
    }
});
test('transient player getter failure retries without wedging installation', async () => {
    const s = setup(); s.api(); let failed = false;
    s.player.getPlayerResponse = () => { if (!failed) {failed = true; throw Error('not ready')} return {}; };
    s.install(); s.ready(); await s.advance(200); assert.deepEqual(s.reloads, [['video', 12]]);
});
test('an unrelated video or small static buffer cannot suppress initial recovery', async () => {
    const s = setup('complete'); s.api();
    s.player.getProgressState = () => ({ current: 0, loaded: 0.2 });
    s.context.document.querySelector = selector => selector === 'video'
        ? { paused: false, currentTime: 100, readyState: 4 } : s.player;
    s.install(); s.snapshot({ backoffTimeMs: 10000 }); await s.advance(0);
    assert.deepEqual(s.reloads, [['video', 12]]);
});
test('same-video timestamp navigation cancels pending recovery', async () => {
    const s = setup(); s.api(); s.install();
    s.context.location.search = '?v=video&t=90'; s.ready(); await s.advance(11000);
    assert.deepEqual(s.reloads, []);
});

test('a failed reload is attempted only once', async () => {
    const s = setup('complete'); let attempts = 0;
    s.player.loadVideoById = () => { attempts++; throw Error('reload failed'); };
    s.install(); s.snapshot({ backoffTimeMs: 1000 }); await s.advance(11000);
    assert.equal(attempts, 1);
});
test('a suspended poll cannot reload after its deadline', async () => {
    const s = setup('complete'); s.install(); s.snapshot({ backoffTimeMs: 1000 });
    await s.advance(0); s.api(); s.resume(60000);
    assert.deepEqual(s.reloads, []);
});

test('generated scriptlet observes late backoff and executes its queued call once', async () => {
    const s = setup('complete'); s.api();
    s.run("globalThis.__wbeScriptletCalls = {'trusted-youtube-backoff-recovery': [[], []]}");
    s.run(shipped); s.snapshot({ backoffTimeMs: 1 }); await s.advance(0);
    assert.equal(s.run('Function.prototype.call === originalCall'), true);
    assert.deepEqual(s.reloads, [['video', 12]]);
});
