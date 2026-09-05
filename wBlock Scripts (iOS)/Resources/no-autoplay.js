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
// - Transition cache: until NATIVE_MIGRATED_KEY is true, a leftover enabled
//   (ENABLED_KEY) value overrides native enabled state, while leftover and
//   native per-site allow values both stand the gate down. Thereafter leftover
//   values are only a native-read fallback and for live storage.onChanged
//   reconcile.
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

    // The manifest loads the same bundled gate before this controller.
    var noAutoplayGate = globalThis.__wblockNoAutoplayGate;
    if (typeof noAutoplayGate !== 'function') return;

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

    function requestPageWorldGate(gateToken) {
        try {
            browser.runtime.sendMessage({
                action: 'wblock:noAutoplay:injectGate',
                token: gateToken
            }).then(function () {
                // The native decision may change while page-world injection is pending.
                dispatchControl(desired ? 'enable' : 'disable');
            }).catch(function () { /* background unavailable; isolated gate stays */ });
        } catch (e) { /* ignore */ }
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
            // Sites such as YouTube enforce Trusted Types and drive playback
            // from script, so DOM-level enforcement alone is not enough (#676).
            // Ask the background to run the same gate in the page world via
            // scripting.executeScript, which CSP does not govern. The gate's
            // window guard and shared DOM attributes keep both copies agreeing.
            requestPageWorldGate(token);
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
        var hasLegacyEnabled = !!(stored
            && Object.prototype.hasOwnProperty.call(stored, ENABLED_KEY));
        var legacyAllowed = !!(stored && stored[allowKey] === true);
        var migrated = !!(stored && stored[NATIVE_MIGRATED_KEY] === true);
        var native = await getNativeNoAutoplayState(host);

        if (!migrated && hasLegacyEnabled) {
            // Native protobuf defaults are indistinguishable from a user who
            // turned the feature off. Until popup migration completes, retain
            // a leftover enabled value, but still honor Site Settings writes
            // that have already reached native storage.
            enabled = stored[ENABLED_KEY] === true;
            siteAllowed = legacyAllowed || !!(native && native.siteAllowed === true);
        } else if (native) {
            enabled = native.enabled === true;
            siteAllowed = native.siteAllowed === true;
        } else {
            enabled = !!(stored && stored[ENABLED_KEY] === true);
            siteAllowed = legacyAllowed;
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

    // Native protobuf changes do not emit storage events, so refresh after
    // Safari returns this page to the foreground.
    try {
        document.addEventListener('visibilitychange', function () {
            if (document.visibilityState === 'visible') reconcile();
        });
        window.addEventListener('pageshow', reconcile);
    } catch (e) { /* ignore */ }

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
