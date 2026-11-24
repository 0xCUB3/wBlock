function youtubePlayerRequest() {
    // Safari can bypass JSON.stringify by encoding a body or constructing a Request.
    // Keep all three paths on the same request policy.
    'use strict';
    const mobile = location.hostname === 'm.youtube.com';
    if (!mobile && !['www.youtube.com', 'youtube.com'].includes(location.hostname)) return;
    const installed = Symbol.for('wBlock.youtubePlayerRequest');
    if (globalThis[installed]) return;
    Object.defineProperty(globalThis, installed, { value: true });
    const parse = JSON.parse.bind(JSON);
    const stringify = JSON.stringify.bind(JSON);
    const locked = Object.getOwnPropertyDescriptor(JSON, 'parse')?.writable === false;
    const excluded = () => /^\/(?:shorts(?:\/|$)|tv(?:\/|$))/.test(location.pathname);
    const isPremium = () =>
        globalThis.ytInitialData?.topbar?.desktopTopbarRenderer?.logo?.topbarLogoRenderer?.iconImage?.iconType === 'YOUTUBE_PREMIUM_LOGO'
        || document.getElementById?.('masthead')?.getAttribute?.('logo-type') === 'YOUTUBE_PREMIUM_LOGO';
    const unmuteVideoIds = new Set();
    let rewroteAnonymous = false;
    const rememberUnmute = videoId => {
        if (typeof videoId === 'string' && videoId) {
            unmuteVideoIds.delete(videoId);
            unmuteVideoIds.add(videoId);
            if (unmuteVideoIds.size > 32) {
                unmuteVideoIds.delete(unmuteVideoIds.values().next().value);
            }
        } else {
            rewroteAnonymous = true;
        }
    };
    const mutate = data => {
        if (excluded() || !data || typeof data !== 'object') return false;
        const client = data.context?.client;
        if (mobile) {
            if (location.pathname.startsWith('/embed/') || !client) return false;
            const contexts = [data.playbackContext, data.playerRequest?.playbackContext]
                .filter(context => context?.contentPlaybackContext && context.adPlaybackContext === undefined);
            if (!contexts.length) return false;
            const now = String(Date.now());
            for (const context of contexts) context.contentPlaybackContext.lactMilliseconds = now;
            return true;
        }
        if (isPremium()) return false;
        const contexts = [data.playbackContext, data.playerRequest?.playbackContext]
            .filter(context => context?.contentPlaybackContext);
        if (!client || contexts.length === 0 || data.params?.startsWith('YAHI')
            || data.playerRequest?.params?.startsWith('YAHI')) return false;
        const status = document.getElementById('movie_player')?.getPlayerResponse?.()?.playabilityStatus?.status;
        if (status === 'LOGIN_REQUIRED' || status === 'CONTENT_CHECK_REQUIRED') return false;
        if (locked) {
            if (client.clientName !== 'WEB') return false;
            client.clientScreen = 'CHANNEL';
        } else {
            if (client.clientScreen === 'CHANNEL') return false;
            const hadMuteParam = data.params === 'eAFgAQ' || data.playerRequest?.params === 'eAFgAQ';
            if (!hadMuteParam) rememberUnmute(data.videoId || data.playerRequest?.videoId);
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
            Object.defineProperty(document, 'visibilityState', {
                get: () => excluded() && document.hidden ? 'hidden' : 'visible', configurable: true,
            });
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
    // lactMilliseconds is time since the viewer's last input, so the mobile value
    // reads as decades idle and YouTube answers with an immediate "Video paused.
    // Continue watching?" prompt. Drop that prompt from the player responses.
    const dropIdlePrompt = data => {
        for (const response of [data, data?.playerResponse]) {
            const messages = response?.messages;
            if (Array.isArray(messages) && messages.some(message => message?.youThereRenderer)) {
                response.messages = messages.filter(message => !message?.youThereRenderer);
            }
        }
        return data;
    };
    // The eAFgAQ player parameter marks the request as an ad-free preview, so
    // YouTube answers with playerConfig.audioConfig.muteOnStart: true. Drop it
    // from player and get_watch responses for requests rewritten by this scriptlet.
    const dropMuteFromResponse = response => {
        const audioConfig = response?.playerConfig?.audioConfig;
        if (!audioConfig || !Object.hasOwn(audioConfig, 'muteOnStart')) return;
        const responseId = response?.videoDetails?.videoId;
        if (typeof responseId === 'string' && responseId ? unmuteVideoIds.has(responseId) : rewroteAnonymous) {
            delete audioConfig.muteOnStart;
        }
    };
    const dropMuteOnStart = data => {
        if (excluded() || (!rewroteAnonymous && unmuteVideoIds.size === 0) || !data || typeof data !== 'object') return data;
        if (Array.isArray(data)) {
            for (const item of data) {
                if (!item || typeof item !== 'object') continue;
                dropMuteFromResponse(item);
                if (item.playerResponse && typeof item.playerResponse === 'object') {
                    dropMuteFromResponse(item.playerResponse);
                }
            }
        } else {
            dropMuteFromResponse(data);
            if (data.playerResponse && typeof data.playerResponse === 'object') {
                dropMuteFromResponse(data.playerResponse);
            }
        }
        return data;
    };
    const onResponse = mobile ? dropIdlePrompt : dropMuteOnStart;
    install(JSON, 'parse', {
        apply(target, self, args) {
            const data = Reflect.apply(target, self, args);
            try { onResponse(data); } catch (_) {}
            return data;
        },
    });
    install(globalThis.Response?.prototype, 'json', {
        apply(target, self, args) {
            return Reflect.apply(target, self, args).then(data => {
                try { onResponse(data); } catch (_) {}
                return data;
            });
        },
    });
    try {
        const xhrProto = globalThis.XMLHttpRequest?.prototype;
        const xhrResponse = xhrProto && Object.getOwnPropertyDescriptor(xhrProto, 'response');
        if (xhrResponse?.get && xhrResponse.configurable) {
            Object.defineProperty(xhrProto, 'response', {
                configurable: true,
                enumerable: xhrResponse.enumerable,
                get() {
                    const data = xhrResponse.get.call(this);
                    if (this.responseType === 'json') {
                        try { onResponse(data); } catch (_) {}
                    }
                    return data;
                },
            });
        }
    } catch (_) {}
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
