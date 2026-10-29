function youtubePlayerRequest() {
    // Safari can bypass JSON.stringify by encoding a body or constructing a Request.
    // Keep all three paths on the same request policy.
    'use strict';
    if (!['www.youtube.com', 'youtube.com'].includes(location.hostname)) return;
    const installed = Symbol.for('wBlock.youtubePlayerRequest');
    if (globalThis[installed]) return;
    Object.defineProperty(globalThis, installed, { value: true });
    const parse = JSON.parse.bind(JSON);
    const stringify = JSON.stringify.bind(JSON);
    const locked = Object.getOwnPropertyDescriptor(JSON, 'parse')?.writable === false;
    const excluded = () => /^\/(?:shorts(?:\/|$)|tv(?:\/|$))/.test(location.pathname);
    const mutate = data => {
        if (excluded() || !data || typeof data !== 'object') return false;
        const client = data.context?.client;
        const contexts = [data.playbackContext, data.playerRequest?.playbackContext]
            .filter(context => context?.contentPlaybackContext);
        if (!client || contexts.length === 0 || data.params?.startsWith('YAHI')) return false;
        const status = document.getElementById('movie_player')?.getPlayerResponse?.()?.playabilityStatus?.status;
        if (status === 'LOGIN_REQUIRED' || status === 'CONTENT_CHECK_REQUIRED') return false;
        if (locked) {
            if (client.clientName !== 'WEB') return false;
            client.clientScreen = 'CHANNEL';
        } else {
            if (client.clientScreen === 'CHANNEL') return false;
            data.params = 'eAFgAQ';
            if (data.playerRequest) data.playerRequest.params = 'eAFgAQ';
            for (const context of contexts) context.params = 'eAFgAQ';
        }
        for (const context of contexts) {
            context.contentPlaybackContext.lactMilliseconds = String(Date.now());
        }
        if (client.configInfo) delete client.configInfo.appInstallData;
        // The alternate playback context otherwise backs off in background tabs.
        try {
            Object.defineProperty(document, 'visibilityState', { get: () => 'visible', configurable: true });
        } catch (_) {}
        return true;
    };
    const editBody = body => {
        if (typeof body !== 'string' || !body.includes('"contentPlaybackContext"')) return body;
        try {
            const data = parse(body);
            return mutate(data) ? stringify(data) : body;
        } catch (_) { return body; }
    };
    const install = (owner, key, handler) => {
        try {
            if (typeof owner?.[key] === 'function') Reflect.set(owner, key, new Proxy(owner[key], handler));
        } catch (_) {}
    };
    install(JSON, 'stringify', {
        apply(target, self, args) {
            try { mutate(args[0]); } catch (_) {}
            return Reflect.apply(target, self, args);
        },
    });
    install(globalThis.TextEncoder?.prototype, 'encode', {
        apply(target, self, args) {
            args[0] = editBody(args[0]);
            return Reflect.apply(target, self, args);
        },
    });
    install(globalThis, 'Request', {
        construct(target, args, newTarget) {
            try {
                const url = new URL(args[0]?.url ?? args[0], location.href);
                if (url.origin === location.origin && url.pathname.startsWith('/youtubei/')) {
                    const body = args[1]?.body;
                    const edited = editBody(body);
                    if (edited !== body) args[1] = { ...args[1], body: edited };
                }
            } catch (_) {}
            return Reflect.construct(target, args, newTarget);
        },
    });
}
