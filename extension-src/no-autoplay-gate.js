// Shared by the document-start controller and direct page-world injection.
(function () {
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
            if (disabled || !event.isTrusted) return;
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
    globalThis.__wblockNoAutoplayGate = noAutoplayGate;
})();
