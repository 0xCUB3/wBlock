// ==UserScript==
// @name         Player Cleaner
// @namespace    com.skula.wblock
// @version      0.1.0
// @description  Gives custom web players native controls, auto PiP, background playback, restored subtitle and chapter tracks, Now Playing metadata, and remembered playback preferences.
// @description:de  Bietet Web-Playern native Steuerelemente, Auto-PiP, Hintergrundwiedergabe, wiederhergestellte Untertitel und Kapitel, Now-Playing-Metadaten und gespeicherte Wiedergabeeinstellungen.
// @description:es  Añade a los reproductores web controles nativos, PiP automático, reproducción en segundo plano, subtítulos y capítulos restaurados, metadatos Now Playing y preferencias recordadas.
// @description:fr  Ajoute aux lecteurs web les commandes natives, le PiP automatique, la lecture en arrière-plan, les sous-titres et chapitres restaurés, les métadonnées À l’écoute et les préférences mémorisées.
// @description:it  Aggiunge ai player web controlli nativi, PiP automatico, riproduzione in background, sottotitoli e capitoli ripristinati, metadati Now Playing e preferenze memorizzate.
// @description:pt-BR  Adiciona aos players web controles nativos, PiP automático, reprodução em segundo plano, legendas e capítulos restaurados, metadados Reproduzindo Agora e preferências lembradas.
// @description:ja  Webプレーヤーにネイティブコントロール、自動PiP、バックグラウンド再生、字幕とチャプターの復元、再生中メタデータ、記憶される再生設定を追加します。
// @description:ko  웹 플레이어에 네이티브 컨트롤, 자동 PIP, 백그라운드 재생, 자막과 챕터 복원, Now Playing 메타데이터 및 재생 환경설정 저장을 추가합니다.
// @description:ru  Добавляет веб-плеерам нативные элементы управления, авто-PiP, фоновое воспроизведение, восстановленные субтитры и главы, метаданные «Исполняется» и сохранение настроек.
// @description:zh-Hans  为网页播放器添加原生控件、自动画中画、后台播放、恢复的字幕和章节、正在播放元数据以及记忆的播放偏好。
// @author       wBlock
// @match        http://*/*
// @match        https://*/*
// @exclude      https://www.youtube.com/*
// @exclude      https://m.youtube.com/*
// @exclude      https://music.youtube.com/*
// @exclude      https://www.youtube-nocookie.com/*
// @noframes
// @run-at       document-start
// @inject-into  page
// @grant        none
// ==/UserScript==

(function () {
    'use strict';

    // ------------------------------------------------------------------
    // Player Cleaner
    //
    // Many sites wrap a perfectly good HTML5 <video> in a custom player
    // (video.js, JW Player, Plyr, Flowplayer, MediaElement, Clappr, ...)
    // whose chrome hides native controls and breaks Picture-in-Picture.
    // This script finds those players, resolves the underlying media source
    // where possible, and swaps in a clean native <video>. When the source
    // is an opaque media-source blob we instead enhance the existing video
    // in place so playback keeps working with native controls.
    //
    // Features:
    //   - Custom player detection & replacement (video.js, JW, Plyr, ...)
    //   - Auto PiP: enters PiP on tab switch or when scrolled out of view
    //   - Background playback: keeps playing in background tabs
    //   - iOS toolbar: hidden by default, shows on tap, auto-hides
    //
    // YouTube is excluded; Tube Cleaner handles it. Per-site disabling is
    // provided by wBlock's userscript site settings.
    // ------------------------------------------------------------------

    var LOG_PREFIX = '[Player Cleaner]';
    var ATTR_DONE = 'data-wblock-player-cleaner';
    var PREFERENCES_KEY = 'wblock.playerCleaner.preferences';
    var RESUME_KEY = 'wblock.playerCleaner.resume';

    // ------------------------------------------------------------------
    // Background playback — keep videos playing in background tabs
    // ------------------------------------------------------------------

    var _realHidden = false;
    var _realVisibility = 'visible';

    function findDocumentGetter(name) {
        try {
            var proto = document;
            while (proto) {
                var descriptor = Object.getOwnPropertyDescriptor(proto, name);
                if (descriptor && typeof descriptor.get === 'function') {
                    return descriptor.get;
                }
                proto = Object.getPrototypeOf(proto);
            }
        } catch (e) { /* ignore */ }
        return null;
    }

    // Capture the native getters before enableBackgroundPlayback() shadows the
    // properties on document. Reading document.hidden inside the later event
    // listener would otherwise always return our forced false value.
    var nativeHiddenGetter = findDocumentGetter('hidden');
    var nativeVisibilityGetter = findDocumentGetter('visibilityState');

    function updateRealVisibility() {
        try {
            _realHidden = nativeHiddenGetter ? nativeHiddenGetter.call(document) : document.hidden;
            _realVisibility = nativeVisibilityGetter ?
                nativeVisibilityGetter.call(document) : document.visibilityState;
        } catch (e) { /* ignore */ }
    }

    updateRealVisibility();
    document.addEventListener('visibilitychange', updateRealVisibility);

    function enableBackgroundPlayback() {
        if (loadPlaybackPreferences().backgroundPlayback === false) return;
        try {
            Object.defineProperty(document, 'hidden', {
                get: function () { return false; },
                configurable: true
            });
        } catch (e) { /* ignore */ }
        try {
            Object.defineProperty(document, 'visibilityState', {
                get: function () { return 'visible'; },
                configurable: true
            });
        } catch (e) { /* ignore */ }
    }

    // ------------------------------------------------------------------
    // Auto PiP — automatic Picture-in-Picture
    // ------------------------------------------------------------------

    var AUTO_PIP_KEY = 'wblock.playerCleaner.autoPiP';
    var autoPiPEnabled = true;

    function getAutoPiP() {
        try {
            var stored = localStorage.getItem(AUTO_PIP_KEY);
            return stored === null ? true : stored === '1';
        } catch (e) { return true; }
    }

    try { autoPiPEnabled = getAutoPiP(); } catch (e) { /* ignore */ }

    function isPiPActive(video) {
        return document.pictureInPictureElement === video ||
            (video && video.webkitPresentationMode === 'picture-in-picture');
    }

    function enterPiP(video) {
        if (!video || !autoPiPEnabled) return;
        if (isPiPActive(video)) return;
        if (video.paused || video.ended) return;
        try {
            if (video.webkitSupportsPresentationMode &&
                typeof video.webkitSetPresentationMode === 'function') {
                video.webkitSetPresentationMode('picture-in-picture');
            } else if (video.requestPictureInPicture) {
                video.requestPictureInPicture();
            }
        } catch (e) { /* ignore */ }
    }

    function exitPiP(video) {
        if (!video) return;
        if (!isPiPActive(video)) return;
        try {
            if (video.webkitSupportsPresentationMode &&
                typeof video.webkitSetPresentationMode === 'function') {
                video.webkitSetPresentationMode('inline');
            } else if (document.pictureInPictureElement) {
                document.exitPictureInPicture();
            }
        } catch (e) { /* ignore */ }
    }

    function registerVideoCleanup(video, cleanup) {
        if (!video._wblockCleanups) { video._wblockCleanups = []; }
        video._wblockCleanups.push(cleanup);
    }

    function releaseVideoResources(video) {
        if (!video) return;
        var cleanups = video._wblockCleanups || [];
        video._wblockCleanups = [];
        for (var i = 0; i < cleanups.length; i++) {
            try { cleanups[i](); } catch (e) { /* ignore */ }
        }
        video._wblockAutoPiPHooked = false;
        video._wblockControlsGuarded = false;
        video._wblockControlsPatched = false;
        video._wblockEnhanced = false;
        video._wblockUpgradeable = false;
        video._wblockCleaned = false;
        video._wblockPreferencesHooked = false;
        video._wblockMediaSessionHooked = false;
        try { video.removeAttribute(ATTR_DONE); } catch (e) { /* ignore */ }
    }

    function setupAutoPiP(video) {
        if (!video || video._wblockAutoPiPHooked) return;
        video._wblockAutoPiPHooked = true;

        function onVisibilityChange() {
            if (!autoPiPEnabled) return;
            if (_realHidden) {
                if (!video.paused && !video.ended) { enterPiP(video); }
            } else if (document.hasFocus() && isPiPActive(video)) {
                exitPiP(video);
            }
        }

        // Window focus alone cannot tell whether another macOS window covers
        // Safari, so blur must not trigger PiP. Actual tab hiding and viewport
        // intersection changes provide reliable signals.
        function onFocus() {
            if (!autoPiPEnabled || _realHidden) return;
            if (document.hasFocus() && isPiPActive(video)) { exitPiP(video); }
        }

        document.addEventListener('visibilitychange', onVisibilityChange);
        window.addEventListener('focus', onFocus);
        registerVideoCleanup(video, function () {
            document.removeEventListener('visibilitychange', onVisibilityChange);
            window.removeEventListener('focus', onFocus);
        });

        if (typeof IntersectionObserver !== 'undefined') {
            var scrollObserver = new IntersectionObserver(function (entries) {
                if (!autoPiPEnabled) return;
                entries.forEach(function (entry) {
                    if (!entry.isIntersecting && !video.paused && !video.ended) {
                        enterPiP(video);
                    } else if (entry.isIntersecting && isPiPActive(video)) {
                        exitPiP(video);
                    }
                });
            }, { threshold: 0.1 });
            scrollObserver.observe(video);
            registerVideoCleanup(video, function () {
                try { scrollObserver.disconnect(); } catch (e) { /* ignore */ }
            });
        }
    }

    function log() {
        try {
            if (window.__wblockPlayerCleanerDebug) {
                console.log.apply(console, [LOG_PREFIX].concat([].slice.call(arguments)));
            }
        } catch (e) { /* ignore */ }
    }

    // Player container selectors for the common custom-player libraries.
    var PLAYER_SELECTORS = [
        '.video-js',                 // video.js
        '.vjs-tech',                 // video.js (inner tech, handled via parent)
        '.jwplayer',                 // JW Player
        '.jw-wrapper',               // JW Player
        '.plyr',                     // Plyr
        '.flowplayer',               // Flowplayer
        '.mejs-container',           // MediaElement.js
        '.mejs__container',          // MediaElement.js (newer)
        '.clappr',                   // Clappr
        '[data-clappr-player]',      // Clappr
        '.hlsjs',                    // hls.js wrappers
        '.fluid_video_wrapper',      // Fluid Player
        '.fp-player',                // Flowplayer (inner)
        'mux-player',                // Mux Player custom element
        'media-controller',          // Media Chrome
        'media-theme',               // Media Chrome generic theme
        'media-theme-youtube',       // Media Chrome YouTube theme
        '.media-player',             // Media Chrome / modern wrappers
        '.media-default-skin'        // videojs.org's modern demo wrapper
    ];
    var PLAYER_SELECTOR = PLAYER_SELECTORS.join(',');

    function isHttpUrl(value) {
        return typeof value === 'string' && /^https?:\/\//i.test(value);
    }

    function isPlayableUrl(value) {
        if (!isHttpUrl(value)) { return false; }
        // Safari does not natively play MPEG-DASH manifests. Replacing a working
        // MSE/blob pipeline with its .mpd URL breaks playback; leave it enhanced
        // in place instead. Other extensionless player-API URLs remain allowed.
        try {
            var pathname = new URL(value).pathname.toLowerCase();
            if (/\.mpd$/.test(pathname)) { return false; }
        } catch (e) { /* keep the already-validated http(s) URL */ }
        return true;
    }

    function isLikelyMediaUrl(value) {
        if (!isPlayableUrl(value)) { return false; }
        try {
            return /\.(?:mp4|m4v|mov|webm|ogv|ogg|m3u8|mp3|m4a|aac|wav|flac|opus|ts)$/i
                .test(new URL(value).pathname);
        } catch (e) { return false; }
    }

    function looksLikeUrlValue(value) {
        if (typeof value !== 'string') { return false; }
        var raw = value.trim();
        return /^(?:https?:)?\/\//i.test(raw) || /^(?:\/|\.\/|\.\.\/)/.test(raw) ||
            /[.?&=]/.test(raw);
    }

    // Resolve a candidate media URL to an absolute http(s) URL. Many players
    // (e.g. archive.org's JW Player) expose root-relative or protocol-relative
    // URLs like "/download/item/movie.mp4". The browser only auto-resolves URLs
    // it loads itself, not JS strings or data-attributes, so resolve them
    // against the document base here. Returns null for empty/non-http(s) values
    // (blob:, data:, javascript:, ...).
    function toAbsoluteUrl(value) {
        if (typeof value !== 'string') { return null; }
        var v = value.trim();
        if (!v) { return null; }
        if (isHttpUrl(v)) { return v; }
        try {
            var resolved = new URL(v, document.baseURI).href;
            return isHttpUrl(resolved) ? resolved : null;
        } catch (e) { return null; }
    }

    // ------------------------------------------------------------------
    // Playback preferences, native tracks, and system media integration
    // ------------------------------------------------------------------

    function loadPlaybackPreferences() {
        // Null media values mean "preserve the site's current state" until the
        // user changes that control in a cleaned player for the first time.
        var defaults = { playbackRate: null, volume: null, muted: null,
            subtitleLanguage: '', backgroundPlayback: true };
        try {
            var saved = JSON.parse(localStorage.getItem(PREFERENCES_KEY) || '{}');
            for (var key in saved) if (Object.prototype.hasOwnProperty.call(defaults, key)) defaults[key] = saved[key];
        } catch (e) { /* use defaults */ }
        return defaults;
    }

    function savePlaybackPreference(key, value) {
        try {
            var preferences = loadPlaybackPreferences();
            preferences[key] = value;
            localStorage.setItem(PREFERENCES_KEY, JSON.stringify(preferences));
        } catch (e) { /* ignore */ }
    }

    function resumeIdentity(video) {
        var pageIdentity = location.origin + location.pathname + location.search;
        try {
            var canonical = document.querySelector('link[rel="canonical"]');
            if (canonical && canonical.href) pageIdentity = canonical.href;
        } catch (e) { /* ignore */ }
        // Distinguish multiple independent players on one page without retaining
        // expiring CDN signatures or query tokens. Opaque MSE streams fall back
        // to the canonical page URL, which is normally their stable identity.
        try {
            var source = sourceFromVideoElement(video);
            if (source && source.indexOf('blob:') !== 0) {
                var parsed = new URL(source, location.href);
                return pageIdentity + '|' + parsed.origin + parsed.pathname;
            }
        } catch (e) { /* ignore */ }
        return pageIdentity;
    }

    function setupPlaybackPreferences(video) {
        if (!video || video._wblockPreferencesHooked) return;
        video._wblockPreferencesHooked = true;
        var preferences = loadPlaybackPreferences();
        var applying = true;
        var lastResumeSave = 0;
        var resumeApplied = false;

        if (typeof preferences.playbackRate === 'number' && preferences.playbackRate > 0) try {
            video.playbackRate = Math.max(0.25, Math.min(4, preferences.playbackRate));
        } catch (e) { /* ignore */ }
        if (typeof preferences.volume === 'number') try {
            video.volume = Math.max(0, Math.min(1, preferences.volume));
        } catch (e) { /* ignore */ }
        if (typeof preferences.muted === 'boolean') try { video.muted = preferences.muted; } catch (e) { /* ignore */ }
        setTimeout(function () { applying = false; }, 0);

        function applySubtitlePreference() {
            var language = loadPlaybackPreferences().subtitleLanguage;
            if (!language || !video.textTracks) return;
            for (var i = 0; i < video.textTracks.length; i++) {
                var track = video.textTracks[i];
                if (track.kind !== 'subtitles' && track.kind !== 'captions') continue;
                if (track.language === language) {
                    try { track.mode = 'showing'; } catch (e) { /* ignore */ }
                    return;
                }
            }
        }

        function restoreResumePosition() {
            if (resumeApplied || !isFinite(video.duration) || video.duration < 60) return;
            resumeApplied = true;
            try {
                var entries = JSON.parse(localStorage.getItem(RESUME_KEY) || '{}');
                var position = Number(entries[resumeIdentity(video)] || 0);
                if (position > 10 && position < video.duration - 15) video.currentTime = position;
            } catch (e) { /* ignore */ }
            applySubtitlePreference();
        }

        function saveResumePosition(force) {
            var now = Date.now();
            if (!force && now - lastResumeSave < 5000) return;
            lastResumeSave = now;
            try {
                var entries = JSON.parse(localStorage.getItem(RESUME_KEY) || '{}');
                var id = resumeIdentity(video);
                if (video.ended || video.currentTime >= video.duration - 10) delete entries[id];
                else if (video.currentTime > 10 && isFinite(video.duration) && video.duration >= 60) entries[id] = Math.floor(video.currentTime);
                var keys = Object.keys(entries);
                while (keys.length > 50) delete entries[keys.shift()];
                localStorage.setItem(RESUME_KEY, JSON.stringify(entries));
            } catch (e) { /* ignore */ }
        }

        function onRateChange() { if (!applying) savePlaybackPreference('playbackRate', video.playbackRate); }
        function onVolumeChange() {
            if (applying) return;
            savePlaybackPreference('volume', video.volume);
            savePlaybackPreference('muted', video.muted);
        }
        function onTextTrackChange() {
            for (var i = 0; i < video.textTracks.length; i++) {
                var track = video.textTracks[i];
                if ((track.kind === 'subtitles' || track.kind === 'captions') && track.mode === 'showing') {
                    savePlaybackPreference('subtitleLanguage', track.language || '');
                    return;
                }
            }
        }

        video.addEventListener('loadedmetadata', restoreResumePosition);
        video.addEventListener('durationchange', restoreResumePosition);
        video.addEventListener('ratechange', onRateChange);
        video.addEventListener('volumechange', onVolumeChange);
        function onPauseOrEnded() { saveResumePosition(true); }
        video.addEventListener('timeupdate', saveResumePosition);
        video.addEventListener('pause', onPauseOrEnded);
        video.addEventListener('ended', onPauseOrEnded);
        if (video.textTracks) video.textTracks.addEventListener('change', onTextTrackChange);
        restoreResumePosition();
        registerVideoCleanup(video, function () {
            saveResumePosition(true);
            video.removeEventListener('loadedmetadata', restoreResumePosition);
            video.removeEventListener('durationchange', restoreResumePosition);
            video.removeEventListener('ratechange', onRateChange);
            video.removeEventListener('volumechange', onVolumeChange);
            video.removeEventListener('timeupdate', saveResumePosition);
            video.removeEventListener('pause', onPauseOrEnded);
            video.removeEventListener('ended', onPauseOrEnded);
            if (video.textTracks) video.textTracks.removeEventListener('change', onTextTrackChange);
        });
    }

    function appendNativeTrack(video, definition) {
        if (!definition) return;
        var source = toAbsoluteUrl(definition.src || definition.file);
        if (!source || !isHttpUrl(source)) return;
        var kind = String(definition.kind || 'subtitles').toLowerCase();
        if (kind === 'captions') kind = 'subtitles';
        if (kind !== 'subtitles' && kind !== 'chapters' && kind !== 'descriptions') return;
        var existing = video.querySelectorAll('track');
        for (var i = 0; i < existing.length; i++) if (existing[i].src === source) return;
        var track = document.createElement('track');
        track.kind = kind;
        track.src = source;
        track.label = definition.label || definition.name || definition.srclang || definition.language || kind;
        if (definition.srclang || definition.language) track.srclang = definition.srclang || definition.language;
        if (definition.default) track.default = true;
        video.appendChild(track);
    }

    function recoverSidecarTracks(container, video) {
        if (!container || !video) return;
        try {
            var domTracks = container.querySelectorAll('track[src]');
            for (var i = 0; i < domTracks.length; i++) {
                if (domTracks[i].parentNode !== video) appendNativeTrack(video, {
                    src: domTracks[i].src, kind: domTracks[i].kind, label: domTracks[i].label,
                    srclang: domTracks[i].srclang, default: domTracks[i].default
                });
            }
        } catch (e) { /* ignore */ }
        try {
            if (window.jwplayer) {
                var jw = window.jwplayer(container.id || container);
                var item = jw && jw.getPlaylistItem ? jw.getPlaylistItem() : null;
                var tracks = item && item.tracks || [];
                for (var j = 0; j < tracks.length; j++) appendNativeTrack(video, tracks[j]);
            }
        } catch (e) { /* ignore */ }
        try {
            if (window.videojs && window.videojs.getPlayers) {
                var players = window.videojs.getPlayers();
                for (var id in players) {
                    var player = players[id];
                    var element = player && player.el ? player.el() : null;
                    if (!element || !(container.contains(element) || element.contains(container))) continue;
                    var source = player.currentSource ? player.currentSource() : null;
                    var tracks = source && source.tracks || player.options_ && player.options_.tracks || [];
                    for (var k = 0; k < tracks.length; k++) appendNativeTrack(video, tracks[k]);
                }
            }
        } catch (e) { /* ignore */ }
    }

    var mediaSessionOwner = null;

    function setupMediaSession(container, video) {
        if (!video || video._wblockMediaSessionHooked || !navigator.mediaSession || typeof MediaMetadata === 'undefined') return;
        video._wblockMediaSessionHooked = true;
        function meta(name) {
            var element = document.querySelector('meta[property="' + name + '"],meta[name="' + name + '"]');
            return element && element.content || '';
        }
        function activate() {
            if (navigator.mediaSession.metadata && mediaSessionOwner !== video) return;
            mediaSessionOwner = video;
            var title = meta('og:title') || document.title || location.hostname;
            var artist = meta('og:site_name') || location.hostname;
            var artworkURL = video.poster || meta('og:image');
            var data = { title: title, artist: artist };
            if (artworkURL) data.artwork = [{ src: artworkURL }];
            try {
                video._wblockMediaMetadata = new MediaMetadata(data);
                navigator.mediaSession.metadata = video._wblockMediaMetadata;
            } catch (e) { /* ignore */ }
            var actions = {
                play: function () {
                    var request = video.play();
                    if (request && request.catch) request.catch(function () {});
                },
                pause: function () { video.pause(); },
                seekbackward: function (details) { video.currentTime = Math.max(0, video.currentTime - (details.seekOffset || 10)); },
                seekforward: function (details) { video.currentTime = Math.min(video.duration || Infinity, video.currentTime + (details.seekOffset || 10)); },
                seekto: function (details) { if (isFinite(details.seekTime)) video.currentTime = details.seekTime; }
            };
            try {
                var jw = window.jwplayer && window.jwplayer(container.id || container);
                var playlist = jw && jw.getPlaylist ? jw.getPlaylist() : null;
                if (playlist && playlist.length > 1 && typeof jw.playlistItem === 'function' &&
                    typeof jw.getPlaylistIndex === 'function') {
                    actions.previoustrack = function () { jw.playlistItem(Math.max(0, jw.getPlaylistIndex() - 1)); };
                    actions.nexttrack = function () { jw.playlistItem(Math.min(playlist.length - 1, jw.getPlaylistIndex() + 1)); };
                }
            } catch (e) { /* no JW playlist */ }
            try {
                if (!actions.nexttrack && window.videojs && window.videojs.getPlayers) {
                    var players = window.videojs.getPlayers();
                    for (var id in players) {
                        var candidate = players[id];
                        var element = candidate && candidate.el ? candidate.el() : null;
                        if (!element || !(container.contains(element) || element.contains(container)) || !candidate.playlist) continue;
                        if (typeof candidate.playlist.previous === 'function') actions.previoustrack = function () { candidate.playlist.previous(); };
                        if (typeof candidate.playlist.next === 'function') actions.nexttrack = function () { candidate.playlist.next(); };
                        break;
                    }
                }
            } catch (e) { /* no video.js playlist plugin */ }
            video._wblockMediaActions = Object.keys(actions);
            for (var action in actions) try { navigator.mediaSession.setActionHandler(action, actions[action]); } catch (e) { /* unsupported action */ }
        }
        function updatePosition() {
            if (mediaSessionOwner !== video || !navigator.mediaSession.setPositionState) return;
            if (isFinite(video.duration) && video.duration > 0) try {
                navigator.mediaSession.setPositionState({ duration: video.duration,
                    playbackRate: video.playbackRate || 1,
                    position: Math.max(0, Math.min(video.currentTime, video.duration)) });
            } catch (e) { /* ignore transient media state */ }
        }
        video.addEventListener('play', activate);
        video.addEventListener('timeupdate', updatePosition);
        video.addEventListener('ratechange', updatePosition);
        if (!video.paused) activate();
        registerVideoCleanup(video, function () {
            video.removeEventListener('play', activate);
            video.removeEventListener('timeupdate', updatePosition);
            video.removeEventListener('ratechange', updatePosition);
            if (mediaSessionOwner === video) {
                mediaSessionOwner = null;
                try {
                    if (navigator.mediaSession.metadata === video._wblockMediaMetadata)
                        navigator.mediaSession.metadata = null;
                } catch (e) { /* ignore */ }
                video._wblockMediaMetadata = null;
                (video._wblockMediaActions || []).forEach(function (action) {
                    try { navigator.mediaSession.setActionHandler(action, null); } catch (e) { /* ignore */ }
                });
                video._wblockMediaActions = null;
            }
        });
    }

    // ------------------------------------------------------------------
    // Source discovery
    // ------------------------------------------------------------------

    function sourceFromVideoElement(video) {
        try {
            if (isPlayableUrl(video.currentSrc)) { return video.currentSrc; }
            if (isPlayableUrl(video.src) && video.src.indexOf('blob:') !== 0) { return video.src; }
            var sources = video.getElementsByTagName('source');
            for (var i = 0; i < sources.length; i++) {
                var type = (sources[i].getAttribute('type') || '').toLowerCase();
                if (type.indexOf('dash') !== -1) { continue; }
                var src = toAbsoluteUrl(sources[i].getAttribute('src'));
                if (isPlayableUrl(src)) { return src; }
            }
        } catch (e) { /* ignore */ }
        return null;
    }

    function sourceFromDom(container) {
        try {
            // Data attributes commonly used to hold the media URL.
            var candidates = container.querySelectorAll('[data-src],[data-video-src],[data-file],[data-video],[data-source],[data-url]');
            var attrs = ['data-src', 'data-video-src', 'data-file', 'data-video', 'data-source', 'data-url'];
            for (var i = 0; i < candidates.length; i++) {
                for (var a = 0; a < attrs.length; a++) {
                    var raw = candidates[i].getAttribute(attrs[a]);
                    var value = toAbsoluteUrl(raw);
                    if (!isPlayableUrl(value)) { continue; }
                    // Generic data-src/data-url commonly point to poster images.
                    // Require a media-looking extension there; media-specific
                    // attributes may use extensionless CDN endpoints but must at
                    // least look URL-like rather than being a player/video ID.
                    var generic = attrs[a] === 'data-src' || attrs[a] === 'data-url';
                    if (generic ? isLikelyMediaUrl(value) : looksLikeUrlValue(raw)) {
                        return value;
                    }
                }
            }
            var directAttrs = ['data-src', 'data-file', 'data-video-src'];
            for (var d = 0; d < directAttrs.length; d++) {
                var directRaw = container.getAttribute(directAttrs[d]);
                var direct = toAbsoluteUrl(directRaw);
                var directGeneric = directAttrs[d] === 'data-src';
                if (isPlayableUrl(direct) &&
                    (directGeneric ? isLikelyMediaUrl(direct) : looksLikeUrlValue(directRaw))) {
                    return direct;
                }
            }
        } catch (e) { /* ignore */ }
        return null;
    }

    function sourceFromVideojs(container) {
        try {
            if (!window.videojs) { return null; }
            var players = window.videojs.getPlayers ? window.videojs.getPlayers() : {};
            for (var id in players) {
                var player = players[id];
                if (!player) { continue; }
                try {
                    var el = player.el ? player.el() : null;
                    if (el && (container.contains(el) || el.contains(container))) {
                        var current = player.currentSource ? player.currentSource() : null;
                        var currentSrc = current ? toAbsoluteUrl(current.src) : null;
                        if (currentSrc && isPlayableUrl(currentSrc)) { return currentSrc; }
                        var list = player.currentSources ? player.currentSources() : [];
                        for (var i = 0; i < list.length; i++) {
                            var listSrc = toAbsoluteUrl(list[i].src);
                            if (isPlayableUrl(listSrc)) { return listSrc; }
                        }
                    }
                } catch (e) { /* keep looking */ }
            }
        } catch (e) { /* ignore */ }
        return null;
    }

    function sourceFromJwPlayer(container) {
        try {
            if (!window.jwplayer) { return null; }
            var instance = window.jwplayer(container.id || container);
            if (!instance) { return null; }
            var item = instance.getPlaylistItem ? instance.getPlaylistItem() : null;
            if (item) {
                var file = toAbsoluteUrl(item.file);
                if (isPlayableUrl(file)) { return file; }
                var sources = item.sources || [];
                for (var i = 0; i < sources.length; i++) {
                    var sfile = toAbsoluteUrl(sources[i].file);
                    if (isPlayableUrl(sfile)) { return sfile; }
                }
            }
        } catch (e) { /* ignore */ }
        return null;
    }

    // ------------------------------------------------------------------
    // Replacement
    // ------------------------------------------------------------------

    function normalizeContainer(raw) {
        // Some selectors match inner elements; climb to the outermost player
        // wrapper so we replace the whole custom chrome, not just part of it.
        var container = raw;
        var wrapperSelectors = ['.video-js', '.jwplayer', '.jw-wrapper', '.plyr',
            '.flowplayer', '.mejs-container', '.mejs__container', '.clappr',
            '[data-clappr-player]', '.fluid_video_wrapper', 'mux-player',
            'media-controller', 'media-theme', 'media-theme-youtube',
            '.media-player', '.media-default-skin'];
        for (var i = 0; i < wrapperSelectors.length; i++) {
            var ancestor = container.closest ? container.closest(wrapperSelectors[i]) : null;
            if (ancestor) { container = ancestor; }
        }
        return container;
    }

    function forceNativeControls(video) {
        if (video._wblockControlsPatched) return;
        video._wblockControlsPatched = true;
        video.controls = true;
        video.setAttribute('controls', '');
    }

    // WebKit renders native controls from the `controls` content attribute.
    // Do not shadow the media element's controls property with a non-configurable
    // instance descriptor: doing that before WebKit initializes its native media
    // controls can break the controls implementation itself. Observe the content
    // attribute instead; MutationObserver restores it at the pre-paint microtask
    // checkpoint whenever a custom player removes it.
    function guardNativeControls(video) {
        if (!video || video._wblockControlsGuarded) return;
        video._wblockControlsGuarded = true;

        function restore() {
            if (video && !video.hasAttribute('controls')) {
                video.setAttribute('controls', '');
            }
        }

        var observer = null;
        try {
            observer = new MutationObserver(restore);
            observer.observe(video, { attributes: true, attributeFilter: ['controls'] });
        } catch (e) { /* ignore */ }

        restore();
        registerVideoCleanup(video, function () {
            if (observer) {
                try { observer.disconnect(); } catch (e) { /* ignore */ }
            }
        });
    }

    // Generic chrome hiding. Instead of maintaining a per-library selector list
    // (which inevitably misses bespoke players), walk every element inside the
    // container and hide anything that is not the video, an ancestor of the
    // video (needed for layout), or a descendant of the video (<source>,
    // <track>).  In "aggressive" mode all such chrome is hidden; this is safe
    // when the container is a known player wrapper or has its own positioning
    // context (position !== 'static'), both strong signals that the element is
    // a dedicated player shell rather than a general-purpose page wrapper.
    // In conservative mode only positioned (absolute / fixed / sticky) elements
    // are hidden, which covers the vast majority of overlay-style custom
    // controls while leaving flow-layout page content intact.
    function hideContainerChrome(container, video, aggressive) {
        if (!container || !container.querySelectorAll) return;
        var elements = container.querySelectorAll('*');
        for (var i = 0; i < elements.length; i++) {
            var el = elements[i];
            if (el === video) continue;
            if (video.contains(el)) continue;   // <source>, <track>
            if (el.contains(video)) continue;   // ancestor wrappers
            if (aggressive) {
                try { el.style.display = 'none'; } catch (e) { /* ignore */ }
            } else {
                try {
                    var pos = getComputedStyle(el).position;
                    if (pos === 'absolute' || pos === 'fixed' || pos === 'sticky') {
                        el.style.display = 'none';
                    }
                } catch (e) { /* ignore */ }
            }
        }
    }

    // Determine whether a container is a dedicated player shell (aggressive
    // hiding is safe) or might be a general-purpose wrapper (conservative only).
    function isPlayerShell(container) {
        if (container.matches && container.matches(PLAYER_SELECTOR)) return true;
        try {
            return getComputedStyle(container).position !== 'static';
        } catch (e) { return false; }
    }

    function enhanceInPlace(container, video, upgradeable) {
        if (video._wblockEnhanced) {
            // A video can first appear as a bare custom player and later be
            // wrapped by a known library. Promote it so source discovery may
            // still clean the known wrapper when its API/data arrives. Re-hide
            // chrome a framework may have rendered after initial cleanup.
            if (upgradeable) { video._wblockUpgradeable = true; }
            hideContainerChrome(container, video, isPlayerShell(container));
            return;
        }
        video._wblockEnhanced = true;
        // Upgradeable videos get one more replacement chance once their metadata
        // (and therefore currentSrc) has loaded; see onLoadedMetadata. Bare
        // videos enhanced under unknown chrome are not upgradeable, so their
        // wrapper layout is preserved.
        video._wblockUpgradeable = !!upgradeable;
        // We could not resolve a clean source (opaque MSE blob). Keep the
        // existing video playing but expose native controls + PiP and remove
        // obvious custom control overlays.
        try {
            forceNativeControls(video);
            video.playsInline = true;
            video.setAttribute('playsinline', '');
            video.removeAttribute('disablepictureinpicture');
            video.disablePictureInPicture = false;
        } catch (e) { /* ignore */ }

        recoverSidecarTracks(container, video);
        setupAutoPiP(video);
        setupPlaybackPreferences(video);
        setupMediaSession(container, video);

        hideContainerChrome(container, video, isPlayerShell(container));

        // Keep controls forced on
        guardNativeControls(video);
    }

    function capturePlaybackState(video) {
        var state = { paused: true, currentTime: 0, volume: 1, muted: false, playbackRate: 1 };
        try { state.paused = video.paused; } catch (e) { /* ignore */ }
        try { state.currentTime = video.currentTime || 0; } catch (e) { /* ignore */ }
        try { state.volume = video.volume; } catch (e) { /* ignore */ }
        try { state.muted = video.muted; } catch (e) { /* ignore */ }
        try { state.playbackRate = video.playbackRate || 1; } catch (e) { /* ignore */ }
        return state;
    }

    function restorePlaybackState(video, state, sourceChanged) {
        try { video.volume = state.volume; } catch (e) { /* ignore */ }
        try { video.muted = state.muted; } catch (e) { /* ignore */ }
        try { video.playbackRate = state.playbackRate; } catch (e) { /* ignore */ }

        function restorePositionAndPlayback() {
            if (state.currentTime > 0) {
                try { video.currentTime = state.currentTime; } catch (e) { /* ignore */ }
            }
            if (!state.paused) {
                try {
                    var result = video.play();
                    if (result && result.catch) { result.catch(function () {}); }
                } catch (e) { /* ignore */ }
            }
        }

        if (sourceChanged && video.readyState < 1) {
            video.addEventListener('loadedmetadata', restorePositionAndPlayback, { once: true });
        } else {
            restorePositionAndPlayback();
        }
    }

    function cleanPlayer(container, video, src) {
        if (video._wblockCleaned) { return; }
        var state = capturePlaybackState(video);
        // If the browser is already playing a direct source, retain it exactly:
        // changing src would discard buffered media, selected tracks, and time.
        // API/data-attribute discovery is used only when the element itself still
        // has no direct http(s) source (typically an opaque placeholder blob).
        var elementSource = sourceFromVideoElement(video);
        var sourceChanged = !elementSource && !!src;

        // Detach and reinsert the SAME media element. Creating a replacement
        // element causes another network load and a visible blank/buffering gap.
        // Keeping the original also preserves captions and any MSE pipeline.
        try { video.remove(); } catch (e) {
            try { if (video.parentNode) { video.parentNode.removeChild(video); } } catch (e2) { /* ignore */ }
        }
        while (container.firstChild) { container.removeChild(container.firstChild); }
        container.appendChild(video);
        if (sourceChanged) {
            try { video.src = src; } catch (e) { /* ignore */ }
        }

        video._wblockCleaned = true;
        video._wblockUpgradeable = false;
        video.setAttribute(ATTR_DONE, '1');
        container.setAttribute(ATTR_DONE, '1');
        try {
            container.classList.remove('video-js', 'vjs-paused', 'vjs-playing');
        } catch (e) { /* ignore */ }
        video.style.width = '100%';
        video.style.height = '100%';
        video.style.background = '#000';
        forceNativeControls(video);
        recoverSidecarTracks(container, video);
        setupAutoPiP(video);
        setupPlaybackPreferences(video);
        setupMediaSession(container, video);
        guardNativeControls(video);
        restorePlaybackState(video, state, sourceChanged);
    }

    function replacePlayer(container, allowExternalDiscovery) {
        var video = container.querySelector ? container.querySelector('video') : null;
        if (!video) { return; }
        if (video._wblockCleaned) {
            hideContainerChrome(container, video, isPlayerShell(container));
            return;
        }

        // Native controls are the critical path. Apply them before querying
        // player APIs or walking data attributes so the visible switch happens
        // in this mutation microtask even if source discovery is not ready yet.
        enableBackgroundPlayback();
        video.setAttribute(ATTR_DONE, '1');
        container.setAttribute(ATTR_DONE, '1');
        enhanceInPlace(container, video, true);

        // A custom element owns its shadow tree and may tear itself down if its
        // internal structure is removed (Archive.org's <play-av> does exactly
        // that). Nativeize shadow players in place and preserve their pipeline;
        // structural cleanup is only safe in the document's light DOM.
        try {
            if (container.getRootNode && container.getRootNode() !== document) { return; }
            // MediaElement keeps querying its generated wrapper after startup;
            // deleting that wrapper leaves playback alive but makes its own
            // lifecycle callbacks throw. Its controls are already hidden, so
            // preserve the shell and nativeize the media element in place.
            if (container.matches && container.matches('.mejs-container,.mejs__container')) { return; }
        } catch (e) { /* continue with the conservative light-DOM path */ }

        // During parser construction, never delete the wrapper DOM before the
        // site's own setup script has run. Native controls and hidden overlays
        // are already visible pre-paint; structural cleanup can safely wait for
        // DOMContentLoaded or a genuine media-ready event.
        var mayClean = !!allowExternalDiscovery;
        if (!mayClean) { return; }
        var src = sourceFromVideoElement(video);
        if (!src && mayClean) {
            src = sourceFromVideojs(container) ||
                sourceFromJwPlayer(container) ||
                sourceFromDom(container) ||
                null;
        }
        log('player detected', container.className, 'source:', src ? 'resolved' : 'opaque');
        if (src && mayClean) { cleanPlayer(container, video, src); }
    }

    // A clean source is often not discoverable at first scan because the player
    // exposes a blob:/opaque src until metadata or its JS API loads. ATTR_DONE is
    // deliberately non-terminal: media events, source mutations, and recovery
    // scans all call replacePlayer again until cleanup becomes possible.
    function onMediaSourceReady(event) {
        var video = event.target;
        if (!(video instanceof HTMLVideoElement)) { return; }
        if (!video._wblockEnhanced || !video._wblockUpgradeable || video._wblockCleaned) { return; }
        var container = (video.closest && video.closest(PLAYER_SELECTOR)) ||
            video.parentElement || video;
        container = normalizeContainer(container);
        try { replacePlayer(container, true); } catch (e) { log('upgrade failed', e); }
    }

    // ------------------------------------------------------------------
    // Scanning
    // ------------------------------------------------------------------

    // A <video> that is not inside a recognized player-library container but
    // still looks like a content player whose native controls are suppressed by
    // custom chrome (modern players such as Mux or bespoke wrappers). These get
    // enhanced in place rather than rebuilt, so an unknown wrapper's layout is
    // left intact.
    function needsBareEnhancement(video) {
        if (video.getAttribute && video.getAttribute(ATTR_DONE)) { return false; }
        if (video.controls) { return false; } // native controls already present
        // Must have (or be about to have) a source to be a real player.
        var src = video.currentSrc || video.src ||
            (video.getAttribute && video.getAttribute('src'));
        if (!src && !(video.querySelector && video.querySelector('source'))) { return false; }
        // Skip ambient/background/hero video: autoplay + muted is the dominant
        // decorative pattern that should keep no native controls.
        if (video.autoplay && video.muted) { return false; }
        // Skip tiny rendered videos (hover previews / thumbnails) when the size
        // is known; offsetWidth/Height are 0 before layout, so only filter on a
        // reliably-small box.
        var w = video.offsetWidth, h = video.offsetHeight;
        if (w > 0 && h > 0 && w < 160 && h < 120) { return false; }
        return true;
    }

    function scan(root, allowExternalDiscovery) {
        var scope = root || document;
        if (!scope || !scope.querySelectorAll) { return; }
        var seen = [];

        function addContainer(raw) {
            var container = normalizeContainer(raw);
            if (!container || seen.indexOf(container) !== -1) { return; }
            seen.push(container);
        }

        // Include the affected node's nearest wrapper. querySelectorAll() does
        // not include the root itself, and a player often adds its <video> in a
        // later mutation after the wrapper was first observed.
        if (scope.nodeType === 1) {
            try {
                var nearest = scope.matches(PLAYER_SELECTOR) ? scope : scope.closest(PLAYER_SELECTOR);
                if (nearest) { addContainer(nearest); }
            } catch (e) { /* ignore */ }
        }

        // Pass 1: known player-library containers (video.js, JW Player, Plyr...).
        var known;
        try { known = scope.querySelectorAll(PLAYER_SELECTOR); }
        catch (e) { known = []; }
        for (var i = 0; i < known.length; i++) { addContainer(known[i]); }
        for (var j = 0; j < seen.length; j++) {
            try { replacePlayer(seen[j], allowExternalDiscovery); }
            catch (e) { log('replace failed', e); }
        }

        // Pass 2: any other <video> whose native controls are suppressed by an
        // unrecognized custom player. Wait until parsing finishes: before then,
        // autoplay/muted/layout signals can be incomplete, and WebKit can throw
        // while initializing native controls for several parser-created videos.
        // Known wrappers above remain on the pre-paint path.
        if (document.readyState === 'loading') { return; }
        var bareVideos = [];
        if (scope.nodeType === 1 && scope.tagName === 'VIDEO') { bareVideos.push(scope); }
        var descendants;
        try { descendants = scope.querySelectorAll('video'); }
        catch (e) { descendants = []; }
        for (var k = 0; k < descendants.length; k++) { bareVideos.push(descendants[k]); }
        for (var v = 0; v < bareVideos.length; v++) {
            var video = bareVideos[v];
            if (!needsBareEnhancement(video)) { continue; }
            var bareContainer = video.parentElement || video;
            log('bare player detected', bareContainer.className || '(no class)', 'enhancing in place');
            try {
                video.setAttribute(ATTR_DONE, '1');
                if (bareContainer.setAttribute) { bareContainer.setAttribute(ATTR_DONE, '1'); }
                enableBackgroundPlayback();
                enhanceInPlace(bareContainer, video, false);
            } catch (e) { log('bare enhance failed', e); }
        }
    }

    var observedRoots = [];
    var observedRootObservers = [];

    function collectVideos(node, output) {
        if (!node || !node.querySelectorAll) { return; }
        if (node.nodeType === 1 && node.tagName === 'VIDEO') { output.push(node); }
        var videos = node.querySelectorAll('video');
        for (var i = 0; i < videos.length; i++) { output.push(videos[i]); }
    }

    function discoverShadowRoots(node) {
        if (!node || !node.querySelectorAll) { return; }
        function inspect(element) {
            try {
                if (element.shadowRoot) { observeTreeRoot(element.shadowRoot); }
            } catch (e) { /* closed roots are captured by attachShadow instead */ }
        }
        if (node.nodeType === 1) { inspect(node); }
        var elements = node.querySelectorAll('*');
        for (var i = 0; i < elements.length; i++) { inspect(elements[i]); }
    }

    function disconnectTreeRoot(root) {
        var index = observedRoots.indexOf(root);
        if (index === -1 || root === document) { return; }
        try { observedRootObservers[index].disconnect(); } catch (e) { /* ignore */ }
        try {
            root.removeEventListener('loadedmetadata', onMediaSourceReady, true);
            root.removeEventListener('durationchange', onMediaSourceReady, true);
        } catch (e) { /* ignore */ }
        observedRoots.splice(index, 1);
        observedRootObservers.splice(index, 1);
    }

    function releaseDetachedShadowRoots() {
        // Closed roots are not reachable through host.shadowRoot, so use the
        // retained root list. Disconnect and release them when their host leaves
        // the document; re-insertion of an open root is rediscovered normally.
        for (var i = observedRoots.length - 1; i >= 0; i--) {
            var root = observedRoots[i];
            if (root === document || !root.host || root.host.isConnected) { continue; }
            var videos = [];
            collectVideos(root, videos);
            for (var v = 0; v < videos.length; v++) { releaseVideoResources(videos[v]); }
            disconnectTreeRoot(root);
        }
    }

    function hasSourceSignal(node) {
        if (!node || !node.querySelectorAll) { return false; }
        try {
            if (node.nodeType === 1 &&
                (node.tagName === 'VIDEO' || node.tagName === 'SOURCE' ||
                 node.matches('[data-src],[data-video-src],[data-file],[data-video],[data-source],[data-url]'))) {
                return true;
            }
            return !!node.querySelector('video,source,[data-src],[data-video-src],[data-file],[data-video],[data-source],[data-url]');
        } catch (e) { return false; }
    }

    function handleMutations(records) {
        var roots = [];
        var detachedVideos = [];
        var sourceRelevant = false;
        function addRoot(node) {
            if (!node || (node.nodeType !== 1 && node.nodeType !== 9 && node.nodeType !== 11)) { return; }
            if (roots.indexOf(node) === -1) { roots.push(node); }
        }
        for (var i = 0; i < records.length; i++) {
            var record = records[i];
            addRoot(record.target);
            if (record.type === 'attributes' && record.attributeName !== 'class') {
                sourceRelevant = true;
            }
            for (var j = 0; j < record.addedNodes.length; j++) {
                var added = record.addedNodes[j];
                addRoot(added);
                discoverShadowRoots(added);
                if (hasSourceSignal(added)) { sourceRelevant = true; }
            }
            for (var k = 0; k < record.removedNodes.length; k++) {
                collectVideos(record.removedNodes[k], detachedVideos);
            }
        }
        // MutationObserver callbacks run at the microtask checkpoint before
        // rendering. Process affected roots now—never add a timer/debounce—so
        // custom chrome cannot survive into the next paint. Only source/video
        // changes after parsing may trigger structural source discovery;
        // ordinary player UI churn is nativeization-only.
        var mayDiscover = sourceRelevant && document.readyState !== 'loading';
        for (var r = 0; r < roots.length; r++) { scan(roots[r], mayDiscover); }
        // DOM moves report a removal and addition in the same batch. Release
        // resources only for videos that remain detached after processing.
        for (var d = 0; d < detachedVideos.length; d++) {
            if (!detachedVideos[d].isConnected) {
                releaseVideoResources(detachedVideos[d]);
            }
        }
        releaseDetachedShadowRoots();
    }

    function observeTreeRoot(root) {
        if (!root || observedRoots.indexOf(root) !== -1 || typeof MutationObserver === 'undefined') { return; }
        var observer = new MutationObserver(handleMutations);
        try {
            observer.observe(root, {
                childList: true,
                subtree: true,
                attributes: true,
                attributeFilter: [
                    'class', 'src', 'data-src', 'data-video-src', 'data-file',
                    'data-video', 'data-source', 'data-url'
                ]
            });
        } catch (e) { return; }
        observedRoots.push(root);
        observedRootObservers.push(observer);
        try {
            root.addEventListener('loadedmetadata', onMediaSourceReady, true);
            root.addEventListener('durationchange', onMediaSourceReady, true);
        } catch (e) { /* ignore */ }
        discoverShadowRoots(root);
        scan(root, document.readyState !== 'loading');
    }

    function patchAttachShadow() {
        try {
            var original = Element.prototype.attachShadow;
            if (!original || original._wblockPlayerCleanerPatched) { return; }
            function patchedAttachShadow() {
                var root = original.apply(this, arguments);
                observeTreeRoot(root);
                return root;
            }
            patchedAttachShadow._wblockPlayerCleanerPatched = true;
            Element.prototype.attachShadow = patchedAttachShadow;
        } catch (e) { /* fall back to discovering open roots from DOM mutations */ }
    }

    function scanAllRoots(allowExternalDiscovery) {
        var roots = observedRoots.slice();
        for (var i = 0; i < roots.length; i++) { scan(roots[i], allowExternalDiscovery); }
    }

    function boot() {
        // Patch first so a custom element attaching a root during parser startup
        // cannot outrun observation. Document and every discovered shadow root
        // then share the same pre-paint mutation/source lifecycle.
        patchAttachShadow();
        observeTreeRoot(document);
    }

    // After all stylesheets have loaded, re-run chrome hiding for enhanced
    // videos.  At DOMContentLoaded some positioned overlays may not yet have
    // their final computed styles (external CSS not yet applied), so the
    // conservative sweep can miss them.  The load event guarantees styles are
    // resolved, letting isPlayerShell() and the position checks work correctly.
    function rehideChrome() {
        var videos = document.querySelectorAll('video[' + ATTR_DONE + ']');
        for (var i = 0; i < videos.length; i++) {
            var v = videos[i];
            if (!v._wblockEnhanced && !v._wblockCleaned) continue;
            var c = v.parentElement;
            if (!c) continue;
            hideContainerChrome(c, v, isPlayerShell(c));
        }
    }

    // Start at document-start. DOMContentLoaded/load scans are recovery passes
    // only; normal players are handled by the pre-paint MutationObservers.
    boot();
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function () { scanAllRoots(true); }, { once: true });
        window.addEventListener('load', function () { scanAllRoots(true); rehideChrome(); }, { once: true });
    } else {
        // document-start already passed (e.g. injected late); schedule a
        // one-time rehide after load in case stylesheets are still pending.
        window.addEventListener('load', function () { rehideChrome(); }, { once: true });
    }
})();
