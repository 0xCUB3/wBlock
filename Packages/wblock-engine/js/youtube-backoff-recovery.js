function youtubeBackoffRecovery() {
    // When YouTube answers the first stream request with a backoff (an
    // ad-block penalty), the player sits with an empty buffer for several
    // seconds. Watch the stream snapshots for a `backoffTimeMs`, and if one
    // shows up (or none was seen at all), reload the video once the page is
    // ready, which starts a fresh stream right away.
    // From AdGuard Base (AdguardFilters, GPL-3.0), where it ships as a raw
    // `#%#` script that wBlock's engine does not run.
    'use strict';
    if (location.hostname !== 'www.youtube.com') return;
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
                if (obj.backoffTimeMs !== undefined) return true;
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
    window.Function.prototype.call = new Proxy(window.Function.prototype.call, {
        apply(target, thisArg, args) {
            const snapshot = args[0];
            if (snapshot?.requestNumber && snapshot?.snapshot) {
                try {
                    backoff = hasBackoff(snapshot);
                    sawSnapshot = true;
                    if (backoff || missing) Function.prototype.call = call;
                } catch (_) {}
            }
            return Reflect.apply(target, thisArg, args);
        },
    });
    window.addEventListener('DOMContentLoaded', async () => {
        Function.prototype.call = call;
        if (!backoff && sawSnapshot) return;
        const params = new URLSearchParams(location.search);
        const videoId = params.get('v');
        if (!videoId) return;
        const deadline = Date.now() + 10000;
        const player = await new Promise(resolve => {
            const poll = () => {
                const found = document.querySelector('#movie_player');
                if (found) resolve(found);
                else if (Date.now() > deadline) resolve(null);
                else setTimeout(poll, 200);
            };
            poll();
        });
        if (typeof player?.loadVideoById !== 'function') return;
        try { player.loadVideoById(videoId, parseInt(params.get('t') ?? '0', 10)); } catch (_) {}
    });
}
