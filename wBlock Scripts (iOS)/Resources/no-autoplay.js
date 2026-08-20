// wBlock No Autoplay (WebExtension content script)
//
// Keeps media paused until the user taps, clicks, or key-activates it, which
// stops muted feed/scroll autoplay. The enforcement gate has to patch
// HTMLMediaElement.prototype.play before page scripts call it, so it is
// injected into the page world via an inline <script> tag; when a strict CSP
// blocks that, the same gate runs in this isolated world, where its DOM-level
// protections (autoplay stripping, pause-on-play, unlock on interaction)
// still apply to the shared document.
//
// State model:
// - Authoritative: native app state (protobuf) via getNoAutoplayState and popup
//   setters; CloudSync keeps devices aligned after legacy state has migrated.
// - Transition cache: until NATIVE_MIGRATED_KEY is true, leftover enabled
//   (ENABLED_KEY) and per-site allow (ALLOW_PREFIX + host) values override
//   native protobuf defaults. Thereafter they are only a native-read fallback
//   and for live storage.onChanged reconcile.
// - Sites where wBlock is disabled ("Enable on this site" off) stand down.
// - Warm hint: page localStorage[HINT_KEY] mirrors the last arming decision so
//   repeat visits arm synchronously at document_start. The hint is page-writable
//   by design (same trust model as the userscript injector warm-start cache):
//   the worst a page can do is toggle its own first-paint arming, and the async
//   authoritative check corrects it. Autoplay blocking is a convenience, not a
//   security boundary.

(function () {
    'use strict';

    var ENABLED_KEY = 'wblock.noAutoplay.enabled.v1';
    var ALLOW_PREFIX = 'wblock.noAutoplayAllow.v1:';
    var NATIVE_MIGRATED_KEY = 'wblock.noAutoplay.nativeMigrated.v1';
    var HINT_KEY = '__wblock_no_autoplay_arm_v1';
    var NATIVE_MESSAGE_TIMEOUT_MS = 3500;

    var hasExtensionContext = typeof browser !== 'undefined'
        && !!browser.runtime
        && typeof browser.runtime.sendNativeMessage === 'function'
        && !!browser.storage
        && !!browser.storage.local;
    if (!hasExtensionContext) return;

    // ------------------------------------------------------------------
    // Gate. Runs in the page world (serialized via Function.prototype
    // .toString into an inline <script>) or, as the CSP fallback, directly
    // in this isolated world. It must stay fully self-contained: no
    // references to the enclosing scope.
    // ------------------------------------------------------------------
    function noAutoplayGate(token) {
        'use strict';

        if (window.__wblockNoAutoplayGateActive) return;
        window.__wblockNoAutoplayGateActive = true;

        var doc = document;
        var disabled = false;
        var unlocked = typeof WeakSet === 'function' ? new WeakSet() : null;

        // Execution marker: the controller checks this attribute to learn
        // whether page-world injection survived the page's CSP.
        try {
            if (doc.documentElement) {
                doc.documentElement.setAttribute('data-wblock-no-autoplay-gate', '1');
            }
        } catch (e) { /* ignore */ }

        function makeNotAllowed() {
            try {
                return new DOMException(
                    'The play() request was interrupted because autoplay is disabled.',
                    'NotAllowedError'
                );
            } catch (e) {
                var err = new Error('The play() request was interrupted because autoplay is disabled.');
                err.name = 'NotAllowedError';
                return err;
            }
        }

        function isMedia(node) {
            return !!(node && (node.localName === 'video' || node.localName === 'audio'));
        }

        // The unlocked state is mirrored into a DOM attribute so that the
        // page-world gate and an isolated-world gate agree on it even though
        // expandos and WeakSets do not cross worlds.
        function isUnlocked(media) {
            if (disabled) return true;
            if (!media) return false;
            try { if (media._wblockNoAutoplayUnlocked) return true; } catch (e) { /* ignore */ }
            try {
                if (media.getAttribute && media.getAttribute('data-wblock-no-autoplay-unlocked') === '1') return true;
            } catch (e) { /* ignore */ }
            return !!(unlocked && unlocked.has(media));
        }

        function unlock(media) {
            if (!isMedia(media)) return;
            try { media._wblockNoAutoplayUnlocked = true; } catch (e) { /* ignore */ }
            try { media.setAttribute('data-wblock-no-autoplay-unlocked', '1'); } catch (e) { /* ignore */ }
            if (unlocked) {
                try { unlocked.add(media); } catch (e) { /* ignore */ }
            }
        }

        function disarm(media) {
            if (disabled || !isMedia(media) || isUnlocked(media)) return;
            try { media.autoplay = false; } catch (e) { /* ignore */ }
            try { media.removeAttribute('autoplay'); } catch (e) { /* ignore */ }
            try { media.setAttribute('data-wblock-no-autoplay', '1'); } catch (e) { /* ignore */ }
        }

        function pauseIfLocked(media) {
            if (disabled || !isMedia(media) || isUnlocked(media)) return;
            disarm(media);
            try {
                if (!media.paused) media.pause();
            } catch (e) { /* ignore */ }
        }

        function watchMedia(media) {
            if (!isMedia(media)) return;
            disarm(media);
            pauseIfLocked(media);
        }

        function scan(root) {
            if (disabled || !root) return;
            if (isMedia(root)) watchMedia(root);
            if (!root.querySelectorAll) return;
            var list = root.querySelectorAll('video, audio');
            for (var i = 0; i < list.length; i++) watchMedia(list[i]);
        }

        function eventPath(event) {
            try {
                if (typeof event.composedPath === 'function') return event.composedPath();
            } catch (e) { /* ignore */ }
            var path = [];
            var node = event.target;
            while (node) {
                path.push(node);
                node = node.parentNode || node.host;
            }
            return path;
        }

        // A gesture on the media itself (or on the single-media player around
        // it, e.g. a custom play button) unlocks that element.
        function unlockFromEvent(event) {
            if (disabled) return;
            var path = eventPath(event);
            var i;
            for (i = 0; i < path.length; i++) {
                if (isMedia(path[i])) {
                    unlock(path[i]);
                    return;
                }
            }
            // Walk up from the target looking for player chrome that wraps
            // exactly one media element. Stop before page-level containers:
            // treating body/html as a "player" would let a gesture anywhere
            // on the page unlock its only video.
            var el = event.target;
            for (i = 0; i < 8 && el; i++) {
                if (el === doc.body || el === doc.documentElement || el === doc) return;
                if (el.querySelectorAll) {
                    var list = el.querySelectorAll('video, audio');
                    if (list.length === 1) {
                        unlock(list[0]);
                        return;
                    }
                    if (list.length > 1) return;
                }
                el = el.parentElement || el.parentNode;
            }
        }

        function onKey(event) {
            var key = event.key;
            if (key !== ' ' && key !== 'k' && key !== 'K' && key !== 'MediaPlayPause') return;
            unlockFromEvent(event);
        }

        function onPlayEvent(event) {
            pauseIfLocked(event.target);
        }

        try {
            var nativePlay = HTMLMediaElement.prototype.play;
            HTMLMediaElement.prototype.play = function () {
                if (isUnlocked(this)) return nativePlay.apply(this, arguments);
                disarm(this);
                try { if (!this.paused) this.pause(); } catch (e) { /* ignore */ }
                return Promise.reject(makeNotAllowed());
            };
        } catch (e) { /* ignore */ }

        try {
            var autoplayDesc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'autoplay');
            if (autoplayDesc && typeof autoplayDesc.set === 'function' && typeof autoplayDesc.get === 'function') {
                Object.defineProperty(HTMLMediaElement.prototype, 'autoplay', {
                    configurable: true,
                    enumerable: autoplayDesc.enumerable,
                    get: function () {
                        return isUnlocked(this) ? autoplayDesc.get.call(this) : false;
                    },
                    set: function (value) {
                        if (!isUnlocked(this) && value) {
                            autoplayDesc.set.call(this, false);
                            try { this.removeAttribute('autoplay'); } catch (e) { /* ignore */ }
                            return;
                        }
                        autoplayDesc.set.call(this, value);
                    }
                });
            }
        } catch (e) { /* ignore */ }

        try {
            var nativeCreateElement = Document.prototype.createElement;
            Document.prototype.createElement = function (name) {
                var el = nativeCreateElement.apply(this, arguments);
                if (typeof name === 'string' && /^(video|audio)$/i.test(name)) watchMedia(el);
                return el;
            };
        } catch (e) { /* ignore */ }

        var observer = new MutationObserver(function (mutations) {
            if (disabled) return;
            for (var i = 0; i < mutations.length; i++) {
                var mutation = mutations[i];
                if (mutation.type === 'attributes') {
                    if (!isUnlocked(mutation.target)) disarm(mutation.target);
                    continue;
                }
                var nodes = mutation.addedNodes;
                for (var j = 0; j < nodes.length; j++) scan(nodes[j]);
            }
        });

        function observeRoot(root) {
            if (!root || root._wblockNoAutoplayObserved) return;
            root._wblockNoAutoplayObserved = true;
            try {
                observer.observe(root, {
                    childList: true,
                    subtree: true,
                    attributes: true,
                    attributeFilter: ['autoplay']
                });
            } catch (e) { /* ignore */ }
            scan(root);
        }

        try {
            var nativeAttachShadow = Element.prototype.attachShadow;
            if (nativeAttachShadow && !nativeAttachShadow._wblockNoAutoplayPatched) {
                var patchedAttachShadow = function () {
                    var root = nativeAttachShadow.apply(this, arguments);
                    observeRoot(root);
                    return root;
                };
                patchedAttachShadow._wblockNoAutoplayPatched = true;
                Element.prototype.attachShadow = patchedAttachShadow;
            }
        } catch (e) { /* ignore */ }

        // Control channel from the extension controller. DOM events cross
        // worlds, so the same channel reaches a page-world or isolated-world
        // gate. The token is random per page load so page scripts cannot
        // guess the event names ahead of time.
        try {
            doc.addEventListener('wblock-no-autoplay-disable-' + token, function () {
                disabled = true;
            }, false);
            doc.addEventListener('wblock-no-autoplay-enable-' + token, function () {
                disabled = false;
                scan(doc.documentElement || doc);
            }, false);
        } catch (e) { /* ignore */ }

        function boot() {
            try {
                doc.addEventListener('pointerdown', unlockFromEvent, true);
                doc.addEventListener('touchstart', unlockFromEvent, true);
                doc.addEventListener('click', unlockFromEvent, true);
                doc.addEventListener('keydown', onKey, true);
                doc.addEventListener('play', onPlayEvent, true);
                doc.addEventListener('playing', onPlayEvent, true);
            } catch (e) { /* ignore */ }
            if (doc.documentElement) observeRoot(doc.documentElement);
            else doc.addEventListener('DOMContentLoaded', function () {
                if (doc.documentElement) observeRoot(doc.documentElement);
            });
        }

        boot();
    }

    // ------------------------------------------------------------------
    // Controller (isolated world): decides whether the gate is armed.
    // ------------------------------------------------------------------

    var armed = false;
    var desired = false;
    var waitingForRoot = false;
    var token = null;
    var reconcileSeq = 0;

    function readHint() {
        try { return localStorage.getItem(HINT_KEY) === '1'; } catch (e) { return false; }
    }

    function writeHint(shouldArm) {
        try {
            if (shouldArm) localStorage.setItem(HINT_KEY, '1');
            else localStorage.removeItem(HINT_KEY);
        } catch (e) { /* ignore */ }
    }

    function makeToken() {
        try {
            var bytes = new Uint8Array(16);
            crypto.getRandomValues(bytes);
            var out = '';
            for (var i = 0; i < bytes.length; i++) out += (bytes[i] + 256).toString(16).slice(1);
            return out;
        } catch (e) {
            return String(Date.now()) + '-' + String(Math.random()).slice(2);
        }
    }

    function dispatchControl(action) {
        if (!token) return;
        try {
            document.dispatchEvent(new Event('wblock-no-autoplay-' + action + '-' + token));
        } catch (e) { /* ignore */ }
    }

    // Best-effort CSP nonce detection, same approach as the userscript injector.
    function getCspNonce() {
        try {
            var el = document.querySelector('script[nonce]');
            var nonce = el ? (el.nonce || el.getAttribute('nonce') || '') : '';
            return nonce || '';
        } catch (e) {
            return '';
        }
    }

    function injectPageGate(gateToken) {
        try {
            var parent = document.head || document.documentElement;
            if (!parent) return false;
            var el = document.createElement('script');
            el.textContent = '(' + noAutoplayGate.toString() + ')(' + JSON.stringify(gateToken) + ');';
            el.setAttribute('type', 'text/javascript');
            var nonce = getCspNonce();
            if (nonce) el.nonce = nonce;
            parent.appendChild(el);
            el.remove();
            // Inline scripts execute synchronously on append; the gate marks
            // the document element, so a missing marker means the page's CSP
            // blocked execution.
            return !!(document.documentElement
                && document.documentElement.getAttribute('data-wblock-no-autoplay-gate') === '1');
        } catch (e) {
            return false;
        }
    }

    function armNow() {
        if (armed) {
            dispatchControl('enable');
            return;
        }
        token = makeToken();
        if (!injectPageGate(token)) {
            // Strict CSP: run the gate in this world instead. The play() and
            // autoplay patches then only cover this world, but attribute
            // stripping, pause-on-play, and unlock tracking act on the shared
            // DOM, so autoplay is still suppressed.
            noAutoplayGate(token);
        }
        armed = true;
    }

    function ensureArmed() {
        if (armed) {
            dispatchControl('enable');
            return;
        }
        if (document.head || document.documentElement) {
            armNow();
            return;
        }
        // document_start can run before the document element exists. Nothing
        // page-visible has executed yet at that point, so arming at the
        // earliest childList mutation still lands the gate before any page
        // script runs (the parser reaches a microtask checkpoint before it
        // executes a script).
        if (waitingForRoot) return;
        waitingForRoot = true;
        try {
            var rootObserver = new MutationObserver(function () {
                if (!document.documentElement) return;
                rootObserver.disconnect();
                waitingForRoot = false;
                if (desired && !armed) armNow();
            });
            rootObserver.observe(document, { childList: true });
        } catch (e) {
            waitingForRoot = false;
            armNow();
        }
    }

    function standDown() {
        if (armed) dispatchControl('disable');
    }

    function withTimeout(promise, ms) {
        return new Promise(function (resolve, reject) {
            var timer = setTimeout(function () { reject(new Error('timeout')); }, ms);
            Promise.resolve(promise).then(
                function (value) { clearTimeout(timer); resolve(value); },
                function (error) { clearTimeout(timer); reject(error); }
            );
        });
    }

    function getSiteDisabled(host) {
        return withTimeout(
            browser.runtime.sendNativeMessage('application.id', { action: 'getSiteDisabledState', host: host }),
            NATIVE_MESSAGE_TIMEOUT_MS
        ).then(function (response) {
            if (!response || typeof response.disabled !== 'boolean') {
                return null;
            }
            return response.disabled;
        }).catch(function () {
            return null;
        });
    }

    function getNativeNoAutoplayState(host) {
        return withTimeout(
            browser.runtime.sendNativeMessage('application.id', {
                action: 'getNoAutoplayState',
                host: host,
            }),
            NATIVE_MESSAGE_TIMEOUT_MS
        ).then(function (response) {
            if (!response
                || typeof response.enabled !== 'boolean'
                || typeof response.siteAllowed !== 'boolean') {
                return null;
            }
            return {
                enabled: response.enabled,
                siteAllowed: response.siteAllowed,
            };
        }).catch(function () {
            return null;
        });
    }

    async function computeShouldArm() {
        var host = location.hostname;
        if (!host) return false;
        var enabled = false;
        var siteAllowed = false;
        var allowKey = ALLOW_PREFIX + host;
        var stored = await browser.storage.local.get([
            NATIVE_MIGRATED_KEY,
            ENABLED_KEY,
            allowKey,
        ]);
        var hasLegacyState = !!(stored && (
            Object.prototype.hasOwnProperty.call(stored, ENABLED_KEY)
            || Object.prototype.hasOwnProperty.call(stored, allowKey)
        ));
        if (stored && stored[NATIVE_MIGRATED_KEY] !== true && hasLegacyState) {
            // Native protobuf defaults are indistinguishable from a user who
            // turned the feature off. Until popup migration completes, retain
            // the Safari values rather than losing a leftover enabled setting.
            enabled = stored[ENABLED_KEY] === true;
            siteAllowed = stored[allowKey] === true;
        } else {
            var native = await getNativeNoAutoplayState(host);
            if (native) {
                enabled = native.enabled === true;
                siteAllowed = native.siteAllowed === true;
            } else {
                enabled = !!(stored && stored[ENABLED_KEY] === true);
                siteAllowed = !!(stored && stored[allowKey] === true);
            }
        }
        if (!enabled) return false;
        if (siteAllowed) return false;
        var siteDisabled = await getSiteDisabled(host);
        if (siteDisabled !== false) return false;
        return true;
    }

    async function reconcile() {
        var seq = ++reconcileSeq;
        var shouldArm = false;
        try {
            shouldArm = await computeShouldArm();
        } catch (e) {
            shouldArm = false;
        }
        if (seq !== reconcileSeq) return; // superseded by a newer reconcile
        writeHint(shouldArm);
        desired = shouldArm;
        if (shouldArm) ensureArmed();
        else standDown();
    }

    // Synchronous path: arm before page scripts run when the last
    // authoritative decision for this origin was "armed".
    if (readHint()) {
        desired = true;
        ensureArmed();
    }

    // Authoritative path: native no-autoplay state (storage cache fallback) plus
    // native disabled-sites state. Corrects the hint in both directions.
    reconcile();

    // Live updates when the popup changes the global or per-site setting.
    try {
        browser.storage.onChanged.addListener(function (changes, area) {
            if (area !== 'local') return;
            if ((NATIVE_MIGRATED_KEY in changes)
                || (ENABLED_KEY in changes)
                || ((ALLOW_PREFIX + location.hostname) in changes)) {
                reconcile();
            }
        });
    } catch (e) { /* ignore */ }
})();
