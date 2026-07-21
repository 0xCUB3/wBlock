// ==UserScript==
// @name         Player Cleaner
// @namespace    com.skula.wblock
// @version      1.2.0
// @description  Replaces custom video players on websites (other than YouTube) with a clean HTML5 video element, restoring native controls, Picture-in-Picture, auto PiP, and background playback. Disable it per site from the wBlock toolbar if a player misbehaves.
// @description:de  Ersetzt benutzerdefinierte Video-Player auf Websites (außer YouTube) durch ein sauberes HTML5-Videoelement und stellt native Steuerelemente, Bild-in-Bild, automatisches PiP und Hintergrundwiedergabe wieder her. Deaktivieren Sie ihn bei Problemen pro Website in der wBlock-Symbolleiste.
// @description:es  Reemplaza los reproductores de vídeo personalizados en sitios web (distintos de YouTube) con un elemento de vídeo HTML5 limpio, restaurando los controles nativos, Picture-in-Picture, PiP automático y reproducción en segundo plano. Desactívelo por sitio desde la barra de herramientas de wBlock si un reproductor falla.
// @description:fr  Remplace les lecteurs vidéo personnalisés des sites web (autres que YouTube) par un élément vidéo HTML5 propre, en restaurant les commandes natives, l'image dans l'image, le PiP automatique et la lecture en arrière-plan. Désactivez-le par site depuis la barre d'outils wBlock si un lecteur se comporte mal.
// @description:it  Sostituisce i lettori video personalizzati sui siti web (diversi da YouTube) con un elemento video HTML5 pulito, ripristinando i controlli nativi, Picture-in-Picture, PiP automatico e riproduzione in background. Disattivalo per sito dalla barra degli strumenti di wBlock se un lettore non funziona.
// @description:pt-BR  Substitui players de vídeo personalizados em sites (diferentes do YouTube) por um elemento de vídeo HTML5 limpo, restaurando os controles nativos, Picture-in-Picture, PiP automático e reprodução em segundo plano. Desative-o por site na barra de ferramentas do wBlock se um player se comportar mal.
// @description:ja  YouTube以外のWebサイトのカスタム動画プレーヤーをクリーンなHTML5 video要素に置き換え、ネイティブコントロール、ピクチャー・イン・ピクチャー、自動PiP、バックグラウンド再生を復元します。プレーヤーが誤動作する場合は、wBlockツールバーからサイトごとに無効にできます。
// @description:ko  YouTube 이외의 웹사이트에서 사용자 지정 동영상 플레이어를 깨끗한 HTML5 video 요소로 대체하여 네이티브 컨트롤, PIP, 자동 PIP, 백그라운드 재생을 복원합니다. 플레이어가 오작동하면 wBlock 도구 막대에서 사이트별로 비활성화하세요.
// @description:ru  Заменяет пользовательские видеоплееры на сайтах (кроме YouTube) чистым HTML5-элементом video, восстанавливая нативные элементы управления, картинку-в-картинке, автоматический PiP и фоновое воспроизведение. Отключите его для сайта на панели wBlock, если плеер работает некорректно.
// @description:zh-Hans  将网站（YouTube 除外）上的自定义视频播放器替换为干净的 HTML5 video 元素，恢复原生控件、画中画、自动画中画和后台播放。如果某个播放器出现问题，可从 wBlock 工具栏按网站停用。
// @author       wBlock
// @match        http://*/*
// @match        https://*/*
// @exclude      https://www.youtube.com/*
// @exclude      https://m.youtube.com/*
// @exclude      https://music.youtube.com/*
// @exclude      https://www.youtube-nocookie.com/*
// @run-at       document-idle
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
    //   - Auto PiP: enters PiP on tab switch, window blur, scroll out of view
    //   - Background playback: keeps playing in background tabs
    //   - iOS toolbar: hidden by default, shows on tap, auto-hides
    //
    // YouTube is excluded; Tube Cleaner handles it. Per-site disabling is
    // provided by wBlock's userscript site settings.
    // ------------------------------------------------------------------

    var LOG_PREFIX = '[Player Cleaner]';
    var ATTR_DONE = 'data-wblock-player-cleaner';

    var IS_IOS = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
        (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

    // ------------------------------------------------------------------
    // Background playback — keep videos playing in background tabs
    // ------------------------------------------------------------------

    var _realHidden = false;
    var _realVisibility = 'visible';

    // Capture real visibility state before we override document.hidden
    try {
        _realHidden = document.hidden;
        _realVisibility = document.visibilityState;
    } catch (e) { /* ignore */ }

    document.addEventListener('visibilitychange', function () {
        try {
            _realHidden = document.hidden;
            _realVisibility = document.visibilityState;
        } catch (e) { /* ignore */ }
    });

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

    function setupAutoPiP(video) {
        if (!video || video._wblockAutoPiPHooked) return;
        video._wblockAutoPiPHooked = true;

        // Tab switch: enter PiP when tab hides, exit when visible
        document.addEventListener('visibilitychange', function () {
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
        });

        // Window blur: enter PiP when switching to another app
        window.addEventListener('blur', function () {
            if (!autoPiPEnabled) return;
            if (_realHidden) return;
            setTimeout(function () {
                if (document.hasFocus()) return;
                if (!video.paused && !video.ended) {
                    enterPiP(video);
                }
            }, 100);
        });

        window.addEventListener('focus', function () {
            if (!autoPiPEnabled) return;
            if (_realHidden) return;
            if (document.hasFocus() && isPiPActive(video)) {
                exitPiP(video);
            }
        });

        // Scroll out of view
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
        '.fp-player'                 // Flowplayer (inner)
    ];

    function isHttpUrl(value) {
        return typeof value === 'string' && /^https?:\/\//i.test(value);
    }

    function isPlayableUrl(value) {
        if (!isHttpUrl(value)) { return false; }
        // Prefer obviously-playable media; allow plain http(s) too since many
        // sites serve mp4/m3u8 from extensionless CDN URLs.
        return true;
    }

    // ------------------------------------------------------------------
    // Source discovery
    // ------------------------------------------------------------------

    function sourceFromVideoElement(video) {
        try {
            if (isHttpUrl(video.currentSrc)) { return video.currentSrc; }
            if (isHttpUrl(video.src) && video.src.indexOf('blob:') !== 0) { return video.src; }
            var sources = video.getElementsByTagName('source');
            for (var i = 0; i < sources.length; i++) {
                var src = sources[i].getAttribute('src');
                if (isHttpUrl(src)) { return src; }
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
                    var value = candidates[i].getAttribute(attrs[a]);
                    if (isPlayableUrl(value)) { return value; }
                }
            }
            var direct = container.getAttribute('data-src') || container.getAttribute('data-file') ||
                container.getAttribute('data-video-src');
            if (isPlayableUrl(direct)) { return direct; }
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
                        if (current && isPlayableUrl(current.src)) { return current.src; }
                        var list = player.currentSources ? player.currentSources() : [];
                        for (var i = 0; i < list.length; i++) {
                            if (isPlayableUrl(list[i].src)) { return list[i].src; }
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
                if (isPlayableUrl(item.file)) { return item.file; }
                var sources = item.sources || [];
                for (var i = 0; i < sources.length; i++) {
                    if (isPlayableUrl(sources[i].file)) { return sources[i].file; }
                }
            }
        } catch (e) { /* ignore */ }
        return null;
    }

    function discoverSource(container, video) {
        return sourceFromVideoElement(video) ||
            sourceFromVideojs(container) ||
            sourceFromJwPlayer(container) ||
            sourceFromDom(container) ||
            null;
    }

    // ------------------------------------------------------------------
    // Replacement
    // ------------------------------------------------------------------

    function copyRelevantAttributes(fromVideo, toVideo) {
        var attrs = ['poster', 'title', 'preload', 'loop', 'muted', 'autoplay'];
        for (var i = 0; i < attrs.length; i++) {
            var name = attrs[i];
            var value = fromVideo.getAttribute(name);
            if (value !== null) {
                try { toVideo.setAttribute(name, value); } catch (e) { /* ignore */ }
            }
        }
        // Carry over <track> elements (captions/subtitles).
        try {
            var tracks = fromVideo.getElementsByTagName('track');
            for (var t = 0; t < tracks.length; t++) {
                toVideo.appendChild(tracks[t].cloneNode(true));
            }
        } catch (e) { /* ignore */ }
    }

    function buildCleanVideo(src, originalVideo) {
        var video = document.createElement('video');
        video.controls = true;
        video.playsInline = true;
        video.setAttribute('playsinline', '');
        video.setAttribute('webkit-playsinline', '');
        video.removeAttribute('disablepictureinpicture');
        video.disablePictureInPicture = false;
        video.style.width = '100%';
        video.style.height = '100%';
        video.style.background = '#000';
        if (originalVideo) { copyRelevantAttributes(originalVideo, video); }
        if (src) { video.src = src; }
        return video;
    }

    function normalizeContainer(raw) {
        // Some selectors match inner elements; climb to the outermost player
        // wrapper so we replace the whole custom chrome, not just part of it.
        var container = raw;
        var wrapperSelectors = ['.video-js', '.jwplayer', '.jw-wrapper', '.plyr',
            '.flowplayer', '.mejs-container', '.mejs__container', '.clappr',
            '[data-clappr-player]', '.fluid_video_wrapper'];
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
        try {
            Object.defineProperty(video, 'controls', {
                get: function () { return true; },
                set: function (v) { /* ignore */ },
                configurable: false
            });
        } catch (e) { /* ignore */ }
        video.setAttribute('controls', '');
    }

    // WebKit renders native controls from the `controls` CONTENT ATTRIBUTE, not
    // the JavaScript property. forceNativeControls() shadows the property so
    // `video.controls = false` is ignored, but a player can still strip the
    // attribute via removeAttribute(), hiding the controls. A `!video.controls`
    // guard never fires because the shadowed getter always returns true. So we
    // defend the attribute itself: a MutationObserver restores it whenever it is
    // removed, with a polling fallback.
    function guardNativeControls(video) {
        if (!video || video._wblockControlsGuarded) return;
        video._wblockControlsGuarded = true;

        function restore() {
            if (video && !video.hasAttribute('controls')) {
                video.setAttribute('controls', '');
            }
        }

        try {
            var observer = new MutationObserver(restore);
            observer.observe(video, { attributes: true, attributeFilter: ['controls'] });
        } catch (e) { /* ignore */ }

        restore();
        setInterval(restore, 1000);
    }

    function enhanceInPlace(container, video) {
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

        setupAutoPiP(video);

        var overlaySelectors = [
            '.vjs-control-bar', '.vjs-big-play-button', '.vjs-poster',
            '.jw-controls', '.jw-display-icon-container',
            '.plyr__controls', '.fp-ui', '.fp-header',
            '.mejs-controls', '.mejs__controls',
            '.clappr-media-control'
        ];
        for (var i = 0; i < overlaySelectors.length; i++) {
            var overlays = container.querySelectorAll(overlaySelectors[i]);
            for (var j = 0; j < overlays.length; j++) {
                try { overlays[j].style.display = 'none'; } catch (e) { /* ignore */ }
            }
        }

        // Keep controls forced on
        guardNativeControls(video);
    }

    function replacePlayer(container) {
        if (container.getAttribute && container.getAttribute(ATTR_DONE)) { return; }
        var video = container.querySelector ? container.querySelector('video') : null;
        if (!video) { return; }
        if (video.getAttribute && video.getAttribute(ATTR_DONE)) { return; }

        var src = discoverSource(container, video);
        log('player detected', container.className, 'source:', src ? 'resolved' : 'opaque');

        enableBackgroundPlayback();

        if (src) {
            var clean = buildCleanVideo(src, video);
            clean.setAttribute(ATTR_DONE, '1');
            // Replace the container's contents with the clean video, keeping
            // the container itself so page layout/sizing still applies.
            while (container.firstChild) { container.removeChild(container.firstChild); }
            container.appendChild(clean);
            try {
                container.classList.remove('video-js', 'vjs-paused', 'vjs-playing');
            } catch (e) { /* ignore */ }
            container.setAttribute(ATTR_DONE, '1');
            forceNativeControls(clean);
            setupAutoPiP(clean);

            // Keep controls forced on
            guardNativeControls(clean);
        } else {
            video.setAttribute(ATTR_DONE, '1');
            container.setAttribute(ATTR_DONE, '1');
            enhanceInPlace(container, video);
        }
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

    function scan(root) {
        var scope = root || document;
        var seen = [];
        // Pass 1: known player-library containers (video.js, JW Player, Plyr...).
        for (var i = 0; i < PLAYER_SELECTORS.length; i++) {
            var nodes;
            try { nodes = scope.querySelectorAll(PLAYER_SELECTORS[i]); }
            catch (e) { continue; }
            for (var j = 0; j < nodes.length; j++) {
                var container = normalizeContainer(nodes[j]);
                if (!container || seen.indexOf(container) !== -1) { continue; }
                seen.push(container);
                try { replacePlayer(container); }
                catch (e) { log('replace failed', e); }
            }
        }
        // Pass 2: any other <video> whose native controls are suppressed by an
        // unrecognized custom player. Enhance in place only (never rebuild), so
        // an unknown wrapper's layout is left intact.
        var bareVideos;
        try { bareVideos = scope.querySelectorAll('video'); }
        catch (e) { bareVideos = []; }
        for (var k = 0; k < bareVideos.length; k++) {
            var video = bareVideos[k];
            if (!needsBareEnhancement(video)) { continue; }
            var bareContainer = video.parentElement || video;
            if (bareContainer.getAttribute && bareContainer.getAttribute(ATTR_DONE)) { continue; }
            log('bare player detected', bareContainer.className || '(no class)', 'enhancing in place');
            try {
                video.setAttribute(ATTR_DONE, '1');
                if (bareContainer.setAttribute) { bareContainer.setAttribute(ATTR_DONE, '1'); }
                enableBackgroundPlayback();
                enhanceInPlace(bareContainer, video);
            } catch (e) { log('bare enhance failed', e); }
        }
    }

    function observe() {
        if (typeof MutationObserver === 'undefined') { return; }
        var scheduled = false;
        var observer = new MutationObserver(function () {
            if (scheduled) { return; }
            scheduled = true;
            setTimeout(function () {
                scheduled = false;
                scan(document);
            }, 500);
        });
        try {
            observer.observe(document.documentElement, { childList: true, subtree: true });
        } catch (e) { /* ignore */ }
    }

    function boot() {
        scan(document);
        // Players often mount after idle; rescan a few times then observe.
        setTimeout(function () { scan(document); }, 800);
        setTimeout(function () { scan(document); }, 2000);
        observe();
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', boot, { once: true });
    } else {
        boot();
    }
})();
