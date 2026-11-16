function spotifyAdMedia() {
    // Spotify loads an ad track from its CDN after the player's content loader
    // sets `_url`. A blocked or redirected ad request leaves the player stuck, so
    // ad tracks get a silent in-page stand-in that makes no network request. The
    // player decides how it loads the track: a direct src takes the MP4 stand-in,
    // and a typed <source type="audio/mp3"> takes the MP3 one, since WebKit rejects
    // an MP4 under an audio MIME type. Songs and other pages are untouched.
    // From AdGuard Base (AdguardFilters, GPL-3.0).
    'use strict';
    if (location.hostname !== 'open.spotify.com') return;
    const key = Symbol.for('wBlock.spotifyAdMedia');
    if (window[key]) return;
    Object.defineProperty(window, key, { value: true });
    const then = Promise.prototype.then;
    // Returns null when the approach is unknown or declares another type, so that
    // load keeps its own URL. A thrown error leaves the URL alone as well.
    const standInFor = content => {
        let type;
        try {
            type = content.getLoadingApproach().type;
        } catch (_) {
            return null;
        }
        if (!type) return 'data:video/mp4;base64,__SILENT_MP4__';
        return type === 'audio/mp3' ? 'data:audio/mp3;base64,__SILENT_MP3__' : null;
    };
    Promise.prototype.then = new Proxy(then, {
        apply(target, self, args) {
            // The loader callback that caches the content is the one that names this call.
            if (typeof args[0] === 'function' && Function.prototype.toString.call(args[0]).includes('this._getCacheKey')) {
                const callback = args[0];
                args[0] = new Proxy(callback, {
                    apply(fn, thisArg, callArgs) {
                        const content = callArgs[0];
                        if (typeof content?._uri === 'string' && content._uri.startsWith('spotify:ad:') && content._url) {
                            const standIn = standInFor(content);
                            if (standIn) content._url = standIn;
                        }
                        return Reflect.apply(fn, thisArg, callArgs);
                    },
                });
            }
            return Reflect.apply(target, self, args);
        },
    });
}
