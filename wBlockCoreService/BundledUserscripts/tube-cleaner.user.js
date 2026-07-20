// ==UserScript==
// @name         Tube Cleaner
// @namespace    com.skula.wblock
// @version      1.0.0
// @description  Replaces the YouTube player with a minimal HTML5 video element. Removes in-video ads, stops play/pause/seek tracking, restores Picture-in-Picture, keeps videos playing in background tabs, and adds an audio-only mode.
// @description:de  Ersetzt den YouTube-Player durch ein minimales HTML5-Videoelement. Entfernt In-Video-Werbung, stoppt die Verfolgung von Wiedergabe/Pause/Spulen, stellt Bild-in-Bild wieder her, hält Videos in Hintergrund-Tabs am Laufen und fügt einen Nur-Audio-Modus hinzu.
// @description:es  Reemplaza el reproductor de YouTube con un elemento de vídeo HTML5 mínimo. Elimina los anuncios dentro del vídeo, detiene el seguimiento de reproducción/pausa/búsqueda, restaura Picture-in-Picture, mantiene los vídeos reproduciéndose en pestañas en segundo plano y añade un modo de solo audio.
// @description:fr  Remplace le lecteur YouTube par un élément vidéo HTML5 minimal. Supprime les publicités dans la vidéo, arrête le suivi lecture/pause/recherche, restaure l'image dans l'image, garde les vidéos en lecture dans les onglets en arrière-plan et ajoute un mode audio seul.
// @description:it  Sostituisce il lettore YouTube con un elemento video HTML5 minimale. Rimuove gli annunci in-video, interrompe il monitoraggio di riproduzione/pausa/ricerca, ripristina Picture-in-Picture, mantiene i video in riproduzione nelle schede in secondo piano e aggiunge una modalità solo audio.
// @description:pt-BR  Substitui o player do YouTube por um elemento de vídeo HTML5 mínimo. Remove anúncios no vídeo, interrompe o rastreamento de reprodução/pausa/busca, restaura o Picture-in-Picture, mantém os vídeos reproduzindo em abas em segundo plano e adiciona um modo somente áudio.
// @description:ja  YouTubeプレーヤーを最小限のHTML5 video要素に置き換えます。動画内広告を削除し、再生/一時停止/シークの追跡を停止し、ピクチャー・イン・ピクチャーを復元し、バックグラウンドタブで動画を再生し続け、音声のみのモードを追加します。
// @description:ko  YouTube 플레이어를 최소한의 HTML5 video 요소로 대체합니다. 동영상 내 광고를 제거하고, 재생/일시정지/탐색 추적을 중지하고, PIP를 복원하고, 백그라운드 탭에서 동영상 재생을 유지하고, 오디오 전용 모드를 추가합니다.
// @description:ru  Заменяет плеер YouTube минимальным HTML5-элементом video. Удаляет рекламу внутри видео, прекращает отслеживание воспроизведения/паузы/перемотки, восстанавливает картинку-в-картинке, продолжает воспроизведение во фоновых вкладках и добавляет режим только аудио.
// @description:zh-Hans  将 YouTube 播放器替换为极简的 HTML5 video 元素。移除视频内广告，停止播放/暂停/拖动跟踪，恢复画中画，让视频在后台标签页继续播放，并新增纯音频模式。
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
    // Tube Cleaner
    //
    // Replaces YouTube's player with a plain HTML5 <video> fed directly from
    // YouTube's streaming data. Because we play the raw media stream instead
    // of YouTube's player, in-video ads are never inserted, play/pause/seek
    // events are never reported, Picture-in-Picture works natively, and the
    // video keeps playing when the tab loses focus.
    //
    // This is a best-effort, from-scratch reimplementation. YouTube changes
    // its player frequently; when a stream cannot be resolved we fall back to
    // the original player so the page is never left broken.
    // ------------------------------------------------------------------

    var LOG_PREFIX = '[Tube Cleaner]';
    var STORAGE_AUDIO = 'wblock.tubeCleaner.audioOnly';
    var STORAGE_QUALITY = 'wblock.tubeCleaner.quality';
    var ATTR_MANAGED = 'data-wblock-tube-cleaner';
    var FALLBACK_HOSTS = ['www.youtube.com', 'm.youtube.com', 'music.youtube.com', 'www.youtube-nocookie.com'];

    function log() {
        try {
            if (window.__wblockTubeCleanerDebug) {
                console.log.apply(console, [LOG_PREFIX].concat([].slice.call(arguments)));
            }
        } catch (e) { /* ignore */ }
    }

    // ------------------------------------------------------------------
    // URL / video id helpers
    // ------------------------------------------------------------------

    function currentVideoId() {
        try {
            var path = location.pathname;
            var match = path.match(/^\/(?:watch|embed|shorts|v|live)\/?/);
            if (path === '/watch' || path.indexOf('/watch') === 0) {
                var params = new URLSearchParams(location.search);
                var v = params.get('v');
                if (v && v.length >= 11) { return v.slice(0, 11); }
                return null;
            }
            var m = path.match(/^\/(?:embed|shorts|v)\/([A-Za-z0-9_-]{11})/);
            if (m) { return m[1]; }
            if (path.indexOf('/live/') === 0) {
                var lm = path.match(/^\/live\/([A-Za-z0-9_-]{11})/);
                if (lm) { return lm[1]; }
            }
            return null;
        } catch (e) {
            return null;
        }
    }

    function isEmbedPage() {
        return location.pathname.indexOf('/embed/') === 0;
    }

    function requestedStartTime() {
        try {
            var params = new URLSearchParams(location.search);
            var t = params.get('t') || params.get('start');
            if (!t) { return 0; }
            if (/^\d+$/.test(t)) { return parseInt(t, 10); }
            var m = t.match(/(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?/);
            if (!m) { return 0; }
            return (parseInt(m[1] || 0, 10) * 3600) +
                (parseInt(m[2] || 0, 10) * 60) +
                (parseInt(m[3] || 0, 10));
        } catch (e) {
            return 0;
        }
    }

    function wantsAutoplay() {
        try {
            var params = new URLSearchParams(location.search);
            var auto = params.get('autoplay');
            if (auto !== null) { return auto !== '0'; }
            // Embeds default to autoplay when requested by the embedder.
            return isEmbedPage();
        } catch (e) {
            return false;
        }
    }

    // ------------------------------------------------------------------
    // Player response acquisition
    // ------------------------------------------------------------------

    function extractBalancedJson(text, start) {
        var depth = 0;
        var inString = false;
        var escaped = false;
        for (var i = start; i < text.length; i++) {
            var ch = text[i];
            if (inString) {
                if (escaped) { escaped = false; }
                else if (ch === '\\') { escaped = true; }
                else if (ch === '"') { inString = false; }
                continue;
            }
            if (ch === '"') { inString = true; }
            else if (ch === '{' || ch === '[') { depth++; }
            else if (ch === '}' || ch === ']') {
                depth--;
                if (depth === 0) { return text.slice(start, i + 1); }
            }
        }
        return null;
    }

    function readInitialPlayerResponse() {
        try {
            if (window.ytInitialPlayerResponse && window.ytInitialPlayerResponse.streamingData) {
                return window.ytInitialPlayerResponse;
            }
        } catch (e) { /* ignore */ }
        try {
            var scripts = document.getElementsByTagName('script');
            for (var i = 0; i < scripts.length; i++) {
                var text = scripts[i].textContent || '';
                var idx = text.indexOf('ytInitialPlayerResponse');
                if (idx === -1) { continue; }
                var eq = text.indexOf('=', idx);
                if (eq === -1) { continue; }
                var start = text.indexOf('{', eq);
                if (start === -1) { continue; }
                var json = extractBalancedJson(text, start);
                if (!json) { continue; }
                try {
                    var parsed = JSON.parse(json);
                    if (parsed && parsed.streamingData) { return parsed; }
                } catch (e) { /* keep scanning */ }
            }
        } catch (e) { /* ignore */ }
        return null;
    }

    function innertubeKey() {
        try {
            if (window.ytcfg && typeof window.ytcfg.get === 'function') {
                var key = window.ytcfg.get('INNERTUBE_API_KEY');
                if (key) { return key; }
            }
        } catch (e) { /* ignore */ }
        try {
            var scripts = document.getElementsByTagName('script');
            for (var i = 0; i < scripts.length; i++) {
                var text = scripts[i].textContent || '';
                var m = text.match(/"INNERTUBE_API_KEY":"([^"]+)"/);
                if (m) { return m[1]; }
            }
        } catch (e) { /* ignore */ }
        return '';
    }

    function innertubeContext() {
        try {
            if (window.ytcfg && typeof window.ytcfg.get === 'function') {
                var ctx = window.ytcfg.get('INNERTUBE_CONTEXT');
                if (ctx && ctx.client) { return ctx; }
            }
        } catch (e) { /* ignore */ }
        return {
            client: {
                clientName: 'WEB',
                clientVersion: '2.20240101.00.00',
                hl: 'en',
                gl: 'US'
            }
        };
    }

    function fetchPlayerResponse(videoId) {
        var key = innertubeKey();
        var url = 'https://' + location.hostname + '/youtubei/v1/player' +
            (key ? '?key=' + encodeURIComponent(key) : '') + '&prettyPrint=false';
        var body = {
            videoId: videoId,
            context: innertubeContext(),
            playbackContext: {
                contentPlaybackContext: { html5Preference: 'HTML5_PREF_WANTS' }
            },
            contentCheckOk: true,
            racyCheckOk: true
        };
        return fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            credentials: 'include',
            body: JSON.stringify(body)
        }).then(function (res) {
            if (!res.ok) { throw new Error('InnerTube HTTP ' + res.status); }
            return res.json();
        });
    }

    function resolvePlayerResponse(videoId) {
        var initial = readInitialPlayerResponse();
        var initialVideoId = initial && initial.videoDetails ? initial.videoDetails.videoId : null;
        if (initial && initialVideoId === videoId && initial.streamingData) {
            return Promise.resolve(initial);
        }
        return fetchPlayerResponse(videoId).catch(function (err) {
            log('InnerTube fetch failed, falling back to initial response', err);
            if (initial) { return initial; }
            throw err;
        });
    }

    // ------------------------------------------------------------------
    // Stream selection
    // ------------------------------------------------------------------
    //
    // We only use formats that carry a direct, playable `url`. Ciphered
    // formats (signatureCipher) require decrypting YouTube's obfuscated
    // player, which changes constantly; rather than break unpredictably we
    // skip them and fall back to HLS or the original player.

    function hasDirectUrl(format) {
        return format && typeof format.url === 'string' && format.url.indexOf('http') === 0;
    }

    function parseHeight(format) {
        if (format.height) { return format.height; }
        var m = (format.qualityLabel || '').match(/(\d+)p/);
        return m ? parseInt(m[1], 10) : 0;
    }

    function collectStreams(playerResponse) {
        var streamingData = playerResponse.streamingData || {};
        var progressive = (streamingData.formats || []).filter(function (f) {
            return hasDirectUrl(f) && f.mimeType && f.mimeType.indexOf('video') === 0;
        });
        var audio = (streamingData.adaptiveFormats || []).filter(function (f) {
            return hasDirectUrl(f) && f.mimeType && f.mimeType.indexOf('audio') === 0;
        });
        progressive.sort(function (a, b) { return parseHeight(b) - parseHeight(a); });
        audio.sort(function (a, b) {
            return (b.audioBitrate || b.bitrate || 0) - (a.audioBitrate || a.bitrate || 0);
        });
        return {
            progressive: progressive,
            audio: audio,
            hls: streamingData.hlsManifestUrl || null,
            isLive: !!(playerResponse.videoDetails && playerResponse.videoDetails.isLiveContent) &&
                !!streamingData.hlsManifestUrl
        };
    }

    function preferredQualityLabel() {
        try { return localStorage.getItem(STORAGE_QUALITY) || ''; } catch (e) { return ''; }
    }

    function isAudioOnly() {
        try { return localStorage.getItem(STORAGE_AUDIO) === '1'; } catch (e) { return false; }
    }

    function setAudioOnly(value) {
        try { localStorage.setItem(STORAGE_AUDIO, value ? '1' : '0'); } catch (e) { /* ignore */ }
    }

    function setPreferredQuality(label) {
        try { localStorage.setItem(STORAGE_QUALITY, label); } catch (e) { /* ignore */ }
    }

    function chooseVideoSource(streams) {
        if (streams.isLive && streams.hls) {
            return { src: streams.hls, kind: 'live', label: 'Live' };
        }
        if (streams.progressive.length === 0) {
            if (streams.hls) { return { src: streams.hls, kind: 'hls', label: 'Auto' }; }
            return null;
        }
        var wanted = preferredQualityLabel();
        if (wanted) {
            for (var i = 0; i < streams.progressive.length; i++) {
                if ((streams.progressive[i].qualityLabel || '') === wanted) {
                    return { src: streams.progressive[i].url, kind: 'progressive', label: wanted };
                }
            }
        }
        var best = streams.progressive[0];
        return { src: best.url, kind: 'progressive', label: best.qualityLabel || 'Auto' };
    }

    function chooseAudioSource(streams) {
        if (streams.audio.length === 0) { return null; }
        return { src: streams.audio[0].url, kind: 'audio', label: 'Audio only' };
    }

    // ------------------------------------------------------------------
    // Player UI
    // ------------------------------------------------------------------

    function findPlayerContainer() {
        return document.getElementById('movie_player') ||
            document.querySelector('#player .html5-video-player') ||
            document.querySelector('.html5-video-player');
    }

    function buildVideoElement(src, isAudio) {
        var video = document.createElement('video');
        video.src = src;
        video.controls = true;
        video.playsInline = true;
        video.setAttribute('playsinline', '');
        video.setAttribute('webkit-playsinline', '');
        video.style.width = '100%';
        video.style.height = '100%';
        video.style.background = '#000';
        video.style.objectFit = isAudio ? 'contain' : 'contain';
        return video;
    }

    function styleHost(container) {
        container.style.background = '#000';
    }

    function buildOverlay(container, video, streams, state) {
        var overlay = document.createElement('div');
        overlay.className = 'wblock-tc-overlay';
        overlay.style.cssText = [
            'position:absolute', 'top:8px', 'right:8px', 'z-index:60',
            'display:flex', 'gap:6px', 'align-items:center',
            'font:12px/1.2 -apple-system,system-ui,sans-serif'
        ].join(';');

        // Quality / audio selector.
        var select = document.createElement('select');
        select.style.cssText = [
            'background:rgba(0,0,0,0.7)', 'color:#fff', 'border:1px solid rgba(255,255,255,0.3)',
            'border-radius:4px', 'padding:3px 6px', 'font-size:12px', 'cursor:pointer'
        ].join(';');

        var audioOpt = document.createElement('option');
        audioOpt.value = '__audio__';
        audioOpt.textContent = 'Audio only';
        if (streams.audio.length === 0) { audioOpt.disabled = true; }
        select.appendChild(audioOpt);

        if (streams.isLive && streams.hls) {
            var liveOpt = document.createElement('option');
            liveOpt.value = '__live__';
            liveOpt.textContent = 'Live';
            select.appendChild(liveOpt);
        }

        streams.progressive.forEach(function (format) {
            var opt = document.createElement('option');
            opt.value = format.qualityLabel || ('h' + parseHeight(format));
            opt.textContent = (format.qualityLabel || (parseHeight(format) + 'p')) +
                (format.mimeType && format.mimeType.indexOf('mp4') !== -1 ? '' : '');
            select.appendChild(opt);
        });

        function reflectCurrent() {
            select.value = isAudioOnly() ? '__audio__' : (state.currentLabel || '');
            if (select.selectedIndex === -1 && select.options.length > 0) {
                select.selectedIndex = 0;
            }
        }
        reflectCurrent();

        select.addEventListener('change', function () {
            var value = select.value;
            if (value === '__audio__') {
                setAudioOnly(true);
                state.swapTo(chooseAudioSource(streams), true);
            } else if (value === '__live__') {
                setAudioOnly(false);
                state.swapTo({ src: streams.hls, kind: 'live', label: 'Live' }, false);
            } else {
                setAudioOnly(false);
                setPreferredQuality(value);
                var format = null;
                for (var i = 0; i < streams.progressive.length; i++) {
                    if ((streams.progressive[i].qualityLabel || ('h' + parseHeight(streams.progressive[i]))) === value) {
                        format = streams.progressive[i];
                        break;
                    }
                }
                if (format) {
                    state.swapTo({ src: format.url, kind: 'progressive', label: value }, false);
                }
            }
            reflectCurrent();
        });

        overlay.appendChild(select);

        // Picture-in-Picture button (Safari exposes the native one too, but
        // this guarantees it everywhere).
        if (document.pictureInPictureEnabled !== false && typeof video.requestPictureInPicture === 'function') {
            var pip = document.createElement('button');
            pip.type = 'button';
            pip.textContent = 'PiP';
            pip.title = 'Picture in Picture';
            pip.style.cssText = [
                'background:rgba(0,0,0,0.7)', 'color:#fff', 'border:1px solid rgba(255,255,255,0.3)',
                'border-radius:4px', 'padding:3px 8px', 'font-size:12px', 'cursor:pointer'
            ].join(';');
            pip.addEventListener('click', function () {
                try {
                    if (document.pictureInPictureElement) {
                        document.exitPictureInPicture();
                    } else {
                        video.requestPictureInPicture();
                    }
                } catch (e) { log('PiP failed', e); }
            });
            overlay.appendChild(pip);
        }

        // Restore the original YouTube player.
        var restore = document.createElement('button');
        restore.type = 'button';
        restore.textContent = 'Restore';
        restore.title = 'Restore the original YouTube player';
        restore.style.cssText = [
            'background:rgba(0,0,0,0.7)', 'color:#fff', 'border:1px solid rgba(255,255,255,0.3)',
            'border-radius:4px', 'padding:3px 8px', 'font-size:12px', 'cursor:pointer'
        ].join(';');
        restore.addEventListener('click', function () {
            state.restoreOriginal();
        });
        overlay.appendChild(restore);

        container.appendChild(overlay);
        return overlay;
    }

    function showFallback(container, message) {
        var box = document.createElement('div');
        box.className = 'wblock-tc-fallback';
        box.style.cssText = [
            'position:absolute', 'inset:0', 'z-index:70',
            'display:flex', 'flex-direction:column', 'gap:10px',
            'align-items:center', 'justify-content:center',
            'background:rgba(0,0,0,0.85)', 'color:#fff', 'text-align:center',
            'font:14px/1.4 -apple-system,system-ui,sans-serif', 'padding:20px',
            'box-sizing:border-box'
        ].join(';');
        var text = document.createElement('div');
        text.textContent = message;
        box.appendChild(text);
        var btn = document.createElement('button');
        btn.type = 'button';
        btn.textContent = 'Use the original YouTube player';
        btn.style.cssText = [
            'background:#3ea6ff', 'color:#000', 'border:none', 'border-radius:4px',
            'padding:8px 14px', 'font-size:14px', 'cursor:pointer'
        ].join(';');
        box.appendChild(btn);
        container.appendChild(box);
        return btn;
    }

    // ------------------------------------------------------------------
    // Installation
    // ------------------------------------------------------------------

    var activeSession = null;

    function teardownActive() {
        if (activeSession && typeof activeSession.teardown === 'function') {
            try { activeSession.teardown(); } catch (e) { /* ignore */ }
        }
        activeSession = null;
    }

    function installPlayer(container, playerResponse) {
        var videoId = playerResponse.videoDetails ? playerResponse.videoDetails.videoId : currentVideoId();
        var streams = collectStreams(playerResponse);
        log('streams', {
            progressive: streams.progressive.length,
            audio: streams.audio.length,
            hls: !!streams.hls,
            live: streams.isLive
        });

        // Preserve the original player so we can restore it.
        var originalChildren = [];
        while (container.firstChild) {
            originalChildren.push(container.firstChild);
            container.removeChild(container.firstChild);
        }
        container.setAttribute(ATTR_MANAGED, videoId || '1');
        styleHost(container);
        container.style.position = container.style.position || 'relative';

        var state = { currentLabel: '', video: null };

        function restoreOriginal() {
            try {
                if (state.video) {
                    state.video.pause();
                }
            } catch (e) { /* ignore */ }
            while (container.firstChild) {
                container.removeChild(container.firstChild);
            }
            originalChildren.forEach(function (child) {
                container.appendChild(child);
            });
            container.removeAttribute(ATTR_MANAGED);
            teardownActive();
            // Let YouTube re-mount its player controls over the restored nodes.
            try {
                if (window.location) {
                    window.dispatchEvent(new Event('resize'));
                }
            } catch (e) { /* ignore */ }
        }

        function mount(source, isAudio) {
            if (!source) { return false; }
            if (state.video) {
                try { state.video.pause(); } catch (e) { /* ignore */ }
                if (state.video.parentNode) { state.video.parentNode.removeChild(state.video); }
            }
            var video = buildVideoElement(source.src, isAudio);
            state.video = video;
            state.currentLabel = source.label;
            container.insertBefore(video, container.firstChild);

            var startAt = requestedStartTime();
            if (startAt > 0 && source.kind !== 'live') {
                video.addEventListener('loadedmetadata', function once() {
                    video.removeEventListener('loadedmetadata', once);
                    try {
                        if (isFinite(video.duration) && startAt < video.duration) {
                            video.currentTime = startAt;
                        }
                    } catch (e) { /* ignore */ }
                });
            }
            if (wantsAutoplay()) {
                var playPromise = video.play();
                if (playPromise && typeof playPromise.catch === 'function') {
                    playPromise.catch(function () {
                        // Autoplay with sound may be blocked; retry muted so the
                        // user still gets a playing video they can unmute.
                        video.muted = true;
                        var retry = video.play();
                        if (retry && typeof retry.catch === 'function') { retry.catch(function () {}); }
                    });
                }
            }
            return true;
        }

        state.swapTo = function (source, isAudio) {
            var preserveTime = state.video ? state.video.currentTime : 0;
            var wasPlaying = state.video ? !state.video.paused : false;
            if (!mount(source, isAudio)) { return; }
            if (preserveTime > 0 && source.kind !== 'live') {
                state.video.addEventListener('loadedmetadata', function once() {
                    state.video.removeEventListener('loadedmetadata', once);
                    try { state.video.currentTime = preserveTime; } catch (e) { /* ignore */ }
                    if (wasPlaying) {
                        var p = state.video.play();
                        if (p && typeof p.catch === 'function') { p.catch(function () {}); }
                    }
                });
            }
        };

        state.restoreOriginal = restoreOriginal;

        var initialSource = isAudioOnly() ? chooseAudioSource(streams) : chooseVideoSource(streams);
        if (!initialSource) {
            // No directly-playable stream. Restore and let YouTube handle it.
            restoreOriginal();
            return false;
        }

        if (!mount(initialSource, isAudioOnly())) {
            restoreOriginal();
            return false;
        }

        buildOverlay(container, state.video, streams, state);

        activeSession = {
            videoId: videoId,
            teardown: function () {
                try {
                    if (state.video) { state.video.pause(); }
                } catch (e) { /* ignore */ }
            }
        };

        return true;
    }

    function tryInstall() {
        var videoId = currentVideoId();
        if (!videoId) {
            teardownActive();
            return;
        }

        var container = findPlayerContainer();
        if (!container) { return; }

        // Already installed for this video.
        if (container.getAttribute(ATTR_MANAGED) === videoId) { return; }

        // A previous session for a different video: tear it down first.
        if (activeSession && activeSession.videoId !== videoId) {
            teardownActive();
        }

        resolvePlayerResponse(videoId).then(function (playerResponse) {
            // Re-check: navigation may have happened during the async fetch.
            if (currentVideoId() !== videoId) { return; }
            var target = findPlayerContainer();
            if (!target) { return; }
            if (target.getAttribute(ATTR_MANAGED) === videoId) { return; }

            var playability = playerResponse.playabilityStatus || {};
            if (playability.status && playability.status !== 'OK' && playability.status !== 'LIVE_STREAM') {
                log('not playable', playability.status);
                return; // leave the original player for login/age-gate/etc.
            }

            var ok = installPlayer(target, playerResponse);
            if (!ok) {
                log('could not install; leaving original player');
            }
        }).catch(function (err) {
            log('failed to resolve player response', err);
        });
    }

    // ------------------------------------------------------------------
    // Navigation handling (YouTube is a single-page app)
    // ------------------------------------------------------------------

    var lastHandledUrl = '';

    function onNavigate() {
        if (location.href === lastHandledUrl) { return; }
        lastHandledUrl = location.href;
        teardownActive();
        // The player container is rebuilt on SPA navigation; give it a moment.
        setTimeout(tryInstall, 0);
        setTimeout(tryInstall, 600);
        setTimeout(tryInstall, 1500);
    }

    function watchNavigation() {
        // YouTube fires these custom events on SPA navigations.
        document.addEventListener('yt-navigate-finish', onNavigate, true);
        document.addEventListener('yt-page-data-updated', onNavigate, true);
        window.addEventListener('popstate', onNavigate, true);

        // Poll as a backstop for navigation paths that do not fire events.
        setInterval(function () {
            if (location.href !== lastHandledUrl) { onNavigate(); }
        }, 1000);
    }

    function waitForPlayerThenInstall(timeoutMs) {
        var started = Date.now();
        var timer = setInterval(function () {
            var videoId = currentVideoId();
            var container = findPlayerContainer();
            if (videoId && container) {
                clearInterval(timer);
                tryInstall();
            } else if (Date.now() - started > timeoutMs) {
                clearInterval(timer);
            }
        }, 250);
    }

    function boot() {
        if (!currentVideoId()) {
            // Not a video page yet; navigation watcher will pick it up.
            watchNavigation();
            return;
        }
        lastHandledUrl = location.href;
        watchNavigation();
        waitForPlayerThenInstall(15000);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', boot, { once: true });
    } else {
        boot();
    }
})();
