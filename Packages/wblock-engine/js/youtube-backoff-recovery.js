function youtubeBackoffRecovery() {
    // Recover an idle initial player from a positive stream backoff. The
    // early-install fallback covers snapshots missed before DOM readiness.
    // From AdGuard Base (AdguardFilters, GPL-3.0), also used with uBO lists.
    'use strict';
    if (location.hostname !== 'www.youtube.com') return;
    const key = Symbol.for('wblock.youtubeBackoffRecovery');
    const state = window[key] || (window[key] = { active: false, reloaded: false });
    if (state.active || state.reloaded) return;
    state.active = true;
    const late = document.readyState !== 'loading';
    const params = new URLSearchParams(location.search);
    const videoId = params.get('v');
    const sameVideo = () => {
        const current = new URLSearchParams(location.search);
        return videoId && current.get('v') === videoId && current.get('t') === params.get('t')
            && current.get('start') === params.get('start')
            && !/^\/(?:shorts|tv|embed)(?:\/|$)/.test(location.pathname || '');
    };
    const call = Function.prototype.call;
    let sawSnapshot = false, backoff = false, missing = false;
    const hasBackoff = (root, maxDepth = 5) => {
        if (typeof root !== 'object' || root === null) return false;
        const stack = [{ obj: root, depth: 0 }];
        const seen = new WeakSet();
        while (stack.length && !missing) {
            const { obj, depth } = stack.pop();
            if (depth > maxDepth || typeof obj !== 'object' || obj === null || seen.has(obj)) continue;
            seen.add(obj);
            let own;
            try { own = Object.hasOwn(obj, 'backoffTimeMs'); } catch (_) {}
            if (own) {
                if (Number.isFinite(obj.backoffTimeMs) && obj.backoffTimeMs > 0) return true;
                missing = true;
                return false;
            }
            for (const key in obj) {
                if (!Object.hasOwn(obj, key)) continue;
                let value;
                try { value = obj[key]; } catch (_) {}
                if (value !== null && typeof value === 'object' && !seen.has(value) && stack.length < 1000) {
                    stack.push({ obj: value, depth: depth + 1 });
                }
            }
        }
        return false;
    };
    let watching = true;
    const stopWatching = () => {
        watching = false;
        clearTimeout(watchTimer);
        if (Function.prototype.call === hook) Function.prototype.call = call;
    };
    const hook = new Proxy(call, {
        apply(target, thisArg, args) {
            try {
                const snapshot = args[0];
                if (watching && snapshot?.requestNumber && snapshot?.snapshot) {
                    backoff = hasBackoff(snapshot);
                    sawSnapshot = true;
                    if (backoff || missing) {
                        stopWatching();
                        if (late) {
                            if (backoff) setTimeout(recover, 0);
                            else state.active = false;
                        }
                    }
                }
            } catch (_) {}
            return Reflect.apply(target, thisArg, args);
        },
    });
    const watchTimer = setTimeout(() => {
        stopWatching();
        if (late) state.active = false;
    }, 10000);
    window.Function.prototype.call = hook;
    const recover = () => {
        stopWatching();
        if ((!backoff && sawSnapshot) || (late && !backoff)) {
            state.active = false;
            return;
        }
        if (!sameVideo()) { state.active = false; return; }
        const time = params.get('t') || params.get('start') || '0';
        const parts = /^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$/.exec(time);
        const start = /^\d+(?:\.\d+)?$/.test(time) ? Number(time)
            : parts ? Number(parts[1] || 0) * 3600 + Number(parts[2] || 0) * 60 + Number(parts[3] || 0) : 0;
        const deadline = Date.now() + 10000;
        const poll = () => {
            if (state.reloaded || Date.now() >= deadline || !sameVideo()) { state.active = false; return; }
            try {
                const player = document.querySelector('#movie_player');
                if (typeof player?.loadVideoById === 'function') {
                    const status = player.getPlayerResponse?.()?.playabilityStatus?.status;
                    const playingId = player.getVideoData?.()?.video_id;
                    const playerState = player.getPlayerState?.();
                    const media = player.querySelector?.('video');
                    if ((status && status !== 'OK') || (playingId && playingId !== videoId)
                        || ![1, 3].includes(playerState) || !media || media.paused
                        || !Number.isFinite(media.currentTime) || media.currentTime > start + 0.1) {
                        state.active = false;
                        return;
                    }
                    state.reloaded = true;
                    state.active = false;
                    try { player.loadVideoById(videoId, start); } catch (_) {}
                    return;
                }
            } catch (_) {}
            if (Date.now() > deadline) state.active = false;
            else setTimeout(poll, 200);
        };
        poll();
    };
    if (!late) window.addEventListener('DOMContentLoaded', recover, { once: true });
}
