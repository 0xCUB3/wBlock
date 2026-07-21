// ==UserScript==
// @name         Tube Cleaner
// @namespace    com.skula.wblock
// @version      4.0.0
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
    // Tube Cleaner v3.0.0
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

    var debug = true;

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

    var IS_IOS = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
        (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
    var IS_MOBILE_SITE = location.hostname === 'm.youtube.com' ||
        /mobi|android/i.test(navigator.userAgent);

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
                video.webkitSetPresentationMode('picture-in-picture');
                log('PiP entered');
            } else if (video.requestPictureInPicture) {
                video.requestPictureInPicture();
                log('PiP entered via API');
            }
        } catch (e) { warn('enterPiP failed', e); }
    }

    function exitPiP(video) {
        if (!video) return;
        if (!isPiPActive(video)) return;
        try {
            if (video.webkitSupportsPresentationMode &&
                typeof video.webkitSetPresentationMode === 'function') {
                video.webkitSetPresentationMode('inline');
                log('PiP exited');
            } else if (document.pictureInPictureElement) {
                document.exitPictureInPicture();
            }
        } catch (e) { warn('exitPiP failed', e); }
    }

    function setupAutoPiP(video) {
        if (!video || video._wblockAutoPiPHooked) return;
        video._wblockAutoPiPHooked = true;

        // Tab switch: enter PiP when tab hides, exit when visible
        // Note: enableBackgroundPlayback() overrides document.hidden to always
        // return false, so we use _realHidden which tracks the true state.
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
            if (_realHidden) return; // already handled by visibilitychange
            setTimeout(function () {
                if (document.hasFocus()) return; // focus moved within document
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
        video.addEventListener('webkitpresentationmodechanged', function () {
            log('presentation mode changed:', video.webkitPresentationMode);
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
        '{ display: block !important; }',

        // Ensure Safari's native media controls show up.
        '.wblock-tc-native video::-webkit-media-controls',
        '{ display: flex !important; opacity: 1 !important; visibility: visible !important; }',

        '.wblock-tc-native video::-webkit-media-controls-panel',
        '{ display: flex !important; opacity: 1 !important; }',

        // Make sure the video container allows native controls to
        // render by removing overflow hidden.
        '#movie_player .html5-video-container',
        '{ overflow: visible !important; }',

        // Let the native controls bar extend below the video.
        '.wblock-tc-native',
        '{ overflow: visible !important; }',

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
        if (document.getElementById(STYLE_ID)) { return; }
        var style = document.createElement('style');
        style.id = STYLE_ID;
        style.textContent = CSS;
        if (document.head) {
            document.head.appendChild(style);
        } else {
            document.documentElement.appendChild(style);
        }
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

    // Track real visibility state separately since we override document.hidden
    var _realHidden = false;
    var _realVisibility = 'visible';

    document.addEventListener('visibilitychange', function () {
        // Store the real state before it gets overridden
        try {
            _realHidden = document.hidden;
            _realVisibility = document.visibilityState;
        } catch (e) { /* ignore */ }
    });

    // Also capture the initial state
    try {
        _realHidden = document.hidden;
        _realVisibility = document.visibilityState;
    } catch (e) { /* ignore */ }

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

    function forceNativeControls(video) {
        // YouTube's player actively sets controls=false.  We intercept
        // the property setter to prevent that.  Safari's native controls
        // bar will then stay visible.
        if (video._wblockControlsPatched) return;
        video._wblockControlsPatched = true;

        video.controls = true;

        // Intercept the 'controls' property so YouTube can't turn it off
        try {
            Object.defineProperty(video, 'controls', {
                get: function () { return true; },
                set: function (v) { /* ignore YouTube's attempts to disable */ },
                configurable: false
            });
        } catch (e) {
            // If it fails (e.g. already defined), just try again periodically
        }

        // Also set the attribute directly in case YouTube uses setAttribute
        video.setAttribute('controls', '');
    }

    function transformPlayer() {
        var player = document.getElementById('movie_player');
        if (!player) {
            player = document.querySelector('.html5-video-player');
            if (!player) return;
        }

        var video = player.querySelector('video');
        if (!video) return;

        // Check if we already processed this video
        var videoId = '';
        try {
            var params = new URLSearchParams(location.search);
            videoId = params.get('v') || '';
        } catch (e) { /* ignore */ }

        if (player.getAttribute(ATTR_CLEANED) === videoId) return;
        player.setAttribute(ATTR_CLEANED, videoId);

        log('transforming player for', videoId || '(unknown)');

        // 1. Mark the video as native by adding a wrapper class
        player.classList.add('wblock-tc-native');

        // 2. Force Safari native controls (lock the property so YouTube
        //    can't turn them off)
        forceNativeControls(video);

        // 3. Enable PiP
        video.removeAttribute('disablepictureinpicture');
        video.disablePictureInPicture = false;

        // 4. Keep the original video element (it has the SABR/MSE
        //    pipeline attached by YouTube's player).  Cloning would
        //    lose the source buffers and cause 403s.
        //    Intercept addEventListener to block only YouTube's
        //    tracking/hijacking listeners, not the essential playback
        //    events that YouTube's player needs to manage the stream.
        if (!video._wblockPatched) {
            video._wblockPatched = true;
            var origAdd = video.addEventListener.bind(video);
            video.addEventListener = function (type, listener, options) {
                // Block only YouTube's tracking events, not the
                // essential playback events the player needs.
                var blocked = [
                    'timeupdate', 'progress', 'waiting', 'stalled',
                    'suspend', 'abort', 'emptied'
                ];
                if (blocked.indexOf(type) !== -1) {
                    return; // silently drop tracking
                }
                return origAdd(type, listener, options);
            };
        }

        // 5. Keep controls forced on (YouTube may try to remove them) — but
        //    don't fight it too aggressively; the Object.defineProperty handles it.
        var controlsGuard = setInterval(function () {
            if (video && !video.controls) {
                video.controls = true;
                video.setAttribute('controls', '');
            }
        }, 2000);

        // 6. Apply audio-only preference
        setAudioOnlyStyles(isAudioOnly());

        // 7. Enable background playback
        enableBackgroundPlayback();

        // 8. Build toolbar overlay
        buildToolbar(player, video);

        // 9. Apply preferred quality (deferred — let the player finish init)
        setTimeout(function () {
            applyPreferredQuality();
        }, 3000);

        // 10. Observe for video element recreation
        var observer = new MutationObserver(function () {
            var newVid = player.querySelector('video');
            if (newVid && newVid !== video) {
                log('re-patching new video element');
                video = newVid;
                forceNativeControls(video);
                video.disablePictureInPicture = false;
                buildToolbar(player, video);
            }
        });
        observer.observe(player, { childList: true, subtree: true });

        // 11. Hook player state changes to re-apply quality
        hookPlayerStateChanges();

        // 12. Setup auto PiP
        setupAutoPiP(video);

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
        var player = document.getElementById('movie_player');
        if (!player || !player.getAvailableQualityLevels) return [];
        var levels = player.getAvailableQualityLevels();
        if (!levels || !levels.length) return [];
        // levels is ordered highest-first, may include 'auto'
        return levels.filter(function (q) { return q && q !== 'auto'; });
    }

    function getCurrentQuality() {
        var player = document.getElementById('movie_player');
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
        // Click it twice to ensure it opens (first click closes, second opens)
        settingsBtn.click();
        settingsBtn.click();
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
            '.ytp-drop-down-menu-button, ' +
            '[role="menuitemradio"]');

        // Also try the panel menu items
        var panelItems = player.querySelectorAll('.ytp-panel-menu .ytp-menuitem');

        // Look for the label that matches our target
        var items = [];
        for (var i = 0; i < panelItems.length; i++) items.push(panelItems[i]);

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
        var player = document.getElementById('movie_player');
        if (!player) { warn('setQuality: no player'); return false; }

        if (target === 'auto') {
            // Reset to auto by setting a wide range via API
            if (player.setPlaybackQualityRange) {
                try { player.setPlaybackQualityRange('tiny', 'hd2160'); } catch (e) { /* ignore */ }
            }
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
        // Retry a few times — the player may not be fully ready
        var attempts = 0;
        var timer = setInterval(function () {
            attempts++;
            var current = getCurrentQuality();
            if (current === preferred || attempts > 10) {
                clearInterval(timer);
                return;
            }
            setQuality(preferred);
        }, 500);
    }

    var _qualityHooked = false;
    function hookPlayerStateChanges() {
        if (_qualityHooked) return;
        _qualityHooked = true;

        // Re-apply preferred quality when the player changes state
        // (e.g. new video loads, ad finishes, etc.)
        document.addEventListener('yt-player-state-change', function () {
            var preferred = getPreferredQuality();
            if (preferred !== 'auto') {
                setTimeout(function () { setQuality(preferred); }, 300);
            }
        });
    }

    // ------------------------------------------------------------------
    // Toolbar overlay (quality, audio-only, PiP)
    // ------------------------------------------------------------------

    function buildToolbar(player, video) {
        var existing = player.querySelector('.wblock-tc-toolbar');
        if (existing) existing.remove();

        var toolbar = document.createElement('div');
        toolbar.className = 'wblock-tc-toolbar';
        // Position at bottom-right, above native controls. Always visible but
        // semi-transparent, full opacity on hover.
        // On mobile (iOS/iPadOS) use larger touch targets and always-visible.
        var toolbarBottom = IS_IOS ? '12px' : '42px';
        var toolbarOpacity = IS_IOS ? '1' : '0.75';
        var toolbarFont = IS_IOS ? '14px' : '11px';
        toolbar.style.cssText = 'position:absolute;bottom:' + toolbarBottom + ';right:8px;z-index:60;display:flex;gap:6px;align-items:center;pointer-events:auto;font:' + toolbarFont + '/1.2 -apple-system,system-ui,sans-serif;opacity:' + toolbarOpacity + ';transition:opacity 0.15s';

        var btnStyle = 'background:rgba(0,0,0,0.7);color:#fff;border:none;border-radius:4px;padding:3px 8px;font-size:11px;cursor:pointer;-webkit-user-select:none;user-select:none';
        // On iOS, use larger touch targets (minimum 44pt)
        if (IS_IOS) {
            btnStyle = 'background:rgba(0,0,0,0.7);color:#fff;border:none;border-radius:6px;padding:8px 12px;font-size:14px;cursor:pointer;-webkit-user-select:none;user-select:none';
        }

        // Quality selector
        var qualityBtn = document.createElement('button');
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
        var menuFont = IS_IOS ? '16px' : '12px';
        var menuPadding = IS_IOS ? '8px 0' : '4px 0';
        var menuMinWidth = IS_IOS ? '140px' : '100px';
        qualityMenu.style.cssText = 'position:absolute;bottom:100%;right:0;margin-bottom:4px;background:rgba(0,0,0,0.9);border-radius:5px;padding:' + menuPadding + ';min-width:' + menuMinWidth + ';display:none;z-index:70;font:' + menuFont + '/1.8 -apple-system,system-ui,sans-serif';

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
                qualityMenu.style.display = 'block';
            } else {
                qualityMenu.style.display = 'none';
            }
        });

        // Close menu on outside click
        document.addEventListener('click', function () {
            qualityMenu.style.display = 'none';
        });

        var qualityWrap = document.createElement('div');
        qualityWrap.style.cssText = 'position:relative';
        qualityWrap.appendChild(qualityBtn);
        qualityWrap.appendChild(qualityMenu);
        toolbar.appendChild(qualityWrap);

        // Update quality label periodically
        setInterval(updateQualityBtn, 2000);

        // Audio-only toggle
        var audioBtn = document.createElement('button');
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

        // On iOS / iPadOS: hide by default, show on tap, auto-hide after
        // a few seconds (same behavior as Safari's native controls).
        if (IS_IOS) {
            toolbar.style.opacity = '0';
            toolbar.style.pointerEvents = 'none';

            var iosToolbarTimer = null;

            function showToolbarIOS() {
                toolbar.style.opacity = '1';
                toolbar.style.pointerEvents = 'auto';
                clearTimeout(iosToolbarTimer);
                iosToolbarTimer = setTimeout(function () {
                    toolbar.style.opacity = '0';
                    toolbar.style.pointerEvents = 'none';
                }, 4000);
            }

            // Show on tap anywhere on the player
            player.addEventListener('touchstart', showToolbarIOS, { passive: true });

            // Also show on play/pause (user tapped the native controls)
            video.addEventListener('play', showToolbarIOS);
            video.addEventListener('pause', showToolbarIOS);

            // Keep visible while tapping directly on toolbar buttons
            toolbar.addEventListener('touchstart', function (e) {
                e.stopPropagation();
                clearTimeout(iosToolbarTimer);
            }, { passive: true });

            // Hide after a timeout when a toolbar button is tapped
            toolbar.addEventListener('click', function () {
                clearTimeout(iosToolbarTimer);
                iosToolbarTimer = setTimeout(function () {
                    toolbar.style.opacity = '0';
                    toolbar.style.pointerEvents = 'none';
                }, 4000);
            });
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
            document.addEventListener('mousemove', function (e) {
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
            });

            // Also show on mouse entering the player from outside
            player.addEventListener('mouseenter', function () {
                showToolbar();
            });

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
            video.addEventListener('play', function () {
                scheduleHideToolbar();
            });

            // Show when video is paused
            video.addEventListener('pause', function () {
                showToolbar();
            });

            // Show toolbar briefly when entering PiP (user can interact)
            video.addEventListener('webkitpresentationmodechanged', function () {
                if (video.webkitPresentationMode === 'picture-in-picture') {
                    showToolbar();
                    setTimeout(hideToolbar, 3000);
                }
            });
        }

        // Show on CSS class toggle (for keyboard shortcuts)
        toolbar.classList.add('wblock-tc-toolbar-built');

        player.appendChild(toolbar);
    }

    // ------------------------------------------------------------------
    // SPA navigation handling
    // ------------------------------------------------------------------

    var lastUrl = '';

    function onNavigate() {
        if (location.href === lastUrl) return;
        lastUrl = location.href;

        var player = document.getElementById('movie_player') ||
            document.querySelector('.html5-video-player');
        if (player) {
            player.removeAttribute(ATTR_CLEANED);
            player.classList.remove('wblock-tc-native');
        }

        // Try to transform at intervals
        setTimeout(transformPlayer, 500);
        setTimeout(transformPlayer, 1500);
        setTimeout(transformPlayer, 3000);
    }

    function watchNavigation() {
        document.addEventListener('yt-navigate-finish', onNavigate, true);
        try {
            document.addEventListener('yt-page-data-updated', onNavigate, true);
        } catch (e) { /* ignore */ }
        window.addEventListener('popstate', onNavigate, true);
        // Poll for URL changes as a fallback
        setInterval(function () {
            if (location.href !== lastUrl) onNavigate();
        }, 1000);
    }

    // ------------------------------------------------------------------
    // Boot
    // ------------------------------------------------------------------

    function waitForPlayer() {
        var started = Date.now();
        var timer = setInterval(function () {
            var player = document.getElementById('movie_player') ||
                document.querySelector('.html5-video-player');
            // On mobile YouTube, the player may be in a different container
            if (!player && IS_MOBILE_SITE) {
                player = document.querySelector('ytd-player') ||
                    document.querySelector('#player-container');
            }
            var video = player && player.querySelector('video');
            if (player && video) {
                clearInterval(timer);
                transformPlayer();
            } else if (Date.now() - started > 15000) {
                clearInterval(timer);
                warn('timed out waiting for player');
            }
        }, 250);
    }

    function boot() {
        // Inject CSS immediately
        injectStyles();
        enableBackgroundPlayback();

        lastUrl = location.href;
        watchNavigation();
        waitForPlayer();
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', boot);
    } else {
        boot();
    }

    // Expose debug helpers on window for console testing
    try {
        window.__wblockTubeDebug = {
            getAvailableQualities: getAvailableQualities,
            getCurrentQuality: getCurrentQuality,
            setQuality: setQuality,
            getPreferredQuality: getPreferredQuality,
            setPreferredQuality: setPreferredQuality,
            QUALITY_LABELS: QUALITY_LABELS,
            getPlayer: function () { return document.getElementById('movie_player'); },
            inspectPlayer: function () {
                var p = document.getElementById('movie_player');
                if (!p) return 'no player';
                var methods = [];
                for (var k in p) {
                    if (typeof p[k] === 'function' && k.indexOf('playback') !== -1 || k.indexOf('Quality') !== -1) {
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