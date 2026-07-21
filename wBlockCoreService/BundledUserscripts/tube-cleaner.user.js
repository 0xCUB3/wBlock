// ==UserScript==
// @name         Tube Cleaner
// @namespace    com.skula.wblock
// @version      4.2.4
// @description  Replaces the YouTube player with a native HTML video element using YouTube's stream. Removes ads, restores picture-in-picture, keeps videos playing in background tabs, and adds an audio-only mode.
// @description:de  Ersetzt den YouTube-Player durch ein natives HTML-Videoelement mit YouTube-Stream. Entfernt Werbung, stellt Bild-in-Bild wieder her, hält Videos in Hintergrund-Tabs am Laufen und fügt einen Nur-Audio-Modus hinzu.
// @description:es  Reemplaza el reproductor de YouTube con un elemento de video HTML nativo usando el stream de YouTube. Elimina anuncios, restaura picture-in-picture, mantiene los videos reproduciéndose en segundo plano y añade un modo de solo audio.
// @description:fr  Remplace le lecteur YouTube par un élément vidéo HTML natif utilisant le flux YouTube. Supprime les publicités, restaure l'image dans l'image, garde les vidéos en lecture en arrière-plan et ajoute un mode audio seul.
// @description:it  Sostituisce il lettore YouTube con un elemento video HTML nativo usando lo stream YouTube. Rimuove gli annunci, ripristina picture-in-picture, mantiene i video in riproduzione in background e aggiunge una modalità solo audio.
// @description:pt-BR  Substitui o player do YouTube por um elemento de vídeo HTML nativo usando o stream do YouTube. Remove anúncios, restaura picture-in-picture, mantém vídeos em reprodução em segundo plano e adiciona modo somente áudio.
// @description:ja  YouTubeのプレーヤーをネイティブHTMLビデオ要素に置き換え、YouTubeのストリームを使用します。広告を削除し、ピクチャーインピクチャーを復元し、バックグラウンドタブで動画を再生し続け、オーディオのみのモードを追加します。
// @description:ko  YouTube 플레이어를 YouTube 스트림을 사용하는 네이티브 HTML 비디오 요소로 대체합니다. 광고를 제거하고, PIP를 복원하고, 백그라운드 탭에서 동영상 재생을 유지하고, 오디오 전용 모드를 추가합니다.
// @description:ru  Заменяет плеер YouTube на нативный HTML-видеоэлемент, использующий поток YouTube. Удаляет рекламу, восстанавливает картинку-в-картинке, продолжает воспроизведение в фоновых вкладках и добавляет режим только аудио.
// @description:zh-Hans  使用 YouTube 的流替换 YouTube 播放器为原生 HTML 视频元素。移除广告，恢复画中画，保持视频在后台标签页播放，并添加纯音频模式。
// @author       wBlock
// @match        https://www.youtube.com/*
// @match        https://m.youtube.com/*
// @match        https://music.youtube.com/*
// @match        https://www.youtube-nocookie.com/*
// @run-at       document-start
// @inject-into  page
// @grant        none
// ==/UserScript==

(function () {
    'use strict';

    // ------------------------------------------------------------------
    // Tube Cleaner v4.2.4
    //
    // Vinegar Extract approach: instead of trying to extract stream URLs
    // from the player response (which 403 due to SABR), we let YouTube's
    // player create and initialize the <video> element with its SABR/MSE
    // pipeline, then we repurpose that <video> element into a native
    // Safari player.
    //
    // How it works:
    //   1. Wait for YouTube's player to create a <video> element
    //   2. Detach it from YouTube's player container
    //   3. Insert it into a minimal native wrapper
    //   4. Enable Safari's native controls
    //   5. Hide YouTube's player chrome via CSS
    //   6. Ad blocking is handled by wBlock's content blocker
    //
    // This preserves full quality (SABR adaptive bitrate) while giving
    // the user a native Safari video experience.
    // ------------------------------------------------------------------

    var LOG_PREFIX = '[Tube Cleaner]';
    var STORAGE_AUDIO = 'wblock.tubeCleaner.audioOnly';
    var STORAGE_QUALITY = 'wblock.tubeCleaner.quality';
    var ATTR_CLEANED = 'data-wblock-tc-cleaned';

    var debug = !!window.__wblockTubeCleanerDebug;

    function log() {
        if (!debug) return;
        try { console.log.apply(console, [LOG_PREFIX].concat([].slice.call(arguments))); }
        catch (e) { /* ignore */ }
    }

    function warn() {
        try { console.warn.apply(console, [LOG_PREFIX].concat([].slice.call(arguments))); }
        catch (e) { /* ignore */ }
    }

    // ------------------------------------------------------------------
    // iOS / iPadOS detection
    // ------------------------------------------------------------------

    // iPadOS requesting the desktop site reports "MacIntel" with touch support.
    // Real Macs report zero maxTouchPoints in Safari. Do not inspect
    // documentElement here: production injection can run before <html> exists.
    var IS_IOS = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
        (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
    // ------------------------------------------------------------------
    // Auto PiP
    // ------------------------------------------------------------------

    var AUTO_PIP_KEY = 'wblock.tubeCleaner.autoPiP';
    var autoPiPEnabled = true;
    var pipActive = false;

    function getAutoPiP() {
        try {
            var stored = localStorage.getItem(AUTO_PIP_KEY);
            return stored === null ? true : stored === '1';
        } catch (e) { return true; }
    }

    function setAutoPiP(v) {
        try { localStorage.setItem(AUTO_PIP_KEY, v ? '1' : '0'); } catch (e) { /* ignore */ }
        autoPiPEnabled = v;
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
                // Track only PiP entered by Tube Cleaner. PiP entered manually
                // from Safari's controls must remain under the user's control.
                pipActive = true;
                video.webkitSetPresentationMode('picture-in-picture');
                log('PiP entered');
            } else if (video.requestPictureInPicture) {
                pipActive = true;
                var request = video.requestPictureInPicture();
                if (request && request.catch) {
                    request.catch(function (e) {
                        pipActive = false;
                        log('PiP request rejected', e);
                    });
                }
                log('PiP entered via API');
            }
        } catch (e) {
            pipActive = false;
            warn('enterPiP failed', e);
        }
    }

    function exitPiP(video) {
        if (!video || !pipActive) return;
        if (!isPiPActive(video)) {
            pipActive = false;
            return;
        }
        try {
            if (video.webkitSupportsPresentationMode &&
                typeof video.webkitSetPresentationMode === 'function') {
                video.webkitSetPresentationMode('inline');
                pipActive = false;
                log('PiP exited');
            } else if (document.pictureInPictureElement) {
                var request = document.exitPictureInPicture();
                if (request && request.catch) {
                    request.catch(function (e) { log('PiP exit rejected', e); });
                }
                pipActive = false;
            }
        } catch (e) { warn('exitPiP failed', e); }
    }

    function setupAutoPiP(video) {
        if (!video || video._wblockAutoPiPHooked) return;
        video._wblockAutoPiPHooked = true;

        // Tab switch: enter PiP when tab hides, exit when visible.
        // Note: enableBackgroundPlayback() overrides document.hidden to always
        // return false, so we use _realHidden which tracks the true state.
        function onVisibilityChange() {
            if (!autoPiPEnabled) return;
            if (_realHidden) {
                if (!video.paused && !video.ended) {
                    enterPiP(video);
                }
            } else {
                if (document.hasFocus() && isPiPActive(video)) {
                    exitPiP(video);
                }
            }
        }

        // Window blur: enter PiP when switching to another app
        var blurTimer = null;
        function onBlur() {
            if (!autoPiPEnabled) return;
            if (_realHidden) return; // already handled by visibilitychange
            clearTimeout(blurTimer);
            blurTimer = setTimeout(function () {
                blurTimer = null;
                if (document.hasFocus()) return; // focus moved within document
                if (!video.paused && !video.ended) {
                    enterPiP(video);
                }
            }, 100);
        }

        function onFocus() {
            if (!autoPiPEnabled) return;
            if (_realHidden) return;
            if (document.hasFocus() && isPiPActive(video)) {
                exitPiP(video);
            }
        }

        document.addEventListener('visibilitychange', onVisibilityChange);
        window.addEventListener('blur', onBlur);
        window.addEventListener('focus', onFocus);

        // Scroll out of view: use IntersectionObserver
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

        // Listen for presentation mode changes
        function onPresentationModeChange() {
            if (video.webkitPresentationMode !== 'picture-in-picture') {
                pipActive = false;
            }
            log('presentation mode changed:', video.webkitPresentationMode);
        }
        function onLeavePictureInPicture() { pipActive = false; }
        video.addEventListener('webkitpresentationmodechanged', onPresentationModeChange);
        video.addEventListener('leavepictureinpicture', onLeavePictureInPicture);

        // Release all of the above when this video is superseded, so listeners
        // and observers do not accumulate across SPA navigations.
        registerCleanup(function () {
            document.removeEventListener('visibilitychange', onVisibilityChange);
            window.removeEventListener('blur', onBlur);
            window.removeEventListener('focus', onFocus);
            clearTimeout(blurTimer);
            try { scrollObserver.disconnect(); } catch (e) { /* ignore */ }
            video.removeEventListener('webkitpresentationmodechanged', onPresentationModeChange);
            video.removeEventListener('leavepictureinpicture', onLeavePictureInPicture);
        });
    }

    // ------------------------------------------------------------------
    // Preferences
    // ------------------------------------------------------------------

    function isAudioOnly() {
        try { return localStorage.getItem(STORAGE_AUDIO) === '1'; } catch (e) { return false; }
    }

    function setAudioOnly(v) {
        try { localStorage.setItem(STORAGE_AUDIO, v ? '1' : '0'); } catch (e) { /* ignore */ }
    }

    function getPreferredQuality() {
        try { return localStorage.getItem(STORAGE_QUALITY) || 'auto'; } catch (e) { return 'auto'; }
    }

    function setPreferredQuality(q) {
        try { localStorage.setItem(STORAGE_QUALITY, q); } catch (e) { /* ignore */ }
    }

    // ------------------------------------------------------------------
    // CSS injected into the page
    // ------------------------------------------------------------------

    var STYLE_ID = 'wblock-tc-style';

    var CSS = [
        // Hide YouTube's player chrome entirely. The native <video>
        // element gets its own controls from Safari.
        '#movie_player .ytp-chrome-top,',
        '#movie_player .ytp-chrome-bottom,',
        '#movie_player .ytp-gradient-top,',
        '#movie_player .ytp-gradient-bottom,',
        '#movie_player .ytp-title,',
        '#movie_player .ytp-pip-button,',
        '#movie_player .ytp-chrome-controls,',
        '#movie_player .ytp-right-controls,',
        '#movie_player .ytp-left-controls,',
        '#movie_player .ytp-play-button,',
        '#movie_player .ytp-volume-area,',
        '#movie_player .ytp-time-display,',
        '#movie_player .ytp-progress-bar,',
        '#movie_player .ytp-progress-bar-container,',
        '#movie_player .ytp-settings-button,',
        '#movie_player .ytp-fullscreen-button,',
        '#movie_player .ytp-remote-button,',
        '#movie_player .ytp-size-button,',
        '#movie_player .ytp-subtitles-button,',
        '#movie_player .ytp-autonav-endscreen-button,',
        '#movie_player .ytp-share-button,',
        '#movie_player .ytp-watch-later-button,',
        '#movie_player .ytp-menuitem,',
        // Storyboard scrubbing preview
        '.ytp-storyboard-framepreview,',
        '.ytp-tooltip,',
        // Ad overlays
        '.ytp-ad-module,',
        '.video-ads,',
        '#player-ads,',
        '.ytp-ad-overlay-container,',
        '.ytp-ad-overlay-slot,',
        '.ytp-ad-image-overlay,',
        '.ytp-ad-overlay-image,',
        '.ytp-ad-badge,',
        // Annotations, cards, end screen
        '.ytp-ce-element,',
        '.ytp-cards-teaser,',
        '.iv-branding,',
        '.ytp-ce-covering-overlay,',
        '.ytp-ce-cover,',
        // Pause overlay
        '.ytp-pause-overlay,',
        // Autoplay countdown
        '.ytp-autonav-endscreen-countdown-overlay,',
        '.ytp-autonav-toggle-button-container,',
        // Info panel
        '.ytp-video-info-panel,',
        // Channel watermark
        '.ytp-watermark,',
        // Related videos overlay
        '.ytp-related-overlay,',
        // Large play button in center
        '.ytp-large-play-button,',
        // Unplayable text
        '.ytp-error,',
        // Spoiler overlay
        '.ytp-spoiler-overlay',
        '{ display: none !important; }',

        // Make the video container fully transparent so only the
        // native <video> element shows through.
        '#movie_player .html5-video-player,',
        '#movie_player',
        '{ background: transparent !important; }',

        // Remove padding/margins that YouTube adds for its controls.
        '#movie_player .html5-video-container',
        '{ position: static !important; }',

        // Let the video fill the container.
        '#movie_player video',
        '{ width: 100% !important; height: 100% !important; }',

        // Hide the YouTube player container's custom cursor.
        '#movie_player',
        '{ cursor: default !important; }',

        // Hide the "Youtube" link in the player.
        '.ytp-youtube-button,',
        '.ytp-title-link',
        '{ display: none !important; }',

        // Ensure the player container doesn't clip our toolbar.
        '#movie_player',
        '{ overflow: visible !important; }',

        // Toolbar is hidden by default, appears on hover near bottom.
        // '.wblock-tc-toolbar',
        // '{ opacity: 1 !important; display: flex !important; }',

        // Ensure the native controls bar is visible on the video.
        // YouTube's player often sets the video to be a child of
        // elements with overflow:hidden or pointer-events:none.
        '.wblock-tc-native video',
        '{ display: block !important; pointer-events: auto !important; }',

        // YouTube leaves several transparent gesture/feedback layers above the
        // media element. They must not steal taps from Safari's native controls.
        '.wblock-tc-native .ytp-cued-thumbnail-overlay,',
        '.wblock-tc-native .ytp-paid-content-overlay,',
        '.wblock-tc-native .ytp-bezel,',
        '.wblock-tc-native .ytp-spinner,',
        '.wblock-tc-native .ytp-doubletap-ui-legacy,',
        '.wblock-tc-native .ytp-touch-response,',
        '.wblock-tc-native .ytp-player-content',
        '{ pointer-events: none !important; }',

        // Mobile YouTube renders its new controls outside #movie_player in a
        // sibling custom-element tree. It appears after "Tap to unmute" and
        // otherwise sits above Safari's native media controls.
        '#player-control-container,',
        'ytm-custom-control,',
        'ytm-watch-player-controls',
        '{ display: none !important; pointer-events: none !important; }',

        // Do not style Safari's private ::-webkit-media-controls tree. iOS and
        // macOS use different internal layouts, and forcing display/flex on the
        // iOS shadow controls breaks both video painting and touch hit-testing.

        // Make sure the video container allows native controls to
        // render by removing overflow hidden.
        '#movie_player .html5-video-container',
        '{ overflow: visible !important; }',

        // Let the native controls bar extend below the video.
        '.wblock-tc-native',
        '{ overflow: visible !important; }',

        // The active desktop-Shorts player is not guaranteed to use the
        // movie_player id. Repeat the critical cleanup rules against the class
        // applied by Tube Cleaner so alternate YouTube player instances receive
        // the same native layout.
        '.wblock-tc-native .ytp-chrome-top,',
        '.wblock-tc-native .ytp-chrome-bottom,',
        '.wblock-tc-native .ytp-gradient-top,',
        '.wblock-tc-native .ytp-gradient-bottom,',
        '.wblock-tc-native .ytp-title,',
        '.wblock-tc-native .ytp-large-play-button,',
        '.wblock-tc-native .ytp-ad-module,',
        '.wblock-tc-native .video-ads,',
        '.wblock-tc-native .ytp-ad-overlay-container,',
        '.wblock-tc-native .ytp-ce-element,',
        '.wblock-tc-native .ytp-cards-teaser,',
        '.wblock-tc-native .ytp-pause-overlay,',
        '.wblock-tc-native .ytp-autonav-endscreen-countdown-overlay,',
        '.wblock-tc-native .ytp-watermark,',
        '.wblock-tc-native .ytp-related-overlay,',
        '.wblock-tc-native .ytp-error',
        '{ display: none !important; }',

        '.wblock-tc-native .html5-video-container',
        '{ position: static !important; overflow: visible !important; }',

        '.wblock-tc-native video',
        '{ width: 100% !important; height: 100% !important; }',

        // Prevent iOS double-tap zoom on toolbar buttons.
        '.wblock-tc-toolbar button, .wblock-tc-toolbar div',
        '{ touch-action: manipulation !important; }',
    ].join(' ');

    var AUDIO_ONLY_CSS = [
        '.wblock-tc-native video,',
        '.wblock-tc-native .html5-video-container',
        '{ visibility: hidden !important; }'
    ].join(' ');

    function injectStyles() {
        if (document.getElementById(STYLE_ID)) { return true; }
        var root = document.head || document.documentElement;
        if (!root) { return false; }
        var style = document.createElement('style');
        style.id = STYLE_ID;
        style.textContent = CSS;
        root.appendChild(style);
        return true;
    }

    function setAudioOnlyStyles(enabled) {
        var id = STYLE_ID + '-audio';
        var existing = document.getElementById(id);
        if (enabled && !existing) {
            var style = document.createElement('style');
            style.id = id;
            style.textContent = AUDIO_ONLY_CSS;
            (document.head || document.documentElement).appendChild(style);
        } else if (!enabled && existing) {
            existing.remove();
        }
    }

    // ------------------------------------------------------------------
    // Background playback
    // ------------------------------------------------------------------

    // Track real visibility state separately since we override document.hidden.
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

    var nativeHiddenGetter = findDocumentGetter('hidden');
    var nativeVisibilityGetter = findDocumentGetter('visibilityState');

    function updateRealVisibility() {
        try {
            _realHidden = nativeHiddenGetter ? nativeHiddenGetter.call(document) : document.hidden;
            _realVisibility = nativeVisibilityGetter ?
                nativeVisibilityGetter.call(document) : document.visibilityState;
        } catch (e) { /* ignore */ }
    }

    // Capture initially and keep using the native prototype getters after the
    // document instance properties are shadowed for background playback.
    updateRealVisibility();
    document.addEventListener('visibilitychange', updateRealVisibility);

    function enableBackgroundPlayback() {
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
    // Core: extract the <video> from YouTube's player and make it native
    // ------------------------------------------------------------------

    var currentState = null;

    // ------------------------------------------------------------------
    // Per-video resource tracking
    //
    // YouTube is a single-page app. Navigating between videos (or the player
    // recreating its <video> element) used to leak resources: each new video
    // added more document/window listeners, MutationObservers, and setInterval
    // timers without removing the previous video's. We track the active video's
    // teardown callbacks and run them before activating a new video, so resource
    // counts stay flat no matter how many videos play in a session.
    // ------------------------------------------------------------------

    var activeVideo = null;
    var playerObserver = null;
    var activeCleanups = [];

    function registerCleanup(fn) {
        activeCleanups.push(fn);
    }

    function releaseActiveVideo() {
        var previousVideo = activeVideo;
        var cleanups = activeCleanups;
        activeCleanups = [];
        for (var i = 0; i < cleanups.length; i++) {
            try { cleanups[i](); } catch (e) { /* ignore */ }
        }
        // The same media element can survive a YouTube SPA navigation. Reset
        // hook flags after teardown so activateVideo() reattaches resources when
        // that element is immediately activated again.
        if (previousVideo) {
            previousVideo._wblockAutoPiPHooked = false;
            previousVideo._wblockControlsGuarded = false;
            previousVideo._wblockControlsPatched = false;
        }
        activeVideo = null;
        pipActive = false;
    }

    // Activate a video element: tear down the previous video's resources first,
    // then apply every per-video enhancement. Called on first transform and again
    // whenever the player recreates its <video> element.
    function activateVideo(player, video) {
        releaseActiveVideo();
        activeVideo = video;
        forceNativeControls(video);
        guardNativeControls(video);
        // Keep YouTube's media listeners intact. SABR/MSE uses waiting,
        // stalled, progress, and related events to maintain the stream.
        // On iOS, custom controls inside #movie_player are not reliable:
        // YouTube/native media handling can consume the touch before it reaches
        // the toolbar. Let Safari own the complete interaction surface there.
        if (!IS_IOS) { buildToolbar(player, video); }
        setupAutoPiP(video);
    }

    function restoreNativeMediaCapabilities(video) {
        if (!video) return;
        try {
            if (!video.controls) { video.controls = true; }
            if (!video.hasAttribute('controls')) { video.setAttribute('controls', ''); }
            ensurePlaysInline(video);
            // YouTube may suppress native PiP and fullscreen-adjacent controls
            // while its custom chrome is active. Those restrictions no longer
            // apply once Safari's native controls own interaction.
            if (video.hasAttribute('controlslist')) { video.removeAttribute('controlslist'); }
            if (video.hasAttribute('disablepictureinpicture')) { video.removeAttribute('disablepictureinpicture'); }
            if (video.disablePictureInPicture) { video.disablePictureInPicture = false; }

            if (IS_IOS) {
                // YouTube's iOS SABR pipeline uses ManagedMediaSource through a
                // blob URL. WebKit requires remote playback to stay disabled
                // unless the element also provides a network source for AirPlay.
                // Forcing AirPlay on can leave the physical-device media pipeline
                // loading forever even though desktop WebKit keeps playing.
                if (!video.disableRemotePlayback) { video.disableRemotePlayback = true; }
                if (!video.hasAttribute('disableremoteplayback')) {
                    video.setAttribute('disableremoteplayback', '');
                }
                if (video.getAttribute('x-webkit-airplay') === 'allow') {
                    video.removeAttribute('x-webkit-airplay');
                }
            } else {
                // Desktop Safari can safely expose AirPlay too.
                if (video.hasAttribute('disableremoteplayback')) { video.removeAttribute('disableremoteplayback'); }
                if (video.disableRemotePlayback) { video.disableRemotePlayback = false; }
                if (video.getAttribute('x-webkit-airplay') !== 'allow') {
                    video.setAttribute('x-webkit-airplay', 'allow');
                }
            }
        } catch (e) { /* ignore */ }
    }

    function forceNativeControls(video) {
        if (video._wblockControlsPatched) return;
        video._wblockControlsPatched = true;
        restoreNativeMediaCapabilities(video);
    }

    // WebKit renders Safari's native controls from the controls content
    // attribute. Do not replace the native property descriptor: early instance
    // shadowing can break WebKit's own media-controls initialization. Restore the
    // attribute at each mutation microtask instead.
    function guardNativeControls(video) {
        if (!video || video._wblockControlsGuarded) return;
        video._wblockControlsGuarded = true;

        function restore() { restoreNativeMediaCapabilities(video); }

        var observer = null;
        try {
            observer = new MutationObserver(restore);
            observer.observe(video, {
                attributes: true,
                attributeFilter: [
                    'controls', 'controlslist', 'disablepictureinpicture',
                    'disableremoteplayback', 'playsinline',
                    'webkit-playsinline', 'x-webkit-airplay'
                ]
            });
        } catch (e) { /* ignore */ }

        restore();

        registerCleanup(function () {
            if (observer) { try { observer.disconnect(); } catch (e) { /* ignore */ } }
        });
    }

    // Ensure inline playback on iOS/iPadOS. Without `playsinline`, iOS opens the
    // video in the fullscreen system player instead of playing inline. YouTube's
    // desktop player (served to iPadOS by default) may omit this attribute, and
    // since we reuse YouTube's <video> element we must set it ourselves.
    function ensurePlaysInline(video) {
        if (!video) return;
        try {
            if (!video.playsInline) { video.playsInline = true; }
            if (!video.hasAttribute('playsinline')) { video.setAttribute('playsinline', ''); }
            if (!video.hasAttribute('webkit-playsinline')) { video.setAttribute('webkit-playsinline', ''); }
        } catch (e) { /* ignore */ }
    }

    function findPlayer() {
        var candidates = [];
        function add(raw) {
            if (!raw) return;
            var player = raw.matches && raw.matches('.html5-video-player') ? raw :
                (raw.querySelector && raw.querySelector('.html5-video-player')) || raw;
            if (!player.querySelector || !player.querySelector('video')) return;
            if (candidates.indexOf(player) === -1) { candidates.push(player); }
        }

        var known = document.querySelectorAll('#movie_player, .html5-video-player');
        for (var i = 0; i < known.length; i++) { add(known[i]); }
        if (!candidates.length) {
            var wrappers = document.querySelectorAll('ytd-player, ytm-player, #player-container');
            for (var w = 0; w < wrappers.length; w++) { add(wrappers[w]); }
        }
        if (!candidates.length) return null;
        if (candidates.length === 1) return candidates[0];
        var visiblePlaying = null;
        for (var p = 0; p < candidates.length; p++) {
            if (candidates[p].classList.contains('playing-mode') &&
                candidates[p].getAttribute('aria-hidden') !== 'true' && !candidates[p].hidden) {
                if (visiblePlaying) { visiblePlaying = null; break; }
                visiblePlaying = candidates[p];
            }
        }
        if (visiblePlaying) return visiblePlaying;

        // Desktop Shorts can retain multiple player instances. Prefer the
        // visible, initialized, currently-playing one instead of the first DOM
        // match, which is commonly an offscreen previous Short.
        var best = candidates[0];
        var bestScore = -Infinity;
        for (var c = 0; c < candidates.length; c++) {
            var candidate = candidates[c];
            var video = candidate.querySelector('video');
            var score = 0;
            try {
                if (candidate.getAttribute('aria-hidden') === 'true' || candidate.hidden) { score -= 200; }
                if (candidate.classList.contains('playing-mode')) { score += 80; }
                if (video.currentSrc || video.src) { score += 30; }
                if (video.readyState > 0) { score += 30; }
                if (!video.paused && !video.ended) { score += 100; }
                var rect = candidate.getBoundingClientRect();
                if (rect.width > 1 && rect.height > 1 &&
                    rect.bottom > 0 && rect.right > 0 &&
                    rect.top < window.innerHeight && rect.left < window.innerWidth) {
                    score += 60;
                }
                var style = getComputedStyle(candidate);
                if (style.display === 'none' || style.visibility === 'hidden') { score -= 200; }
            } catch (e) { /* keep the structural score */ }
            if (score > bestScore) {
                best = candidate;
                bestScore = score;
            }
        }
        return best;
    }

    function transformPlayer() {
        var player = findPlayer();
        if (!player) return;

        var video = player.querySelector('video');
        if (!video) return;

        // Check if we already processed this video
        var videoId = '';
        try {
            var params = new URLSearchParams(location.search);
            videoId = params.get('v') || '';
        } catch (e) { /* ignore */ }

        if (player.getAttribute(ATTR_CLEANED) === videoId && activeVideo === video) return;
        player.setAttribute(ATTR_CLEANED, videoId);

        log('transforming player for', videoId || '(unknown)');

        // 1. Mark the video as native by adding a wrapper class
        player.classList.add('wblock-tc-native');

        // 2-5. Apply all per-video enhancements (native controls, PiP/inline
        // attributes, controls guard, toolbar, auto-PiP).
        // activateVideo first tears down the previous video's resources so
        // nothing leaks across SPA navigations.
        activateVideo(player, video);

        // 6. Apply audio-only preference on desktop only. Hiding the <video>
        // on iOS also hides Safari's native controls, and the mode never reduced
        // SABR video transfer in the first place. Clear old persisted state so
        // users cannot remain trapped on a black, non-interactive player.
        if (IS_IOS) {
            if (isAudioOnly()) { setAudioOnly(false); }
            setAudioOnlyStyles(false);
        } else {
            setAudioOnlyStyles(isAudioOnly());
        }

        // 7. Enable background playback
        enableBackgroundPlayback();

        // 8. Fixed quality ranges can stall YouTube's SABR pipeline on iOS.
        // The custom quality UI is desktop-only, so migrate old mobile state
        // back to YouTube's adaptive range and never start the retry loop there.
        if (IS_IOS) {
            if (getPreferredQuality() !== 'auto') { setPreferredQuality('auto'); }
            setQuality('auto');
        } else {
            var qualityDelay = setTimeout(function () {
                qualityDelay = null;
                applyPreferredQuality();
            }, 3000);
            registerCleanup(function () {
                if (qualityDelay !== null) {
                    clearTimeout(qualityDelay);
                    qualityDelay = null;
                }
            });
        }

        // 7. Observe for video element recreation. The player element persists
        // across SPA navigations, so disconnect any previous observer before
        // creating a new one to avoid accumulating observers.
        if (playerObserver) {
            try { playerObserver.disconnect(); } catch (e) { /* ignore */ }
        }
        playerObserver = new MutationObserver(function () {
            var newVid = player.querySelector('video');
            if (newVid && newVid !== activeVideo) {
                log('re-patching new video element');
                activateVideo(player, newVid);
            }
        });
        playerObserver.observe(player, { childList: true, subtree: true });

        log('player transformed');
    }

    // ------------------------------------------------------------------
    // Quality control via YouTube's internal player UI
    // ------------------------------------------------------------------

    // YouTube's quality labels match quality strings
    var QUALITY_LABELS = {
        auto: 'Auto',
        hd2160: '4K',
        hd1440: '1440p',
        hd1080: '1080p',
        hd720: '720p',
        large: '480p',
        medium: '360p',
        small: '240p',
        tiny: '144p'
    };

    // Ordered from highest to lowest (excluding 'auto')
    var QUALITY_ORDER = [
        'hd2160', 'hd1440', 'hd1080', 'hd720',
        'large', 'medium', 'small', 'tiny'
    ];

    function getAvailableQualities() {
        var player = findPlayer();
        if (!player || !player.getAvailableQualityLevels) return [];
        var levels = player.getAvailableQualityLevels();
        if (!levels || !levels.length) return [];
        // levels is ordered highest-first, may include 'auto'
        return levels.filter(function (q) { return q && q !== 'auto'; });
    }

    function getCurrentQuality() {
        var player = findPlayer();
        if (!player || !player.getPlaybackQuality) return 'auto';
        var q = player.getPlaybackQuality();
        return q || 'auto';
    }

    // Click YouTube's internal settings button to open the quality menu
    function openSettingsMenu(player) {
        var settingsBtn = player.querySelector('.ytp-settings-button') ||
            player.querySelector('[aria-label="Settings"]') ||
            player.querySelector('.ytp-button[aria-label*="Settings"]');
        if (!settingsBtn) { warn('openSettings: no settings button'); return false; }
        var expanded = settingsBtn.getAttribute('aria-expanded') === 'true' ||
            player.classList.contains('ytp-settings-menu-open');
        if (!expanded) { settingsBtn.click(); }
        return true;
    }

    // Find the quality menu item in the settings panel
    function clickQualityMenuItem(player) {
        var menuItems = player.querySelectorAll('.ytp-menuitem');
        for (var i = 0; i < menuItems.length; i++) {
            var item = menuItems[i];
            var content = item.querySelector('.ytp-menuitem-content');
            if (content && content.textContent && content.textContent.match(/\d{3,}/)) {
                // This is the quality menu item (has resolution numbers)
                item.click();
                return true;
            }
        }
        // Alternative: look for the label
        for (var j = 0; j < menuItems.length; j++) {
            var label = menuItems[j].querySelector('.ytp-menuitem-label');
            if (label && label.textContent && label.textContent.toLowerCase().indexOf('quality') !== -1) {
                menuItems[j].click();
                return true;
            }
        }
        return false;
    }

    // Click a specific quality option in the quality submenu
    function clickQualityOption(player, target) {
        var targetLabel = QUALITY_LABELS[target] || target;
        // Try to find by quality label text (e.g. "1080p", "720p")
        var allOptions = player.querySelectorAll('.ytp-quality-menu .ytp-menuitem, ' +
            '.ytp-drop-down-menu-button, [role="menuitemradio"], ' +
            '.ytp-panel-menu .ytp-menuitem');

        // Look for the label that matches our target
        var items = [];
        for (var i = 0; i < allOptions.length; i++) items.push(allOptions[i]);

        // Sort: prefer exact match, then partial match
        var bestMatch = null;
        var bestScore = -1;
        for (var j = 0; j < items.length; j++) {
            var text = items[j].textContent || '';
            var score = 0;
            if (text.indexOf(targetLabel) !== -1) score = 2;
            else if (text.indexOf(target) !== -1) score = 1;
            if (score > bestScore) {
                bestScore = score;
                bestMatch = items[j];
            }
        }

        if (bestMatch && bestScore > 0) {
            log('clicking quality option:', bestMatch.textContent);
            bestMatch.click();
            return true;
        }

        return false;
    }

    // Close the settings panel
    function closeSettingsPanel(player) {
        var backBtn = player.querySelector('.ytp-panel-header button');
        if (backBtn) {
            backBtn.click();
            return true;
        }
        // Click the settings button again to toggle it closed
        var settingsBtn = player.querySelector('.ytp-settings-button');
        if (settingsBtn) {
            settingsBtn.click();
        }
        return false;
    }

    function setQuality(target) {
        var player = findPlayer();
        if (!player) { warn('setQuality: no player'); return false; }

        if (target === 'auto') {
            // Reset to auto by setting a wide range via API and remove the
            // fixed-quality bias previously written by Tube Cleaner.
            if (player.setPlaybackQualityRange) {
                try { player.setPlaybackQualityRange('tiny', 'hd2160'); } catch (e) { /* ignore */ }
            }
            try { localStorage.removeItem('yt-player-quality'); } catch (e) { /* ignore */ }
            return true;
        }

        var levels = getAvailableQualities();
        if (levels.indexOf(target) === -1) {
            // Target not available, pick the closest lower quality
            var targetIdx = QUALITY_ORDER.indexOf(target);
            for (var i = targetIdx + 1; i < QUALITY_ORDER.length; i++) {
                if (levels.indexOf(QUALITY_ORDER[i]) !== -1) {
                    target = QUALITY_ORDER[i];
                    break;
                }
            }
        }

        log('setQuality:', target, 'available:', levels);

        var worked = false;

        // Approach 1: Simulate clicks on YouTube's quality UI (most reliable)
        // This is what YouTube Auto HD does and it works on the SABR player.
        try {
            if (openSettingsMenu(player)) {
                setTimeout(function () {
                    if (clickQualityMenuItem(player)) {
                        setTimeout(function () {
                            if (clickQualityOption(player, target)) {
                                worked = true;
                                log('UI click approach succeeded for', target);
                            }
                            // Close the settings panel
                            setTimeout(function () {
                                closeSettingsPanel(player);
                            }, 100);
                        }, 200);
                    } else {
                        // If we can't find the quality menu, close settings
                        closeSettingsPanel(player);
                    }
                }, 200);
            }
        } catch (e) { warn('UI click approach failed', e); }

        // Approach 2: setPlaybackQualityRange (may work on non-SABR players)
        if (player.setPlaybackQualityRange) {
            try {
                log('calling setPlaybackQualityRange', target, target);
                player.setPlaybackQualityRange(target, target);
                worked = true;
            } catch (e) { /* ignore */ }
        }

        // Approach 3: setPlaybackQuality (older API — no-op on SABR)
        if (player.setPlaybackQuality) {
            try {
                log('calling setPlaybackQuality', target);
                player.setPlaybackQuality(target);
            } catch (e) { /* ignore */ }
        }

        // Approach 4: set the yt-player-quality in localStorage as a bias
        try {
            localStorage.setItem('yt-player-quality', JSON.stringify({
                quality: target,
                previousQuality: 'auto',
                expiry: Date.now() + 86400000
            }));
        } catch (e) { /* ignore */ }

        log('setQuality complete, UI click:', worked);
        return worked;
    }

    function applyPreferredQuality() {
        var preferred = getPreferredQuality();
        if (preferred === 'auto') return;
        // Retry a few times — the player may not be fully ready.
        var attempts = 0;
        var timer = null;
        function stop() {
            if (timer !== null) {
                clearInterval(timer);
                timer = null;
            }
        }
        timer = setInterval(function () {
            attempts++;
            var current = getCurrentQuality();
            if (current === preferred || attempts > 10) {
                stop();
                return;
            }
            setQuality(preferred);
        }, 500);
        registerCleanup(stop);
    }

    // ------------------------------------------------------------------
    // Toolbar overlay (quality, audio-only, PiP)
    // ------------------------------------------------------------------

    function buildToolbar(player, video) {
        var existing = player.querySelector('.wblock-tc-toolbar');
        if (existing) {
            if (existing._wblockQualityTimer) clearInterval(existing._wblockQualityTimer);
            existing.remove();
        }

        var toolbar = document.createElement('div');
        toolbar.className = 'wblock-tc-toolbar';
        // Position at bottom-right above Safari's native controls. On iOS the
        // native controls consume touch events, so this toolbar must stay visible
        // rather than relying on a tap bubbling through the media-controls layer.
        var toolbarBottom = IS_IOS ? 'calc(56px + env(safe-area-inset-bottom, 0px))' : '42px';
        var toolbarRight = IS_IOS ? 'max(8px, env(safe-area-inset-right, 0px))' : '8px';
        var toolbarOpacity = IS_IOS ? '1' : '0.75';
        var toolbarFont = IS_IOS ? '14px' : '11px';
        toolbar.style.cssText = 'position:absolute;bottom:' + toolbarBottom + ';right:' + toolbarRight + ';z-index:2147483646;display:flex;gap:6px;align-items:center;pointer-events:auto;font:' + toolbarFont + '/1.2 -apple-system,system-ui,sans-serif;opacity:' + toolbarOpacity + ';transition:opacity 0.15s';

        var btnStyle = 'background:rgba(0,0,0,0.7);color:#fff;border:none;border-radius:4px;padding:3px 8px;font-size:11px;cursor:pointer;-webkit-user-select:none;user-select:none';
        // On iOS, use larger touch targets (minimum 44pt)
        if (IS_IOS) {
            btnStyle = 'background:rgba(0,0,0,0.78);color:#fff;border:none;border-radius:8px;padding:8px 12px;min-width:44px;min-height:44px;font-size:14px;cursor:pointer;-webkit-user-select:none;user-select:none;touch-action:manipulation';
        }

        // Quality selector
        var qualityBtn = document.createElement('button');
        qualityBtn.className = 'wblock-tc-quality-button';
        qualityBtn.type = 'button';
        qualityBtn.style.cssText = btnStyle;
        function updateQualityBtn() {
            var current = getCurrentQuality();
            var label = QUALITY_LABELS[current] || current;
            qualityBtn.textContent = label;
            qualityBtn.title = 'Video quality (click to change)';
        }
        updateQualityBtn();

        // Quality dropdown — opens upward since toolbar is at bottom
        var qualityMenu = document.createElement('div');
        qualityMenu.className = 'wblock-tc-quality-menu';
        var menuFont = IS_IOS ? '16px' : '12px';
        var menuPadding = IS_IOS ? '8px 0' : '4px 0';
        var menuMinWidth = IS_IOS ? '140px' : '100px';
        qualityMenu.style.cssText = 'position:absolute;bottom:100%;right:0;margin-bottom:4px;box-sizing:border-box;background:rgba(0,0,0,0.92);border-radius:5px;padding:' + menuPadding + ';min-width:' + menuMinWidth + ';max-height:60vh;overflow-y:auto;-webkit-overflow-scrolling:touch;display:none;z-index:70;font:' + menuFont + '/1.8 -apple-system,system-ui,sans-serif';

        function buildQualityMenu() {
            // Clear safely — avoid innerHTML which triggers TrustedHTML CSP
            while (qualityMenu.firstChild) {
                qualityMenu.removeChild(qualityMenu.firstChild);
            }
            var levels = getAvailableQualities();
            var preferred = getPreferredQuality();

            var itemPadding = IS_IOS ? '10px 16px' : '4px 12px';

            // Auto option
            var autoItem = document.createElement('div');
            autoItem.style.cssText = 'padding:' + itemPadding + ';cursor:pointer;color:#fff;white-space:nowrap';
            autoItem.textContent = 'Auto';
            if (preferred === 'auto') {
                autoItem.style.color = '#4fc3f7';
            }
            autoItem.addEventListener('click', function (e) {
                e.stopPropagation();
                setPreferredQuality('auto');
                setQuality('auto');
                updateQualityBtn();
                qualityMenu.style.display = 'none';
            });
            autoItem.addEventListener('mouseenter', function () { this.style.background = 'rgba(255,255,255,0.15)'; });
            autoItem.addEventListener('mouseleave', function () { this.style.background = ''; });
            qualityMenu.appendChild(autoItem);

            // Available quality levels
            for (var i = 0; i < levels.length; i++) {
                (function (q) {
                    var item = document.createElement('div');
                    item.style.cssText = 'padding:' + itemPadding + ';cursor:pointer;color:#fff;white-space:nowrap';
                    item.textContent = QUALITY_LABELS[q] || q;
                    if (preferred === q) {
                        item.style.color = '#4fc3f7';
                    }
                    item.addEventListener('click', function (e) {
                        e.stopPropagation();
                        setPreferredQuality(q);
                        setQuality(q);
                        updateQualityBtn();
                        qualityMenu.style.display = 'none';
                    });
                    item.addEventListener('mouseenter', function () { this.style.background = 'rgba(255,255,255,0.15)'; });
                    item.addEventListener('mouseleave', function () { this.style.background = ''; });
                    qualityMenu.appendChild(item);
                })(levels[i]);
            }
        }

        qualityBtn.addEventListener('click', function (e) {
            e.stopPropagation();
            if (qualityMenu.style.display === 'none') {
                buildQualityMenu();
                if (IS_IOS) {
                    var playerRect = player.getBoundingClientRect();
                    var toolbarRect = toolbar.getBoundingClientRect();
                    var roomAbove = Math.floor(toolbarRect.top - playerRect.top - 8);
                    qualityMenu.style.maxHeight = Math.max(44, roomAbove) + 'px';
                }
                qualityMenu.style.display = 'block';
            } else {
                qualityMenu.style.display = 'none';
            }
        });

        // Close menu on outside click
        function onDocumentClick() {
            qualityMenu.style.display = 'none';
        }
        document.addEventListener('click', onDocumentClick);
        registerCleanup(function () {
            document.removeEventListener('click', onDocumentClick);
        });

        var qualityWrap = document.createElement('div');
        qualityWrap.style.cssText = 'position:relative';
        qualityWrap.appendChild(qualityBtn);
        qualityWrap.appendChild(qualityMenu);
        toolbar.appendChild(qualityWrap);

        // Update quality label periodically. Store the timer on the toolbar so
        // it can be cleared when the toolbar is rebuilt (avoids a leak across
        // video-element re-creation).
        toolbar._wblockQualityTimer = setInterval(updateQualityBtn, 2000);
        registerCleanup(function () {
            if (toolbar._wblockQualityTimer) {
                clearInterval(toolbar._wblockQualityTimer);
                toolbar._wblockQualityTimer = null;
            }
        });

        // Audio-only toggle
        var audioBtn = document.createElement('button');
        audioBtn.className = 'wblock-tc-audio-button';
        audioBtn.type = 'button';
        audioBtn.style.cssText = btnStyle;
        function updateAudioBtn() {
            audioBtn.textContent = isAudioOnly() ? 'Video' : 'Audio';
            audioBtn.title = isAudioOnly() ? 'Switch to video mode' : 'Switch to audio-only mode';
        }
        updateAudioBtn();
        audioBtn.addEventListener('click', function (e) {
            e.stopPropagation();
            var next = !isAudioOnly();
            setAudioOnly(next);
            setAudioOnlyStyles(next);
            updateAudioBtn();
        });
        toolbar.appendChild(audioBtn);

        // PiP button is intentionally omitted — Safari's native controls
        // already provide PiP. Auto PiP handles automatic PiP entry.

        // Keep the compact mobile toolbar visible. Native iOS media controls
        // consume taps before they bubble to #movie_player, so tap-to-reveal is
        // not reliable on actual iPhone/iPad hardware.
        if (IS_IOS) {
            toolbar.style.opacity = '1';
            toolbar.style.pointerEvents = 'auto';
        } else {
            // Start hidden on desktop — it appears with native controls
            toolbar.style.opacity = '0';
            toolbar.style.pointerEvents = 'none';

            var toolbarTimer = null;
            var TOOLBAR_HIDE_DELAY = 3000;

            function showToolbar() {
                toolbar.style.opacity = '1';
                toolbar.style.pointerEvents = 'auto';
                clearTimeout(toolbarTimer);
            }

            function hideToolbar() {
                toolbar.style.opacity = '0';
                toolbar.style.pointerEvents = 'none';
            }

            function scheduleHideToolbar() {
                clearTimeout(toolbarTimer);
                toolbarTimer = setTimeout(hideToolbar, TOOLBAR_HIDE_DELAY);
            }

            // Listen for mouse movement anywhere on the player to show
            // toolbar (same trigger as Safari's native controls)
            //
            // We use a document-level mousemove listener and check if
            // the mouse is over the player area. This is more reliable
            // than listening on the player element because YouTube's
            // overlay divs (html5-video-container, etc.) sit on top and
            // can intercept mouse events.
            var _isOverPlayer = false;
            function onDocumentMouseMove(e) {
                var rect = player.getBoundingClientRect();
                var over = e.clientX >= rect.left && e.clientX <= rect.right &&
                    e.clientY >= rect.top && e.clientY <= rect.bottom;
                if (over && !_isOverPlayer) {
                    _isOverPlayer = true;
                    showToolbar();
                }
                if (over) {
                    scheduleHideToolbar();
                }
                if (!over && _isOverPlayer) {
                    _isOverPlayer = false;
                    scheduleHideToolbar();
                }
            }
            document.addEventListener('mousemove', onDocumentMouseMove);

            // Also show on mouse entering the player from outside
            function onPlayerMouseEnter() { showToolbar(); }
            player.addEventListener('mouseenter', onPlayerMouseEnter);

            // Keep visible while hovering directly over toolbar
            toolbar.addEventListener('mouseenter', function () {
                showToolbar();
                clearTimeout(toolbarTimer);
            });

            toolbar.addEventListener('mouseleave', function () {
                scheduleHideToolbar();
            });

            // Show on keyboard focus (tab navigation)
            toolbar.addEventListener('focusin', function () {
                showToolbar();
            });

            // Hide when video starts playing (controls auto-hide)
            function onVideoPlay() { scheduleHideToolbar(); }
            video.addEventListener('play', onVideoPlay);

            // Show when video is paused
            function onVideoPause() { showToolbar(); }
            video.addEventListener('pause', onVideoPause);

            // Show toolbar briefly when entering PiP (user can interact)
            var presentationTimer = null;
            function onPresentationModeChange() {
                if (video.webkitPresentationMode === 'picture-in-picture') {
                    showToolbar();
                    clearTimeout(presentationTimer);
                    presentationTimer = setTimeout(hideToolbar, 3000);
                }
            }
            video.addEventListener('webkitpresentationmodechanged', onPresentationModeChange);

            registerCleanup(function () {
                clearTimeout(toolbarTimer);
                clearTimeout(presentationTimer);
                document.removeEventListener('mousemove', onDocumentMouseMove);
                player.removeEventListener('mouseenter', onPlayerMouseEnter);
                video.removeEventListener('play', onVideoPlay);
                video.removeEventListener('pause', onVideoPause);
                video.removeEventListener('webkitpresentationmodechanged', onPresentationModeChange);
            });
        }

        // Show on CSS class toggle (for keyboard shortcuts)
        toolbar.classList.add('wblock-tc-toolbar-built');

        player.appendChild(toolbar);
        registerCleanup(function () {
            if (toolbar.parentNode) { toolbar.parentNode.removeChild(toolbar); }
        });
    }

    // ------------------------------------------------------------------
    // SPA navigation handling
    // ------------------------------------------------------------------

    var lastUrl = '';

    function onNavigate() {
        if (location.href === lastUrl) return;
        lastUrl = location.href;

        var player = findPlayer();
        if (player) {
            player.removeAttribute(ATTR_CLEANED);
            // Never remove wblock-tc-native here. Keeping the native class on
            // the persistent player prevents YouTube chrome flashing while the
            // SPA swaps video/page data.
        }

        transformPlayer();
        // Recovery only. The player/document observers are the primary path.
        setTimeout(transformPlayer, 100);
        setTimeout(transformPlayer, 500);
    }

    function watchNavigation() {
        document.addEventListener('yt-navigate-start', onNavigate, true);
        document.addEventListener('yt-navigate-finish', onNavigate, true);
        try {
            document.addEventListener('yt-page-data-updated', onNavigate, true);
        } catch (e) { /* ignore */ }
        window.addEventListener('popstate', onNavigate, true);
        // Poll for URL changes as a last-resort fallback only.
        setInterval(function () {
            if (location.href !== lastUrl) onNavigate();
        }, 1000);
    }

    // ------------------------------------------------------------------
    // Boot
    // ------------------------------------------------------------------

    var documentPlayerObserver = null;

    function nodeMayContainPlayer(node) {
        if (!node || node.nodeType !== 1) { return false; }
        try {
            if (node.tagName === 'VIDEO' || node.id === 'movie_player' ||
                node.id === 'player-container' ||
                node.matches('.html5-video-player, ytd-player')) {
                return true;
            }
            return !!node.querySelector('video, #movie_player, .html5-video-player, ytd-player, #player-container');
        } catch (e) { return false; }
    }

    function observeDocumentForPlayer() {
        if (documentPlayerObserver || typeof MutationObserver === 'undefined') { return; }
        documentPlayerObserver = new MutationObserver(function (records) {
            // The first parser mutation creates <html>; install anti-flash CSS
            // then even when the userscript itself ran before documentElement.
            injectStyles();
            var relevant = false;
            for (var i = 0; i < records.length && !relevant; i++) {
                var record = records[i];
                if (nodeMayContainPlayer(record.target)) { relevant = true; break; }
                for (var j = 0; j < record.addedNodes.length; j++) {
                    if (nodeMayContainPlayer(record.addedNodes[j])) {
                        relevant = true;
                        break;
                    }
                }
            }
            // MutationObserver runs before rendering. Transform now—no polling
            // interval or debounce—so YouTube chrome never reaches next paint.
            if (relevant) { transformPlayer(); }
        });
        try {
            documentPlayerObserver.observe(document, {
                childList: true,
                subtree: true,
                attributes: true,
                attributeFilter: ['id', 'class']
            });
        } catch (e) { /* ignore */ }
    }

    function boot() {
        observeDocumentForPlayer();
        injectStyles();
        enableBackgroundPlayback();
        lastUrl = location.href;
        watchNavigation();
        transformPlayer();

        // Recovery scans only; normal startup is handled pre-paint above.
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', transformPlayer, { once: true });
            window.addEventListener('load', transformPlayer, { once: true });
        }
    }

    boot();

    // Expose debug helpers on window for console testing
    try {
        window.__wblockTubeDebug = {
            getAvailableQualities: getAvailableQualities,
            getCurrentQuality: getCurrentQuality,
            setQuality: setQuality,
            getPreferredQuality: getPreferredQuality,
            setPreferredQuality: setPreferredQuality,
            QUALITY_LABELS: QUALITY_LABELS,
            getPlayer: findPlayer,
            inspectPlayer: function () {
                var p = findPlayer();
                if (!p) return 'no player';
                var methods = [];
                for (var k in p) {
                    if (typeof p[k] === 'function' &&
                        (k.indexOf('playback') !== -1 || k.indexOf('Quality') !== -1)) {
                        methods.push(k);
                    }
                }
                return {
                    methods: methods,
                    hasGetAvailableQualityLevels: typeof p.getAvailableQualityLevels === 'function',
                    hasGetAvailableQualityData: typeof p.getAvailableQualityData === 'function',
                    hasSetPlaybackQualityRange: typeof p.setPlaybackQualityRange === 'function',
                    hasSetPlaybackQuality: typeof p.setPlaybackQuality === 'function',
                    hasGetPlaybackQuality: typeof p.getPlaybackQuality === 'function',
                    levels: typeof p.getAvailableQualityLevels === 'function' ? p.getAvailableQualityLevels() : 'N/A',
                    qualityData: typeof p.getAvailableQualityData === 'function' ? p.getAvailableQualityData() : 'N/A',
                    current: typeof p.getPlaybackQuality === 'function' ? p.getPlaybackQuality() : 'N/A'
                };
            }
        };
        log('debug helpers exposed at window.__wblockTubeDebug');
    } catch (e) { /* ignore */ }
})();