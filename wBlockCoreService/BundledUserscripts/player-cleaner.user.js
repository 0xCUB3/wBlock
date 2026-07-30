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
    var HIDDEN_ATTR = 'data-wblock-pc-hidden';
    var HIDE_STYLE_ID = 'wblock-pc-hide';
    var PREFERENCES_KEY = 'wblock.playerCleaner.preferences';
    var RESUME_KEY = 'wblock.playerCleaner.resume';
    var enhancedVideos = [];

    // A blob: src on the media element means the page attached a MediaSource /
    // ManagedMediaSource (Player Cleaner never assigns blob urls itself).
    function hasOpaqueMediaSource(video) {
        try {
            return !!(video && ((video.currentSrc || '').indexOf('blob:') === 0 ||
                (video.src || '').indexOf('blob:') === 0));
        } catch (e) { return false; }
    }

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
        video._wblockClickGuard = false;
        video._wblockEnhanced = false;
        video._wblockUpgradeable = false;
        video._wblockCleaned = false;
        var _ei = enhancedVideos.indexOf(video);
        if (_ei !== -1) { enhancedVideos.splice(_ei, 1); }
        video._wblockPreferencesHooked = false;
        video._wblockMediaSessionHooked = false;
        video._wblockShortcutsHooked = false;
        video._wblockTrackHarvestHooked = false;
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
        '.media-default-skin',       // videojs.org's modern demo wrapper
        '.WebPlayerContainer',       // ESPN / Disney BAM player
        '.mw-tmh-player',            // MediaWiki TimedMediaHandler
        '[data-mw-tmh]'              // MediaWiki TimedMediaHandler
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

    // Resolve a media or sidecar URL to an absolute http(s) URL. The browser
    // resolves element attributes itself, but not JS track definitions. Returns
    // null for empty/non-http(s) values (blob:, data:, javascript:, ...).
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
        function harvestTracks() {
            try {
                var domTracks = container.querySelectorAll ? container.querySelectorAll('track[src]') : [];
                for (var i = 0; i < domTracks.length; i++) {
                    if (domTracks[i].parentNode !== video) appendNativeTrack(video, {
                        src: domTracks[i].src, kind: domTracks[i].kind, label: domTracks[i].label,
                        srclang: domTracks[i].srclang, default: domTracks[i].default
                    });
                }
            } catch (e) { /* ignore */ }
            try {
                var elements = [container, video];
                for (var d = 0; d < elements.length; d++) {
                    var el = elements[d];
                    if (!el || !el.getAttribute) continue;
                    var attr = el.getAttribute('data-subtitles') || el.getAttribute('data-captions') || el.getAttribute('data-tracks');
                    if (attr) {
                        if (attr.indexOf('[') === 0 || attr.indexOf('{') === 0) {
                            var parsed = JSON.parse(attr);
                            var arr = Array.isArray(parsed) ? parsed : [parsed];
                            for (var p = 0; p < arr.length; p++) appendNativeTrack(video, arr[p]);
                        } else {
                            appendNativeTrack(video, { src: attr, kind: 'subtitles' });
                        }
                    }
                }
            } catch (e) { /* ignore */ }
            try {
                if (window.jwplayer) {
                    var jw = window.jwplayer(container.id || container);
                    if (jw && typeof jw.getCaptions === 'function') {
                        var captions = jw.getCaptions();
                        if (Array.isArray(captions)) {
                            for (var jc = 0; jc < captions.length; jc++) appendNativeTrack(video, captions[jc]);
                        }
                    }
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
                        if (typeof player.remoteTextTracks === 'function') {
                            var remote = player.remoteTextTracks();
                            if (remote && remote.length) {
                                for (var r = 0; r < remote.length; r++) appendNativeTrack(video, remote[r]);
                            }
                        }
                    }
                }
            } catch (e) { /* ignore */ }
            try {
                var plyr = video.plyr || container.plyr || window.plyr;
                if (plyr && plyr.captions && Array.isArray(plyr.captions.tracks)) {
                    for (var pl = 0; pl < plyr.captions.tracks.length; pl++) appendNativeTrack(video, plyr.captions.tracks[pl]);
                }
            } catch (e) { /* ignore */ }
            try {
                var hls = video._hls || container._hls || window._hls;
                if (hls && Array.isArray(hls.subtitleTracks)) {
                    for (var hl = 0; hl < hls.subtitleTracks.length; hl++) {
                        var st = hls.subtitleTracks[hl];
                        if (st && (st.url || st.vtt)) appendNativeTrack(video, {
                            src: st.url || st.vtt, kind: 'subtitles', label: st.name || st.lang, srclang: st.lang
                        });
                    }
                }
            } catch (e) { /* ignore */ }
            try {
                var dash = video._dash || container._dash || window._dash;
                if (dash && typeof dash.getTracksFor === 'function') {
                    var dashTracks = dash.getTracksFor('subtitle');
                    if (Array.isArray(dashTracks)) {
                        for (var dt = 0; dt < dashTracks.length; dt++) {
                            var dTrack = dashTracks[dt];
                            if (dTrack && dTrack.url) appendNativeTrack(video, {
                                src: dTrack.url, kind: 'subtitles', label: dTrack.lang || dTrack.id, srclang: dTrack.lang
                            });
                        }
                    }
                }
            } catch (e) { /* ignore */ }
        }
        harvestTracks();
        if (video.textTracks && !video._wblockTrackHarvestHooked) {
            video._wblockTrackHarvestHooked = true;
            function onAddTrack() { harvestTracks(); }
            try {
                video.textTracks.addEventListener('addtrack', onAddTrack);
                registerVideoCleanup(video, function () {
                    try { video.textTracks.removeEventListener('addtrack', onAddTrack); } catch (e) {}
                });
            } catch (e) { /* ignore */ }
        }
    }

    function showToast(video, text) {
        if (!video || !text) return;
        try {
            var targetHost = video.parentNode || document.body;
            var toast = targetHost.querySelector('.wblock-pc-toast');
            if (!toast) {
                toast = document.createElement('div');
                toast.className = 'wblock-pc-toast';
                toast.style.cssText = 'position:absolute;top:16px;left:50%;transform:translateX(-50%);' +
                    'background:rgba(0,0,0,0.85);color:#fff;padding:6px 14px;border-radius:16px;' +
                    'font:600 13px -apple-system,system-ui,sans-serif;pointer-events:none;z-index:2147483647;' +
                    'box-shadow:0 4px 12px rgba(0,0,0,0.3);transition:opacity 0.2s linear;opacity:1';
                targetHost.appendChild(toast);
            }
            toast.textContent = text;
            toast.style.opacity = '1';
            if (toast._timer) clearTimeout(toast._timer);
            toast._timer = setTimeout(function () {
                toast.style.opacity = '0';
                setTimeout(function () { try { toast.remove(); } catch (e) {} }, 250);
            }, 1200);
        } catch (e) { /* ignore */ }
    }

    function setupKeyboardShortcuts(container, video) {
        if (!video || video._wblockShortcutsHooked) return;
        video._wblockShortcutsHooked = true;

        function isEditingElement(el) {
            if (!el) return false;
            var tag = el.tagName ? el.tagName.toUpperCase() : '';
            if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return true;
            if (el.isContentEditable) return true;
            if (el.shadowRoot && el.shadowRoot.activeElement) return isEditingElement(el.shadowRoot.activeElement);
            return false;
        }

        function onKeyDown(e) {
            if (e.defaultPrevented || e.metaKey || e.ctrlKey || e.altKey) return;
            if (isEditingElement(document.activeElement)) return;

            if (video.paused && document.activeElement !== video && !container.contains(document.activeElement)) {
                var playing = document.querySelector('video:not([paused])');
                if (playing && playing !== video) return;
            }

            var key = e.key;
            if (key === '[' || key === '{') {
                e.preventDefault();
                var lowerRate = Math.max(0.25, Math.round((video.playbackRate - 0.25) * 100) / 100);
                video.playbackRate = lowerRate;
                savePlaybackPreference('playbackRate', lowerRate);
                showToast(video, lowerRate.toFixed(2) + 'x');
            } else if (key === ']' || key === '}') {
                e.preventDefault();
                var higherRate = Math.min(4.0, Math.round((video.playbackRate + 0.25) * 100) / 100);
                video.playbackRate = higherRate;
                savePlaybackPreference('playbackRate', higherRate);
                showToast(video, higherRate.toFixed(2) + 'x');
            } else if (key === '=' || key === '+') {
                e.preventDefault();
                video.playbackRate = 1.0;
                savePlaybackPreference('playbackRate', 1.0);
                showToast(video, '1.00x');
            } else if (key === 'f' || key === 'F') {
                e.preventDefault();
                try {
                    if (document.fullscreenElement === video || document.webkitFullscreenElement === video) {
                        if (document.exitFullscreen) document.exitFullscreen();
                        else if (document.webkitExitFullscreen) document.webkitExitFullscreen();
                    } else {
                        if (video.requestFullscreen) video.requestFullscreen();
                        else if (video.webkitRequestFullscreen) video.webkitRequestFullscreen();
                        else if (video.webkitEnterFullscreen) video.webkitEnterFullscreen();
                    }
                } catch (err) { /* ignore */ }
            } else if (key === 'p' || key === 'P') {
                e.preventDefault();
                try {
                    if (document.pictureInPictureElement === video || video.webkitPresentationMode === 'picture-in-picture') {
                        if (document.exitPictureInPicture) document.exitPictureInPicture();
                        else if (video.webkitSetPresentationMode) video.webkitSetPresentationMode('inline');
                    } else {
                        if (video.requestPictureInPicture) video.requestPictureInPicture();
                        else if (video.webkitSetPresentationMode) video.webkitSetPresentationMode('picture-in-picture');
                    }
                } catch (err) { /* ignore */ }
            } else if (key === 'm' || key === 'M') {
                e.preventDefault();
                video.muted = !video.muted;
                savePlaybackPreference('muted', video.muted);
                showToast(video, video.muted ? 'Muted' : 'Unmuted');
            } else if (key === 'k' || key === 'K') {
                e.preventDefault();
                if (video.paused) video.play();
                else video.pause();
            } else if (key === 'j' || key === 'J' || key === 'ArrowLeft') {
                e.preventDefault();
                video.currentTime = Math.max(0, video.currentTime - 5);
                showToast(video, '-5s');
            } else if (key === 'l' || key === 'L' || key === 'ArrowRight') {
                e.preventDefault();
                video.currentTime = Math.min(video.duration || Infinity, video.currentTime + 5);
                showToast(video, '+5s');
            }
        }

        window.addEventListener('keydown', onKeyDown, true);
        registerVideoCleanup(video, function () {
            window.removeEventListener('keydown', onKeyDown, true);
        });
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
    // Media element source state
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

    function hasElementSourceSignal(video) {
        try {
            if (video.srcObject) { return true; }
            if (video.currentSrc || video.getAttribute('src')) { return true; }
            var sources = video.getElementsByTagName('source');
            for (var i = 0; i < sources.length; i++) {
                if (sources[i].getAttribute('src')) { return true; }
            }
        } catch (e) { /* ignore */ }
        return false;
    }

    // ------------------------------------------------------------------
    // Replacement
    // ------------------------------------------------------------------

    function normalizeContainer(raw) {
        // Some selectors match inner elements; climb to the outermost player
        // wrapper so we replace the whole custom chrome, not just part of it.
        var container = raw;
        if (container && container.tagName === 'VIDEO') {
            container = container.parentElement || container;
        }
        var wrapperSelectors = ['.video-js', '.jwplayer', '.jw-wrapper', '.plyr',
            '.flowplayer', '.mejs-container', '.mejs__container', '.clappr',
            '[data-clappr-player]', '.fluid_video_wrapper', 'mux-player',
            'media-controller', 'media-theme', 'media-theme-youtube',
            '.media-player', '.media-default-skin', '.WebPlayerContainer',
            '.mw-tmh-player', '[data-mw-tmh]'];
        for (var i = 0; i < wrapperSelectors.length; i++) {
            var ancestor = container.closest ? container.closest(wrapperSelectors[i]) : null;
            if (ancestor && ancestor.tagName !== 'VIDEO') { container = ancestor; }
        }
        return container;
    }

    function forceNativeControls(video) {
        if (video._wblockControlsPatched) return;
        video._wblockControlsPatched = true;
        video.controls = true;
        video.setAttribute('controls', '');
        try {
            if (video.hasAttribute('disabled')) { video.removeAttribute('disabled'); }
            if (video.disabled) { video.disabled = false; }
        } catch (e) { /* ignore */ }
    }

    // The UA services native-control clicks below the JS event layer, but stopping
    // clicks in capture phase breaks native control buttons in WebKit shadow DOM.
    // Stopping propagation in bubble phase allows native controls (play, pause,
    // skip) to handle the click first, while preventing outer custom player shells
    // (video.js, Vimeo) from receiving the click and double-toggling playback.
    function blockCompetingClicks(video) {
        if (!video || video._wblockClickGuard) return;
        video._wblockClickGuard = true;
        try {
            video.addEventListener('click', function (e) { e.stopPropagation(); });
        } catch (e) { /* ignore */ }
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

    // Durable hide: an attribute-backed !important rule beats design-system CSS
    // that reasserts display, and survives most same-node style writes. Inline
    // setProperty(..., 'important') covers the same fight when the attribute is
    // stripped. Never hide <html>/<body>/<video>.
    function ensureHideStyle() {
        if (document.getElementById(HIDE_STYLE_ID)) return;
        try {
            var style = document.createElement('style');
            style.id = HIDE_STYLE_ID;
            style.textContent = '[' + HIDDEN_ATTR + ']{display:none!important;visibility:hidden!important;pointer-events:none!important}';
            (document.head || document.documentElement).appendChild(style);
        } catch (e) { /* ignore */ }
    }

    function hideElement(el) {
        if (!el || el === document.documentElement || el === document.body) return;
        if (el.tagName === 'VIDEO' || el.tagName === 'SOURCE' || el.tagName === 'TRACK') return;
        try {
            ensureHideStyle();
            el.setAttribute(HIDDEN_ATTR, '1');
            el.style.setProperty('display', 'none', 'important');
        } catch (e) { /* ignore */ }
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
                hideElement(el);
            } else {
                try {
                    var pos = getComputedStyle(el).position;
                    if (pos === 'absolute' || pos === 'fixed' || pos === 'sticky') {
                        hideElement(el);
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

    // The player shell for a video: the nearest recognized library wrapper, or —
    // for bespoke players — the nearest positioned ancestor. Custom players hang
    // their overlay chrome (controls, poster, outro) off a positioning context,
    // frequently as siblings of an intermediate video wrapper rather than of the
    // video itself (Vimeo, LinkedIn). Deriving the container from the direct
    // parent then misses those siblings and leaves the original chrome painted
    // over the native controls. Climbing to the positioning context catches them.
    // Falls back to the parent when nothing nearer than the page root is
    // positioned, so a positioned <body> can never trigger a whole-page hide.
    function containerForVideo(video) {
        var known = video.closest && video.closest(PLAYER_SELECTOR);
        if (known && known.tagName !== 'VIDEO') { return normalizeContainer(known); }
        var el = video.parentElement;
        while (el && el.parentElement && el.tagName !== 'BODY') {
            try {
                if (getComputedStyle(el).position !== 'static') { return el; }
            } catch (e) { break; }
            el = el.parentElement;
        }
        return video.parentElement || video;
    }

    // The outermost ancestor that still bounds the player: the highest one whose
    // box is close to the video's size. A control bar pinned to the video's edges
    // (LinkedIn) lives inside this shell but OUTSIDE the video's own wrapper, so a
    // container-descendant sweep never reaches it. The size bound stops the climb
    // before page content (post text, reactions) that sits in a taller ancestor.
    function playerShell(video) {
        var shell = video.parentElement, el = video.parentElement;
        var vr;
        try { vr = video.getBoundingClientRect(); } catch (e) { return shell || video; }
        if (vr.width < 2 || vr.height < 2) { return shell || video; }
        var maxH = vr.height * 1.7 + 160, maxW = vr.width * 1.35 + 48;
        while (el && el.tagName !== 'BODY' && el.tagName !== 'HTML') {
            var r;
            try { r = el.getBoundingClientRect(); } catch (e) { break; }
            if (r.height > maxH || r.width > maxW) { break; }
            shell = el;
            el = el.parentElement;
        }
        return shell || video.parentElement || video;
    }

    // Does a rect overlap the video, allowing control bars that sit on the bottom
    // edge (or just below it) and side/top overlays flush with the edges?
    function overlapsVideo(r, vr) {
        var ix = Math.min(r.right, vr.right + 8) - Math.max(r.left, vr.left - 8);
        var iy = Math.min(r.bottom, vr.bottom + 72) - Math.max(r.top, vr.top - 8);
        return ix >= 4 && iy >= 4;
    }

    // True for overlay chrome that sits on the video without being page chrome.
    // Rejects full-page / full-card boxes so feed text and reaction rows stay.
    function isPlayerOverlay(el, vr) {
        var r;
        try { r = el.getBoundingClientRect(); } catch (e) { return false; }
        if (r.width < 2 || r.height < 2) { return false; }
        if (r.height > vr.height * 1.55 + 48 && r.width > vr.width * 0.85) { return false; }
        var vw = window.innerWidth || 0, vh = window.innerHeight || 0;
        if (vw > 0 && vh > 0 && r.width > vw * 0.9 && r.height > vh * 0.45) { return false; }
        return overlapsVideo(r, vr);
    }

    // Full-bleed cover painted over the video with position:static/relative
    // (LinkedIn end-card: a grid sibling flex box the same size as the media,
    // pe:auto, that steals every hit from native controls). Positioned overlays
    // are handled separately; this is the static same-footprint case.
    function isVideoCover(el, vr) {
        var r;
        try { r = el.getBoundingClientRect(); } catch (e) { return false; }
        if (r.width < 8 || r.height < 8) { return false; }
        if (r.width >= vr.width * 0.85 && r.height >= vr.height * 0.85 &&
            r.width <= vr.width * 1.2 + 8 && r.height <= vr.height * 1.2 + 8) {
            var cx = (r.left + r.right) / 2, cy = (r.top + r.bottom) / 2;
            var vcx = (vr.left + vr.right) / 2, vcy = (vr.top + vr.bottom) / 2;
            if (Math.abs(cx - vcx) <= vr.width * 0.15 && Math.abs(cy - vcy) <= vr.height * 0.15) {
                return true;
            }
        }
        var ix = Math.min(r.right, vr.right) - Math.max(r.left, vr.left);
        var iy = Math.min(r.bottom, vr.bottom) - Math.max(r.top, vr.top);
        if (ix < 8 || iy < 8) { return false; }
        return (ix * iy) >= (vr.width * vr.height * 0.55);
    }

    // Static player control bar (LinkedIn): a short strip spanning most of the
    // video width, stacked over the bottom or top control region. Too short for
    // isVideoCover and not positioned, so it slips past every other check and
    // steals hits from native controls.
    function isControlBar(el, vr) {
        var r;
        try { r = el.getBoundingClientRect(); } catch (e) { return false; }
        if (r.width < 8 || r.height < 8) { return false; }
        if (r.height > vr.height * 0.4 + 24) { return false; }
        var ovX = Math.min(r.right, vr.right) - Math.max(r.left, vr.left);
        if (ovX < vr.width * 0.5) { return false; }
        // Bar must straddle the video horizontally; tolerate padding/box-sizing
        // making it a touch wider than the media.
        var cx = (r.left + r.right) / 2;
        if (cx < vr.left - r.width * 0.1 || cx > vr.right + r.width * 0.1) { return false; }
        var ovY = Math.min(r.bottom, vr.bottom) - Math.max(r.top, vr.top);
        if (ovY < 4) { return false; }
        var cy = (r.top + r.bottom) / 2;
        return cy >= vr.bottom - vr.height * 0.4 || cy <= vr.top + vr.height * 0.4;
    }

    // Hide overlay chrome within an off-path subtree drawn over the video.
    // Positioned roots that overlap are hidden wholesale. Static roots that are
    // full-bleed video covers (LinkedIn) are also hidden wholesale. Other static
    // roots whose box is off the video are pruned; remaining static roots are
    // walked only for positioned descendants so post text/reactions stay.
    function hideOverlappingSubtree(root, video, vr) {
        if (root === video || root.contains(video) || video.contains(root)) { return; }
        var rr;
        try { rr = root.getBoundingClientRect(); } catch (e) { return; }
        var pos;
        try { pos = getComputedStyle(root).position; } catch (e) { return; }
        if (pos === 'absolute' || pos === 'sticky' || pos === 'fixed') {
            if (isPlayerOverlay(root, vr)) { hideElement(root); }
            return;
        }
        if (isVideoCover(root, vr)) {
            hideElement(root);
            return;
        }
        if (isControlBar(root, vr)) {
            hideElement(root);
            return;
        }
        if (!overlapsVideo(rr, vr)) { return; }
        var els = root.querySelectorAll('*');
        for (var i = 0; i < els.length; i++) {
            var el = els[i];
            if (el === video || el.contains(video) || video.contains(el)) { continue; }
            try {
                var p = getComputedStyle(el).position;
                if (p === 'absolute' || p === 'sticky' || p === 'fixed') {
                    if (isPlayerOverlay(el, vr)) { hideElement(el); }
                } else if (isVideoCover(el, vr)) {
                    hideElement(el);
                }
            } catch (e) { /* ignore */ }
        }
    }

    // Climb the video's ancestors while they bound the player and hide overlay
    // chrome (siblings of the video's wrapper) that overlaps the media. Catches
    // players whose controls hang off an outer shell rather than the video's own
    // wrapper — the case a container-descendant sweep misses.
    function hideOverlappingChrome(video) {
        var vr;
        try { vr = video.getBoundingClientRect(); } catch (e) { return; }
        if (vr.width < 2 || vr.height < 2) { return; }
        var maxH = vr.height * 1.7 + 160, maxW = vr.width * 1.35 + 48;
        var child = video;
        for (var anc = video.parentElement; anc && anc.tagName !== 'BODY' && anc.tagName !== 'HTML'; child = anc, anc = anc.parentElement) {
            var ar;
            try { ar = anc.getBoundingClientRect(); } catch (e) { break; }
            if (ar.height > maxH || ar.width > maxW) { break; }
            for (var c = 0; c < anc.children.length; c++) {
                if (anc.children[c] !== child) { hideOverlappingSubtree(anc.children[c], video, vr); }
            }
        }
    }

    // Hide a candidate that sits over the video but is not an ancestor/descendant
    // of it. Used by both hit-testing and the detached (portal) scan. Accepts
    // positioned chrome and static/relative full-bleed covers (LinkedIn).
    function hideIfDetachedOverlay(el, video, vr) {
        if (!el || el === video || el === document.documentElement || el === document.body) { return; }
        if (video.contains(el) || (el.contains && el.contains(video))) { return; }
        // A hit often lands on a control (slider/button) nested in a static bar;
        // hide the bar rather than the inner control, which the caller sees.
        var bar = el;
        for (var i = 0; i < 6 && bar && bar !== document.body; i++) {
            if (bar !== video && !video.contains(bar) && isControlBar(bar, vr)) {
                hideElement(bar);
                return;
            }
            bar = bar.parentElement;
        }
        if (!isPlayerOverlay(el, vr)) { return; }
        try {
            var pos = getComputedStyle(el).position;
            if (pos !== 'absolute' && pos !== 'fixed' && pos !== 'sticky' && !isVideoCover(el, vr)) {
                return;
            }
        } catch (e) { return; }
        hideElement(el);
    }

    // Hit-test the pixels over the video and hide anything painted above it.
    // Catches React portals, position:fixed controls, and overlays whose DOM
    // parent is outside the player shell — the case an ancestor climb misses
    // (LinkedIn feed player). Also scans top-level body children geometrically
    // so off-viewport / zero-hit-test cases (and portal remounts) still get hid.
    function hideStackedChrome(video) {
        var vr;
        try { vr = video.getBoundingClientRect(); } catch (e) { return; }
        if (vr.width < 2 || vr.height < 2) { return; }
        var vw = window.innerWidth || 0, vh = window.innerHeight || 0;
        if (typeof document.elementsFromPoint === 'function') {
            var pts = [
                [vr.left + vr.width * 0.5, vr.top + vr.height * 0.5],
                [vr.left + 28, vr.top + 28],
                [vr.right - 28, vr.top + 28],
                [vr.left + vr.width * 0.5, vr.top + 20],
                [vr.left + vr.width * 0.5, vr.bottom - 18],
                [vr.left + 28, vr.bottom - 18],
                [vr.right - 28, vr.bottom - 18]
            ];
            for (var i = 0; i < pts.length; i++) {
                var x = pts[i][0], y = pts[i][1];
                if (vw > 0 && (x < 0 || y < 0 || x > vw || y > vh)) { continue; }
                var stack;
                try { stack = document.elementsFromPoint(x, y); } catch (e) { continue; }
                if (!stack) { continue; }
                for (var s = 0; s < stack.length; s++) {
                    var hit = stack[s];
                    if (hit === video || video.contains(hit)) { break; }
                    hideIfDetachedOverlay(hit, video, vr);
                }
            }
        }
        // Geometric pass over body-level nodes (and one level of children). Portals
        // and fixed chrome almost always land here; keeps cost bounded on big pages.
        var body = document.body;
        if (!body) { return; }
        for (var b = 0; b < body.children.length; b++) {
            var top = body.children[b];
            hideIfDetachedOverlay(top, video, vr);
            var kids = top.children;
            if (!kids || kids.length > 40) { continue; }
            for (var k = 0; k < kids.length; k++) {
                hideIfDetachedOverlay(kids[k], video, vr);
            }
        }
    }

    function suppressChrome(container, video) {
        hideContainerChrome(container, video, isPlayerShell(container));
        hideOverlappingChrome(video);
        hideStackedChrome(video);
    }

    // Custom players (LinkedIn) paint or remount chrome on play/seek/end after
    // our one-shot hide. Re-run hide on those media events, on the next two
    // animation frames, and on short deferred timeouts — LinkedIn's static
    // "Watch again" cover often lands a few hundred ms after `ended`.
    function armChromeWatch(video) {
        if (!video || video._wblockChromeWatch) { return; }
        video._wblockChromeWatch = true;
        var timers = [];
        function kick() {
            if (!video.isConnected) { return; }
            hideOverlappingChrome(video);
            hideStackedChrome(video);
        }
        function kickAfterPaint() {
            kick();
            if (typeof requestAnimationFrame === 'function') {
                requestAnimationFrame(function () { requestAnimationFrame(kick); });
            }
        }
        function kickDeferred() {
            kickAfterPaint();
            if (typeof setTimeout !== 'function') { return; }
            [50, 200, 500].forEach(function (ms) {
                timers.push(setTimeout(kick, ms));
            });
        }
        try {
            video.addEventListener('play', kickDeferred);
            video.addEventListener('pause', kickDeferred);
            video.addEventListener('ended', kickDeferred);
            video.addEventListener('seeking', kick);
            video.addEventListener('loadeddata', kick);
        } catch (e) { /* ignore */ }
        registerVideoCleanup(video, function () {
            try {
                video.removeEventListener('play', kickDeferred);
                video.removeEventListener('pause', kickDeferred);
                video.removeEventListener('ended', kickDeferred);
                video.removeEventListener('seeking', kick);
                video.removeEventListener('loadeddata', kick);
            } catch (e) { /* ignore */ }
            for (var t = 0; t < timers.length; t++) {
                try { clearTimeout(timers[t]); } catch (e) { /* ignore */ }
            }
            timers = [];
        });
    }

    function enhanceInPlace(container, video, upgradeable) {
        if (video._wblockEnhanced) {
            // A video can first appear as a bare custom player and later be
            // wrapped by a known library. Promote it so a later element source
            // can still clean the known wrapper. Re-hide chrome a framework may
            // have rendered after initial cleanup.
            if (upgradeable) { video._wblockUpgradeable = true; }
            suppressChrome(container, video);
            return;
        }
        video._wblockEnhanced = true;
        if (enhancedVideos.indexOf(video) === -1) { enhancedVideos.push(video); }
        // Upgradeable videos get one more replacement chance once their metadata
        // (and therefore currentSrc) has loaded; see onMediaSourceReady. Bare
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
        setupKeyboardShortcuts(container, video);

        suppressChrome(container, video);
        armChromeWatch(video);
        blockCompetingClicks(video);

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
        // A blob: src means the page attached a MediaSource / MSE pipeline it
        // owns and is actively feeding (cnn / ms.now, iOS and desktop).
        // Emptying the wrapper or overwriting src wedges that pipeline and
        // surfaces as a player that fails to load until the page is refreshed.
        // enhanceInPlace() already gave the element native controls and hid
        // the custom chrome, so leaving the pipeline untouched loses nothing.
        // This is a platform-agnostic rule based on the source type, not the
        // user agent or the readyState (which may still be 0 when the pipeline
        // is being set up).
        if (hasOpaqueMediaSource(video)) { return; }
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
        if (enhancedVideos.indexOf(video) === -1) { enhancedVideos.push(video); }
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
        setupKeyboardShortcuts(container, video);
        guardNativeControls(video);
        restorePlaybackState(video, state, sourceChanged);
        hideOverlappingChrome(video);
        hideStackedChrome(video);
        armChromeWatch(video);
    }

    function selectContainerVideo(container) {
        if (!container || !container.querySelectorAll) { return null; }
        var videos = container.querySelectorAll('video');
        if (!videos.length) { return null; }
        var selected = videos[0];
        var bestScore = -1;
        for (var i = 0; i < videos.length; i++) {
            var candidate = videos[i];
            var score = hasElementSourceSignal(candidate) ? 100 : 0;
            try {
                if (candidate.currentSrc) { score += 20; }
                if (candidate.srcObject) { score += 20; }
                if (!candidate.paused && !candidate.ended) { score += 10; }
                score += Math.min(candidate.readyState || 0, 4);
                if (candidate.offsetWidth > 0 && candidate.offsetHeight > 0) { score += 5; }
                if (getComputedStyle(candidate).display === 'none') { score -= 5; }
            } catch (e) { /* use the source-signal score */ }
            if (score > bestScore) {
                bestScore = score;
                selected = candidate;
            }
        }
        return selected;
    }

    function replacePlayer(container, allowStructuralCleanup) {
        var video = selectContainerVideo(container);
        if (!video) { return; }
        if (video._wblockCleaned) {
            suppressChrome(container, video);
            return;
        }

        // A recognized wrapper can expose its API URL before its media element
        // has a source. That is an initialization state, not permission to
        // delete the wrapper: on a warm/cached load JW Player can still be
        // building controls and will later attach its MSE blob. Wait for an
        // element-owned source mutation so Player Cleaner cannot race setup.
        if (!hasElementSourceSignal(video)) {
            log('player initializing; waiting for media element source');
            return;
        }

        // Native controls are the critical path once the media element owns a
        // source. Apply them in this mutation microtask before the next paint.
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
        var mayClean = !!allowStructuralCleanup;
        if (!mayClean) { return; }

        // Only a direct source owned by the media element authorizes structural
        // cleanup. Player API and data-attribute URLs are hints, not proof that
        // setup is complete; using them caused cached-load races where the
        // cleaner emptied JW Player's wrapper before it attached its blob.
        var src = sourceFromVideoElement(video);
        log('player detected', container.className, 'source:', src ? 'element-owned' : 'opaque');
        if (src) { cleanPlayer(container, video, src); }
    }

    // A clean source is often not discoverable at first scan because the player
    // exposes a blob:/opaque src until metadata or its JS API loads. ATTR_DONE is
    // deliberately non-terminal: media events, source mutations, and recovery
    // scans all call replacePlayer again until cleanup becomes possible.
    function onMediaSourceReady(event) {
        var video = event.target;
        if (!(video instanceof HTMLVideoElement)) { return; }
        if (!video._wblockEnhanced || !video._wblockUpgradeable || video._wblockCleaned) { return; }
        var container = containerForVideo(video);
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

    function scan(root, allowStructuralCleanup) {
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
            try { replacePlayer(seen[j], allowStructuralCleanup); }
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
            var bareContainer = containerForVideo(video);
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
        // changes after parsing may trigger structural cleanup; ordinary player
        // UI churn is nativeization-only.
        var mayClean = sourceRelevant && document.readyState !== 'loading';
        for (var r = 0; r < roots.length; r++) { scan(roots[r], mayClean); }
        // Re-hide overlay chrome for already-enhanced videos whose player region a
        // mutation just touched. Custom players (LinkedIn) (re)mount or refresh
        // their control overlay after the one-shot hide — typically on play — so
        // the hide must be re-applied reactively, not only at scan time. Portals
        // remounted outside the shell still need a hit-test pass, so any player
        // with a non-empty mutation batch re-runs hideStackedChrome.
        var anyAdded = false;
        for (var ai = 0; ai < records.length && !anyAdded; ai++) {
            if (records[ai].addedNodes && records[ai].addedNodes.length) { anyAdded = true; }
        }
        for (var e = enhancedVideos.length - 1; e >= 0; e--) {
            var ev = enhancedVideos[e];
            if (!ev.isConnected) { enhancedVideos.splice(e, 1); continue; }
            var shell = playerShell(ev);
            var touched = false;
            for (var mi = 0; mi < records.length && !touched; mi++) {
                if (shell.contains(records[mi].target)) { touched = true; break; }
                var added = records[mi].addedNodes;
                for (var ni = 0; ni < added.length; ni++) {
                    if (added[ni].nodeType === 1 && shell.contains(added[ni])) { touched = true; break; }
                }
            }
            if (touched) {
                hideOverlappingChrome(ev);
                hideStackedChrome(ev);
            } else if (anyAdded) {
                hideStackedChrome(ev);
            }
        }
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

    function scanAllRoots(allowStructuralCleanup) {
        var roots = observedRoots.slice();
        for (var i = 0; i < roots.length; i++) { scan(roots[i], allowStructuralCleanup); }
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
            var c = containerForVideo(v);
            if (!c) continue;
            suppressChrome(c, v);
            blockCompetingClicks(v);
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
