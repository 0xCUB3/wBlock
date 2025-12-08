function _defineProperty2(e, r, t) {
    return (
        (r = _toPropertyKey(r)) in e
            ? Object.defineProperty(e, r, {
                  value: t,
                  enumerable: !0,
                  configurable: !0,
                  writable: !0,
              })
            : (e[r] = t),
        e
    );
}
function _toPropertyKey(t) {
    var i = _toPrimitive(t, "string");
    return "symbol" == typeof i ? i : i + "";
}
function _toPrimitive(t, r) {
    if ("object" != typeof t || !t) return t;
    var e = t[Symbol.toPrimitive];
    if (void 0 !== e) {
        var i = e.call(t, r || "default");
        if ("object" != typeof i) return i;
        throw new TypeError("@@toPrimitive must return a primitive value.");
    }
    return ("string" === r ? String : Number)(t);
}
/*
 * WebExtension v1.0.4 (build date: Fri, 15 Aug 2025 06:15:41 GMT)
 * (c) 2025 ameshkov
 * Released under the ISC license
 * https://github.com/ameshkov/safari-blocker
 */
(function (browser) {
    "use strict";

    /**
     * @adguard/extended-css - v2.1.1 - Thu Dec 19 2024
     * https://github.com/AdguardTeam/ExtendedCss#homepage
     * Copyright (c) 2024 AdGuard. Licensed GPL-3.0
     */
    function _defineProperty(obj, key, value) {
        if (key in obj) {
            Object.defineProperty(obj, key, {
                value: value,
                enumerable: true,
                configurable: true,
                writable: true,
            });
        } else {
            obj[key] = value;
        }
        return obj;
    }
    ({
        /**
         * Safe console.error version.
         */
        error:
            typeof console !== "undefined" &&
            console.error &&
            console.error.bind
                ? console.error.bind(window.console)
                : console.error,
        /**
         * Safe console.info version.
         */
        info:
            typeof console !== "undefined" && console.info && console.info.bind
                ? console.info.bind(window.console)
                : console.info,
    });

    /**
     * Checks whether passed `arg` is number type.
     *
     * @param arg Value to check.
     *
     * @returns True if `arg` is number and not NaN.
     */
    const isNumber = (arg) => {
        return typeof arg === "number" && !Number.isNaN(arg);
    };

    /**
     * The purpose of ThrottleWrapper is to throttle calls of the function
     * that applies ExtendedCss rules. The reasoning here is that the function calls
     * are triggered by MutationObserver and there may be many mutations in a short period of time.
     * We do not want to apply rules on every mutation so we use this helper to make sure
     * that there is only one call in the given amount of time.
     */

    class ThrottleWrapper {
        /**
         * Creates new ThrottleWrapper.
         * The {@link callback} should be executed not more often than {@link ThrottleWrapper.THROTTLE_DELAY_MS}.
         *
         * @param callback The callback.
         */
        constructor(callback) {
            this.callback = callback;
            this.executeCallback = this.executeCallback.bind(this);
        }
        /**
         * Calls the {@link callback} function and update bounded throttle wrapper properties.
         */

        executeCallback() {
            this.lastRunTime = performance.now();
            if (isNumber(this.timerId)) {
                clearTimeout(this.timerId);
                delete this.timerId;
            }
            this.callback();
        }
        /**
         * Schedules the {@link executeCallback} function execution via setTimeout.
         * It may triggered by MutationObserver job which may occur too ofter, so we limit the function execution:
         *
         * 1. If {@link timerId} is set, ignore the call, because the function is already scheduled to be executed;
         *
         * 2. If {@link lastRunTime} is set, we need to check the time elapsed time since the last call. If it is
         * less than {@link ThrottleWrapper.THROTTLE_DELAY_MS}, we schedule the function execution after the remaining time.
         *
         * Otherwise, we execute the function asynchronously to ensure that it is executed
         * in the correct order with respect to DOM events, by deferring its execution until after
         * those tasks have completed.
         */

        run() {
            if (isNumber(this.timerId)) {
                // there is a pending execution scheduled
                return;
            }
            if (isNumber(this.lastRunTime)) {
                const elapsedTime = performance.now() - this.lastRunTime;
                if (elapsedTime < ThrottleWrapper.THROTTLE_DELAY_MS) {
                    this.timerId = window.setTimeout(
                        this.executeCallback,
                        ThrottleWrapper.THROTTLE_DELAY_MS - elapsedTime,
                    );
                    return;
                }
            }
            /**
             * We use `setTimeout` instead `requestAnimationFrame`
             * here because requestAnimationFrame can be delayed for a long time
             * when the browser saves battery or the engine is heavily loaded.
             */

            this.timerId = window.setTimeout(this.executeCallback);
        }
    }
    _defineProperty(ThrottleWrapper, "THROTTLE_DELAY_MS", 150);
    function AmazonApstag(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function AmazonApstag(source) {
            var apstagWrapper = {
                fetchBids(a, b) {
                    if (typeof b === "function") {
                        b([]);
                    }
                },
                init: noopFunc,
                setDisplayBids: noopFunc,
                targetingKeys: noopFunc,
            };
            window.apstag = apstagWrapper;
            hit(source);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function noopFunc() {}
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            AmazonApstag.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function DidomiLoader(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function DidomiLoader(source) {
            function UserConsentStatusForVendorSubscribe() {}
            UserConsentStatusForVendorSubscribe.prototype.filter = function () {
                return new UserConsentStatusForVendorSubscribe();
            };
            UserConsentStatusForVendorSubscribe.prototype.subscribe = noopFunc;
            function UserConsentStatusForVendor() {}
            UserConsentStatusForVendor.prototype.first = function () {
                return new UserConsentStatusForVendorSubscribe();
            };
            UserConsentStatusForVendor.prototype.filter = function () {
                return new UserConsentStatusForVendorSubscribe();
            };
            UserConsentStatusForVendor.prototype.subscribe = noopFunc;
            var DidomiWrapper = {
                isConsentRequired: falseFunc,
                getUserConsentStatusForPurpose: trueFunc,
                getUserConsentStatus: trueFunc,
                getUserStatus: noopFunc,
                getRequiredPurposes: noopArray,
                getUserConsentStatusForVendor: trueFunc,
                Purposes: {
                    Cookies: "cookies",
                },
                notice: {
                    configure: noopFunc,
                    hide: noopFunc,
                    isVisible: falseFunc,
                    show: noopFunc,
                    showDataProcessing: trueFunc,
                },
                isUserConsentStatusPartial: falseFunc,
                on() {
                    return {
                        actions: {},
                        emitter: {},
                        services: {},
                        store: {},
                    };
                },
                shouldConsentBeCollected: falseFunc,
                getUserConsentStatusForAll: noopFunc,
                getObservableOnUserConsentStatusForVendor() {
                    return new UserConsentStatusForVendor();
                },
            };
            window.Didomi = DidomiWrapper;
            var didomiStateWrapper = {
                didomiExperimentId: "",
                didomiExperimentUserGroup: "",
                didomiGDPRApplies: 1,
                didomiIABConsent: "",
                didomiPurposesConsent: "",
                didomiPurposesConsentDenied: "",
                didomiPurposesConsentUnknown: "",
                didomiVendorsConsent: "",
                didomiVendorsConsentDenied: "",
                didomiVendorsConsentUnknown: "",
                didomiVendorsRawConsent: "",
                didomiVendorsRawConsentDenied: "",
                didomiVendorsRawConsentUnknown: "",
            };
            window.didomiState = didomiStateWrapper;
            var tcData = {
                eventStatus: "tcloaded",
                gdprApplies: false,
                listenerId: noopFunc,
                vendor: {
                    consents: [],
                },
                purpose: {
                    consents: [],
                },
            };
            var __tcfapiWrapper = function __tcfapiWrapper(
                command,
                version,
                callback,
            ) {
                if (
                    typeof callback !== "function" ||
                    command === "removeEventListener"
                ) {
                    return;
                }
                callback(tcData, true);
            };
            window.__tcfapi = __tcfapiWrapper;
            var didomiEventListenersWrapper = {
                stub: true,
                push: noopFunc,
            };
            window.didomiEventListeners = didomiEventListenersWrapper;
            var didomiOnReadyWrapper = {
                stub: true,
                push(arg) {
                    if (typeof arg !== "function") {
                        return;
                    }
                    if (document.readyState !== "complete") {
                        window.addEventListener("load", function () {
                            setTimeout(arg(window.Didomi));
                        });
                    } else {
                        setTimeout(arg(window.Didomi));
                    }
                },
            };
            window.didomiOnReady = window.didomiOnReady || didomiOnReadyWrapper;
            if (Array.isArray(window.didomiOnReady)) {
                window.didomiOnReady.forEach(function (arg) {
                    if (typeof arg === "function") {
                        try {
                            setTimeout(arg(window.Didomi));
                        } catch (e) {}
                    }
                });
            }
            hit(source);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function noopFunc() {}
        function noopArray() {
            return [];
        }
        function trueFunc() {
            return true;
        }
        function falseFunc() {
            return false;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            DidomiLoader.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function Fingerprintjs2(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function Fingerprintjs2(source) {
            var browserId = "";
            for (var i = 0; i < 8; i += 1) {
                browserId += (Math.random() * 65536 + 4096)
                    .toString(16)
                    .slice(-4);
            }
            var Fingerprint2 = function Fingerprint2() {};
            Fingerprint2.get = function (options, callback) {
                if (!callback) {
                    callback = options;
                }
                setTimeout(function () {
                    if (callback) {
                        callback(browserId, []);
                    }
                }, 1);
            };
            Fingerprint2.prototype = {
                get: Fingerprint2.get,
            };
            window.Fingerprint2 = Fingerprint2;
            hit(source);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            Fingerprintjs2.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function Fingerprintjs3(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function Fingerprintjs3(source) {
            var visitorId = (function () {
                var id = "";
                for (var i = 0; i < 8; i += 1) {
                    id += (Math.random() * 65536 + 4096).toString(16).slice(-4);
                }
                return id;
            })();
            var FingerprintJS = function FingerprintJS() {};
            FingerprintJS.prototype = {
                load() {
                    return Promise.resolve(new FingerprintJS());
                },
                get() {
                    return Promise.resolve({
                        visitorId: visitorId,
                    });
                },
                hashComponents: noopStr,
            };
            window.FingerprintJS = new FingerprintJS();
            hit(source);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function noopStr() {
            return "";
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            Fingerprintjs3.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function Gemius(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function Gemius(source) {
            var GemiusPlayer = function GemiusPlayer() {};
            GemiusPlayer.prototype = {
                setVideoObject: noopFunc,
                newProgram: noopFunc,
                programEvent: noopFunc,
                newAd: noopFunc,
                adEvent: noopFunc,
            };
            window.GemiusPlayer = GemiusPlayer;
            hit(source);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function noopFunc() {}
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            Gemius.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function GoogleAnalytics(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function GoogleAnalytics(source) {
            var _window$googleAnalyti;
            var Tracker = function Tracker() {};
            var proto = Tracker.prototype;
            proto.get = noopFunc;
            proto.set = noopFunc;
            proto.send = noopFunc;
            var googleAnalyticsName = window.GoogleAnalyticsObject || "ga";
            var queue =
                (_window$googleAnalyti = window[googleAnalyticsName]) ===
                    null || _window$googleAnalyti === void 0
                    ? void 0
                    : _window$googleAnalyti.q;
            function ga(a) {
                var len = arguments.length;
                if (len === 0) {
                    return;
                }
                var lastArg = arguments[len - 1];
                var replacer;
                if (
                    lastArg instanceof Object &&
                    lastArg !== null &&
                    typeof lastArg.hitCallback === "function"
                ) {
                    replacer = lastArg.hitCallback;
                } else if (typeof lastArg === "function") {
                    replacer = function replacer() {
                        lastArg(ga.create());
                    };
                }
                try {
                    setTimeout(replacer, 1);
                } catch (ex) {}
            }
            ga.create = function () {
                return new Tracker();
            };
            ga.getByName = function () {
                return new Tracker();
            };
            ga.getAll = function () {
                return [new Tracker()];
            };
            ga.remove = noopFunc;
            ga.loaded = true;
            window[googleAnalyticsName] = ga;
            if (Array.isArray(queue)) {
                var push = function push(arg) {
                    ga(...arg);
                };
                queue.push = push;
                queue.forEach(push);
            }
            var { dataLayer: dataLayer, google_optimize: google_optimize } =
                window;
            if (dataLayer instanceof Object === false) {
                return;
            }
            if (
                dataLayer.hide instanceof Object &&
                typeof dataLayer.hide.end === "function"
            ) {
                dataLayer.hide.end();
            }
            var handleCallback = function handleCallback(dataObj, funcName) {
                if (dataObj && typeof dataObj[funcName] === "function") {
                    setTimeout(dataObj[funcName]);
                }
            };
            if (typeof dataLayer.push === "function") {
                dataLayer.push = function (data) {
                    if (data instanceof Object) {
                        handleCallback(data, "eventCallback");
                        for (var key in data) {
                            handleCallback(data[key], "event_callback");
                        }
                        if (
                            !data.hasOwnProperty("eventCallback") &&
                            !data.hasOwnProperty("eventCallback")
                        ) {
                            [].push.call(window.dataLayer, data);
                        }
                    }
                    if (Array.isArray(data)) {
                        data.forEach(function (arg) {
                            handleCallback(arg, "callback");
                        });
                    }
                    return noopFunc;
                };
            }
            if (
                google_optimize instanceof Object &&
                typeof google_optimize.get === "function"
            ) {
                var googleOptimizeWrapper = {
                    get: noopFunc,
                };
                window.google_optimize = googleOptimizeWrapper;
            }
            hit(source);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function noopFunc() {}
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            GoogleAnalytics.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function GoogleAnalyticsGa(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function GoogleAnalyticsGa(source) {
            function Gaq() {}
            Gaq.prototype.Na = noopFunc;
            Gaq.prototype.O = noopFunc;
            Gaq.prototype.Sa = noopFunc;
            Gaq.prototype.Ta = noopFunc;
            Gaq.prototype.Va = noopFunc;
            Gaq.prototype._createAsyncTracker = noopFunc;
            Gaq.prototype._getAsyncTracker = noopFunc;
            Gaq.prototype._getPlugin = noopFunc;
            Gaq.prototype.push = function (data) {
                if (typeof data === "function") {
                    data();
                    return;
                }
                if (Array.isArray(data) === false) {
                    return;
                }
                if (
                    typeof data[0] === "string" &&
                    /(^|\.)_link$/.test(data[0]) &&
                    typeof data[1] === "string"
                ) {
                    window.location.assign(data[1]);
                }
                if (
                    data[0] === "_set" &&
                    data[1] === "hitCallback" &&
                    typeof data[2] === "function"
                ) {
                    data[2]();
                }
            };
            var gaq = new Gaq();
            var asyncTrackers = window._gaq || [];
            if (Array.isArray(asyncTrackers)) {
                while (asyncTrackers[0]) {
                    gaq.push(asyncTrackers.shift());
                }
            }
            window._gaq = gaq.qf = gaq;
            function Gat() {}
            var api = [
                "_addIgnoredOrganic",
                "_addIgnoredRef",
                "_addItem",
                "_addOrganic",
                "_addTrans",
                "_clearIgnoredOrganic",
                "_clearIgnoredRef",
                "_clearOrganic",
                "_cookiePathCopy",
                "_deleteCustomVar",
                "_getName",
                "_setAccount",
                "_getAccount",
                "_getClientInfo",
                "_getDetectFlash",
                "_getDetectTitle",
                "_getLinkerUrl",
                "_getLocalGifPath",
                "_getServiceMode",
                "_getVersion",
                "_getVisitorCustomVar",
                "_initData",
                "_link",
                "_linkByPost",
                "_setAllowAnchor",
                "_setAllowHash",
                "_setAllowLinker",
                "_setCampContentKey",
                "_setCampMediumKey",
                "_setCampNameKey",
                "_setCampNOKey",
                "_setCampSourceKey",
                "_setCampTermKey",
                "_setCampaignCookieTimeout",
                "_setCampaignTrack",
                "_setClientInfo",
                "_setCookiePath",
                "_setCookiePersistence",
                "_setCookieTimeout",
                "_setCustomVar",
                "_setDetectFlash",
                "_setDetectTitle",
                "_setDomainName",
                "_setLocalGifPath",
                "_setLocalRemoteServerMode",
                "_setLocalServerMode",
                "_setReferrerOverride",
                "_setRemoteServerMode",
                "_setSampleRate",
                "_setSessionTimeout",
                "_setSiteSpeedSampleRate",
                "_setSessionCookieTimeout",
                "_setVar",
                "_setVisitorCookieTimeout",
                "_trackEvent",
                "_trackPageLoadTime",
                "_trackPageview",
                "_trackSocial",
                "_trackTiming",
                "_trackTrans",
                "_visitCode",
            ];
            var tracker = api.reduce(function (res, funcName) {
                res[funcName] = noopFunc;
                return res;
            }, {});
            tracker._getLinkerUrl = function (a) {
                return a;
            };
            tracker._link = function (url) {
                if (typeof url !== "string") {
                    return;
                }
                try {
                    window.location.assign(url);
                } catch (e) {
                    logMessage(source, e);
                }
            };
            Gat.prototype._anonymizeIP = noopFunc;
            Gat.prototype._createTracker = noopFunc;
            Gat.prototype._forceSSL = noopFunc;
            Gat.prototype._getPlugin = noopFunc;
            Gat.prototype._getTracker = function () {
                return tracker;
            };
            Gat.prototype._getTrackerByName = function () {
                return tracker;
            };
            Gat.prototype._getTrackers = noopFunc;
            Gat.prototype.aa = noopFunc;
            Gat.prototype.ab = noopFunc;
            Gat.prototype.hb = noopFunc;
            Gat.prototype.la = noopFunc;
            Gat.prototype.oa = noopFunc;
            Gat.prototype.pa = noopFunc;
            Gat.prototype.u = noopFunc;
            var gat = new Gat();
            window._gat = gat;
            hit(source);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function noopFunc() {}
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            GoogleAnalyticsGa.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function GoogleIma3(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function GoogleIma3(source) {
            var _window$google$ima;
            var VERSION = "3.453.0";
            var ima = {};
            var AdDisplayContainer = function AdDisplayContainer(
                containerElement,
            ) {
                var divElement = document.createElement("div");
                divElement.style.setProperty("display", "none", "important");
                divElement.style.setProperty(
                    "visibility",
                    "collapse",
                    "important",
                );
                if (containerElement) {
                    containerElement.appendChild(divElement);
                }
            };
            AdDisplayContainer.prototype.destroy = noopFunc;
            AdDisplayContainer.prototype.initialize = noopFunc;
            var ImaSdkSettings = function ImaSdkSettings() {};
            ImaSdkSettings.CompanionBackfillMode = {
                ALWAYS: "always",
                ON_MASTER_AD: "on_master_ad",
            };
            ImaSdkSettings.VpaidMode = {
                DISABLED: 0,
                ENABLED: 1,
                INSECURE: 2,
            };
            ImaSdkSettings.prototype = {
                c: true,
                f: {},
                i: false,
                l: "",
                p: "",
                r: 0,
                t: "",
                v: "",
                getCompanionBackfill: noopFunc,
                getDisableCustomPlaybackForIOS10Plus() {
                    return this.i;
                },
                getDisabledFlashAds: function getDisabledFlashAds() {
                    return true;
                },
                getFeatureFlags() {
                    return this.f;
                },
                getLocale() {
                    return this.l;
                },
                getNumRedirects() {
                    return this.r;
                },
                getPlayerType() {
                    return this.t;
                },
                getPlayerVersion() {
                    return this.v;
                },
                getPpid() {
                    return this.p;
                },
                getVpaidMode() {
                    return this.C;
                },
                isCookiesEnabled() {
                    return this.c;
                },
                isVpaidAdapter() {
                    return this.M;
                },
                setCompanionBackfill: noopFunc,
                setAutoPlayAdBreaks(a) {
                    this.K = a;
                },
                setCookiesEnabled(c) {
                    this.c = !!c;
                },
                setDisableCustomPlaybackForIOS10Plus(i) {
                    this.i = !!i;
                },
                setDisableFlashAds: noopFunc,
                setFeatureFlags(f) {
                    this.f = !!f;
                },
                setIsVpaidAdapter(a) {
                    this.M = a;
                },
                setLocale(l) {
                    this.l = !!l;
                },
                setNumRedirects(r) {
                    this.r = !!r;
                },
                setPageCorrelator(a) {
                    this.R = a;
                },
                setPlayerType(t) {
                    this.t = !!t;
                },
                setPlayerVersion(v) {
                    this.v = !!v;
                },
                setPpid(p) {
                    this.p = !!p;
                },
                setVpaidMode(a) {
                    this.C = a;
                },
                setSessionId: noopFunc,
                setStreamCorrelator: noopFunc,
                setVpaidAllowed: noopFunc,
                CompanionBackfillMode: {
                    ALWAYS: "always",
                    ON_MASTER_AD: "on_master_ad",
                },
                VpaidMode: {
                    DISABLED: 0,
                    ENABLED: 1,
                    INSECURE: 2,
                },
            };
            var EventHandler = function EventHandler() {
                this.listeners = new Map();
                this._dispatch = function (e) {
                    var listeners = this.listeners.get(e.type);
                    listeners = listeners ? listeners.values() : [];
                    for (
                        var _i = 0, _Array$from = Array.from(listeners);
                        _i < _Array$from.length;
                        _i++
                    ) {
                        var listener = _Array$from[_i];
                        try {
                            listener(e);
                        } catch (r) {
                            logMessage(source, r);
                        }
                    }
                };
                this.addEventListener = function (
                    types,
                    callback,
                    options,
                    context,
                ) {
                    if (!Array.isArray(types)) {
                        types = [types];
                    }
                    for (var i = 0; i < types.length; i += 1) {
                        var type = types[i];
                        if (!this.listeners.has(type)) {
                            this.listeners.set(type, new Map());
                        }
                        this.listeners
                            .get(type)
                            .set(callback, callback.bind(context || this));
                    }
                };
                this.removeEventListener = function (types, callback) {
                    if (!Array.isArray(types)) {
                        types = [types];
                    }
                    for (var i = 0; i < types.length; i += 1) {
                        var _this$listeners$get;
                        var type = types[i];
                        (_this$listeners$get = this.listeners.get(type)) ===
                            null ||
                            _this$listeners$get === void 0 ||
                            _this$listeners$get.delete(callback);
                    }
                };
            };
            var AdsManager = new EventHandler();
            AdsManager.volume = 1;
            AdsManager.collapse = noopFunc;
            AdsManager.configureAdsManager = noopFunc;
            AdsManager.destroy = noopFunc;
            AdsManager.discardAdBreak = noopFunc;
            AdsManager.expand = noopFunc;
            AdsManager.focus = noopFunc;
            AdsManager.getAdSkippableState = function () {
                return false;
            };
            AdsManager.getCuePoints = function () {
                return [0];
            };
            AdsManager.getCurrentAd = function () {
                return currentAd;
            };
            AdsManager.getCurrentAdCuePoints = function () {
                return [];
            };
            AdsManager.getRemainingTime = function () {
                return 0;
            };
            AdsManager.getVolume = function () {
                return this.volume;
            };
            AdsManager.init = noopFunc;
            AdsManager.isCustomClickTrackingUsed = function () {
                return false;
            };
            AdsManager.isCustomPlaybackUsed = function () {
                return false;
            };
            AdsManager.pause = noopFunc;
            AdsManager.requestNextAdBreak = noopFunc;
            AdsManager.resize = noopFunc;
            AdsManager.resume = noopFunc;
            AdsManager.setVolume = function (v) {
                this.volume = v;
            };
            AdsManager.skip = noopFunc;
            AdsManager.start = function () {
                for (
                    var _i2 = 0,
                        _arr = [
                            AdEvent.Type.ALL_ADS_COMPLETED,
                            AdEvent.Type.CONTENT_RESUME_REQUESTED,
                        ];
                    _i2 < _arr.length;
                    _i2++
                ) {
                    var type = _arr[_i2];
                    try {
                        this._dispatch(new ima.AdEvent(type));
                    } catch (e) {
                        logMessage(source, e);
                    }
                }
            };
            AdsManager.stop = noopFunc;
            AdsManager.updateAdsRenderingSettings = noopFunc;
            var manager = Object.create(AdsManager);
            var AdsManagerLoadedEvent = function AdsManagerLoadedEvent(
                type,
                adsRequest,
                userRequestContext,
            ) {
                this.type = type;
                this.adsRequest = adsRequest;
                this.userRequestContext = userRequestContext;
            };
            AdsManagerLoadedEvent.prototype = {
                getAdsManager: function getAdsManager() {
                    return manager;
                },
                getUserRequestContext() {
                    if (this.userRequestContext) {
                        return this.userRequestContext;
                    }
                    return {};
                },
            };
            AdsManagerLoadedEvent.Type = {
                ADS_MANAGER_LOADED: "adsManagerLoaded",
            };
            var AdsLoader = EventHandler;
            AdsLoader.prototype.settings = new ImaSdkSettings();
            AdsLoader.prototype.contentComplete = noopFunc;
            AdsLoader.prototype.destroy = noopFunc;
            AdsLoader.prototype.getSettings = function () {
                return this.settings;
            };
            AdsLoader.prototype.getVersion = function () {
                return VERSION;
            };
            AdsLoader.prototype.requestAds = function (
                adsRequest,
                userRequestContext,
            ) {
                var _this = this;
                requestAnimationFrame(function () {
                    var { ADS_MANAGER_LOADED: ADS_MANAGER_LOADED } =
                        AdsManagerLoadedEvent.Type;
                    var event = new ima.AdsManagerLoadedEvent(
                        ADS_MANAGER_LOADED,
                        adsRequest,
                        userRequestContext,
                    );
                    _this._dispatch(event);
                });
                var e = new ima.AdError(
                    "adPlayError",
                    1205,
                    1205,
                    "The browser prevented playback initiated without user interaction.",
                    adsRequest,
                    userRequestContext,
                );
                requestAnimationFrame(function () {
                    _this._dispatch(new ima.AdErrorEvent(e));
                });
            };
            var AdsRenderingSettings = noopFunc;
            var AdsRequest = function AdsRequest() {};
            AdsRequest.prototype = {
                setAdWillAutoPlay: noopFunc,
                setAdWillPlayMuted: noopFunc,
                setContinuousPlayback: noopFunc,
            };
            var AdPodInfo = function AdPodInfo() {};
            AdPodInfo.prototype = {
                getAdPosition: function getAdPosition() {
                    return 1;
                },
                getIsBumper: function getIsBumper() {
                    return false;
                },
                getMaxDuration: function getMaxDuration() {
                    return -1;
                },
                getPodIndex: function getPodIndex() {
                    return 1;
                },
                getTimeOffset: function getTimeOffset() {
                    return 0;
                },
                getTotalAds: function getTotalAds() {
                    return 1;
                },
            };
            var UniversalAdIdInfo = function UniversalAdIdInfo() {};
            UniversalAdIdInfo.prototype.getAdIdRegistry = function () {
                return "";
            };
            UniversalAdIdInfo.prototype.getAdIsValue = function () {
                return "";
            };
            var Ad = function Ad() {};
            Ad.prototype = {
                pi: new AdPodInfo(),
                getAdId: function getAdId() {
                    return "";
                },
                getAdPodInfo() {
                    return this.pi;
                },
                getAdSystem: function getAdSystem() {
                    return "";
                },
                getAdvertiserName: function getAdvertiserName() {
                    return "";
                },
                getApiFramework: function getApiFramework() {
                    return null;
                },
                getCompanionAds: function getCompanionAds() {
                    return [];
                },
                getContentType: function getContentType() {
                    return "";
                },
                getCreativeAdId: function getCreativeAdId() {
                    return "";
                },
                getDealId: function getDealId() {
                    return "";
                },
                getDescription: function getDescription() {
                    return "";
                },
                getDuration: function getDuration() {
                    return 8.5;
                },
                getHeight: function getHeight() {
                    return 0;
                },
                getMediaUrl: function getMediaUrl() {
                    return null;
                },
                getMinSuggestedDuration: function getMinSuggestedDuration() {
                    return -2;
                },
                getSkipTimeOffset: function getSkipTimeOffset() {
                    return -1;
                },
                getSurveyUrl: function getSurveyUrl() {
                    return null;
                },
                getTitle: function getTitle() {
                    return "";
                },
                getTraffickingParametersString:
                    function getTraffickingParametersString() {
                        return "";
                    },
                getUiElements: function getUiElements() {
                    return [""];
                },
                getUniversalAdIdRegistry: function getUniversalAdIdRegistry() {
                    return "unknown";
                },
                getUniversalAdIds: function getUniversalAdIds() {
                    return [new UniversalAdIdInfo()];
                },
                getUniversalAdIdValue: function getUniversalAdIdValue() {
                    return "unknown";
                },
                getVastMediaBitrate: function getVastMediaBitrate() {
                    return 0;
                },
                getVastMediaHeight: function getVastMediaHeight() {
                    return 0;
                },
                getVastMediaWidth: function getVastMediaWidth() {
                    return 0;
                },
                getWidth: function getWidth() {
                    return 0;
                },
                getWrapperAdIds: function getWrapperAdIds() {
                    return [""];
                },
                getWrapperAdSystems: function getWrapperAdSystems() {
                    return [""];
                },
                getWrapperCreativeIds: function getWrapperCreativeIds() {
                    return [""];
                },
                isLinear: function isLinear() {
                    return true;
                },
                isSkippable() {
                    return true;
                },
            };
            var CompanionAd = function CompanionAd() {};
            CompanionAd.prototype = {
                getAdSlotId: function getAdSlotId() {
                    return "";
                },
                getContent: function getContent() {
                    return "";
                },
                getContentType: function getContentType() {
                    return "";
                },
                getHeight: function getHeight() {
                    return 1;
                },
                getWidth: function getWidth() {
                    return 1;
                },
            };
            var AdError = function AdError(
                type,
                code,
                vast,
                message,
                adsRequest,
                userRequestContext,
            ) {
                this.errorCode = code;
                this.message = message;
                this.type = type;
                this.adsRequest = adsRequest;
                this.userRequestContext = userRequestContext;
                this.getErrorCode = function () {
                    return this.errorCode;
                };
                this.getInnerError = function () {
                    return null;
                };
                this.getMessage = function () {
                    return this.message;
                };
                this.getType = function () {
                    return this.type;
                };
                this.getVastErrorCode = function () {
                    return this.vastErrorCode;
                };
                this.toString = function () {
                    return `AdError ${this.errorCode}: ${this.message}`;
                };
            };
            AdError.ErrorCode = {};
            AdError.Type = {};
            var isEngadget = function isEngadget() {
                try {
                    for (
                        var _i3 = 0,
                            _Object$values = Object.values(
                                window.vidible._getContexts(),
                            );
                        _i3 < _Object$values.length;
                        _i3++
                    ) {
                        var _ctx$getPlayer;
                        var ctx = _Object$values[_i3];
                        if (
                            (_ctx$getPlayer = ctx.getPlayer()) !== null &&
                            _ctx$getPlayer !== void 0 &&
                            (_ctx$getPlayer = _ctx$getPlayer.div) !== null &&
                            _ctx$getPlayer !== void 0 &&
                            _ctx$getPlayer.innerHTML.includes(
                                "www.engadget.com",
                            )
                        ) {
                            return true;
                        }
                    }
                } catch (e) {}
                return false;
            };
            var currentAd = isEngadget() ? undefined : new Ad();
            var AdEvent = function AdEvent(type) {
                this.type = type;
            };
            AdEvent.prototype = {
                getAd: function getAd() {
                    return currentAd;
                },
                getAdData: function getAdData() {},
            };
            AdEvent.Type = {
                AD_BREAK_READY: "adBreakReady",
                AD_BUFFERING: "adBuffering",
                AD_CAN_PLAY: "adCanPlay",
                AD_METADATA: "adMetadata",
                AD_PROGRESS: "adProgress",
                ALL_ADS_COMPLETED: "allAdsCompleted",
                CLICK: "click",
                COMPLETE: "complete",
                CONTENT_PAUSE_REQUESTED: "contentPauseRequested",
                CONTENT_RESUME_REQUESTED: "contentResumeRequested",
                DURATION_CHANGE: "durationChange",
                EXPANDED_CHANGED: "expandedChanged",
                FIRST_QUARTILE: "firstQuartile",
                IMPRESSION: "impression",
                INTERACTION: "interaction",
                LINEAR_CHANGE: "linearChange",
                LINEAR_CHANGED: "linearChanged",
                LOADED: "loaded",
                LOG: "log",
                MIDPOINT: "midpoint",
                PAUSED: "pause",
                RESUMED: "resume",
                SKIPPABLE_STATE_CHANGED: "skippableStateChanged",
                SKIPPED: "skip",
                STARTED: "start",
                THIRD_QUARTILE: "thirdQuartile",
                USER_CLOSE: "userClose",
                VIDEO_CLICKED: "videoClicked",
                VIDEO_ICON_CLICKED: "videoIconClicked",
                VIEWABLE_IMPRESSION: "viewable_impression",
                VOLUME_CHANGED: "volumeChange",
                VOLUME_MUTED: "mute",
            };
            var AdErrorEvent = function AdErrorEvent(error) {
                this.error = error;
                this.type = "adError";
                this.getError = function () {
                    return this.error;
                };
                this.getUserRequestContext = function () {
                    var _this$error;
                    if (
                        (_this$error = this.error) !== null &&
                        _this$error !== void 0 &&
                        _this$error.userRequestContext
                    ) {
                        return this.error.userRequestContext;
                    }
                    return {};
                };
            };
            AdErrorEvent.Type = {
                AD_ERROR: "adError",
            };
            var CustomContentLoadedEvent =
                function CustomContentLoadedEvent() {};
            CustomContentLoadedEvent.Type = {
                CUSTOM_CONTENT_LOADED: "deprecated-event",
            };
            var CompanionAdSelectionSettings =
                function CompanionAdSelectionSettings() {};
            CompanionAdSelectionSettings.CreativeType = {
                ALL: "All",
                FLASH: "Flash",
                IMAGE: "Image",
            };
            CompanionAdSelectionSettings.ResourceType = {
                ALL: "All",
                HTML: "Html",
                IFRAME: "IFrame",
                STATIC: "Static",
            };
            CompanionAdSelectionSettings.SizeCriteria = {
                IGNORE: "IgnoreSize",
                SELECT_EXACT_MATCH: "SelectExactMatch",
                SELECT_NEAR_MATCH: "SelectNearMatch",
            };
            var AdCuePoints = function AdCuePoints() {};
            AdCuePoints.prototype = {
                getCuePoints: function getCuePoints() {
                    return [];
                },
                getAdIdRegistry: function getAdIdRegistry() {
                    return "";
                },
                getAdIdValue: function getAdIdValue() {
                    return "";
                },
            };
            var AdProgressData = noopFunc;
            Object.assign(ima, {
                AdCuePoints: AdCuePoints,
                AdDisplayContainer: AdDisplayContainer,
                AdError: AdError,
                AdErrorEvent: AdErrorEvent,
                AdEvent: AdEvent,
                AdPodInfo: AdPodInfo,
                AdProgressData: AdProgressData,
                AdsLoader: AdsLoader,
                AdsManager: manager,
                AdsManagerLoadedEvent: AdsManagerLoadedEvent,
                AdsRenderingSettings: AdsRenderingSettings,
                AdsRequest: AdsRequest,
                CompanionAd: CompanionAd,
                CompanionAdSelectionSettings: CompanionAdSelectionSettings,
                CustomContentLoadedEvent: CustomContentLoadedEvent,
                gptProxyInstance: {},
                ImaSdkSettings: ImaSdkSettings,
                OmidAccessMode: {
                    DOMAIN: "domain",
                    FULL: "full",
                    LIMITED: "limited",
                },
                OmidVerificationVendor: {
                    1: "OTHER",
                    2: "MOAT",
                    3: "DOUBLEVERIFY",
                    4: "INTEGRAL_AD_SCIENCE",
                    5: "PIXELATE",
                    6: "NIELSEN",
                    7: "COMSCORE",
                    8: "MEETRICS",
                    9: "GOOGLE",
                    OTHER: 1,
                    MOAT: 2,
                    DOUBLEVERIFY: 3,
                    INTEGRAL_AD_SCIENCE: 4,
                    PIXELATE: 5,
                    NIELSEN: 6,
                    COMSCORE: 7,
                    MEETRICS: 8,
                    GOOGLE: 9,
                },
                settings: new ImaSdkSettings(),
                UiElements: {
                    AD_ATTRIBUTION: "adAttribution",
                    COUNTDOWN: "countdown",
                },
                UniversalAdIdInfo: UniversalAdIdInfo,
                VERSION: VERSION,
                ViewMode: {
                    FULLSCREEN: "fullscreen",
                    NORMAL: "normal",
                },
            });
            if (!window.google) {
                window.google = {};
            }
            if (
                (_window$google$ima = window.google.ima) !== null &&
                _window$google$ima !== void 0 &&
                _window$google$ima.dai
            ) {
                ima.dai = window.google.ima.dai;
            }
            window.google.ima = ima;
            hit(source);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function noopFunc() {}
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            GoogleIma3.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function GoogleSyndicationAdsByGoogle(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function GoogleSyndicationAdsByGoogle(source) {
            window.adsbygoogle = {
                loaded: true,
                push(arg) {
                    if (typeof this.length === "undefined") {
                        this.length = 0;
                        this.length += 1;
                    }
                    if (
                        arg !== null &&
                        arg instanceof Object &&
                        arg.constructor.name === "Object"
                    ) {
                        for (
                            var _i = 0, _Object$keys = Object.keys(arg);
                            _i < _Object$keys.length;
                            _i++
                        ) {
                            var key = _Object$keys[_i];
                            if (typeof arg[key] === "function") {
                                try {
                                    arg[key].call(this, {});
                                } catch (_unused) {}
                            }
                        }
                    }
                },
            };
            var adElems = document.querySelectorAll(".adsbygoogle");
            var css =
                "height:1px!important;max-height:1px!important;max-width:1px!important;width:1px!important;";
            var statusAttrName = "data-adsbygoogle-status";
            var ASWIFT_IFRAME_MARKER = "aswift_";
            var GOOGLE_ADS_IFRAME_MARKER = "google_ads_iframe_";
            var executed = false;
            for (var i = 0; i < adElems.length; i += 1) {
                var adElemChildNodes = adElems[i].childNodes;
                var childNodesQuantity = adElemChildNodes.length;
                var areIframesDefined = false;
                if (childNodesQuantity > 0) {
                    areIframesDefined =
                        childNodesQuantity === 2 &&
                        adElemChildNodes[0].nodeName.toLowerCase() ===
                            "iframe" &&
                        adElemChildNodes[0].id.includes(ASWIFT_IFRAME_MARKER) &&
                        adElemChildNodes[1].nodeName.toLowerCase() ===
                            "iframe" &&
                        adElemChildNodes[1].id.includes(
                            GOOGLE_ADS_IFRAME_MARKER,
                        );
                }
                if (!areIframesDefined) {
                    adElems[i].setAttribute(statusAttrName, "done");
                    var aswiftIframe = document.createElement("iframe");
                    aswiftIframe.id = `${ASWIFT_IFRAME_MARKER}${i}`;
                    aswiftIframe.style = css;
                    adElems[i].appendChild(aswiftIframe);
                    var innerAswiftIframe = document.createElement("iframe");
                    aswiftIframe.contentWindow.document.body.appendChild(
                        innerAswiftIframe,
                    );
                    var googleadsIframe = document.createElement("iframe");
                    googleadsIframe.id = `${GOOGLE_ADS_IFRAME_MARKER}${i}`;
                    googleadsIframe.style = css;
                    adElems[i].appendChild(googleadsIframe);
                    var innerGoogleadsIframe = document.createElement("iframe");
                    googleadsIframe.contentWindow.document.body.appendChild(
                        innerGoogleadsIframe,
                    );
                    executed = true;
                }
            }
            if (executed) {
                hit(source);
            }
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            GoogleSyndicationAdsByGoogle.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function GoogleTagServicesGpt(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function GoogleTagServicesGpt(source) {
            var slots = new Map();
            var slotsById = new Map();
            var slotsPerPath = new Map();
            var slotCreatives = new Map();
            var eventCallbacks = new Map();
            var gTargeting = new Map();
            var addEventListener = function addEventListener(name, listener) {
                if (!eventCallbacks.has(name)) {
                    eventCallbacks.set(name, new Set());
                }
                eventCallbacks.get(name).add(listener);
                return this;
            };
            var removeEventListener = function removeEventListener(
                name,
                listener,
            ) {
                if (eventCallbacks.has(name)) {
                    return eventCallbacks.get(name).delete(listener);
                }
                return false;
            };
            var fireSlotEvent = function fireSlotEvent(name, slot) {
                return new Promise(function (resolve) {
                    requestAnimationFrame(function () {
                        var size = [0, 0];
                        var callbacksSet = eventCallbacks.get(name) || [];
                        var callbackArray = Array.from(callbacksSet);
                        for (var i = 0; i < callbackArray.length; i += 1) {
                            callbackArray[i]({
                                isEmpty: true,
                                size: size,
                                slot: slot,
                            });
                        }
                        resolve();
                    });
                });
            };
            var emptySlotElement = function emptySlotElement(slot) {
                var node = document.getElementById(slot.getSlotElementId());
                while (node !== null && node !== void 0 && node.lastChild) {
                    node.lastChild.remove();
                }
            };
            var recreateIframeForSlot = function recreateIframeForSlot(slot) {
                var _document$getElementB;
                var eid = `google_ads_iframe_${slot.getId()}`;
                (_document$getElementB = document.getElementById(eid)) ===
                    null ||
                    _document$getElementB === void 0 ||
                    _document$getElementB.remove();
                var node = document.getElementById(slot.getSlotElementId());
                if (node) {
                    var f = document.createElement("iframe");
                    f.id = eid;
                    f.srcdoc = "<body></body>";
                    f.style =
                        "position:absolute; width:0; height:0; left:0; right:0; z-index:-1; border:0";
                    f.setAttribute("width", 0);
                    f.setAttribute("height", 0);
                    f.setAttribute("data-load-complete", true);
                    f.setAttribute("data-google-container-id", true);
                    f.setAttribute("sandbox", "");
                    node.appendChild(f);
                }
            };
            var displaySlot = function displaySlot(slot) {
                if (!slot) {
                    return;
                }
                var id = slot.getSlotElementId();
                if (!document.getElementById(id)) {
                    return;
                }
                var parent = document.getElementById(id);
                if (parent) {
                    parent.appendChild(document.createElement("div"));
                }
                emptySlotElement(slot);
                recreateIframeForSlot(slot);
                fireSlotEvent("slotRenderEnded", slot);
                fireSlotEvent("slotRequested", slot);
                fireSlotEvent("slotResponseReceived", slot);
                fireSlotEvent("slotOnload", slot);
                fireSlotEvent("impressionViewable", slot);
            };
            var companionAdsService = {
                addEventListener: addEventListener,
                removeEventListener: removeEventListener,
                enableSyncLoading: noopFunc,
                setRefreshUnfilledSlots: noopFunc,
                getSlots: noopArray,
            };
            var contentService = {
                addEventListener: addEventListener,
                removeEventListener: removeEventListener,
                setContent: noopFunc,
            };
            function PassbackSlot() {}
            PassbackSlot.prototype.display = noopFunc;
            PassbackSlot.prototype.get = noopNull;
            PassbackSlot.prototype.set = noopThis;
            PassbackSlot.prototype.setClickUrl = noopThis;
            PassbackSlot.prototype.setTagForChildDirectedTreatment = noopThis;
            PassbackSlot.prototype.setTargeting = noopThis;
            PassbackSlot.prototype.updateTargetingFromMap = noopThis;
            function SizeMappingBuilder() {}
            SizeMappingBuilder.prototype.addSize = noopThis;
            SizeMappingBuilder.prototype.build = noopNull;
            var getTargetingValue = function getTargetingValue(v) {
                if (typeof v === "string") {
                    return [v];
                }
                try {
                    return Array.prototype.flat.call(v);
                } catch (_unused) {}
                return [];
            };
            var updateTargeting = function updateTargeting(targeting, map) {
                if (typeof map === "object") {
                    for (var key in map) {
                        if (Object.prototype.hasOwnProperty.call(map, key)) {
                            targeting.set(key, getTargetingValue(map[key]));
                        }
                    }
                }
            };
            var defineSlot = function defineSlot(
                adUnitPath,
                creatives,
                optDiv,
            ) {
                if (slotsById.has(optDiv)) {
                    var _document$getElementB2;
                    (_document$getElementB2 =
                        document.getElementById(optDiv)) === null ||
                        _document$getElementB2 === void 0 ||
                        _document$getElementB2.remove();
                    return slotsById.get(optDiv);
                }
                var attributes = new Map();
                var targeting = new Map();
                var exclusions = new Set();
                var response = {
                    advertiserId: undefined,
                    campaignId: undefined,
                    creativeId: undefined,
                    creativeTemplateId: undefined,
                    lineItemId: undefined,
                };
                var sizes = [
                    {
                        getHeight: function getHeight() {
                            return 2;
                        },
                        getWidth: function getWidth() {
                            return 2;
                        },
                    },
                ];
                var num = (slotsPerPath.get(adUnitPath) || 0) + 1;
                slotsPerPath.set(adUnitPath, num);
                var id = `${adUnitPath}_${num}`;
                var clickUrl = "";
                var collapseEmptyDiv = null;
                var services = new Set();
                var slot = {
                    addService(e) {
                        services.add(e);
                        return slot;
                    },
                    clearCategoryExclusions: noopThis,
                    clearTargeting(k) {
                        if (k === undefined) {
                            targeting.clear();
                        } else {
                            targeting.delete(k);
                        }
                    },
                    defineSizeMapping(mapping) {
                        slotCreatives.set(optDiv, mapping);
                        return this;
                    },
                    get: function get(k) {
                        return attributes.get(k);
                    },
                    getAdUnitPath: function getAdUnitPath() {
                        return adUnitPath;
                    },
                    getAttributeKeys: function getAttributeKeys() {
                        return Array.from(attributes.keys());
                    },
                    getCategoryExclusions: function getCategoryExclusions() {
                        return Array.from(exclusions);
                    },
                    getClickUrl: function getClickUrl() {
                        return clickUrl;
                    },
                    getCollapseEmptyDiv: function getCollapseEmptyDiv() {
                        return collapseEmptyDiv;
                    },
                    getContentUrl: function getContentUrl() {
                        return "";
                    },
                    getDivStartsCollapsed: function getDivStartsCollapsed() {
                        return null;
                    },
                    getDomId: function getDomId() {
                        return optDiv;
                    },
                    getEscapedQemQueryId: function getEscapedQemQueryId() {
                        return "";
                    },
                    getFirstLook: function getFirstLook() {
                        return 0;
                    },
                    getId: function getId() {
                        return id;
                    },
                    getHtml: function getHtml() {
                        return "";
                    },
                    getName: function getName() {
                        return id;
                    },
                    getOutOfPage: function getOutOfPage() {
                        return false;
                    },
                    getResponseInformation: function getResponseInformation() {
                        return response;
                    },
                    getServices: function getServices() {
                        return Array.from(services);
                    },
                    getSizes: function getSizes() {
                        return sizes;
                    },
                    getSlotElementId: function getSlotElementId() {
                        return optDiv;
                    },
                    getSlotId: function getSlotId() {
                        return slot;
                    },
                    getTargeting: function getTargeting(k) {
                        return targeting.get(k) || gTargeting.get(k) || [];
                    },
                    getTargetingKeys: function getTargetingKeys() {
                        return Array.from(
                            new Set(
                                Array.of(
                                    ...gTargeting.keys(),
                                    ...targeting.keys(),
                                ),
                            ),
                        );
                    },
                    getTargetingMap: function getTargetingMap() {
                        return Object.assign(
                            Object.fromEntries(gTargeting.entries()),
                            Object.fromEntries(targeting.entries()),
                        );
                    },
                    set(k, v) {
                        attributes.set(k, v);
                        return slot;
                    },
                    setCategoryExclusion(e) {
                        exclusions.add(e);
                        return slot;
                    },
                    setClickUrl(u) {
                        clickUrl = u;
                        return slot;
                    },
                    setCollapseEmptyDiv(v) {
                        collapseEmptyDiv = !!v;
                        return slot;
                    },
                    setSafeFrameConfig: noopThis,
                    setTagForChildDirectedTreatment: noopThis,
                    setTargeting(k, v) {
                        targeting.set(k, getTargetingValue(v));
                        return slot;
                    },
                    toString: function toString() {
                        return id;
                    },
                    updateTargetingFromMap(map) {
                        updateTargeting(targeting, map);
                        return slot;
                    },
                };
                slots.set(adUnitPath, slot);
                slotsById.set(optDiv, slot);
                slotCreatives.set(optDiv, creatives);
                return slot;
            };
            var pubAdsService = {
                addEventListener: addEventListener,
                removeEventListener: removeEventListener,
                clear: noopFunc,
                clearCategoryExclusions: noopThis,
                clearTagForChildDirectedTreatment: noopThis,
                clearTargeting(k) {
                    if (k === undefined) {
                        gTargeting.clear();
                    } else {
                        gTargeting.delete(k);
                    }
                },
                collapseEmptyDivs: noopFunc,
                defineOutOfPagePassback() {
                    return new PassbackSlot();
                },
                definePassback() {
                    return new PassbackSlot();
                },
                disableInitialLoad: noopFunc,
                display: noopFunc,
                enableAsyncRendering: noopFunc,
                enableLazyLoad: noopFunc,
                enableSingleRequest: noopFunc,
                enableSyncRendering: noopFunc,
                enableVideoAds: noopFunc,
                get: noopNull,
                getAttributeKeys: noopArray,
                getTargeting: noopArray,
                getTargetingKeys: noopArray,
                getSlots: noopArray,
                isInitialLoadDisabled: trueFunc,
                refresh: noopFunc,
                set: noopThis,
                setCategoryExclusion: noopThis,
                setCentering: noopFunc,
                setCookieOptions: noopThis,
                setForceSafeFrame: noopThis,
                setLocation: noopThis,
                setPrivacySettings: noopThis,
                setPublisherProvidedId: noopThis,
                setRequestNonPersonalizedAds: noopThis,
                setSafeFrameConfig: noopThis,
                setTagForChildDirectedTreatment: noopThis,
                setTargeting: noopThis,
                setVideoContent: noopThis,
                updateCorrelator: noopFunc,
            };
            var { googletag = {} } = window;
            var { cmd = [] } = googletag;
            googletag.apiReady = true;
            googletag.cmd = [];
            googletag.cmd.push = function (a) {
                try {
                    a();
                } catch (ex) {}
                return 1;
            };
            googletag.companionAds = function () {
                return companionAdsService;
            };
            googletag.content = function () {
                return contentService;
            };
            googletag.defineOutOfPageSlot = defineSlot;
            googletag.defineSlot = defineSlot;
            googletag.destroySlots = function () {
                slots.clear();
                slotsById.clear();
            };
            googletag.disablePublisherConsole = noopFunc;
            googletag.display = function (arg) {
                var id;
                if (arg !== null && arg !== void 0 && arg.getSlotElementId) {
                    id = arg.getSlotElementId();
                } else if (arg !== null && arg !== void 0 && arg.nodeType) {
                    id = arg.id;
                } else {
                    id = String(arg);
                }
                displaySlot(slotsById.get(id));
            };
            googletag.enableServices = noopFunc;
            googletag.getVersion = noopStr;
            googletag.pubads = function () {
                return pubAdsService;
            };
            googletag.pubadsReady = true;
            googletag.setAdIframeTitle = noopFunc;
            googletag.sizeMapping = function () {
                return new SizeMappingBuilder();
            };
            window.googletag = googletag;
            while (cmd.length !== 0) {
                googletag.cmd.push(cmd.shift());
            }
            hit(source);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function noopFunc() {}
        function noopThis() {
            return this;
        }
        function noopNull() {
            return null;
        }
        function noopArray() {
            return [];
        }
        function noopStr() {
            return "";
        }
        function trueFunc() {
            return true;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            GoogleTagServicesGpt.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function Matomo(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function Matomo(source) {
            var Tracker = function Tracker() {};
            Tracker.prototype.setDoNotTrack = noopFunc;
            Tracker.prototype.setDomains = noopFunc;
            Tracker.prototype.setCustomDimension = noopFunc;
            Tracker.prototype.trackPageView = noopFunc;
            var AsyncTracker = function AsyncTracker() {};
            AsyncTracker.prototype.addListener = noopFunc;
            var matomoWrapper = {
                getTracker: Tracker,
                getAsyncTracker: AsyncTracker,
            };
            window.Piwik = matomoWrapper;
            hit(source);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function noopFunc() {}
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            Matomo.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function NaverWcslog(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function NaverWcslog(source) {
            window.wcs_add = {};
            window.wcs_do = noopFunc;
            window.wcs = {
                inflow: noopFunc,
            };
            hit(source);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function noopFunc() {}
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            NaverWcslog.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function Pardot(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function Pardot(source) {
            window.piVersion = "1.0.2";
            window.piScriptNum = 0;
            window.piScriptObj = [];
            window.checkNamespace = noopFunc;
            window.getPardotUrl = noopStr;
            window.piGetParameter = noopNull;
            window.piSetCookie = noopFunc;
            window.piGetCookie = noopStr;
            function piTracker() {
                window.pi = {
                    tracker: {
                        visitor_id: "",
                        visitor_id_sign: "",
                        pi_opt_in: "",
                        campaign_id: "",
                    },
                };
                window.piScriptNum += 1;
            }
            window.piResponse = noopFunc;
            window.piTracker = piTracker;
            piTracker();
            hit(source);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function noopFunc() {}
        function noopStr() {
            return "";
        }
        function noopNull() {
            return null;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            Pardot.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function Prebid(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function Prebid(source) {
            var pushFunction = function pushFunction(arg) {
                if (typeof arg === "function") {
                    try {
                        arg.call();
                    } catch (ex) {}
                }
            };
            var pbjsWrapper = {
                addAdUnits() {},
                adServers: {
                    dfp: {
                        buildVideoUrl: noopStr,
                    },
                },
                adUnits: [],
                aliasBidder() {},
                cmd: [],
                enableAnalytics() {},
                getHighestCpmBids: noopArray,
                libLoaded: true,
                que: [],
                requestBids(arg) {
                    if (arg instanceof Object && arg.bidsBackHandler) {
                        try {
                            arg.bidsBackHandler.call();
                        } catch (ex) {}
                    }
                },
                removeAdUnit() {},
                setBidderConfig() {},
                setConfig() {},
                setTargetingForGPTAsync() {},
            };
            pbjsWrapper.cmd.push = pushFunction;
            pbjsWrapper.que.push = pushFunction;
            window.pbjs = pbjsWrapper;
            hit(source);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function noopStr() {
            return "";
        }
        function noopArray() {
            return [];
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            Prebid.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function ScoreCardResearchBeacon(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function ScoreCardResearchBeacon(source) {
            window.COMSCORE = {
                purge() {
                    window._comscore = [];
                },
                beacon() {},
            };
            hit(source);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            ScoreCardResearchBeacon.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function abortCurrentInlineScript(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function abortCurrentInlineScript(source, property, search) {
            var searchRegexp = toRegExp(search);
            var rid = randomId();
            var SRC_DATA_MARKER = "data:text/javascript;base64,";
            var getCurrentScript = function getCurrentScript() {
                if ("currentScript" in document) {
                    return document.currentScript;
                }
                var scripts = document.getElementsByTagName("script");
                return scripts[scripts.length - 1];
            };
            var ourScript = getCurrentScript();
            var abort = function abort() {
                var _scriptEl$src;
                var scriptEl = getCurrentScript();
                if (!scriptEl) {
                    return;
                }
                var content = scriptEl.textContent;
                try {
                    var textContentGetter = Object.getOwnPropertyDescriptor(
                        Node.prototype,
                        "textContent",
                    ).get;
                    content = textContentGetter.call(scriptEl);
                } catch (e) {}
                if (
                    content.length === 0 &&
                    typeof scriptEl.src !== "undefined" &&
                    (_scriptEl$src = scriptEl.src) !== null &&
                    _scriptEl$src !== void 0 &&
                    _scriptEl$src.startsWith(SRC_DATA_MARKER)
                ) {
                    var encodedContent = scriptEl.src.slice(
                        SRC_DATA_MARKER.length,
                    );
                    content = window.atob(encodedContent);
                }
                if (
                    scriptEl instanceof HTMLScriptElement &&
                    content.length > 0 &&
                    scriptEl !== ourScript &&
                    searchRegexp.test(content)
                ) {
                    hit(source);
                    throw new ReferenceError(rid);
                }
            };
            var _setChainPropAccess = function setChainPropAccess(
                owner,
                property,
            ) {
                var chainInfo = getPropertyInChain(owner, property);
                var { base: base } = chainInfo;
                var { prop: prop, chain: chain } = chainInfo;
                if (base instanceof Object === false && base === null) {
                    var props = property.split(".");
                    var propIndex = props.indexOf(prop);
                    var baseName = props[propIndex - 1];
                    var message = `The scriptlet had been executed before the ${baseName} was loaded.`;
                    logMessage(source, message);
                    return;
                }
                if (chain) {
                    var setter = function setter(a) {
                        base = a;
                        if (a instanceof Object) {
                            _setChainPropAccess(a, chain);
                        }
                    };
                    Object.defineProperty(owner, prop, {
                        get: function get() {
                            return base;
                        },
                        set: setter,
                    });
                    return;
                }
                var currentValue = base[prop];
                var origDescriptor = Object.getOwnPropertyDescriptor(
                    base,
                    prop,
                );
                if (
                    origDescriptor instanceof Object === false ||
                    origDescriptor.get instanceof Function === false
                ) {
                    currentValue = base[prop];
                    origDescriptor = undefined;
                }
                var descriptorWrapper = Object.assign(getDescriptorAddon(), {
                    currentValue: currentValue,
                    get() {
                        if (!this.isAbortingSuspended) {
                            this.isolateCallback(abort);
                        }
                        if (origDescriptor instanceof Object) {
                            return origDescriptor.get.call(base);
                        }
                        return this.currentValue;
                    },
                    set(newValue) {
                        if (!this.isAbortingSuspended) {
                            this.isolateCallback(abort);
                        }
                        if (origDescriptor instanceof Object) {
                            origDescriptor.set.call(base, newValue);
                        } else {
                            this.currentValue = newValue;
                        }
                    },
                });
                setPropertyAccess(base, prop, {
                    get() {
                        return descriptorWrapper.get.call(descriptorWrapper);
                    },
                    set(newValue) {
                        descriptorWrapper.set.call(descriptorWrapper, newValue);
                    },
                });
            };
            _setChainPropAccess(window, property);
            window.onerror = createOnErrorHandler(rid).bind();
        }
        function randomId() {
            return Math.random().toString(36).slice(2, 9);
        }
        function setPropertyAccess(e, r, t) {
            var c = Object.getOwnPropertyDescriptor(e, r);
            return (
                !(c && !c.configurable) &&
                (Object.defineProperty(e, r, t), true)
            );
        }
        function getPropertyInChain(e, r) {
            var n = r.indexOf(".");
            if (-1 === n)
                return {
                    base: e,
                    prop: r,
                };
            var i = r.slice(0, n);
            if (null === e)
                return {
                    base: e,
                    prop: i,
                    chain: r,
                };
            var t = e[i];
            return (
                (r = r.slice(n + 1)),
                ((e instanceof Object || "object" == typeof e) &&
                    isEmptyObject(e)) ||
                null === t
                    ? {
                          base: e,
                          prop: i,
                          chain: r,
                      }
                    : void 0 !== t
                      ? getPropertyInChain(t, r)
                      : (Object.defineProperty(e, i, {
                            configurable: true,
                        }),
                        {
                            base: e,
                            prop: i,
                            chain: r,
                        })
            );
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function createOnErrorHandler(r) {
            var n = window.onerror;
            return function (e) {
                if ("string" == typeof e && e.includes(r)) return true;
                if (n instanceof Function) {
                    for (
                        var t = arguments.length,
                            o = new Array(t > 1 ? t - 1 : 0),
                            i = 1;
                        i < t;
                        i++
                    )
                        o[i - 1] = arguments[i];
                    return n.apply(window, [e, ...o]);
                }
                return false;
            };
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function isEmptyObject(t) {
            return 0 === Object.keys(t).length && !t.prototype;
        }
        function getDescriptorAddon() {
            return {
                isAbortingSuspended: false,
                isolateCallback(r) {
                    this.isAbortingSuspended = true;
                    try {
                        for (
                            var e = arguments.length,
                                n = new Array(e > 1 ? e - 1 : 0),
                                t = 1;
                            t < e;
                            t++
                        )
                            n[t - 1] = arguments[t];
                        var i = r(...n);
                        return ((this.isAbortingSuspended = !1), i);
                    } catch (r) {
                        var s = randomId();
                        throw (
                            (this.isAbortingSuspended = false),
                            new ReferenceError(s)
                        );
                    }
                },
            };
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            abortCurrentInlineScript.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function abortOnPropertyRead(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function abortOnPropertyRead(source, property) {
            if (!property) {
                return;
            }
            var rid = randomId();
            var abort = function abort() {
                hit(source);
                throw new ReferenceError(rid);
            };
            var _setChainPropAccess = function setChainPropAccess(
                owner,
                property,
            ) {
                var chainInfo = getPropertyInChain(owner, property);
                var { base: base } = chainInfo;
                var { prop: prop, chain: chain } = chainInfo;
                if (chain) {
                    var setter = function setter(a) {
                        base = a;
                        if (a instanceof Object) {
                            _setChainPropAccess(a, chain);
                        }
                    };
                    Object.defineProperty(owner, prop, {
                        get: function get() {
                            return base;
                        },
                        set: setter,
                    });
                    return;
                }
                setPropertyAccess(base, prop, {
                    get: abort,
                    set: function set() {},
                });
            };
            _setChainPropAccess(window, property);
            window.onerror = createOnErrorHandler(rid).bind();
        }
        function randomId() {
            return Math.random().toString(36).slice(2, 9);
        }
        function setPropertyAccess(e, r, t) {
            var c = Object.getOwnPropertyDescriptor(e, r);
            return (
                !(c && !c.configurable) &&
                (Object.defineProperty(e, r, t), true)
            );
        }
        function getPropertyInChain(e, r) {
            var n = r.indexOf(".");
            if (-1 === n)
                return {
                    base: e,
                    prop: r,
                };
            var i = r.slice(0, n);
            if (null === e)
                return {
                    base: e,
                    prop: i,
                    chain: r,
                };
            var t = e[i];
            return (
                (r = r.slice(n + 1)),
                ((e instanceof Object || "object" == typeof e) &&
                    isEmptyObject(e)) ||
                null === t
                    ? {
                          base: e,
                          prop: i,
                          chain: r,
                      }
                    : void 0 !== t
                      ? getPropertyInChain(t, r)
                      : (Object.defineProperty(e, i, {
                            configurable: true,
                        }),
                        {
                            base: e,
                            prop: i,
                            chain: r,
                        })
            );
        }
        function createOnErrorHandler(r) {
            var n = window.onerror;
            return function (e) {
                if ("string" == typeof e && e.includes(r)) return true;
                if (n instanceof Function) {
                    for (
                        var t = arguments.length,
                            o = new Array(t > 1 ? t - 1 : 0),
                            i = 1;
                        i < t;
                        i++
                    )
                        o[i - 1] = arguments[i];
                    return n.apply(window, [e, ...o]);
                }
                return false;
            };
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function isEmptyObject(t) {
            return 0 === Object.keys(t).length && !t.prototype;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            abortOnPropertyRead.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function abortOnPropertyWrite(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function abortOnPropertyWrite(source, property) {
            if (!property) {
                return;
            }
            var rid = randomId();
            var abort = function abort() {
                hit(source);
                throw new ReferenceError(rid);
            };
            var _setChainPropAccess = function setChainPropAccess(
                owner,
                property,
            ) {
                var chainInfo = getPropertyInChain(owner, property);
                var { base: base } = chainInfo;
                var { prop: prop, chain: chain } = chainInfo;
                if (chain) {
                    var setter = function setter(a) {
                        base = a;
                        if (a instanceof Object) {
                            _setChainPropAccess(a, chain);
                        }
                    };
                    Object.defineProperty(owner, prop, {
                        get: function get() {
                            return base;
                        },
                        set: setter,
                    });
                    return;
                }
                setPropertyAccess(base, prop, {
                    set: abort,
                });
            };
            _setChainPropAccess(window, property);
            window.onerror = createOnErrorHandler(rid).bind();
        }
        function randomId() {
            return Math.random().toString(36).slice(2, 9);
        }
        function setPropertyAccess(e, r, t) {
            var c = Object.getOwnPropertyDescriptor(e, r);
            return (
                !(c && !c.configurable) &&
                (Object.defineProperty(e, r, t), true)
            );
        }
        function getPropertyInChain(e, r) {
            var n = r.indexOf(".");
            if (-1 === n)
                return {
                    base: e,
                    prop: r,
                };
            var i = r.slice(0, n);
            if (null === e)
                return {
                    base: e,
                    prop: i,
                    chain: r,
                };
            var t = e[i];
            return (
                (r = r.slice(n + 1)),
                ((e instanceof Object || "object" == typeof e) &&
                    isEmptyObject(e)) ||
                null === t
                    ? {
                          base: e,
                          prop: i,
                          chain: r,
                      }
                    : void 0 !== t
                      ? getPropertyInChain(t, r)
                      : (Object.defineProperty(e, i, {
                            configurable: true,
                        }),
                        {
                            base: e,
                            prop: i,
                            chain: r,
                        })
            );
        }
        function createOnErrorHandler(r) {
            var n = window.onerror;
            return function (e) {
                if ("string" == typeof e && e.includes(r)) return true;
                if (n instanceof Function) {
                    for (
                        var t = arguments.length,
                            o = new Array(t > 1 ? t - 1 : 0),
                            i = 1;
                        i < t;
                        i++
                    )
                        o[i - 1] = arguments[i];
                    return n.apply(window, [e, ...o]);
                }
                return false;
            };
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function isEmptyObject(t) {
            return 0 === Object.keys(t).length && !t.prototype;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            abortOnPropertyWrite.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function abortOnStackTrace(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function abortOnStackTrace(source, property, stack) {
            if (!property || !stack) {
                return;
            }
            var rid = randomId();
            var abort = function abort() {
                hit(source);
                throw new ReferenceError(rid);
            };
            var _setChainPropAccess = function setChainPropAccess(
                owner,
                property,
            ) {
                var chainInfo = getPropertyInChain(owner, property);
                var { base: base } = chainInfo;
                var { prop: prop, chain: chain } = chainInfo;
                if (chain) {
                    var setter = function setter(a) {
                        base = a;
                        if (a instanceof Object) {
                            _setChainPropAccess(a, chain);
                        }
                    };
                    Object.defineProperty(owner, prop, {
                        get: function get() {
                            return base;
                        },
                        set: setter,
                    });
                    return;
                }
                if (
                    !stack.match(/^(inlineScript|injectedScript)$/) &&
                    !isValidStrPattern(stack)
                ) {
                    logMessage(source, `Invalid parameter: ${stack}`);
                    return;
                }
                var descriptorWrapper = Object.assign(getDescriptorAddon(), {
                    value: base[prop],
                    get() {
                        if (
                            !this.isAbortingSuspended &&
                            this.isolateCallback(
                                matchStackTrace,
                                stack,
                                new Error().stack,
                            )
                        ) {
                            abort();
                        }
                        return this.value;
                    },
                    set(newValue) {
                        if (
                            !this.isAbortingSuspended &&
                            this.isolateCallback(
                                matchStackTrace,
                                stack,
                                new Error().stack,
                            )
                        ) {
                            abort();
                        }
                        this.value = newValue;
                    },
                });
                setPropertyAccess(base, prop, {
                    get() {
                        return descriptorWrapper.get.call(descriptorWrapper);
                    },
                    set(newValue) {
                        descriptorWrapper.set.call(descriptorWrapper, newValue);
                    },
                });
            };
            _setChainPropAccess(window, property);
            window.onerror = createOnErrorHandler(rid).bind();
        }
        function randomId() {
            return Math.random().toString(36).slice(2, 9);
        }
        function setPropertyAccess(e, r, t) {
            var c = Object.getOwnPropertyDescriptor(e, r);
            return (
                !(c && !c.configurable) &&
                (Object.defineProperty(e, r, t), true)
            );
        }
        function getPropertyInChain(e, r) {
            var n = r.indexOf(".");
            if (-1 === n)
                return {
                    base: e,
                    prop: r,
                };
            var i = r.slice(0, n);
            if (null === e)
                return {
                    base: e,
                    prop: i,
                    chain: r,
                };
            var t = e[i];
            return (
                (r = r.slice(n + 1)),
                ((e instanceof Object || "object" == typeof e) &&
                    isEmptyObject(e)) ||
                null === t
                    ? {
                          base: e,
                          prop: i,
                          chain: r,
                      }
                    : void 0 !== t
                      ? getPropertyInChain(t, r)
                      : (Object.defineProperty(e, i, {
                            configurable: true,
                        }),
                        {
                            base: e,
                            prop: i,
                            chain: r,
                        })
            );
        }
        function createOnErrorHandler(r) {
            var n = window.onerror;
            return function (e) {
                if ("string" == typeof e && e.includes(r)) return true;
                if (n instanceof Function) {
                    for (
                        var t = arguments.length,
                            o = new Array(t > 1 ? t - 1 : 0),
                            i = 1;
                        i < t;
                        i++
                    )
                        o[i - 1] = arguments[i];
                    return n.apply(window, [e, ...o]);
                }
                return false;
            };
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function isValidStrPattern(e) {
            var t,
                n = escapeRegExp(e);
            "/" === e[0] && "/" === e[e.length - 1] && (n = e.slice(1, -1));
            try {
                ((t = new RegExp(n)), (t = !0));
            } catch (e) {
                t = false;
            }
            return t;
        }
        function escapeRegExp(e) {
            return e.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        }
        function matchStackTrace(e, t) {
            if (!e || "" === e) return true;
            var r = backupRegExpValues();
            if (shouldAbortInlineOrInjectedScript(e, t))
                return (
                    r.length && r[0] !== RegExp.$1 && restoreRegExpValues(r),
                    true
                );
            var n = toRegExp(e),
                a = t
                    .split("\n")
                    .slice(2)
                    .map(function (e) {
                        return e.trim();
                    })
                    .join("\n");
            return (
                r.length && r[0] !== RegExp.$1 && restoreRegExpValues(r),
                getNativeRegexpTest().call(n, a)
            );
        }
        function getDescriptorAddon() {
            return {
                isAbortingSuspended: false,
                isolateCallback(r) {
                    this.isAbortingSuspended = true;
                    try {
                        for (
                            var e = arguments.length,
                                n = new Array(e > 1 ? e - 1 : 0),
                                t = 1;
                            t < e;
                            t++
                        )
                            n[t - 1] = arguments[t];
                        var i = r(...n);
                        return ((this.isAbortingSuspended = !1), i);
                    } catch (r) {
                        var s = randomId();
                        throw (
                            (this.isAbortingSuspended = false),
                            new ReferenceError(s)
                        );
                    }
                },
            };
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function isEmptyObject(t) {
            return 0 === Object.keys(t).length && !t.prototype;
        }
        function getNativeRegexpTest() {
            var t = Object.getOwnPropertyDescriptor(RegExp.prototype, "test"),
                e = null == t ? void 0 : t.value;
            if (t && "function" == typeof t.value) return e;
            throw new Error("RegExp.prototype.test is not a function");
        }
        function shouldAbortInlineOrInjectedScript(t, i) {
            var r = "inlineScript",
                n = "injectedScript",
                isInlineScript = function isInlineScript(t) {
                    return t.includes(r);
                },
                isInjectedScript = function isInjectedScript(t) {
                    return t.includes(n);
                };
            if (!isInlineScript(t) && !isInjectedScript(t)) return false;
            var e = window.location.href,
                s = e.indexOf("#");
            -1 !== s && (e = e.slice(0, s));
            var c = i
                .split("\n")
                .slice(2)
                .map(function (t) {
                    return t.trim();
                })
                .map(function (t) {
                    var i,
                        s = /(.*?@)?(\S+)(:\d+)(:\d+)\)?$/.exec(t);
                    if (s) {
                        var c,
                            l,
                            a = s[2],
                            u = s[3],
                            o = s[4];
                        if (
                            (null !== (c = a) &&
                                void 0 !== c &&
                                c.startsWith("(") &&
                                (a = a.slice(1)),
                            null !== (l = a) &&
                                void 0 !== l &&
                                l.startsWith("<anonymous>"))
                        ) {
                            var d;
                            a = n;
                            var f =
                                void 0 !== s[1]
                                    ? s[1].slice(0, -1)
                                    : t.slice(0, s.index).trim();
                            (null !== (d = f) &&
                                void 0 !== d &&
                                d.startsWith("at") &&
                                (f = f.slice(2).trim()),
                                (i = `${f} ${a}${u}${o}`.trim()));
                        } else
                            i =
                                a === e
                                    ? `${r}${u}${o}`.trim()
                                    : `${a}${u}${o}`.trim();
                    } else i = t;
                    return i;
                });
            if (c)
                for (var l = 0; l < c.length; l += 1) {
                    if (
                        isInlineScript(t) &&
                        c[l].startsWith(r) &&
                        c[l].match(toRegExp(t))
                    )
                        return true;
                    if (
                        isInjectedScript(t) &&
                        c[l].startsWith(n) &&
                        c[l].match(toRegExp(t))
                    )
                        return true;
                }
            return false;
        }
        function backupRegExpValues() {
            try {
                for (var r = [], e = 1; e < 10; e += 1) {
                    var a = `$${e}`;
                    if (!RegExp[a]) break;
                    r.push(RegExp[a]);
                }
                return r;
            } catch (r) {
                return [];
            }
        }
        function restoreRegExpValues(e) {
            if (e.length)
                try {
                    var r = "";
                    r =
                        1 === e.length
                            ? `(${e[0]})`
                            : e.reduce(function (e, r, t) {
                                  return 1 === t
                                      ? `(${e}),(${r})`
                                      : `${e},(${r})`;
                              });
                    var t = new RegExp(r);
                    e.toString().replace(t, "");
                } catch (e) {
                    var n = `Failed to restore RegExp values: ${e}`;
                    console.log(n);
                }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            abortOnStackTrace.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function adjustSetInterval(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function adjustSetInterval(source, matchCallback, matchDelay, boost) {
            var nativeSetInterval = window.setInterval;
            var matchRegexp = toRegExp(matchCallback);
            var intervalWrapper = function intervalWrapper(callback, delay) {
                if (!isValidCallback(callback)) {
                    var message = `Scriptlet can't be applied because of invalid callback: '${String(callback)}'`;
                    logMessage(source, message);
                } else if (
                    matchRegexp.test(callback.toString()) &&
                    isDelayMatched(matchDelay, delay)
                ) {
                    delay *= getBoostMultiplier(boost);
                    hit(source);
                }
                for (
                    var _len = arguments.length,
                        args = new Array(_len > 2 ? _len - 2 : 0),
                        _key = 2;
                    _key < _len;
                    _key++
                ) {
                    args[_key - 2] = arguments[_key];
                }
                return nativeSetInterval.apply(window, [
                    callback,
                    delay,
                    ...args,
                ]);
            };
            window.setInterval = intervalWrapper;
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function isValidCallback(n) {
            return n instanceof Function || "string" == typeof n;
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function getBoostMultiplier(t) {
            var e = parseFloat(t),
                i = nativeIsNaN(e) || !nativeIsFinite(e) ? 0.05 : e;
            return (i < 0.001 && (i = 0.001), i > 50 && (i = 50), i);
        }
        function isDelayMatched(a, e) {
            return shouldMatchAnyDelay(a) || e === getMatchDelay(a);
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function nativeIsNaN(N) {
            return (Number.isNaN || window.isNaN)(N);
        }
        function nativeIsFinite(i) {
            return (Number.isFinite || window.isFinite)(i);
        }
        function getMatchDelay(a) {
            var e = parseInt(a, 10);
            return nativeIsNaN(e) ? 1e3 : e;
        }
        function shouldMatchAnyDelay(n) {
            return "*" === n;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            adjustSetInterval.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function adjustSetTimeout(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function adjustSetTimeout(source, matchCallback, matchDelay, boost) {
            var nativeSetTimeout = window.setTimeout;
            var matchRegexp = toRegExp(matchCallback);
            var timeoutWrapper = function timeoutWrapper(callback, delay) {
                if (!isValidCallback(callback)) {
                    var message = `Scriptlet can't be applied because of invalid callback: '${String(callback)}'`;
                    logMessage(source, message);
                } else if (
                    matchRegexp.test(callback.toString()) &&
                    isDelayMatched(matchDelay, delay)
                ) {
                    delay *= getBoostMultiplier(boost);
                    hit(source);
                }
                for (
                    var _len = arguments.length,
                        args = new Array(_len > 2 ? _len - 2 : 0),
                        _key = 2;
                    _key < _len;
                    _key++
                ) {
                    args[_key - 2] = arguments[_key];
                }
                return nativeSetTimeout.apply(window, [
                    callback,
                    delay,
                    ...args,
                ]);
            };
            window.setTimeout = timeoutWrapper;
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function isValidCallback(n) {
            return n instanceof Function || "string" == typeof n;
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function getBoostMultiplier(t) {
            var e = parseFloat(t),
                i = nativeIsNaN(e) || !nativeIsFinite(e) ? 0.05 : e;
            return (i < 0.001 && (i = 0.001), i > 50 && (i = 50), i);
        }
        function isDelayMatched(a, e) {
            return shouldMatchAnyDelay(a) || e === getMatchDelay(a);
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function nativeIsNaN(N) {
            return (Number.isNaN || window.isNaN)(N);
        }
        function nativeIsFinite(i) {
            return (Number.isFinite || window.isFinite)(i);
        }
        function getMatchDelay(a) {
            var e = parseInt(a, 10);
            return nativeIsNaN(e) ? 1e3 : e;
        }
        function shouldMatchAnyDelay(n) {
            return "*" === n;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            adjustSetTimeout.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function callNoThrow(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function callNoThrow(source, functionName) {
            if (!functionName) {
                return;
            }
            var { base: base, prop: prop } = getPropertyInChain(
                window,
                functionName,
            );
            if (!base || !prop || typeof base[prop] !== "function") {
                var message = `${functionName} is not a function`;
                logMessage(source, message);
                return;
            }
            var objectWrapper = function objectWrapper() {
                var result;
                try {
                    result = Reflect.apply(...arguments);
                } catch (e) {
                    var _message = `Error calling ${functionName}: ${e.message}`;
                    logMessage(source, _message);
                }
                hit(source);
                return result;
            };
            var objectHandler = {
                apply: objectWrapper,
            };
            base[prop] = new Proxy(base[prop], objectHandler);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function getPropertyInChain(e, r) {
            var n = r.indexOf(".");
            if (-1 === n)
                return {
                    base: e,
                    prop: r,
                };
            var i = r.slice(0, n);
            if (null === e)
                return {
                    base: e,
                    prop: i,
                    chain: r,
                };
            var t = e[i];
            return (
                (r = r.slice(n + 1)),
                ((e instanceof Object || "object" == typeof e) &&
                    isEmptyObject(e)) ||
                null === t
                    ? {
                          base: e,
                          prop: i,
                          chain: r,
                      }
                    : void 0 !== t
                      ? getPropertyInChain(t, r)
                      : (Object.defineProperty(e, i, {
                            configurable: true,
                        }),
                        {
                            base: e,
                            prop: i,
                            chain: r,
                        })
            );
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function isEmptyObject(t) {
            return 0 === Object.keys(t).length && !t.prototype;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            callNoThrow.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function debugCurrentInlineScript(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function debugCurrentInlineScript(source, property, search) {
            var searchRegexp = toRegExp(search);
            var rid = randomId();
            var getCurrentScript = function getCurrentScript() {
                if ("currentScript" in document) {
                    return document.currentScript;
                }
                var scripts = document.getElementsByTagName("script");
                return scripts[scripts.length - 1];
            };
            var ourScript = getCurrentScript();
            var abort = function abort() {
                var scriptEl = getCurrentScript();
                if (!scriptEl) {
                    return;
                }
                var content = scriptEl.textContent;
                try {
                    var textContentGetter = Object.getOwnPropertyDescriptor(
                        Node.prototype,
                        "textContent",
                    ).get;
                    content = textContentGetter.call(scriptEl);
                } catch (e) {}
                if (
                    scriptEl instanceof HTMLScriptElement &&
                    content.length > 0 &&
                    scriptEl !== ourScript &&
                    searchRegexp.test(content)
                ) {
                    hit(source);
                    debugger;
                }
            };
            var _setChainPropAccess = function setChainPropAccess(
                owner,
                property,
            ) {
                var chainInfo = getPropertyInChain(owner, property);
                var { base: base } = chainInfo;
                var { prop: prop, chain: chain } = chainInfo;
                if (base instanceof Object === false && base === null) {
                    var props = property.split(".");
                    var propIndex = props.indexOf(prop);
                    var baseName = props[propIndex - 1];
                    var message = `The scriptlet had been executed before the ${baseName} was loaded.`;
                    logMessage(message, source.verbose);
                    return;
                }
                if (chain) {
                    var setter = function setter(a) {
                        base = a;
                        if (a instanceof Object) {
                            _setChainPropAccess(a, chain);
                        }
                    };
                    Object.defineProperty(owner, prop, {
                        get: function get() {
                            return base;
                        },
                        set: setter,
                    });
                    return;
                }
                var currentValue = base[prop];
                setPropertyAccess(base, prop, {
                    set: function set(value) {
                        abort();
                        currentValue = value;
                    },
                    get: function get() {
                        abort();
                        return currentValue;
                    },
                });
            };
            _setChainPropAccess(window, property);
            window.onerror = createOnErrorHandler(rid).bind();
        }
        function randomId() {
            return Math.random().toString(36).slice(2, 9);
        }
        function setPropertyAccess(e, r, t) {
            var c = Object.getOwnPropertyDescriptor(e, r);
            return (
                !(c && !c.configurable) &&
                (Object.defineProperty(e, r, t), true)
            );
        }
        function getPropertyInChain(e, r) {
            var n = r.indexOf(".");
            if (-1 === n)
                return {
                    base: e,
                    prop: r,
                };
            var i = r.slice(0, n);
            if (null === e)
                return {
                    base: e,
                    prop: i,
                    chain: r,
                };
            var t = e[i];
            return (
                (r = r.slice(n + 1)),
                ((e instanceof Object || "object" == typeof e) &&
                    isEmptyObject(e)) ||
                null === t
                    ? {
                          base: e,
                          prop: i,
                          chain: r,
                      }
                    : void 0 !== t
                      ? getPropertyInChain(t, r)
                      : (Object.defineProperty(e, i, {
                            configurable: true,
                        }),
                        {
                            base: e,
                            prop: i,
                            chain: r,
                        })
            );
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function createOnErrorHandler(r) {
            var n = window.onerror;
            return function (e) {
                if ("string" == typeof e && e.includes(r)) return true;
                if (n instanceof Function) {
                    for (
                        var t = arguments.length,
                            o = new Array(t > 1 ? t - 1 : 0),
                            i = 1;
                        i < t;
                        i++
                    )
                        o[i - 1] = arguments[i];
                    return n.apply(window, [e, ...o]);
                }
                return false;
            };
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function isEmptyObject(t) {
            return 0 === Object.keys(t).length && !t.prototype;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            debugCurrentInlineScript.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function debugOnPropertyRead(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function debugOnPropertyRead(source, property) {
            if (!property) {
                return;
            }
            var rid = randomId();
            var abort = function abort() {
                hit(source);
                debugger;
            };
            var _setChainPropAccess = function setChainPropAccess(
                owner,
                property,
            ) {
                var chainInfo = getPropertyInChain(owner, property);
                var { base: base } = chainInfo;
                var { prop: prop, chain: chain } = chainInfo;
                if (chain) {
                    var setter = function setter(a) {
                        base = a;
                        if (a instanceof Object) {
                            _setChainPropAccess(a, chain);
                        }
                    };
                    Object.defineProperty(owner, prop, {
                        get: function get() {
                            return base;
                        },
                        set: setter,
                    });
                    return;
                }
                setPropertyAccess(base, prop, {
                    get: abort,
                    set: noopFunc,
                });
            };
            _setChainPropAccess(window, property);
            window.onerror = createOnErrorHandler(rid).bind();
        }
        function randomId() {
            return Math.random().toString(36).slice(2, 9);
        }
        function setPropertyAccess(e, r, t) {
            var c = Object.getOwnPropertyDescriptor(e, r);
            return (
                !(c && !c.configurable) &&
                (Object.defineProperty(e, r, t), true)
            );
        }
        function getPropertyInChain(e, r) {
            var n = r.indexOf(".");
            if (-1 === n)
                return {
                    base: e,
                    prop: r,
                };
            var i = r.slice(0, n);
            if (null === e)
                return {
                    base: e,
                    prop: i,
                    chain: r,
                };
            var t = e[i];
            return (
                (r = r.slice(n + 1)),
                ((e instanceof Object || "object" == typeof e) &&
                    isEmptyObject(e)) ||
                null === t
                    ? {
                          base: e,
                          prop: i,
                          chain: r,
                      }
                    : void 0 !== t
                      ? getPropertyInChain(t, r)
                      : (Object.defineProperty(e, i, {
                            configurable: true,
                        }),
                        {
                            base: e,
                            prop: i,
                            chain: r,
                        })
            );
        }
        function createOnErrorHandler(r) {
            var n = window.onerror;
            return function (e) {
                if ("string" == typeof e && e.includes(r)) return true;
                if (n instanceof Function) {
                    for (
                        var t = arguments.length,
                            o = new Array(t > 1 ? t - 1 : 0),
                            i = 1;
                        i < t;
                        i++
                    )
                        o[i - 1] = arguments[i];
                    return n.apply(window, [e, ...o]);
                }
                return false;
            };
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function noopFunc() {}
        function isEmptyObject(t) {
            return 0 === Object.keys(t).length && !t.prototype;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            debugOnPropertyRead.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function debugOnPropertyWrite(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function debugOnPropertyWrite(source, property) {
            if (!property) {
                return;
            }
            var rid = randomId();
            var abort = function abort() {
                hit(source);
                debugger;
            };
            var _setChainPropAccess = function setChainPropAccess(
                owner,
                property,
            ) {
                var chainInfo = getPropertyInChain(owner, property);
                var { base: base } = chainInfo;
                var { prop: prop, chain: chain } = chainInfo;
                if (chain) {
                    var setter = function setter(a) {
                        base = a;
                        if (a instanceof Object) {
                            _setChainPropAccess(a, chain);
                        }
                    };
                    Object.defineProperty(owner, prop, {
                        get: function get() {
                            return base;
                        },
                        set: setter,
                    });
                    return;
                }
                setPropertyAccess(base, prop, {
                    set: abort,
                });
            };
            _setChainPropAccess(window, property);
            window.onerror = createOnErrorHandler(rid).bind();
        }
        function randomId() {
            return Math.random().toString(36).slice(2, 9);
        }
        function setPropertyAccess(e, r, t) {
            var c = Object.getOwnPropertyDescriptor(e, r);
            return (
                !(c && !c.configurable) &&
                (Object.defineProperty(e, r, t), true)
            );
        }
        function getPropertyInChain(e, r) {
            var n = r.indexOf(".");
            if (-1 === n)
                return {
                    base: e,
                    prop: r,
                };
            var i = r.slice(0, n);
            if (null === e)
                return {
                    base: e,
                    prop: i,
                    chain: r,
                };
            var t = e[i];
            return (
                (r = r.slice(n + 1)),
                ((e instanceof Object || "object" == typeof e) &&
                    isEmptyObject(e)) ||
                null === t
                    ? {
                          base: e,
                          prop: i,
                          chain: r,
                      }
                    : void 0 !== t
                      ? getPropertyInChain(t, r)
                      : (Object.defineProperty(e, i, {
                            configurable: true,
                        }),
                        {
                            base: e,
                            prop: i,
                            chain: r,
                        })
            );
        }
        function createOnErrorHandler(r) {
            var n = window.onerror;
            return function (e) {
                if ("string" == typeof e && e.includes(r)) return true;
                if (n instanceof Function) {
                    for (
                        var t = arguments.length,
                            o = new Array(t > 1 ? t - 1 : 0),
                            i = 1;
                        i < t;
                        i++
                    )
                        o[i - 1] = arguments[i];
                    return n.apply(window, [e, ...o]);
                }
                return false;
            };
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function isEmptyObject(t) {
            return 0 === Object.keys(t).length && !t.prototype;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            debugOnPropertyWrite.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function dirString(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function dirString(source, times) {
            var { dir: dir } = console;
            function dirWrapper(object) {
                if (typeof dir === "function") {
                    dir.call(this, object);
                }
                hit(source);
            }
            console.dir = dirWrapper;
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            dirString.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function disableNewtabLinks(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function disableNewtabLinks(source) {
            document.addEventListener("click", function (ev) {
                var { target: target } = ev;
                while (target !== null) {
                    if (
                        target.localName === "a" &&
                        target.hasAttribute("target")
                    ) {
                        ev.stopPropagation();
                        ev.preventDefault();
                        hit(source);
                        break;
                    }
                    target = target.parentNode;
                }
            });
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            disableNewtabLinks.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function evalDataPrune(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function evalDataPrune(
            source,
            propsToRemove,
            requiredInitialProps,
            stack,
        ) {
            var prunePaths = getPrunePath(propsToRemove);
            var requiredPaths = getPrunePath(requiredInitialProps);
            var nativeObjects = {
                nativeStringify: window.JSON.stringify,
            };
            var evalWrapper = function evalWrapper(target, thisArg, args) {
                var data = Reflect.apply(target, thisArg, args);
                if (typeof data === "object") {
                    data = jsonPruner(
                        source,
                        data,
                        prunePaths,
                        requiredPaths,
                        stack,
                        nativeObjects,
                    );
                }
                return data;
            };
            var evalHandler = {
                apply: evalWrapper,
            };
            window.eval = new Proxy(window.eval, evalHandler);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function matchStackTrace(e, t) {
            if (!e || "" === e) return true;
            var r = backupRegExpValues();
            if (shouldAbortInlineOrInjectedScript(e, t))
                return (
                    r.length && r[0] !== RegExp.$1 && restoreRegExpValues(r),
                    true
                );
            var n = toRegExp(e),
                a = t
                    .split("\n")
                    .slice(2)
                    .map(function (e) {
                        return e.trim();
                    })
                    .join("\n");
            return (
                r.length && r[0] !== RegExp.$1 && restoreRegExpValues(r),
                getNativeRegexpTest().call(n, a)
            );
        }
        function getWildcardPropertyInChain(r, e) {
            var a =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                i =
                    arguments.length > 3 && void 0 !== arguments[3]
                        ? arguments[3]
                        : [],
                t = arguments.length > 4 ? arguments[4] : void 0,
                o = e.indexOf(".");
            if (-1 === o) {
                if ("*" === e || "[]" === e) {
                    for (var n in r)
                        if (Object.prototype.hasOwnProperty.call(r, n))
                            if (void 0 !== t) {
                                var s = r[n];
                                "string" == typeof s && t instanceof RegExp
                                    ? t.test(s) &&
                                      i.push({
                                          base: r,
                                          prop: n,
                                      })
                                    : s === t &&
                                      i.push({
                                          base: r,
                                          prop: n,
                                      });
                            } else
                                i.push({
                                    base: r,
                                    prop: n,
                                });
                } else if (void 0 !== t) {
                    var p = r[e];
                    "string" == typeof p && t instanceof RegExp
                        ? t.test(p) &&
                          i.push({
                              base: r,
                              prop: e,
                          })
                        : r[e] === t &&
                          i.push({
                              base: r,
                              prop: e,
                          });
                } else
                    i.push({
                        base: r,
                        prop: e,
                    });
                return i;
            }
            var c = e.slice(0, o);
            if (
                ("[]" === c && Array.isArray(r)) ||
                ("*" === c && r instanceof Object) ||
                ("[-]" === c && Array.isArray(r)) ||
                ("{-}" === c && r instanceof Object)
            ) {
                var f = e.slice(o + 1),
                    y = Object.keys(r);
                if ("{-}" === c || "[-]" === c) {
                    var h = Array.isArray(r) ? "array" : "object";
                    return (
                        (("{-}" !== c || "object" !== h) &&
                            ("[-]" !== c || "array" !== h)) ||
                            y.forEach(function (e) {
                                var a = r[e];
                                isKeyInObject(a, f, t) &&
                                    i.push({
                                        base: r,
                                        prop: e,
                                    });
                            }),
                        i
                    );
                }
                y.forEach(function (e) {
                    getWildcardPropertyInChain(r[e], f, a, i, t);
                });
            }
            Array.isArray(r) &&
                r.forEach(function (r) {
                    void 0 !== r && getWildcardPropertyInChain(r, e, a, i, t);
                });
            var d = r[c];
            return (
                (e = e.slice(o + 1)),
                void 0 !== d && getWildcardPropertyInChain(d, e, a, i, t),
                i
            );
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function isPruningNeeded(n, t, r, e, a, i) {
            if (!t) return false;
            var o,
                { nativeStringify: u } = i,
                c = r.map(function (n) {
                    return n.path;
                }),
                f = e.map(function (n) {
                    return n.path;
                });
            if (0 === c.length && f.length > 0) {
                var g = u(t);
                if (toRegExp(f.join("")).test(g))
                    return (
                        logMessage(
                            n,
                            `${window.location.hostname}\n${u(t, null, 2)}\nStack trace:\n${new Error().stack}`,
                            true,
                        ),
                        t &&
                            "object" == typeof t &&
                            logMessage(n, t, true, false),
                        (o = false)
                    );
            }
            if (a && !matchStackTrace(a, new Error().stack || ""))
                return (o = false);
            for (
                var s,
                    l = [".*.", "*.", ".*", ".[].", "[].", ".[]"],
                    _loop = function _loop() {
                        var n = f[p],
                            r = n.split(".").pop(),
                            e = l.some(function (t) {
                                return n.includes(t);
                            }),
                            a = getWildcardPropertyInChain(t, n, e);
                        if (!a.length)
                            return {
                                v: (o = false),
                            };
                        o = !e;
                        for (var i = 0; i < a.length; i += 1) {
                            var u =
                                "string" == typeof r && void 0 !== a[i].base[r];
                            o = e ? u || o : u && o;
                        }
                    },
                    p = 0;
                p < f.length;
                p += 1
            )
                if ((s = _loop())) return s.v;
            return o;
        }
        function jsonPruner(e, r, n, a, t, i) {
            var { nativeStringify: o } = i;
            if (0 === n.length && 0 === a.length)
                return (
                    logMessage(
                        e,
                        `${window.location.hostname}\n${o(r, null, 2)}\nStack trace:\n${new Error().stack}`,
                        true,
                    ),
                    r && "object" == typeof r && logMessage(e, r, true, false),
                    r
                );
            try {
                if (!1 === isPruningNeeded(e, r, n, a, t, i)) return r;
                n.forEach(function (n) {
                    for (
                        var a = n.path,
                            t = n.value,
                            i = getWildcardPropertyInChain(r, a, !0, [], t),
                            o = i.length - 1;
                        o >= 0;
                        o -= 1
                    ) {
                        var s = i[o];
                        if (void 0 !== s && s.base)
                            if ((hit(e), Array.isArray(s.base)))
                                try {
                                    var l = Number(s.prop);
                                    if (Number.isNaN(l)) continue;
                                    s.base.splice(l, 1);
                                } catch (e) {
                                    console.error(
                                        "Error while deleting array element",
                                        e,
                                    );
                                }
                            else delete s.base[s.prop];
                    }
                });
            } catch (r) {
                logMessage(e, r);
            }
            return r;
        }
        function getPrunePath(t) {
            var r = ".[=].";
            if ("string" == typeof t && void 0 !== t && "" !== t) {
                var e = (function (t) {
                    for (
                        var e = [], n = "", i = 0, a = false, s = false;
                        i < t.length;

                    ) {
                        var u = t[i];
                        if (a)
                            ((n += u),
                                "\\" === u
                                    ? (s = !s)
                                    : ("/" !== u || s || (a = false),
                                      (s = false)),
                                (i += 1));
                        else {
                            if (
                                " " === u ||
                                "\n" === u ||
                                "\t" === u ||
                                "\r" === u ||
                                "\f" === u ||
                                "\v" === u
                            ) {
                                for (; i < t.length && /\s/.test(t[i]); )
                                    i += 1;
                                "" !== n && (e.push(n), (n = ""));
                                continue;
                            }
                            if (t.startsWith(r, i)) {
                                if (((n += r), "/" === t[(i += 5)])) {
                                    ((a = true),
                                        (s = false),
                                        (n += "/"),
                                        (i += 1));
                                    continue;
                                }
                                continue;
                            }
                            ((n += u), (i += 1));
                        }
                    }
                    return ("" !== n && e.push(n), e);
                })(t);
                return e.map(function (t) {
                    var e = t.split(r),
                        n = e[0],
                        i = e[1];
                    return void 0 !== i
                        ? ("true" === i
                              ? (i = true)
                              : "false" === i
                                ? (i = false)
                                : i.startsWith("/")
                                  ? (i = toRegExp(i))
                                  : "string" == typeof i &&
                                    /^\d+$/.test(i) &&
                                    (i = parseFloat(i)),
                          {
                              path: n,
                              value: i,
                          })
                        : {
                              path: n,
                          };
                });
            }
            return [];
        }
        function getNativeRegexpTest() {
            var t = Object.getOwnPropertyDescriptor(RegExp.prototype, "test"),
                e = null == t ? void 0 : t.value;
            if (t && "function" == typeof t.value) return e;
            throw new Error("RegExp.prototype.test is not a function");
        }
        function shouldAbortInlineOrInjectedScript(t, i) {
            var r = "inlineScript",
                n = "injectedScript",
                isInlineScript = function isInlineScript(t) {
                    return t.includes(r);
                },
                isInjectedScript = function isInjectedScript(t) {
                    return t.includes(n);
                };
            if (!isInlineScript(t) && !isInjectedScript(t)) return false;
            var e = window.location.href,
                s = e.indexOf("#");
            -1 !== s && (e = e.slice(0, s));
            var c = i
                .split("\n")
                .slice(2)
                .map(function (t) {
                    return t.trim();
                })
                .map(function (t) {
                    var i,
                        s = /(.*?@)?(\S+)(:\d+)(:\d+)\)?$/.exec(t);
                    if (s) {
                        var c,
                            l,
                            a = s[2],
                            u = s[3],
                            o = s[4];
                        if (
                            (null !== (c = a) &&
                                void 0 !== c &&
                                c.startsWith("(") &&
                                (a = a.slice(1)),
                            null !== (l = a) &&
                                void 0 !== l &&
                                l.startsWith("<anonymous>"))
                        ) {
                            var d;
                            a = n;
                            var f =
                                void 0 !== s[1]
                                    ? s[1].slice(0, -1)
                                    : t.slice(0, s.index).trim();
                            (null !== (d = f) &&
                                void 0 !== d &&
                                d.startsWith("at") &&
                                (f = f.slice(2).trim()),
                                (i = `${f} ${a}${u}${o}`.trim()));
                        } else
                            i =
                                a === e
                                    ? `${r}${u}${o}`.trim()
                                    : `${a}${u}${o}`.trim();
                    } else i = t;
                    return i;
                });
            if (c)
                for (var l = 0; l < c.length; l += 1) {
                    if (
                        isInlineScript(t) &&
                        c[l].startsWith(r) &&
                        c[l].match(toRegExp(t))
                    )
                        return true;
                    if (
                        isInjectedScript(t) &&
                        c[l].startsWith(n) &&
                        c[l].match(toRegExp(t))
                    )
                        return true;
                }
            return false;
        }
        function backupRegExpValues() {
            try {
                for (var r = [], e = 1; e < 10; e += 1) {
                    var a = `$${e}`;
                    if (!RegExp[a]) break;
                    r.push(RegExp[a]);
                }
                return r;
            } catch (r) {
                return [];
            }
        }
        function restoreRegExpValues(e) {
            if (e.length)
                try {
                    var r = "";
                    r =
                        1 === e.length
                            ? `(${e[0]})`
                            : e.reduce(function (e, r, t) {
                                  return 1 === t
                                      ? `(${e}),(${r})`
                                      : `${e},(${r})`;
                              });
                    var t = new RegExp(r);
                    e.toString().replace(t, "");
                } catch (e) {
                    var n = `Failed to restore RegExp values: ${e}`;
                    console.log(n);
                }
        }
        function isKeyInObject(t, r, e) {
            var n = r.split("."),
                _check2 = function _check(t, r) {
                    if (null == t) return false;
                    if (0 === r.length)
                        return (
                            void 0 === e ||
                            ("string" == typeof t && e instanceof RegExp
                                ? e.test(t)
                                : t === e)
                        );
                    var n = r[0],
                        i = r.slice(1);
                    if ("*" === n || "[]" === n) {
                        if (Array.isArray(t))
                            return t.some(function (t) {
                                return _check2(t, i);
                            });
                        if ("object" == typeof t && null !== t)
                            return Object.keys(t).some(function (r) {
                                return _check2(t[r], i);
                            });
                    }
                    return (
                        !!Object.prototype.hasOwnProperty.call(t, n) &&
                        _check2(t[n], i)
                    );
                };
            return _check2(t, n);
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            evalDataPrune.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function forceWindowClose(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function forceWindowClose(source) {
            var path =
                arguments.length > 1 && arguments[1] !== undefined
                    ? arguments[1]
                    : "";
            if (typeof window.close !== "function") {
                var message =
                    "window.close() is not a function so 'close-window' scriptlet is unavailable";
                logMessage(source, message);
                return;
            }
            var closeImmediately = function closeImmediately() {
                try {
                    hit(source);
                    window.close();
                } catch (e) {
                    logMessage(source, e);
                }
            };
            var closeByExtension = function closeByExtension() {
                var extCall = function extCall() {
                    dispatchEvent(new Event("adguard:scriptlet-close-window"));
                };
                window.addEventListener(
                    "adguard:subscribed-to-close-window",
                    extCall,
                    {
                        once: true,
                    },
                );
                setTimeout(function () {
                    window.removeEventListener(
                        "adguard:subscribed-to-close-window",
                        extCall,
                        {
                            once: true,
                        },
                    );
                }, 5e3);
            };
            var shouldClose = function shouldClose() {
                if (path === "") {
                    return true;
                }
                var pathRegexp = toRegExp(path);
                var currentPath = `${window.location.pathname}${window.location.search}`;
                return pathRegexp.test(currentPath);
            };
            if (shouldClose()) {
                closeImmediately();
                if (navigator.userAgent.includes("Chrome")) {
                    closeByExtension();
                }
            }
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            forceWindowClose.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function hideInShadowDom(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function hideInShadowDom(source, selector, baseSelector) {
            if (!Element.prototype.attachShadow) {
                return;
            }
            var hideElement = function hideElement(targetElement) {
                var DISPLAY_NONE_CSS = "display:none!important;";
                targetElement.style.cssText = DISPLAY_NONE_CSS;
            };
            var hideHandler = function hideHandler() {
                var hostElements = !baseSelector
                    ? findHostElements(document.documentElement)
                    : document.querySelectorAll(baseSelector);
                var _loop = function _loop() {
                    var isHidden = false;
                    var { targets: targets, innerHosts: innerHosts } =
                        pierceShadowDom(selector, hostElements);
                    targets.forEach(function (targetEl) {
                        hideElement(targetEl);
                        isHidden = true;
                    });
                    if (isHidden) {
                        hit(source);
                    }
                    hostElements = innerHosts;
                };
                while (hostElements.length !== 0) {
                    _loop();
                }
            };
            hideHandler();
            observeDOMChanges(hideHandler, true);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function observeDOMChanges(t) {
            var e =
                    arguments.length > 1 &&
                    void 0 !== arguments[1] &&
                    arguments[1],
                n =
                    arguments.length > 2 && void 0 !== arguments[2]
                        ? arguments[2]
                        : [],
                i = new MutationObserver(
                    throttle(function () {
                        (disconnect(), t(), connect());
                    }, 20),
                ),
                connect = function connect() {
                    n.length > 0
                        ? i.observe(document.documentElement, {
                              childList: true,
                              subtree: true,
                              attributes: e,
                              attributeFilter: n,
                          })
                        : i.observe(document.documentElement, {
                              childList: true,
                              subtree: true,
                              attributes: e,
                          });
                },
                disconnect = function disconnect() {
                    i.disconnect();
                };
            connect();
        }
        function findHostElements(o) {
            var n = [];
            o &&
                o.querySelectorAll("*").forEach(function (o) {
                    o.shadowRoot && n.push(o);
                });
            return n;
        }
        function pierceShadowDom(e, t) {
            var c = [],
                l = [];
            t.forEach(function (t) {
                var o = t.querySelectorAll(e);
                c = c.concat([].slice.call(o));
                var r = t.shadowRoot,
                    a = r.querySelectorAll(e);
                ((c = c.concat([].slice.call(a))), l.push(findHostElements(r)));
            });
            var o = flatten(l);
            return {
                targets: c,
                innerHosts: o,
            };
        }
        function flatten(r) {
            var n = [];
            r.forEach(function (r) {
                return n.push(r);
            });
            for (var t = []; n.length; ) {
                var u = n.pop();
                Array.isArray(u)
                    ? u.forEach(function (r) {
                          return n.push(r);
                      })
                    : t.push(u);
            }
            return t.reverse();
        }
        function throttle(n, t) {
            var r,
                e = false,
                _wrapper2 = function _wrapper() {
                    for (
                        var o = arguments.length, u = new Array(o), f = 0;
                        f < o;
                        f++
                    )
                        u[f] = arguments[f];
                    e
                        ? (r = u)
                        : (n(...u),
                          (e = true),
                          setTimeout(function () {
                              ((e = false), r && (_wrapper2(...r), (r = null)));
                          }, t));
                };
            return _wrapper2;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            hideInShadowDom.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function hrefSanitizer(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function hrefSanitizer(source, selector) {
            var attribute =
                arguments.length > 2 && arguments[2] !== undefined
                    ? arguments[2]
                    : "text";
            var transform =
                arguments.length > 3 && arguments[3] !== undefined
                    ? arguments[3]
                    : "";
            if (!selector) {
                logMessage(source, "Selector is required.");
                return;
            }
            var BASE64_DECODE_TRANSFORM_MARKER = "base64decode";
            var REMOVE_HASH_TRANSFORM_MARKER = "removeHash";
            var REMOVE_PARAM_TRANSFORM_MARKER = "removeParam";
            var MARKER_SEPARATOR = ":";
            var COMMA = ",";
            var regexpNotValidAtStart =
                /^[^!-~\xAA\xB5\xBA\xC0-\xD6\xD8-\xF6\xF8-\u02C1\u02C6-\u02D1\u02E0-\u02E4\u02EC\u02EE\u0370-\u0374\u0376\u0377\u037A-\u037D\u037F\u0386\u0388-\u038A\u038C\u038E-\u03A1\u03A3-\u03F5\u03F7-\u0481\u048A-\u052F\u0531-\u0556\u0559\u0560-\u0588\u05D0-\u05EA\u05EF-\u05F2\u0620-\u064A\u066E\u066F\u0671-\u06D3\u06D5\u06E5\u06E6\u06EE\u06EF\u06FA-\u06FC\u06FF\u0710\u0712-\u072F\u074D-\u07A5\u07B1\u07CA-\u07EA\u07F4\u07F5\u07FA\u0800-\u0815\u081A\u0824\u0828\u0840-\u0858\u0860-\u086A\u0870-\u0887\u0889-\u088E\u08A0-\u08C9\u0904-\u0939\u093D\u0950\u0958-\u0961\u0971-\u0980\u0985-\u098C\u098F\u0990\u0993-\u09A8\u09AA-\u09B0\u09B2\u09B6-\u09B9\u09BD\u09CE\u09DC\u09DD\u09DF-\u09E1\u09F0\u09F1\u09FC\u0A05-\u0A0A\u0A0F\u0A10\u0A13-\u0A28\u0A2A-\u0A30\u0A32\u0A33\u0A35\u0A36\u0A38\u0A39\u0A59-\u0A5C\u0A5E\u0A72-\u0A74\u0A85-\u0A8D\u0A8F-\u0A91\u0A93-\u0AA8\u0AAA-\u0AB0\u0AB2\u0AB3\u0AB5-\u0AB9\u0ABD\u0AD0\u0AE0\u0AE1\u0AF9\u0B05-\u0B0C\u0B0F\u0B10\u0B13-\u0B28\u0B2A-\u0B30\u0B32\u0B33\u0B35-\u0B39\u0B3D\u0B5C\u0B5D\u0B5F-\u0B61\u0B71\u0B83\u0B85-\u0B8A\u0B8E-\u0B90\u0B92-\u0B95\u0B99\u0B9A\u0B9C\u0B9E\u0B9F\u0BA3\u0BA4\u0BA8-\u0BAA\u0BAE-\u0BB9\u0BD0\u0C05-\u0C0C\u0C0E-\u0C10\u0C12-\u0C28\u0C2A-\u0C39\u0C3D\u0C58-\u0C5A\u0C5D\u0C60\u0C61\u0C80\u0C85-\u0C8C\u0C8E-\u0C90\u0C92-\u0CA8\u0CAA-\u0CB3\u0CB5-\u0CB9\u0CBD\u0CDD\u0CDE\u0CE0\u0CE1\u0CF1\u0CF2\u0D04-\u0D0C\u0D0E-\u0D10\u0D12-\u0D3A\u0D3D\u0D4E\u0D54-\u0D56\u0D5F-\u0D61\u0D7A-\u0D7F\u0D85-\u0D96\u0D9A-\u0DB1\u0DB3-\u0DBB\u0DBD\u0DC0-\u0DC6\u0E01-\u0E30\u0E32\u0E33\u0E40-\u0E46\u0E81\u0E82\u0E84\u0E86-\u0E8A\u0E8C-\u0EA3\u0EA5\u0EA7-\u0EB0\u0EB2\u0EB3\u0EBD\u0EC0-\u0EC4\u0EC6\u0EDC-\u0EDF\u0F00\u0F40-\u0F47\u0F49-\u0F6C\u0F88-\u0F8C\u1000-\u102A\u103F\u1050-\u1055\u105A-\u105D\u1061\u1065\u1066\u106E-\u1070\u1075-\u1081\u108E\u10A0-\u10C5\u10C7\u10CD\u10D0-\u10FA\u10FC-\u1248\u124A-\u124D\u1250-\u1256\u1258\u125A-\u125D\u1260-\u1288\u128A-\u128D\u1290-\u12B0\u12B2-\u12B5\u12B8-\u12BE\u12C0\u12C2-\u12C5\u12C8-\u12D6\u12D8-\u1310\u1312-\u1315\u1318-\u135A\u1380-\u138F\u13A0-\u13F5\u13F8-\u13FD\u1401-\u166C\u166F-\u167F\u1681-\u169A\u16A0-\u16EA\u16F1-\u16F8\u1700-\u1711\u171F-\u1731\u1740-\u1751\u1760-\u176C\u176E-\u1770\u1780-\u17B3\u17D7\u17DC\u1820-\u1878\u1880-\u1884\u1887-\u18A8\u18AA\u18B0-\u18F5\u1900-\u191E\u1950-\u196D\u1970-\u1974\u1980-\u19AB\u19B0-\u19C9\u1A00-\u1A16\u1A20-\u1A54\u1AA7\u1B05-\u1B33\u1B45-\u1B4C\u1B83-\u1BA0\u1BAE\u1BAF\u1BBA-\u1BE5\u1C00-\u1C23\u1C4D-\u1C4F\u1C5A-\u1C7D\u1C80-\u1C8A\u1C90-\u1CBA\u1CBD-\u1CBF\u1CE9-\u1CEC\u1CEE-\u1CF3\u1CF5\u1CF6\u1CFA\u1D00-\u1DBF\u1E00-\u1F15\u1F18-\u1F1D\u1F20-\u1F45\u1F48-\u1F4D\u1F50-\u1F57\u1F59\u1F5B\u1F5D\u1F5F-\u1F7D\u1F80-\u1FB4\u1FB6-\u1FBC\u1FBE\u1FC2-\u1FC4\u1FC6-\u1FCC\u1FD0-\u1FD3\u1FD6-\u1FDB\u1FE0-\u1FEC\u1FF2-\u1FF4\u1FF6-\u1FFC\u2071\u207F\u2090-\u209C\u2102\u2107\u210A-\u2113\u2115\u2119-\u211D\u2124\u2126\u2128\u212A-\u212D\u212F-\u2139\u213C-\u213F\u2145-\u2149\u214E\u2183\u2184\u2C00-\u2CE4\u2CEB-\u2CEE\u2CF2\u2CF3\u2D00-\u2D25\u2D27\u2D2D\u2D30-\u2D67\u2D6F\u2D80-\u2D96\u2DA0-\u2DA6\u2DA8-\u2DAE\u2DB0-\u2DB6\u2DB8-\u2DBE\u2DC0-\u2DC6\u2DC8-\u2DCE\u2DD0-\u2DD6\u2DD8-\u2DDE\u2E2F\u3005\u3006\u3031-\u3035\u303B\u303C\u3041-\u3096\u309D-\u309F\u30A1-\u30FA\u30FC-\u30FF\u3105-\u312F\u3131-\u318E\u31A0-\u31BF\u31F0-\u31FF\u3400-\u4DBF\u4E00-\uA48C\uA4D0-\uA4FD\uA500-\uA60C\uA610-\uA61F\uA62A\uA62B\uA640-\uA66E\uA67F-\uA69D\uA6A0-\uA6E5\uA717-\uA71F\uA722-\uA788\uA78B-\uA7CD\uA7D0\uA7D1\uA7D3\uA7D5-\uA7DC\uA7F2-\uA801\uA803-\uA805\uA807-\uA80A\uA80C-\uA822\uA840-\uA873\uA882-\uA8B3\uA8F2-\uA8F7\uA8FB\uA8FD\uA8FE\uA90A-\uA925\uA930-\uA946\uA960-\uA97C\uA984-\uA9B2\uA9CF\uA9E0-\uA9E4\uA9E6-\uA9EF\uA9FA-\uA9FE\uAA00-\uAA28\uAA40-\uAA42\uAA44-\uAA4B\uAA60-\uAA76\uAA7A\uAA7E-\uAAAF\uAAB1\uAAB5\uAAB6\uAAB9-\uAABD\uAAC0\uAAC2\uAADB-\uAADD\uAAE0-\uAAEA\uAAF2-\uAAF4\uAB01-\uAB06\uAB09-\uAB0E\uAB11-\uAB16\uAB20-\uAB26\uAB28-\uAB2E\uAB30-\uAB5A\uAB5C-\uAB69\uAB70-\uABE2\uAC00-\uD7A3\uD7B0-\uD7C6\uD7CB-\uD7FB\uF900-\uFA6D\uFA70-\uFAD9\uFB00-\uFB06\uFB13-\uFB17\uFB1D\uFB1F-\uFB28\uFB2A-\uFB36\uFB38-\uFB3C\uFB3E\uFB40\uFB41\uFB43\uFB44\uFB46-\uFBB1\uFBD3-\uFD3D\uFD50-\uFD8F\uFD92-\uFDC7\uFDF0-\uFDFB\uFE70-\uFE74\uFE76-\uFEFC\uFF21-\uFF3A\uFF41-\uFF5A\uFF66-\uFFBE\uFFC2-\uFFC7\uFFCA-\uFFCF\uFFD2-\uFFD7\uFFDA-\uFFDC\u{10000}-\u{1000B}\u{1000D}-\u{10026}\u{10028}-\u{1003A}\u{1003C}\u{1003D}\u{1003F}-\u{1004D}\u{10050}-\u{1005D}\u{10080}-\u{100FA}\u{10280}-\u{1029C}\u{102A0}-\u{102D0}\u{10300}-\u{1031F}\u{1032D}-\u{10340}\u{10342}-\u{10349}\u{10350}-\u{10375}\u{10380}-\u{1039D}\u{103A0}-\u{103C3}\u{103C8}-\u{103CF}\u{10400}-\u{1049D}\u{104B0}-\u{104D3}\u{104D8}-\u{104FB}\u{10500}-\u{10527}\u{10530}-\u{10563}\u{10570}-\u{1057A}\u{1057C}-\u{1058A}\u{1058C}-\u{10592}\u{10594}\u{10595}\u{10597}-\u{105A1}\u{105A3}-\u{105B1}\u{105B3}-\u{105B9}\u{105BB}\u{105BC}\u{105C0}-\u{105F3}\u{10600}-\u{10736}\u{10740}-\u{10755}\u{10760}-\u{10767}\u{10780}-\u{10785}\u{10787}-\u{107B0}\u{107B2}-\u{107BA}\u{10800}-\u{10805}\u{10808}\u{1080A}-\u{10835}\u{10837}\u{10838}\u{1083C}\u{1083F}-\u{10855}\u{10860}-\u{10876}\u{10880}-\u{1089E}\u{108E0}-\u{108F2}\u{108F4}\u{108F5}\u{10900}-\u{10915}\u{10920}-\u{10939}\u{10980}-\u{109B7}\u{109BE}\u{109BF}\u{10A00}\u{10A10}-\u{10A13}\u{10A15}-\u{10A17}\u{10A19}-\u{10A35}\u{10A60}-\u{10A7C}\u{10A80}-\u{10A9C}\u{10AC0}-\u{10AC7}\u{10AC9}-\u{10AE4}\u{10B00}-\u{10B35}\u{10B40}-\u{10B55}\u{10B60}-\u{10B72}\u{10B80}-\u{10B91}\u{10C00}-\u{10C48}\u{10C80}-\u{10CB2}\u{10CC0}-\u{10CF2}\u{10D00}-\u{10D23}\u{10D4A}-\u{10D65}\u{10D6F}-\u{10D85}\u{10E80}-\u{10EA9}\u{10EB0}\u{10EB1}\u{10EC2}-\u{10EC4}\u{10F00}-\u{10F1C}\u{10F27}\u{10F30}-\u{10F45}\u{10F70}-\u{10F81}\u{10FB0}-\u{10FC4}\u{10FE0}-\u{10FF6}\u{11003}-\u{11037}\u{11071}\u{11072}\u{11075}\u{11083}-\u{110AF}\u{110D0}-\u{110E8}\u{11103}-\u{11126}\u{11144}\u{11147}\u{11150}-\u{11172}\u{11176}\u{11183}-\u{111B2}\u{111C1}-\u{111C4}\u{111DA}\u{111DC}\u{11200}-\u{11211}\u{11213}-\u{1122B}\u{1123F}\u{11240}\u{11280}-\u{11286}\u{11288}\u{1128A}-\u{1128D}\u{1128F}-\u{1129D}\u{1129F}-\u{112A8}\u{112B0}-\u{112DE}\u{11305}-\u{1130C}\u{1130F}\u{11310}\u{11313}-\u{11328}\u{1132A}-\u{11330}\u{11332}\u{11333}\u{11335}-\u{11339}\u{1133D}\u{11350}\u{1135D}-\u{11361}\u{11380}-\u{11389}\u{1138B}\u{1138E}\u{11390}-\u{113B5}\u{113B7}\u{113D1}\u{113D3}\u{11400}-\u{11434}\u{11447}-\u{1144A}\u{1145F}-\u{11461}\u{11480}-\u{114AF}\u{114C4}\u{114C5}\u{114C7}\u{11580}-\u{115AE}\u{115D8}-\u{115DB}\u{11600}-\u{1162F}\u{11644}\u{11680}-\u{116AA}\u{116B8}\u{11700}-\u{1171A}\u{11740}-\u{11746}\u{11800}-\u{1182B}\u{118A0}-\u{118DF}\u{118FF}-\u{11906}\u{11909}\u{1190C}-\u{11913}\u{11915}\u{11916}\u{11918}-\u{1192F}\u{1193F}\u{11941}\u{119A0}-\u{119A7}\u{119AA}-\u{119D0}\u{119E1}\u{119E3}\u{11A00}\u{11A0B}-\u{11A32}\u{11A3A}\u{11A50}\u{11A5C}-\u{11A89}\u{11A9D}\u{11AB0}-\u{11AF8}\u{11BC0}-\u{11BE0}\u{11C00}-\u{11C08}\u{11C0A}-\u{11C2E}\u{11C40}\u{11C72}-\u{11C8F}\u{11D00}-\u{11D06}\u{11D08}\u{11D09}\u{11D0B}-\u{11D30}\u{11D46}\u{11D60}-\u{11D65}\u{11D67}\u{11D68}\u{11D6A}-\u{11D89}\u{11D98}\u{11EE0}-\u{11EF2}\u{11F02}\u{11F04}-\u{11F10}\u{11F12}-\u{11F33}\u{11FB0}\u{12000}-\u{12399}\u{12480}-\u{12543}\u{12F90}-\u{12FF0}\u{13000}-\u{1342F}\u{13441}-\u{13446}\u{13460}-\u{143FA}\u{14400}-\u{14646}\u{16100}-\u{1611D}\u{16800}-\u{16A38}\u{16A40}-\u{16A5E}\u{16A70}-\u{16ABE}\u{16AD0}-\u{16AED}\u{16B00}-\u{16B2F}\u{16B40}-\u{16B43}\u{16B63}-\u{16B77}\u{16B7D}-\u{16B8F}\u{16D40}-\u{16D6C}\u{16E40}-\u{16E7F}\u{16F00}-\u{16F4A}\u{16F50}\u{16F93}-\u{16F9F}\u{16FE0}\u{16FE1}\u{16FE3}\u{17000}-\u{187F7}\u{18800}-\u{18CD5}\u{18CFF}-\u{18D08}\u{1AFF0}-\u{1AFF3}\u{1AFF5}-\u{1AFFB}\u{1AFFD}\u{1AFFE}\u{1B000}-\u{1B122}\u{1B132}\u{1B150}-\u{1B152}\u{1B155}\u{1B164}-\u{1B167}\u{1B170}-\u{1B2FB}\u{1BC00}-\u{1BC6A}\u{1BC70}-\u{1BC7C}\u{1BC80}-\u{1BC88}\u{1BC90}-\u{1BC99}\u{1D400}-\u{1D454}\u{1D456}-\u{1D49C}\u{1D49E}\u{1D49F}\u{1D4A2}\u{1D4A5}\u{1D4A6}\u{1D4A9}-\u{1D4AC}\u{1D4AE}-\u{1D4B9}\u{1D4BB}\u{1D4BD}-\u{1D4C3}\u{1D4C5}-\u{1D505}\u{1D507}-\u{1D50A}\u{1D50D}-\u{1D514}\u{1D516}-\u{1D51C}\u{1D51E}-\u{1D539}\u{1D53B}-\u{1D53E}\u{1D540}-\u{1D544}\u{1D546}\u{1D54A}-\u{1D550}\u{1D552}-\u{1D6A5}\u{1D6A8}-\u{1D6C0}\u{1D6C2}-\u{1D6DA}\u{1D6DC}-\u{1D6FA}\u{1D6FC}-\u{1D714}\u{1D716}-\u{1D734}\u{1D736}-\u{1D74E}\u{1D750}-\u{1D76E}\u{1D770}-\u{1D788}\u{1D78A}-\u{1D7A8}\u{1D7AA}-\u{1D7C2}\u{1D7C4}-\u{1D7CB}\u{1DF00}-\u{1DF1E}\u{1DF25}-\u{1DF2A}\u{1E030}-\u{1E06D}\u{1E100}-\u{1E12C}\u{1E137}-\u{1E13D}\u{1E14E}\u{1E290}-\u{1E2AD}\u{1E2C0}-\u{1E2EB}\u{1E4D0}-\u{1E4EB}\u{1E5D0}-\u{1E5ED}\u{1E5F0}\u{1E7E0}-\u{1E7E6}\u{1E7E8}-\u{1E7EB}\u{1E7ED}\u{1E7EE}\u{1E7F0}-\u{1E7FE}\u{1E800}-\u{1E8C4}\u{1E900}-\u{1E943}\u{1E94B}\u{1EE00}-\u{1EE03}\u{1EE05}-\u{1EE1F}\u{1EE21}\u{1EE22}\u{1EE24}\u{1EE27}\u{1EE29}-\u{1EE32}\u{1EE34}-\u{1EE37}\u{1EE39}\u{1EE3B}\u{1EE42}\u{1EE47}\u{1EE49}\u{1EE4B}\u{1EE4D}-\u{1EE4F}\u{1EE51}\u{1EE52}\u{1EE54}\u{1EE57}\u{1EE59}\u{1EE5B}\u{1EE5D}\u{1EE5F}\u{1EE61}\u{1EE62}\u{1EE64}\u{1EE67}-\u{1EE6A}\u{1EE6C}-\u{1EE72}\u{1EE74}-\u{1EE77}\u{1EE79}-\u{1EE7C}\u{1EE7E}\u{1EE80}-\u{1EE89}\u{1EE8B}-\u{1EE9B}\u{1EEA1}-\u{1EEA3}\u{1EEA5}-\u{1EEA9}\u{1EEAB}-\u{1EEBB}\u{20000}-\u{2A6DF}\u{2A700}-\u{2B739}\u{2B740}-\u{2B81D}\u{2B820}-\u{2CEA1}\u{2CEB0}-\u{2EBE0}\u{2EBF0}-\u{2EE5D}\u{2F800}-\u{2FA1D}\u{30000}-\u{3134A}\u{31350}-\u{323AF}]+/u;
            var regexpNotValidAtEnd =
                /[^!-~\xAA\xB5\xBA\xC0-\xD6\xD8-\xF6\xF8-\u02C1\u02C6-\u02D1\u02E0-\u02E4\u02EC\u02EE\u0370-\u0374\u0376\u0377\u037A-\u037D\u037F\u0386\u0388-\u038A\u038C\u038E-\u03A1\u03A3-\u03F5\u03F7-\u0481\u048A-\u052F\u0531-\u0556\u0559\u0560-\u0588\u05D0-\u05EA\u05EF-\u05F2\u0620-\u064A\u066E\u066F\u0671-\u06D3\u06D5\u06E5\u06E6\u06EE\u06EF\u06FA-\u06FC\u06FF\u0710\u0712-\u072F\u074D-\u07A5\u07B1\u07CA-\u07EA\u07F4\u07F5\u07FA\u0800-\u0815\u081A\u0824\u0828\u0840-\u0858\u0860-\u086A\u0870-\u0887\u0889-\u088E\u08A0-\u08C9\u0904-\u0939\u093D\u0950\u0958-\u0961\u0971-\u0980\u0985-\u098C\u098F\u0990\u0993-\u09A8\u09AA-\u09B0\u09B2\u09B6-\u09B9\u09BD\u09CE\u09DC\u09DD\u09DF-\u09E1\u09F0\u09F1\u09FC\u0A05-\u0A0A\u0A0F\u0A10\u0A13-\u0A28\u0A2A-\u0A30\u0A32\u0A33\u0A35\u0A36\u0A38\u0A39\u0A59-\u0A5C\u0A5E\u0A72-\u0A74\u0A85-\u0A8D\u0A8F-\u0A91\u0A93-\u0AA8\u0AAA-\u0AB0\u0AB2\u0AB3\u0AB5-\u0AB9\u0ABD\u0AD0\u0AE0\u0AE1\u0AF9\u0B05-\u0B0C\u0B0F\u0B10\u0B13-\u0B28\u0B2A-\u0B30\u0B32\u0B33\u0B35-\u0B39\u0B3D\u0B5C\u0B5D\u0B5F-\u0B61\u0B71\u0B83\u0B85-\u0B8A\u0B8E-\u0B90\u0B92-\u0B95\u0B99\u0B9A\u0B9C\u0B9E\u0B9F\u0BA3\u0BA4\u0BA8-\u0BAA\u0BAE-\u0BB9\u0BD0\u0C05-\u0C0C\u0C0E-\u0C10\u0C12-\u0C28\u0C2A-\u0C39\u0C3D\u0C58-\u0C5A\u0C5D\u0C60\u0C61\u0C80\u0C85-\u0C8C\u0C8E-\u0C90\u0C92-\u0CA8\u0CAA-\u0CB3\u0CB5-\u0CB9\u0CBD\u0CDD\u0CDE\u0CE0\u0CE1\u0CF1\u0CF2\u0D04-\u0D0C\u0D0E-\u0D10\u0D12-\u0D3A\u0D3D\u0D4E\u0D54-\u0D56\u0D5F-\u0D61\u0D7A-\u0D7F\u0D85-\u0D96\u0D9A-\u0DB1\u0DB3-\u0DBB\u0DBD\u0DC0-\u0DC6\u0E01-\u0E30\u0E32\u0E33\u0E40-\u0E46\u0E81\u0E82\u0E84\u0E86-\u0E8A\u0E8C-\u0EA3\u0EA5\u0EA7-\u0EB0\u0EB2\u0EB3\u0EBD\u0EC0-\u0EC4\u0EC6\u0EDC-\u0EDF\u0F00\u0F40-\u0F47\u0F49-\u0F6C\u0F88-\u0F8C\u1000-\u102A\u103F\u1050-\u1055\u105A-\u105D\u1061\u1065\u1066\u106E-\u1070\u1075-\u1081\u108E\u10A0-\u10C5\u10C7\u10CD\u10D0-\u10FA\u10FC-\u1248\u124A-\u124D\u1250-\u1256\u1258\u125A-\u125D\u1260-\u1288\u128A-\u128D\u1290-\u12B0\u12B2-\u12B5\u12B8-\u12BE\u12C0\u12C2-\u12C5\u12C8-\u12D6\u12D8-\u1310\u1312-\u1315\u1318-\u135A\u1380-\u138F\u13A0-\u13F5\u13F8-\u13FD\u1401-\u166C\u166F-\u167F\u1681-\u169A\u16A0-\u16EA\u16F1-\u16F8\u1700-\u1711\u171F-\u1731\u1740-\u1751\u1760-\u176C\u176E-\u1770\u1780-\u17B3\u17D7\u17DC\u1820-\u1878\u1880-\u1884\u1887-\u18A8\u18AA\u18B0-\u18F5\u1900-\u191E\u1950-\u196D\u1970-\u1974\u1980-\u19AB\u19B0-\u19C9\u1A00-\u1A16\u1A20-\u1A54\u1AA7\u1B05-\u1B33\u1B45-\u1B4C\u1B83-\u1BA0\u1BAE\u1BAF\u1BBA-\u1BE5\u1C00-\u1C23\u1C4D-\u1C4F\u1C5A-\u1C7D\u1C80-\u1C8A\u1C90-\u1CBA\u1CBD-\u1CBF\u1CE9-\u1CEC\u1CEE-\u1CF3\u1CF5\u1CF6\u1CFA\u1D00-\u1DBF\u1E00-\u1F15\u1F18-\u1F1D\u1F20-\u1F45\u1F48-\u1F4D\u1F50-\u1F57\u1F59\u1F5B\u1F5D\u1F5F-\u1F7D\u1F80-\u1FB4\u1FB6-\u1FBC\u1FBE\u1FC2-\u1FC4\u1FC6-\u1FCC\u1FD0-\u1FD3\u1FD6-\u1FDB\u1FE0-\u1FEC\u1FF2-\u1FF4\u1FF6-\u1FFC\u2071\u207F\u2090-\u209C\u2102\u2107\u210A-\u2113\u2115\u2119-\u211D\u2124\u2126\u2128\u212A-\u212D\u212F-\u2139\u213C-\u213F\u2145-\u2149\u214E\u2183\u2184\u2C00-\u2CE4\u2CEB-\u2CEE\u2CF2\u2CF3\u2D00-\u2D25\u2D27\u2D2D\u2D30-\u2D67\u2D6F\u2D80-\u2D96\u2DA0-\u2DA6\u2DA8-\u2DAE\u2DB0-\u2DB6\u2DB8-\u2DBE\u2DC0-\u2DC6\u2DC8-\u2DCE\u2DD0-\u2DD6\u2DD8-\u2DDE\u2E2F\u3005\u3006\u3031-\u3035\u303B\u303C\u3041-\u3096\u309D-\u309F\u30A1-\u30FA\u30FC-\u30FF\u3105-\u312F\u3131-\u318E\u31A0-\u31BF\u31F0-\u31FF\u3400-\u4DBF\u4E00-\uA48C\uA4D0-\uA4FD\uA500-\uA60C\uA610-\uA61F\uA62A\uA62B\uA640-\uA66E\uA67F-\uA69D\uA6A0-\uA6E5\uA717-\uA71F\uA722-\uA788\uA78B-\uA7CD\uA7D0\uA7D1\uA7D3\uA7D5-\uA7DC\uA7F2-\uA801\uA803-\uA805\uA807-\uA80A\uA80C-\uA822\uA840-\uA873\uA882-\uA8B3\uA8F2-\uA8F7\uA8FB\uA8FD\uA8FE\uA90A-\uA925\uA930-\uA946\uA960-\uA97C\uA984-\uA9B2\uA9CF\uA9E0-\uA9E4\uA9E6-\uA9EF\uA9FA-\uA9FE\uAA00-\uAA28\uAA40-\uAA42\uAA44-\uAA4B\uAA60-\uAA76\uAA7A\uAA7E-\uAAAF\uAAB1\uAAB5\uAAB6\uAAB9-\uAABD\uAAC0\uAAC2\uAADB-\uAADD\uAAE0-\uAAEA\uAAF2-\uAAF4\uAB01-\uAB06\uAB09-\uAB0E\uAB11-\uAB16\uAB20-\uAB26\uAB28-\uAB2E\uAB30-\uAB5A\uAB5C-\uAB69\uAB70-\uABE2\uAC00-\uD7A3\uD7B0-\uD7C6\uD7CB-\uD7FB\uF900-\uFA6D\uFA70-\uFAD9\uFB00-\uFB06\uFB13-\uFB17\uFB1D\uFB1F-\uFB28\uFB2A-\uFB36\uFB38-\uFB3C\uFB3E\uFB40\uFB41\uFB43\uFB44\uFB46-\uFBB1\uFBD3-\uFD3D\uFD50-\uFD8F\uFD92-\uFDC7\uFDF0-\uFDFB\uFE70-\uFE74\uFE76-\uFEFC\uFF21-\uFF3A\uFF41-\uFF5A\uFF66-\uFFBE\uFFC2-\uFFC7\uFFCA-\uFFCF\uFFD2-\uFFD7\uFFDA-\uFFDC\u{10000}-\u{1000B}\u{1000D}-\u{10026}\u{10028}-\u{1003A}\u{1003C}\u{1003D}\u{1003F}-\u{1004D}\u{10050}-\u{1005D}\u{10080}-\u{100FA}\u{10280}-\u{1029C}\u{102A0}-\u{102D0}\u{10300}-\u{1031F}\u{1032D}-\u{10340}\u{10342}-\u{10349}\u{10350}-\u{10375}\u{10380}-\u{1039D}\u{103A0}-\u{103C3}\u{103C8}-\u{103CF}\u{10400}-\u{1049D}\u{104B0}-\u{104D3}\u{104D8}-\u{104FB}\u{10500}-\u{10527}\u{10530}-\u{10563}\u{10570}-\u{1057A}\u{1057C}-\u{1058A}\u{1058C}-\u{10592}\u{10594}\u{10595}\u{10597}-\u{105A1}\u{105A3}-\u{105B1}\u{105B3}-\u{105B9}\u{105BB}\u{105BC}\u{105C0}-\u{105F3}\u{10600}-\u{10736}\u{10740}-\u{10755}\u{10760}-\u{10767}\u{10780}-\u{10785}\u{10787}-\u{107B0}\u{107B2}-\u{107BA}\u{10800}-\u{10805}\u{10808}\u{1080A}-\u{10835}\u{10837}\u{10838}\u{1083C}\u{1083F}-\u{10855}\u{10860}-\u{10876}\u{10880}-\u{1089E}\u{108E0}-\u{108F2}\u{108F4}\u{108F5}\u{10900}-\u{10915}\u{10920}-\u{10939}\u{10980}-\u{109B7}\u{109BE}\u{109BF}\u{10A00}\u{10A10}-\u{10A13}\u{10A15}-\u{10A17}\u{10A19}-\u{10A35}\u{10A60}-\u{10A7C}\u{10A80}-\u{10A9C}\u{10AC0}-\u{10AC7}\u{10AC9}-\u{10AE4}\u{10B00}-\u{10B35}\u{10B40}-\u{10B55}\u{10B60}-\u{10B72}\u{10B80}-\u{10B91}\u{10C00}-\u{10C48}\u{10C80}-\u{10CB2}\u{10CC0}-\u{10CF2}\u{10D00}-\u{10D23}\u{10D4A}-\u{10D65}\u{10D6F}-\u{10D85}\u{10E80}-\u{10EA9}\u{10EB0}\u{10EB1}\u{10EC2}-\u{10EC4}\u{10F00}-\u{10F1C}\u{10F27}\u{10F30}-\u{10F45}\u{10F70}-\u{10F81}\u{10FB0}-\u{10FC4}\u{10FE0}-\u{10FF6}\u{11003}-\u{11037}\u{11071}\u{11072}\u{11075}\u{11083}-\u{110AF}\u{110D0}-\u{110E8}\u{11103}-\u{11126}\u{11144}\u{11147}\u{11150}-\u{11172}\u{11176}\u{11183}-\u{111B2}\u{111C1}-\u{111C4}\u{111DA}\u{111DC}\u{11200}-\u{11211}\u{11213}-\u{1122B}\u{1123F}\u{11240}\u{11280}-\u{11286}\u{11288}\u{1128A}-\u{1128D}\u{1128F}-\u{1129D}\u{1129F}-\u{112A8}\u{112B0}-\u{112DE}\u{11305}-\u{1130C}\u{1130F}\u{11310}\u{11313}-\u{11328}\u{1132A}-\u{11330}\u{11332}\u{11333}\u{11335}-\u{11339}\u{1133D}\u{11350}\u{1135D}-\u{11361}\u{11380}-\u{11389}\u{1138B}\u{1138E}\u{11390}-\u{113B5}\u{113B7}\u{113D1}\u{113D3}\u{11400}-\u{11434}\u{11447}-\u{1144A}\u{1145F}-\u{11461}\u{11480}-\u{114AF}\u{114C4}\u{114C5}\u{114C7}\u{11580}-\u{115AE}\u{115D8}-\u{115DB}\u{11600}-\u{1162F}\u{11644}\u{11680}-\u{116AA}\u{116B8}\u{11700}-\u{1171A}\u{11740}-\u{11746}\u{11800}-\u{1182B}\u{118A0}-\u{118DF}\u{118FF}-\u{11906}\u{11909}\u{1190C}-\u{11913}\u{11915}\u{11916}\u{11918}-\u{1192F}\u{1193F}\u{11941}\u{119A0}-\u{119A7}\u{119AA}-\u{119D0}\u{119E1}\u{119E3}\u{11A00}\u{11A0B}-\u{11A32}\u{11A3A}\u{11A50}\u{11A5C}-\u{11A89}\u{11A9D}\u{11AB0}-\u{11AF8}\u{11BC0}-\u{11BE0}\u{11C00}-\u{11C08}\u{11C0A}-\u{11C2E}\u{11C40}\u{11C72}-\u{11C8F}\u{11D00}-\u{11D06}\u{11D08}\u{11D09}\u{11D0B}-\u{11D30}\u{11D46}\u{11D60}-\u{11D65}\u{11D67}\u{11D68}\u{11D6A}-\u{11D89}\u{11D98}\u{11EE0}-\u{11EF2}\u{11F02}\u{11F04}-\u{11F10}\u{11F12}-\u{11F33}\u{11FB0}\u{12000}-\u{12399}\u{12480}-\u{12543}\u{12F90}-\u{12FF0}\u{13000}-\u{1342F}\u{13441}-\u{13446}\u{13460}-\u{143FA}\u{14400}-\u{14646}\u{16100}-\u{1611D}\u{16800}-\u{16A38}\u{16A40}-\u{16A5E}\u{16A70}-\u{16ABE}\u{16AD0}-\u{16AED}\u{16B00}-\u{16B2F}\u{16B40}-\u{16B43}\u{16B63}-\u{16B77}\u{16B7D}-\u{16B8F}\u{16D40}-\u{16D6C}\u{16E40}-\u{16E7F}\u{16F00}-\u{16F4A}\u{16F50}\u{16F93}-\u{16F9F}\u{16FE0}\u{16FE1}\u{16FE3}\u{17000}-\u{187F7}\u{18800}-\u{18CD5}\u{18CFF}-\u{18D08}\u{1AFF0}-\u{1AFF3}\u{1AFF5}-\u{1AFFB}\u{1AFFD}\u{1AFFE}\u{1B000}-\u{1B122}\u{1B132}\u{1B150}-\u{1B152}\u{1B155}\u{1B164}-\u{1B167}\u{1B170}-\u{1B2FB}\u{1BC00}-\u{1BC6A}\u{1BC70}-\u{1BC7C}\u{1BC80}-\u{1BC88}\u{1BC90}-\u{1BC99}\u{1D400}-\u{1D454}\u{1D456}-\u{1D49C}\u{1D49E}\u{1D49F}\u{1D4A2}\u{1D4A5}\u{1D4A6}\u{1D4A9}-\u{1D4AC}\u{1D4AE}-\u{1D4B9}\u{1D4BB}\u{1D4BD}-\u{1D4C3}\u{1D4C5}-\u{1D505}\u{1D507}-\u{1D50A}\u{1D50D}-\u{1D514}\u{1D516}-\u{1D51C}\u{1D51E}-\u{1D539}\u{1D53B}-\u{1D53E}\u{1D540}-\u{1D544}\u{1D546}\u{1D54A}-\u{1D550}\u{1D552}-\u{1D6A5}\u{1D6A8}-\u{1D6C0}\u{1D6C2}-\u{1D6DA}\u{1D6DC}-\u{1D6FA}\u{1D6FC}-\u{1D714}\u{1D716}-\u{1D734}\u{1D736}-\u{1D74E}\u{1D750}-\u{1D76E}\u{1D770}-\u{1D788}\u{1D78A}-\u{1D7A8}\u{1D7AA}-\u{1D7C2}\u{1D7C4}-\u{1D7CB}\u{1DF00}-\u{1DF1E}\u{1DF25}-\u{1DF2A}\u{1E030}-\u{1E06D}\u{1E100}-\u{1E12C}\u{1E137}-\u{1E13D}\u{1E14E}\u{1E290}-\u{1E2AD}\u{1E2C0}-\u{1E2EB}\u{1E4D0}-\u{1E4EB}\u{1E5D0}-\u{1E5ED}\u{1E5F0}\u{1E7E0}-\u{1E7E6}\u{1E7E8}-\u{1E7EB}\u{1E7ED}\u{1E7EE}\u{1E7F0}-\u{1E7FE}\u{1E800}-\u{1E8C4}\u{1E900}-\u{1E943}\u{1E94B}\u{1EE00}-\u{1EE03}\u{1EE05}-\u{1EE1F}\u{1EE21}\u{1EE22}\u{1EE24}\u{1EE27}\u{1EE29}-\u{1EE32}\u{1EE34}-\u{1EE37}\u{1EE39}\u{1EE3B}\u{1EE42}\u{1EE47}\u{1EE49}\u{1EE4B}\u{1EE4D}-\u{1EE4F}\u{1EE51}\u{1EE52}\u{1EE54}\u{1EE57}\u{1EE59}\u{1EE5B}\u{1EE5D}\u{1EE5F}\u{1EE61}\u{1EE62}\u{1EE64}\u{1EE67}-\u{1EE6A}\u{1EE6C}-\u{1EE72}\u{1EE74}-\u{1EE77}\u{1EE79}-\u{1EE7C}\u{1EE7E}\u{1EE80}-\u{1EE89}\u{1EE8B}-\u{1EE9B}\u{1EEA1}-\u{1EEA3}\u{1EEA5}-\u{1EEA9}\u{1EEAB}-\u{1EEBB}\u{20000}-\u{2A6DF}\u{2A700}-\u{2B739}\u{2B740}-\u{2B81D}\u{2B820}-\u{2CEA1}\u{2CEB0}-\u{2EBE0}\u{2EBF0}-\u{2EE5D}\u{2F800}-\u{2FA1D}\u{30000}-\u{3134A}\u{31350}-\u{323AF}]+$/u;
            var extractNewHref = function extractNewHref(anchor, attr) {
                if (attr === "text") {
                    if (!anchor.textContent) {
                        return "";
                    }
                    return anchor.textContent
                        .replace(regexpNotValidAtStart, "")
                        .replace(regexpNotValidAtEnd, "");
                }
                if (attr.startsWith("?")) {
                    try {
                        var url = new URL(anchor.href, document.location.href);
                        return url.searchParams.get(attr.slice(1)) || "";
                    } catch (ex) {
                        logMessage(
                            source,
                            `Cannot retrieve the parameter '${attr.slice(1)}' from the URL '${anchor.href}`,
                        );
                        return "";
                    }
                }
                if (attr.startsWith("[") && attr.endsWith("]")) {
                    return anchor.getAttribute(attr.slice(1, -1)) || "";
                }
                return "";
            };
            var isValidURL = function isValidURL(url) {
                try {
                    new URL(url);
                    return true;
                } catch (_unused) {
                    return false;
                }
            };
            var getValidURL = function getValidURL(text) {
                if (!text) {
                    return null;
                }
                try {
                    var { href: href, protocol: protocol } = new URL(
                        text,
                        document.location.href,
                    );
                    if (protocol !== "http:" && protocol !== "https:") {
                        logMessage(
                            source,
                            `Protocol not allowed: "${protocol}", from URL: "${href}"`,
                        );
                        return null;
                    }
                    return href;
                } catch (_unused2) {
                    return null;
                }
            };
            var isSanitizableAnchor = function isSanitizableAnchor(element) {
                return (
                    element.nodeName.toLowerCase() === "a" &&
                    element.hasAttribute("href")
                );
            };
            var _extractURLFromObject = function extractURLFromObject(obj) {
                for (var key in obj) {
                    if (!Object.prototype.hasOwnProperty.call(obj, key)) {
                        continue;
                    }
                    var value = obj[key];
                    if (typeof value === "string" && isValidURL(value)) {
                        return value;
                    }
                    if (typeof value === "object" && value !== null) {
                        var result = _extractURLFromObject(value);
                        if (result) {
                            return result;
                        }
                    }
                }
                return null;
            };
            var isStringifiedObject = function isStringifiedObject(content) {
                return content.startsWith("{") && content.endsWith("}");
            };
            var decodeBase64SeveralTimes = function decodeBase64SeveralTimes(
                text,
                times,
            ) {
                var result = text;
                for (var i = 0; i < times; i += 1) {
                    try {
                        result = atob(result);
                    } catch (e) {
                        if (result === text) {
                            return "";
                        }
                    }
                }
                if (isValidURL(result)) {
                    return result;
                }
                if (isStringifiedObject(result)) {
                    try {
                        var parsedResult = JSON.parse(result);
                        return _extractURLFromObject(parsedResult);
                    } catch (ex) {
                        return "";
                    }
                }
                logMessage(source, `Failed to decode base64 string: ${text}`);
                return "";
            };
            var SEARCH_QUERY_MARKER = "?";
            var SEARCH_PARAMS_MARKER = "&";
            var HASHBANG_MARKER = "#!";
            var ANCHOR_MARKER = "#";
            var DECODE_ATTEMPTS_NUMBER = 10;
            var decodeSearchString = function decodeSearchString(search) {
                var searchString = search.replace(SEARCH_QUERY_MARKER, "");
                var decodedParam;
                var validEncodedParam;
                if (searchString.includes(SEARCH_PARAMS_MARKER)) {
                    var searchParamsArray =
                        searchString.split(SEARCH_PARAMS_MARKER);
                    searchParamsArray.forEach(function (param) {
                        decodedParam = decodeBase64SeveralTimes(
                            param,
                            DECODE_ATTEMPTS_NUMBER,
                        );
                        if (decodedParam && decodedParam.length > 0) {
                            validEncodedParam = decodedParam;
                        }
                    });
                    return validEncodedParam;
                }
                return decodeBase64SeveralTimes(
                    searchString,
                    DECODE_ATTEMPTS_NUMBER,
                );
            };
            var decodeHashString = function decodeHashString(hash) {
                var validEncodedHash = "";
                if (hash.includes(HASHBANG_MARKER)) {
                    validEncodedHash = hash.replace(HASHBANG_MARKER, "");
                } else if (hash.includes(ANCHOR_MARKER)) {
                    validEncodedHash = hash.replace(ANCHOR_MARKER, "");
                }
                return validEncodedHash
                    ? decodeBase64SeveralTimes(
                          validEncodedHash,
                          DECODE_ATTEMPTS_NUMBER,
                      )
                    : "";
            };
            var removeHash = function removeHash(url) {
                var urlObj = new URL(url, window.location.origin);
                if (!urlObj.hash) {
                    return "";
                }
                urlObj.hash = "";
                return urlObj.toString();
            };
            var removeParam = function removeParam(url, transformValue) {
                var urlObj = new URL(url, window.location.origin);
                var paramNamesToRemoveStr =
                    transformValue.split(MARKER_SEPARATOR)[1];
                if (!paramNamesToRemoveStr) {
                    urlObj.search = "";
                    return urlObj.toString();
                }
                var initSearchParamsLength =
                    urlObj.searchParams.toString().length;
                var removeParams = paramNamesToRemoveStr.split(COMMA);
                removeParams.forEach(function (param) {
                    if (urlObj.searchParams.has(param)) {
                        urlObj.searchParams.delete(param);
                    }
                });
                if (
                    initSearchParamsLength ===
                    urlObj.searchParams.toString().length
                ) {
                    return "";
                }
                return urlObj.toString();
            };
            var decodeBase64URL = function decodeBase64URL(url) {
                var { search: search, hash: hash } = new URL(
                    url,
                    document.location.href,
                );
                if (search.length > 0) {
                    return decodeSearchString(search);
                }
                if (hash.length > 0) {
                    return decodeHashString(hash);
                }
                logMessage(source, `Failed to execute base64 from URL: ${url}`);
                return null;
            };
            var base64Decode = function base64Decode(href) {
                if (isValidURL(href)) {
                    return decodeBase64URL(href) || "";
                }
                return (
                    decodeBase64SeveralTimes(href, DECODE_ATTEMPTS_NUMBER) || ""
                );
            };
            var sanitize = function sanitize(elementSelector) {
                var elements;
                try {
                    elements = document.querySelectorAll(elementSelector);
                } catch (e) {
                    logMessage(source, `Invalid selector "${elementSelector}"`);
                    return;
                }
                elements.forEach(function (elem) {
                    try {
                        if (!isSanitizableAnchor(elem)) {
                            logMessage(
                                source,
                                `${elem} is not a valid element to sanitize`,
                            );
                            return;
                        }
                        var newHref = extractNewHref(elem, attribute);
                        if (transform) {
                            switch (true) {
                                case transform ===
                                    BASE64_DECODE_TRANSFORM_MARKER:
                                    newHref = base64Decode(newHref);
                                    break;
                                case transform === REMOVE_HASH_TRANSFORM_MARKER:
                                    newHref = removeHash(newHref);
                                    break;
                                case transform.startsWith(
                                    REMOVE_PARAM_TRANSFORM_MARKER,
                                ): {
                                    newHref = removeParam(newHref, transform);
                                    break;
                                }
                                default:
                                    logMessage(
                                        source,
                                        `Invalid transform option: "${transform}"`,
                                    );
                                    return;
                            }
                        }
                        var newValidHref = getValidURL(newHref);
                        if (!newValidHref) {
                            logMessage(source, `Invalid URL: ${newHref}`);
                            return;
                        }
                        var oldHref = elem.href;
                        elem.setAttribute("href", newValidHref);
                        if (newValidHref !== oldHref) {
                            logMessage(
                                source,
                                `Sanitized "${oldHref}" to "${newValidHref}".`,
                            );
                        }
                    } catch (ex) {
                        logMessage(source, `Failed to sanitize ${elem}.`);
                    }
                });
                hit(source);
            };
            var run = function run() {
                sanitize(selector);
                observeDOMChanges(function () {
                    return sanitize(selector);
                }, true);
            };
            if (document.readyState === "loading") {
                window.addEventListener("DOMContentLoaded", run, {
                    once: true,
                });
            } else {
                run();
            }
        }
        function observeDOMChanges(t) {
            var e =
                    arguments.length > 1 &&
                    void 0 !== arguments[1] &&
                    arguments[1],
                n =
                    arguments.length > 2 && void 0 !== arguments[2]
                        ? arguments[2]
                        : [],
                i = new MutationObserver(
                    throttle(function () {
                        (disconnect(), t(), connect());
                    }, 20),
                ),
                connect = function connect() {
                    n.length > 0
                        ? i.observe(document.documentElement, {
                              childList: true,
                              subtree: true,
                              attributes: e,
                              attributeFilter: n,
                          })
                        : i.observe(document.documentElement, {
                              childList: true,
                              subtree: true,
                              attributes: e,
                          });
                },
                disconnect = function disconnect() {
                    i.disconnect();
                };
            connect();
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function throttle(n, t) {
            var r,
                e = false,
                _wrapper3 = function _wrapper() {
                    for (
                        var o = arguments.length, u = new Array(o), f = 0;
                        f < o;
                        f++
                    )
                        u[f] = arguments[f];
                    e
                        ? (r = u)
                        : (n(...u),
                          (e = true),
                          setTimeout(function () {
                              ((e = false), r && (_wrapper3(...r), (r = null)));
                          }, t));
                };
            return _wrapper3;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            hrefSanitizer.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function injectCssInShadowDom(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function injectCssInShadowDom(source, cssRule) {
            var hostSelector =
                arguments.length > 2 && arguments[2] !== undefined
                    ? arguments[2]
                    : "";
            var cssInjectionMethod =
                arguments.length > 3 && arguments[3] !== undefined
                    ? arguments[3]
                    : "adoptedStyleSheets";
            if (
                !Element.prototype.attachShadow ||
                typeof Proxy === "undefined" ||
                typeof Reflect === "undefined"
            ) {
                return;
            }
            if (
                cssInjectionMethod !== "adoptedStyleSheets" &&
                cssInjectionMethod !== "styleTag"
            ) {
                logMessage(
                    source,
                    `Unknown cssInjectionMethod: ${cssInjectionMethod}`,
                );
                return;
            }
            if (cssRule.match(/(url|image-set)\(.*\)/i)) {
                logMessage(
                    source,
                    '"url()" function is not allowed for css rules',
                );
                return;
            }
            var injectStyleTag = function injectStyleTag(shadowRoot) {
                try {
                    var styleTag = document.createElement("style");
                    styleTag.innerText = cssRule;
                    shadowRoot.appendChild(styleTag);
                    hit(source);
                } catch (error) {
                    logMessage(
                        source,
                        `Unable to inject style tag due to: \n'${error.message}'`,
                    );
                }
            };
            var injectAdoptedStyleSheets = function injectAdoptedStyleSheets(
                shadowRoot,
            ) {
                try {
                    var stylesheet = new CSSStyleSheet();
                    try {
                        stylesheet.insertRule(cssRule);
                    } catch (e) {
                        logMessage(
                            source,
                            `Unable to apply the rule '${cssRule}' due to: \n'${e.message}'`,
                        );
                        return;
                    }
                    shadowRoot.adoptedStyleSheets = [
                        ...shadowRoot.adoptedStyleSheets,
                        stylesheet,
                    ];
                    hit(source);
                } catch (error) {
                    logMessage(
                        source,
                        `Unable to inject adopted style sheet due to: \n'${error.message}'`,
                    );
                    injectStyleTag(shadowRoot);
                }
            };
            var callback = function callback(shadowRoot) {
                if (cssInjectionMethod === "adoptedStyleSheets") {
                    injectAdoptedStyleSheets(shadowRoot);
                } else if (cssInjectionMethod === "styleTag") {
                    injectStyleTag(shadowRoot);
                }
            };
            hijackAttachShadow(window, hostSelector, callback);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function hijackAttachShadow(t, a, e) {
            var o = {
                apply: function apply(t, o, c) {
                    var h = Reflect.apply(t, o, c);
                    return (o && o.matches(a || "*") && e(h), h);
                },
            };
            t.Element.prototype.attachShadow = new Proxy(
                t.Element.prototype.attachShadow,
                o,
            );
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            injectCssInShadowDom.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function jsonPrune(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function jsonPrune(source, propsToRemove, requiredInitialProps) {
            var stack =
                arguments.length > 3 && arguments[3] !== undefined
                    ? arguments[3]
                    : "";
            var prunePaths = getPrunePath(propsToRemove);
            var requiredPaths = getPrunePath(requiredInitialProps);
            var nativeObjects = {
                nativeStringify: window.JSON.stringify,
            };
            var nativeJSONParse = JSON.parse;
            var jsonParseWrapper = function jsonParseWrapper() {
                for (
                    var _len = arguments.length,
                        args = new Array(_len),
                        _key = 0;
                    _key < _len;
                    _key++
                ) {
                    args[_key] = arguments[_key];
                }
                var root = nativeJSONParse.apply(JSON, args);
                return jsonPruner(
                    source,
                    root,
                    prunePaths,
                    requiredPaths,
                    stack,
                    nativeObjects,
                );
            };
            jsonParseWrapper.toString =
                nativeJSONParse.toString.bind(nativeJSONParse);
            JSON.parse = jsonParseWrapper;
            var nativeResponseJson = Response.prototype.json;
            var responseJsonWrapper = function responseJsonWrapper() {
                var promise = nativeResponseJson.apply(this);
                return promise.then(function (obj) {
                    return jsonPruner(
                        source,
                        obj,
                        prunePaths,
                        requiredPaths,
                        stack,
                        nativeObjects,
                    );
                });
            };
            if (typeof Response === "undefined") {
                return;
            }
            Response.prototype.json = responseJsonWrapper;
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function matchStackTrace(e, t) {
            if (!e || "" === e) return true;
            var r = backupRegExpValues();
            if (shouldAbortInlineOrInjectedScript(e, t))
                return (
                    r.length && r[0] !== RegExp.$1 && restoreRegExpValues(r),
                    true
                );
            var n = toRegExp(e),
                a = t
                    .split("\n")
                    .slice(2)
                    .map(function (e) {
                        return e.trim();
                    })
                    .join("\n");
            return (
                r.length && r[0] !== RegExp.$1 && restoreRegExpValues(r),
                getNativeRegexpTest().call(n, a)
            );
        }
        function getWildcardPropertyInChain(r, e) {
            var a =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                i =
                    arguments.length > 3 && void 0 !== arguments[3]
                        ? arguments[3]
                        : [],
                t = arguments.length > 4 ? arguments[4] : void 0,
                o = e.indexOf(".");
            if (-1 === o) {
                if ("*" === e || "[]" === e) {
                    for (var n in r)
                        if (Object.prototype.hasOwnProperty.call(r, n))
                            if (void 0 !== t) {
                                var s = r[n];
                                "string" == typeof s && t instanceof RegExp
                                    ? t.test(s) &&
                                      i.push({
                                          base: r,
                                          prop: n,
                                      })
                                    : s === t &&
                                      i.push({
                                          base: r,
                                          prop: n,
                                      });
                            } else
                                i.push({
                                    base: r,
                                    prop: n,
                                });
                } else if (void 0 !== t) {
                    var p = r[e];
                    "string" == typeof p && t instanceof RegExp
                        ? t.test(p) &&
                          i.push({
                              base: r,
                              prop: e,
                          })
                        : r[e] === t &&
                          i.push({
                              base: r,
                              prop: e,
                          });
                } else
                    i.push({
                        base: r,
                        prop: e,
                    });
                return i;
            }
            var c = e.slice(0, o);
            if (
                ("[]" === c && Array.isArray(r)) ||
                ("*" === c && r instanceof Object) ||
                ("[-]" === c && Array.isArray(r)) ||
                ("{-}" === c && r instanceof Object)
            ) {
                var f = e.slice(o + 1),
                    y = Object.keys(r);
                if ("{-}" === c || "[-]" === c) {
                    var h = Array.isArray(r) ? "array" : "object";
                    return (
                        (("{-}" !== c || "object" !== h) &&
                            ("[-]" !== c || "array" !== h)) ||
                            y.forEach(function (e) {
                                var a = r[e];
                                isKeyInObject(a, f, t) &&
                                    i.push({
                                        base: r,
                                        prop: e,
                                    });
                            }),
                        i
                    );
                }
                y.forEach(function (e) {
                    getWildcardPropertyInChain(r[e], f, a, i, t);
                });
            }
            Array.isArray(r) &&
                r.forEach(function (r) {
                    void 0 !== r && getWildcardPropertyInChain(r, e, a, i, t);
                });
            var d = r[c];
            return (
                (e = e.slice(o + 1)),
                void 0 !== d && getWildcardPropertyInChain(d, e, a, i, t),
                i
            );
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function isPruningNeeded(n, t, r, e, a, i) {
            if (!t) return false;
            var o,
                { nativeStringify: u } = i,
                c = r.map(function (n) {
                    return n.path;
                }),
                f = e.map(function (n) {
                    return n.path;
                });
            if (0 === c.length && f.length > 0) {
                var g = u(t);
                if (toRegExp(f.join("")).test(g))
                    return (
                        logMessage(
                            n,
                            `${window.location.hostname}\n${u(t, null, 2)}\nStack trace:\n${new Error().stack}`,
                            true,
                        ),
                        t &&
                            "object" == typeof t &&
                            logMessage(n, t, true, false),
                        (o = false)
                    );
            }
            if (a && !matchStackTrace(a, new Error().stack || ""))
                return (o = false);
            for (
                var s,
                    l = [".*.", "*.", ".*", ".[].", "[].", ".[]"],
                    _loop = function _loop() {
                        var n = f[p],
                            r = n.split(".").pop(),
                            e = l.some(function (t) {
                                return n.includes(t);
                            }),
                            a = getWildcardPropertyInChain(t, n, e);
                        if (!a.length)
                            return {
                                v: (o = false),
                            };
                        o = !e;
                        for (var i = 0; i < a.length; i += 1) {
                            var u =
                                "string" == typeof r && void 0 !== a[i].base[r];
                            o = e ? u || o : u && o;
                        }
                    },
                    p = 0;
                p < f.length;
                p += 1
            )
                if ((s = _loop())) return s.v;
            return o;
        }
        function jsonPruner(e, r, n, a, t, i) {
            var { nativeStringify: o } = i;
            if (0 === n.length && 0 === a.length)
                return (
                    logMessage(
                        e,
                        `${window.location.hostname}\n${o(r, null, 2)}\nStack trace:\n${new Error().stack}`,
                        true,
                    ),
                    r && "object" == typeof r && logMessage(e, r, true, false),
                    r
                );
            try {
                if (!1 === isPruningNeeded(e, r, n, a, t, i)) return r;
                n.forEach(function (n) {
                    for (
                        var a = n.path,
                            t = n.value,
                            i = getWildcardPropertyInChain(r, a, !0, [], t),
                            o = i.length - 1;
                        o >= 0;
                        o -= 1
                    ) {
                        var s = i[o];
                        if (void 0 !== s && s.base)
                            if ((hit(e), Array.isArray(s.base)))
                                try {
                                    var l = Number(s.prop);
                                    if (Number.isNaN(l)) continue;
                                    s.base.splice(l, 1);
                                } catch (e) {
                                    console.error(
                                        "Error while deleting array element",
                                        e,
                                    );
                                }
                            else delete s.base[s.prop];
                    }
                });
            } catch (r) {
                logMessage(e, r);
            }
            return r;
        }
        function getPrunePath(t) {
            var r = ".[=].";
            if ("string" == typeof t && void 0 !== t && "" !== t) {
                var e = (function (t) {
                    for (
                        var e = [], n = "", i = 0, a = false, s = false;
                        i < t.length;

                    ) {
                        var u = t[i];
                        if (a)
                            ((n += u),
                                "\\" === u
                                    ? (s = !s)
                                    : ("/" !== u || s || (a = false),
                                      (s = false)),
                                (i += 1));
                        else {
                            if (
                                " " === u ||
                                "\n" === u ||
                                "\t" === u ||
                                "\r" === u ||
                                "\f" === u ||
                                "\v" === u
                            ) {
                                for (; i < t.length && /\s/.test(t[i]); )
                                    i += 1;
                                "" !== n && (e.push(n), (n = ""));
                                continue;
                            }
                            if (t.startsWith(r, i)) {
                                if (((n += r), "/" === t[(i += 5)])) {
                                    ((a = true),
                                        (s = false),
                                        (n += "/"),
                                        (i += 1));
                                    continue;
                                }
                                continue;
                            }
                            ((n += u), (i += 1));
                        }
                    }
                    return ("" !== n && e.push(n), e);
                })(t);
                return e.map(function (t) {
                    var e = t.split(r),
                        n = e[0],
                        i = e[1];
                    return void 0 !== i
                        ? ("true" === i
                              ? (i = true)
                              : "false" === i
                                ? (i = false)
                                : i.startsWith("/")
                                  ? (i = toRegExp(i))
                                  : "string" == typeof i &&
                                    /^\d+$/.test(i) &&
                                    (i = parseFloat(i)),
                          {
                              path: n,
                              value: i,
                          })
                        : {
                              path: n,
                          };
                });
            }
            return [];
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function getNativeRegexpTest() {
            var t = Object.getOwnPropertyDescriptor(RegExp.prototype, "test"),
                e = null == t ? void 0 : t.value;
            if (t && "function" == typeof t.value) return e;
            throw new Error("RegExp.prototype.test is not a function");
        }
        function shouldAbortInlineOrInjectedScript(t, i) {
            var r = "inlineScript",
                n = "injectedScript",
                isInlineScript = function isInlineScript(t) {
                    return t.includes(r);
                },
                isInjectedScript = function isInjectedScript(t) {
                    return t.includes(n);
                };
            if (!isInlineScript(t) && !isInjectedScript(t)) return false;
            var e = window.location.href,
                s = e.indexOf("#");
            -1 !== s && (e = e.slice(0, s));
            var c = i
                .split("\n")
                .slice(2)
                .map(function (t) {
                    return t.trim();
                })
                .map(function (t) {
                    var i,
                        s = /(.*?@)?(\S+)(:\d+)(:\d+)\)?$/.exec(t);
                    if (s) {
                        var c,
                            l,
                            a = s[2],
                            u = s[3],
                            o = s[4];
                        if (
                            (null !== (c = a) &&
                                void 0 !== c &&
                                c.startsWith("(") &&
                                (a = a.slice(1)),
                            null !== (l = a) &&
                                void 0 !== l &&
                                l.startsWith("<anonymous>"))
                        ) {
                            var d;
                            a = n;
                            var f =
                                void 0 !== s[1]
                                    ? s[1].slice(0, -1)
                                    : t.slice(0, s.index).trim();
                            (null !== (d = f) &&
                                void 0 !== d &&
                                d.startsWith("at") &&
                                (f = f.slice(2).trim()),
                                (i = `${f} ${a}${u}${o}`.trim()));
                        } else
                            i =
                                a === e
                                    ? `${r}${u}${o}`.trim()
                                    : `${a}${u}${o}`.trim();
                    } else i = t;
                    return i;
                });
            if (c)
                for (var l = 0; l < c.length; l += 1) {
                    if (
                        isInlineScript(t) &&
                        c[l].startsWith(r) &&
                        c[l].match(toRegExp(t))
                    )
                        return true;
                    if (
                        isInjectedScript(t) &&
                        c[l].startsWith(n) &&
                        c[l].match(toRegExp(t))
                    )
                        return true;
                }
            return false;
        }
        function backupRegExpValues() {
            try {
                for (var r = [], e = 1; e < 10; e += 1) {
                    var a = `$${e}`;
                    if (!RegExp[a]) break;
                    r.push(RegExp[a]);
                }
                return r;
            } catch (r) {
                return [];
            }
        }
        function restoreRegExpValues(e) {
            if (e.length)
                try {
                    var r = "";
                    r =
                        1 === e.length
                            ? `(${e[0]})`
                            : e.reduce(function (e, r, t) {
                                  return 1 === t
                                      ? `(${e}),(${r})`
                                      : `${e},(${r})`;
                              });
                    var t = new RegExp(r);
                    e.toString().replace(t, "");
                } catch (e) {
                    var n = `Failed to restore RegExp values: ${e}`;
                    console.log(n);
                }
        }
        function isKeyInObject(t, r, e) {
            var n = r.split("."),
                _check3 = function _check(t, r) {
                    if (null == t) return false;
                    if (0 === r.length)
                        return (
                            void 0 === e ||
                            ("string" == typeof t && e instanceof RegExp
                                ? e.test(t)
                                : t === e)
                        );
                    var n = r[0],
                        i = r.slice(1);
                    if ("*" === n || "[]" === n) {
                        if (Array.isArray(t))
                            return t.some(function (t) {
                                return _check3(t, i);
                            });
                        if ("object" == typeof t && null !== t)
                            return Object.keys(t).some(function (r) {
                                return _check3(t[r], i);
                            });
                    }
                    return (
                        !!Object.prototype.hasOwnProperty.call(t, n) &&
                        _check3(t[n], i)
                    );
                };
            return _check3(t, n);
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            jsonPrune.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function jsonPruneFetchResponse(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function jsonPruneFetchResponse(
            source,
            propsToRemove,
            obligatoryProps,
        ) {
            var propsToMatch =
                arguments.length > 3 && arguments[3] !== undefined
                    ? arguments[3]
                    : "";
            var stack =
                arguments.length > 4 && arguments[4] !== undefined
                    ? arguments[4]
                    : "";
            if (
                typeof fetch === "undefined" ||
                typeof Proxy === "undefined" ||
                typeof Response === "undefined"
            ) {
                return;
            }
            var prunePaths = getPrunePath(propsToRemove);
            var requiredPaths = getPrunePath(obligatoryProps);
            var nativeStringify = window.JSON.stringify;
            var nativeRequestClone = window.Request.prototype.clone;
            var nativeResponseClone = window.Response.prototype.clone;
            var nativeFetch = window.fetch;
            var fetchHandlerWrapper = async function fetchHandlerWrapper(
                target,
                thisArg,
                args,
            ) {
                var fetchData = getFetchData(args, nativeRequestClone);
                if (!matchRequestProps(source, propsToMatch, fetchData)) {
                    return Reflect.apply(target, thisArg, args);
                }
                var originalResponse;
                var clonedResponse;
                try {
                    originalResponse = await nativeFetch.apply(null, args);
                    clonedResponse = nativeResponseClone.call(originalResponse);
                } catch (_unused) {
                    logMessage(
                        source,
                        `Could not make an original fetch request: ${fetchData.url}`,
                    );
                    return Reflect.apply(target, thisArg, args);
                }
                var json;
                try {
                    json = await originalResponse.json();
                } catch (e) {
                    var message = `Response body can't be converted to json: ${objectToString(fetchData)}`;
                    logMessage(source, message);
                    return clonedResponse;
                }
                var modifiedJson = jsonPruner(
                    source,
                    json,
                    prunePaths,
                    requiredPaths,
                    stack,
                    {
                        nativeStringify: nativeStringify,
                        nativeRequestClone: nativeRequestClone,
                        nativeResponseClone: nativeResponseClone,
                        nativeFetch: nativeFetch,
                    },
                );
                var forgedResponse = forgeResponse(
                    originalResponse,
                    nativeStringify(modifiedJson),
                );
                hit(source);
                return forgedResponse;
            };
            var fetchHandler = {
                apply: fetchHandlerWrapper,
            };
            window.fetch = new Proxy(window.fetch, fetchHandler);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function getFetchData(e, t) {
            var a,
                c,
                n = {},
                r = e[0];
            if (r instanceof Request) {
                var u = t.call(r),
                    f = getRequestData(u);
                ((a = f.url), (c = f));
            } else ((a = r), (c = e[1]));
            ((n.url = a), c instanceof Object) &&
                Object.keys(c).forEach(function (e) {
                    n[e] = c[e];
                });
            return n;
        }
        function objectToString(t) {
            return t && "object" == typeof t
                ? isEmptyObject(t)
                    ? "{}"
                    : Object.entries(t)
                          .map(function (t) {
                              var n = t[0],
                                  e = t[1],
                                  o = e;
                              return (
                                  e instanceof Object &&
                                      (o = `{ ${objectToString(e)} }`),
                                  `${n}:"${o}"`
                              );
                          })
                          .join(" ")
                : String(t);
        }
        function matchRequestProps(e, t, r) {
            if ("" === t || "*" === t) return true;
            var a,
                s = parseMatchProps(t);
            if (isValidParsedData(s)) {
                var n = getMatchPropsData(s);
                a = Object.keys(n).every(function (e) {
                    var t = n[e],
                        a = r[e];
                    return (
                        Object.prototype.hasOwnProperty.call(r, e) &&
                        "string" == typeof a &&
                        (null == t ? void 0 : t.test(a))
                    );
                });
            } else (logMessage(e, `Invalid parameter: ${t}`), (a = false));
            return a;
        }
        function jsonPruner(e, r, n, a, t, i) {
            var { nativeStringify: o } = i;
            if (0 === n.length && 0 === a.length)
                return (
                    logMessage(
                        e,
                        `${window.location.hostname}\n${o(r, null, 2)}\nStack trace:\n${new Error().stack}`,
                        true,
                    ),
                    r && "object" == typeof r && logMessage(e, r, true, false),
                    r
                );
            try {
                if (!1 === isPruningNeeded(e, r, n, a, t, i)) return r;
                n.forEach(function (n) {
                    for (
                        var a = n.path,
                            t = n.value,
                            i = getWildcardPropertyInChain(r, a, !0, [], t),
                            o = i.length - 1;
                        o >= 0;
                        o -= 1
                    ) {
                        var s = i[o];
                        if (void 0 !== s && s.base)
                            if ((hit(e), Array.isArray(s.base)))
                                try {
                                    var l = Number(s.prop);
                                    if (Number.isNaN(l)) continue;
                                    s.base.splice(l, 1);
                                } catch (e) {
                                    console.error(
                                        "Error while deleting array element",
                                        e,
                                    );
                                }
                            else delete s.base[s.prop];
                    }
                });
            } catch (r) {
                logMessage(e, r);
            }
            return r;
        }
        function getPrunePath(t) {
            var r = ".[=].";
            if ("string" == typeof t && void 0 !== t && "" !== t) {
                var e = (function (t) {
                    for (
                        var e = [], n = "", i = 0, a = false, s = false;
                        i < t.length;

                    ) {
                        var u = t[i];
                        if (a)
                            ((n += u),
                                "\\" === u
                                    ? (s = !s)
                                    : ("/" !== u || s || (a = false),
                                      (s = false)),
                                (i += 1));
                        else {
                            if (
                                " " === u ||
                                "\n" === u ||
                                "\t" === u ||
                                "\r" === u ||
                                "\f" === u ||
                                "\v" === u
                            ) {
                                for (; i < t.length && /\s/.test(t[i]); )
                                    i += 1;
                                "" !== n && (e.push(n), (n = ""));
                                continue;
                            }
                            if (t.startsWith(r, i)) {
                                if (((n += r), "/" === t[(i += 5)])) {
                                    ((a = true),
                                        (s = false),
                                        (n += "/"),
                                        (i += 1));
                                    continue;
                                }
                                continue;
                            }
                            ((n += u), (i += 1));
                        }
                    }
                    return ("" !== n && e.push(n), e);
                })(t);
                return e.map(function (t) {
                    var e = t.split(r),
                        n = e[0],
                        i = e[1];
                    return void 0 !== i
                        ? ("true" === i
                              ? (i = true)
                              : "false" === i
                                ? (i = false)
                                : i.startsWith("/")
                                  ? (i = toRegExp(i))
                                  : "string" == typeof i &&
                                    /^\d+$/.test(i) &&
                                    (i = parseFloat(i)),
                          {
                              path: n,
                              value: i,
                          })
                        : {
                              path: n,
                          };
                });
            }
            return [];
        }
        function forgeResponse(e, t) {
            var {
                    bodyUsed: s,
                    headers: r,
                    ok: u,
                    redirected: a,
                    status: d,
                    statusText: o,
                    type: l,
                    url: n,
                } = e,
                v = new Response(t, {
                    status: d,
                    statusText: o,
                    headers: r,
                });
            return (
                Object.defineProperties(v, {
                    url: {
                        value: n,
                    },
                    type: {
                        value: l,
                    },
                    ok: {
                        value: u,
                    },
                    bodyUsed: {
                        value: s,
                    },
                    redirected: {
                        value: a,
                    },
                }),
                v
            );
        }
        function isPruningNeeded(n, t, r, e, a, i) {
            if (!t) return false;
            var o,
                { nativeStringify: u } = i,
                c = r.map(function (n) {
                    return n.path;
                }),
                f = e.map(function (n) {
                    return n.path;
                });
            if (0 === c.length && f.length > 0) {
                var g = u(t);
                if (toRegExp(f.join("")).test(g))
                    return (
                        logMessage(
                            n,
                            `${window.location.hostname}\n${u(t, null, 2)}\nStack trace:\n${new Error().stack}`,
                            true,
                        ),
                        t &&
                            "object" == typeof t &&
                            logMessage(n, t, true, false),
                        (o = false)
                    );
            }
            if (a && !matchStackTrace(a, new Error().stack || ""))
                return (o = false);
            for (
                var s,
                    l = [".*.", "*.", ".*", ".[].", "[].", ".[]"],
                    _loop = function _loop() {
                        var n = f[p],
                            r = n.split(".").pop(),
                            e = l.some(function (t) {
                                return n.includes(t);
                            }),
                            a = getWildcardPropertyInChain(t, n, e);
                        if (!a.length)
                            return {
                                v: (o = false),
                            };
                        o = !e;
                        for (var i = 0; i < a.length; i += 1) {
                            var u =
                                "string" == typeof r && void 0 !== a[i].base[r];
                            o = e ? u || o : u && o;
                        }
                    },
                    p = 0;
                p < f.length;
                p += 1
            )
                if ((s = _loop())) return s.v;
            return o;
        }
        function matchStackTrace(e, t) {
            if (!e || "" === e) return true;
            var r = backupRegExpValues();
            if (shouldAbortInlineOrInjectedScript(e, t))
                return (
                    r.length && r[0] !== RegExp.$1 && restoreRegExpValues(r),
                    true
                );
            var n = toRegExp(e),
                a = t
                    .split("\n")
                    .slice(2)
                    .map(function (e) {
                        return e.trim();
                    })
                    .join("\n");
            return (
                r.length && r[0] !== RegExp.$1 && restoreRegExpValues(r),
                getNativeRegexpTest().call(n, a)
            );
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function isValidStrPattern(e) {
            var t,
                n = escapeRegExp(e);
            "/" === e[0] && "/" === e[e.length - 1] && (n = e.slice(1, -1));
            try {
                ((t = new RegExp(n)), (t = !0));
            } catch (e) {
                t = false;
            }
            return t;
        }
        function escapeRegExp(e) {
            return e.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        }
        function isEmptyObject(t) {
            return 0 === Object.keys(t).length && !t.prototype;
        }
        function getRequestData(t) {
            var e = getRequestProps().map(function (e) {
                return [e, t[e]];
            });
            return Object.fromEntries(e);
        }
        function getRequestProps() {
            return [
                "url",
                "method",
                "headers",
                "body",
                "credentials",
                "cache",
                "redirect",
                "referrer",
                "referrerPolicy",
                "integrity",
                "keepalive",
                "signal",
                "mode",
            ];
        }
        function parseMatchProps(e) {
            var r = {};
            return (
                e.split(" ").forEach(function (e) {
                    var n = e.indexOf(":"),
                        i = e.slice(0, n);
                    if (
                        (function (e) {
                            return getRequestProps().includes(e);
                        })(i)
                    ) {
                        var s = e.slice(n + 1);
                        r[i] = s;
                    } else r.url = e;
                }),
                r
            );
        }
        function isValidParsedData(t) {
            return Object.values(t).every(function (t) {
                return isValidStrPattern(t);
            });
        }
        function getMatchPropsData(t) {
            var a = {};
            return (
                Object.keys(t).forEach(function (c) {
                    a[c] = toRegExp(t[c]);
                }),
                a
            );
        }
        function getWildcardPropertyInChain(r, e) {
            var a =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                i =
                    arguments.length > 3 && void 0 !== arguments[3]
                        ? arguments[3]
                        : [],
                t = arguments.length > 4 ? arguments[4] : void 0,
                o = e.indexOf(".");
            if (-1 === o) {
                if ("*" === e || "[]" === e) {
                    for (var n in r)
                        if (Object.prototype.hasOwnProperty.call(r, n))
                            if (void 0 !== t) {
                                var s = r[n];
                                "string" == typeof s && t instanceof RegExp
                                    ? t.test(s) &&
                                      i.push({
                                          base: r,
                                          prop: n,
                                      })
                                    : s === t &&
                                      i.push({
                                          base: r,
                                          prop: n,
                                      });
                            } else
                                i.push({
                                    base: r,
                                    prop: n,
                                });
                } else if (void 0 !== t) {
                    var p = r[e];
                    "string" == typeof p && t instanceof RegExp
                        ? t.test(p) &&
                          i.push({
                              base: r,
                              prop: e,
                          })
                        : r[e] === t &&
                          i.push({
                              base: r,
                              prop: e,
                          });
                } else
                    i.push({
                        base: r,
                        prop: e,
                    });
                return i;
            }
            var c = e.slice(0, o);
            if (
                ("[]" === c && Array.isArray(r)) ||
                ("*" === c && r instanceof Object) ||
                ("[-]" === c && Array.isArray(r)) ||
                ("{-}" === c && r instanceof Object)
            ) {
                var f = e.slice(o + 1),
                    y = Object.keys(r);
                if ("{-}" === c || "[-]" === c) {
                    var h = Array.isArray(r) ? "array" : "object";
                    return (
                        (("{-}" !== c || "object" !== h) &&
                            ("[-]" !== c || "array" !== h)) ||
                            y.forEach(function (e) {
                                var a = r[e];
                                isKeyInObject(a, f, t) &&
                                    i.push({
                                        base: r,
                                        prop: e,
                                    });
                            }),
                        i
                    );
                }
                y.forEach(function (e) {
                    getWildcardPropertyInChain(r[e], f, a, i, t);
                });
            }
            Array.isArray(r) &&
                r.forEach(function (r) {
                    void 0 !== r && getWildcardPropertyInChain(r, e, a, i, t);
                });
            var d = r[c];
            return (
                (e = e.slice(o + 1)),
                void 0 !== d && getWildcardPropertyInChain(d, e, a, i, t),
                i
            );
        }
        function shouldAbortInlineOrInjectedScript(t, i) {
            var r = "inlineScript",
                n = "injectedScript",
                isInlineScript = function isInlineScript(t) {
                    return t.includes(r);
                },
                isInjectedScript = function isInjectedScript(t) {
                    return t.includes(n);
                };
            if (!isInlineScript(t) && !isInjectedScript(t)) return false;
            var e = window.location.href,
                s = e.indexOf("#");
            -1 !== s && (e = e.slice(0, s));
            var c = i
                .split("\n")
                .slice(2)
                .map(function (t) {
                    return t.trim();
                })
                .map(function (t) {
                    var i,
                        s = /(.*?@)?(\S+)(:\d+)(:\d+)\)?$/.exec(t);
                    if (s) {
                        var c,
                            l,
                            a = s[2],
                            u = s[3],
                            o = s[4];
                        if (
                            (null !== (c = a) &&
                                void 0 !== c &&
                                c.startsWith("(") &&
                                (a = a.slice(1)),
                            null !== (l = a) &&
                                void 0 !== l &&
                                l.startsWith("<anonymous>"))
                        ) {
                            var d;
                            a = n;
                            var f =
                                void 0 !== s[1]
                                    ? s[1].slice(0, -1)
                                    : t.slice(0, s.index).trim();
                            (null !== (d = f) &&
                                void 0 !== d &&
                                d.startsWith("at") &&
                                (f = f.slice(2).trim()),
                                (i = `${f} ${a}${u}${o}`.trim()));
                        } else
                            i =
                                a === e
                                    ? `${r}${u}${o}`.trim()
                                    : `${a}${u}${o}`.trim();
                    } else i = t;
                    return i;
                });
            if (c)
                for (var l = 0; l < c.length; l += 1) {
                    if (
                        isInlineScript(t) &&
                        c[l].startsWith(r) &&
                        c[l].match(toRegExp(t))
                    )
                        return true;
                    if (
                        isInjectedScript(t) &&
                        c[l].startsWith(n) &&
                        c[l].match(toRegExp(t))
                    )
                        return true;
                }
            return false;
        }
        function getNativeRegexpTest() {
            var t = Object.getOwnPropertyDescriptor(RegExp.prototype, "test"),
                e = null == t ? void 0 : t.value;
            if (t && "function" == typeof t.value) return e;
            throw new Error("RegExp.prototype.test is not a function");
        }
        function backupRegExpValues() {
            try {
                for (var r = [], e = 1; e < 10; e += 1) {
                    var a = `$${e}`;
                    if (!RegExp[a]) break;
                    r.push(RegExp[a]);
                }
                return r;
            } catch (r) {
                return [];
            }
        }
        function restoreRegExpValues(e) {
            if (e.length)
                try {
                    var r = "";
                    r =
                        1 === e.length
                            ? `(${e[0]})`
                            : e.reduce(function (e, r, t) {
                                  return 1 === t
                                      ? `(${e}),(${r})`
                                      : `${e},(${r})`;
                              });
                    var t = new RegExp(r);
                    e.toString().replace(t, "");
                } catch (e) {
                    var n = `Failed to restore RegExp values: ${e}`;
                    console.log(n);
                }
        }
        function isKeyInObject(t, r, e) {
            var n = r.split("."),
                _check4 = function _check(t, r) {
                    if (null == t) return false;
                    if (0 === r.length)
                        return (
                            void 0 === e ||
                            ("string" == typeof t && e instanceof RegExp
                                ? e.test(t)
                                : t === e)
                        );
                    var n = r[0],
                        i = r.slice(1);
                    if ("*" === n || "[]" === n) {
                        if (Array.isArray(t))
                            return t.some(function (t) {
                                return _check4(t, i);
                            });
                        if ("object" == typeof t && null !== t)
                            return Object.keys(t).some(function (r) {
                                return _check4(t[r], i);
                            });
                    }
                    return (
                        !!Object.prototype.hasOwnProperty.call(t, n) &&
                        _check4(t[n], i)
                    );
                };
            return _check4(t, n);
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            jsonPruneFetchResponse.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function jsonPruneXhrResponse(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function jsonPruneXhrResponse(source, propsToRemove, obligatoryProps) {
            var propsToMatch =
                arguments.length > 3 && arguments[3] !== undefined
                    ? arguments[3]
                    : "";
            var stack =
                arguments.length > 4 && arguments[4] !== undefined
                    ? arguments[4]
                    : "";
            if (typeof Proxy === "undefined") {
                return;
            }
            var shouldLog = !propsToRemove && !obligatoryProps;
            var prunePaths = getPrunePath(propsToRemove);
            var requiredPaths = getPrunePath(obligatoryProps);
            var nativeParse = window.JSON.parse;
            var nativeStringify = window.JSON.stringify;
            var nativeOpen = window.XMLHttpRequest.prototype.open;
            var nativeSend = window.XMLHttpRequest.prototype.send;
            var setRequestHeaderWrapper = function setRequestHeaderWrapper(
                setRequestHeader,
                thisArgument,
                argsList,
            ) {
                thisArgument.collectedHeaders.push(argsList);
                return Reflect.apply(setRequestHeader, thisArgument, argsList);
            };
            var setRequestHeaderHandler = {
                apply: setRequestHeaderWrapper,
            };
            var xhrData;
            var openWrapper = function openWrapper(target, thisArg, args) {
                xhrData = getXhrData.apply(null, args);
                if (
                    matchRequestProps(source, propsToMatch, xhrData) ||
                    shouldLog
                ) {
                    thisArg.xhrShouldBePruned = true;
                    thisArg.headersReceived = !!thisArg.headersReceived;
                }
                if (thisArg.xhrShouldBePruned && !thisArg.headersReceived) {
                    thisArg.headersReceived = true;
                    thisArg.collectedHeaders = [];
                    thisArg.setRequestHeader = new Proxy(
                        thisArg.setRequestHeader,
                        setRequestHeaderHandler,
                    );
                }
                return Reflect.apply(target, thisArg, args);
            };
            var sendWrapper = function sendWrapper(target, thisArg, args) {
                var stackTrace = new Error().stack || "";
                if (
                    !thisArg.xhrShouldBePruned ||
                    (stack && !matchStackTrace(stack, stackTrace))
                ) {
                    return Reflect.apply(target, thisArg, args);
                }
                var forgedRequest = new XMLHttpRequest();
                forgedRequest.addEventListener("readystatechange", function () {
                    if (forgedRequest.readyState !== 4) {
                        return;
                    }
                    var {
                        readyState: readyState,
                        response: response,
                        responseText: responseText,
                        responseURL: responseURL,
                        responseXML: responseXML,
                        status: status,
                        statusText: statusText,
                    } = forgedRequest;
                    var content = responseText || response;
                    if (
                        typeof content !== "string" &&
                        typeof content !== "object"
                    ) {
                        return;
                    }
                    var modifiedContent;
                    if (typeof content === "string") {
                        try {
                            var jsonContent = nativeParse(content);
                            if (shouldLog) {
                                logMessage(
                                    source,
                                    `${window.location.hostname}\n${nativeStringify(jsonContent, null, 2)}\nStack trace:\n${stackTrace}`,
                                    true,
                                );
                                logMessage(source, jsonContent, true, false);
                                modifiedContent = content;
                            } else {
                                modifiedContent = jsonPruner(
                                    source,
                                    jsonContent,
                                    prunePaths,
                                    requiredPaths,
                                    (stack = ""),
                                    {
                                        nativeStringify: nativeStringify,
                                    },
                                );
                                try {
                                    var { responseType: responseType } =
                                        thisArg;
                                    switch (responseType) {
                                        case "":
                                        case "text":
                                            modifiedContent =
                                                nativeStringify(
                                                    modifiedContent,
                                                );
                                            break;
                                        case "arraybuffer":
                                            modifiedContent =
                                                new TextEncoder().encode(
                                                    nativeStringify(
                                                        modifiedContent,
                                                    ),
                                                ).buffer;
                                            break;
                                        case "blob":
                                            modifiedContent = new Blob([
                                                nativeStringify(
                                                    modifiedContent,
                                                ),
                                            ]);
                                            break;
                                        default:
                                            break;
                                    }
                                } catch (error) {
                                    var message = `Response body cannot be converted to reponse type: '${content}'`;
                                    logMessage(source, message);
                                    modifiedContent = content;
                                }
                            }
                        } catch (error) {
                            var _message = `Response body cannot be converted to json: '${content}'`;
                            logMessage(source, _message);
                            modifiedContent = content;
                        }
                    }
                    Object.defineProperties(thisArg, {
                        readyState: {
                            value: readyState,
                            writable: false,
                        },
                        responseURL: {
                            value: responseURL,
                            writable: false,
                        },
                        responseXML: {
                            value: responseXML,
                            writable: false,
                        },
                        status: {
                            value: status,
                            writable: false,
                        },
                        statusText: {
                            value: statusText,
                            writable: false,
                        },
                        response: {
                            value: modifiedContent,
                            writable: false,
                        },
                        responseText: {
                            value: modifiedContent,
                            writable: false,
                        },
                    });
                    setTimeout(function () {
                        var stateEvent = new Event("readystatechange");
                        thisArg.dispatchEvent(stateEvent);
                        var loadEvent = new Event("load");
                        thisArg.dispatchEvent(loadEvent);
                        var loadEndEvent = new Event("loadend");
                        thisArg.dispatchEvent(loadEndEvent);
                    }, 1);
                    hit(source);
                });
                nativeOpen.apply(forgedRequest, [
                    xhrData.method,
                    xhrData.url,
                    Boolean(xhrData.async),
                ]);
                thisArg.collectedHeaders.forEach(function (header) {
                    forgedRequest.setRequestHeader(header[0], header[1]);
                });
                thisArg.collectedHeaders = [];
                try {
                    nativeSend.call(forgedRequest, args);
                } catch (_unused) {
                    return Reflect.apply(target, thisArg, args);
                }
                return undefined;
            };
            var openHandler = {
                apply: openWrapper,
            };
            var sendHandler = {
                apply: sendWrapper,
            };
            XMLHttpRequest.prototype.open = new Proxy(
                XMLHttpRequest.prototype.open,
                openHandler,
            );
            XMLHttpRequest.prototype.send = new Proxy(
                XMLHttpRequest.prototype.send,
                sendHandler,
            );
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function jsonPruner(e, r, n, a, t, i) {
            var { nativeStringify: o } = i;
            if (0 === n.length && 0 === a.length)
                return (
                    logMessage(
                        e,
                        `${window.location.hostname}\n${o(r, null, 2)}\nStack trace:\n${new Error().stack}`,
                        true,
                    ),
                    r && "object" == typeof r && logMessage(e, r, true, false),
                    r
                );
            try {
                if (!1 === isPruningNeeded(e, r, n, a, t, i)) return r;
                n.forEach(function (n) {
                    for (
                        var a = n.path,
                            t = n.value,
                            i = getWildcardPropertyInChain(r, a, !0, [], t),
                            o = i.length - 1;
                        o >= 0;
                        o -= 1
                    ) {
                        var s = i[o];
                        if (void 0 !== s && s.base)
                            if ((hit(e), Array.isArray(s.base)))
                                try {
                                    var l = Number(s.prop);
                                    if (Number.isNaN(l)) continue;
                                    s.base.splice(l, 1);
                                } catch (e) {
                                    console.error(
                                        "Error while deleting array element",
                                        e,
                                    );
                                }
                            else delete s.base[s.prop];
                    }
                });
            } catch (r) {
                logMessage(e, r);
            }
            return r;
        }
        function getPrunePath(t) {
            var r = ".[=].";
            if ("string" == typeof t && void 0 !== t && "" !== t) {
                var e = (function (t) {
                    for (
                        var e = [], n = "", i = 0, a = false, s = false;
                        i < t.length;

                    ) {
                        var u = t[i];
                        if (a)
                            ((n += u),
                                "\\" === u
                                    ? (s = !s)
                                    : ("/" !== u || s || (a = false),
                                      (s = false)),
                                (i += 1));
                        else {
                            if (
                                " " === u ||
                                "\n" === u ||
                                "\t" === u ||
                                "\r" === u ||
                                "\f" === u ||
                                "\v" === u
                            ) {
                                for (; i < t.length && /\s/.test(t[i]); )
                                    i += 1;
                                "" !== n && (e.push(n), (n = ""));
                                continue;
                            }
                            if (t.startsWith(r, i)) {
                                if (((n += r), "/" === t[(i += 5)])) {
                                    ((a = true),
                                        (s = false),
                                        (n += "/"),
                                        (i += 1));
                                    continue;
                                }
                                continue;
                            }
                            ((n += u), (i += 1));
                        }
                    }
                    return ("" !== n && e.push(n), e);
                })(t);
                return e.map(function (t) {
                    var e = t.split(r),
                        n = e[0],
                        i = e[1];
                    return void 0 !== i
                        ? ("true" === i
                              ? (i = true)
                              : "false" === i
                                ? (i = false)
                                : i.startsWith("/")
                                  ? (i = toRegExp(i))
                                  : "string" == typeof i &&
                                    /^\d+$/.test(i) &&
                                    (i = parseFloat(i)),
                          {
                              path: n,
                              value: i,
                          })
                        : {
                              path: n,
                          };
                });
            }
            return [];
        }
        function matchRequestProps(e, t, r) {
            if ("" === t || "*" === t) return true;
            var a,
                s = parseMatchProps(t);
            if (isValidParsedData(s)) {
                var n = getMatchPropsData(s);
                a = Object.keys(n).every(function (e) {
                    var t = n[e],
                        a = r[e];
                    return (
                        Object.prototype.hasOwnProperty.call(r, e) &&
                        "string" == typeof a &&
                        (null == t ? void 0 : t.test(a))
                    );
                });
            } else (logMessage(e, `Invalid parameter: ${t}`), (a = false));
            return a;
        }
        function getXhrData(r, t, a, e, n) {
            return {
                method: r,
                url: t,
                async: a,
                user: e,
                password: n,
            };
        }
        function isPruningNeeded(n, t, r, e, a, i) {
            if (!t) return false;
            var o,
                { nativeStringify: u } = i,
                c = r.map(function (n) {
                    return n.path;
                }),
                f = e.map(function (n) {
                    return n.path;
                });
            if (0 === c.length && f.length > 0) {
                var g = u(t);
                if (toRegExp(f.join("")).test(g))
                    return (
                        logMessage(
                            n,
                            `${window.location.hostname}\n${u(t, null, 2)}\nStack trace:\n${new Error().stack}`,
                            true,
                        ),
                        t &&
                            "object" == typeof t &&
                            logMessage(n, t, true, false),
                        (o = false)
                    );
            }
            if (a && !matchStackTrace(a, new Error().stack || ""))
                return (o = false);
            for (
                var s,
                    l = [".*.", "*.", ".*", ".[].", "[].", ".[]"],
                    _loop = function _loop() {
                        var n = f[p],
                            r = n.split(".").pop(),
                            e = l.some(function (t) {
                                return n.includes(t);
                            }),
                            a = getWildcardPropertyInChain(t, n, e);
                        if (!a.length)
                            return {
                                v: (o = false),
                            };
                        o = !e;
                        for (var i = 0; i < a.length; i += 1) {
                            var u =
                                "string" == typeof r && void 0 !== a[i].base[r];
                            o = e ? u || o : u && o;
                        }
                    },
                    p = 0;
                p < f.length;
                p += 1
            )
                if ((s = _loop())) return s.v;
            return o;
        }
        function matchStackTrace(e, t) {
            if (!e || "" === e) return true;
            var r = backupRegExpValues();
            if (shouldAbortInlineOrInjectedScript(e, t))
                return (
                    r.length && r[0] !== RegExp.$1 && restoreRegExpValues(r),
                    true
                );
            var n = toRegExp(e),
                a = t
                    .split("\n")
                    .slice(2)
                    .map(function (e) {
                        return e.trim();
                    })
                    .join("\n");
            return (
                r.length && r[0] !== RegExp.$1 && restoreRegExpValues(r),
                getNativeRegexpTest().call(n, a)
            );
        }
        function getMatchPropsData(t) {
            var a = {};
            return (
                Object.keys(t).forEach(function (c) {
                    a[c] = toRegExp(t[c]);
                }),
                a
            );
        }
        function getRequestProps() {
            return [
                "url",
                "method",
                "headers",
                "body",
                "credentials",
                "cache",
                "redirect",
                "referrer",
                "referrerPolicy",
                "integrity",
                "keepalive",
                "signal",
                "mode",
            ];
        }
        function isValidParsedData(t) {
            return Object.values(t).every(function (t) {
                return isValidStrPattern(t);
            });
        }
        function parseMatchProps(e) {
            var r = {};
            return (
                e.split(" ").forEach(function (e) {
                    var n = e.indexOf(":"),
                        i = e.slice(0, n);
                    if (
                        (function (e) {
                            return getRequestProps().includes(e);
                        })(i)
                    ) {
                        var s = e.slice(n + 1);
                        r[i] = s;
                    } else r.url = e;
                }),
                r
            );
        }
        function isValidStrPattern(e) {
            var t,
                n = escapeRegExp(e);
            "/" === e[0] && "/" === e[e.length - 1] && (n = e.slice(1, -1));
            try {
                ((t = new RegExp(n)), (t = !0));
            } catch (e) {
                t = false;
            }
            return t;
        }
        function escapeRegExp(e) {
            return e.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        }
        function getWildcardPropertyInChain(r, e) {
            var a =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                i =
                    arguments.length > 3 && void 0 !== arguments[3]
                        ? arguments[3]
                        : [],
                t = arguments.length > 4 ? arguments[4] : void 0,
                o = e.indexOf(".");
            if (-1 === o) {
                if ("*" === e || "[]" === e) {
                    for (var n in r)
                        if (Object.prototype.hasOwnProperty.call(r, n))
                            if (void 0 !== t) {
                                var s = r[n];
                                "string" == typeof s && t instanceof RegExp
                                    ? t.test(s) &&
                                      i.push({
                                          base: r,
                                          prop: n,
                                      })
                                    : s === t &&
                                      i.push({
                                          base: r,
                                          prop: n,
                                      });
                            } else
                                i.push({
                                    base: r,
                                    prop: n,
                                });
                } else if (void 0 !== t) {
                    var p = r[e];
                    "string" == typeof p && t instanceof RegExp
                        ? t.test(p) &&
                          i.push({
                              base: r,
                              prop: e,
                          })
                        : r[e] === t &&
                          i.push({
                              base: r,
                              prop: e,
                          });
                } else
                    i.push({
                        base: r,
                        prop: e,
                    });
                return i;
            }
            var c = e.slice(0, o);
            if (
                ("[]" === c && Array.isArray(r)) ||
                ("*" === c && r instanceof Object) ||
                ("[-]" === c && Array.isArray(r)) ||
                ("{-}" === c && r instanceof Object)
            ) {
                var f = e.slice(o + 1),
                    y = Object.keys(r);
                if ("{-}" === c || "[-]" === c) {
                    var h = Array.isArray(r) ? "array" : "object";
                    return (
                        (("{-}" !== c || "object" !== h) &&
                            ("[-]" !== c || "array" !== h)) ||
                            y.forEach(function (e) {
                                var a = r[e];
                                isKeyInObject(a, f, t) &&
                                    i.push({
                                        base: r,
                                        prop: e,
                                    });
                            }),
                        i
                    );
                }
                y.forEach(function (e) {
                    getWildcardPropertyInChain(r[e], f, a, i, t);
                });
            }
            Array.isArray(r) &&
                r.forEach(function (r) {
                    void 0 !== r && getWildcardPropertyInChain(r, e, a, i, t);
                });
            var d = r[c];
            return (
                (e = e.slice(o + 1)),
                void 0 !== d && getWildcardPropertyInChain(d, e, a, i, t),
                i
            );
        }
        function shouldAbortInlineOrInjectedScript(t, i) {
            var r = "inlineScript",
                n = "injectedScript",
                isInlineScript = function isInlineScript(t) {
                    return t.includes(r);
                },
                isInjectedScript = function isInjectedScript(t) {
                    return t.includes(n);
                };
            if (!isInlineScript(t) && !isInjectedScript(t)) return false;
            var e = window.location.href,
                s = e.indexOf("#");
            -1 !== s && (e = e.slice(0, s));
            var c = i
                .split("\n")
                .slice(2)
                .map(function (t) {
                    return t.trim();
                })
                .map(function (t) {
                    var i,
                        s = /(.*?@)?(\S+)(:\d+)(:\d+)\)?$/.exec(t);
                    if (s) {
                        var c,
                            l,
                            a = s[2],
                            u = s[3],
                            o = s[4];
                        if (
                            (null !== (c = a) &&
                                void 0 !== c &&
                                c.startsWith("(") &&
                                (a = a.slice(1)),
                            null !== (l = a) &&
                                void 0 !== l &&
                                l.startsWith("<anonymous>"))
                        ) {
                            var d;
                            a = n;
                            var f =
                                void 0 !== s[1]
                                    ? s[1].slice(0, -1)
                                    : t.slice(0, s.index).trim();
                            (null !== (d = f) &&
                                void 0 !== d &&
                                d.startsWith("at") &&
                                (f = f.slice(2).trim()),
                                (i = `${f} ${a}${u}${o}`.trim()));
                        } else
                            i =
                                a === e
                                    ? `${r}${u}${o}`.trim()
                                    : `${a}${u}${o}`.trim();
                    } else i = t;
                    return i;
                });
            if (c)
                for (var l = 0; l < c.length; l += 1) {
                    if (
                        isInlineScript(t) &&
                        c[l].startsWith(r) &&
                        c[l].match(toRegExp(t))
                    )
                        return true;
                    if (
                        isInjectedScript(t) &&
                        c[l].startsWith(n) &&
                        c[l].match(toRegExp(t))
                    )
                        return true;
                }
            return false;
        }
        function getNativeRegexpTest() {
            var t = Object.getOwnPropertyDescriptor(RegExp.prototype, "test"),
                e = null == t ? void 0 : t.value;
            if (t && "function" == typeof t.value) return e;
            throw new Error("RegExp.prototype.test is not a function");
        }
        function backupRegExpValues() {
            try {
                for (var r = [], e = 1; e < 10; e += 1) {
                    var a = `$${e}`;
                    if (!RegExp[a]) break;
                    r.push(RegExp[a]);
                }
                return r;
            } catch (r) {
                return [];
            }
        }
        function restoreRegExpValues(e) {
            if (e.length)
                try {
                    var r = "";
                    r =
                        1 === e.length
                            ? `(${e[0]})`
                            : e.reduce(function (e, r, t) {
                                  return 1 === t
                                      ? `(${e}),(${r})`
                                      : `${e},(${r})`;
                              });
                    var t = new RegExp(r);
                    e.toString().replace(t, "");
                } catch (e) {
                    var n = `Failed to restore RegExp values: ${e}`;
                    console.log(n);
                }
        }
        function isKeyInObject(t, r, e) {
            var n = r.split("."),
                _check5 = function _check(t, r) {
                    if (null == t) return false;
                    if (0 === r.length)
                        return (
                            void 0 === e ||
                            ("string" == typeof t && e instanceof RegExp
                                ? e.test(t)
                                : t === e)
                        );
                    var n = r[0],
                        i = r.slice(1);
                    if ("*" === n || "[]" === n) {
                        if (Array.isArray(t))
                            return t.some(function (t) {
                                return _check5(t, i);
                            });
                        if ("object" == typeof t && null !== t)
                            return Object.keys(t).some(function (r) {
                                return _check5(t[r], i);
                            });
                    }
                    return (
                        !!Object.prototype.hasOwnProperty.call(t, n) &&
                        _check5(t[n], i)
                    );
                };
            return _check5(t, n);
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            jsonPruneXhrResponse.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function log$2(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function log() {
            for (
                var _len = arguments.length, args = new Array(_len), _key = 0;
                _key < _len;
                _key++
            ) {
                args[_key] = arguments[_key];
            }
            console.log(args);
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            log.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function logAddEventListener(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function logAddEventListener(source) {
            var nativeAddEventListener =
                window.EventTarget.prototype.addEventListener;
            function addEventListenerWrapper(type, listener) {
                var _this$constructor;
                if (validateType(type) && validateListener(listener)) {
                    var targetElement;
                    var targetElementInfo;
                    var listenerInfo = listenerToString(listener);
                    if (this) {
                        if (this instanceof Window) {
                            targetElementInfo = "window";
                        } else if (this instanceof Document) {
                            targetElementInfo = "document";
                        } else if (this instanceof Element) {
                            targetElement = this;
                            targetElementInfo =
                                getElementAttributesWithValues(this);
                        }
                    }
                    if (targetElementInfo) {
                        var message = `addEventListener("${type}", ${listenerInfo})\nElement: ${targetElementInfo}`;
                        logMessage(source, message, true);
                        if (targetElement) {
                            console.log(
                                "log-addEventListener Element:",
                                targetElement,
                            );
                        }
                    } else {
                        var _message = `addEventListener("${type}", ${listenerInfo})`;
                        logMessage(source, _message, true);
                    }
                    hit(source);
                } else {
                    var _message2 = `Invalid event type or listener passed to addEventListener:\n        type: ${convertTypeToString(type)}\n        listener: ${convertTypeToString(listener)}`;
                    logMessage(source, _message2, true);
                }
                var context = this;
                if (
                    this &&
                    ((_this$constructor = this.constructor) === null ||
                    _this$constructor === void 0
                        ? void 0
                        : _this$constructor.name) === "Window" &&
                    this !== window
                ) {
                    context = window;
                }
                for (
                    var _len = arguments.length,
                        args = new Array(_len > 2 ? _len - 2 : 0),
                        _key = 2;
                    _key < _len;
                    _key++
                ) {
                    args[_key - 2] = arguments[_key];
                }
                return nativeAddEventListener.apply(context, [
                    type,
                    listener,
                    ...args,
                ]);
            }
            var descriptor = {
                configurable: true,
                set: function set() {},
                get: function get() {
                    return addEventListenerWrapper;
                },
            };
            Object.defineProperty(
                window.EventTarget.prototype,
                "addEventListener",
                descriptor,
            );
            Object.defineProperty(window, "addEventListener", descriptor);
            Object.defineProperty(document, "addEventListener", descriptor);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function validateType(e) {
            return void 0 !== e;
        }
        function validateListener(n) {
            return (
                void 0 !== n &&
                ("function" == typeof n ||
                    ("object" == typeof n &&
                        null !== n &&
                        "handleEvent" in n &&
                        "function" == typeof n.handleEvent))
            );
        }
        function listenerToString(n) {
            return "function" == typeof n
                ? n.toString()
                : n.handleEvent.toString();
        }
        function convertTypeToString(n) {
            return void 0 === n
                ? "undefined"
                : "object" == typeof n
                  ? null === n
                      ? "null"
                      : objectToString(n)
                  : String(n);
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function objectToString(t) {
            return t && "object" == typeof t
                ? isEmptyObject(t)
                    ? "{}"
                    : Object.entries(t)
                          .map(function (t) {
                              var n = t[0],
                                  e = t[1],
                                  o = e;
                              return (
                                  e instanceof Object &&
                                      (o = `{ ${objectToString(e)} }`),
                                  `${n}:"${o}"`
                              );
                          })
                          .join(" ")
                : String(t);
        }
        function isEmptyObject(t) {
            return 0 === Object.keys(t).length && !t.prototype;
        }
        function getElementAttributesWithValues(e) {
            if (!(e && e instanceof Element && e.attributes && e.nodeName))
                return "";
            for (
                var t = e.attributes, n = e.nodeName.toLowerCase(), a = 0;
                a < t.length;
                a += 1
            ) {
                var r = t[a];
                n += `[${r.name}="${r.value}"]`;
            }
            return n;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            logAddEventListener.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function logEval(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function logEval(source) {
            var nativeEval = window.eval;
            function evalWrapper(str) {
                hit(source);
                logMessage(source, `eval("${str}")`, true);
                return nativeEval(str);
            }
            window.eval = evalWrapper;
            var nativeFunction = window.Function;
            function FunctionWrapper() {
                hit(source);
                for (
                    var _len = arguments.length,
                        args = new Array(_len),
                        _key = 0;
                    _key < _len;
                    _key++
                ) {
                    args[_key] = arguments[_key];
                }
                logMessage(source, `new Function(${args.join(", ")})`, true);
                return nativeFunction.apply(this, [...args]);
            }
            FunctionWrapper.prototype = Object.create(nativeFunction.prototype);
            FunctionWrapper.prototype.constructor = FunctionWrapper;
            window.Function = FunctionWrapper;
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            logEval.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function logOnStackTrace(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function logOnStackTrace(source, property) {
            if (!property) {
                return;
            }
            var refineStackTrace = function refineStackTrace(stackString) {
                var regExpValues = backupRegExpValues();
                var stackSteps = stackString
                    .split("\n")
                    .slice(2)
                    .map(function (line) {
                        return line.replace(/ {4}at /, "");
                    });
                var logInfoArray = stackSteps.map(function (line) {
                    var funcName;
                    var funcFullPath;
                    var reg = /\(([^\)]+)\)/;
                    var regFirefox = /(.*?@)(\S+)(:\d+):\d+\)?$/;
                    if (line.match(reg)) {
                        funcName = line.split(" ").slice(0, -1).join(" ");
                        funcFullPath = line.match(reg)[1];
                    } else if (line.match(regFirefox)) {
                        funcName = line.split("@").slice(0, -1).join(" ");
                        funcFullPath = line.match(regFirefox)[2];
                    } else {
                        funcName = "function name is not available";
                        funcFullPath = line;
                    }
                    return [funcName, funcFullPath];
                });
                var logInfoObject = {};
                logInfoArray.forEach(function (pair) {
                    logInfoObject[pair[0]] = pair[1];
                });
                if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
                    restoreRegExpValues(regExpValues);
                }
                return logInfoObject;
            };
            var _setChainPropAccess = function setChainPropAccess(
                owner,
                property,
            ) {
                var chainInfo = getPropertyInChain(owner, property);
                var { base: base } = chainInfo;
                var { prop: prop, chain: chain } = chainInfo;
                if (chain) {
                    var setter = function setter(a) {
                        base = a;
                        if (a instanceof Object) {
                            _setChainPropAccess(a, chain);
                        }
                    };
                    Object.defineProperty(owner, prop, {
                        get: function get() {
                            return base;
                        },
                        set: setter,
                    });
                    return;
                }
                var value = base[prop];
                setPropertyAccess(base, prop, {
                    get() {
                        hit(source);
                        logMessage(source, `Get ${prop}`, true);
                        console.table(refineStackTrace(new Error().stack));
                        return value;
                    },
                    set(newValue) {
                        hit(source);
                        logMessage(source, `Set ${prop}`, true);
                        console.table(refineStackTrace(new Error().stack));
                        value = newValue;
                    },
                });
            };
            _setChainPropAccess(window, property);
        }
        function getPropertyInChain(e, r) {
            var n = r.indexOf(".");
            if (-1 === n)
                return {
                    base: e,
                    prop: r,
                };
            var i = r.slice(0, n);
            if (null === e)
                return {
                    base: e,
                    prop: i,
                    chain: r,
                };
            var t = e[i];
            return (
                (r = r.slice(n + 1)),
                ((e instanceof Object || "object" == typeof e) &&
                    isEmptyObject(e)) ||
                null === t
                    ? {
                          base: e,
                          prop: i,
                          chain: r,
                      }
                    : void 0 !== t
                      ? getPropertyInChain(t, r)
                      : (Object.defineProperty(e, i, {
                            configurable: true,
                        }),
                        {
                            base: e,
                            prop: i,
                            chain: r,
                        })
            );
        }
        function setPropertyAccess(e, r, t) {
            var c = Object.getOwnPropertyDescriptor(e, r);
            return (
                !(c && !c.configurable) &&
                (Object.defineProperty(e, r, t), true)
            );
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function isEmptyObject(t) {
            return 0 === Object.keys(t).length && !t.prototype;
        }
        function backupRegExpValues() {
            try {
                for (var r = [], e = 1; e < 10; e += 1) {
                    var a = `$${e}`;
                    if (!RegExp[a]) break;
                    r.push(RegExp[a]);
                }
                return r;
            } catch (r) {
                return [];
            }
        }
        function restoreRegExpValues(e) {
            if (e.length)
                try {
                    var r = "";
                    r =
                        1 === e.length
                            ? `(${e[0]})`
                            : e.reduce(function (e, r, t) {
                                  return 1 === t
                                      ? `(${e}),(${r})`
                                      : `${e},(${r})`;
                              });
                    var t = new RegExp(r);
                    e.toString().replace(t, "");
                } catch (e) {
                    var n = `Failed to restore RegExp values: ${e}`;
                    console.log(n);
                }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            logOnStackTrace.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function m3uPrune(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function m3uPrune(source, propsToRemove) {
            var urlToMatch =
                arguments.length > 2 && arguments[2] !== undefined
                    ? arguments[2]
                    : "";
            var verbose =
                arguments.length > 3 && arguments[3] !== undefined
                    ? arguments[3]
                    : false;
            if (
                typeof Reflect === "undefined" ||
                typeof fetch === "undefined" ||
                typeof Proxy === "undefined" ||
                typeof Response === "undefined"
            ) {
                return;
            }
            var shouldPruneResponse = false;
            var shouldLogContent = verbose === "true";
            var urlMatchRegexp = toRegExp(urlToMatch);
            var SEGMENT_MARKER = "#";
            var AD_MARKER = {
                ASSET: "#EXT-X-ASSET:",
                CUE: "#EXT-X-CUE:",
                CUE_IN: "#EXT-X-CUE-IN",
                DISCONTINUITY: "#EXT-X-DISCONTINUITY",
                EXTINF: "#EXTINF",
                EXTM3U: "#EXTM3U",
                SCTE35: "#EXT-X-SCTE35:",
            };
            var COMCAST_AD_MARKER = {
                AD: "-AD-",
                VAST: "-VAST-",
                VMAP_AD: "-VMAP-AD-",
                VMAP_AD_BREAK: "#EXT-X-VMAP-AD-BREAK:",
            };
            var TAGS_ALLOWLIST = [
                "#EXT-X-TARGETDURATION",
                "#EXT-X-MEDIA-SEQUENCE",
                "#EXT-X-DISCONTINUITY-SEQUENCE",
                "#EXT-X-ENDLIST",
                "#EXT-X-PLAYLIST-TYPE",
                "#EXT-X-I-FRAMES-ONLY",
                "#EXT-X-MEDIA",
                "#EXT-X-STREAM-INF",
                "#EXT-X-I-FRAME-STREAM-INF",
                "#EXT-X-SESSION-DATA",
                "#EXT-X-SESSION-KEY",
                "#EXT-X-INDEPENDENT-SEGMENTS",
                "#EXT-X-START",
            ];
            var isAllowedTag = function isAllowedTag(str) {
                return TAGS_ALLOWLIST.some(function (el) {
                    return str.startsWith(el);
                });
            };
            var _pruneExtinfFromVmapBlock = function pruneExtinfFromVmapBlock(
                lines,
                i,
            ) {
                var array = lines.slice();
                var index = i;
                if (array[index].includes(AD_MARKER.EXTINF)) {
                    array[index] = undefined;
                    index += 1;
                    if (array[index].includes(AD_MARKER.DISCONTINUITY)) {
                        array[index] = undefined;
                        index += 1;
                        var prunedExtinf = _pruneExtinfFromVmapBlock(
                            array,
                            index,
                        );
                        array = prunedExtinf.array;
                        index = prunedExtinf.index;
                    }
                }
                return {
                    array: array,
                    index: index,
                };
            };
            var pruneVmapBlock = function pruneVmapBlock(lines) {
                var array = lines.slice();
                for (var i = 0; i < array.length - 1; i += 1) {
                    if (
                        array[i].includes(COMCAST_AD_MARKER.VMAP_AD) ||
                        array[i].includes(COMCAST_AD_MARKER.VAST) ||
                        array[i].includes(COMCAST_AD_MARKER.AD)
                    ) {
                        array[i] = undefined;
                        if (array[i + 1].includes(AD_MARKER.EXTINF)) {
                            i += 1;
                            var prunedExtinf = _pruneExtinfFromVmapBlock(
                                array,
                                i,
                            );
                            array = prunedExtinf.array;
                            i = prunedExtinf.index - 1;
                        }
                    }
                }
                return array;
            };
            var pruneSpliceoutBlock = function pruneSpliceoutBlock(
                line,
                index,
                array,
            ) {
                if (!line.startsWith(AD_MARKER.CUE)) {
                    return line;
                }
                line = undefined;
                index += 1;
                if (array[index].startsWith(AD_MARKER.ASSET)) {
                    array[index] = undefined;
                    index += 1;
                }
                if (array[index].startsWith(AD_MARKER.SCTE35)) {
                    array[index] = undefined;
                    index += 1;
                }
                if (array[index].startsWith(AD_MARKER.CUE_IN)) {
                    array[index] = undefined;
                    index += 1;
                }
                if (array[index].startsWith(AD_MARKER.SCTE35)) {
                    array[index] = undefined;
                }
                return line;
            };
            var removeM3ULineRegexp = toRegExp(propsToRemove);
            var pruneInfBlock = function pruneInfBlock(line, index, array) {
                if (!line.startsWith(AD_MARKER.EXTINF)) {
                    return line;
                }
                if (!removeM3ULineRegexp.test(array[index + 1])) {
                    return line;
                }
                if (!isAllowedTag(array[index])) {
                    array[index] = undefined;
                }
                index += 1;
                if (!isAllowedTag(array[index])) {
                    array[index] = undefined;
                }
                index += 1;
                if (array[index].startsWith(AD_MARKER.DISCONTINUITY)) {
                    array[index] = undefined;
                }
                return line;
            };
            var pruneSegments = function pruneSegments(lines) {
                for (var i = 0; i < lines.length - 1; i += 1) {
                    var _lines$i;
                    if (
                        (_lines$i = lines[i]) !== null &&
                        _lines$i !== void 0 &&
                        _lines$i.startsWith(SEGMENT_MARKER) &&
                        removeM3ULineRegexp.test(lines[i])
                    ) {
                        var segmentName = lines[i].substring(
                            0,
                            lines[i].indexOf(":"),
                        );
                        if (!segmentName) {
                            return lines;
                        }
                        lines[i] = undefined;
                        i += 1;
                        for (var j = i; j < lines.length; j += 1) {
                            if (
                                !lines[j].includes(segmentName) &&
                                !isAllowedTag(lines[j])
                            ) {
                                lines[j] = undefined;
                            } else {
                                i = j - 1;
                                break;
                            }
                        }
                    }
                }
                return lines;
            };
            var isM3U = function isM3U(text) {
                if (typeof text === "string") {
                    var trimmedText = text.trim();
                    return (
                        trimmedText.startsWith(AD_MARKER.EXTM3U) ||
                        trimmedText.startsWith(COMCAST_AD_MARKER.VMAP_AD_BREAK)
                    );
                }
                return false;
            };
            var isPruningNeeded = function isPruningNeeded(text, regexp) {
                return isM3U(text) && regexp.test(text);
            };
            var pruneM3U = function pruneM3U(text) {
                if (shouldLogContent) {
                    logMessage(source, `Original M3U content:\n${text}`);
                }
                var lines = text.split(/\r?\n/);
                if (text.includes(COMCAST_AD_MARKER.VMAP_AD_BREAK)) {
                    lines = pruneVmapBlock(lines);
                    lines = lines
                        .filter(function (l) {
                            return !!l;
                        })
                        .join("\n");
                    if (shouldLogContent) {
                        logMessage(source, `Modified M3U content:\n${lines}`);
                    }
                    return lines;
                }
                lines = pruneSegments(lines);
                lines = lines
                    .map(function (line, index, array) {
                        if (typeof line === "undefined") {
                            return line;
                        }
                        line = pruneSpliceoutBlock(line, index, array);
                        if (typeof line !== "undefined") {
                            line = pruneInfBlock(line, index, array);
                        }
                        return line;
                    })
                    .filter(function (l) {
                        return !!l;
                    })
                    .join("\n");
                if (shouldLogContent) {
                    logMessage(source, `Modified M3U content:\n${lines}`);
                }
                return lines;
            };
            var nativeOpen = window.XMLHttpRequest.prototype.open;
            var nativeSend = window.XMLHttpRequest.prototype.send;
            var xhrData;
            var openWrapper = function openWrapper(target, thisArg, args) {
                xhrData = getXhrData.apply(null, args);
                if (matchRequestProps(source, urlToMatch, xhrData)) {
                    thisArg.shouldBePruned = true;
                }
                if (thisArg.shouldBePruned) {
                    thisArg.collectedHeaders = [];
                    var setRequestHeaderWrapper =
                        function setRequestHeaderWrapper(
                            target,
                            thisArg,
                            args,
                        ) {
                            thisArg.collectedHeaders.push(args);
                            return Reflect.apply(target, thisArg, args);
                        };
                    var setRequestHeaderHandler = {
                        apply: setRequestHeaderWrapper,
                    };
                    thisArg.setRequestHeader = new Proxy(
                        thisArg.setRequestHeader,
                        setRequestHeaderHandler,
                    );
                }
                return Reflect.apply(target, thisArg, args);
            };
            var sendWrapper = function sendWrapper(target, thisArg, args) {
                var allowedResponseTypeValues = ["", "text"];
                if (
                    !thisArg.shouldBePruned ||
                    !allowedResponseTypeValues.includes(thisArg.responseType)
                ) {
                    return Reflect.apply(target, thisArg, args);
                }
                var forgedRequest = new XMLHttpRequest();
                forgedRequest.addEventListener("readystatechange", function () {
                    if (forgedRequest.readyState !== 4) {
                        return;
                    }
                    var {
                        readyState: readyState,
                        response: response,
                        responseText: responseText,
                        responseURL: responseURL,
                        responseXML: responseXML,
                        status: status,
                        statusText: statusText,
                    } = forgedRequest;
                    var content = responseText || response;
                    if (typeof content !== "string") {
                        return;
                    }
                    if (!propsToRemove) {
                        if (isM3U(response)) {
                            var message = `XMLHttpRequest.open() URL: ${responseURL}\nresponse: ${response}`;
                            logMessage(source, message);
                        }
                    } else {
                        shouldPruneResponse = isPruningNeeded(
                            response,
                            removeM3ULineRegexp,
                        );
                    }
                    var responseContent = shouldPruneResponse
                        ? pruneM3U(response)
                        : response;
                    Object.defineProperties(thisArg, {
                        readyState: {
                            value: readyState,
                            writable: false,
                        },
                        responseURL: {
                            value: responseURL,
                            writable: false,
                        },
                        responseXML: {
                            value: responseXML,
                            writable: false,
                        },
                        status: {
                            value: status,
                            writable: false,
                        },
                        statusText: {
                            value: statusText,
                            writable: false,
                        },
                        response: {
                            value: responseContent,
                            writable: false,
                        },
                        responseText: {
                            value: responseContent,
                            writable: false,
                        },
                    });
                    setTimeout(function () {
                        var stateEvent = new Event("readystatechange");
                        thisArg.dispatchEvent(stateEvent);
                        var loadEvent = new Event("load");
                        thisArg.dispatchEvent(loadEvent);
                        var loadEndEvent = new Event("loadend");
                        thisArg.dispatchEvent(loadEndEvent);
                    }, 1);
                    hit(source);
                });
                nativeOpen.apply(forgedRequest, [xhrData.method, xhrData.url]);
                thisArg.collectedHeaders.forEach(function (header) {
                    var name = header[0];
                    var value = header[1];
                    forgedRequest.setRequestHeader(name, value);
                });
                thisArg.collectedHeaders = [];
                try {
                    nativeSend.call(forgedRequest, args);
                } catch (_unused) {
                    return Reflect.apply(target, thisArg, args);
                }
                return undefined;
            };
            var openHandler = {
                apply: openWrapper,
            };
            var sendHandler = {
                apply: sendWrapper,
            };
            XMLHttpRequest.prototype.open = new Proxy(
                XMLHttpRequest.prototype.open,
                openHandler,
            );
            XMLHttpRequest.prototype.send = new Proxy(
                XMLHttpRequest.prototype.send,
                sendHandler,
            );
            var nativeFetch = window.fetch;
            var fetchWrapper = async function fetchWrapper(
                target,
                thisArg,
                args,
            ) {
                var fetchURL =
                    args[0] instanceof Request ? args[0].url : args[0];
                if (typeof fetchURL !== "string" || fetchURL.length === 0) {
                    return Reflect.apply(target, thisArg, args);
                }
                if (urlMatchRegexp.test(fetchURL)) {
                    var response = await nativeFetch(...args);
                    var clonedResponse = response.clone();
                    var responseText = await response.text();
                    if (!propsToRemove && isM3U(responseText)) {
                        var message = `fetch URL: ${fetchURL}\nresponse text: ${responseText}`;
                        logMessage(source, message);
                        return clonedResponse;
                    }
                    if (isPruningNeeded(responseText, removeM3ULineRegexp)) {
                        var prunedText = pruneM3U(responseText);
                        hit(source);
                        return new Response(prunedText, {
                            status: response.status,
                            statusText: response.statusText,
                            headers: response.headers,
                        });
                    }
                    return clonedResponse;
                }
                return Reflect.apply(target, thisArg, args);
            };
            var fetchHandler = {
                apply: fetchWrapper,
            };
            window.fetch = new Proxy(window.fetch, fetchHandler);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function getXhrData(r, t, a, e, n) {
            return {
                method: r,
                url: t,
                async: a,
                user: e,
                password: n,
            };
        }
        function matchRequestProps(e, t, r) {
            if ("" === t || "*" === t) return true;
            var a,
                s = parseMatchProps(t);
            if (isValidParsedData(s)) {
                var n = getMatchPropsData(s);
                a = Object.keys(n).every(function (e) {
                    var t = n[e],
                        a = r[e];
                    return (
                        Object.prototype.hasOwnProperty.call(r, e) &&
                        "string" == typeof a &&
                        (null == t ? void 0 : t.test(a))
                    );
                });
            } else (logMessage(e, `Invalid parameter: ${t}`), (a = false));
            return a;
        }
        function getMatchPropsData(t) {
            var a = {};
            return (
                Object.keys(t).forEach(function (c) {
                    a[c] = toRegExp(t[c]);
                }),
                a
            );
        }
        function getRequestProps() {
            return [
                "url",
                "method",
                "headers",
                "body",
                "credentials",
                "cache",
                "redirect",
                "referrer",
                "referrerPolicy",
                "integrity",
                "keepalive",
                "signal",
                "mode",
            ];
        }
        function isValidParsedData(t) {
            return Object.values(t).every(function (t) {
                return isValidStrPattern(t);
            });
        }
        function parseMatchProps(e) {
            var r = {};
            return (
                e.split(" ").forEach(function (e) {
                    var n = e.indexOf(":"),
                        i = e.slice(0, n);
                    if (
                        (function (e) {
                            return getRequestProps().includes(e);
                        })(i)
                    ) {
                        var s = e.slice(n + 1);
                        r[i] = s;
                    } else r.url = e;
                }),
                r
            );
        }
        function isValidStrPattern(e) {
            var t,
                n = escapeRegExp(e);
            "/" === e[0] && "/" === e[e.length - 1] && (n = e.slice(1, -1));
            try {
                ((t = new RegExp(n)), (t = !0));
            } catch (e) {
                t = false;
            }
            return t;
        }
        function escapeRegExp(e) {
            return e.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            m3uPrune.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function metrikaYandexTag(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function metrikaYandexTag(source) {
            var asyncCallbackFromOptions = function asyncCallbackFromOptions(
                id,
                param,
            ) {
                var options =
                    arguments.length > 2 && arguments[2] !== undefined
                        ? arguments[2]
                        : {};
                var { callback: callback } = options;
                var { ctx: ctx } = options;
                if (typeof callback === "function") {
                    callback =
                        ctx !== undefined ? callback.bind(ctx) : callback;
                    setTimeout(function () {
                        return callback();
                    });
                }
            };
            var addFileExtension = noopFunc;
            var extLink = asyncCallbackFromOptions;
            var file = asyncCallbackFromOptions;
            var getClientID = function getClientID(id, cb) {
                if (!cb) {
                    return;
                }
                setTimeout(cb(null));
            };
            var hitFunc = asyncCallbackFromOptions;
            var notBounce = asyncCallbackFromOptions;
            var params = noopFunc;
            var reachGoal = function reachGoal(
                id,
                target,
                params,
                callback,
                ctx,
            ) {
                asyncCallbackFromOptions(null, null, {
                    callback: callback,
                    ctx: ctx,
                });
            };
            var setUserID = noopFunc;
            var userParams = noopFunc;
            var destruct = noopFunc;
            var api = {
                addFileExtension: addFileExtension,
                extLink: extLink,
                file: file,
                getClientID: getClientID,
                hit: hitFunc,
                notBounce: notBounce,
                params: params,
                reachGoal: reachGoal,
                setUserID: setUserID,
                userParams: userParams,
                destruct: destruct,
            };
            function init(id) {
                window[`yaCounter${id}`] = api;
                document.dispatchEvent(new Event(`yacounter${id}inited`));
            }
            function ym(id, funcName) {
                if (funcName === "init") {
                    return init(id);
                }
                for (
                    var _len = arguments.length,
                        args = new Array(_len > 2 ? _len - 2 : 0),
                        _key = 2;
                    _key < _len;
                    _key++
                ) {
                    args[_key - 2] = arguments[_key];
                }
                return api[funcName] && api[funcName](id, ...args);
            }
            if (typeof window.ym === "undefined") {
                window.ym = ym;
                ym.a = [];
            } else if (window.ym && window.ym.a) {
                ym.a = window.ym.a;
                window.ym = ym;
                window.ym.a.forEach(function (params) {
                    var id = params[0];
                    init(id);
                });
            }
            hit(source);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function noopFunc() {}
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            metrikaYandexTag.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function metrikaYandexWatch(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function metrikaYandexWatch(source) {
            var cbName = "yandex_metrika_callbacks";
            var asyncCallbackFromOptions = function asyncCallbackFromOptions() {
                var options =
                    arguments.length > 0 && arguments[0] !== undefined
                        ? arguments[0]
                        : {};
                var { callback: callback } = options;
                var { ctx: ctx } = options;
                if (typeof callback === "function") {
                    callback =
                        ctx !== undefined ? callback.bind(ctx) : callback;
                    setTimeout(function () {
                        return callback();
                    });
                }
            };
            function Metrika() {}
            Metrika.counters = noopArray;
            Metrika.prototype.addFileExtension = noopFunc;
            Metrika.prototype.getClientID = noopFunc;
            Metrika.prototype.setUserID = noopFunc;
            Metrika.prototype.userParams = noopFunc;
            Metrika.prototype.params = noopFunc;
            Metrika.prototype.counters = noopArray;
            Metrika.prototype.extLink = function (url, options) {
                asyncCallbackFromOptions(options);
            };
            Metrika.prototype.file = function (url, options) {
                asyncCallbackFromOptions(options);
            };
            Metrika.prototype.hit = function (url, options) {
                asyncCallbackFromOptions(options);
            };
            Metrika.prototype.reachGoal = function (target, params, cb, ctx) {
                asyncCallbackFromOptions({
                    callback: cb,
                    ctx: ctx,
                });
            };
            Metrika.prototype.notBounce = asyncCallbackFromOptions;
            if (window.Ya) {
                window.Ya.Metrika = Metrika;
            } else {
                window.Ya = {
                    Metrika: Metrika,
                };
            }
            if (window[cbName] && Array.isArray(window[cbName])) {
                window[cbName].forEach(function (func) {
                    if (typeof func === "function") {
                        func();
                    }
                });
            }
            hit(source);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function noopFunc() {}
        function noopArray() {
            return [];
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            metrikaYandexWatch.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function noProtectedAudience(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function noProtectedAudience(source) {
            if (Document instanceof Object === false) {
                return;
            }
            var protectedAudienceMethods = {
                joinAdInterestGroup: noopResolveVoid,
                runAdAuction: noopResolveNull,
                leaveAdInterestGroup: noopResolveVoid,
                clearOriginJoinedAdInterestGroups: noopResolveVoid,
                createAuctionNonce: noopStr,
                updateAdInterestGroups: noopFunc,
            };
            for (
                var _i = 0,
                    _Object$keys = Object.keys(protectedAudienceMethods);
                _i < _Object$keys.length;
                _i++
            ) {
                var key = _Object$keys[_i];
                var methodName = key;
                var prototype = Navigator.prototype;
                if (
                    !Object.prototype.hasOwnProperty.call(
                        prototype,
                        methodName,
                    ) ||
                    prototype[methodName] instanceof Function === false
                ) {
                    continue;
                }
                prototype[methodName] = protectedAudienceMethods[methodName];
            }
            hit(source);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function noopStr() {
            return "";
        }
        function noopFunc() {}
        function noopResolveVoid() {
            return Promise.resolve(void 0);
        }
        function noopResolveNull() {
            return Promise.resolve(null);
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            noProtectedAudience.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function noTopics(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function noTopics(source) {
            var TOPICS_PROPERTY_NAME = "browsingTopics";
            if (Document instanceof Object === false) {
                return;
            }
            if (
                !Object.prototype.hasOwnProperty.call(
                    Document.prototype,
                    TOPICS_PROPERTY_NAME,
                ) ||
                Document.prototype[TOPICS_PROPERTY_NAME] instanceof Function ===
                    false
            ) {
                return;
            }
            Document.prototype[TOPICS_PROPERTY_NAME] = function () {
                return noopPromiseResolve("[]");
            };
            hit(source);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function noopPromiseResolve() {
            var e =
                    arguments.length > 0 && void 0 !== arguments[0]
                        ? arguments[0]
                        : "{}",
                t =
                    arguments.length > 1 && void 0 !== arguments[1]
                        ? arguments[1]
                        : "",
                s =
                    arguments.length > 2 && void 0 !== arguments[2]
                        ? arguments[2]
                        : "basic";
            if ("undefined" != typeof Response) {
                var n = new Response(e, {
                    headers: {
                        "Content-Length": `${e.length}`,
                    },
                    status: 200,
                    statusText: "OK",
                });
                return (
                    "opaque" === s
                        ? Object.defineProperties(n, {
                              body: {
                                  value: null,
                              },
                              status: {
                                  value: 0,
                              },
                              ok: {
                                  value: false,
                              },
                              statusText: {
                                  value: "",
                              },
                              url: {
                                  value: "",
                              },
                              type: {
                                  value: s,
                              },
                          })
                        : Object.defineProperties(n, {
                              url: {
                                  value: t,
                              },
                              type: {
                                  value: s,
                              },
                          }),
                    Promise.resolve(n)
                );
            }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            noTopics.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function noeval(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function noeval(source) {
            window.eval = function evalWrapper(s) {
                hit(source);
                logMessage(source, `AdGuard has prevented eval:\n${s}`, true);
            }.bind();
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            noeval.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function nowebrtc(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function nowebrtc(source) {
            var propertyName = "";
            if (window.RTCPeerConnection) {
                propertyName = "RTCPeerConnection";
            } else if (window.webkitRTCPeerConnection) {
                propertyName = "webkitRTCPeerConnection";
            }
            if (propertyName === "") {
                return;
            }
            var rtcReplacement = function rtcReplacement(config) {
                var message = `Document tried to create an RTCPeerConnection: ${convertRtcConfigToString(config)}`;
                logMessage(source, message);
                hit(source);
            };
            rtcReplacement.prototype = {
                close: noopFunc,
                createDataChannel: noopFunc,
                createOffer: noopFunc,
                setRemoteDescription: noopFunc,
            };
            var rtc = window[propertyName];
            window[propertyName] = rtcReplacement;
            if (rtc.prototype) {
                rtc.prototype.createDataChannel = function (a, b) {
                    return {
                        close: noopFunc,
                        send: noopFunc,
                    };
                }.bind(null);
            }
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function noopFunc() {}
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function convertRtcConfigToString(e) {
            var t = "undefined";
            if (null === e) t = "null";
            else if (e instanceof Object) {
                var r = "iceServers",
                    n = "urls";
                Object.prototype.hasOwnProperty.call(e, r) &&
                    e[r] &&
                    Object.prototype.hasOwnProperty.call(e[r][0], n) &&
                    e[r][0][n] &&
                    (t = e[r][0][n].toString());
            }
            return t;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            nowebrtc.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function preventAddEventListener(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function preventAddEventListener(
            source,
            typeSearch,
            listenerSearch,
            additionalArgName,
            additionalArgValue,
        ) {
            var typeSearchRegexp = toRegExp(typeSearch);
            var listenerSearchRegexp = toRegExp(listenerSearch);
            var elementToMatch;
            if (additionalArgName) {
                if (additionalArgName !== "elements") {
                    logMessage(
                        source,
                        `Invalid "additionalArgName": ${additionalArgName}\nOnly "elements" is supported.`,
                    );
                    return;
                }
                if (!additionalArgValue) {
                    logMessage(source, '"additionalArgValue" is required.');
                    return;
                }
                elementToMatch = additionalArgValue;
            }
            var elementMatches = function elementMatches(element) {
                if (elementToMatch === undefined) {
                    return true;
                }
                if (elementToMatch === "window") {
                    return element === window;
                }
                if (elementToMatch === "document") {
                    return element === document;
                }
                if (
                    element &&
                    element.matches &&
                    element.matches(elementToMatch)
                ) {
                    return true;
                }
                return false;
            };
            var nativeAddEventListener =
                window.EventTarget.prototype.addEventListener;
            function addEventListenerWrapper(type, listener) {
                var _this$constructor;
                var shouldPrevent = false;
                if (validateType(type) && validateListener(listener)) {
                    shouldPrevent =
                        typeSearchRegexp.test(type.toString()) &&
                        listenerSearchRegexp.test(listenerToString(listener)) &&
                        elementMatches(this);
                }
                if (shouldPrevent) {
                    hit(source);
                    return undefined;
                }
                var context = this;
                if (
                    this &&
                    ((_this$constructor = this.constructor) === null ||
                    _this$constructor === void 0
                        ? void 0
                        : _this$constructor.name) === "Window" &&
                    this !== window
                ) {
                    context = window;
                }
                for (
                    var _len = arguments.length,
                        args = new Array(_len > 2 ? _len - 2 : 0),
                        _key = 2;
                    _key < _len;
                    _key++
                ) {
                    args[_key - 2] = arguments[_key];
                }
                return nativeAddEventListener.apply(context, [
                    type,
                    listener,
                    ...args,
                ]);
            }
            var descriptor = {
                configurable: true,
                set: function set() {},
                get: function get() {
                    return addEventListenerWrapper;
                },
            };
            Object.defineProperty(
                window.EventTarget.prototype,
                "addEventListener",
                descriptor,
            );
            Object.defineProperty(window, "addEventListener", descriptor);
            Object.defineProperty(document, "addEventListener", descriptor);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function validateType(e) {
            return void 0 !== e;
        }
        function validateListener(n) {
            return (
                void 0 !== n &&
                ("function" == typeof n ||
                    ("object" == typeof n &&
                        null !== n &&
                        "handleEvent" in n &&
                        "function" == typeof n.handleEvent))
            );
        }
        function listenerToString(n) {
            return "function" == typeof n
                ? n.toString()
                : n.handleEvent.toString();
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            preventAddEventListener.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function preventAdfly(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function preventAdfly(source) {
            var isDigit = function isDigit(data) {
                return /^\d$/.test(data);
            };
            var handler = function handler(encodedURL) {
                var evenChars = "";
                var oddChars = "";
                for (var i = 0; i < encodedURL.length; i += 1) {
                    if (i % 2 === 0) {
                        evenChars += encodedURL.charAt(i);
                    } else {
                        oddChars = encodedURL.charAt(i) + oddChars;
                    }
                }
                var data = (evenChars + oddChars).split("");
                for (var _i = 0; _i < data.length; _i += 1) {
                    if (isDigit(data[_i])) {
                        for (var ii = _i + 1; ii < data.length; ii += 1) {
                            if (isDigit(data[ii])) {
                                var temp =
                                    parseInt(data[_i], 10) ^
                                    parseInt(data[ii], 10);
                                if (temp < 10) {
                                    data[_i] = temp.toString();
                                }
                                _i = ii;
                                break;
                            }
                        }
                    }
                }
                data = data.join("");
                var decodedURL = window.atob(data).slice(16, -16);
                if (window.stop) {
                    window.stop();
                }
                window.onbeforeunload = null;
                window.location.href = decodedURL;
            };
            var val;
            var applyHandler = true;
            var result = setPropertyAccess(window, "ysmm", {
                configurable: false,
                set: function set(value) {
                    if (applyHandler) {
                        applyHandler = false;
                        try {
                            if (typeof value === "string") {
                                handler(value);
                            }
                        } catch (err) {}
                    }
                    val = value;
                },
                get: function get() {
                    return val;
                },
            });
            if (result) {
                hit(source);
            } else {
                logMessage(source, "Failed to set up prevent-adfly scriptlet");
            }
        }
        function setPropertyAccess(e, r, t) {
            var c = Object.getOwnPropertyDescriptor(e, r);
            return (
                !(c && !c.configurable) &&
                (Object.defineProperty(e, r, t), true)
            );
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            preventAdfly.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function preventBab(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function preventBab(source) {
            var nativeSetTimeout = window.setTimeout;
            var babRegex = /\.bab_elementid.$/;
            var timeoutWrapper = function timeoutWrapper(callback) {
                if (typeof callback !== "string" || !babRegex.test(callback)) {
                    for (
                        var _len = arguments.length,
                            args = new Array(_len > 1 ? _len - 1 : 0),
                            _key = 1;
                        _key < _len;
                        _key++
                    ) {
                        args[_key - 1] = arguments[_key];
                    }
                    return nativeSetTimeout.apply(window, [callback, ...args]);
                }
                hit(source);
            };
            window.setTimeout = timeoutWrapper;
            var signatures = [
                ["blockadblock"],
                ["babasbm"],
                [/getItem\('babn'\)/],
                [
                    "getElementById",
                    "String.fromCharCode",
                    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789",
                    "charAt",
                    "DOMContentLoaded",
                    "AdBlock",
                    "addEventListener",
                    "doScroll",
                    "fromCharCode",
                    "<<2|r>>4",
                    "sessionStorage",
                    "clientWidth",
                    "localStorage",
                    "Math",
                    "random",
                ],
            ];
            var check = function check(str) {
                if (typeof str !== "string") {
                    return false;
                }
                for (var i = 0; i < signatures.length; i += 1) {
                    var tokens = signatures[i];
                    var match = 0;
                    for (var j = 0; j < tokens.length; j += 1) {
                        var token = tokens[j];
                        var found =
                            token instanceof RegExp
                                ? token.test(str)
                                : str.includes(token);
                        if (found) {
                            match += 1;
                        }
                    }
                    if (match / tokens.length >= 0.8) {
                        return true;
                    }
                }
                return false;
            };
            var nativeEval = window.eval;
            var evalWrapper = function evalWrapper(str) {
                if (!check(str)) {
                    return nativeEval(str);
                }
                hit(source);
                var bodyEl = document.body;
                if (bodyEl) {
                    bodyEl.style.removeProperty("visibility");
                }
                var el = document.getElementById("babasbmsgx");
                if (el) {
                    el.parentNode.removeChild(el);
                }
            };
            window.eval = evalWrapper.bind(window);
            window.eval.toString = nativeEval.toString.bind(nativeEval);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            preventBab.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function preventCanvas(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function preventCanvas(source, contextType) {
            var handlerWrapper = function handlerWrapper(
                target,
                thisArg,
                argumentsList,
            ) {
                var type = argumentsList[0];
                var shouldPrevent = false;
                if (!contextType) {
                    shouldPrevent = true;
                } else if (isValidMatchStr(contextType)) {
                    var {
                        isInvertedMatch: isInvertedMatch,
                        matchRegexp: matchRegexp,
                    } = parseMatchArg(contextType);
                    shouldPrevent = matchRegexp.test(type) !== isInvertedMatch;
                } else {
                    logMessage(
                        source,
                        `Invalid contextType parameter: ${contextType}`,
                    );
                    shouldPrevent = false;
                }
                if (shouldPrevent) {
                    hit(source);
                    return null;
                }
                return Reflect.apply(target, thisArg, argumentsList);
            };
            var canvasHandler = {
                apply: handlerWrapper,
            };
            window.HTMLCanvasElement.prototype.getContext = new Proxy(
                window.HTMLCanvasElement.prototype.getContext,
                canvasHandler,
            );
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function parseMatchArg(t) {
            var e = !!t && (null == t ? void 0 : t.startsWith("!")),
                a = e ? t.slice(1) : t;
            return {
                isInvertedMatch: e,
                matchRegexp: toRegExp(a),
                matchValue: a,
            };
        }
        function isValidMatchStr(t) {
            var i = t;
            return (
                null != t && t.startsWith("!") && (i = t.slice(1)),
                isValidStrPattern(i)
            );
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function escapeRegExp(e) {
            return e.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        }
        function isValidStrPattern(e) {
            var t,
                n = escapeRegExp(e);
            "/" === e[0] && "/" === e[e.length - 1] && (n = e.slice(1, -1));
            try {
                ((t = new RegExp(n)), (t = !0));
            } catch (e) {
                t = false;
            }
            return t;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            preventCanvas.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function preventElementSrcLoading(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function preventElementSrcLoading(source, tagName, match) {
            if (
                typeof Proxy === "undefined" ||
                typeof Reflect === "undefined"
            ) {
                return;
            }
            var srcMockData = {
                script: "data:text/javascript;base64,KCk9Pnt9",
                img: "data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==",
                iframe: "data:text/html;base64, PGRpdj48L2Rpdj4=",
                link: "data:text/plain;base64,",
            };
            var instance;
            if (tagName === "script") {
                instance = HTMLScriptElement;
            } else if (tagName === "img") {
                instance = HTMLImageElement;
            } else if (tagName === "iframe") {
                instance = HTMLIFrameElement;
            } else if (tagName === "link") {
                instance = HTMLLinkElement;
            } else {
                return;
            }
            var policy = getTrustedTypesApi(source);
            var SOURCE_PROPERTY_NAME = tagName === "link" ? "href" : "src";
            var ONERROR_PROPERTY_NAME = "onerror";
            var searchRegexp = toRegExp(match);
            var setMatchedAttribute = function setMatchedAttribute(elem) {
                return elem.setAttribute(source.name, "matched");
            };
            var setAttributeWrapper = function setAttributeWrapper(
                target,
                thisArg,
                args,
            ) {
                if (!args[0] || !args[1]) {
                    return Reflect.apply(target, thisArg, args);
                }
                var nodeName = thisArg.nodeName.toLowerCase();
                var attrName = args[0].toLowerCase();
                var attrValue = args[1];
                var isMatched =
                    attrName === SOURCE_PROPERTY_NAME &&
                    tagName.toLowerCase() === nodeName &&
                    srcMockData[nodeName] &&
                    searchRegexp.test(attrValue);
                if (!isMatched) {
                    return Reflect.apply(target, thisArg, args);
                }
                hit(source);
                setMatchedAttribute(thisArg);
                return Reflect.apply(target, thisArg, [
                    attrName,
                    srcMockData[nodeName],
                ]);
            };
            var setAttributeHandler = {
                apply: setAttributeWrapper,
            };
            instance.prototype.setAttribute = new Proxy(
                Element.prototype.setAttribute,
                setAttributeHandler,
            );
            var origSrcDescriptor = safeGetDescriptor(
                instance.prototype,
                SOURCE_PROPERTY_NAME,
            );
            if (!origSrcDescriptor) {
                return;
            }
            Object.defineProperty(instance.prototype, SOURCE_PROPERTY_NAME, {
                enumerable: true,
                configurable: true,
                get() {
                    return origSrcDescriptor.get.call(this);
                },
                set(urlValue) {
                    var nodeName = this.nodeName.toLowerCase();
                    var isMatched =
                        tagName.toLowerCase() === nodeName &&
                        srcMockData[nodeName] &&
                        searchRegexp.test(urlValue);
                    if (!isMatched) {
                        origSrcDescriptor.set.call(this, urlValue);
                        return true;
                    }
                    var mockData = srcMockData[nodeName];
                    if (
                        typeof TrustedScriptURL !== "undefined" &&
                        policy !== null &&
                        policy !== void 0 &&
                        policy.isSupported &&
                        urlValue instanceof TrustedScriptURL
                    ) {
                        mockData = policy.createScriptURL(mockData);
                    }
                    setMatchedAttribute(this);
                    origSrcDescriptor.set.call(this, mockData);
                    hit(source);
                },
            });
            var origOnerrorDescriptor = safeGetDescriptor(
                HTMLElement.prototype,
                ONERROR_PROPERTY_NAME,
            );
            if (!origOnerrorDescriptor) {
                return;
            }
            Object.defineProperty(
                HTMLElement.prototype,
                ONERROR_PROPERTY_NAME,
                {
                    enumerable: true,
                    configurable: true,
                    get() {
                        return origOnerrorDescriptor.get.call(this);
                    },
                    set(cb) {
                        var isMatched =
                            this.getAttribute(source.name) === "matched";
                        if (!isMatched) {
                            origOnerrorDescriptor.set.call(this, cb);
                            return true;
                        }
                        origOnerrorDescriptor.set.call(this, noopFunc);
                        return true;
                    },
                },
            );
            var addEventListenerWrapper = function addEventListenerWrapper(
                target,
                thisArg,
                args,
            ) {
                if (!args[0] || !args[1] || !thisArg) {
                    return Reflect.apply(target, thisArg, args);
                }
                var eventName = args[0];
                var isMatched =
                    typeof thisArg.getAttribute === "function" &&
                    thisArg.getAttribute(source.name) === "matched" &&
                    eventName === "error";
                if (isMatched) {
                    return Reflect.apply(target, thisArg, [
                        eventName,
                        noopFunc,
                    ]);
                }
                return Reflect.apply(target, thisArg, args);
            };
            var addEventListenerHandler = {
                apply: addEventListenerWrapper,
            };
            EventTarget.prototype.addEventListener = new Proxy(
                EventTarget.prototype.addEventListener,
                addEventListenerHandler,
            );
            var preventInlineOnerror = function preventInlineOnerror(
                tagName,
                src,
            ) {
                window.addEventListener(
                    "error",
                    function (event) {
                        if (
                            !event.target ||
                            !event.target.nodeName ||
                            event.target.nodeName.toLowerCase() !== tagName ||
                            !event.target.src ||
                            !src.test(event.target.src)
                        ) {
                            return;
                        }
                        hit(source);
                        if (typeof event.target.onload === "function") {
                            event.target.onerror = event.target.onload;
                            return;
                        }
                        event.target.onerror = noopFunc;
                    },
                    true,
                );
            };
            preventInlineOnerror(tagName, searchRegexp);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function safeGetDescriptor(r, e) {
            var t = Object.getOwnPropertyDescriptor(r, e);
            return t && t.configurable ? t : null;
        }
        function noopFunc() {}
        function getTrustedTypesApi(t) {
            var r,
                e =
                    null == t || null === (r = t.api) || void 0 === r
                        ? void 0
                        : r.policy;
            if (e) return e;
            var n = "AGPolicy",
                i = window.trustedTypes,
                u = !!i,
                c = {
                    HTML: "TrustedHTML",
                    Script: "TrustedScript",
                    ScriptURL: "TrustedScriptURL",
                };
            if (!u)
                return {
                    name: n,
                    isSupported: u,
                    TrustedType: c,
                    createHTML: function createHTML(t) {
                        return t;
                    },
                    createScript: function createScript(t) {
                        return t;
                    },
                    createScriptURL: function createScriptURL(t) {
                        return t;
                    },
                    create: function create(t, r) {
                        return r;
                    },
                    getAttributeType: function getAttributeType() {
                        return null;
                    },
                    convertAttributeToTrusted:
                        function convertAttributeToTrusted(t, r, e) {
                            return e;
                        },
                    getPropertyType: function getPropertyType() {
                        return null;
                    },
                    convertPropertyToTrusted: function convertPropertyToTrusted(
                        t,
                        r,
                        e,
                    ) {
                        return e;
                    },
                    isHTML: function isHTML() {
                        return false;
                    },
                    isScript: function isScript() {
                        return false;
                    },
                    isScriptURL: function isScriptURL() {
                        return false;
                    },
                };
            var o = i.createPolicy(n, {
                    createHTML: function createHTML(t) {
                        return t;
                    },
                    createScript: function createScript(t) {
                        return t;
                    },
                    createScriptURL: function createScriptURL(t) {
                        return t;
                    },
                }),
                createHTML = function createHTML(t) {
                    return o.createHTML(t);
                },
                createScript = function createScript(t) {
                    return o.createScript(t);
                },
                createScriptURL = function createScriptURL(t) {
                    return o.createScriptURL(t);
                },
                create = function create(t, r) {
                    switch (t) {
                        case c.HTML:
                            return createHTML(r);
                        case c.Script:
                            return createScript(r);
                        case c.ScriptURL:
                            return createScriptURL(r);
                        default:
                            return r;
                    }
                },
                p = i.getAttributeType.bind(i),
                T = i.getPropertyType.bind(i),
                s = i.isHTML.bind(i),
                a = i.isScript.bind(i),
                f = i.isScriptURL.bind(i);
            return {
                name: n,
                isSupported: u,
                TrustedType: c,
                createHTML: createHTML,
                createScript: createScript,
                createScriptURL: createScriptURL,
                create: create,
                getAttributeType: p,
                convertAttributeToTrusted: function convertAttributeToTrusted(
                    t,
                    r,
                    e,
                    n,
                    i,
                ) {
                    var u = p(t, r, n, i);
                    return u ? create(u, e) : e;
                },
                getPropertyType: T,
                convertPropertyToTrusted: function convertPropertyToTrusted(
                    t,
                    r,
                    e,
                    n,
                ) {
                    var i = T(t, r, n);
                    return i ? create(i, e) : e;
                },
                isHTML: s,
                isScript: a,
                isScriptURL: f,
            };
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            preventElementSrcLoading.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function preventEvalIf(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function preventEvalIf(source, search) {
            var searchRegexp = toRegExp(search);
            var nativeEval = window.eval;
            window.eval = function (payload) {
                if (!searchRegexp.test(payload.toString())) {
                    return nativeEval.call(window, payload);
                }
                hit(source);
                return undefined;
            }.bind(window);
            window.eval.toString = nativeEval.toString.bind(nativeEval);
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            preventEvalIf.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function preventFab(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function preventFab(source) {
            hit(source);
            var Fab = function Fab() {};
            Fab.prototype.check = noopFunc;
            Fab.prototype.clearEvent = noopFunc;
            Fab.prototype.emitEvent = noopFunc;
            Fab.prototype.on = function (a, b) {
                if (!a) {
                    b();
                }
                return this;
            };
            Fab.prototype.onDetected = noopThis;
            Fab.prototype.onNotDetected = function (a) {
                a();
                return this;
            };
            Fab.prototype.setOption = noopFunc;
            Fab.prototype.options = {
                set: noopFunc,
                get: noopFunc,
            };
            var fab = new Fab();
            var getSetFab = {
                get() {
                    return Fab;
                },
                set() {},
            };
            var getsetfab = {
                get() {
                    return fab;
                },
                set() {},
            };
            if (Object.prototype.hasOwnProperty.call(window, "FuckAdBlock")) {
                window.FuckAdBlock = Fab;
            } else {
                Object.defineProperty(window, "FuckAdBlock", getSetFab);
            }
            if (Object.prototype.hasOwnProperty.call(window, "BlockAdBlock")) {
                window.BlockAdBlock = Fab;
            } else {
                Object.defineProperty(window, "BlockAdBlock", getSetFab);
            }
            if (Object.prototype.hasOwnProperty.call(window, "SniffAdBlock")) {
                window.SniffAdBlock = Fab;
            } else {
                Object.defineProperty(window, "SniffAdBlock", getSetFab);
            }
            if (Object.prototype.hasOwnProperty.call(window, "fuckAdBlock")) {
                window.fuckAdBlock = fab;
            } else {
                Object.defineProperty(window, "fuckAdBlock", getsetfab);
            }
            if (Object.prototype.hasOwnProperty.call(window, "blockAdBlock")) {
                window.blockAdBlock = fab;
            } else {
                Object.defineProperty(window, "blockAdBlock", getsetfab);
            }
            if (Object.prototype.hasOwnProperty.call(window, "sniffAdBlock")) {
                window.sniffAdBlock = fab;
            } else {
                Object.defineProperty(window, "sniffAdBlock", getsetfab);
            }
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function noopFunc() {}
        function noopThis() {
            return this;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            preventFab.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function preventFetch(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function preventFetch(source, propsToMatch) {
            var responseBody =
                arguments.length > 2 && arguments[2] !== undefined
                    ? arguments[2]
                    : "emptyObj";
            var responseType = arguments.length > 3 ? arguments[3] : undefined;
            if (
                typeof fetch === "undefined" ||
                typeof Proxy === "undefined" ||
                typeof Response === "undefined"
            ) {
                return;
            }
            var nativeRequestClone = Request.prototype.clone;
            var strResponseBody;
            if (responseBody === "" || responseBody === "emptyObj") {
                strResponseBody = "{}";
            } else if (responseBody === "emptyArr") {
                strResponseBody = "[]";
            } else if (responseBody === "emptyStr") {
                strResponseBody = "";
            } else if (
                responseBody === "true" ||
                responseBody.match(/^length:\d+-\d+$/)
            ) {
                strResponseBody = generateRandomResponse(responseBody);
            } else {
                logMessage(
                    source,
                    `Invalid responseBody parameter: '${responseBody}'`,
                );
                return;
            }
            var isResponseTypeSpecified = typeof responseType !== "undefined";
            var isResponseTypeSupported = function isResponseTypeSupported(
                responseType,
            ) {
                var SUPPORTED_TYPES = ["basic", "cors", "opaque"];
                return SUPPORTED_TYPES.includes(responseType);
            };
            if (
                isResponseTypeSpecified &&
                !isResponseTypeSupported(responseType)
            ) {
                logMessage(
                    source,
                    `Invalid responseType parameter: '${responseType}'`,
                );
                return;
            }
            var getResponseType = function getResponseType(request) {
                try {
                    var { mode: mode } = request;
                    if (
                        mode === undefined ||
                        mode === "cors" ||
                        mode === "no-cors"
                    ) {
                        var fetchURL = new URL(request.url);
                        if (fetchURL.origin === document.location.origin) {
                            return "basic";
                        }
                        return mode === "no-cors" ? "opaque" : "cors";
                    }
                } catch (error) {
                    logMessage(
                        source,
                        `Could not determine response type: ${error}`,
                    );
                }
                return undefined;
            };
            var handlerWrapper = async function handlerWrapper(
                target,
                thisArg,
                args,
            ) {
                var shouldPrevent = false;
                var fetchData = getFetchData(args, nativeRequestClone);
                if (typeof propsToMatch === "undefined") {
                    logMessage(
                        source,
                        `fetch( ${objectToString(fetchData)} )`,
                        true,
                    );
                    hit(source);
                    return Reflect.apply(target, thisArg, args);
                }
                shouldPrevent = matchRequestProps(
                    source,
                    propsToMatch,
                    fetchData,
                );
                if (shouldPrevent) {
                    hit(source);
                    var finalResponseType;
                    try {
                        finalResponseType =
                            responseType || getResponseType(fetchData);
                        var origResponse = await Reflect.apply(
                            target,
                            thisArg,
                            args,
                        );
                        if (!origResponse.ok) {
                            return noopPromiseResolve(
                                strResponseBody,
                                fetchData.url,
                                finalResponseType,
                            );
                        }
                        return modifyResponse(origResponse, {
                            body: strResponseBody,
                            type: finalResponseType,
                        });
                    } catch (ex) {
                        return noopPromiseResolve(
                            strResponseBody,
                            fetchData.url,
                            finalResponseType,
                        );
                    }
                }
                return Reflect.apply(target, thisArg, args);
            };
            var fetchHandler = {
                apply: handlerWrapper,
            };
            fetch = new Proxy(fetch, fetchHandler);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function getFetchData(e, t) {
            var a,
                c,
                n = {},
                r = e[0];
            if (r instanceof Request) {
                var u = t.call(r),
                    f = getRequestData(u);
                ((a = f.url), (c = f));
            } else ((a = r), (c = e[1]));
            ((n.url = a), c instanceof Object) &&
                Object.keys(c).forEach(function (e) {
                    n[e] = c[e];
                });
            return n;
        }
        function objectToString(t) {
            return t && "object" == typeof t
                ? isEmptyObject(t)
                    ? "{}"
                    : Object.entries(t)
                          .map(function (t) {
                              var n = t[0],
                                  e = t[1],
                                  o = e;
                              return (
                                  e instanceof Object &&
                                      (o = `{ ${objectToString(e)} }`),
                                  `${n}:"${o}"`
                              );
                          })
                          .join(" ")
                : String(t);
        }
        function matchRequestProps(e, t, r) {
            if ("" === t || "*" === t) return true;
            var a,
                s = parseMatchProps(t);
            if (isValidParsedData(s)) {
                var n = getMatchPropsData(s);
                a = Object.keys(n).every(function (e) {
                    var t = n[e],
                        a = r[e];
                    return (
                        Object.prototype.hasOwnProperty.call(r, e) &&
                        "string" == typeof a &&
                        (null == t ? void 0 : t.test(a))
                    );
                });
            } else (logMessage(e, `Invalid parameter: ${t}`), (a = false));
            return a;
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function noopPromiseResolve() {
            var e =
                    arguments.length > 0 && void 0 !== arguments[0]
                        ? arguments[0]
                        : "{}",
                t =
                    arguments.length > 1 && void 0 !== arguments[1]
                        ? arguments[1]
                        : "",
                s =
                    arguments.length > 2 && void 0 !== arguments[2]
                        ? arguments[2]
                        : "basic";
            if ("undefined" != typeof Response) {
                var n = new Response(e, {
                    headers: {
                        "Content-Length": `${e.length}`,
                    },
                    status: 200,
                    statusText: "OK",
                });
                return (
                    "opaque" === s
                        ? Object.defineProperties(n, {
                              body: {
                                  value: null,
                              },
                              status: {
                                  value: 0,
                              },
                              ok: {
                                  value: false,
                              },
                              statusText: {
                                  value: "",
                              },
                              url: {
                                  value: "",
                              },
                              type: {
                                  value: s,
                              },
                          })
                        : Object.defineProperties(n, {
                              url: {
                                  value: t,
                              },
                              type: {
                                  value: s,
                              },
                          }),
                    Promise.resolve(n)
                );
            }
        }
        function modifyResponse(e) {
            var t,
                s =
                    arguments.length > 1 && void 0 !== arguments[1]
                        ? arguments[1]
                        : {
                              body: "{}",
                          },
                u = {};
            null == e ||
                null === (t = e.headers) ||
                void 0 === t ||
                t.forEach(function (e, t) {
                    u[t] = e;
                });
            var n = new Response(s.body, {
                status: e.status,
                statusText: e.statusText,
                headers: u,
            });
            return (
                Object.defineProperties(n, {
                    url: {
                        value: e.url,
                    },
                    type: {
                        value: s.type || e.type,
                    },
                }),
                n
            );
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function isValidStrPattern(e) {
            var t,
                n = escapeRegExp(e);
            "/" === e[0] && "/" === e[e.length - 1] && (n = e.slice(1, -1));
            try {
                ((t = new RegExp(n)), (t = !0));
            } catch (e) {
                t = false;
            }
            return t;
        }
        function escapeRegExp(e) {
            return e.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        }
        function isEmptyObject(t) {
            return 0 === Object.keys(t).length && !t.prototype;
        }
        function getRequestData(t) {
            var e = getRequestProps().map(function (e) {
                return [e, t[e]];
            });
            return Object.fromEntries(e);
        }
        function getRequestProps() {
            return [
                "url",
                "method",
                "headers",
                "body",
                "credentials",
                "cache",
                "redirect",
                "referrer",
                "referrerPolicy",
                "integrity",
                "keepalive",
                "signal",
                "mode",
            ];
        }
        function parseMatchProps(e) {
            var r = {};
            return (
                e.split(" ").forEach(function (e) {
                    var n = e.indexOf(":"),
                        i = e.slice(0, n);
                    if (
                        (function (e) {
                            return getRequestProps().includes(e);
                        })(i)
                    ) {
                        var s = e.slice(n + 1);
                        r[i] = s;
                    } else r.url = e;
                }),
                r
            );
        }
        function isValidParsedData(t) {
            return Object.values(t).every(function (t) {
                return isValidStrPattern(t);
            });
        }
        function getMatchPropsData(t) {
            var a = {};
            return (
                Object.keys(t).forEach(function (c) {
                    a[c] = toRegExp(t[c]);
                }),
                a
            );
        }
        function generateRandomResponse(e) {
            var t = e;
            if ("true" === t)
                return (t = Math.random().toString(36).slice(-10));
            t = t.replace("length:", "");
            if (!/^\d+-\d+$/.test(t)) return null;
            var n = getNumberFromString(t.split("-")[0]),
                r = getNumberFromString(t.split("-")[1]);
            if (!nativeIsFinite(n) || !nativeIsFinite(r)) return null;
            if (n > r) {
                var i = n;
                ((n = r), (r = i));
            }
            if (r > 5e5) return null;
            var a = getRandomIntInclusive(n, r);
            return (t = getRandomStrByLength(a));
        }
        function nativeIsFinite(i) {
            return (Number.isFinite || window.isFinite)(i);
        }
        function nativeIsNaN(N) {
            return (Number.isNaN || window.isNaN)(N);
        }
        function getNumberFromString(n) {
            var r = parseInt(n, 10);
            return nativeIsNaN(r) ? null : r;
        }
        function getRandomIntInclusive(t, n) {
            return (
                (t = Math.ceil(t)),
                (n = Math.floor(n)),
                Math.floor(Math.random() * (n - t + 1) + t)
            );
        }
        function getRandomStrByLength(r) {
            for (
                var t = "",
                    a =
                        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()_+=~",
                    n = 0;
                n < r;
                n += 1
            )
                t += a.charAt(Math.floor(76 * Math.random()));
            return t;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            preventFetch.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function preventPopadsNet(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function preventPopadsNet(source) {
            var rid = randomId();
            var throwError = function throwError() {
                throw new ReferenceError(rid);
            };
            delete window.PopAds;
            delete window.popns;
            Object.defineProperties(window, {
                PopAds: {
                    set: throwError,
                },
                popns: {
                    set: throwError,
                },
            });
            window.onerror = createOnErrorHandler(rid).bind();
            hit(source);
        }
        function createOnErrorHandler(r) {
            var n = window.onerror;
            return function (e) {
                if ("string" == typeof e && e.includes(r)) return true;
                if (n instanceof Function) {
                    for (
                        var t = arguments.length,
                            o = new Array(t > 1 ? t - 1 : 0),
                            i = 1;
                        i < t;
                        i++
                    )
                        o[i - 1] = arguments[i];
                    return n.apply(window, [e, ...o]);
                }
                return false;
            };
        }
        function randomId() {
            return Math.random().toString(36).slice(2, 9);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            preventPopadsNet.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function preventRefresh(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function preventRefresh(source, delaySec) {
            var getMetaElements = function getMetaElements() {
                var metaNodes = [];
                try {
                    metaNodes = document.querySelectorAll(
                        'meta[http-equiv="refresh" i][content]',
                    );
                } catch (e) {
                    try {
                        metaNodes = document.querySelectorAll(
                            'meta[http-equiv="refresh"][content]',
                        );
                    } catch (e) {
                        logMessage(source, e);
                    }
                }
                return Array.from(metaNodes);
            };
            var getMetaContentDelay = function getMetaContentDelay(
                metaElements,
            ) {
                var delays = metaElements
                    .map(function (meta) {
                        var contentString = meta.getAttribute("content");
                        if (contentString.length === 0) {
                            return null;
                        }
                        var contentDelay;
                        var limiterIndex = contentString.indexOf(";");
                        if (limiterIndex !== -1) {
                            var delaySubstring = contentString.substring(
                                0,
                                limiterIndex,
                            );
                            contentDelay = getNumberFromString(delaySubstring);
                        } else {
                            contentDelay = getNumberFromString(contentString);
                        }
                        return contentDelay;
                    })
                    .filter(function (delay) {
                        return delay !== null;
                    });
                if (!delays.length) {
                    return null;
                }
                var minDelay = delays.reduce(function (a, b) {
                    return Math.min(a, b);
                });
                return minDelay;
            };
            var stop = function stop() {
                var metaElements = getMetaElements();
                if (metaElements.length === 0) {
                    return;
                }
                var secondsToRun = getNumberFromString(delaySec);
                if (secondsToRun === null) {
                    secondsToRun = getMetaContentDelay(metaElements);
                }
                if (secondsToRun === null) {
                    return;
                }
                var delayMs = secondsToRun * 1e3;
                setTimeout(function () {
                    window.stop();
                    hit(source);
                }, delayMs);
            };
            if (document.readyState === "loading") {
                document.addEventListener("DOMContentLoaded", stop, {
                    once: true,
                });
            } else {
                stop();
            }
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function getNumberFromString(n) {
            var r = parseInt(n, 10);
            return nativeIsNaN(r) ? null : r;
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function nativeIsNaN(N) {
            return (Number.isNaN || window.isNaN)(N);
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            preventRefresh.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function preventRequestAnimationFrame(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function preventRequestAnimationFrame(source, match) {
            var nativeRequestAnimationFrame = window.requestAnimationFrame;
            var shouldLog = typeof match === "undefined";
            var { isInvertedMatch: isInvertedMatch, matchRegexp: matchRegexp } =
                parseMatchArg(match);
            var rafWrapper = function rafWrapper(callback) {
                var shouldPrevent = false;
                if (shouldLog) {
                    hit(source);
                    logMessage(
                        source,
                        `requestAnimationFrame(${String(callback)})`,
                        true,
                    );
                } else if (
                    isValidCallback(callback) &&
                    isValidStrPattern(match)
                ) {
                    shouldPrevent =
                        matchRegexp.test(callback.toString()) !==
                        isInvertedMatch;
                }
                if (shouldPrevent) {
                    hit(source);
                    return nativeRequestAnimationFrame(noopFunc);
                }
                for (
                    var _len = arguments.length,
                        args = new Array(_len > 1 ? _len - 1 : 0),
                        _key = 1;
                    _key < _len;
                    _key++
                ) {
                    args[_key - 1] = arguments[_key];
                }
                return nativeRequestAnimationFrame.apply(window, [
                    callback,
                    ...args,
                ]);
            };
            window.requestAnimationFrame = rafWrapper;
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function noopFunc() {}
        function parseMatchArg(t) {
            var e = !!t && (null == t ? void 0 : t.startsWith("!")),
                a = e ? t.slice(1) : t;
            return {
                isInvertedMatch: e,
                matchRegexp: toRegExp(a),
                matchValue: a,
            };
        }
        function isValidStrPattern(e) {
            var t,
                n = escapeRegExp(e);
            "/" === e[0] && "/" === e[e.length - 1] && (n = e.slice(1, -1));
            try {
                ((t = new RegExp(n)), (t = !0));
            } catch (e) {
                t = false;
            }
            return t;
        }
        function isValidCallback(n) {
            return n instanceof Function || "string" == typeof n;
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function escapeRegExp(e) {
            return e.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            preventRequestAnimationFrame.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function preventSetInterval(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function preventSetInterval(source, matchCallback, matchDelay) {
            var shouldLog =
                typeof matchCallback === "undefined" &&
                typeof matchDelay === "undefined";
            var handlerWrapper = function handlerWrapper(
                target,
                thisArg,
                args,
            ) {
                var callback = args[0];
                var delay = args[1];
                var shouldPrevent = false;
                if (shouldLog) {
                    hit(source);
                    logMessage(
                        source,
                        `setInterval(${String(callback)}, ${delay})`,
                        true,
                    );
                } else {
                    shouldPrevent = isPreventionNeeded({
                        callback: callback,
                        delay: delay,
                        matchCallback: matchCallback,
                        matchDelay: matchDelay,
                    });
                }
                if (shouldPrevent) {
                    hit(source);
                    args[0] = noopFunc;
                }
                return target.apply(thisArg, args);
            };
            var setIntervalHandler = {
                apply: handlerWrapper,
            };
            window.setInterval = new Proxy(
                window.setInterval,
                setIntervalHandler,
            );
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function noopFunc() {}
        function isPreventionNeeded(a) {
            var { callback: e, delay: t, matchCallback: r, matchDelay: l } = a;
            if (!isValidCallback(e)) return false;
            if (!isValidMatchStr(r) || (l && !isValidMatchNumber(l)))
                return false;
            var { isInvertedMatch: c, matchRegexp: i } = parseMatchArg(r),
                { isInvertedDelayMatch: n, delayMatch: s } = parseDelayArg(l),
                d = parseRawDelay(t),
                h = String(e);
            return null === s
                ? i.test(h) !== c
                : r
                  ? i.test(h) !== c && (d === s) !== n
                  : (d === s) !== n;
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function nativeIsNaN(N) {
            return (Number.isNaN || window.isNaN)(N);
        }
        function parseMatchArg(t) {
            var e = !!t && (null == t ? void 0 : t.startsWith("!")),
                a = e ? t.slice(1) : t;
            return {
                isInvertedMatch: e,
                matchRegexp: toRegExp(a),
                matchValue: a,
            };
        }
        function parseDelayArg(a) {
            var e = null == a ? void 0 : a.startsWith("!"),
                t = e ? a.slice(1) : a,
                l = parseInt(t, 10);
            return {
                isInvertedDelayMatch: e,
                delayMatch: nativeIsNaN(l) ? null : l,
            };
        }
        function isValidCallback(n) {
            return n instanceof Function || "string" == typeof n;
        }
        function isValidMatchStr(t) {
            var i = t;
            return (
                null != t && t.startsWith("!") && (i = t.slice(1)),
                isValidStrPattern(i)
            );
        }
        function isValidStrPattern(e) {
            var t,
                n = escapeRegExp(e);
            "/" === e[0] && "/" === e[e.length - 1] && (n = e.slice(1, -1));
            try {
                ((t = new RegExp(n)), (t = !0));
            } catch (e) {
                t = false;
            }
            return t;
        }
        function escapeRegExp(e) {
            return e.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        }
        function nativeIsFinite(i) {
            return (Number.isFinite || window.isFinite)(i);
        }
        function isValidMatchNumber(a) {
            var t = a;
            null != a && a.startsWith("!") && (t = a.slice(1));
            var i = parseFloat(t);
            return !nativeIsNaN(i) && nativeIsFinite(i);
        }
        function parseRawDelay(a) {
            var e = Math.floor(parseInt(a, 10));
            return "number" != typeof e || nativeIsNaN(e) ? a : e;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            preventSetInterval.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function preventSetTimeout(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function preventSetTimeout(source, matchCallback, matchDelay) {
            var shouldLog =
                typeof matchCallback === "undefined" &&
                typeof matchDelay === "undefined";
            var handlerWrapper = function handlerWrapper(
                target,
                thisArg,
                args,
            ) {
                var callback = args[0];
                var delay = args[1];
                var shouldPrevent = false;
                if (shouldLog) {
                    hit(source);
                    logMessage(
                        source,
                        `setTimeout(${String(callback)}, ${delay})`,
                        true,
                    );
                } else {
                    shouldPrevent = isPreventionNeeded({
                        callback: callback,
                        delay: delay,
                        matchCallback: matchCallback,
                        matchDelay: matchDelay,
                    });
                }
                if (shouldPrevent) {
                    hit(source);
                    args[0] = noopFunc;
                }
                return target.apply(thisArg, args);
            };
            var setTimeoutHandler = {
                apply: handlerWrapper,
            };
            window.setTimeout = new Proxy(window.setTimeout, setTimeoutHandler);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function noopFunc() {}
        function isPreventionNeeded(a) {
            var { callback: e, delay: t, matchCallback: r, matchDelay: l } = a;
            if (!isValidCallback(e)) return false;
            if (!isValidMatchStr(r) || (l && !isValidMatchNumber(l)))
                return false;
            var { isInvertedMatch: c, matchRegexp: i } = parseMatchArg(r),
                { isInvertedDelayMatch: n, delayMatch: s } = parseDelayArg(l),
                d = parseRawDelay(t),
                h = String(e);
            return null === s
                ? i.test(h) !== c
                : r
                  ? i.test(h) !== c && (d === s) !== n
                  : (d === s) !== n;
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function parseMatchArg(t) {
            var e = !!t && (null == t ? void 0 : t.startsWith("!")),
                a = e ? t.slice(1) : t;
            return {
                isInvertedMatch: e,
                matchRegexp: toRegExp(a),
                matchValue: a,
            };
        }
        function parseDelayArg(a) {
            var e = null == a ? void 0 : a.startsWith("!"),
                t = e ? a.slice(1) : a,
                l = parseInt(t, 10);
            return {
                isInvertedDelayMatch: e,
                delayMatch: nativeIsNaN(l) ? null : l,
            };
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function nativeIsNaN(N) {
            return (Number.isNaN || window.isNaN)(N);
        }
        function isValidCallback(n) {
            return n instanceof Function || "string" == typeof n;
        }
        function isValidMatchStr(t) {
            var i = t;
            return (
                null != t && t.startsWith("!") && (i = t.slice(1)),
                isValidStrPattern(i)
            );
        }
        function escapeRegExp(e) {
            return e.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        }
        function isValidStrPattern(e) {
            var t,
                n = escapeRegExp(e);
            "/" === e[0] && "/" === e[e.length - 1] && (n = e.slice(1, -1));
            try {
                ((t = new RegExp(n)), (t = !0));
            } catch (e) {
                t = false;
            }
            return t;
        }
        function nativeIsFinite(i) {
            return (Number.isFinite || window.isFinite)(i);
        }
        function isValidMatchNumber(a) {
            var t = a;
            null != a && a.startsWith("!") && (t = a.slice(1));
            var i = parseFloat(t);
            return !nativeIsNaN(i) && nativeIsFinite(i);
        }
        function parseRawDelay(a) {
            var e = Math.floor(parseInt(a, 10));
            return "number" != typeof e || nativeIsNaN(e) ? a : e;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            preventSetTimeout.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function preventWindowOpen(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function preventWindowOpen(source) {
            var match =
                arguments.length > 1 && arguments[1] !== undefined
                    ? arguments[1]
                    : "*";
            var delay = arguments.length > 2 ? arguments[2] : undefined;
            var replacement = arguments.length > 3 ? arguments[3] : undefined;
            var nativeOpen = window.open;
            var isNewSyntax = match !== "0" && match !== "1";
            var oldOpenWrapper = function oldOpenWrapper(str) {
                match = Number(match) > 0;
                for (
                    var _len = arguments.length,
                        args = new Array(_len > 1 ? _len - 1 : 0),
                        _key = 1;
                    _key < _len;
                    _key++
                ) {
                    args[_key - 1] = arguments[_key];
                }
                if (!isValidStrPattern(delay)) {
                    logMessage(source, `Invalid parameter: ${delay}`);
                    return nativeOpen.apply(window, [str, ...args]);
                }
                var searchRegexp = toRegExp(delay);
                if (match !== searchRegexp.test(str)) {
                    return nativeOpen.apply(window, [str, ...args]);
                }
                hit(source);
                return handleOldReplacement(replacement);
            };
            var newOpenWrapper = function newOpenWrapper(url) {
                var shouldLog = replacement && replacement.includes("log");
                for (
                    var _len2 = arguments.length,
                        args = new Array(_len2 > 1 ? _len2 - 1 : 0),
                        _key2 = 1;
                    _key2 < _len2;
                    _key2++
                ) {
                    args[_key2 - 1] = arguments[_key2];
                }
                if (shouldLog) {
                    var argsStr =
                        args && args.length > 0 ? `, ${args.join(", ")}` : "";
                    var message = `${url}${argsStr}`;
                    logMessage(source, message, true);
                    hit(source);
                }
                var shouldPrevent = false;
                if (match === "*") {
                    shouldPrevent = true;
                } else if (isValidMatchStr(match)) {
                    var {
                        isInvertedMatch: isInvertedMatch,
                        matchRegexp: matchRegexp,
                    } = parseMatchArg(match);
                    shouldPrevent = matchRegexp.test(url) !== isInvertedMatch;
                } else {
                    logMessage(source, `Invalid parameter: ${match}`);
                    shouldPrevent = false;
                }
                if (shouldPrevent) {
                    var parsedDelay = parseInt(delay, 10);
                    var result;
                    if (nativeIsNaN(parsedDelay)) {
                        result = noopNull();
                    } else {
                        var decoyArgs = {
                            replacement: replacement,
                            url: url,
                            delay: parsedDelay,
                        };
                        var decoy = createDecoy(decoyArgs);
                        var popup = decoy.contentWindow;
                        if (typeof popup === "object" && popup !== null) {
                            Object.defineProperty(popup, "closed", {
                                value: false,
                            });
                            Object.defineProperty(popup, "opener", {
                                value: window,
                            });
                            Object.defineProperty(popup, "frameElement", {
                                value: null,
                            });
                        } else {
                            var nativeGetter =
                                decoy.contentWindow && decoy.contentWindow.get;
                            Object.defineProperty(decoy, "contentWindow", {
                                get: getPreventGetter(nativeGetter),
                            });
                            popup = decoy.contentWindow;
                        }
                        result = popup;
                    }
                    hit(source);
                    return result;
                }
                return nativeOpen.apply(window, [url, ...args]);
            };
            window.open = isNewSyntax ? newOpenWrapper : oldOpenWrapper;
            window.open.toString = nativeOpen.toString.bind(nativeOpen);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function isValidStrPattern(e) {
            var t,
                n = escapeRegExp(e);
            "/" === e[0] && "/" === e[e.length - 1] && (n = e.slice(1, -1));
            try {
                ((t = new RegExp(n)), (t = !0));
            } catch (e) {
                t = false;
            }
            return t;
        }
        function escapeRegExp(e) {
            return e.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        }
        function isValidMatchStr(t) {
            var i = t;
            return (
                null != t && t.startsWith("!") && (i = t.slice(1)),
                isValidStrPattern(i)
            );
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function nativeIsNaN(N) {
            return (Number.isNaN || window.isNaN)(N);
        }
        function parseMatchArg(t) {
            var e = !!t && (null == t ? void 0 : t.startsWith("!")),
                a = e ? t.slice(1) : t;
            return {
                isInvertedMatch: e,
                matchRegexp: toRegExp(a),
                matchValue: a,
            };
        }
        function handleOldReplacement(e) {
            var n;
            if (e) {
                if ("trueFunc" === e) n = trueFunc;
                else if (e.includes("=")) {
                    if (e.startsWith("{") && e.endsWith("}")) {
                        var t = e.slice(1, -1),
                            u = substringBefore(t, "=");
                        "noopFunc" === substringAfter(t, "=") &&
                            ((n = {})[u] = noopFunc);
                    }
                }
            } else n = noopFunc;
            return n;
        }
        function createDecoy(e) {
            var t,
                r = (function (e) {
                    return ((e.Object = "data"), (e.Iframe = "src"), e);
                })({}),
                { replacement: n, url: o, delay: a } = e;
            t = "obj" === n ? "object" : "iframe";
            var i = document.createElement(t);
            return (
                i instanceof HTMLObjectElement
                    ? (i[r.Object] = o)
                    : i instanceof HTMLIFrameElement && (i[r.Iframe] = o),
                i.style.setProperty("height", "1px", "important"),
                i.style.setProperty("position", "fixed", "important"),
                i.style.setProperty("top", "-1px", "important"),
                i.style.setProperty("width", "1px", "important"),
                document.body.appendChild(i),
                setTimeout(function () {
                    return i.remove();
                }, 1e3 * a),
                i
            );
        }
        function getPreventGetter(n) {
            return function (t, e) {
                return (
                    (!e || "closed" !== e) &&
                    ("function" == typeof n ? noopFunc : e && t[e])
                );
            };
        }
        function noopNull() {
            return null;
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function noopFunc() {}
        function trueFunc() {
            return true;
        }
        function substringBefore(r, n) {
            if (!r || false) return r;
            var e = r.indexOf(n);
            return e < 0 ? r : r.substring(0, e);
        }
        function substringAfter(n, r) {
            if (!n) return n;
            var t = n.indexOf(r);
            return t < 0 ? "" : n.substring(t + r.length);
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            preventWindowOpen.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function preventXHR(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function preventXHR(source, propsToMatch, customResponseText) {
            if (typeof Proxy === "undefined") {
                return;
            }
            var nativeOpen = window.XMLHttpRequest.prototype.open;
            var nativeGetResponseHeader =
                window.XMLHttpRequest.prototype.getResponseHeader;
            var nativeGetAllResponseHeaders =
                window.XMLHttpRequest.prototype.getAllResponseHeaders;
            var xhrData;
            var modifiedResponse = "";
            var modifiedResponseText = "";
            var openWrapper = function openWrapper(target, thisArg, args) {
                xhrData = getXhrData.apply(null, args);
                if (typeof propsToMatch === "undefined") {
                    logMessage(
                        source,
                        `xhr( ${objectToString(xhrData)} )`,
                        true,
                    );
                    hit(source);
                } else if (matchRequestProps(source, propsToMatch, xhrData)) {
                    thisArg.shouldBePrevented = true;
                    thisArg.xhrData = xhrData;
                }
                if (thisArg.shouldBePrevented) {
                    thisArg.collectedHeaders = [];
                    var setRequestHeaderWrapper =
                        function setRequestHeaderWrapper(
                            target,
                            thisArg,
                            args,
                        ) {
                            thisArg.collectedHeaders.push(args);
                            return Reflect.apply(target, thisArg, args);
                        };
                    var setRequestHeaderHandler = {
                        apply: setRequestHeaderWrapper,
                    };
                    thisArg.setRequestHeader = new Proxy(
                        thisArg.setRequestHeader,
                        setRequestHeaderHandler,
                    );
                }
                return Reflect.apply(target, thisArg, args);
            };
            var sendWrapper = function sendWrapper(target, thisArg, args) {
                if (!thisArg.shouldBePrevented) {
                    return Reflect.apply(target, thisArg, args);
                }
                if (thisArg.responseType === "blob") {
                    modifiedResponse = new Blob();
                }
                if (thisArg.responseType === "arraybuffer") {
                    modifiedResponse = new ArrayBuffer();
                }
                if (customResponseText) {
                    var randomText = generateRandomResponse(customResponseText);
                    if (randomText) {
                        modifiedResponse = randomText;
                        modifiedResponseText = randomText;
                    } else {
                        logMessage(
                            source,
                            `Invalid randomize parameter: '${customResponseText}'`,
                        );
                    }
                }
                var forgedRequest = new XMLHttpRequest();
                var transitionReadyState = function transitionReadyState(
                    state,
                ) {
                    if (state === 4) {
                        var {
                            responseURL: responseURL,
                            responseXML: responseXML,
                        } = forgedRequest;
                        Object.defineProperties(thisArg, {
                            readyState: {
                                value: 4,
                                writable: false,
                            },
                            statusText: {
                                value: "OK",
                                writable: false,
                            },
                            responseURL: {
                                value: responseURL || thisArg.xhrData.url,
                                writable: false,
                            },
                            responseXML: {
                                value: responseXML,
                                writable: false,
                            },
                            status: {
                                value: 200,
                                writable: false,
                            },
                            response: {
                                value: modifiedResponse,
                                writable: false,
                            },
                            responseText: {
                                value: modifiedResponseText,
                                writable: false,
                            },
                        });
                        hit(source);
                    } else {
                        Object.defineProperty(thisArg, "readyState", {
                            value: state,
                            writable: true,
                            configurable: true,
                        });
                    }
                    var stateEvent = new Event("readystatechange");
                    thisArg.dispatchEvent(stateEvent);
                };
                forgedRequest.addEventListener("readystatechange", function () {
                    transitionReadyState(1);
                    var loadStartEvent = new ProgressEvent("loadstart");
                    thisArg.dispatchEvent(loadStartEvent);
                    transitionReadyState(2);
                    transitionReadyState(3);
                    var progressEvent = new ProgressEvent("progress");
                    thisArg.dispatchEvent(progressEvent);
                    transitionReadyState(4);
                });
                setTimeout(function () {
                    var loadEvent = new ProgressEvent("load");
                    thisArg.dispatchEvent(loadEvent);
                    var loadEndEvent = new ProgressEvent("loadend");
                    thisArg.dispatchEvent(loadEndEvent);
                }, 1);
                nativeOpen.apply(forgedRequest, [
                    thisArg.xhrData.method,
                    thisArg.xhrData.url,
                ]);
                thisArg.collectedHeaders.forEach(function (header) {
                    var name = header[0];
                    var value = header[1];
                    forgedRequest.setRequestHeader(name, value);
                });
                return undefined;
            };
            var getHeaderWrapper = function getHeaderWrapper(
                target,
                thisArg,
                args,
            ) {
                if (!thisArg.shouldBePrevented) {
                    return nativeGetResponseHeader.apply(thisArg, args);
                }
                if (!thisArg.collectedHeaders.length) {
                    return null;
                }
                var searchHeaderName = args[0].toLowerCase();
                var matchedHeader = thisArg.collectedHeaders.find(
                    function (header) {
                        var headerName = header[0].toLowerCase();
                        return headerName === searchHeaderName;
                    },
                );
                return matchedHeader ? matchedHeader[1] : null;
            };
            var getAllHeadersWrapper = function getAllHeadersWrapper(
                target,
                thisArg,
            ) {
                if (!thisArg.shouldBePrevented) {
                    return nativeGetAllResponseHeaders.call(thisArg);
                }
                if (!thisArg.collectedHeaders.length) {
                    return "";
                }
                var allHeadersStr = thisArg.collectedHeaders
                    .map(function (header) {
                        var headerName = header[0];
                        var headerValue = header[1];
                        return `${headerName.toLowerCase()}: ${headerValue}`;
                    })
                    .join("\r\n");
                return allHeadersStr;
            };
            var openHandler = {
                apply: openWrapper,
            };
            var sendHandler = {
                apply: sendWrapper,
            };
            var getHeaderHandler = {
                apply: getHeaderWrapper,
            };
            var getAllHeadersHandler = {
                apply: getAllHeadersWrapper,
            };
            XMLHttpRequest.prototype.open = new Proxy(
                XMLHttpRequest.prototype.open,
                openHandler,
            );
            XMLHttpRequest.prototype.send = new Proxy(
                XMLHttpRequest.prototype.send,
                sendHandler,
            );
            XMLHttpRequest.prototype.getResponseHeader = new Proxy(
                XMLHttpRequest.prototype.getResponseHeader,
                getHeaderHandler,
            );
            XMLHttpRequest.prototype.getAllResponseHeaders = new Proxy(
                XMLHttpRequest.prototype.getAllResponseHeaders,
                getAllHeadersHandler,
            );
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function objectToString(t) {
            return t && "object" == typeof t
                ? isEmptyObject(t)
                    ? "{}"
                    : Object.entries(t)
                          .map(function (t) {
                              var n = t[0],
                                  e = t[1],
                                  o = e;
                              return (
                                  e instanceof Object &&
                                      (o = `{ ${objectToString(e)} }`),
                                  `${n}:"${o}"`
                              );
                          })
                          .join(" ")
                : String(t);
        }
        function generateRandomResponse(e) {
            var t = e;
            if ("true" === t)
                return (t = Math.random().toString(36).slice(-10));
            t = t.replace("length:", "");
            if (!/^\d+-\d+$/.test(t)) return null;
            var n = getNumberFromString(t.split("-")[0]),
                r = getNumberFromString(t.split("-")[1]);
            if (!nativeIsFinite(n) || !nativeIsFinite(r)) return null;
            if (n > r) {
                var i = n;
                ((n = r), (r = i));
            }
            if (r > 5e5) return null;
            var a = getRandomIntInclusive(n, r);
            return (t = getRandomStrByLength(a));
        }
        function matchRequestProps(e, t, r) {
            if ("" === t || "*" === t) return true;
            var a,
                s = parseMatchProps(t);
            if (isValidParsedData(s)) {
                var n = getMatchPropsData(s);
                a = Object.keys(n).every(function (e) {
                    var t = n[e],
                        a = r[e];
                    return (
                        Object.prototype.hasOwnProperty.call(r, e) &&
                        "string" == typeof a &&
                        (null == t ? void 0 : t.test(a))
                    );
                });
            } else (logMessage(e, `Invalid parameter: ${t}`), (a = false));
            return a;
        }
        function getXhrData(r, t, a, e, n) {
            return {
                method: r,
                url: t,
                async: a,
                user: e,
                password: n,
            };
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function isValidStrPattern(e) {
            var t,
                n = escapeRegExp(e);
            "/" === e[0] && "/" === e[e.length - 1] && (n = e.slice(1, -1));
            try {
                ((t = new RegExp(n)), (t = !0));
            } catch (e) {
                t = false;
            }
            return t;
        }
        function escapeRegExp(e) {
            return e.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        }
        function isEmptyObject(t) {
            return 0 === Object.keys(t).length && !t.prototype;
        }
        function getNumberFromString(n) {
            var r = parseInt(n, 10);
            return nativeIsNaN(r) ? null : r;
        }
        function nativeIsFinite(i) {
            return (Number.isFinite || window.isFinite)(i);
        }
        function nativeIsNaN(N) {
            return (Number.isNaN || window.isNaN)(N);
        }
        function parseMatchProps(e) {
            var r = {};
            return (
                e.split(" ").forEach(function (e) {
                    var n = e.indexOf(":"),
                        i = e.slice(0, n);
                    if (
                        (function (e) {
                            return getRequestProps().includes(e);
                        })(i)
                    ) {
                        var s = e.slice(n + 1);
                        r[i] = s;
                    } else r.url = e;
                }),
                r
            );
        }
        function isValidParsedData(t) {
            return Object.values(t).every(function (t) {
                return isValidStrPattern(t);
            });
        }
        function getMatchPropsData(t) {
            var a = {};
            return (
                Object.keys(t).forEach(function (c) {
                    a[c] = toRegExp(t[c]);
                }),
                a
            );
        }
        function getRequestProps() {
            return [
                "url",
                "method",
                "headers",
                "body",
                "credentials",
                "cache",
                "redirect",
                "referrer",
                "referrerPolicy",
                "integrity",
                "keepalive",
                "signal",
                "mode",
            ];
        }
        function getRandomIntInclusive(t, n) {
            return (
                (t = Math.ceil(t)),
                (n = Math.floor(n)),
                Math.floor(Math.random() * (n - t + 1) + t)
            );
        }
        function getRandomStrByLength(r) {
            for (
                var t = "",
                    a =
                        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()_+=~",
                    n = 0;
                n < r;
                n += 1
            )
                t += a.charAt(Math.floor(76 * Math.random()));
            return t;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            preventXHR.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function removeAttr(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function removeAttr(source, attrs, selector) {
            var applying =
                arguments.length > 3 && arguments[3] !== undefined
                    ? arguments[3]
                    : "asap stay";
            if (!attrs) {
                return;
            }
            attrs = attrs.split(/\s*\|\s*/);
            if (!selector) {
                selector = `[${attrs.join("],[")}]`;
            }
            var rmattr = function rmattr() {
                var nodes = [];
                try {
                    nodes = [].slice.call(document.querySelectorAll(selector));
                } catch (e) {
                    logMessage(source, `Invalid selector arg: '${selector}'`);
                }
                var removed = false;
                nodes.forEach(function (node) {
                    attrs.forEach(function (attr) {
                        node.removeAttribute(attr);
                        removed = true;
                    });
                });
                if (removed) {
                    hit(source);
                }
            };
            var flags = parseFlags(applying);
            var run = function run() {
                rmattr();
                if (!flags.hasFlag(flags.STAY)) {
                    return;
                }
                observeDOMChanges(rmattr, true);
            };
            if (flags.hasFlag(flags.ASAP)) {
                if (document.readyState === "loading") {
                    window.addEventListener("DOMContentLoaded", rmattr, {
                        once: true,
                    });
                } else {
                    rmattr();
                }
            }
            if (
                document.readyState !== "complete" &&
                flags.hasFlag(flags.COMPLETE)
            ) {
                window.addEventListener("load", run, {
                    once: true,
                });
            } else if (flags.hasFlag(flags.STAY)) {
                if (!applying.includes(" ")) {
                    rmattr();
                }
                observeDOMChanges(rmattr, true);
            }
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function observeDOMChanges(t) {
            var e =
                    arguments.length > 1 &&
                    void 0 !== arguments[1] &&
                    arguments[1],
                n =
                    arguments.length > 2 && void 0 !== arguments[2]
                        ? arguments[2]
                        : [],
                i = new MutationObserver(
                    throttle(function () {
                        (disconnect(), t(), connect());
                    }, 20),
                ),
                connect = function connect() {
                    n.length > 0
                        ? i.observe(document.documentElement, {
                              childList: true,
                              subtree: true,
                              attributes: e,
                              attributeFilter: n,
                          })
                        : i.observe(document.documentElement, {
                              childList: true,
                              subtree: true,
                              attributes: e,
                          });
                },
                disconnect = function disconnect() {
                    i.disconnect();
                };
            connect();
        }
        function parseFlags(t) {
            var e = "asap",
                n = "complete",
                a = "stay",
                r = new Set([e, n, a]),
                s = new Set(
                    t
                        .trim()
                        .split(" ")
                        .filter(function (t) {
                            return r.has(t);
                        }),
                );
            return {
                ASAP: e,
                COMPLETE: n,
                STAY: a,
                hasFlag: function hasFlag(t) {
                    return s.has(t);
                },
            };
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function throttle(n, t) {
            var r,
                e = false,
                _wrapper4 = function _wrapper() {
                    for (
                        var o = arguments.length, u = new Array(o), f = 0;
                        f < o;
                        f++
                    )
                        u[f] = arguments[f];
                    e
                        ? (r = u)
                        : (n(...u),
                          (e = true),
                          setTimeout(function () {
                              ((e = false), r && (_wrapper4(...r), (r = null)));
                          }, t));
                };
            return _wrapper4;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            removeAttr.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function removeClass(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function removeClass(source, classNames, selector) {
            var applying =
                arguments.length > 3 && arguments[3] !== undefined
                    ? arguments[3]
                    : "asap stay";
            if (!classNames) {
                return;
            }
            classNames = classNames.split(/\s*\|\s*/);
            var selectors = [];
            if (!selector) {
                selectors = classNames.map(function (className) {
                    return `.${className}`;
                });
            }
            var removeClassHandler = function removeClassHandler() {
                var nodes = new Set();
                if (selector) {
                    var foundNodes = [];
                    try {
                        foundNodes = [].slice.call(
                            document.querySelectorAll(selector),
                        );
                    } catch (e) {
                        logMessage(
                            source,
                            `Invalid selector arg: '${selector}'`,
                        );
                    }
                    foundNodes.forEach(function (n) {
                        return nodes.add(n);
                    });
                } else if (selectors.length > 0) {
                    selectors.forEach(function (s) {
                        var elements = document.querySelectorAll(s);
                        for (var i = 0; i < elements.length; i += 1) {
                            var element = elements[i];
                            nodes.add(element);
                        }
                    });
                }
                var removed = false;
                nodes.forEach(function (node) {
                    classNames.forEach(function (className) {
                        if (node.classList.contains(className)) {
                            node.classList.remove(className);
                            removed = true;
                        }
                    });
                });
                if (removed) {
                    hit(source);
                }
            };
            var CLASS_ATTR_NAME = ["class"];
            var flags = parseFlags(applying);
            var run = function run() {
                removeClassHandler();
                if (!flags.hasFlag(flags.STAY)) {
                    return;
                }
                observeDOMChanges(removeClassHandler, true, CLASS_ATTR_NAME);
            };
            if (flags.hasFlag(flags.ASAP)) {
                if (document.readyState === "loading") {
                    window.addEventListener(
                        "DOMContentLoaded",
                        removeClassHandler,
                        {
                            once: true,
                        },
                    );
                } else {
                    removeClassHandler();
                }
            }
            if (
                document.readyState !== "complete" &&
                flags.hasFlag(flags.COMPLETE)
            ) {
                window.addEventListener("load", run, {
                    once: true,
                });
            } else if (flags.hasFlag(flags.STAY)) {
                if (!applying.includes(" ")) {
                    removeClassHandler();
                }
                observeDOMChanges(removeClassHandler, true, CLASS_ATTR_NAME);
            }
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function observeDOMChanges(t) {
            var e =
                    arguments.length > 1 &&
                    void 0 !== arguments[1] &&
                    arguments[1],
                n =
                    arguments.length > 2 && void 0 !== arguments[2]
                        ? arguments[2]
                        : [],
                i = new MutationObserver(
                    throttle(function () {
                        (disconnect(), t(), connect());
                    }, 20),
                ),
                connect = function connect() {
                    n.length > 0
                        ? i.observe(document.documentElement, {
                              childList: true,
                              subtree: true,
                              attributes: e,
                              attributeFilter: n,
                          })
                        : i.observe(document.documentElement, {
                              childList: true,
                              subtree: true,
                              attributes: e,
                          });
                },
                disconnect = function disconnect() {
                    i.disconnect();
                };
            connect();
        }
        function parseFlags(t) {
            var e = "asap",
                n = "complete",
                a = "stay",
                r = new Set([e, n, a]),
                s = new Set(
                    t
                        .trim()
                        .split(" ")
                        .filter(function (t) {
                            return r.has(t);
                        }),
                );
            return {
                ASAP: e,
                COMPLETE: n,
                STAY: a,
                hasFlag: function hasFlag(t) {
                    return s.has(t);
                },
            };
        }
        function throttle(n, t) {
            var r,
                e = false,
                _wrapper5 = function _wrapper() {
                    for (
                        var o = arguments.length, u = new Array(o), f = 0;
                        f < o;
                        f++
                    )
                        u[f] = arguments[f];
                    e
                        ? (r = u)
                        : (n(...u),
                          (e = true),
                          setTimeout(function () {
                              ((e = false), r && (_wrapper5(...r), (r = null)));
                          }, t));
                };
            return _wrapper5;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            removeClass.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function removeCookie(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function removeCookie(source, match) {
            var matchRegexp = toRegExp(match);
            var removeCookieFromHost = function removeCookieFromHost(
                cookieName,
                hostName,
            ) {
                var cookieSpec = `${cookieName}=`;
                var domain1 = `; domain=${hostName}`;
                var domain2 = `; domain=.${hostName}`;
                var path = "; path=/";
                var expiration = "; expires=Thu, 01 Jan 1970 00:00:00 GMT";
                document.cookie = cookieSpec + expiration;
                document.cookie = cookieSpec + domain1 + expiration;
                document.cookie = cookieSpec + domain2 + expiration;
                document.cookie = cookieSpec + path + expiration;
                document.cookie = cookieSpec + domain1 + path + expiration;
                document.cookie = cookieSpec + domain2 + path + expiration;
                hit(source);
            };
            var rmCookie = function rmCookie() {
                document.cookie.split(";").forEach(function (cookieStr) {
                    var pos = cookieStr.indexOf("=");
                    if (pos === -1) {
                        return;
                    }
                    var cookieName = cookieStr.slice(0, pos).trim();
                    if (!matchRegexp.test(cookieName)) {
                        return;
                    }
                    var hostParts = document.location.hostname.split(".");
                    for (var i = 0; i <= hostParts.length - 1; i += 1) {
                        var hostName = hostParts.slice(i).join(".");
                        if (hostName) {
                            removeCookieFromHost(cookieName, hostName);
                        }
                    }
                });
            };
            rmCookie();
            window.addEventListener("beforeunload", rmCookie);
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            removeCookie.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function removeInShadowDom(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function removeInShadowDom(source, selector, baseSelector) {
            if (!Element.prototype.attachShadow) {
                return;
            }
            var removeElement = function removeElement(targetElement) {
                targetElement.remove();
            };
            var removeHandler = function removeHandler() {
                var hostElements = !baseSelector
                    ? findHostElements(document.documentElement)
                    : document.querySelectorAll(baseSelector);
                var _loop = function _loop() {
                    var isRemoved = false;
                    var { targets: targets, innerHosts: innerHosts } =
                        pierceShadowDom(selector, hostElements);
                    targets.forEach(function (targetEl) {
                        removeElement(targetEl);
                        isRemoved = true;
                    });
                    if (isRemoved) {
                        hit(source);
                    }
                    hostElements = innerHosts;
                };
                while (hostElements.length !== 0) {
                    _loop();
                }
            };
            removeHandler();
            observeDOMChanges(removeHandler, true);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function observeDOMChanges(t) {
            var e =
                    arguments.length > 1 &&
                    void 0 !== arguments[1] &&
                    arguments[1],
                n =
                    arguments.length > 2 && void 0 !== arguments[2]
                        ? arguments[2]
                        : [],
                i = new MutationObserver(
                    throttle(function () {
                        (disconnect(), t(), connect());
                    }, 20),
                ),
                connect = function connect() {
                    n.length > 0
                        ? i.observe(document.documentElement, {
                              childList: true,
                              subtree: true,
                              attributes: e,
                              attributeFilter: n,
                          })
                        : i.observe(document.documentElement, {
                              childList: true,
                              subtree: true,
                              attributes: e,
                          });
                },
                disconnect = function disconnect() {
                    i.disconnect();
                };
            connect();
        }
        function findHostElements(o) {
            var n = [];
            o &&
                o.querySelectorAll("*").forEach(function (o) {
                    o.shadowRoot && n.push(o);
                });
            return n;
        }
        function pierceShadowDom(e, t) {
            var c = [],
                l = [];
            t.forEach(function (t) {
                var o = t.querySelectorAll(e);
                c = c.concat([].slice.call(o));
                var r = t.shadowRoot,
                    a = r.querySelectorAll(e);
                ((c = c.concat([].slice.call(a))), l.push(findHostElements(r)));
            });
            var o = flatten(l);
            return {
                targets: c,
                innerHosts: o,
            };
        }
        function flatten(r) {
            var n = [];
            r.forEach(function (r) {
                return n.push(r);
            });
            for (var t = []; n.length; ) {
                var u = n.pop();
                Array.isArray(u)
                    ? u.forEach(function (r) {
                          return n.push(r);
                      })
                    : t.push(u);
            }
            return t.reverse();
        }
        function throttle(n, t) {
            var r,
                e = false,
                _wrapper6 = function _wrapper() {
                    for (
                        var o = arguments.length, u = new Array(o), f = 0;
                        f < o;
                        f++
                    )
                        u[f] = arguments[f];
                    e
                        ? (r = u)
                        : (n(...u),
                          (e = true),
                          setTimeout(function () {
                              ((e = false), r && (_wrapper6(...r), (r = null)));
                          }, t));
                };
            return _wrapper6;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            removeInShadowDom.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function removeNodeText(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function removeNodeText(source, nodeName, textMatch, parentSelector) {
            var {
                selector: selector,
                nodeNameMatch: nodeNameMatch,
                textContentMatch: textContentMatch,
            } = parseNodeTextParams(nodeName, textMatch);
            var handleNodes = function handleNodes(nodes) {
                return nodes.forEach(function (node) {
                    var shouldReplace = isTargetNode(
                        node,
                        nodeNameMatch,
                        textContentMatch,
                    );
                    if (shouldReplace) {
                        var ALL_TEXT_PATTERN = /^[^]*$/;
                        var REPLACEMENT = "";
                        replaceNodeText(
                            source,
                            node,
                            ALL_TEXT_PATTERN,
                            REPLACEMENT,
                        );
                    }
                });
            };
            if (document.documentElement) {
                handleExistingNodes(selector, handleNodes, parentSelector);
            }
            observeDocumentWithTimeout(function (mutations) {
                return handleMutations(
                    mutations,
                    handleNodes,
                    selector,
                    parentSelector,
                );
            });
        }
        function observeDocumentWithTimeout(e) {
            var t =
                    arguments.length > 1 && void 0 !== arguments[1]
                        ? arguments[1]
                        : {
                              subtree: true,
                              childList: true,
                          },
                n =
                    arguments.length > 2 && void 0 !== arguments[2]
                        ? arguments[2]
                        : 1e4,
                o = new MutationObserver(function (n, o) {
                    (o.disconnect(),
                        e(n, o),
                        o.observe(document.documentElement, t));
                });
            (o.observe(document.documentElement, t),
                "number" == typeof n &&
                    setTimeout(function () {
                        return o.disconnect();
                    }, n));
        }
        function handleExistingNodes(e, n, o) {
            (o ? document.querySelectorAll(o) : [document]).forEach(
                function (o) {
                    return (function (o) {
                        if ("#text" === e) {
                            var r = nodeListToArray(o.childNodes).filter(
                                function (e) {
                                    return e.nodeType === Node.TEXT_NODE;
                                },
                            );
                            n(r);
                        } else {
                            var t = nodeListToArray(o.querySelectorAll(e));
                            n(t);
                        }
                    })(o);
                },
            );
        }
        function handleMutations(n, d, e, o) {
            var t = getAddedNodes(n);
            e && o
                ? t.forEach(function () {
                      handleExistingNodes(e, d, o);
                  })
                : d(t);
        }
        function replaceNodeText(e, t, n, r) {
            var { textContent: a } = t;
            if (a) {
                var i = a.replace(n, r);
                if ("SCRIPT" === t.nodeName)
                    i = getTrustedTypesApi(e).createScript(i);
                ((t.textContent = i), hit(e));
            }
        }
        function isTargetNode(e, t, n) {
            var { nodeName: o, textContent: s } = e,
                a = o.toLowerCase();
            return (
                null !== s &&
                "" !== s &&
                (t instanceof RegExp ? t.test(a) : t === a) &&
                (n instanceof RegExp ? n.test(s) : s.includes(n))
            );
        }
        function parseNodeTextParams(t, e) {
            var a,
                n =
                    arguments.length > 2 && void 0 !== arguments[2]
                        ? arguments[2]
                        : null,
                r = "/",
                s = !(t.startsWith(r) && t.endsWith(r)),
                o = s ? t : "*",
                h = s ? t : toRegExp(t),
                i = e.startsWith(r) ? toRegExp(e) : e;
            return (
                n && (a = n.startsWith(r) ? toRegExp(n) : n),
                {
                    selector: o,
                    nodeNameMatch: h,
                    textContentMatch: i,
                    patternMatch: a,
                }
            );
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function nodeListToArray(r) {
            for (var n = [], o = 0; o < r.length; o += 1) n.push(r[o]);
            return n;
        }
        function getAddedNodes(d) {
            for (var e = [], r = 0; r < d.length; r += 1)
                for (var { addedNodes: n } = d[r], o = 0; o < n.length; o += 1)
                    e.push(n[o]);
            return e;
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function getTrustedTypesApi(t) {
            var r,
                e =
                    null == t || null === (r = t.api) || void 0 === r
                        ? void 0
                        : r.policy;
            if (e) return e;
            var n = "AGPolicy",
                i = window.trustedTypes,
                u = !!i,
                c = {
                    HTML: "TrustedHTML",
                    Script: "TrustedScript",
                    ScriptURL: "TrustedScriptURL",
                };
            if (!u)
                return {
                    name: n,
                    isSupported: u,
                    TrustedType: c,
                    createHTML: function createHTML(t) {
                        return t;
                    },
                    createScript: function createScript(t) {
                        return t;
                    },
                    createScriptURL: function createScriptURL(t) {
                        return t;
                    },
                    create: function create(t, r) {
                        return r;
                    },
                    getAttributeType: function getAttributeType() {
                        return null;
                    },
                    convertAttributeToTrusted:
                        function convertAttributeToTrusted(t, r, e) {
                            return e;
                        },
                    getPropertyType: function getPropertyType() {
                        return null;
                    },
                    convertPropertyToTrusted: function convertPropertyToTrusted(
                        t,
                        r,
                        e,
                    ) {
                        return e;
                    },
                    isHTML: function isHTML() {
                        return false;
                    },
                    isScript: function isScript() {
                        return false;
                    },
                    isScriptURL: function isScriptURL() {
                        return false;
                    },
                };
            var o = i.createPolicy(n, {
                    createHTML: function createHTML(t) {
                        return t;
                    },
                    createScript: function createScript(t) {
                        return t;
                    },
                    createScriptURL: function createScriptURL(t) {
                        return t;
                    },
                }),
                createHTML = function createHTML(t) {
                    return o.createHTML(t);
                },
                createScript = function createScript(t) {
                    return o.createScript(t);
                },
                createScriptURL = function createScriptURL(t) {
                    return o.createScriptURL(t);
                },
                create = function create(t, r) {
                    switch (t) {
                        case c.HTML:
                            return createHTML(r);
                        case c.Script:
                            return createScript(r);
                        case c.ScriptURL:
                            return createScriptURL(r);
                        default:
                            return r;
                    }
                },
                p = i.getAttributeType.bind(i),
                T = i.getPropertyType.bind(i),
                s = i.isHTML.bind(i),
                a = i.isScript.bind(i),
                f = i.isScriptURL.bind(i);
            return {
                name: n,
                isSupported: u,
                TrustedType: c,
                createHTML: createHTML,
                createScript: createScript,
                createScriptURL: createScriptURL,
                create: create,
                getAttributeType: p,
                convertAttributeToTrusted: function convertAttributeToTrusted(
                    t,
                    r,
                    e,
                    n,
                    i,
                ) {
                    var u = p(t, r, n, i);
                    return u ? create(u, e) : e;
                },
                getPropertyType: T,
                convertPropertyToTrusted: function convertPropertyToTrusted(
                    t,
                    r,
                    e,
                    n,
                ) {
                    var i = T(t, r, n);
                    return i ? create(i, e) : e;
                },
                isHTML: s,
                isScript: a,
                isScriptURL: f,
            };
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            removeNodeText.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function setAttr(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function setAttr(source, selector, attr) {
            var value =
                arguments.length > 3 && arguments[3] !== undefined
                    ? arguments[3]
                    : "";
            if (!selector || !attr) {
                return;
            }
            var allowedValues = ["true", "false"];
            var shouldCopyValue = value.startsWith("[") && value.endsWith("]");
            var isValidValue =
                value.length === 0 ||
                (!nativeIsNaN(parseInt(value, 10)) &&
                    parseInt(value, 10) >= 0 &&
                    parseInt(value, 10) <= 32767) ||
                allowedValues.includes(value.toLowerCase());
            if (!shouldCopyValue && !isValidValue) {
                logMessage(
                    source,
                    `Invalid attribute value provided: '${convertTypeToString(value)}'`,
                );
                return;
            }
            var attributeHandler;
            if (shouldCopyValue) {
                attributeHandler = function attributeHandler(
                    elem,
                    attr,
                    value,
                ) {
                    var valueToCopy = elem.getAttribute(value.slice(1, -1));
                    if (valueToCopy === null) {
                        logMessage(
                            source,
                            `No element attribute found to copy value from: ${value}`,
                        );
                    }
                    elem.setAttribute(attr, valueToCopy);
                };
            }
            setAttributeBySelector(
                source,
                selector,
                attr,
                value,
                attributeHandler,
            );
            observeDOMChanges(function () {
                return setAttributeBySelector(
                    source,
                    selector,
                    attr,
                    value,
                    attributeHandler,
                );
            }, true);
        }
        function setAttributeBySelector(e, t, l, o) {
            var r,
                c =
                    arguments.length > 4 && void 0 !== arguments[4]
                        ? arguments[4]
                        : defaultAttributeSetter;
            try {
                r = document.querySelectorAll(t);
            } catch (l) {
                return void logMessage(
                    e,
                    `Failed to find elements matching selector "${t}"`,
                );
            }
            if (r && 0 !== r.length)
                try {
                    (r.forEach(function (e) {
                        return c(e, l, o);
                    }),
                        hit(e));
                } catch (t) {
                    logMessage(
                        e,
                        `Failed to set [${l}="${o}"] to each of selected elements.`,
                    );
                }
        }
        function observeDOMChanges(t) {
            var e =
                    arguments.length > 1 &&
                    void 0 !== arguments[1] &&
                    arguments[1],
                n =
                    arguments.length > 2 && void 0 !== arguments[2]
                        ? arguments[2]
                        : [],
                i = new MutationObserver(
                    throttle(function () {
                        (disconnect(), t(), connect());
                    }, 20),
                ),
                connect = function connect() {
                    n.length > 0
                        ? i.observe(document.documentElement, {
                              childList: true,
                              subtree: true,
                              attributes: e,
                              attributeFilter: n,
                          })
                        : i.observe(document.documentElement, {
                              childList: true,
                              subtree: true,
                              attributes: e,
                          });
                },
                disconnect = function disconnect() {
                    i.disconnect();
                };
            connect();
        }
        function nativeIsNaN(N) {
            return (Number.isNaN || window.isNaN)(N);
        }
        function convertTypeToString(n) {
            return void 0 === n
                ? "undefined"
                : "object" == typeof n
                  ? null === n
                      ? "null"
                      : objectToString(n)
                  : String(n);
        }
        function defaultAttributeSetter(t, e, r) {
            return t.setAttribute(e, r);
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function throttle(n, t) {
            var r,
                e = false,
                _wrapper7 = function _wrapper() {
                    for (
                        var o = arguments.length, u = new Array(o), f = 0;
                        f < o;
                        f++
                    )
                        u[f] = arguments[f];
                    e
                        ? (r = u)
                        : (n(...u),
                          (e = true),
                          setTimeout(function () {
                              ((e = false), r && (_wrapper7(...r), (r = null)));
                          }, t));
                };
            return _wrapper7;
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            setAttr.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function setConstant(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function setConstant(source, property, value) {
            var stack =
                arguments.length > 3 && arguments[3] !== undefined
                    ? arguments[3]
                    : "";
            var valueWrapper =
                arguments.length > 4 && arguments[4] !== undefined
                    ? arguments[4]
                    : "";
            var setProxyTrap =
                arguments.length > 5 && arguments[5] !== undefined
                    ? arguments[5]
                    : false;
            var uboAliases = [
                "set-constant.js",
                "ubo-set-constant.js",
                "set.js",
                "ubo-set.js",
                "ubo-set-constant",
                "ubo-set",
            ];
            if (uboAliases.includes(source.name)) {
                if (stack.length !== 1 && !getNumberFromString(stack)) {
                    valueWrapper = stack;
                }
                stack = undefined;
            }
            if (!property || !matchStackTrace(stack, new Error().stack)) {
                return;
            }
            var isProxyTrapSet = false;
            var emptyArr = noopArray();
            var emptyObj = noopObject();
            var constantValue;
            if (value === "undefined") {
                constantValue = undefined;
            } else if (value === "false") {
                constantValue = false;
            } else if (value === "true") {
                constantValue = true;
            } else if (value === "null") {
                constantValue = null;
            } else if (value === "emptyArr") {
                constantValue = emptyArr;
            } else if (value === "emptyObj") {
                constantValue = emptyObj;
            } else if (value === "noopFunc") {
                constantValue = noopFunc;
            } else if (value === "noopCallbackFunc") {
                constantValue = noopCallbackFunc;
            } else if (value === "trueFunc") {
                constantValue = trueFunc;
            } else if (value === "falseFunc") {
                constantValue = falseFunc;
            } else if (value === "throwFunc") {
                constantValue = throwFunc;
            } else if (value === "noopPromiseResolve") {
                constantValue = noopPromiseResolve;
            } else if (value === "noopPromiseReject") {
                constantValue = noopPromiseReject;
            } else if (/^\d+$/.test(value)) {
                constantValue = parseFloat(value);
                if (nativeIsNaN(constantValue)) {
                    return;
                }
                if (Math.abs(constantValue) > 32767) {
                    return;
                }
            } else if (value === "-1") {
                constantValue = -1;
            } else if (value === "") {
                constantValue = "";
            } else if (value === "yes") {
                constantValue = "yes";
            } else if (value === "no") {
                constantValue = "no";
            } else {
                return;
            }
            var valueWrapperNames = [
                "asFunction",
                "asCallback",
                "asResolved",
                "asRejected",
            ];
            if (valueWrapperNames.includes(valueWrapper)) {
                var valueWrappersMap = {
                    asFunction(v) {
                        return function () {
                            return v;
                        };
                    },
                    asCallback(v) {
                        return function () {
                            return function () {
                                return v;
                            };
                        };
                    },
                    asResolved(v) {
                        return Promise.resolve(v);
                    },
                    asRejected(v) {
                        return Promise.reject(v);
                    },
                };
                constantValue = valueWrappersMap[valueWrapper](constantValue);
            }
            var canceled = false;
            var mustCancel = function mustCancel(value) {
                if (canceled) {
                    return canceled;
                }
                canceled =
                    value !== undefined &&
                    constantValue !== undefined &&
                    typeof value !== typeof constantValue &&
                    value !== null;
                return canceled;
            };
            var trapProp = function trapProp(
                base,
                prop,
                configurable,
                handler,
            ) {
                if (!handler.init(base[prop])) {
                    return false;
                }
                var origDescriptor = Object.getOwnPropertyDescriptor(
                    base,
                    prop,
                );
                var prevSetter;
                if (origDescriptor instanceof Object) {
                    if (!origDescriptor.configurable) {
                        var message = `Property '${prop}' is not configurable`;
                        logMessage(source, message);
                        return false;
                    }
                    if (base[prop]) {
                        base[prop] = constantValue;
                    }
                    if (origDescriptor.set instanceof Function) {
                        prevSetter = origDescriptor.set;
                    }
                }
                Object.defineProperty(base, prop, {
                    configurable: configurable,
                    get() {
                        return handler.get();
                    },
                    set(a) {
                        if (prevSetter !== undefined) {
                            prevSetter(a);
                        }
                        if (a instanceof Object) {
                            var propertiesToCheck = property
                                .split(".")
                                .slice(1);
                            if (setProxyTrap && !isProxyTrapSet) {
                                isProxyTrapSet = true;
                                a = new Proxy(a, {
                                    get: function get(
                                        target,
                                        propertyKey,
                                        val,
                                    ) {
                                        propertiesToCheck.reduce(function (
                                            object,
                                            currentProp,
                                            index,
                                            array,
                                        ) {
                                            var currentObj =
                                                object === null ||
                                                object === void 0
                                                    ? void 0
                                                    : object[currentProp];
                                            if (
                                                index === array.length - 1 &&
                                                currentObj !== constantValue
                                            ) {
                                                object[currentProp] =
                                                    constantValue;
                                            }
                                            return currentObj || object;
                                        }, target);
                                        return Reflect.get(
                                            target,
                                            propertyKey,
                                            val,
                                        );
                                    },
                                });
                            }
                        }
                        handler.set(a);
                    },
                });
                return true;
            };
            var _setChainPropAccess = function setChainPropAccess(
                owner,
                property,
            ) {
                var chainInfo = getPropertyInChain(owner, property);
                var { base: base } = chainInfo;
                var { prop: prop, chain: chain } = chainInfo;
                var inChainPropHandler = {
                    factValue: undefined,
                    init(a) {
                        this.factValue = a;
                        return true;
                    },
                    get() {
                        return this.factValue;
                    },
                    set(a) {
                        if (this.factValue === a) {
                            return;
                        }
                        this.factValue = a;
                        if (a instanceof Object) {
                            _setChainPropAccess(a, chain);
                        }
                    },
                };
                var endPropHandler = {
                    init(a) {
                        if (mustCancel(a)) {
                            return false;
                        }
                        return true;
                    },
                    get() {
                        return constantValue;
                    },
                    set(a) {
                        if (!mustCancel(a)) {
                            return;
                        }
                        constantValue = a;
                    },
                };
                if (!chain) {
                    var isTrapped = trapProp(base, prop, false, endPropHandler);
                    if (isTrapped) {
                        hit(source);
                    }
                    return;
                }
                if (base !== undefined && base[prop] === null) {
                    trapProp(base, prop, true, inChainPropHandler);
                    return;
                }
                if (
                    (base instanceof Object || typeof base === "object") &&
                    isEmptyObject(base)
                ) {
                    trapProp(base, prop, true, inChainPropHandler);
                }
                var propValue = owner[prop];
                if (
                    propValue instanceof Object ||
                    (typeof propValue === "object" && propValue !== null)
                ) {
                    _setChainPropAccess(propValue, chain);
                }
                trapProp(base, prop, true, inChainPropHandler);
            };
            _setChainPropAccess(window, property);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function getNumberFromString(n) {
            var r = parseInt(n, 10);
            return nativeIsNaN(r) ? null : r;
        }
        function noopArray() {
            return [];
        }
        function noopObject() {
            return {};
        }
        function noopFunc() {}
        function noopCallbackFunc() {
            return noopFunc;
        }
        function trueFunc() {
            return true;
        }
        function falseFunc() {
            return false;
        }
        function throwFunc() {
            throw new Error();
        }
        function noopPromiseReject() {
            return Promise.reject();
        }
        function noopPromiseResolve() {
            var e =
                    arguments.length > 0 && void 0 !== arguments[0]
                        ? arguments[0]
                        : "{}",
                t =
                    arguments.length > 1 && void 0 !== arguments[1]
                        ? arguments[1]
                        : "",
                s =
                    arguments.length > 2 && void 0 !== arguments[2]
                        ? arguments[2]
                        : "basic";
            if ("undefined" != typeof Response) {
                var n = new Response(e, {
                    headers: {
                        "Content-Length": `${e.length}`,
                    },
                    status: 200,
                    statusText: "OK",
                });
                return (
                    "opaque" === s
                        ? Object.defineProperties(n, {
                              body: {
                                  value: null,
                              },
                              status: {
                                  value: 0,
                              },
                              ok: {
                                  value: false,
                              },
                              statusText: {
                                  value: "",
                              },
                              url: {
                                  value: "",
                              },
                              type: {
                                  value: s,
                              },
                          })
                        : Object.defineProperties(n, {
                              url: {
                                  value: t,
                              },
                              type: {
                                  value: s,
                              },
                          }),
                    Promise.resolve(n)
                );
            }
        }
        function getPropertyInChain(e, r) {
            var n = r.indexOf(".");
            if (-1 === n)
                return {
                    base: e,
                    prop: r,
                };
            var i = r.slice(0, n);
            if (null === e)
                return {
                    base: e,
                    prop: i,
                    chain: r,
                };
            var t = e[i];
            return (
                (r = r.slice(n + 1)),
                ((e instanceof Object || "object" == typeof e) &&
                    isEmptyObject(e)) ||
                null === t
                    ? {
                          base: e,
                          prop: i,
                          chain: r,
                      }
                    : void 0 !== t
                      ? getPropertyInChain(t, r)
                      : (Object.defineProperty(e, i, {
                            configurable: true,
                        }),
                        {
                            base: e,
                            prop: i,
                            chain: r,
                        })
            );
        }
        function matchStackTrace(e, t) {
            if (!e || "" === e) return true;
            var r = backupRegExpValues();
            if (shouldAbortInlineOrInjectedScript(e, t))
                return (
                    r.length && r[0] !== RegExp.$1 && restoreRegExpValues(r),
                    true
                );
            var n = toRegExp(e),
                a = t
                    .split("\n")
                    .slice(2)
                    .map(function (e) {
                        return e.trim();
                    })
                    .join("\n");
            return (
                r.length && r[0] !== RegExp.$1 && restoreRegExpValues(r),
                getNativeRegexpTest().call(n, a)
            );
        }
        function nativeIsNaN(N) {
            return (Number.isNaN || window.isNaN)(N);
        }
        function isEmptyObject(t) {
            return 0 === Object.keys(t).length && !t.prototype;
        }
        function shouldAbortInlineOrInjectedScript(t, i) {
            var r = "inlineScript",
                n = "injectedScript",
                isInlineScript = function isInlineScript(t) {
                    return t.includes(r);
                },
                isInjectedScript = function isInjectedScript(t) {
                    return t.includes(n);
                };
            if (!isInlineScript(t) && !isInjectedScript(t)) return false;
            var e = window.location.href,
                s = e.indexOf("#");
            -1 !== s && (e = e.slice(0, s));
            var c = i
                .split("\n")
                .slice(2)
                .map(function (t) {
                    return t.trim();
                })
                .map(function (t) {
                    var i,
                        s = /(.*?@)?(\S+)(:\d+)(:\d+)\)?$/.exec(t);
                    if (s) {
                        var c,
                            l,
                            a = s[2],
                            u = s[3],
                            o = s[4];
                        if (
                            (null !== (c = a) &&
                                void 0 !== c &&
                                c.startsWith("(") &&
                                (a = a.slice(1)),
                            null !== (l = a) &&
                                void 0 !== l &&
                                l.startsWith("<anonymous>"))
                        ) {
                            var d;
                            a = n;
                            var f =
                                void 0 !== s[1]
                                    ? s[1].slice(0, -1)
                                    : t.slice(0, s.index).trim();
                            (null !== (d = f) &&
                                void 0 !== d &&
                                d.startsWith("at") &&
                                (f = f.slice(2).trim()),
                                (i = `${f} ${a}${u}${o}`.trim()));
                        } else
                            i =
                                a === e
                                    ? `${r}${u}${o}`.trim()
                                    : `${a}${u}${o}`.trim();
                    } else i = t;
                    return i;
                });
            if (c)
                for (var l = 0; l < c.length; l += 1) {
                    if (
                        isInlineScript(t) &&
                        c[l].startsWith(r) &&
                        c[l].match(toRegExp(t))
                    )
                        return true;
                    if (
                        isInjectedScript(t) &&
                        c[l].startsWith(n) &&
                        c[l].match(toRegExp(t))
                    )
                        return true;
                }
            return false;
        }
        function getNativeRegexpTest() {
            var t = Object.getOwnPropertyDescriptor(RegExp.prototype, "test"),
                e = null == t ? void 0 : t.value;
            if (t && "function" == typeof t.value) return e;
            throw new Error("RegExp.prototype.test is not a function");
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function backupRegExpValues() {
            try {
                for (var r = [], e = 1; e < 10; e += 1) {
                    var a = `$${e}`;
                    if (!RegExp[a]) break;
                    r.push(RegExp[a]);
                }
                return r;
            } catch (r) {
                return [];
            }
        }
        function restoreRegExpValues(e) {
            if (e.length)
                try {
                    var r = "";
                    r =
                        1 === e.length
                            ? `(${e[0]})`
                            : e.reduce(function (e, r, t) {
                                  return 1 === t
                                      ? `(${e}),(${r})`
                                      : `${e},(${r})`;
                              });
                    var t = new RegExp(r);
                    e.toString().replace(t, "");
                } catch (e) {
                    var n = `Failed to restore RegExp values: ${e}`;
                    console.log(n);
                }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            setConstant.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function setCookie(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function setCookie(source, name, value) {
            var path =
                arguments.length > 3 && arguments[3] !== undefined
                    ? arguments[3]
                    : "/";
            var domain =
                arguments.length > 4 && arguments[4] !== undefined
                    ? arguments[4]
                    : "";
            var validValue = getLimitedCookieValue(value);
            if (validValue === null) {
                logMessage(source, `Invalid cookie value: '${validValue}'`);
                return;
            }
            if (!isValidCookiePath(path)) {
                logMessage(source, `Invalid cookie path: '${path}'`);
                return;
            }
            if (!document.location.origin.includes(domain)) {
                logMessage(
                    source,
                    `Cookie domain not matched by origin: '${domain}'`,
                );
                return;
            }
            var cookieToSet = serializeCookie(
                name,
                validValue,
                path,
                domain,
                false,
            );
            if (!cookieToSet) {
                logMessage(source, "Invalid cookie name or value");
                return;
            }
            hit(source);
            document.cookie = cookieToSet;
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function nativeIsNaN(N) {
            return (Number.isNaN || window.isNaN)(N);
        }
        function getLimitedCookieValue(e) {
            if (!e) return null;
            var n;
            if (
                new Set([
                    "true",
                    "t",
                    "false",
                    "f",
                    "yes",
                    "y",
                    "no",
                    "n",
                    "ok",
                    "on",
                    "off",
                    "accept",
                    "accepted",
                    "notaccepted",
                    "reject",
                    "rejected",
                    "allow",
                    "allowed",
                    "disallow",
                    "deny",
                    "enable",
                    "enabled",
                    "disable",
                    "disabled",
                    "necessary",
                    "required",
                    "hide",
                    "hidden",
                    "essential",
                    "nonessential",
                    "checked",
                    "unchecked",
                    "forbidden",
                    "forever",
                ]).has(e.toLowerCase())
            )
                n = e;
            else if ("emptyArr" === e) n = "[]";
            else if ("emptyObj" === e) n = "{}";
            else {
                if (!/^\d+$/.test(e)) return null;
                if (((n = parseFloat(e)), nativeIsNaN(n))) return null;
                if (Math.abs(n) < 0 || Math.abs(n) > 32767) return null;
            }
            return n;
        }
        function serializeCookie(e, o, i) {
            var n =
                    arguments.length > 3 && void 0 !== arguments[3]
                        ? arguments[3]
                        : "",
                t =
                    !(arguments.length > 4 && void 0 !== arguments[4]) ||
                    arguments[4];
            if ((!t && `${o}`.includes(";")) || e.includes(";")) return null;
            var r = `${e}=${t ? encodeURIComponent(o) : o}`;
            if (e.startsWith("__Host-"))
                return (
                    (r += "; path=/; secure"),
                    n &&
                        console.debug(
                            `Domain value: "${n}" has been ignored, because is not allowed for __Host- prefixed cookies`,
                        ),
                    r
                );
            var s = getCookiePath(i);
            return (
                s && (r += `; ${s}`),
                e.startsWith("__Secure-") && (r += "; secure"),
                n && (r += `; domain=${n}`),
                r
            );
        }
        function isValidCookiePath(n) {
            return "/" === n || "none" === n;
        }
        function getCookiePath(t) {
            return "/" === t ? "path=/" : "";
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            setCookie.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function setCookieReload(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function setCookieReload(source, name, value) {
            var path =
                arguments.length > 3 && arguments[3] !== undefined
                    ? arguments[3]
                    : "/";
            var domain =
                arguments.length > 4 && arguments[4] !== undefined
                    ? arguments[4]
                    : "";
            if (isCookieSetWithValue(document.cookie, name, value)) {
                return;
            }
            var validValue = getLimitedCookieValue(value);
            if (validValue === null) {
                logMessage(source, `Invalid cookie value: '${value}'`);
                return;
            }
            if (!isValidCookiePath(path)) {
                logMessage(source, `Invalid cookie path: '${path}'`);
                return;
            }
            if (!document.location.origin.includes(domain)) {
                logMessage(
                    source,
                    `Cookie domain not matched by origin: '${domain}'`,
                );
                return;
            }
            var cookieToSet = serializeCookie(
                name,
                validValue,
                path,
                domain,
                false,
            );
            if (!cookieToSet) {
                logMessage(source, "Invalid cookie name or value");
                return;
            }
            document.cookie = cookieToSet;
            hit(source);
            if (isCookieSetWithValue(document.cookie, name, value)) {
                window.location.reload();
            }
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function nativeIsNaN(N) {
            return (Number.isNaN || window.isNaN)(N);
        }
        function isCookieSetWithValue(e, t, r) {
            return e.split(";").some(function (e) {
                var n = e.indexOf("=");
                if (-1 === n) return false;
                var i = e.slice(0, n).trim(),
                    a = e.slice(n + 1).trim();
                if (
                    new Set(["$now$", "$currentDate$", "$currentISODate$"]).has(
                        r,
                    )
                ) {
                    var u = Date.now(),
                        s = /^\d+$/.test(a)
                            ? parseInt(a, 10)
                            : new Date(a).getTime();
                    return t === i && s > u - 864e5;
                }
                return t === i && r === a;
            });
        }
        function getLimitedCookieValue(e) {
            if (!e) return null;
            var n;
            if (
                new Set([
                    "true",
                    "t",
                    "false",
                    "f",
                    "yes",
                    "y",
                    "no",
                    "n",
                    "ok",
                    "on",
                    "off",
                    "accept",
                    "accepted",
                    "notaccepted",
                    "reject",
                    "rejected",
                    "allow",
                    "allowed",
                    "disallow",
                    "deny",
                    "enable",
                    "enabled",
                    "disable",
                    "disabled",
                    "necessary",
                    "required",
                    "hide",
                    "hidden",
                    "essential",
                    "nonessential",
                    "checked",
                    "unchecked",
                    "forbidden",
                    "forever",
                ]).has(e.toLowerCase())
            )
                n = e;
            else if ("emptyArr" === e) n = "[]";
            else if ("emptyObj" === e) n = "{}";
            else {
                if (!/^\d+$/.test(e)) return null;
                if (((n = parseFloat(e)), nativeIsNaN(n))) return null;
                if (Math.abs(n) < 0 || Math.abs(n) > 32767) return null;
            }
            return n;
        }
        function serializeCookie(e, o, i) {
            var n =
                    arguments.length > 3 && void 0 !== arguments[3]
                        ? arguments[3]
                        : "",
                t =
                    !(arguments.length > 4 && void 0 !== arguments[4]) ||
                    arguments[4];
            if ((!t && `${o}`.includes(";")) || e.includes(";")) return null;
            var r = `${e}=${t ? encodeURIComponent(o) : o}`;
            if (e.startsWith("__Host-"))
                return (
                    (r += "; path=/; secure"),
                    n &&
                        console.debug(
                            `Domain value: "${n}" has been ignored, because is not allowed for __Host- prefixed cookies`,
                        ),
                    r
                );
            var s = getCookiePath(i);
            return (
                s && (r += `; ${s}`),
                e.startsWith("__Secure-") && (r += "; secure"),
                n && (r += `; domain=${n}`),
                r
            );
        }
        function isValidCookiePath(n) {
            return "/" === n || "none" === n;
        }
        function getCookiePath(t) {
            return "/" === t ? "path=/" : "";
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            setCookieReload.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function setLocalStorageItem(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function setLocalStorageItem(source, key, value) {
            if (typeof key === "undefined") {
                logMessage(source, "Item key should be specified.");
                return;
            }
            var validValue;
            try {
                validValue = getLimitedStorageItemValue(value);
            } catch (_unused) {
                logMessage(source, `Invalid storage item value: '${value}'`);
                return;
            }
            var { localStorage: localStorage } = window;
            if (validValue === "$remove$") {
                removeStorageItem(source, localStorage, key);
            } else {
                setStorageItem(source, localStorage, key, validValue);
            }
            hit(source);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function nativeIsNaN(N) {
            return (Number.isNaN || window.isNaN)(N);
        }
        function setStorageItem(e, t, s, a) {
            try {
                t.setItem(s, a);
            } catch (t) {
                var o = `Unable to set storage item due to: ${t.message}`;
                logMessage(e, o);
            }
        }
        function removeStorageItem(e, t, o) {
            try {
                if (
                    o.startsWith("/") &&
                    (o.endsWith("/") || o.endsWith("/i")) &&
                    isValidStrPattern(o)
                ) {
                    var r = toRegExp(o);
                    Object.keys(t).forEach(function (e) {
                        r.test(e) && t.removeItem(e);
                    });
                } else t.removeItem(o);
            } catch (t) {
                var s = `Unable to remove storage item due to: ${t.message}`;
                logMessage(e, s);
            }
        }
        function getLimitedStorageItemValue(e) {
            if ("string" != typeof e) throw new Error("Invalid value");
            var r;
            if (
                new Set([
                    "undefined",
                    "false",
                    "true",
                    "null",
                    "",
                    "yes",
                    "no",
                    "on",
                    "off",
                    "accept",
                    "accepted",
                    "reject",
                    "rejected",
                    "allowed",
                    "denied",
                    "forbidden",
                    "forever",
                ]).has(e.toLowerCase())
            )
                r = e;
            else if ("emptyArr" === e) r = "[]";
            else if ("emptyObj" === e) r = "{}";
            else if (/^\d+$/.test(e)) {
                if (((r = parseFloat(e)), nativeIsNaN(r)))
                    throw new Error("Invalid value");
                if (Math.abs(r) > 32767) throw new Error("Invalid value");
            } else {
                if ("$remove$" !== e) throw new Error("Invalid value");
                r = "$remove$";
            }
            return r;
        }
        function isValidStrPattern(e) {
            var t,
                n = escapeRegExp(e);
            "/" === e[0] && "/" === e[e.length - 1] && (n = e.slice(1, -1));
            try {
                ((t = new RegExp(n)), (t = !0));
            } catch (e) {
                t = false;
            }
            return t;
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function escapeRegExp(e) {
            return e.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            setLocalStorageItem.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function setPopadsDummy(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function setPopadsDummy(source) {
            delete window.PopAds;
            delete window.popns;
            Object.defineProperties(window, {
                PopAds: {
                    get: function get() {
                        hit(source);
                        return {};
                    },
                },
                popns: {
                    get: function get() {
                        hit(source);
                        return {};
                    },
                },
            });
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            setPopadsDummy.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function setSessionStorageItem(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function setSessionStorageItem(source, key, value) {
            if (typeof key === "undefined") {
                logMessage(source, "Item key should be specified.");
                return;
            }
            var validValue;
            try {
                validValue = getLimitedStorageItemValue(value);
            } catch (_unused) {
                logMessage(source, `Invalid storage item value: '${value}'`);
                return;
            }
            var { sessionStorage: sessionStorage } = window;
            if (validValue === "$remove$") {
                removeStorageItem(source, sessionStorage, key);
            } else {
                setStorageItem(source, sessionStorage, key, validValue);
            }
            hit(source);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function nativeIsNaN(N) {
            return (Number.isNaN || window.isNaN)(N);
        }
        function setStorageItem(e, t, s, a) {
            try {
                t.setItem(s, a);
            } catch (t) {
                var o = `Unable to set storage item due to: ${t.message}`;
                logMessage(e, o);
            }
        }
        function removeStorageItem(e, t, o) {
            try {
                if (
                    o.startsWith("/") &&
                    (o.endsWith("/") || o.endsWith("/i")) &&
                    isValidStrPattern(o)
                ) {
                    var r = toRegExp(o);
                    Object.keys(t).forEach(function (e) {
                        r.test(e) && t.removeItem(e);
                    });
                } else t.removeItem(o);
            } catch (t) {
                var s = `Unable to remove storage item due to: ${t.message}`;
                logMessage(e, s);
            }
        }
        function getLimitedStorageItemValue(e) {
            if ("string" != typeof e) throw new Error("Invalid value");
            var r;
            if (
                new Set([
                    "undefined",
                    "false",
                    "true",
                    "null",
                    "",
                    "yes",
                    "no",
                    "on",
                    "off",
                    "accept",
                    "accepted",
                    "reject",
                    "rejected",
                    "allowed",
                    "denied",
                    "forbidden",
                    "forever",
                ]).has(e.toLowerCase())
            )
                r = e;
            else if ("emptyArr" === e) r = "[]";
            else if ("emptyObj" === e) r = "{}";
            else if (/^\d+$/.test(e)) {
                if (((r = parseFloat(e)), nativeIsNaN(r)))
                    throw new Error("Invalid value");
                if (Math.abs(r) > 32767) throw new Error("Invalid value");
            } else {
                if ("$remove$" !== e) throw new Error("Invalid value");
                r = "$remove$";
            }
            return r;
        }
        function isValidStrPattern(e) {
            var t,
                n = escapeRegExp(e);
            "/" === e[0] && "/" === e[e.length - 1] && (n = e.slice(1, -1));
            try {
                ((t = new RegExp(n)), (t = !0));
            } catch (e) {
                t = false;
            }
            return t;
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function escapeRegExp(e) {
            return e.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            setSessionStorageItem.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function spoofCSS(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function spoofCSS(
            source,
            selectors,
            cssPropertyName,
            cssPropertyValue,
        ) {
            if (!selectors) {
                return;
            }
            var uboAliases = [
                "spoof-css.js",
                "ubo-spoof-css.js",
                "ubo-spoof-css",
            ];
            function convertToCamelCase(cssProperty) {
                if (!cssProperty.includes("-")) {
                    return cssProperty;
                }
                var splittedProperty = cssProperty.split("-");
                var firstPart = splittedProperty[0];
                var secondPart = splittedProperty[1];
                return `${firstPart}${secondPart[0].toUpperCase()}${secondPart.slice(1)}`;
            }
            var shouldDebug = !!(
                cssPropertyName === "debug" && cssPropertyValue
            );
            var propToValueMap = new Map();
            if (uboAliases.includes(source.name)) {
                var { args: args } = source;
                var arrayOfProperties = [];
                var isDebug = args.at(-2);
                if (isDebug === "debug") {
                    arrayOfProperties = args.slice(1, -2);
                } else {
                    arrayOfProperties = args.slice(1);
                }
                for (var i = 0; i < arrayOfProperties.length; i += 2) {
                    if (arrayOfProperties[i] === "") {
                        break;
                    }
                    propToValueMap.set(
                        convertToCamelCase(arrayOfProperties[i]),
                        arrayOfProperties[i + 1],
                    );
                }
            } else if (cssPropertyName && cssPropertyValue && !shouldDebug) {
                propToValueMap.set(
                    convertToCamelCase(cssPropertyName),
                    cssPropertyValue,
                );
            }
            var spoofStyle = function spoofStyle(cssProperty, realCssValue) {
                return propToValueMap.has(cssProperty)
                    ? propToValueMap.get(cssProperty)
                    : realCssValue;
            };
            var setRectValue = function setRectValue(rect, prop, value) {
                Object.defineProperty(rect, prop, {
                    value: parseFloat(value),
                });
            };
            var getter = function getter(target, prop, receiver) {
                hit(source);
                if (prop === "toString") {
                    return target.toString.bind(target);
                }
                return Reflect.get(target, prop, receiver);
            };
            var getComputedStyleWrapper = function getComputedStyleWrapper(
                target,
                thisArg,
                args,
            ) {
                if (shouldDebug) {
                    debugger;
                }
                var style = Reflect.apply(target, thisArg, args);
                if (!args[0].matches(selectors)) {
                    return style;
                }
                var proxiedStyle = new Proxy(style, {
                    get(target, prop) {
                        var CSSStyleProp = target[prop];
                        if (typeof CSSStyleProp !== "function") {
                            return spoofStyle(prop, CSSStyleProp || "");
                        }
                        if (prop !== "getPropertyValue") {
                            return CSSStyleProp.bind(target);
                        }
                        var getPropertyValueFunc = new Proxy(CSSStyleProp, {
                            apply(target, thisArg, args) {
                                var cssName = args[0];
                                var cssValue = thisArg[cssName];
                                return spoofStyle(cssName, cssValue);
                            },
                            get: getter,
                        });
                        return getPropertyValueFunc;
                    },
                    getOwnPropertyDescriptor(target, prop) {
                        if (propToValueMap.has(prop)) {
                            return {
                                configurable: true,
                                enumerable: true,
                                value: propToValueMap.get(prop),
                                writable: true,
                            };
                        }
                        return Reflect.getOwnPropertyDescriptor(target, prop);
                    },
                });
                hit(source);
                return proxiedStyle;
            };
            var getComputedStyleHandler = {
                apply: getComputedStyleWrapper,
                get: getter,
            };
            window.getComputedStyle = new Proxy(
                window.getComputedStyle,
                getComputedStyleHandler,
            );
            var getBoundingClientRectWrapper =
                function getBoundingClientRectWrapper(target, thisArg, args) {
                    if (shouldDebug) {
                        debugger;
                    }
                    var rect = Reflect.apply(target, thisArg, args);
                    if (!thisArg.matches(selectors)) {
                        return rect;
                    }
                    var { x: x, y: y, height: height, width: width } = rect;
                    var newDOMRect = new window.DOMRect(x, y, width, height);
                    if (propToValueMap.has("top")) {
                        setRectValue(
                            newDOMRect,
                            "top",
                            propToValueMap.get("top"),
                        );
                    }
                    if (propToValueMap.has("bottom")) {
                        setRectValue(
                            newDOMRect,
                            "bottom",
                            propToValueMap.get("bottom"),
                        );
                    }
                    if (propToValueMap.has("left")) {
                        setRectValue(
                            newDOMRect,
                            "left",
                            propToValueMap.get("left"),
                        );
                    }
                    if (propToValueMap.has("right")) {
                        setRectValue(
                            newDOMRect,
                            "right",
                            propToValueMap.get("right"),
                        );
                    }
                    if (propToValueMap.has("height")) {
                        setRectValue(
                            newDOMRect,
                            "height",
                            propToValueMap.get("height"),
                        );
                    }
                    if (propToValueMap.has("width")) {
                        setRectValue(
                            newDOMRect,
                            "width",
                            propToValueMap.get("width"),
                        );
                    }
                    hit(source);
                    return newDOMRect;
                };
            var getBoundingClientRectHandler = {
                apply: getBoundingClientRectWrapper,
                get: getter,
            };
            window.Element.prototype.getBoundingClientRect = new Proxy(
                window.Element.prototype.getBoundingClientRect,
                getBoundingClientRectHandler,
            );
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            spoofCSS.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function trustedClickElement(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function trustedClickElement(source, selectors) {
            var extraMatch =
                arguments.length > 2 && arguments[2] !== undefined
                    ? arguments[2]
                    : "";
            var delay =
                arguments.length > 3 && arguments[3] !== undefined
                    ? arguments[3]
                    : NaN;
            var reload =
                arguments.length > 4 && arguments[4] !== undefined
                    ? arguments[4]
                    : "";
            if (!selectors) {
                return;
            }
            var SHADOW_COMBINATOR = " >>> ";
            var OBSERVER_TIMEOUT_MS = 1e4;
            var THROTTLE_DELAY_MS = 20;
            var STATIC_CLICK_DELAY_MS = 150;
            var STATIC_RELOAD_DELAY_MS = 500;
            var COOKIE_MATCH_MARKER = "cookie:";
            var LOCAL_STORAGE_MATCH_MARKER = "localStorage:";
            var TEXT_MATCH_MARKER = "containsText:";
            var RELOAD_ON_FINAL_CLICK_MARKER = "reloadAfterClick";
            var SELECTORS_DELIMITER = ",";
            var COOKIE_STRING_DELIMITER = ";";
            var COLON = ":";
            var EXTRA_MATCH_DELIMITER =
                /(,\s*){1}(?=!?cookie:|!?localStorage:|containsText:)/;
            var sleep = function sleep(delayMs) {
                return new Promise(function (resolve) {
                    setTimeout(resolve, delayMs);
                });
            };
            if (selectors.includes(SHADOW_COMBINATOR)) {
                var attachShadowWrapper = function attachShadowWrapper(
                    target,
                    thisArg,
                    argumentsList,
                ) {
                    var _argumentsList$;
                    var mode =
                        (_argumentsList$ = argumentsList[0]) === null ||
                        _argumentsList$ === void 0
                            ? void 0
                            : _argumentsList$.mode;
                    if (mode === "closed") {
                        argumentsList[0].mode = "open";
                    }
                    return Reflect.apply(target, thisArg, argumentsList);
                };
                var attachShadowHandler = {
                    apply: attachShadowWrapper,
                };
                window.Element.prototype.attachShadow = new Proxy(
                    window.Element.prototype.attachShadow,
                    attachShadowHandler,
                );
            }
            var parsedDelay;
            if (delay) {
                parsedDelay = parseInt(String(delay), 10);
                var isValidDelay =
                    !Number.isNaN(parsedDelay) ||
                    parsedDelay < OBSERVER_TIMEOUT_MS;
                if (!isValidDelay) {
                    var message = `Passed delay '${delay}' is invalid or bigger than ${OBSERVER_TIMEOUT_MS} ms`;
                    logMessage(source, message);
                    return;
                }
            }
            var canClick = !parsedDelay;
            var cookieMatches = [];
            var localStorageMatches = [];
            var textMatches = "";
            var isInvertedMatchCookie = false;
            var isInvertedMatchLocalStorage = false;
            if (extraMatch) {
                var parsedExtraMatch = extraMatch
                    .split(EXTRA_MATCH_DELIMITER)
                    .map(function (matchStr) {
                        return matchStr.trim();
                    });
                parsedExtraMatch.forEach(function (matchStr) {
                    if (matchStr.includes(COOKIE_MATCH_MARKER)) {
                        var {
                            isInvertedMatch: isInvertedMatch,
                            matchValue: matchValue,
                        } = parseMatchArg(matchStr);
                        isInvertedMatchCookie = isInvertedMatch;
                        var cookieMatch = matchValue.replace(
                            COOKIE_MATCH_MARKER,
                            "",
                        );
                        cookieMatches.push(cookieMatch);
                    }
                    if (matchStr.includes(LOCAL_STORAGE_MATCH_MARKER)) {
                        var {
                            isInvertedMatch: _isInvertedMatch,
                            matchValue: _matchValue,
                        } = parseMatchArg(matchStr);
                        isInvertedMatchLocalStorage = _isInvertedMatch;
                        var localStorageMatch = _matchValue.replace(
                            LOCAL_STORAGE_MATCH_MARKER,
                            "",
                        );
                        localStorageMatches.push(localStorageMatch);
                    }
                    if (matchStr.includes(TEXT_MATCH_MARKER)) {
                        var { matchValue: _matchValue2 } =
                            parseMatchArg(matchStr);
                        var textMatch = _matchValue2.replace(
                            TEXT_MATCH_MARKER,
                            "",
                        );
                        textMatches = textMatch;
                    }
                });
            }
            if (cookieMatches.length > 0) {
                var parsedCookieMatches = parseCookieString(
                    cookieMatches.join(COOKIE_STRING_DELIMITER),
                );
                var parsedCookies = parseCookieString(document.cookie);
                var cookieKeys = Object.keys(parsedCookies);
                if (cookieKeys.length === 0) {
                    return;
                }
                var cookiesMatched = Object.keys(parsedCookieMatches).every(
                    function (key) {
                        var valueMatch = parsedCookieMatches[key]
                            ? toRegExp(parsedCookieMatches[key])
                            : null;
                        var keyMatch = toRegExp(key);
                        return cookieKeys.some(function (cookieKey) {
                            var keysMatched = keyMatch.test(cookieKey);
                            if (!keysMatched) {
                                return false;
                            }
                            if (!valueMatch) {
                                return true;
                            }
                            var parsedCookieValue = parsedCookies[cookieKey];
                            if (!parsedCookieValue) {
                                return false;
                            }
                            return valueMatch.test(parsedCookieValue);
                        });
                    },
                );
                var shouldRun = cookiesMatched !== isInvertedMatchCookie;
                if (!shouldRun) {
                    return;
                }
            }
            if (localStorageMatches.length > 0) {
                var localStorageMatched = localStorageMatches.every(
                    function (str) {
                        var itemValue = window.localStorage.getItem(str);
                        return itemValue || itemValue === "";
                    },
                );
                var _shouldRun =
                    localStorageMatched !== isInvertedMatchLocalStorage;
                if (!_shouldRun) {
                    return;
                }
            }
            var textMatchRegexp = textMatches ? toRegExp(textMatches) : null;
            var selectorsSequence = selectors
                .split(SELECTORS_DELIMITER)
                .map(function (selector) {
                    return selector.trim();
                });
            var createElementObj = function createElementObj(
                element,
                selector,
            ) {
                return {
                    element: element || null,
                    clicked: false,
                    selectorText: selector || null,
                };
            };
            var elementsSequence = Array(selectorsSequence.length).fill(
                createElementObj(null),
            );
            var findAndClickElement = function findAndClickElement(elementObj) {
                try {
                    if (!elementObj.selectorText) {
                        return;
                    }
                    var element = queryShadowSelector(elementObj.selectorText);
                    if (!element) {
                        logMessage(
                            source,
                            `Could not find element: '${elementObj.selectorText}'`,
                        );
                        return;
                    }
                    element.click();
                    elementObj.clicked = true;
                } catch (error) {
                    logMessage(
                        source,
                        `Could not click element: '${elementObj.selectorText}'`,
                    );
                }
            };
            var shouldReloadAfterClick = false;
            var reloadDelayMs = STATIC_RELOAD_DELAY_MS;
            if (reload) {
                var reloadSplit = reload.split(COLON);
                var reloadMarker = reloadSplit[0];
                var reloadValue = reloadSplit[1];
                if (reloadMarker !== RELOAD_ON_FINAL_CLICK_MARKER) {
                    logMessage(
                        source,
                        `Passed reload option '${reload}' is invalid`,
                    );
                    return;
                }
                if (reloadValue) {
                    var passedReload = Number(reloadValue);
                    if (Number.isNaN(passedReload)) {
                        logMessage(
                            source,
                            `Passed reload delay value '${passedReload}' is invalid`,
                        );
                        return;
                    }
                    if (passedReload > OBSERVER_TIMEOUT_MS) {
                        logMessage(
                            source,
                            `Passed reload delay value '${passedReload}' is bigger than maximum ${OBSERVER_TIMEOUT_MS} ms`,
                        );
                        return;
                    }
                    reloadDelayMs = passedReload;
                }
                shouldReloadAfterClick = true;
            }
            var canReload = true;
            var clickElementsBySequence =
                async function clickElementsBySequence() {
                    for (var i = 0; i < elementsSequence.length; i += 1) {
                        var elementObj = elementsSequence[i];
                        if (i >= 1) {
                            await sleep(STATIC_CLICK_DELAY_MS);
                        }
                        if (!elementObj.element) {
                            break;
                        }
                        if (!elementObj.clicked) {
                            if (elementObj.element.isConnected) {
                                elementObj.element.click();
                                elementObj.clicked = true;
                            } else {
                                findAndClickElement(elementObj);
                            }
                        }
                    }
                    var allElementsClicked = elementsSequence.every(
                        function (elementObj) {
                            return elementObj.clicked === true;
                        },
                    );
                    if (allElementsClicked) {
                        if (shouldReloadAfterClick && canReload) {
                            canReload = false;
                            setTimeout(function () {
                                window.location.reload();
                            }, reloadDelayMs);
                        }
                        hit(source);
                    }
                };
            var handleElement = function handleElement(element, i, selector) {
                var elementObj = createElementObj(element, selector);
                elementsSequence[i] = elementObj;
                if (canClick) {
                    clickElementsBySequence();
                }
            };
            var fulfillAndHandleSelectors =
                function fulfillAndHandleSelectors() {
                    var fulfilledSelectors = [];
                    selectorsSequence.forEach(function (selector, i) {
                        if (!selector) {
                            return;
                        }
                        var element = queryShadowSelector(
                            selector,
                            document.documentElement,
                            textMatchRegexp,
                        );
                        if (!element) {
                            return;
                        }
                        handleElement(element, i, selector);
                        fulfilledSelectors.push(selector);
                    });
                    selectorsSequence = selectorsSequence.map(
                        function (selector) {
                            return selector &&
                                fulfilledSelectors.includes(selector)
                                ? null
                                : selector;
                        },
                    );
                    return selectorsSequence;
                };
            var findElements = function findElements(mutations, observer) {
                selectorsSequence = fulfillAndHandleSelectors();
                var allSelectorsFulfilled = selectorsSequence.every(
                    function (selector) {
                        return selector === null;
                    },
                );
                if (allSelectorsFulfilled) {
                    observer.disconnect();
                }
            };
            var initializeMutationObserver =
                function initializeMutationObserver() {
                    var observer = new MutationObserver(
                        throttle(findElements, THROTTLE_DELAY_MS),
                    );
                    observer.observe(document.documentElement, {
                        attributes: true,
                        childList: true,
                        subtree: true,
                    });
                    setTimeout(function () {
                        return observer.disconnect();
                    }, OBSERVER_TIMEOUT_MS);
                };
            var checkInitialElements = function checkInitialElements() {
                var foundElements = selectorsSequence.every(
                    function (selector) {
                        if (!selector) {
                            return false;
                        }
                        var element = queryShadowSelector(
                            selector,
                            document.documentElement,
                            textMatchRegexp,
                        );
                        return !!element;
                    },
                );
                if (foundElements) {
                    fulfillAndHandleSelectors();
                } else {
                    initializeMutationObserver();
                }
            };
            checkInitialElements();
            if (parsedDelay) {
                setTimeout(function () {
                    clickElementsBySequence();
                    canClick = true;
                }, parsedDelay);
            }
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function parseCookieString(i) {
            var r = i.split(";"),
                n = {};
            return (
                r.forEach(function (i) {
                    var r,
                        t = "",
                        e = i.indexOf("=");
                    (-1 === e
                        ? (r = i.trim())
                        : ((r = i.slice(0, e).trim()), (t = i.slice(e + 1))),
                        (n[r] = t || null));
                }),
                n
            );
        }
        function throttle(n, t) {
            var r,
                e = false,
                _wrapper8 = function _wrapper() {
                    for (
                        var o = arguments.length, u = new Array(o), f = 0;
                        f < o;
                        f++
                    )
                        u[f] = arguments[f];
                    e
                        ? (r = u)
                        : (n(...u),
                          (e = true),
                          setTimeout(function () {
                              ((e = false), r && (_wrapper8(...r), (r = null)));
                          }, t));
                };
            return _wrapper8;
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function parseMatchArg(t) {
            var e = !!t && (null == t ? void 0 : t.startsWith("!")),
                a = e ? t.slice(1) : t;
            return {
                isInvertedMatch: e,
                matchRegexp: toRegExp(a),
                matchValue: a,
            };
        }
        function queryShadowSelector(e) {
            var t =
                    arguments.length > 1 && void 0 !== arguments[1]
                        ? arguments[1]
                        : document.documentElement,
                o =
                    arguments.length > 2 && void 0 !== arguments[2]
                        ? arguments[2]
                        : null,
                r = " >>> ",
                l = e.indexOf(r);
            if (-1 === l)
                return o ? findElementWithText(t, e, o) : t.querySelector(e);
            var n = e.slice(0, l).trim(),
                i = t.querySelector(n);
            return i && i.shadowRoot
                ? queryShadowSelector(e.slice(l + 5).trim(), i.shadowRoot, o)
                : null;
        }
        function doesElementContainText(t, e) {
            var { textContent: n } = t;
            return !!n && e.test(n);
        }
        function findElementWithText(e, n, t) {
            for (var l = e.querySelectorAll(n), r = 0; r < l.length; r += 1)
                if (doesElementContainText(l[r], t)) return l[r];
            return null;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            trustedClickElement.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function trustedCreateElement(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function trustedCreateElement(source, parentSelector, tagName) {
            var attributePairs =
                arguments.length > 3 && arguments[3] !== undefined
                    ? arguments[3]
                    : "";
            var textContent =
                arguments.length > 4 && arguments[4] !== undefined
                    ? arguments[4]
                    : "";
            var cleanupDelayMs =
                arguments.length > 5 && arguments[5] !== undefined
                    ? arguments[5]
                    : NaN;
            if (!parentSelector || !tagName) {
                return;
            }
            var IFRAME_WINDOW_NAME = "trusted-create-element-window";
            if (window.name === IFRAME_WINDOW_NAME) {
                return;
            }
            var logError = function logError(prefix, error) {
                logMessage(
                    source,
                    `${prefix} due to ${getErrorMessage(error)}`,
                );
            };
            var element;
            try {
                element = document.createElement(tagName);
                element.textContent = textContent;
            } catch (e) {
                logError(`Cannot create element with tag name '${tagName}'`, e);
                return;
            }
            var attributes = [];
            try {
                attributes = parseAttributePairs(attributePairs);
            } catch (e) {
                logError(
                    `Cannot parse attributePairs param: '${attributePairs}'`,
                    e,
                );
                return;
            }
            attributes.forEach(function (attr) {
                try {
                    element.setAttribute(attr.name, attr.value);
                } catch (e) {
                    logError(
                        `Cannot set attribute '${attr.name}' with value '${attr.value}'`,
                        e,
                    );
                }
            });
            var timerId;
            var elementCreated = false;
            var elementRemoved = false;
            var findParentAndAppendEl = function findParentAndAppendEl(
                parentElSelector,
                el,
                removeElDelayMs,
            ) {
                var parentEl;
                try {
                    parentEl = document.querySelector(parentElSelector);
                } catch (e) {
                    logError(
                        `Cannot find parent element by selector '${parentElSelector}'`,
                        e,
                    );
                    return false;
                }
                if (!parentEl) {
                    logMessage(
                        source,
                        `No parent element found by selector: '${parentElSelector}'`,
                    );
                    return false;
                }
                try {
                    if (!parentEl.contains(el)) {
                        parentEl.append(el);
                    }
                    if (el instanceof HTMLIFrameElement && el.contentWindow) {
                        el.contentWindow.name = IFRAME_WINDOW_NAME;
                    }
                    elementCreated = true;
                    hit(source);
                } catch (e) {
                    logError(
                        `Cannot append child to parent by selector '${parentElSelector}'`,
                        e,
                    );
                    return false;
                }
                if (!nativeIsNaN(removeElDelayMs)) {
                    timerId = setTimeout(function () {
                        el.remove();
                        elementRemoved = true;
                        clearTimeout(timerId);
                    }, removeElDelayMs);
                }
                return true;
            };
            if (
                !findParentAndAppendEl(parentSelector, element, cleanupDelayMs)
            ) {
                observeDocumentWithTimeout(function (mutations, observer) {
                    if (
                        elementRemoved ||
                        elementCreated ||
                        findParentAndAppendEl(
                            parentSelector,
                            element,
                            cleanupDelayMs,
                        )
                    ) {
                        observer.disconnect();
                    }
                });
            }
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function observeDocumentWithTimeout(e) {
            var t =
                    arguments.length > 1 && void 0 !== arguments[1]
                        ? arguments[1]
                        : {
                              subtree: true,
                              childList: true,
                          },
                n =
                    arguments.length > 2 && void 0 !== arguments[2]
                        ? arguments[2]
                        : 1e4,
                o = new MutationObserver(function (n, o) {
                    (o.disconnect(),
                        e(n, o),
                        o.observe(document.documentElement, t));
                });
            (o.observe(document.documentElement, t),
                "number" == typeof n &&
                    setTimeout(function () {
                        return o.disconnect();
                    }, n));
        }
        function nativeIsNaN(N) {
            return (Number.isNaN || window.isNaN)(N);
        }
        function parseAttributePairs(e) {
            if (!e) return [];
            for (var r = [], t = 0; t < e.length; t += 1) {
                for (
                    var i = "", n = "";
                    t < e.length && "=" !== e[t] && " " !== e[t];

                )
                    ((i += e[t]), (t += 1));
                if (t < e.length && "=" === e[t]) {
                    var o = null;
                    if ("'" !== e[(t += 1)] && '"' !== e[t])
                        throw new Error(
                            `Attribute value should be quoted: "${e.slice(t)}"`,
                        );
                    for (o = e[t], t += 1; t < e.length; t += 1)
                        if (e[t] === o) {
                            if ("\\" !== e[t - 1]) {
                                ((t += 1), (o = null));
                                break;
                            }
                            n = `${n.slice(0, -1)}${o}`;
                        } else n += e[t];
                    if (null !== o)
                        throw new Error(
                            `Unbalanced quote for attribute value: '${e}'`,
                        );
                }
                if (((i = i.trim()), (n = n.trim()), !i)) {
                    if (!n) continue;
                    throw new Error(
                        `Attribute name before '=' should be specified: '${e}'`,
                    );
                }
                if (
                    (r.push({
                        name: i,
                        value: n,
                    }),
                    e[t] && " " !== e[t])
                )
                    throw new Error(
                        `No space before attribute: '${e.slice(t)}'`,
                    );
            }
            return r;
        }
        function getErrorMessage(e) {
            var r;
            if (
                "object" == typeof (r = e) &&
                null !== r &&
                "message" in r &&
                "string" == typeof r.message
            )
                return e.message;
            try {
                return new Error(JSON.stringify(e)).message;
            } catch (r) {
                return new Error(String(e)).message;
            }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            trustedCreateElement.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function trustedDispatchEvent(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function trustedDispatchEvent(source, event, target) {
            if (!event) {
                return;
            }
            var hasBeenDispatched = false;
            var eventTarget = document;
            if (target === "window") {
                eventTarget = window;
            }
            var events = new Set();
            var dispatch = function dispatch() {
                var customEvent = new Event(event);
                if (typeof target === "string" && target !== "window") {
                    eventTarget = document.querySelector(target);
                }
                var isEventAdded = events.has(event);
                if (!hasBeenDispatched && isEventAdded && eventTarget) {
                    hasBeenDispatched = true;
                    hit(source);
                    eventTarget.dispatchEvent(customEvent);
                }
            };
            var wrapper = function wrapper(eventListener, thisArg, args) {
                var eventName = args[0];
                if (thisArg && eventName) {
                    events.add(eventName);
                    setTimeout(function () {
                        dispatch();
                    }, 1);
                }
                return Reflect.apply(eventListener, thisArg, args);
            };
            var handler = {
                apply: wrapper,
            };
            EventTarget.prototype.addEventListener = new Proxy(
                EventTarget.prototype.addEventListener,
                handler,
            );
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            trustedDispatchEvent.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function trustedPruneInboundObject(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function trustedPruneInboundObject(
            source,
            functionName,
            propsToRemove,
            requiredInitialProps,
        ) {
            var stack =
                arguments.length > 4 && arguments[4] !== undefined
                    ? arguments[4]
                    : "";
            if (!functionName) {
                return;
            }
            var nativeObjects = {
                nativeStringify: window.JSON.stringify,
            };
            var { base: base, prop: prop } = getPropertyInChain(
                window,
                functionName,
            );
            if (!base || !prop || typeof base[prop] !== "function") {
                var message = `${functionName} is not a function`;
                logMessage(source, message);
                return;
            }
            var prunePaths = getPrunePath(propsToRemove);
            var requiredPaths = getPrunePath(requiredInitialProps);
            var objectWrapper = function objectWrapper(target, thisArg, args) {
                var data = args[0];
                if (typeof data === "object") {
                    data = jsonPruner(
                        source,
                        data,
                        prunePaths,
                        requiredPaths,
                        stack,
                        nativeObjects,
                    );
                    args[0] = data;
                }
                return Reflect.apply(target, thisArg, args);
            };
            var objectHandler = {
                apply: objectWrapper,
            };
            base[prop] = new Proxy(base[prop], objectHandler);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function matchStackTrace(e, t) {
            if (!e || "" === e) return true;
            var r = backupRegExpValues();
            if (shouldAbortInlineOrInjectedScript(e, t))
                return (
                    r.length && r[0] !== RegExp.$1 && restoreRegExpValues(r),
                    true
                );
            var n = toRegExp(e),
                a = t
                    .split("\n")
                    .slice(2)
                    .map(function (e) {
                        return e.trim();
                    })
                    .join("\n");
            return (
                r.length && r[0] !== RegExp.$1 && restoreRegExpValues(r),
                getNativeRegexpTest().call(n, a)
            );
        }
        function getPropertyInChain(e, r) {
            var n = r.indexOf(".");
            if (-1 === n)
                return {
                    base: e,
                    prop: r,
                };
            var i = r.slice(0, n);
            if (null === e)
                return {
                    base: e,
                    prop: i,
                    chain: r,
                };
            var t = e[i];
            return (
                (r = r.slice(n + 1)),
                ((e instanceof Object || "object" == typeof e) &&
                    isEmptyObject(e)) ||
                null === t
                    ? {
                          base: e,
                          prop: i,
                          chain: r,
                      }
                    : void 0 !== t
                      ? getPropertyInChain(t, r)
                      : (Object.defineProperty(e, i, {
                            configurable: true,
                        }),
                        {
                            base: e,
                            prop: i,
                            chain: r,
                        })
            );
        }
        function getWildcardPropertyInChain(r, e) {
            var a =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                i =
                    arguments.length > 3 && void 0 !== arguments[3]
                        ? arguments[3]
                        : [],
                t = arguments.length > 4 ? arguments[4] : void 0,
                o = e.indexOf(".");
            if (-1 === o) {
                if ("*" === e || "[]" === e) {
                    for (var n in r)
                        if (Object.prototype.hasOwnProperty.call(r, n))
                            if (void 0 !== t) {
                                var s = r[n];
                                "string" == typeof s && t instanceof RegExp
                                    ? t.test(s) &&
                                      i.push({
                                          base: r,
                                          prop: n,
                                      })
                                    : s === t &&
                                      i.push({
                                          base: r,
                                          prop: n,
                                      });
                            } else
                                i.push({
                                    base: r,
                                    prop: n,
                                });
                } else if (void 0 !== t) {
                    var p = r[e];
                    "string" == typeof p && t instanceof RegExp
                        ? t.test(p) &&
                          i.push({
                              base: r,
                              prop: e,
                          })
                        : r[e] === t &&
                          i.push({
                              base: r,
                              prop: e,
                          });
                } else
                    i.push({
                        base: r,
                        prop: e,
                    });
                return i;
            }
            var c = e.slice(0, o);
            if (
                ("[]" === c && Array.isArray(r)) ||
                ("*" === c && r instanceof Object) ||
                ("[-]" === c && Array.isArray(r)) ||
                ("{-}" === c && r instanceof Object)
            ) {
                var f = e.slice(o + 1),
                    y = Object.keys(r);
                if ("{-}" === c || "[-]" === c) {
                    var h = Array.isArray(r) ? "array" : "object";
                    return (
                        (("{-}" !== c || "object" !== h) &&
                            ("[-]" !== c || "array" !== h)) ||
                            y.forEach(function (e) {
                                var a = r[e];
                                isKeyInObject(a, f, t) &&
                                    i.push({
                                        base: r,
                                        prop: e,
                                    });
                            }),
                        i
                    );
                }
                y.forEach(function (e) {
                    getWildcardPropertyInChain(r[e], f, a, i, t);
                });
            }
            Array.isArray(r) &&
                r.forEach(function (r) {
                    void 0 !== r && getWildcardPropertyInChain(r, e, a, i, t);
                });
            var d = r[c];
            return (
                (e = e.slice(o + 1)),
                void 0 !== d && getWildcardPropertyInChain(d, e, a, i, t),
                i
            );
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function isPruningNeeded(n, t, r, e, a, i) {
            if (!t) return false;
            var o,
                { nativeStringify: u } = i,
                c = r.map(function (n) {
                    return n.path;
                }),
                f = e.map(function (n) {
                    return n.path;
                });
            if (0 === c.length && f.length > 0) {
                var g = u(t);
                if (toRegExp(f.join("")).test(g))
                    return (
                        logMessage(
                            n,
                            `${window.location.hostname}\n${u(t, null, 2)}\nStack trace:\n${new Error().stack}`,
                            true,
                        ),
                        t &&
                            "object" == typeof t &&
                            logMessage(n, t, true, false),
                        (o = false)
                    );
            }
            if (a && !matchStackTrace(a, new Error().stack || ""))
                return (o = false);
            for (
                var s,
                    l = [".*.", "*.", ".*", ".[].", "[].", ".[]"],
                    _loop = function _loop() {
                        var n = f[p],
                            r = n.split(".").pop(),
                            e = l.some(function (t) {
                                return n.includes(t);
                            }),
                            a = getWildcardPropertyInChain(t, n, e);
                        if (!a.length)
                            return {
                                v: (o = false),
                            };
                        o = !e;
                        for (var i = 0; i < a.length; i += 1) {
                            var u =
                                "string" == typeof r && void 0 !== a[i].base[r];
                            o = e ? u || o : u && o;
                        }
                    },
                    p = 0;
                p < f.length;
                p += 1
            )
                if ((s = _loop())) return s.v;
            return o;
        }
        function jsonPruner(e, r, n, a, t, i) {
            var { nativeStringify: o } = i;
            if (0 === n.length && 0 === a.length)
                return (
                    logMessage(
                        e,
                        `${window.location.hostname}\n${o(r, null, 2)}\nStack trace:\n${new Error().stack}`,
                        true,
                    ),
                    r && "object" == typeof r && logMessage(e, r, true, false),
                    r
                );
            try {
                if (!1 === isPruningNeeded(e, r, n, a, t, i)) return r;
                n.forEach(function (n) {
                    for (
                        var a = n.path,
                            t = n.value,
                            i = getWildcardPropertyInChain(r, a, !0, [], t),
                            o = i.length - 1;
                        o >= 0;
                        o -= 1
                    ) {
                        var s = i[o];
                        if (void 0 !== s && s.base)
                            if ((hit(e), Array.isArray(s.base)))
                                try {
                                    var l = Number(s.prop);
                                    if (Number.isNaN(l)) continue;
                                    s.base.splice(l, 1);
                                } catch (e) {
                                    console.error(
                                        "Error while deleting array element",
                                        e,
                                    );
                                }
                            else delete s.base[s.prop];
                    }
                });
            } catch (r) {
                logMessage(e, r);
            }
            return r;
        }
        function getPrunePath(t) {
            var r = ".[=].";
            if ("string" == typeof t && void 0 !== t && "" !== t) {
                var e = (function (t) {
                    for (
                        var e = [], n = "", i = 0, a = false, s = false;
                        i < t.length;

                    ) {
                        var u = t[i];
                        if (a)
                            ((n += u),
                                "\\" === u
                                    ? (s = !s)
                                    : ("/" !== u || s || (a = false),
                                      (s = false)),
                                (i += 1));
                        else {
                            if (
                                " " === u ||
                                "\n" === u ||
                                "\t" === u ||
                                "\r" === u ||
                                "\f" === u ||
                                "\v" === u
                            ) {
                                for (; i < t.length && /\s/.test(t[i]); )
                                    i += 1;
                                "" !== n && (e.push(n), (n = ""));
                                continue;
                            }
                            if (t.startsWith(r, i)) {
                                if (((n += r), "/" === t[(i += 5)])) {
                                    ((a = true),
                                        (s = false),
                                        (n += "/"),
                                        (i += 1));
                                    continue;
                                }
                                continue;
                            }
                            ((n += u), (i += 1));
                        }
                    }
                    return ("" !== n && e.push(n), e);
                })(t);
                return e.map(function (t) {
                    var e = t.split(r),
                        n = e[0],
                        i = e[1];
                    return void 0 !== i
                        ? ("true" === i
                              ? (i = true)
                              : "false" === i
                                ? (i = false)
                                : i.startsWith("/")
                                  ? (i = toRegExp(i))
                                  : "string" == typeof i &&
                                    /^\d+$/.test(i) &&
                                    (i = parseFloat(i)),
                          {
                              path: n,
                              value: i,
                          })
                        : {
                              path: n,
                          };
                });
            }
            return [];
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function getNativeRegexpTest() {
            var t = Object.getOwnPropertyDescriptor(RegExp.prototype, "test"),
                e = null == t ? void 0 : t.value;
            if (t && "function" == typeof t.value) return e;
            throw new Error("RegExp.prototype.test is not a function");
        }
        function shouldAbortInlineOrInjectedScript(t, i) {
            var r = "inlineScript",
                n = "injectedScript",
                isInlineScript = function isInlineScript(t) {
                    return t.includes(r);
                },
                isInjectedScript = function isInjectedScript(t) {
                    return t.includes(n);
                };
            if (!isInlineScript(t) && !isInjectedScript(t)) return false;
            var e = window.location.href,
                s = e.indexOf("#");
            -1 !== s && (e = e.slice(0, s));
            var c = i
                .split("\n")
                .slice(2)
                .map(function (t) {
                    return t.trim();
                })
                .map(function (t) {
                    var i,
                        s = /(.*?@)?(\S+)(:\d+)(:\d+)\)?$/.exec(t);
                    if (s) {
                        var c,
                            l,
                            a = s[2],
                            u = s[3],
                            o = s[4];
                        if (
                            (null !== (c = a) &&
                                void 0 !== c &&
                                c.startsWith("(") &&
                                (a = a.slice(1)),
                            null !== (l = a) &&
                                void 0 !== l &&
                                l.startsWith("<anonymous>"))
                        ) {
                            var d;
                            a = n;
                            var f =
                                void 0 !== s[1]
                                    ? s[1].slice(0, -1)
                                    : t.slice(0, s.index).trim();
                            (null !== (d = f) &&
                                void 0 !== d &&
                                d.startsWith("at") &&
                                (f = f.slice(2).trim()),
                                (i = `${f} ${a}${u}${o}`.trim()));
                        } else
                            i =
                                a === e
                                    ? `${r}${u}${o}`.trim()
                                    : `${a}${u}${o}`.trim();
                    } else i = t;
                    return i;
                });
            if (c)
                for (var l = 0; l < c.length; l += 1) {
                    if (
                        isInlineScript(t) &&
                        c[l].startsWith(r) &&
                        c[l].match(toRegExp(t))
                    )
                        return true;
                    if (
                        isInjectedScript(t) &&
                        c[l].startsWith(n) &&
                        c[l].match(toRegExp(t))
                    )
                        return true;
                }
            return false;
        }
        function isEmptyObject(t) {
            return 0 === Object.keys(t).length && !t.prototype;
        }
        function backupRegExpValues() {
            try {
                for (var r = [], e = 1; e < 10; e += 1) {
                    var a = `$${e}`;
                    if (!RegExp[a]) break;
                    r.push(RegExp[a]);
                }
                return r;
            } catch (r) {
                return [];
            }
        }
        function restoreRegExpValues(e) {
            if (e.length)
                try {
                    var r = "";
                    r =
                        1 === e.length
                            ? `(${e[0]})`
                            : e.reduce(function (e, r, t) {
                                  return 1 === t
                                      ? `(${e}),(${r})`
                                      : `${e},(${r})`;
                              });
                    var t = new RegExp(r);
                    e.toString().replace(t, "");
                } catch (e) {
                    var n = `Failed to restore RegExp values: ${e}`;
                    console.log(n);
                }
        }
        function isKeyInObject(t, r, e) {
            var n = r.split("."),
                _check6 = function _check(t, r) {
                    if (null == t) return false;
                    if (0 === r.length)
                        return (
                            void 0 === e ||
                            ("string" == typeof t && e instanceof RegExp
                                ? e.test(t)
                                : t === e)
                        );
                    var n = r[0],
                        i = r.slice(1);
                    if ("*" === n || "[]" === n) {
                        if (Array.isArray(t))
                            return t.some(function (t) {
                                return _check6(t, i);
                            });
                        if ("object" == typeof t && null !== t)
                            return Object.keys(t).some(function (r) {
                                return _check6(t[r], i);
                            });
                    }
                    return (
                        !!Object.prototype.hasOwnProperty.call(t, n) &&
                        _check6(t[n], i)
                    );
                };
            return _check6(t, n);
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            trustedPruneInboundObject.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function trustedReplaceArgument(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function trustedReplaceArgument(
            source,
            methodPath,
            argumentIndex,
            argumentValue,
            pattern,
        ) {
            var stack =
                arguments.length > 5 && arguments[5] !== undefined
                    ? arguments[5]
                    : "";
            var verbose =
                arguments.length > 6 && arguments[6] !== undefined
                    ? arguments[6]
                    : "false";
            if (
                ((!methodPath || !argumentIndex || !argumentValue) &&
                    verbose === "false") ||
                (!methodPath && verbose === "true")
            ) {
                return;
            }
            var SHOULD_LOG_ONLY =
                verbose === "true" &&
                !argumentIndex &&
                !argumentValue &&
                !pattern &&
                !stack;
            var MARKERS = {
                JSON: "json:",
                REPLACE: "replace:",
            };
            var constantValue;
            var replaceRegexValue = "";
            var shouldReplaceArgument = false;
            if (argumentValue.startsWith(MARKERS.REPLACE)) {
                var replacementRegexPair =
                    extractRegexAndReplacement(argumentValue);
                if (!replacementRegexPair) {
                    logMessage(
                        source,
                        `Invalid argument value format: ${argumentValue}`,
                    );
                    return;
                }
                replaceRegexValue = replacementRegexPair.regexPart;
                constantValue = replacementRegexPair.replacementPart;
                shouldReplaceArgument = true;
            } else if (argumentValue.startsWith(MARKERS.JSON)) {
                try {
                    constantValue = JSON.parse(
                        argumentValue.slice(MARKERS.JSON.length),
                    );
                } catch (error) {
                    logMessage(
                        source,
                        `Invalid JSON argument value: ${argumentValue}`,
                    );
                    return;
                }
            } else {
                var emptyArr = noopArray();
                var emptyObj = noopObject();
                if (argumentValue === "undefined") {
                    constantValue = undefined;
                } else if (argumentValue === "false") {
                    constantValue = false;
                } else if (argumentValue === "true") {
                    constantValue = true;
                } else if (argumentValue === "null") {
                    constantValue = null;
                } else if (argumentValue === "emptyArr") {
                    constantValue = emptyArr;
                } else if (argumentValue === "emptyObj") {
                    constantValue = emptyObj;
                } else if (argumentValue === "noopFunc") {
                    constantValue = noopFunc;
                } else if (argumentValue === "noopCallbackFunc") {
                    constantValue = noopCallbackFunc;
                } else if (argumentValue === "trueFunc") {
                    constantValue = trueFunc;
                } else if (argumentValue === "falseFunc") {
                    constantValue = falseFunc;
                } else if (argumentValue === "throwFunc") {
                    constantValue = throwFunc;
                } else if (argumentValue === "noopPromiseResolve") {
                    constantValue = noopPromiseResolve;
                } else if (argumentValue === "noopPromiseReject") {
                    constantValue = noopPromiseReject;
                } else if (/^-?\d+$/.test(argumentValue)) {
                    constantValue = parseFloat(argumentValue);
                    if (nativeIsNaN(constantValue)) {
                        return;
                    }
                } else {
                    constantValue = argumentValue;
                }
            }
            var getPathParts = getPropertyInChain;
            var {
                base: base,
                chain: chain,
                prop: prop,
            } = getPathParts(window, methodPath);
            if (typeof chain !== "undefined") {
                logMessage(
                    source,
                    `Could not reach the end of the prop chain: ${methodPath}`,
                );
                return;
            }
            var nativeMethod = base[prop];
            if (!nativeMethod || typeof nativeMethod !== "function") {
                logMessage(
                    source,
                    `Could not retrieve the method: ${methodPath}`,
                );
                return;
            }
            var stringifyObject = function stringifyObject(obj) {
                return JSON.stringify(obj, function (key, value) {
                    return typeof value === "function"
                        ? value.toString()
                        : value;
                });
            };
            var createFormattedMessage = function createFormattedMessage(args) {
                var when =
                    arguments.length > 1 && arguments[1] !== undefined
                        ? arguments[1]
                        : "original";
                var formattedArgs = args.map(function (arg, index) {
                    if (typeof arg === "object" && arg !== null) {
                        try {
                            return `${index}: ${stringifyObject(arg)} // Object converted to string`;
                        } catch (e) {
                            return `${index}: ${String(arg)} // Object conversion failed`;
                        }
                    }
                    return `${index}: ${String(arg)}`;
                });
                var modifiedOrOriginal =
                    when === "modified" ? "modified" : when;
                var message = `${methodPath} ${modifiedOrOriginal} arguments:\n${formattedArgs.join(",\n")}`;
                return message;
            };
            var checkArgument = function checkArgument(arg) {
                if (stack && !matchStackTrace(stack, new Error().stack || "")) {
                    return false;
                }
                if (pattern) {
                    if (typeof arg === "object" && arg !== null) {
                        try {
                            var argString = stringifyObject(arg);
                            return (
                                !!argString && toRegExp(pattern).test(argString)
                            );
                        } catch (error) {
                            logMessage(
                                source,
                                `Failed to stringify argument: ${arg}\nError: ${error}`,
                            );
                        }
                    }
                    var argumentContent = String(arg);
                    return (
                        !!argumentContent &&
                        toRegExp(pattern).test(argumentContent)
                    );
                }
                return true;
            };
            var isMatchingSuspended = false;
            var applyWrapper = function applyWrapper(
                target,
                thisArg,
                argumentsList,
            ) {
                if (isMatchingSuspended) {
                    isMatchingSuspended = false;
                    return Reflect.apply(target, thisArg, argumentsList);
                }
                isMatchingSuspended = true;
                if (verbose === "true") {
                    var formattedMessage =
                        createFormattedMessage(argumentsList);
                    logMessage(source, formattedMessage);
                }
                if (SHOULD_LOG_ONLY) {
                    isMatchingSuspended = false;
                    return Reflect.apply(target, thisArg, argumentsList);
                }
                var argumentToReplace = argumentsList[Number(argumentIndex)];
                var shouldSetArgument = checkArgument(argumentToReplace);
                if (!shouldSetArgument) {
                    isMatchingSuspended = false;
                    return Reflect.apply(target, thisArg, argumentsList);
                }
                if (
                    typeof argumentToReplace === "string" &&
                    shouldReplaceArgument
                ) {
                    argumentsList[Number(argumentIndex)] =
                        argumentToReplace.replace(
                            replaceRegexValue,
                            constantValue,
                        );
                } else {
                    argumentsList[Number(argumentIndex)] = constantValue;
                }
                if (verbose === "true") {
                    var _formattedMessage = createFormattedMessage(
                        argumentsList,
                        "modified",
                    );
                    logMessage(source, _formattedMessage);
                }
                hit(source);
                isMatchingSuspended = false;
                return Reflect.apply(target, thisArg, argumentsList);
            };
            var constructWrapper = function constructWrapper(
                target,
                argumentsList,
                newTarget,
            ) {
                if (isMatchingSuspended) {
                    isMatchingSuspended = false;
                    return Reflect.construct(target, argumentsList, newTarget);
                }
                isMatchingSuspended = true;
                if (verbose === "true") {
                    var formattedMessage =
                        createFormattedMessage(argumentsList);
                    logMessage(source, formattedMessage);
                }
                if (SHOULD_LOG_ONLY) {
                    isMatchingSuspended = false;
                    return Reflect.construct(target, argumentsList, newTarget);
                }
                var argumentToReplace = argumentsList[Number(argumentIndex)];
                var shouldSetArgument = checkArgument(argumentToReplace);
                if (!shouldSetArgument) {
                    isMatchingSuspended = false;
                    return Reflect.construct(target, argumentsList, newTarget);
                }
                if (
                    typeof argumentToReplace === "string" &&
                    shouldReplaceArgument
                ) {
                    argumentsList[Number(argumentIndex)] =
                        argumentToReplace.replace(
                            replaceRegexValue,
                            constantValue,
                        );
                } else {
                    argumentsList[Number(argumentIndex)] = constantValue;
                }
                if (verbose === "true") {
                    var _formattedMessage2 = createFormattedMessage(
                        argumentsList,
                        "modified",
                    );
                    logMessage(source, _formattedMessage2);
                }
                hit(source);
                isMatchingSuspended = false;
                return Reflect.construct(target, argumentsList, newTarget);
            };
            var getWrapper = function getWrapper(target, propName, receiver) {
                if (propName === "toString") {
                    return target.toString.bind(target);
                }
                return Reflect.get(target, propName, receiver);
            };
            var objectHandler = {
                apply: applyWrapper,
                construct: constructWrapper,
                get: getWrapper,
            };
            base[prop] = new Proxy(nativeMethod, objectHandler);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function noopArray() {
            return [];
        }
        function noopObject() {
            return {};
        }
        function noopCallbackFunc() {
            return noopFunc;
        }
        function noopFunc() {}
        function trueFunc() {
            return true;
        }
        function falseFunc() {
            return false;
        }
        function throwFunc() {
            throw new Error();
        }
        function noopPromiseReject() {
            return Promise.reject();
        }
        function noopPromiseResolve() {
            var e =
                    arguments.length > 0 && void 0 !== arguments[0]
                        ? arguments[0]
                        : "{}",
                t =
                    arguments.length > 1 && void 0 !== arguments[1]
                        ? arguments[1]
                        : "",
                s =
                    arguments.length > 2 && void 0 !== arguments[2]
                        ? arguments[2]
                        : "basic";
            if ("undefined" != typeof Response) {
                var n = new Response(e, {
                    headers: {
                        "Content-Length": `${e.length}`,
                    },
                    status: 200,
                    statusText: "OK",
                });
                return (
                    "opaque" === s
                        ? Object.defineProperties(n, {
                              body: {
                                  value: null,
                              },
                              status: {
                                  value: 0,
                              },
                              ok: {
                                  value: false,
                              },
                              statusText: {
                                  value: "",
                              },
                              url: {
                                  value: "",
                              },
                              type: {
                                  value: s,
                              },
                          })
                        : Object.defineProperties(n, {
                              url: {
                                  value: t,
                              },
                              type: {
                                  value: s,
                              },
                          }),
                    Promise.resolve(n)
                );
            }
        }
        function matchStackTrace(e, t) {
            if (!e || "" === e) return true;
            var r = backupRegExpValues();
            if (shouldAbortInlineOrInjectedScript(e, t))
                return (
                    r.length && r[0] !== RegExp.$1 && restoreRegExpValues(r),
                    true
                );
            var n = toRegExp(e),
                a = t
                    .split("\n")
                    .slice(2)
                    .map(function (e) {
                        return e.trim();
                    })
                    .join("\n");
            return (
                r.length && r[0] !== RegExp.$1 && restoreRegExpValues(r),
                getNativeRegexpTest().call(n, a)
            );
        }
        function getPropertyInChain(e, r) {
            var n = r.indexOf(".");
            if (-1 === n)
                return {
                    base: e,
                    prop: r,
                };
            var i = r.slice(0, n);
            if (null === e)
                return {
                    base: e,
                    prop: i,
                    chain: r,
                };
            var t = e[i];
            return (
                (r = r.slice(n + 1)),
                ((e instanceof Object || "object" == typeof e) &&
                    isEmptyObject(e)) ||
                null === t
                    ? {
                          base: e,
                          prop: i,
                          chain: r,
                      }
                    : void 0 !== t
                      ? getPropertyInChain(t, r)
                      : (Object.defineProperty(e, i, {
                            configurable: true,
                        }),
                        {
                            base: e,
                            prop: i,
                            chain: r,
                        })
            );
        }
        function extractRegexAndReplacement(e) {
            if (e) {
                var r = e.slice(8),
                    t = "";
                if (
                    (r.endsWith("/g") && ((r = r.slice(0, -1)), (t = "g")),
                    r.startsWith("/") && r.endsWith("/"))
                ) {
                    for (
                        var i = r.slice(1, -1), a = -1, c = 0;
                        c < i.length;
                        c += 1
                    )
                        if ("/" === i[c]) {
                            for (
                                var f = false, n = c - 1;
                                n >= 0 && "\\" === i[n];

                            )
                                ((f = !f), (n -= 1));
                            if (!f) {
                                a = c;
                                break;
                            }
                        }
                    if (-1 !== a) {
                        var s = `/${i.slice(0, a)}/${t}`,
                            l = i.slice(a + 1);
                        if (s && "//" !== s) {
                            var g;
                            try {
                                g = toRegExp(s);
                            } catch (e) {
                                return;
                            }
                            if (g)
                                return {
                                    regexPart: g,
                                    replacementPart: l,
                                };
                        }
                    }
                }
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function getNativeRegexpTest() {
            var t = Object.getOwnPropertyDescriptor(RegExp.prototype, "test"),
                e = null == t ? void 0 : t.value;
            if (t && "function" == typeof t.value) return e;
            throw new Error("RegExp.prototype.test is not a function");
        }
        function shouldAbortInlineOrInjectedScript(t, i) {
            var r = "inlineScript",
                n = "injectedScript",
                isInlineScript = function isInlineScript(t) {
                    return t.includes(r);
                },
                isInjectedScript = function isInjectedScript(t) {
                    return t.includes(n);
                };
            if (!isInlineScript(t) && !isInjectedScript(t)) return false;
            var e = window.location.href,
                s = e.indexOf("#");
            -1 !== s && (e = e.slice(0, s));
            var c = i
                .split("\n")
                .slice(2)
                .map(function (t) {
                    return t.trim();
                })
                .map(function (t) {
                    var i,
                        s = /(.*?@)?(\S+)(:\d+)(:\d+)\)?$/.exec(t);
                    if (s) {
                        var c,
                            l,
                            a = s[2],
                            u = s[3],
                            o = s[4];
                        if (
                            (null !== (c = a) &&
                                void 0 !== c &&
                                c.startsWith("(") &&
                                (a = a.slice(1)),
                            null !== (l = a) &&
                                void 0 !== l &&
                                l.startsWith("<anonymous>"))
                        ) {
                            var d;
                            a = n;
                            var f =
                                void 0 !== s[1]
                                    ? s[1].slice(0, -1)
                                    : t.slice(0, s.index).trim();
                            (null !== (d = f) &&
                                void 0 !== d &&
                                d.startsWith("at") &&
                                (f = f.slice(2).trim()),
                                (i = `${f} ${a}${u}${o}`.trim()));
                        } else
                            i =
                                a === e
                                    ? `${r}${u}${o}`.trim()
                                    : `${a}${u}${o}`.trim();
                    } else i = t;
                    return i;
                });
            if (c)
                for (var l = 0; l < c.length; l += 1) {
                    if (
                        isInlineScript(t) &&
                        c[l].startsWith(r) &&
                        c[l].match(toRegExp(t))
                    )
                        return true;
                    if (
                        isInjectedScript(t) &&
                        c[l].startsWith(n) &&
                        c[l].match(toRegExp(t))
                    )
                        return true;
                }
            return false;
        }
        function nativeIsNaN(N) {
            return (Number.isNaN || window.isNaN)(N);
        }
        function isEmptyObject(t) {
            return 0 === Object.keys(t).length && !t.prototype;
        }
        function backupRegExpValues() {
            try {
                for (var r = [], e = 1; e < 10; e += 1) {
                    var a = `$${e}`;
                    if (!RegExp[a]) break;
                    r.push(RegExp[a]);
                }
                return r;
            } catch (r) {
                return [];
            }
        }
        function restoreRegExpValues(e) {
            if (e.length)
                try {
                    var r = "";
                    r =
                        1 === e.length
                            ? `(${e[0]})`
                            : e.reduce(function (e, r, t) {
                                  return 1 === t
                                      ? `(${e}),(${r})`
                                      : `${e},(${r})`;
                              });
                    var t = new RegExp(r);
                    e.toString().replace(t, "");
                } catch (e) {
                    var n = `Failed to restore RegExp values: ${e}`;
                    console.log(n);
                }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            trustedReplaceArgument.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function trustedReplaceFetchResponse(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function trustedReplaceFetchResponse(source) {
            var pattern =
                arguments.length > 1 && arguments[1] !== undefined
                    ? arguments[1]
                    : "";
            var replacement =
                arguments.length > 2 && arguments[2] !== undefined
                    ? arguments[2]
                    : "";
            var propsToMatch =
                arguments.length > 3 && arguments[3] !== undefined
                    ? arguments[3]
                    : "";
            var verbose =
                arguments.length > 4 && arguments[4] !== undefined
                    ? arguments[4]
                    : false;
            if (
                typeof fetch === "undefined" ||
                typeof Proxy === "undefined" ||
                typeof Response === "undefined"
            ) {
                return;
            }
            if (pattern === "" && replacement !== "") {
                logMessage(
                    source,
                    "Pattern argument should not be empty string",
                );
                return;
            }
            var shouldLog = pattern === "" && replacement === "";
            var shouldLogContent = verbose === "true";
            var nativeRequestClone = Request.prototype.clone;
            var nativeFetch = fetch;
            var shouldReplace = false;
            var fetchData;
            var handlerWrapper = function handlerWrapper(
                target,
                thisArg,
                args,
            ) {
                fetchData = getFetchData(args, nativeRequestClone);
                if (shouldLog) {
                    logMessage(
                        source,
                        `fetch( ${objectToString(fetchData)} )`,
                        true,
                    );
                    hit(source);
                    return Reflect.apply(target, thisArg, args);
                }
                shouldReplace = matchRequestProps(
                    source,
                    propsToMatch,
                    fetchData,
                );
                if (!shouldReplace) {
                    return Reflect.apply(target, thisArg, args);
                }
                return nativeFetch
                    .apply(null, args)
                    .then(function (response) {
                        return response
                            .text()
                            .then(function (bodyText) {
                                var patternRegexp =
                                    pattern === "*"
                                        ? /(\n|.)*/
                                        : toRegExp(pattern);
                                if (shouldLogContent) {
                                    logMessage(
                                        source,
                                        `Original text content: ${bodyText}`,
                                    );
                                }
                                var modifiedTextContent = bodyText.replace(
                                    patternRegexp,
                                    replacement,
                                );
                                if (shouldLogContent) {
                                    logMessage(
                                        source,
                                        `Modified text content: ${modifiedTextContent}`,
                                    );
                                }
                                var forgedResponse = forgeResponse(
                                    response,
                                    modifiedTextContent,
                                );
                                hit(source);
                                return forgedResponse;
                            })
                            .catch(function () {
                                var fetchDataStr = objectToString(fetchData);
                                var message = `Response body can't be converted to text: ${fetchDataStr}`;
                                logMessage(source, message);
                                return Reflect.apply(target, thisArg, args);
                            });
                    })
                    .catch(function () {
                        return Reflect.apply(target, thisArg, args);
                    });
            };
            var fetchHandler = {
                apply: handlerWrapper,
            };
            fetch = new Proxy(fetch, fetchHandler);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function getFetchData(e, t) {
            var a,
                c,
                n = {},
                r = e[0];
            if (r instanceof Request) {
                var u = t.call(r),
                    f = getRequestData(u);
                ((a = f.url), (c = f));
            } else ((a = r), (c = e[1]));
            ((n.url = a), c instanceof Object) &&
                Object.keys(c).forEach(function (e) {
                    n[e] = c[e];
                });
            return n;
        }
        function objectToString(t) {
            return t && "object" == typeof t
                ? isEmptyObject(t)
                    ? "{}"
                    : Object.entries(t)
                          .map(function (t) {
                              var n = t[0],
                                  e = t[1],
                                  o = e;
                              return (
                                  e instanceof Object &&
                                      (o = `{ ${objectToString(e)} }`),
                                  `${n}:"${o}"`
                              );
                          })
                          .join(" ")
                : String(t);
        }
        function matchRequestProps(e, t, r) {
            if ("" === t || "*" === t) return true;
            var a,
                s = parseMatchProps(t);
            if (isValidParsedData(s)) {
                var n = getMatchPropsData(s);
                a = Object.keys(n).every(function (e) {
                    var t = n[e],
                        a = r[e];
                    return (
                        Object.prototype.hasOwnProperty.call(r, e) &&
                        "string" == typeof a &&
                        (null == t ? void 0 : t.test(a))
                    );
                });
            } else (logMessage(e, `Invalid parameter: ${t}`), (a = false));
            return a;
        }
        function forgeResponse(e, t) {
            var {
                    bodyUsed: s,
                    headers: r,
                    ok: u,
                    redirected: a,
                    status: d,
                    statusText: o,
                    type: l,
                    url: n,
                } = e,
                v = new Response(t, {
                    status: d,
                    statusText: o,
                    headers: r,
                });
            return (
                Object.defineProperties(v, {
                    url: {
                        value: n,
                    },
                    type: {
                        value: l,
                    },
                    ok: {
                        value: u,
                    },
                    bodyUsed: {
                        value: s,
                    },
                    redirected: {
                        value: a,
                    },
                }),
                v
            );
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function isValidStrPattern(e) {
            var t,
                n = escapeRegExp(e);
            "/" === e[0] && "/" === e[e.length - 1] && (n = e.slice(1, -1));
            try {
                ((t = new RegExp(n)), (t = !0));
            } catch (e) {
                t = false;
            }
            return t;
        }
        function escapeRegExp(e) {
            return e.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        }
        function isEmptyObject(t) {
            return 0 === Object.keys(t).length && !t.prototype;
        }
        function getRequestData(t) {
            var e = getRequestProps().map(function (e) {
                return [e, t[e]];
            });
            return Object.fromEntries(e);
        }
        function getRequestProps() {
            return [
                "url",
                "method",
                "headers",
                "body",
                "credentials",
                "cache",
                "redirect",
                "referrer",
                "referrerPolicy",
                "integrity",
                "keepalive",
                "signal",
                "mode",
            ];
        }
        function parseMatchProps(e) {
            var r = {};
            return (
                e.split(" ").forEach(function (e) {
                    var n = e.indexOf(":"),
                        i = e.slice(0, n);
                    if (
                        (function (e) {
                            return getRequestProps().includes(e);
                        })(i)
                    ) {
                        var s = e.slice(n + 1);
                        r[i] = s;
                    } else r.url = e;
                }),
                r
            );
        }
        function isValidParsedData(t) {
            return Object.values(t).every(function (t) {
                return isValidStrPattern(t);
            });
        }
        function getMatchPropsData(t) {
            var a = {};
            return (
                Object.keys(t).forEach(function (c) {
                    a[c] = toRegExp(t[c]);
                }),
                a
            );
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            trustedReplaceFetchResponse.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function trustedReplaceNodeText(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function trustedReplaceNodeText(
            source,
            nodeName,
            textMatch,
            pattern,
            replacement,
        ) {
            var fixQuotes = function fixQuotes(str) {
                if (typeof str !== "string") {
                    return str;
                }
                return str.replace(/\\'/g, "'").replace(/\\"/g, '"');
            };
            var fixedPattern = fixQuotes(pattern);
            var fixedReplacement = fixQuotes(replacement);
            var {
                selector: selector,
                nodeNameMatch: nodeNameMatch,
                textContentMatch: textContentMatch,
                patternMatch: patternMatch,
            } = parseNodeTextParams(nodeName, textMatch, fixedPattern);
            for (
                var _len = arguments.length,
                    extraArgs = new Array(_len > 5 ? _len - 5 : 0),
                    _key = 5;
                _key < _len;
                _key++
            ) {
                extraArgs[_key - 5] = arguments[_key];
            }
            var shouldLog = extraArgs.includes("verbose");
            var handleNodes = function handleNodes(nodes) {
                return nodes.forEach(function (node) {
                    var shouldReplace = isTargetNode(
                        node,
                        nodeNameMatch,
                        textContentMatch,
                    );
                    if (shouldReplace) {
                        if (shouldLog) {
                            var originalText = node.textContent;
                            if (originalText) {
                                logMessage(
                                    source,
                                    `Original text content: ${originalText}`,
                                );
                            }
                        }
                        replaceNodeText(
                            source,
                            node,
                            patternMatch,
                            fixedReplacement,
                        );
                        if (shouldLog) {
                            var modifiedText = node.textContent;
                            if (modifiedText) {
                                logMessage(
                                    source,
                                    `Modified text content: ${modifiedText}`,
                                );
                            }
                        }
                    }
                });
            };
            if (document.documentElement) {
                handleExistingNodes(selector, handleNodes);
            }
            observeDocumentWithTimeout(function (mutations) {
                return handleMutations(mutations, handleNodes);
            });
        }
        function observeDocumentWithTimeout(e) {
            var t =
                    arguments.length > 1 && void 0 !== arguments[1]
                        ? arguments[1]
                        : {
                              subtree: true,
                              childList: true,
                          },
                n =
                    arguments.length > 2 && void 0 !== arguments[2]
                        ? arguments[2]
                        : 1e4,
                o = new MutationObserver(function (n, o) {
                    (o.disconnect(),
                        e(n, o),
                        o.observe(document.documentElement, t));
                });
            (o.observe(document.documentElement, t),
                "number" == typeof n &&
                    setTimeout(function () {
                        return o.disconnect();
                    }, n));
        }
        function handleExistingNodes(e, n, o) {
            [document].forEach(function (o) {
                return (function (o) {
                    if ("#text" === e) {
                        var r = nodeListToArray(o.childNodes).filter(
                            function (e) {
                                return e.nodeType === Node.TEXT_NODE;
                            },
                        );
                        n(r);
                    } else {
                        var t = nodeListToArray(o.querySelectorAll(e));
                        n(t);
                    }
                })(o);
            });
        }
        function handleMutations(n, d, e, o) {
            var t = getAddedNodes(n);
            d(t);
        }
        function replaceNodeText(e, t, n, r) {
            var { textContent: a } = t;
            if (a) {
                var i = a.replace(n, r);
                if ("SCRIPT" === t.nodeName)
                    i = getTrustedTypesApi(e).createScript(i);
                ((t.textContent = i), hit(e));
            }
        }
        function isTargetNode(e, t, n) {
            var { nodeName: o, textContent: s } = e,
                a = o.toLowerCase();
            return (
                null !== s &&
                "" !== s &&
                (t instanceof RegExp ? t.test(a) : t === a) &&
                (n instanceof RegExp ? n.test(s) : s.includes(n))
            );
        }
        function parseNodeTextParams(t, e) {
            var a,
                n =
                    arguments.length > 2 && void 0 !== arguments[2]
                        ? arguments[2]
                        : null,
                r = "/",
                s = !(t.startsWith(r) && t.endsWith(r)),
                o = s ? t : "*",
                h = s ? t : toRegExp(t),
                i = e.startsWith(r) ? toRegExp(e) : e;
            return (
                n && (a = n.startsWith(r) ? toRegExp(n) : n),
                {
                    selector: o,
                    nodeNameMatch: h,
                    textContentMatch: i,
                    patternMatch: a,
                }
            );
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function nodeListToArray(r) {
            for (var n = [], o = 0; o < r.length; o += 1) n.push(r[o]);
            return n;
        }
        function getAddedNodes(d) {
            for (var e = [], r = 0; r < d.length; r += 1)
                for (var { addedNodes: n } = d[r], o = 0; o < n.length; o += 1)
                    e.push(n[o]);
            return e;
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function getTrustedTypesApi(t) {
            var r,
                e =
                    null == t || null === (r = t.api) || void 0 === r
                        ? void 0
                        : r.policy;
            if (e) return e;
            var n = "AGPolicy",
                i = window.trustedTypes,
                u = !!i,
                c = {
                    HTML: "TrustedHTML",
                    Script: "TrustedScript",
                    ScriptURL: "TrustedScriptURL",
                };
            if (!u)
                return {
                    name: n,
                    isSupported: u,
                    TrustedType: c,
                    createHTML: function createHTML(t) {
                        return t;
                    },
                    createScript: function createScript(t) {
                        return t;
                    },
                    createScriptURL: function createScriptURL(t) {
                        return t;
                    },
                    create: function create(t, r) {
                        return r;
                    },
                    getAttributeType: function getAttributeType() {
                        return null;
                    },
                    convertAttributeToTrusted:
                        function convertAttributeToTrusted(t, r, e) {
                            return e;
                        },
                    getPropertyType: function getPropertyType() {
                        return null;
                    },
                    convertPropertyToTrusted: function convertPropertyToTrusted(
                        t,
                        r,
                        e,
                    ) {
                        return e;
                    },
                    isHTML: function isHTML() {
                        return false;
                    },
                    isScript: function isScript() {
                        return false;
                    },
                    isScriptURL: function isScriptURL() {
                        return false;
                    },
                };
            var o = i.createPolicy(n, {
                    createHTML: function createHTML(t) {
                        return t;
                    },
                    createScript: function createScript(t) {
                        return t;
                    },
                    createScriptURL: function createScriptURL(t) {
                        return t;
                    },
                }),
                createHTML = function createHTML(t) {
                    return o.createHTML(t);
                },
                createScript = function createScript(t) {
                    return o.createScript(t);
                },
                createScriptURL = function createScriptURL(t) {
                    return o.createScriptURL(t);
                },
                create = function create(t, r) {
                    switch (t) {
                        case c.HTML:
                            return createHTML(r);
                        case c.Script:
                            return createScript(r);
                        case c.ScriptURL:
                            return createScriptURL(r);
                        default:
                            return r;
                    }
                },
                p = i.getAttributeType.bind(i),
                T = i.getPropertyType.bind(i),
                s = i.isHTML.bind(i),
                a = i.isScript.bind(i),
                f = i.isScriptURL.bind(i);
            return {
                name: n,
                isSupported: u,
                TrustedType: c,
                createHTML: createHTML,
                createScript: createScript,
                createScriptURL: createScriptURL,
                create: create,
                getAttributeType: p,
                convertAttributeToTrusted: function convertAttributeToTrusted(
                    t,
                    r,
                    e,
                    n,
                    i,
                ) {
                    var u = p(t, r, n, i);
                    return u ? create(u, e) : e;
                },
                getPropertyType: T,
                convertPropertyToTrusted: function convertPropertyToTrusted(
                    t,
                    r,
                    e,
                    n,
                ) {
                    var i = T(t, r, n);
                    return i ? create(i, e) : e;
                },
                isHTML: s,
                isScript: a,
                isScriptURL: f,
            };
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            trustedReplaceNodeText.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function trustedReplaceOutboundText(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function trustedReplaceOutboundText(source, methodPath) {
            var textToReplace =
                arguments.length > 2 && arguments[2] !== undefined
                    ? arguments[2]
                    : "";
            var replacement =
                arguments.length > 3 && arguments[3] !== undefined
                    ? arguments[3]
                    : "";
            var decodeMethod =
                arguments.length > 4 && arguments[4] !== undefined
                    ? arguments[4]
                    : "";
            var stack =
                arguments.length > 5 && arguments[5] !== undefined
                    ? arguments[5]
                    : "";
            var logContent =
                arguments.length > 6 && arguments[6] !== undefined
                    ? arguments[6]
                    : "";
            if (!methodPath) {
                return;
            }
            var getPathParts = getPropertyInChain;
            var {
                base: base,
                chain: chain,
                prop: prop,
            } = getPathParts(window, methodPath);
            if (typeof chain !== "undefined") {
                logMessage(
                    source,
                    `Could not reach the end of the prop chain: ${methodPath}`,
                );
                return;
            }
            var nativeMethod = base[prop];
            if (!nativeMethod || typeof nativeMethod !== "function") {
                logMessage(
                    source,
                    `Could not retrieve the method: ${methodPath}`,
                );
                return;
            }
            var isValidBase64 = function isValidBase64(str) {
                try {
                    if (str === "") {
                        return false;
                    }
                    var decodedString = atob(str);
                    var encodedString = btoa(decodedString);
                    var stringWithoutPadding = str.replace(/=+$/, "");
                    var encodedStringWithoutPadding = encodedString.replace(
                        /=+$/,
                        "",
                    );
                    return encodedStringWithoutPadding === stringWithoutPadding;
                } catch (e) {
                    return false;
                }
            };
            var decodeAndReplaceContent = function decodeAndReplaceContent(
                content,
                pattern,
                textReplacement,
                decode,
                log,
            ) {
                switch (decode) {
                    case "base64":
                        try {
                            if (!isValidBase64(content)) {
                                logMessage(
                                    source,
                                    `Text content is not a valid base64 encoded string: ${content}`,
                                );
                                return content;
                            }
                            var decodedContent = atob(content);
                            if (log) {
                                logMessage(
                                    source,
                                    `Decoded text content: ${decodedContent}`,
                                );
                            }
                            var modifiedContent = textToReplace
                                ? decodedContent.replace(
                                      pattern,
                                      textReplacement,
                                  )
                                : decodedContent;
                            if (log) {
                                var message =
                                    modifiedContent !== decodedContent
                                        ? `Modified decoded text content: ${modifiedContent}`
                                        : "Decoded text content was not modified";
                                logMessage(source, message);
                            }
                            var encodedContent = btoa(modifiedContent);
                            return encodedContent;
                        } catch (e) {
                            return content;
                        }
                    default:
                        return content.replace(pattern, textReplacement);
                }
            };
            var logOriginalContent = !textToReplace || !!logContent;
            var logModifiedContent = !!logContent;
            var logDecodedContent = !!decodeMethod && !!logContent;
            var isMatchingSuspended = false;
            var objectWrapper = function objectWrapper(
                target,
                thisArg,
                argumentsList,
            ) {
                if (isMatchingSuspended) {
                    return Reflect.apply(target, thisArg, argumentsList);
                }
                isMatchingSuspended = true;
                hit(source);
                var result = Reflect.apply(target, thisArg, argumentsList);
                if (stack && !matchStackTrace(stack, new Error().stack || "")) {
                    return result;
                }
                if (typeof result === "string") {
                    if (logOriginalContent) {
                        logMessage(source, `Original text content: ${result}`);
                    }
                    var patternRegexp = toRegExp(textToReplace);
                    var modifiedContent =
                        textToReplace || logDecodedContent
                            ? decodeAndReplaceContent(
                                  result,
                                  patternRegexp,
                                  replacement,
                                  decodeMethod,
                                  logContent,
                              )
                            : result;
                    if (logModifiedContent) {
                        var message =
                            modifiedContent !== result
                                ? `Modified text content: ${modifiedContent}`
                                : "Text content was not modified";
                        logMessage(source, message);
                    }
                    isMatchingSuspended = false;
                    return modifiedContent;
                }
                isMatchingSuspended = false;
                logMessage(source, "Content is not a string");
                return result;
            };
            var objectHandler = {
                apply: objectWrapper,
            };
            base[prop] = new Proxy(nativeMethod, objectHandler);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function matchStackTrace(e, t) {
            if (!e || "" === e) return true;
            var r = backupRegExpValues();
            if (shouldAbortInlineOrInjectedScript(e, t))
                return (
                    r.length && r[0] !== RegExp.$1 && restoreRegExpValues(r),
                    true
                );
            var n = toRegExp(e),
                a = t
                    .split("\n")
                    .slice(2)
                    .map(function (e) {
                        return e.trim();
                    })
                    .join("\n");
            return (
                r.length && r[0] !== RegExp.$1 && restoreRegExpValues(r),
                getNativeRegexpTest().call(n, a)
            );
        }
        function getPropertyInChain(e, r) {
            var n = r.indexOf(".");
            if (-1 === n)
                return {
                    base: e,
                    prop: r,
                };
            var i = r.slice(0, n);
            if (null === e)
                return {
                    base: e,
                    prop: i,
                    chain: r,
                };
            var t = e[i];
            return (
                (r = r.slice(n + 1)),
                ((e instanceof Object || "object" == typeof e) &&
                    isEmptyObject(e)) ||
                null === t
                    ? {
                          base: e,
                          prop: i,
                          chain: r,
                      }
                    : void 0 !== t
                      ? getPropertyInChain(t, r)
                      : (Object.defineProperty(e, i, {
                            configurable: true,
                        }),
                        {
                            base: e,
                            prop: i,
                            chain: r,
                        })
            );
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function shouldAbortInlineOrInjectedScript(t, i) {
            var r = "inlineScript",
                n = "injectedScript",
                isInlineScript = function isInlineScript(t) {
                    return t.includes(r);
                },
                isInjectedScript = function isInjectedScript(t) {
                    return t.includes(n);
                };
            if (!isInlineScript(t) && !isInjectedScript(t)) return false;
            var e = window.location.href,
                s = e.indexOf("#");
            -1 !== s && (e = e.slice(0, s));
            var c = i
                .split("\n")
                .slice(2)
                .map(function (t) {
                    return t.trim();
                })
                .map(function (t) {
                    var i,
                        s = /(.*?@)?(\S+)(:\d+)(:\d+)\)?$/.exec(t);
                    if (s) {
                        var c,
                            l,
                            a = s[2],
                            u = s[3],
                            o = s[4];
                        if (
                            (null !== (c = a) &&
                                void 0 !== c &&
                                c.startsWith("(") &&
                                (a = a.slice(1)),
                            null !== (l = a) &&
                                void 0 !== l &&
                                l.startsWith("<anonymous>"))
                        ) {
                            var d;
                            a = n;
                            var f =
                                void 0 !== s[1]
                                    ? s[1].slice(0, -1)
                                    : t.slice(0, s.index).trim();
                            (null !== (d = f) &&
                                void 0 !== d &&
                                d.startsWith("at") &&
                                (f = f.slice(2).trim()),
                                (i = `${f} ${a}${u}${o}`.trim()));
                        } else
                            i =
                                a === e
                                    ? `${r}${u}${o}`.trim()
                                    : `${a}${u}${o}`.trim();
                    } else i = t;
                    return i;
                });
            if (c)
                for (var l = 0; l < c.length; l += 1) {
                    if (
                        isInlineScript(t) &&
                        c[l].startsWith(r) &&
                        c[l].match(toRegExp(t))
                    )
                        return true;
                    if (
                        isInjectedScript(t) &&
                        c[l].startsWith(n) &&
                        c[l].match(toRegExp(t))
                    )
                        return true;
                }
            return false;
        }
        function getNativeRegexpTest() {
            var t = Object.getOwnPropertyDescriptor(RegExp.prototype, "test"),
                e = null == t ? void 0 : t.value;
            if (t && "function" == typeof t.value) return e;
            throw new Error("RegExp.prototype.test is not a function");
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function isEmptyObject(t) {
            return 0 === Object.keys(t).length && !t.prototype;
        }
        function backupRegExpValues() {
            try {
                for (var r = [], e = 1; e < 10; e += 1) {
                    var a = `$${e}`;
                    if (!RegExp[a]) break;
                    r.push(RegExp[a]);
                }
                return r;
            } catch (r) {
                return [];
            }
        }
        function restoreRegExpValues(e) {
            if (e.length)
                try {
                    var r = "";
                    r =
                        1 === e.length
                            ? `(${e[0]})`
                            : e.reduce(function (e, r, t) {
                                  return 1 === t
                                      ? `(${e}),(${r})`
                                      : `${e},(${r})`;
                              });
                    var t = new RegExp(r);
                    e.toString().replace(t, "");
                } catch (e) {
                    var n = `Failed to restore RegExp values: ${e}`;
                    console.log(n);
                }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            trustedReplaceOutboundText.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function trustedReplaceXhrResponse(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function trustedReplaceXhrResponse(source) {
            var pattern =
                arguments.length > 1 && arguments[1] !== undefined
                    ? arguments[1]
                    : "";
            var replacement =
                arguments.length > 2 && arguments[2] !== undefined
                    ? arguments[2]
                    : "";
            var propsToMatch =
                arguments.length > 3 && arguments[3] !== undefined
                    ? arguments[3]
                    : "";
            var verbose =
                arguments.length > 4 && arguments[4] !== undefined
                    ? arguments[4]
                    : false;
            if (typeof Proxy === "undefined") {
                return;
            }
            if (pattern === "" && replacement !== "") {
                var message = "Pattern argument should not be empty string.";
                logMessage(source, message);
                return;
            }
            var shouldLog = pattern === "" && replacement === "";
            var shouldLogContent = verbose === "true";
            var nativeOpen = window.XMLHttpRequest.prototype.open;
            var nativeSend = window.XMLHttpRequest.prototype.send;
            var xhrData;
            var openWrapper = function openWrapper(target, thisArg, args) {
                xhrData = getXhrData.apply(null, args);
                if (shouldLog) {
                    var _message = `xhr( ${objectToString(xhrData)} )`;
                    logMessage(source, _message, true);
                    hit(source);
                    return Reflect.apply(target, thisArg, args);
                }
                if (matchRequestProps(source, propsToMatch, xhrData)) {
                    thisArg.shouldBePrevented = true;
                    thisArg.headersReceived = !!thisArg.headersReceived;
                }
                if (thisArg.shouldBePrevented && !thisArg.headersReceived) {
                    thisArg.headersReceived = true;
                    thisArg.collectedHeaders = [];
                    var setRequestHeaderWrapper =
                        function setRequestHeaderWrapper(
                            target,
                            thisArg,
                            args,
                        ) {
                            thisArg.collectedHeaders.push(args);
                            return Reflect.apply(target, thisArg, args);
                        };
                    var setRequestHeaderHandler = {
                        apply: setRequestHeaderWrapper,
                    };
                    thisArg.setRequestHeader = new Proxy(
                        thisArg.setRequestHeader,
                        setRequestHeaderHandler,
                    );
                }
                return Reflect.apply(target, thisArg, args);
            };
            var sendWrapper = function sendWrapper(target, thisArg, args) {
                if (!thisArg.shouldBePrevented) {
                    return Reflect.apply(target, thisArg, args);
                }
                var forgedRequest = new XMLHttpRequest();
                forgedRequest.addEventListener("readystatechange", function () {
                    if (forgedRequest.readyState !== 4) {
                        return;
                    }
                    var {
                        readyState: readyState,
                        response: response,
                        responseText: responseText,
                        responseURL: responseURL,
                        responseXML: responseXML,
                        status: status,
                        statusText: statusText,
                    } = forgedRequest;
                    var content = responseText || response;
                    if (typeof content !== "string") {
                        return;
                    }
                    var patternRegexp =
                        pattern === "*" ? /(\n|.)*/ : toRegExp(pattern);
                    if (shouldLogContent) {
                        logMessage(source, `Original text content: ${content}`);
                    }
                    var modifiedContent = content.replace(
                        patternRegexp,
                        replacement,
                    );
                    if (shouldLogContent) {
                        logMessage(
                            source,
                            `Modified text content: ${modifiedContent}`,
                        );
                    }
                    Object.defineProperties(thisArg, {
                        readyState: {
                            value: readyState,
                            writable: false,
                        },
                        responseURL: {
                            value: responseURL,
                            writable: false,
                        },
                        responseXML: {
                            value: responseXML,
                            writable: false,
                        },
                        status: {
                            value: status,
                            writable: false,
                        },
                        statusText: {
                            value: statusText,
                            writable: false,
                        },
                        response: {
                            value: modifiedContent,
                            writable: false,
                        },
                        responseText: {
                            value: modifiedContent,
                            writable: false,
                        },
                    });
                    setTimeout(function () {
                        var stateEvent = new Event("readystatechange");
                        thisArg.dispatchEvent(stateEvent);
                        var loadEvent = new Event("load");
                        thisArg.dispatchEvent(loadEvent);
                        var loadEndEvent = new Event("loadend");
                        thisArg.dispatchEvent(loadEndEvent);
                    }, 1);
                    hit(source);
                });
                nativeOpen.apply(forgedRequest, [xhrData.method, xhrData.url]);
                thisArg.collectedHeaders.forEach(function (header) {
                    var name = header[0];
                    var value = header[1];
                    forgedRequest.setRequestHeader(name, value);
                });
                thisArg.collectedHeaders = [];
                try {
                    nativeSend.call(forgedRequest, args);
                } catch (_unused) {
                    return Reflect.apply(target, thisArg, args);
                }
                return undefined;
            };
            var openHandler = {
                apply: openWrapper,
            };
            var sendHandler = {
                apply: sendWrapper,
            };
            XMLHttpRequest.prototype.open = new Proxy(
                XMLHttpRequest.prototype.open,
                openHandler,
            );
            XMLHttpRequest.prototype.send = new Proxy(
                XMLHttpRequest.prototype.send,
                sendHandler,
            );
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function objectToString(t) {
            return t && "object" == typeof t
                ? isEmptyObject(t)
                    ? "{}"
                    : Object.entries(t)
                          .map(function (t) {
                              var n = t[0],
                                  e = t[1],
                                  o = e;
                              return (
                                  e instanceof Object &&
                                      (o = `{ ${objectToString(e)} }`),
                                  `${n}:"${o}"`
                              );
                          })
                          .join(" ")
                : String(t);
        }
        function matchRequestProps(e, t, r) {
            if ("" === t || "*" === t) return true;
            var a,
                s = parseMatchProps(t);
            if (isValidParsedData(s)) {
                var n = getMatchPropsData(s);
                a = Object.keys(n).every(function (e) {
                    var t = n[e],
                        a = r[e];
                    return (
                        Object.prototype.hasOwnProperty.call(r, e) &&
                        "string" == typeof a &&
                        (null == t ? void 0 : t.test(a))
                    );
                });
            } else (logMessage(e, `Invalid parameter: ${t}`), (a = false));
            return a;
        }
        function getXhrData(r, t, a, e, n) {
            return {
                method: r,
                url: t,
                async: a,
                user: e,
                password: n,
            };
        }
        function getMatchPropsData(t) {
            var a = {};
            return (
                Object.keys(t).forEach(function (c) {
                    a[c] = toRegExp(t[c]);
                }),
                a
            );
        }
        function getRequestProps() {
            return [
                "url",
                "method",
                "headers",
                "body",
                "credentials",
                "cache",
                "redirect",
                "referrer",
                "referrerPolicy",
                "integrity",
                "keepalive",
                "signal",
                "mode",
            ];
        }
        function isValidParsedData(t) {
            return Object.values(t).every(function (t) {
                return isValidStrPattern(t);
            });
        }
        function parseMatchProps(e) {
            var r = {};
            return (
                e.split(" ").forEach(function (e) {
                    var n = e.indexOf(":"),
                        i = e.slice(0, n);
                    if (
                        (function (e) {
                            return getRequestProps().includes(e);
                        })(i)
                    ) {
                        var s = e.slice(n + 1);
                        r[i] = s;
                    } else r.url = e;
                }),
                r
            );
        }
        function isValidStrPattern(e) {
            var t,
                n = escapeRegExp(e);
            "/" === e[0] && "/" === e[e.length - 1] && (n = e.slice(1, -1));
            try {
                ((t = new RegExp(n)), (t = !0));
            } catch (e) {
                t = false;
            }
            return t;
        }
        function escapeRegExp(e) {
            return e.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        }
        function isEmptyObject(t) {
            return 0 === Object.keys(t).length && !t.prototype;
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            trustedReplaceXhrResponse.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function trustedSetAttr(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function trustedSetAttr(source, selector, attr) {
            var value =
                arguments.length > 3 && arguments[3] !== undefined
                    ? arguments[3]
                    : "";
            if (!selector || !attr) {
                return;
            }
            setAttributeBySelector(source, selector, attr, value);
            observeDOMChanges(function () {
                return setAttributeBySelector(source, selector, attr, value);
            }, true);
        }
        function setAttributeBySelector(e, t, l, o) {
            var r,
                c =
                    arguments.length > 4 && void 0 !== arguments[4]
                        ? arguments[4]
                        : defaultAttributeSetter;
            try {
                r = document.querySelectorAll(t);
            } catch (l) {
                return void logMessage(
                    e,
                    `Failed to find elements matching selector "${t}"`,
                );
            }
            if (r && 0 !== r.length)
                try {
                    (r.forEach(function (e) {
                        return c(e, l, o);
                    }),
                        hit(e));
                } catch (t) {
                    logMessage(
                        e,
                        `Failed to set [${l}="${o}"] to each of selected elements.`,
                    );
                }
        }
        function observeDOMChanges(t) {
            var e =
                    arguments.length > 1 &&
                    void 0 !== arguments[1] &&
                    arguments[1],
                n =
                    arguments.length > 2 && void 0 !== arguments[2]
                        ? arguments[2]
                        : [],
                i = new MutationObserver(
                    throttle(function () {
                        (disconnect(), t(), connect());
                    }, 20),
                ),
                connect = function connect() {
                    n.length > 0
                        ? i.observe(document.documentElement, {
                              childList: true,
                              subtree: true,
                              attributes: e,
                              attributeFilter: n,
                          })
                        : i.observe(document.documentElement, {
                              childList: true,
                              subtree: true,
                              attributes: e,
                          });
                },
                disconnect = function disconnect() {
                    i.disconnect();
                };
            connect();
        }
        function defaultAttributeSetter(t, e, r) {
            return t.setAttribute(e, r);
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function throttle(n, t) {
            var r,
                e = false,
                _wrapper9 = function _wrapper() {
                    for (
                        var o = arguments.length, u = new Array(o), f = 0;
                        f < o;
                        f++
                    )
                        u[f] = arguments[f];
                    e
                        ? (r = u)
                        : (n(...u),
                          (e = true),
                          setTimeout(function () {
                              ((e = false), r && (_wrapper9(...r), (r = null)));
                          }, t));
                };
            return _wrapper9;
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            trustedSetAttr.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function trustedSetConstant(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function trustedSetConstant(source, property, value, stack) {
            if (!property || !matchStackTrace(stack, new Error().stack)) {
                return;
            }
            var constantValue;
            try {
                constantValue = inferValue(value);
            } catch (e) {
                logMessage(source, e);
                return;
            }
            var canceled = false;
            var mustCancel = function mustCancel(value) {
                if (canceled) {
                    return canceled;
                }
                canceled =
                    value !== undefined &&
                    constantValue !== undefined &&
                    typeof value !== typeof constantValue &&
                    value !== null;
                return canceled;
            };
            var trapProp = function trapProp(
                base,
                prop,
                configurable,
                handler,
            ) {
                if (!handler.init(base[prop])) {
                    return false;
                }
                var origDescriptor = Object.getOwnPropertyDescriptor(
                    base,
                    prop,
                );
                var prevSetter;
                if (origDescriptor instanceof Object) {
                    if (!origDescriptor.configurable) {
                        var message = `Property '${prop}' is not configurable`;
                        logMessage(source, message);
                        return false;
                    }
                    base[prop] = constantValue;
                    if (origDescriptor.set instanceof Function) {
                        prevSetter = origDescriptor.set;
                    }
                }
                Object.defineProperty(base, prop, {
                    configurable: configurable,
                    get() {
                        return handler.get();
                    },
                    set(a) {
                        if (prevSetter !== undefined) {
                            prevSetter(a);
                        }
                        handler.set(a);
                    },
                });
                return true;
            };
            var _setChainPropAccess = function setChainPropAccess(
                owner,
                property,
            ) {
                var chainInfo = getPropertyInChain(owner, property);
                var { base: base } = chainInfo;
                var { prop: prop, chain: chain } = chainInfo;
                var inChainPropHandler = {
                    factValue: undefined,
                    init(a) {
                        this.factValue = a;
                        return true;
                    },
                    get() {
                        return this.factValue;
                    },
                    set(a) {
                        if (this.factValue === a) {
                            return;
                        }
                        this.factValue = a;
                        if (a instanceof Object) {
                            _setChainPropAccess(a, chain);
                        }
                    },
                };
                var endPropHandler = {
                    init(a) {
                        if (mustCancel(a)) {
                            return false;
                        }
                        return true;
                    },
                    get() {
                        return constantValue;
                    },
                    set(a) {
                        if (!mustCancel(a)) {
                            return;
                        }
                        constantValue = a;
                    },
                };
                if (!chain) {
                    var isTrapped = trapProp(base, prop, false, endPropHandler);
                    if (isTrapped) {
                        hit(source);
                    }
                    return;
                }
                if (base !== undefined && base[prop] === null) {
                    trapProp(base, prop, true, inChainPropHandler);
                    return;
                }
                if (
                    (base instanceof Object || typeof base === "object") &&
                    isEmptyObject(base)
                ) {
                    trapProp(base, prop, true, inChainPropHandler);
                }
                var propValue = owner[prop];
                if (
                    propValue instanceof Object ||
                    (typeof propValue === "object" && propValue !== null)
                ) {
                    _setChainPropAccess(propValue, chain);
                }
                trapProp(base, prop, true, inChainPropHandler);
            };
            _setChainPropAccess(window, property);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function inferValue(r) {
            if ("undefined" !== r) {
                if ("false" === r) return false;
                if ("true" === r) return true;
                if ("null" === r) return null;
                if ("NaN" === r) return NaN;
                if (r.startsWith("/") && r.endsWith("/")) return toRegExp(r);
                var e = Number(r);
                if (!nativeIsNaN(e)) {
                    if (Math.abs(e) > 32767)
                        throw new Error(
                            "number values bigger than 32767 are not allowed",
                        );
                    return e;
                }
                var t = `'${r}' value type can't be inferred`;
                try {
                    var n = JSON.parse(r);
                    if (n instanceof Object || "string" == typeof n) return n;
                } catch (r) {
                    t += `: ${r}`;
                }
                throw new TypeError(t);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function getPropertyInChain(e, r) {
            var n = r.indexOf(".");
            if (-1 === n)
                return {
                    base: e,
                    prop: r,
                };
            var i = r.slice(0, n);
            if (null === e)
                return {
                    base: e,
                    prop: i,
                    chain: r,
                };
            var t = e[i];
            return (
                (r = r.slice(n + 1)),
                ((e instanceof Object || "object" == typeof e) &&
                    isEmptyObject(e)) ||
                null === t
                    ? {
                          base: e,
                          prop: i,
                          chain: r,
                      }
                    : void 0 !== t
                      ? getPropertyInChain(t, r)
                      : (Object.defineProperty(e, i, {
                            configurable: true,
                        }),
                        {
                            base: e,
                            prop: i,
                            chain: r,
                        })
            );
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function matchStackTrace(e, t) {
            if (!e || "" === e) return true;
            var r = backupRegExpValues();
            if (shouldAbortInlineOrInjectedScript(e, t))
                return (
                    r.length && r[0] !== RegExp.$1 && restoreRegExpValues(r),
                    true
                );
            var n = toRegExp(e),
                a = t
                    .split("\n")
                    .slice(2)
                    .map(function (e) {
                        return e.trim();
                    })
                    .join("\n");
            return (
                r.length && r[0] !== RegExp.$1 && restoreRegExpValues(r),
                getNativeRegexpTest().call(n, a)
            );
        }
        function nativeIsNaN(N) {
            return (Number.isNaN || window.isNaN)(N);
        }
        function isEmptyObject(t) {
            return 0 === Object.keys(t).length && !t.prototype;
        }
        function getNativeRegexpTest() {
            var t = Object.getOwnPropertyDescriptor(RegExp.prototype, "test"),
                e = null == t ? void 0 : t.value;
            if (t && "function" == typeof t.value) return e;
            throw new Error("RegExp.prototype.test is not a function");
        }
        function shouldAbortInlineOrInjectedScript(t, i) {
            var r = "inlineScript",
                n = "injectedScript",
                isInlineScript = function isInlineScript(t) {
                    return t.includes(r);
                },
                isInjectedScript = function isInjectedScript(t) {
                    return t.includes(n);
                };
            if (!isInlineScript(t) && !isInjectedScript(t)) return false;
            var e = window.location.href,
                s = e.indexOf("#");
            -1 !== s && (e = e.slice(0, s));
            var c = i
                .split("\n")
                .slice(2)
                .map(function (t) {
                    return t.trim();
                })
                .map(function (t) {
                    var i,
                        s = /(.*?@)?(\S+)(:\d+)(:\d+)\)?$/.exec(t);
                    if (s) {
                        var c,
                            l,
                            a = s[2],
                            u = s[3],
                            o = s[4];
                        if (
                            (null !== (c = a) &&
                                void 0 !== c &&
                                c.startsWith("(") &&
                                (a = a.slice(1)),
                            null !== (l = a) &&
                                void 0 !== l &&
                                l.startsWith("<anonymous>"))
                        ) {
                            var d;
                            a = n;
                            var f =
                                void 0 !== s[1]
                                    ? s[1].slice(0, -1)
                                    : t.slice(0, s.index).trim();
                            (null !== (d = f) &&
                                void 0 !== d &&
                                d.startsWith("at") &&
                                (f = f.slice(2).trim()),
                                (i = `${f} ${a}${u}${o}`.trim()));
                        } else
                            i =
                                a === e
                                    ? `${r}${u}${o}`.trim()
                                    : `${a}${u}${o}`.trim();
                    } else i = t;
                    return i;
                });
            if (c)
                for (var l = 0; l < c.length; l += 1) {
                    if (
                        isInlineScript(t) &&
                        c[l].startsWith(r) &&
                        c[l].match(toRegExp(t))
                    )
                        return true;
                    if (
                        isInjectedScript(t) &&
                        c[l].startsWith(n) &&
                        c[l].match(toRegExp(t))
                    )
                        return true;
                }
            return false;
        }
        function backupRegExpValues() {
            try {
                for (var r = [], e = 1; e < 10; e += 1) {
                    var a = `$${e}`;
                    if (!RegExp[a]) break;
                    r.push(RegExp[a]);
                }
                return r;
            } catch (r) {
                return [];
            }
        }
        function restoreRegExpValues(e) {
            if (e.length)
                try {
                    var r = "";
                    r =
                        1 === e.length
                            ? `(${e[0]})`
                            : e.reduce(function (e, r, t) {
                                  return 1 === t
                                      ? `(${e}),(${r})`
                                      : `${e},(${r})`;
                              });
                    var t = new RegExp(r);
                    e.toString().replace(t, "");
                } catch (e) {
                    var n = `Failed to restore RegExp values: ${e}`;
                    console.log(n);
                }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            trustedSetConstant.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function trustedSetCookie(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function trustedSetCookie(source, name, value) {
            var offsetExpiresSec =
                arguments.length > 3 && arguments[3] !== undefined
                    ? arguments[3]
                    : "";
            var path =
                arguments.length > 4 && arguments[4] !== undefined
                    ? arguments[4]
                    : "/";
            var domain =
                arguments.length > 5 && arguments[5] !== undefined
                    ? arguments[5]
                    : "";
            if (typeof name === "undefined") {
                logMessage(source, "Cookie name should be specified");
                return;
            }
            if (typeof value === "undefined") {
                logMessage(source, "Cookie value should be specified");
                return;
            }
            var parsedValue = parseKeywordValue(value);
            if (!isValidCookiePath(path)) {
                logMessage(source, `Invalid cookie path: '${path}'`);
                return;
            }
            if (!document.location.origin.includes(domain)) {
                logMessage(
                    source,
                    `Cookie domain not matched by origin: '${domain}'`,
                );
                return;
            }
            var cookieToSet = serializeCookie(
                name,
                parsedValue,
                path,
                domain,
                false,
            );
            if (!cookieToSet) {
                logMessage(source, "Invalid cookie name or value");
                return;
            }
            if (offsetExpiresSec) {
                var parsedOffsetMs = getTrustedCookieOffsetMs(offsetExpiresSec);
                if (!parsedOffsetMs) {
                    logMessage(
                        source,
                        `Invalid offsetExpiresSec value: ${offsetExpiresSec}`,
                    );
                    return;
                }
                var expires = Date.now() + parsedOffsetMs;
                cookieToSet += `; expires=${new Date(expires).toUTCString()}`;
            }
            document.cookie = cookieToSet;
            hit(source);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function serializeCookie(e, o, i) {
            var n =
                    arguments.length > 3 && void 0 !== arguments[3]
                        ? arguments[3]
                        : "",
                t =
                    !(arguments.length > 4 && void 0 !== arguments[4]) ||
                    arguments[4];
            if ((!t && `${o}`.includes(";")) || e.includes(";")) return null;
            var r = `${e}=${t ? encodeURIComponent(o) : o}`;
            if (e.startsWith("__Host-"))
                return (
                    (r += "; path=/; secure"),
                    n &&
                        console.debug(
                            `Domain value: "${n}" has been ignored, because is not allowed for __Host- prefixed cookies`,
                        ),
                    r
                );
            var s = getCookiePath(i);
            return (
                s && (r += `; ${s}`),
                e.startsWith("__Secure-") && (r += "; secure"),
                n && (r += `; domain=${n}`),
                r
            );
        }
        function isValidCookiePath(n) {
            return "/" === n || "none" === n;
        }
        function getTrustedCookieOffsetMs(e) {
            var r;
            if ("1year" === e) r = 31536e3;
            else if ("1day" === e) r = 86400;
            else if (((r = Number.parseInt(e, 10)), Number.isNaN(r)))
                return null;
            return 1e3 * r;
        }
        function parseKeywordValue(t) {
            var e = t;
            return (
                "$now$" === t
                    ? (e = Date.now().toString())
                    : "$currentDate$" === t
                      ? (e = Date())
                      : "$currentISODate$" === t &&
                        (e = new Date().toISOString()),
                e
            );
        }
        function getCookiePath(t) {
            return "/" === t ? "path=/" : "";
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            trustedSetCookie.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function trustedSetCookieReload(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function trustedSetCookieReload(source, name, value) {
            var offsetExpiresSec =
                arguments.length > 3 && arguments[3] !== undefined
                    ? arguments[3]
                    : "";
            var path =
                arguments.length > 4 && arguments[4] !== undefined
                    ? arguments[4]
                    : "/";
            var domain =
                arguments.length > 5 && arguments[5] !== undefined
                    ? arguments[5]
                    : "";
            if (typeof name === "undefined") {
                logMessage(source, "Cookie name should be specified");
                return;
            }
            if (typeof value === "undefined") {
                logMessage(source, "Cookie value should be specified");
                return;
            }
            if (isCookieSetWithValue(document.cookie, name, value)) {
                return;
            }
            var parsedValue = parseKeywordValue(value);
            if (!isValidCookiePath(path)) {
                logMessage(source, `Invalid cookie path: '${path}'`);
                return;
            }
            if (!document.location.origin.includes(domain)) {
                logMessage(
                    source,
                    `Cookie domain not matched by origin: '${domain}'`,
                );
                return;
            }
            var cookieToSet = serializeCookie(
                name,
                parsedValue,
                path,
                domain,
                false,
            );
            if (!cookieToSet) {
                logMessage(source, "Invalid cookie name or value");
                return;
            }
            if (offsetExpiresSec) {
                var parsedOffsetMs = getTrustedCookieOffsetMs(offsetExpiresSec);
                if (!parsedOffsetMs) {
                    logMessage(
                        source,
                        `Invalid offsetExpiresSec value: ${offsetExpiresSec}`,
                    );
                    return;
                }
                var expires = Date.now() + parsedOffsetMs;
                cookieToSet += `; expires=${new Date(expires).toUTCString()}`;
            }
            document.cookie = cookieToSet;
            hit(source);
            var cookieValueToCheck = parseCookieString(document.cookie)[name];
            if (
                isCookieSetWithValue(document.cookie, name, cookieValueToCheck)
            ) {
                window.location.reload();
            }
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function isCookieSetWithValue(e, t, r) {
            return e.split(";").some(function (e) {
                var n = e.indexOf("=");
                if (-1 === n) return false;
                var i = e.slice(0, n).trim(),
                    a = e.slice(n + 1).trim();
                if (
                    new Set(["$now$", "$currentDate$", "$currentISODate$"]).has(
                        r,
                    )
                ) {
                    var u = Date.now(),
                        s = /^\d+$/.test(a)
                            ? parseInt(a, 10)
                            : new Date(a).getTime();
                    return t === i && s > u - 864e5;
                }
                return t === i && r === a;
            });
        }
        function serializeCookie(e, o, i) {
            var n =
                    arguments.length > 3 && void 0 !== arguments[3]
                        ? arguments[3]
                        : "",
                t =
                    !(arguments.length > 4 && void 0 !== arguments[4]) ||
                    arguments[4];
            if ((!t && `${o}`.includes(";")) || e.includes(";")) return null;
            var r = `${e}=${t ? encodeURIComponent(o) : o}`;
            if (e.startsWith("__Host-"))
                return (
                    (r += "; path=/; secure"),
                    n &&
                        console.debug(
                            `Domain value: "${n}" has been ignored, because is not allowed for __Host- prefixed cookies`,
                        ),
                    r
                );
            var s = getCookiePath(i);
            return (
                s && (r += `; ${s}`),
                e.startsWith("__Secure-") && (r += "; secure"),
                n && (r += `; domain=${n}`),
                r
            );
        }
        function isValidCookiePath(n) {
            return "/" === n || "none" === n;
        }
        function getTrustedCookieOffsetMs(e) {
            var r;
            if ("1year" === e) r = 31536e3;
            else if ("1day" === e) r = 86400;
            else if (((r = Number.parseInt(e, 10)), Number.isNaN(r)))
                return null;
            return 1e3 * r;
        }
        function parseKeywordValue(t) {
            var e = t;
            return (
                "$now$" === t
                    ? (e = Date.now().toString())
                    : "$currentDate$" === t
                      ? (e = Date())
                      : "$currentISODate$" === t &&
                        (e = new Date().toISOString()),
                e
            );
        }
        function parseCookieString(i) {
            var r = i.split(";"),
                n = {};
            return (
                r.forEach(function (i) {
                    var r,
                        t = "",
                        e = i.indexOf("=");
                    (-1 === e
                        ? (r = i.trim())
                        : ((r = i.slice(0, e).trim()), (t = i.slice(e + 1))),
                        (n[r] = t || null));
                }),
                n
            );
        }
        function getCookiePath(t) {
            return "/" === t ? "path=/" : "";
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            trustedSetCookieReload.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function trustedSetLocalStorageItem(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function trustedSetLocalStorageItem(source, key, value) {
            if (typeof key === "undefined") {
                logMessage(source, "Item key should be specified");
                return;
            }
            if (typeof value === "undefined") {
                logMessage(source, "Item value should be specified");
                return;
            }
            var parsedValue = parseKeywordValue(value);
            var { localStorage: localStorage } = window;
            setStorageItem(source, localStorage, key, parsedValue);
            hit(source);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function setStorageItem(e, t, s, a) {
            try {
                t.setItem(s, a);
            } catch (t) {
                var o = `Unable to set storage item due to: ${t.message}`;
                logMessage(e, o);
            }
        }
        function parseKeywordValue(t) {
            var e = t;
            return (
                "$now$" === t
                    ? (e = Date.now().toString())
                    : "$currentDate$" === t
                      ? (e = Date())
                      : "$currentISODate$" === t &&
                        (e = new Date().toISOString()),
                e
            );
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            trustedSetLocalStorageItem.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function trustedSetSessionStorageItem(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function trustedSetSessionStorageItem(source, key, value) {
            if (typeof key === "undefined") {
                logMessage(source, "Item key should be specified");
                return;
            }
            if (typeof value === "undefined") {
                logMessage(source, "Item value should be specified");
                return;
            }
            var parsedValue = parseKeywordValue(value);
            var { sessionStorage: sessionStorage } = window;
            setStorageItem(source, sessionStorage, key, parsedValue);
            hit(source);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function setStorageItem(e, t, s, a) {
            try {
                t.setItem(s, a);
            } catch (t) {
                var o = `Unable to set storage item due to: ${t.message}`;
                logMessage(e, o);
            }
        }
        function parseKeywordValue(t) {
            var e = t;
            return (
                "$now$" === t
                    ? (e = Date.now().toString())
                    : "$currentDate$" === t
                      ? (e = Date())
                      : "$currentISODate$" === t &&
                        (e = new Date().toISOString()),
                e
            );
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            trustedSetSessionStorageItem.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function trustedSuppressNativeMethod(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function trustedSuppressNativeMethod(source, methodPath, signatureStr) {
            var how =
                arguments.length > 3 && arguments[3] !== undefined
                    ? arguments[3]
                    : "abort";
            var stack =
                arguments.length > 4 && arguments[4] !== undefined
                    ? arguments[4]
                    : "";
            if (!methodPath || !signatureStr) {
                return;
            }
            var IGNORE_ARG_SYMBOL = " ";
            var suppress = how === "abort" ? getAbortFunc() : function () {};
            var signatureMatcher;
            try {
                signatureMatcher = signatureStr
                    .split("|")
                    .map(function (value) {
                        return value === IGNORE_ARG_SYMBOL
                            ? value
                            : inferValue(value);
                    });
            } catch (e) {
                logMessage(
                    source,
                    `Could not parse the signature matcher: ${getErrorMessage(e)}`,
                );
                return;
            }
            var getPathParts = getPropertyInChain;
            var {
                base: base,
                chain: chain,
                prop: prop,
            } = getPathParts(window, methodPath);
            if (typeof chain !== "undefined") {
                logMessage(
                    source,
                    `Could not reach the end of the prop chain: ${methodPath}`,
                );
                return;
            }
            var nativeMethod = base[prop];
            if (!nativeMethod || typeof nativeMethod !== "function") {
                logMessage(
                    source,
                    `Could not retrieve the method: ${methodPath}`,
                );
                return;
            }
            function matchMethodCall(nativeArguments, matchArguments) {
                return matchArguments.every(function (matcher, i) {
                    if (matcher === IGNORE_ARG_SYMBOL) {
                        return true;
                    }
                    var argument = nativeArguments[i];
                    return isValueMatched(argument, matcher);
                });
            }
            var isMatchingSuspended = false;
            function apply(target, thisArg, argumentsList) {
                if (isMatchingSuspended) {
                    return Reflect.apply(target, thisArg, argumentsList);
                }
                isMatchingSuspended = true;
                if (stack && !matchStackTrace(stack, new Error().stack || "")) {
                    isMatchingSuspended = false;
                    return Reflect.apply(target, thisArg, argumentsList);
                }
                var isMatching = matchMethodCall(
                    argumentsList,
                    signatureMatcher,
                );
                isMatchingSuspended = false;
                if (isMatching) {
                    hit(source);
                    return suppress();
                }
                return Reflect.apply(target, thisArg, argumentsList);
            }
            base[prop] = new Proxy(nativeMethod, {
                apply: apply,
            });
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function getPropertyInChain(e, r) {
            var n = r.indexOf(".");
            if (-1 === n)
                return {
                    base: e,
                    prop: r,
                };
            var i = r.slice(0, n);
            if (null === e)
                return {
                    base: e,
                    prop: i,
                    chain: r,
                };
            var t = e[i];
            return (
                (r = r.slice(n + 1)),
                ((e instanceof Object || "object" == typeof e) &&
                    isEmptyObject(e)) ||
                null === t
                    ? {
                          base: e,
                          prop: i,
                          chain: r,
                      }
                    : void 0 !== t
                      ? getPropertyInChain(t, r)
                      : (Object.defineProperty(e, i, {
                            configurable: true,
                        }),
                        {
                            base: e,
                            prop: i,
                            chain: r,
                        })
            );
        }
        function inferValue(r) {
            if ("undefined" !== r) {
                if ("false" === r) return false;
                if ("true" === r) return true;
                if ("null" === r) return null;
                if ("NaN" === r) return NaN;
                if (r.startsWith("/") && r.endsWith("/")) return toRegExp(r);
                var e = Number(r);
                if (!nativeIsNaN(e)) {
                    if (Math.abs(e) > 32767)
                        throw new Error(
                            "number values bigger than 32767 are not allowed",
                        );
                    return e;
                }
                var t = `'${r}' value type can't be inferred`;
                try {
                    var n = JSON.parse(r);
                    if (n instanceof Object || "string" == typeof n) return n;
                } catch (r) {
                    t += `: ${r}`;
                }
                throw new TypeError(t);
            }
        }
        function isValueMatched(t, r) {
            return (
                "function" != typeof t &&
                (nativeIsNaN(t)
                    ? nativeIsNaN(r)
                    : null == t || "number" == typeof t || "boolean" == typeof t
                      ? t === r
                      : "string" == typeof t
                        ? ("string" == typeof r || r instanceof RegExp) &&
                          isStringMatched(t, r)
                        : Array.isArray(t) && Array.isArray(r)
                          ? isArrayMatched(t, r)
                          : !(!isArbitraryObject(t) || !isArbitraryObject(r)) &&
                            isObjectMatched(t, r))
            );
        }
        function getAbortFunc() {
            var r = randomId(),
                n = false;
            return function () {
                throw (
                    n ||
                        ((window.onerror = createOnErrorHandler(r)),
                        (n = true)),
                    new ReferenceError(r)
                );
            };
        }
        function matchStackTrace(e, t) {
            if (!e || "" === e) return true;
            var r = backupRegExpValues();
            if (shouldAbortInlineOrInjectedScript(e, t))
                return (
                    r.length && r[0] !== RegExp.$1 && restoreRegExpValues(r),
                    true
                );
            var n = toRegExp(e),
                a = t
                    .split("\n")
                    .slice(2)
                    .map(function (e) {
                        return e.trim();
                    })
                    .join("\n");
            return (
                r.length && r[0] !== RegExp.$1 && restoreRegExpValues(r),
                getNativeRegexpTest().call(n, a)
            );
        }
        function getErrorMessage(e) {
            var r;
            if (
                "object" == typeof (r = e) &&
                null !== r &&
                "message" in r &&
                "string" == typeof r.message
            )
                return e.message;
            try {
                return new Error(JSON.stringify(e)).message;
            } catch (r) {
                return new Error(String(e)).message;
            }
        }
        function shouldAbortInlineOrInjectedScript(t, i) {
            var r = "inlineScript",
                n = "injectedScript",
                isInlineScript = function isInlineScript(t) {
                    return t.includes(r);
                },
                isInjectedScript = function isInjectedScript(t) {
                    return t.includes(n);
                };
            if (!isInlineScript(t) && !isInjectedScript(t)) return false;
            var e = window.location.href,
                s = e.indexOf("#");
            -1 !== s && (e = e.slice(0, s));
            var c = i
                .split("\n")
                .slice(2)
                .map(function (t) {
                    return t.trim();
                })
                .map(function (t) {
                    var i,
                        s = /(.*?@)?(\S+)(:\d+)(:\d+)\)?$/.exec(t);
                    if (s) {
                        var c,
                            l,
                            a = s[2],
                            u = s[3],
                            o = s[4];
                        if (
                            (null !== (c = a) &&
                                void 0 !== c &&
                                c.startsWith("(") &&
                                (a = a.slice(1)),
                            null !== (l = a) &&
                                void 0 !== l &&
                                l.startsWith("<anonymous>"))
                        ) {
                            var d;
                            a = n;
                            var f =
                                void 0 !== s[1]
                                    ? s[1].slice(0, -1)
                                    : t.slice(0, s.index).trim();
                            (null !== (d = f) &&
                                void 0 !== d &&
                                d.startsWith("at") &&
                                (f = f.slice(2).trim()),
                                (i = `${f} ${a}${u}${o}`.trim()));
                        } else
                            i =
                                a === e
                                    ? `${r}${u}${o}`.trim()
                                    : `${a}${u}${o}`.trim();
                    } else i = t;
                    return i;
                });
            if (c)
                for (var l = 0; l < c.length; l += 1) {
                    if (
                        isInlineScript(t) &&
                        c[l].startsWith(r) &&
                        c[l].match(toRegExp(t))
                    )
                        return true;
                    if (
                        isInjectedScript(t) &&
                        c[l].startsWith(n) &&
                        c[l].match(toRegExp(t))
                    )
                        return true;
                }
            return false;
        }
        function getNativeRegexpTest() {
            var t = Object.getOwnPropertyDescriptor(RegExp.prototype, "test"),
                e = null == t ? void 0 : t.value;
            if (t && "function" == typeof t.value) return e;
            throw new Error("RegExp.prototype.test is not a function");
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function nativeIsNaN(N) {
            return (Number.isNaN || window.isNaN)(N);
        }
        function randomId() {
            return Math.random().toString(36).slice(2, 9);
        }
        function createOnErrorHandler(r) {
            var n = window.onerror;
            return function (e) {
                if ("string" == typeof e && e.includes(r)) return true;
                if (n instanceof Function) {
                    for (
                        var t = arguments.length,
                            o = new Array(t > 1 ? t - 1 : 0),
                            i = 1;
                        i < t;
                        i++
                    )
                        o[i - 1] = arguments[i];
                    return n.apply(window, [e, ...o]);
                }
                return false;
            };
        }
        function isEmptyObject(t) {
            return 0 === Object.keys(t).length && !t.prototype;
        }
        function isArbitraryObject(r) {
            return !(
                null === r ||
                "object" != typeof r ||
                Array.isArray(r) ||
                r instanceof RegExp
            );
        }
        function isStringMatched(t, n) {
            return "string" == typeof n
                ? "" === n
                    ? t === n
                    : t.includes(n)
                : n instanceof RegExp && n.test(t);
        }
        function isArrayMatched(r, n) {
            if (0 === r.length) return 0 === n.length;
            if (0 === n.length) return false;
            for (
                var t,
                    _loop = function _loop() {
                        var t = n[e];
                        return r.some(function (r) {
                            return isValueMatched(r, t);
                        })
                            ? 0
                            : {
                                  v: false,
                              };
                    },
                    e = 0;
                e < n.length;
                e += 1
            )
                if (0 !== (t = _loop()) && t) return t.v;
            return true;
        }
        function isObjectMatched(e, t) {
            for (var r = Object.keys(t), a = 0; a < r.length; a += 1) {
                var c = r[a],
                    n = e[c];
                if (!isValueMatched(n, t[c])) return false;
            }
            return true;
        }
        function backupRegExpValues() {
            try {
                for (var r = [], e = 1; e < 10; e += 1) {
                    var a = `$${e}`;
                    if (!RegExp[a]) break;
                    r.push(RegExp[a]);
                }
                return r;
            } catch (r) {
                return [];
            }
        }
        function restoreRegExpValues(e) {
            if (e.length)
                try {
                    var r = "";
                    r =
                        1 === e.length
                            ? `(${e[0]})`
                            : e.reduce(function (e, r, t) {
                                  return 1 === t
                                      ? `(${e}),(${r})`
                                      : `${e},(${r})`;
                              });
                    var t = new RegExp(r);
                    e.toString().replace(t, "");
                } catch (e) {
                    var n = `Failed to restore RegExp values: ${e}`;
                    console.log(n);
                }
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            trustedSuppressNativeMethod.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    function xmlPrune(source, args) {
        var flag = "done";
        var uniqueIdentifier =
            source.uniqueId +
            source.name +
            "_" +
            (Array.isArray(args) ? args.join("_") : "");
        if (source.uniqueId) {
            if (Window.prototype.toString[uniqueIdentifier] === flag) {
                return;
            }
        }
        function xmlPrune(source, propsToRemove) {
            var optionalProp =
                arguments.length > 2 && arguments[2] !== undefined
                    ? arguments[2]
                    : "";
            var urlToMatch =
                arguments.length > 3 && arguments[3] !== undefined
                    ? arguments[3]
                    : "";
            var verbose =
                arguments.length > 4 && arguments[4] !== undefined
                    ? arguments[4]
                    : false;
            if (
                typeof Reflect === "undefined" ||
                typeof fetch === "undefined" ||
                typeof Proxy === "undefined" ||
                typeof Response === "undefined"
            ) {
                return;
            }
            var shouldPruneResponse = false;
            var shouldLogContent = verbose === "true";
            var urlMatchRegexp = toRegExp(urlToMatch);
            var XPATH_MARKER = "xpath(";
            var isXpath =
                propsToRemove && propsToRemove.startsWith(XPATH_MARKER);
            var getXPathElements = function getXPathElements(contextNode) {
                var matchedElements = [];
                try {
                    var elementsToRemove = propsToRemove.slice(
                        XPATH_MARKER.length,
                        -1,
                    );
                    var xpathResult = contextNode.evaluate(
                        elementsToRemove,
                        contextNode,
                        null,
                        XPathResult.UNORDERED_NODE_SNAPSHOT_TYPE,
                        null,
                    );
                    for (var i = 0; i < xpathResult.snapshotLength; i += 1) {
                        matchedElements.push(xpathResult.snapshotItem(i));
                    }
                } catch (ex) {
                    var message = `Invalid XPath parameter: ${propsToRemove}\n${ex}`;
                    logMessage(source, message);
                }
                return matchedElements;
            };
            var xPathPruning = function xPathPruning(xPathElements) {
                xPathElements.forEach(function (element) {
                    if (element.nodeType === 1) {
                        element.remove();
                    } else if (element.nodeType === 2) {
                        element.ownerElement.removeAttribute(element.nodeName);
                    }
                });
            };
            var isXML = function isXML(text) {
                if (typeof text === "string") {
                    var trimmedText = text.trim();
                    if (
                        trimmedText.startsWith("<") &&
                        trimmedText.endsWith(">")
                    ) {
                        return true;
                    }
                }
                return false;
            };
            var createXMLDocument = function createXMLDocument(text) {
                var xmlParser = new DOMParser();
                var xmlDocument = xmlParser.parseFromString(text, "text/xml");
                return xmlDocument;
            };
            var isPruningNeeded = function isPruningNeeded(
                response,
                propsToRemove,
            ) {
                if (!isXML(response)) {
                    return false;
                }
                var docXML = createXMLDocument(response);
                return isXpath
                    ? getXPathElements(docXML)
                    : !!docXML.querySelector(propsToRemove);
            };
            var pruneXML = function pruneXML(text) {
                if (!isXML(text)) {
                    shouldPruneResponse = false;
                    return text;
                }
                var xmlDoc = createXMLDocument(text);
                var errorNode = xmlDoc.querySelector("parsererror");
                if (errorNode) {
                    return text;
                }
                if (
                    optionalProp !== "" &&
                    xmlDoc.querySelector(optionalProp) === null
                ) {
                    shouldPruneResponse = false;
                    return text;
                }
                var elements = isXpath
                    ? getXPathElements(xmlDoc)
                    : xmlDoc.querySelectorAll(propsToRemove);
                if (!elements.length) {
                    shouldPruneResponse = false;
                    return text;
                }
                if (shouldLogContent) {
                    var cloneXmlDoc = xmlDoc.cloneNode(true);
                    logMessage(source, "Original xml:");
                    logMessage(source, cloneXmlDoc, true, false);
                }
                if (isXpath) {
                    xPathPruning(elements);
                } else {
                    elements.forEach(function (elem) {
                        elem.remove();
                    });
                }
                if (shouldLogContent) {
                    logMessage(source, "Modified xml:");
                    logMessage(source, xmlDoc, true, false);
                }
                var serializer = new XMLSerializer();
                text = serializer.serializeToString(xmlDoc);
                return text;
            };
            var nativeOpen = window.XMLHttpRequest.prototype.open;
            var nativeSend = window.XMLHttpRequest.prototype.send;
            var xhrData;
            var openWrapper = function openWrapper(target, thisArg, args) {
                xhrData = getXhrData.apply(null, args);
                if (matchRequestProps(source, urlToMatch, xhrData)) {
                    thisArg.shouldBePruned = true;
                }
                if (thisArg.shouldBePruned) {
                    thisArg.collectedHeaders = [];
                    var setRequestHeaderWrapper =
                        function setRequestHeaderWrapper(
                            target,
                            thisArg,
                            args,
                        ) {
                            thisArg.collectedHeaders.push(args);
                            return Reflect.apply(target, thisArg, args);
                        };
                    var setRequestHeaderHandler = {
                        apply: setRequestHeaderWrapper,
                    };
                    thisArg.setRequestHeader = new Proxy(
                        thisArg.setRequestHeader,
                        setRequestHeaderHandler,
                    );
                }
                return Reflect.apply(target, thisArg, args);
            };
            var sendWrapper = function sendWrapper(target, thisArg, args) {
                var allowedResponseTypeValues = ["", "text"];
                if (
                    !thisArg.shouldBePruned ||
                    !allowedResponseTypeValues.includes(thisArg.responseType)
                ) {
                    return Reflect.apply(target, thisArg, args);
                }
                var forgedRequest = new XMLHttpRequest();
                forgedRequest.addEventListener("readystatechange", function () {
                    if (forgedRequest.readyState !== 4) {
                        return;
                    }
                    var {
                        readyState: readyState,
                        response: response,
                        responseText: responseText,
                        responseURL: responseURL,
                        responseXML: responseXML,
                        status: status,
                        statusText: statusText,
                    } = forgedRequest;
                    var content = responseText || response;
                    if (typeof content !== "string") {
                        return;
                    }
                    if (!propsToRemove) {
                        if (isXML(response)) {
                            var message = `XMLHttpRequest.open() URL: ${responseURL}\nresponse: ${response}`;
                            logMessage(source, message);
                            logMessage(
                                source,
                                createXMLDocument(response),
                                true,
                                false,
                            );
                        }
                    } else {
                        shouldPruneResponse = isPruningNeeded(
                            response,
                            propsToRemove,
                        );
                    }
                    var responseContent = shouldPruneResponse
                        ? pruneXML(response)
                        : response;
                    Object.defineProperties(thisArg, {
                        readyState: {
                            value: readyState,
                            writable: false,
                        },
                        responseURL: {
                            value: responseURL,
                            writable: false,
                        },
                        responseXML: {
                            value: responseXML,
                            writable: false,
                        },
                        status: {
                            value: status,
                            writable: false,
                        },
                        statusText: {
                            value: statusText,
                            writable: false,
                        },
                        response: {
                            value: responseContent,
                            writable: false,
                        },
                        responseText: {
                            value: responseContent,
                            writable: false,
                        },
                    });
                    setTimeout(function () {
                        var stateEvent = new Event("readystatechange");
                        thisArg.dispatchEvent(stateEvent);
                        var loadEvent = new Event("load");
                        thisArg.dispatchEvent(loadEvent);
                        var loadEndEvent = new Event("loadend");
                        thisArg.dispatchEvent(loadEndEvent);
                    }, 1);
                    hit(source);
                });
                nativeOpen.apply(forgedRequest, [xhrData.method, xhrData.url]);
                thisArg.collectedHeaders.forEach(function (header) {
                    var name = header[0];
                    var value = header[1];
                    forgedRequest.setRequestHeader(name, value);
                });
                thisArg.collectedHeaders = [];
                try {
                    nativeSend.call(forgedRequest, args);
                } catch (_unused) {
                    return Reflect.apply(target, thisArg, args);
                }
                return undefined;
            };
            var openHandler = {
                apply: openWrapper,
            };
            var sendHandler = {
                apply: sendWrapper,
            };
            XMLHttpRequest.prototype.open = new Proxy(
                XMLHttpRequest.prototype.open,
                openHandler,
            );
            XMLHttpRequest.prototype.send = new Proxy(
                XMLHttpRequest.prototype.send,
                sendHandler,
            );
            var nativeFetch = window.fetch;
            var fetchWrapper = async function fetchWrapper(
                target,
                thisArg,
                args,
            ) {
                var fetchURL =
                    args[0] instanceof Request ? args[0].url : args[0];
                if (typeof fetchURL !== "string" || fetchURL.length === 0) {
                    return Reflect.apply(target, thisArg, args);
                }
                if (urlMatchRegexp.test(fetchURL)) {
                    var response = await nativeFetch(...args);
                    var clonedResponse = response.clone();
                    var responseText = await response.text();
                    shouldPruneResponse = isPruningNeeded(
                        responseText,
                        propsToRemove,
                    );
                    if (!shouldPruneResponse) {
                        var message = `fetch URL: ${fetchURL}\nresponse text: ${responseText}`;
                        logMessage(source, message);
                        logMessage(
                            source,
                            createXMLDocument(responseText),
                            true,
                            false,
                        );
                        return clonedResponse;
                    }
                    var prunedText = pruneXML(responseText);
                    if (shouldPruneResponse) {
                        hit(source);
                        return new Response(prunedText, {
                            status: response.status,
                            statusText: response.statusText,
                            headers: response.headers,
                        });
                    }
                    return clonedResponse;
                }
                return Reflect.apply(target, thisArg, args);
            };
            var fetchHandler = {
                apply: fetchWrapper,
            };
            window.fetch = new Proxy(window.fetch, fetchHandler);
        }
        function hit(e) {
            if (e.verbose) {
                try {
                    var n = console.trace.bind(console),
                        i = "[AdGuard] ";
                    ("corelibs" === e.engine
                        ? (i += e.ruleText)
                        : (e.domainName && (i += `${e.domainName}`),
                          e.args
                              ? (i += `#%#//scriptlet('${e.name}', '${e.args.join("', '")}')`)
                              : (i += `#%#//scriptlet('${e.name}')`)),
                        n && n(i));
                } catch (e) {}
                "function" == typeof window.__debug && window.__debug(e);
            }
        }
        function logMessage(e, o) {
            var n =
                    arguments.length > 2 &&
                    void 0 !== arguments[2] &&
                    arguments[2],
                g =
                    !(arguments.length > 3 && void 0 !== arguments[3]) ||
                    arguments[3],
                { name: l, verbose: v } = e;
            if (n || v) {
                var a = console.log;
                g ? a(`${l}: ${o}`) : a(`${l}:`, o);
            }
        }
        function toRegExp(e) {
            var r = e || "",
                t = "/";
            if ("" === r) return new RegExp(".?");
            var n,
                i,
                s = r.lastIndexOf(t),
                a = r.substring(s + 1),
                g = r.substring(0, s + 1),
                u =
                    ((i = a),
                    (n = g).startsWith(t) &&
                    n.endsWith(t) &&
                    !n.endsWith("\\/") &&
                    (function (e) {
                        if (!e) return false;
                        try {
                            return (new RegExp("", e), !0);
                        } catch (e) {
                            return false;
                        }
                    })(i)
                        ? i
                        : "");
            if ((r.startsWith(t) && r.endsWith(t)) || u)
                return new RegExp((u ? g : r).slice(1, -1), u);
            var c = r
                .replace(/\\'/g, "'")
                .replace(/\\"/g, '"')
                .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return new RegExp(c);
        }
        function getXhrData(r, t, a, e, n) {
            return {
                method: r,
                url: t,
                async: a,
                user: e,
                password: n,
            };
        }
        function matchRequestProps(e, t, r) {
            if ("" === t || "*" === t) return true;
            var a,
                s = parseMatchProps(t);
            if (isValidParsedData(s)) {
                var n = getMatchPropsData(s);
                a = Object.keys(n).every(function (e) {
                    var t = n[e],
                        a = r[e];
                    return (
                        Object.prototype.hasOwnProperty.call(r, e) &&
                        "string" == typeof a &&
                        (null == t ? void 0 : t.test(a))
                    );
                });
            } else (logMessage(e, `Invalid parameter: ${t}`), (a = false));
            return a;
        }
        function getMatchPropsData(t) {
            var a = {};
            return (
                Object.keys(t).forEach(function (c) {
                    a[c] = toRegExp(t[c]);
                }),
                a
            );
        }
        function getRequestProps() {
            return [
                "url",
                "method",
                "headers",
                "body",
                "credentials",
                "cache",
                "redirect",
                "referrer",
                "referrerPolicy",
                "integrity",
                "keepalive",
                "signal",
                "mode",
            ];
        }
        function isValidParsedData(t) {
            return Object.values(t).every(function (t) {
                return isValidStrPattern(t);
            });
        }
        function parseMatchProps(e) {
            var r = {};
            return (
                e.split(" ").forEach(function (e) {
                    var n = e.indexOf(":"),
                        i = e.slice(0, n);
                    if (
                        (function (e) {
                            return getRequestProps().includes(e);
                        })(i)
                    ) {
                        var s = e.slice(n + 1);
                        r[i] = s;
                    } else r.url = e;
                }),
                r
            );
        }
        function isValidStrPattern(e) {
            var t,
                n = escapeRegExp(e);
            "/" === e[0] && "/" === e[e.length - 1] && (n = e.slice(1, -1));
            try {
                ((t = new RegExp(n)), (t = !0));
            } catch (e) {
                t = false;
            }
            return t;
        }
        function escapeRegExp(e) {
            return e.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        }
        var updatedArgs = args ? [].concat(source).concat(args) : [source];
        try {
            xmlPrune.apply(this, updatedArgs);
            if (source.uniqueId) {
                Object.defineProperty(
                    Window.prototype.toString,
                    uniqueIdentifier,
                    {
                        value: flag,
                        enumerable: false,
                        writable: false,
                        configurable: false,
                    },
                );
            }
        } catch (e) {
            console.log(e);
        }
    }
    var scriptletsMap = {
        "amazon-apstag": AmazonApstag,
        "ubo-amazon_apstag.js": AmazonApstag,
        "amazon_apstag.js": AmazonApstag,
        "didomi-loader": DidomiLoader,
        fingerprintjs2: Fingerprintjs2,
        "ubo-fingerprint2.js": Fingerprintjs2,
        "fingerprint2.js": Fingerprintjs2,
        fingerprintjs3: Fingerprintjs3,
        "ubo-fingerprint3.js": Fingerprintjs3,
        "fingerprint3.js": Fingerprintjs3,
        gemius: Gemius,
        "google-analytics-ga": GoogleAnalyticsGa,
        "ubo-google-analytics_ga.js": GoogleAnalyticsGa,
        "google-analytics_ga.js": GoogleAnalyticsGa,
        "google-analytics": GoogleAnalytics,
        "ubo-google-analytics_analytics.js": GoogleAnalytics,
        "google-analytics_analytics.js": GoogleAnalytics,
        "googletagmanager-gtm": GoogleAnalytics,
        "ubo-googletagmanager_gtm.js": GoogleAnalytics,
        "googletagmanager_gtm.js": GoogleAnalytics,
        "google-ima3": GoogleIma3,
        "ubo-google-ima.js": GoogleIma3,
        "google-ima.js": GoogleIma3,
        "googlesyndication-adsbygoogle": GoogleSyndicationAdsByGoogle,
        "ubo-googlesyndication_adsbygoogle.js": GoogleSyndicationAdsByGoogle,
        "googlesyndication_adsbygoogle.js": GoogleSyndicationAdsByGoogle,
        "googletagservices-gpt": GoogleTagServicesGpt,
        "ubo-googletagservices_gpt.js": GoogleTagServicesGpt,
        "googletagservices_gpt.js": GoogleTagServicesGpt,
        matomo: Matomo,
        "naver-wcslog": NaverWcslog,
        "pardot-1.0": Pardot,
        prebid: Prebid,
        "scorecardresearch-beacon": ScoreCardResearchBeacon,
        "ubo-scorecardresearch_beacon.js": ScoreCardResearchBeacon,
        "scorecardresearch_beacon.js": ScoreCardResearchBeacon,
        "abort-current-inline-script": abortCurrentInlineScript,
        "abort-current-script.js": abortCurrentInlineScript,
        "ubo-abort-current-script.js": abortCurrentInlineScript,
        "acs.js": abortCurrentInlineScript,
        "ubo-acs.js": abortCurrentInlineScript,
        "ubo-abort-current-script": abortCurrentInlineScript,
        "ubo-acs": abortCurrentInlineScript,
        "abort-current-inline-script.js": abortCurrentInlineScript,
        "ubo-abort-current-inline-script.js": abortCurrentInlineScript,
        "acis.js": abortCurrentInlineScript,
        "ubo-acis.js": abortCurrentInlineScript,
        "ubo-abort-current-inline-script": abortCurrentInlineScript,
        "ubo-acis": abortCurrentInlineScript,
        "abp-abort-current-inline-script": abortCurrentInlineScript,
        "abort-on-property-read": abortOnPropertyRead,
        "abort-on-property-read.js": abortOnPropertyRead,
        "ubo-abort-on-property-read.js": abortOnPropertyRead,
        "aopr.js": abortOnPropertyRead,
        "ubo-aopr.js": abortOnPropertyRead,
        "ubo-abort-on-property-read": abortOnPropertyRead,
        "ubo-aopr": abortOnPropertyRead,
        "abp-abort-on-property-read": abortOnPropertyRead,
        "abort-on-property-write": abortOnPropertyWrite,
        "abort-on-property-write.js": abortOnPropertyWrite,
        "ubo-abort-on-property-write.js": abortOnPropertyWrite,
        "aopw.js": abortOnPropertyWrite,
        "ubo-aopw.js": abortOnPropertyWrite,
        "ubo-abort-on-property-write": abortOnPropertyWrite,
        "ubo-aopw": abortOnPropertyWrite,
        "abp-abort-on-property-write": abortOnPropertyWrite,
        "abort-on-stack-trace": abortOnStackTrace,
        "abort-on-stack-trace.js": abortOnStackTrace,
        "ubo-abort-on-stack-trace.js": abortOnStackTrace,
        "aost.js": abortOnStackTrace,
        "ubo-aost.js": abortOnStackTrace,
        "ubo-abort-on-stack-trace": abortOnStackTrace,
        "ubo-aost": abortOnStackTrace,
        "abp-abort-on-stack-trace": abortOnStackTrace,
        "adjust-setInterval": adjustSetInterval,
        "nano-setInterval-booster.js": adjustSetInterval,
        "ubo-nano-setInterval-booster.js": adjustSetInterval,
        "nano-sib.js": adjustSetInterval,
        "ubo-nano-sib.js": adjustSetInterval,
        "adjust-setInterval.js": adjustSetInterval,
        "ubo-adjust-setInterval.js": adjustSetInterval,
        "ubo-nano-setInterval-booster": adjustSetInterval,
        "ubo-nano-sib": adjustSetInterval,
        "ubo-adjust-setInterval": adjustSetInterval,
        "adjust-setTimeout": adjustSetTimeout,
        "adjust-setTimeout.js": adjustSetTimeout,
        "ubo-adjust-setTimeout.js": adjustSetTimeout,
        "nano-setTimeout-booster.js": adjustSetTimeout,
        "ubo-nano-setTimeout-booster.js": adjustSetTimeout,
        "nano-stb.js": adjustSetTimeout,
        "ubo-nano-stb.js": adjustSetTimeout,
        "ubo-adjust-setTimeout": adjustSetTimeout,
        "ubo-nano-setTimeout-booster": adjustSetTimeout,
        "ubo-nano-stb": adjustSetTimeout,
        "call-nothrow": callNoThrow,
        "call-nothrow.js": callNoThrow,
        "ubo-call-nothrow.js": callNoThrow,
        "ubo-call-nothrow": callNoThrow,
        "debug-current-inline-script": debugCurrentInlineScript,
        "debug-on-property-read": debugOnPropertyRead,
        "debug-on-property-write": debugOnPropertyWrite,
        "dir-string": dirString,
        "disable-newtab-links": disableNewtabLinks,
        "disable-newtab-links.js": disableNewtabLinks,
        "ubo-disable-newtab-links.js": disableNewtabLinks,
        "ubo-disable-newtab-links": disableNewtabLinks,
        "evaldata-prune": evalDataPrune,
        "evaldata-prune.js": evalDataPrune,
        "ubo-evaldata-prune.js": evalDataPrune,
        "ubo-evaldata-prune": evalDataPrune,
        "close-window": forceWindowClose,
        "window-close-if.js": forceWindowClose,
        "ubo-window-close-if.js": forceWindowClose,
        "ubo-window-close-if": forceWindowClose,
        "close-window.js": forceWindowClose,
        "ubo-close-window.js": forceWindowClose,
        "ubo-close-window": forceWindowClose,
        "hide-in-shadow-dom": hideInShadowDom,
        "href-sanitizer": hrefSanitizer,
        "href-sanitizer.js": hrefSanitizer,
        "ubo-href-sanitizer.js": hrefSanitizer,
        "ubo-href-sanitizer": hrefSanitizer,
        "inject-css-in-shadow-dom": injectCssInShadowDom,
        "json-prune-fetch-response": jsonPruneFetchResponse,
        "json-prune-fetch-response.js": jsonPruneFetchResponse,
        "ubo-json-prune-fetch-response.js": jsonPruneFetchResponse,
        "ubo-json-prune-fetch-response": jsonPruneFetchResponse,
        "json-prune": jsonPrune,
        "json-prune.js": jsonPrune,
        "ubo-json-prune.js": jsonPrune,
        "ubo-json-prune": jsonPrune,
        "abp-json-prune": jsonPrune,
        "json-prune-xhr-response": jsonPruneXhrResponse,
        "json-prune-xhr-response.js": jsonPruneXhrResponse,
        "ubo-json-prune-xhr-response.js": jsonPruneXhrResponse,
        "ubo-json-prune-xhr-response": jsonPruneXhrResponse,
        "log-addEventListener": logAddEventListener,
        "addEventListener-logger.js": logAddEventListener,
        "ubo-addEventListener-logger.js": logAddEventListener,
        "aell.js": logAddEventListener,
        "ubo-aell.js": logAddEventListener,
        "ubo-addEventListener-logger": logAddEventListener,
        "ubo-aell": logAddEventListener,
        "log-eval": logEval,
        log: log$2,
        "abp-log": log$2,
        "log-on-stack-trace": logOnStackTrace,
        "m3u-prune": m3uPrune,
        "m3u-prune.js": m3uPrune,
        "ubo-m3u-prune.js": m3uPrune,
        "ubo-m3u-prune": m3uPrune,
        "metrika-yandex-tag": metrikaYandexTag,
        "metrika-yandex-watch": metrikaYandexWatch,
        "no-protected-audience": noProtectedAudience,
        "no-topics": noTopics,
        noeval: noeval,
        "noeval.js": noeval,
        "silent-noeval.js": noeval,
        "ubo-noeval.js": noeval,
        "ubo-silent-noeval.js": noeval,
        "ubo-noeval": noeval,
        "ubo-silent-noeval": noeval,
        nowebrtc: nowebrtc,
        "nowebrtc.js": nowebrtc,
        "ubo-nowebrtc.js": nowebrtc,
        "ubo-nowebrtc": nowebrtc,
        "prevent-addEventListener": preventAddEventListener,
        "addEventListener-defuser.js": preventAddEventListener,
        "ubo-addEventListener-defuser.js": preventAddEventListener,
        "aeld.js": preventAddEventListener,
        "ubo-aeld.js": preventAddEventListener,
        "ubo-addEventListener-defuser": preventAddEventListener,
        "ubo-aeld": preventAddEventListener,
        "abp-prevent-listener": preventAddEventListener,
        "prevent-adfly": preventAdfly,
        "prevent-bab": preventBab,
        "ubo-nobab": preventBab,
        nobab: preventBab,
        "bab-defuser": preventBab,
        "nobab.js": preventBab,
        "ubo-nobab.js": preventBab,
        "bab-defuser.js": preventBab,
        "prevent-canvas": preventCanvas,
        "prevent-canvas.js": preventCanvas,
        "ubo-prevent-canvas.js": preventCanvas,
        "ubo-prevent-canvas": preventCanvas,
        "prevent-element-src-loading": preventElementSrcLoading,
        "prevent-eval-if": preventEvalIf,
        "noeval-if.js": preventEvalIf,
        "ubo-noeval-if.js": preventEvalIf,
        "ubo-noeval-if": preventEvalIf,
        "prevent-fab-3.2.0": preventFab,
        "nofab.js": preventFab,
        "ubo-nofab.js": preventFab,
        "fuckadblock.js-3.2.0": preventFab,
        "ubo-fuckadblock.js-3.2.0": preventFab,
        "ubo-nofab": preventFab,
        "prevent-fetch": preventFetch,
        "prevent-fetch.js": preventFetch,
        "ubo-prevent-fetch.js": preventFetch,
        "ubo-prevent-fetch": preventFetch,
        "no-fetch-if.js": preventFetch,
        "ubo-no-fetch-if.js": preventFetch,
        "ubo-no-fetch-if": preventFetch,
        "prevent-popads-net": preventPopadsNet,
        "popads.net.js": preventPopadsNet,
        "ubo-popads.net.js": preventPopadsNet,
        "ubo-popads.net": preventPopadsNet,
        "prevent-refresh": preventRefresh,
        "prevent-refresh.js": preventRefresh,
        "refresh-defuser.js": preventRefresh,
        "refresh-defuser": preventRefresh,
        "ubo-prevent-refresh.js": preventRefresh,
        "ubo-prevent-refresh": preventRefresh,
        "ubo-refresh-defuser.js": preventRefresh,
        "ubo-refresh-defuser": preventRefresh,
        "prevent-requestAnimationFrame": preventRequestAnimationFrame,
        "no-requestAnimationFrame-if.js": preventRequestAnimationFrame,
        "ubo-no-requestAnimationFrame-if.js": preventRequestAnimationFrame,
        "norafif.js": preventRequestAnimationFrame,
        "ubo-norafif.js": preventRequestAnimationFrame,
        "ubo-no-requestAnimationFrame-if": preventRequestAnimationFrame,
        "ubo-norafif": preventRequestAnimationFrame,
        "prevent-setInterval": preventSetInterval,
        "no-setInterval-if.js": preventSetInterval,
        "ubo-no-setInterval-if.js": preventSetInterval,
        "setInterval-defuser.js": preventSetInterval,
        "ubo-setInterval-defuser.js": preventSetInterval,
        "nosiif.js": preventSetInterval,
        "ubo-nosiif.js": preventSetInterval,
        "sid.js": preventSetInterval,
        "ubo-sid.js": preventSetInterval,
        "ubo-no-setInterval-if": preventSetInterval,
        "ubo-setInterval-defuser": preventSetInterval,
        "ubo-nosiif": preventSetInterval,
        "ubo-sid": preventSetInterval,
        "prevent-setTimeout": preventSetTimeout,
        "no-setTimeout-if.js": preventSetTimeout,
        "ubo-no-setTimeout-if.js": preventSetTimeout,
        "nostif.js": preventSetTimeout,
        "ubo-nostif.js": preventSetTimeout,
        "ubo-no-setTimeout-if": preventSetTimeout,
        "ubo-nostif": preventSetTimeout,
        "setTimeout-defuser.js": preventSetTimeout,
        "ubo-setTimeout-defuser.js": preventSetTimeout,
        "ubo-setTimeout-defuser": preventSetTimeout,
        "std.js": preventSetTimeout,
        "ubo-std.js": preventSetTimeout,
        "ubo-std": preventSetTimeout,
        "prevent-window-open": preventWindowOpen,
        "window.open-defuser.js": preventWindowOpen,
        "ubo-window.open-defuser.js": preventWindowOpen,
        "ubo-window.open-defuser": preventWindowOpen,
        "nowoif.js": preventWindowOpen,
        "ubo-nowoif.js": preventWindowOpen,
        "ubo-nowoif": preventWindowOpen,
        "no-window-open-if.js": preventWindowOpen,
        "ubo-no-window-open-if.js": preventWindowOpen,
        "ubo-no-window-open-if": preventWindowOpen,
        "prevent-xhr": preventXHR,
        "no-xhr-if.js": preventXHR,
        "ubo-no-xhr-if.js": preventXHR,
        "ubo-no-xhr-if": preventXHR,
        "remove-attr": removeAttr,
        "remove-attr.js": removeAttr,
        "ubo-remove-attr.js": removeAttr,
        "ra.js": removeAttr,
        "ubo-ra.js": removeAttr,
        "ubo-remove-attr": removeAttr,
        "ubo-ra": removeAttr,
        "remove-class": removeClass,
        "remove-class.js": removeClass,
        "ubo-remove-class.js": removeClass,
        "rc.js": removeClass,
        "ubo-rc.js": removeClass,
        "ubo-remove-class": removeClass,
        "ubo-rc": removeClass,
        "remove-cookie": removeCookie,
        "cookie-remover.js": removeCookie,
        "ubo-cookie-remover.js": removeCookie,
        "ubo-cookie-remover": removeCookie,
        "remove-cookie.js": removeCookie,
        "ubo-remove-cookie.js": removeCookie,
        "ubo-remove-cookie": removeCookie,
        "abp-cookie-remover": removeCookie,
        "remove-in-shadow-dom": removeInShadowDom,
        "remove-node-text": removeNodeText,
        "remove-node-text.js": removeNodeText,
        "ubo-remove-node-text.js": removeNodeText,
        "rmnt.js": removeNodeText,
        "ubo-rmnt.js": removeNodeText,
        "ubo-remove-node-text": removeNodeText,
        "ubo-rmnt": removeNodeText,
        "set-attr": setAttr,
        "set-attr.js": setAttr,
        "ubo-set-attr.js": setAttr,
        "ubo-set-attr": setAttr,
        "set-constant": setConstant,
        "set-constant.js": setConstant,
        "ubo-set-constant.js": setConstant,
        "set.js": setConstant,
        "ubo-set.js": setConstant,
        "ubo-set-constant": setConstant,
        "ubo-set": setConstant,
        "abp-override-property-read": setConstant,
        "set-cookie": setCookie,
        "set-cookie.js": setCookie,
        "ubo-set-cookie.js": setCookie,
        "ubo-set-cookie": setCookie,
        "set-cookie-reload": setCookieReload,
        "set-cookie-reload.js": setCookieReload,
        "ubo-set-cookie-reload.js": setCookieReload,
        "ubo-set-cookie-reload": setCookieReload,
        "set-local-storage-item": setLocalStorageItem,
        "set-local-storage-item.js": setLocalStorageItem,
        "ubo-set-local-storage-item.js": setLocalStorageItem,
        "ubo-set-local-storage-item": setLocalStorageItem,
        "set-popads-dummy": setPopadsDummy,
        "popads-dummy.js": setPopadsDummy,
        "ubo-popads-dummy.js": setPopadsDummy,
        "ubo-popads-dummy": setPopadsDummy,
        "set-session-storage-item": setSessionStorageItem,
        "set-session-storage-item.js": setSessionStorageItem,
        "ubo-set-session-storage-item.js": setSessionStorageItem,
        "ubo-set-session-storage-item": setSessionStorageItem,
        "spoof-css": spoofCSS,
        "spoof-css.js": spoofCSS,
        "ubo-spoof-css.js": spoofCSS,
        "ubo-spoof-css": spoofCSS,
        "trusted-click-element": trustedClickElement,
        "trusted-create-element": trustedCreateElement,
        "trusted-dispatch-event": trustedDispatchEvent,
        "trusted-prune-inbound-object": trustedPruneInboundObject,
        "trusted-replace-argument": trustedReplaceArgument,
        "trusted-replace-fetch-response": trustedReplaceFetchResponse,
        "trusted-replace-node-text": trustedReplaceNodeText,
        "trusted-replace-outbound-text": trustedReplaceOutboundText,
        "trusted-replace-xhr-response": trustedReplaceXhrResponse,
        "trusted-set-attr": trustedSetAttr,
        "trusted-set-constant": trustedSetConstant,
        "trusted-set-cookie": trustedSetCookie,
        "trusted-set-cookie-reload": trustedSetCookieReload,
        "trusted-set-local-storage-item": trustedSetLocalStorageItem,
        "trusted-set-session-storage-item": trustedSetSessionStorageItem,
        "trusted-suppress-native-method": trustedSuppressNativeMethod,
        "xml-prune": xmlPrune,
        "xml-prune.js": xmlPrune,
        "ubo-xml-prune.js": xmlPrune,
        "ubo-xml-prune": xmlPrune,
    };
    var getScriptletFunction = function getScriptletFunction(name) {
        return scriptletsMap[name];
    };
    function passSourceAndProps(source, code) {
        var redirect =
            arguments.length > 2 && arguments[2] !== undefined
                ? arguments[2]
                : false;
        var sourceString = JSON.stringify(source);
        var argsString = source.args
            ? `[${source.args.map(function (arg) {
                  return JSON.stringify(arg);
              })}]`
            : undefined;
        var params = argsString
            ? `${sourceString}, ${argsString}`
            : sourceString;
        if (redirect) {
            return `(function(source, args){\n${code}\n})(${params});`;
        }
        return `(${code})(${params});`;
    }
    function wrapInNonameFunc(code) {
        return `function(source, args){\n${code}\n}`;
    }
    function getScriptletCode(source) {
        var scriptletFunction = getScriptletFunction(source.name);
        if (typeof scriptletFunction !== "function") {
            throw new Error(
                `Error: cannot invoke scriptlet with name: '${source.name}'`,
            );
        }
        var scriptletFunctionString = scriptletFunction.toString();
        var result =
            source.engine === "corelibs" || source.engine === "test"
                ? wrapInNonameFunc(scriptletFunctionString)
                : passSourceAndProps(source, scriptletFunctionString);
        return result;
    }
    var scriptlets = {
        invoke: getScriptletCode,
        getScriptletFunction: getScriptletFunction,
    };

    /*
     * SafariExtension v4.0.4 (build date: Fri, 15 Aug 2025 06:06:17 GMT)
     * (c) 2025 Adguard Software Ltd.
     * Released under the GPL-3.0 license
     * https://github.com/AdguardTeam/SafariConverterLib/tree/master/Extension
     */

    /* eslint-disable no-console */
    /* eslint-disable class-methods-use-this */
    /* eslint-disable max-classes-per-file */
    /**
     * @file Defines the logger interface and its default implementation.
     */
    /**
     * Logging level.
     */
    var LoggingLevel;
    (function (LoggingLevel) {
        LoggingLevel[(LoggingLevel["Debug"] = 2)] = "Debug";
        LoggingLevel[(LoggingLevel["Info"] = 1)] = "Info";
        LoggingLevel[(LoggingLevel["Error"] = 0)] = "Error";
    })(LoggingLevel || (LoggingLevel = {}));
    const getTimestamp = () => `[${new Date().toISOString()}]`;
    /**
     * Console logger implementation.
     */
    class ConsoleLogger {
        /**
         * Creates a new console logger.
         *
         * @param prefix Prefix to add to the log messages.
         * @param level Logging level.
         */
        constructor(prefix, level) {
            _defineProperty2(this, "prefix", "[Safari Extension]");
            _defineProperty2(this, "loggingLevel", LoggingLevel.Info);
            this.prefix = prefix;
            this.loggingLevel = level;
        }
        get level() {
            return this.loggingLevel;
        }
        set level(level) {
            this.loggingLevel = level;
        }
        debug() {
            if (this.loggingLevel >= LoggingLevel.Debug) {
                for (
                    var _len3 = arguments.length,
                        args = new Array(_len3),
                        _key3 = 0;
                    _key3 < _len3;
                    _key3++
                ) {
                    args[_key3] = arguments[_key3];
                }
                console.debug(getTimestamp(), this.prefix, ...args);
            }
        }
        info() {
            if (this.loggingLevel >= LoggingLevel.Info) {
                for (
                    var _len4 = arguments.length,
                        args = new Array(_len4),
                        _key4 = 0;
                    _key4 < _len4;
                    _key4++
                ) {
                    args[_key4] = arguments[_key4];
                }
                console.info(getTimestamp(), this.prefix, ...args);
            }
        }
        error() {
            if (this.loggingLevel >= LoggingLevel.Error) {
                for (
                    var _len5 = arguments.length,
                        args = new Array(_len5),
                        _key5 = 0;
                    _key5 < _len5;
                    _key5++
                ) {
                    args[_key5] = arguments[_key5];
                }
                console.error(getTimestamp(), this.prefix, ...args);
            }
        }
    }
    /**
     * Logger that does not print anything.
     */
    class NullLogger {
        constructor() {
            _defineProperty2(this, "level", LoggingLevel.Debug);
        }
        debug() {
            // Do nothing.
        }
        info() {
            // Do nothing.
        }
        error() {
            // Do nothing.
        }
    }
    /**
     * Default logger. Can be redefined by the library user.
     */
    let internalLogger = new NullLogger();
    /**
     * Proxy logger that delegates all calls to the internal logger.
     * This internal logger can be redefined by the library user
     * via `setLogger`.
     */
    class ProxyLogger {
        get level() {
            return internalLogger.level;
        }
        set level(level) {
            internalLogger.level = level;
        }
        debug() {
            internalLogger.debug(...arguments);
        }
        info() {
            internalLogger.info(...arguments);
        }
        error() {
            internalLogger.error(...arguments);
        }
    }
    /**
     * Sets the logger to use.
     *
     * @param logger to use.
     */
    const setLogger = (logger) => {
        internalLogger = logger;
    };
    /**
     * Logger instance that will be used inside the library (and can be actually
     * used outside the library too). It delegates all calls to the internal logger
     * that can be redefined via `setLogger`.
     */
    const log$1 = new ProxyLogger();
    const version = "4.0.4";

    /**
     * @file Contains common constants and helper functions.
     */
    /**
     * Name of the engine used to run scriptlets.
     */
    const SCRIPTLET_ENGINE_NAME = "safari-extension";
    /**
     * Makes sure that we're dealing with CSS rules (selector + style)
     *
     * @param css Array of CSS selectors (for hiding elements) or full CSS rules.
     * @returns Array of CSS rules.
     */
    const toCSSRules = (css) => {
        return css
            .map((s) => s.trim())
            .filter((s) => s.length > 0)
            .map((s) => {
                return s.at(-1) !== "}" ? `${s} {display:none!important;}` : s;
            });
    };
    /* eslint-enable class-methods-use-this */

    /**
     * @file Exports `BackgroundScript` object that it supposed to be used by
     * web extension's background script.
     */
    /**
     * `BackgroundScript` is a class that is used by web extension's background
     * script to apply the configuration to the web page. It uses
     * `browser.scripting` API to inject scripts and CSS into the web page.
     *
     * It's important that for correct work this class relies on the presence of
     * `adguard.contentScript` object in the `ISOLATED` world that implements
     * `ContentScript` interface.
     */
    class BackgroundScript {
        /**
         * Creates an instance of the `BackgroundScript` object.
         *
         * The constructor accepts a map of registered functions. The idea is that
         * we would like JS rules to work in the same way as scriptlets, i.e. use
         * `browser.scripting.executeScript` with `world: 'MAIN'` In order to do
         * that we need to deal with JS functions. Unfortunately, due to security
         * limitations we cannot create `Function` objects from script text inside
         * the extension. To overcome that we can prepare a map of script texts and
         * functions. This map should be constructed in compile time and then
         * passed to the constructor. Whenever the script rule is applied, we will
         * first check if there's a registered `Function` object for the script
         * text and if there is, it will be used to execute the script. Otherwise,
         * we will attempt to execute it as a string (but the website CSP may
         * prevent that).
         *
         * @param registeredScripts Map of registered script functions.
         */
        constructor() {
            let registeredScripts =
                arguments.length > 0 && arguments[0] !== undefined
                    ? arguments[0]
                    : new Map();
            /**
             * Map of registered script functions.
             */
            _defineProperty2(this, "registeredScripts", void 0);
            this.registeredScripts = registeredScripts;
            // Make sure that the default registered script is always added to the
            // map. This is a default registered script that is used on
            // testcases.agrd.dev for CSP tests.
            this.registeredScripts.set(
                'console.log(Date.now(), "default registered script")',
                () => {
                    // eslint-disable-next-line no-console
                    console.log(Date.now(), "default registered script");
                },
            );
        }
        /**
         * Applies the configuration to the given tab and frame.
         *
         * @param tabId ID of the tab to apply the configuration to.
         * @param frameId ID of the frame to apply the configuration to.
         * @param configuration Configuration to apply.
         * @returns Promise that resolves when the configuration is applied.
         */
        async applyConfiguration(tabId, frameId, configuration) {
            log$1.debug(
                "Applying configuration to tab",
                tabId,
                "frame",
                frameId,
                "configuration",
                configuration,
            );
            await Promise.all([
                BackgroundScript.insertCss(tabId, frameId, configuration.css),
                BackgroundScript.insertExtendedCss(
                    tabId,
                    frameId,
                    configuration.extendedCss,
                ),
                BackgroundScript.runScriptlets(
                    tabId,
                    frameId,
                    configuration.scriptlets,
                ),
                BackgroundScript.runScripts(
                    tabId,
                    frameId,
                    configuration.js,
                    this.registeredScripts,
                ),
            ]);
            log$1.debug(
                "Finished applying configuration to tab",
                tabId,
                "frame",
                frameId,
            );
        }
        /**
         * Wrapper over `browser.scripting.scriptInjection` that logs errors.
         *
         * @param scriptInjection Script injection to execute.
         */
        static async executeScript(scriptInjection) {
            const results =
                await browser.scripting.executeScript(scriptInjection);
            if (results.length === 0) {
                log$1.error(
                    "Failed to execute script in target",
                    scriptInjection.target,
                );
                return;
            }
            const result = results[0];
            if (result.error) {
                log$1.error(
                    "Failed to execute script in target",
                    scriptInjection.target,
                    "error",
                    result.error,
                );
            }
        }
        /**
         * Runs scripts in the given tab and frame.
         *
         * @param tabId ID of the tab to run the scripts in.
         * @param frameId ID of the frame to run the scripts in.
         * @param scripts Scripts to run.
         * @param registeredScripts Map of registered script functions.
         * @returns Promise that resolves when the scripts are run.
         */
        static async runScripts(tabId, frameId, scripts, registeredScripts) {
            if (scripts.length === 0) {
                log$1.debug(
                    "No scripts to run in tab",
                    tabId,
                    "frame",
                    frameId,
                );
                return;
            }
            // Scan scripts for registered functions.
            const scriptFunctions = [];
            const scriptTexts = [];
            for (const script of scripts) {
                const scriptFunction = registeredScripts.get(script);
                if (scriptFunction) {
                    scriptFunctions.push(scriptFunction);
                } else {
                    scriptTexts.push(script);
                }
            }
            log$1.debug(
                "Found",
                scriptFunctions.length,
                "registered functions and",
                scriptTexts.length,
                "scripts to run in tab",
                tabId,
                "frame",
                frameId,
            );
            await Promise.all([
                BackgroundScript.runScriptFunctions(
                    tabId,
                    frameId,
                    scriptFunctions,
                ),
                BackgroundScript.runScriptTexts(tabId, frameId, scriptTexts),
            ]);
            log$1.debug(
                "Finished running scripts in tab",
                tabId,
                "frame",
                frameId,
            );
        }
        /**
         * Runs script functions in the given tab and frame.
         *
         * @param tabId ID of the tab to run the scripts in.
         * @param frameId ID of the frame to run the scripts in.
         * @param scriptFunctions Scripts to run.
         * @returns Promise that resolves when the scripts are run.
         */
        static async runScriptFunctions(tabId, frameId, scriptFunctions) {
            if (scriptFunctions.length === 0) {
                log$1.debug(
                    "No script functions to run in tab",
                    tabId,
                    "frame",
                    frameId,
                );
                return;
            }
            log$1.debug(
                "Running script functions in tab",
                tabId,
                "frame",
                frameId,
                "script functions",
                scriptFunctions,
            );
            const promises = scriptFunctions.map((scriptFunction) => {
                return BackgroundScript.runScriptFunction(
                    tabId,
                    frameId,
                    scriptFunction,
                );
            });
            await Promise.all(promises);
            log$1.debug(
                "Finished running script functions in tab",
                tabId,
                "frame",
                frameId,
            );
        }
        /**
         * Runs a script in the given tab and frame.
         *
         * @param tabId ID of the tab to run the script in.
         * @param frameId ID of the frame to run the script in.
         * @param scriptFunction Script to run.
         * @returns Promise that resolves when the script is run.
         */
        static async runScriptFunction(tabId, frameId, scriptFunction) {
            log$1.debug(
                "Running script function in tab",
                tabId,
                "frame",
                frameId,
                "script function",
                scriptFunction,
            );
            await BackgroundScript.executeScript({
                target: {
                    tabId,
                    frameIds: [frameId],
                },
                func: scriptFunction,
                world: "MAIN",
                injectImmediately: true,
            });
            log$1.debug(
                "Finished running script function in tab",
                tabId,
                "frame",
                frameId,
            );
        }
        /**
         * Runs script texts in the given tab and frame.
         *
         * @param tabId ID of the tab to run the script texts in.
         * @param frameId ID of the frame to run the script texts in.
         * @param scriptTexts Script texts to run.
         * @returns Promise that resolves when the script texts are run.
         */
        static async runScriptTexts(tabId, frameId, scriptTexts) {
            if (scriptTexts.length === 0) {
                log$1.debug(
                    "No script texts to run in tab",
                    tabId,
                    "frame",
                    frameId,
                );
                return;
            }
            log$1.debug(
                "Running script texts in tab",
                tabId,
                "frame",
                frameId,
                "script texts",
                scriptTexts,
            );
            await BackgroundScript.executeScript({
                target: {
                    tabId,
                    frameIds: [frameId],
                },
                func: function () {
                    let scripts =
                        arguments.length > 0 && arguments[0] !== undefined
                            ? arguments[0]
                            : [];
                    try {
                        adguard.contentScript.runScripts(scripts);
                    } catch (e) {
                        // eslint-disable-next-line no-console
                        console.error(
                            "Failed to run scripts, make sure adguard.contentScript is available",
                            e,
                        );
                    }
                },
                args: [scriptTexts],
                world: "ISOLATED",
                injectImmediately: true,
            });
            log$1.debug(
                "Finished running script texts in tab",
                tabId,
                "frame",
                frameId,
            );
        }
        /**
         * Inserts extended CSS into the given tab and frame.
         *
         * @param tabId ID of the tab to insert extended CSS into.
         * @param frameId ID of the frame to insert extended CSS into.
         * @param extendedCss Extended CSS to insert.
         * @returns Promise that resolves when the extended CSS is inserted.
         */
        static async insertExtendedCss(tabId, frameId, extendedCss) {
            if (extendedCss.length === 0) {
                log$1.debug(
                    "No extended CSS to insert into tab",
                    tabId,
                    "frame",
                    frameId,
                );
                return;
            }
            await BackgroundScript.executeScript({
                target: {
                    tabId,
                    frameIds: [frameId],
                },
                func: function () {
                    let extCss =
                        arguments.length > 0 && arguments[0] !== undefined
                            ? arguments[0]
                            : [];
                    try {
                        adguard.contentScript.insertExtendedCss(extCss);
                    } catch (e) {
                        // eslint-disable-next-line no-console
                        console.error(
                            "Failed to insert extended CSS, make sure adguard.contentScript is available",
                            e,
                        );
                    }
                },
                args: [extendedCss],
                world: "ISOLATED",
                injectImmediately: true,
            });
        }
        /**
         * Inserts CSS into the given tab and frame.
         *
         * @param tabId ID of the tab to insert CSS into.
         * @param frameId ID of the frame to insert CSS into.
         * @param css CSS to insert.
         * @returns Promise that resolves when the CSS is inserted.
         */
        static async insertCss(tabId, frameId, css) {
            if (css.length === 0) {
                log$1.debug(
                    "No CSS to insert into tab",
                    tabId,
                    "frame",
                    frameId,
                );
                return;
            }
            log$1.debug(
                "Inserting CSS into tab",
                tabId,
                "frame",
                frameId,
                "css",
                css,
            );
            const cssRules = toCSSRules(css);
            const cssStyle = cssRules.join("\n");
            await browser.scripting.insertCSS({
                target: {
                    tabId,
                    frameIds: [frameId],
                },
                origin: "USER",
                css: cssStyle,
            });
            log$1.debug("CSS inserted into tab", tabId, "frame", frameId);
        }
        /**
         * Runs scriptlets in the given tab and frame.
         *
         * @param tabId ID of the tab to run the scriptlets in.
         * @param frameId ID of the frame to run the scriptlets in.
         * @param scriptlets Scriptlets to run.
         * @returns Promise that resolves when the scriptlets are run.
         */
        static async runScriptlets(tabId, frameId, scriptlets) {
            if (scriptlets.length === 0) {
                log$1.debug(
                    "No scriptlets to run into tab",
                    tabId,
                    "frame",
                    frameId,
                );
                return;
            }
            log$1.debug(
                "Running scriptlets in the tab",
                tabId,
                "frame",
                frameId,
                "scriptlets",
                scriptlets,
            );
            const promises = scriptlets.map((scriptlet) =>
                BackgroundScript.runScriptlet(tabId, frameId, scriptlet),
            );
            await Promise.all(promises);
            log$1.debug(
                "Finished running scriptlets in the tab",
                tabId,
                "frame",
                frameId,
            );
        }
        /**
         * Runs a scriptlet in the given tab and frame.
         *
         * @param tabId ID of the tab to run the scriptlet in.
         * @param frameId ID of the frame to run the scriptlet in.
         * @param scriptlet Scriptlet to run.
         * @returns Promise that resolves when the scriptlet is run.
         */
        static async runScriptlet(tabId, frameId, scriptlet) {
            log$1.debug(
                "Running scriptlet",
                scriptlet.name,
                "in the tab",
                tabId,
                "frame",
                frameId,
            );
            const scriptletFunction = scriptlets.getScriptletFunction(
                scriptlet.name,
            );
            if (!scriptletFunction) {
                log$1.error("Scriptlet function not found", scriptlet.name);
                return;
            }
            // Use verbose logging in scriptlets when debug-level logging is
            // enabled.
            const verbose = log$1.level === LoggingLevel.Debug;
            const scriptletSource = {
                engine: SCRIPTLET_ENGINE_NAME,
                name: scriptlet.name,
                args: scriptlet.args,
                version: version,
                verbose,
            };
            const args = [];
            args.push(scriptletSource);
            args.push(scriptlet.args);
            await BackgroundScript.executeScript({
                target: {
                    tabId,
                    frameIds: [frameId],
                },
                func: scriptletFunction,
                args,
                world: "MAIN",
                injectImmediately: true,
            });
            log$1.debug(
                "Finished running scriptlet",
                scriptlet.name,
                "in the tab",
                tabId,
                "frame",
                frameId,
            );
        }
    }

    /**
     * @file Defines message interface.
     */
    /**
     * Represents a type of message.
     */
    var MessageType;
    (function (MessageType) {
        MessageType["InitContentScript"] = "InitContentScript";
    })(MessageType || (MessageType = {}));

    /**
     * @file Background script for the WebExtension.
     *
     * This script handles messages from other parts of the extension,
     * communicates with a native messaging host, and uses a cache mechanism
     * to serve responses quickly while updating them in the background.
     */
    // Initialize the logger to be used by the `@adguard/safari-extension`.
    // Change logging level to Debug if you need to see more details.
    const log = new ConsoleLogger("[wBlock Scripts]", LoggingLevel.Info);
    setLogger(log);
    /**
     * Global variable to track the engine timestamp.
     * This value is used to invalidate the cache when the underlying engine
     * is updated.
     */
    let engineTimestamp = 0;
    /**
     * BackgroundScript is used to apply filtering configuration to web pages.
     * Note, that it relies on the content script to be injected into the page
     * and available in the ISOLATED world via `adguard.contentScript` object.
     */
    const backgroundScript = new BackgroundScript();
    /**
     * Cache to store the rules for a given URL. The key is a URL (string) and
     * the value is a Configuration. Caching content script configurations allows us
     * to respond to content script requests quickly while also updating the cache
     * in the background.
     */
    const cache = new Map();
    /**
     * Returns a cache key for the given URL and top-level URL.
     *
     * @param url - Page URL for which the rules are requested.
     * @param topUrl - Top-level page URL (to distinguish between frames)
     * @returns The cache key.
     */
    const cacheKey = (url, topUrl) => `${url}#${topUrl ?? ""}`;
    /**
     * Makes a native messaging request to obtain rules for the given message.
     * Also handles cache invalidation if the engine timestamp has changed.
     *
     * @param request - Original request from the content script.
     * @param url - Page URL for which the rules are requested.
     * @param topUrl - Top-level page URL (to distinguish between frames)
     * @returns The response message from the native host.
     */
    const requestConfiguration = async (request, url, topUrl) => {
        // Prepare the request payload.
        request.payload = {
            url,
            topUrl,
        };
        // Send the request to the native messaging host and wait for the response.
        const response = await browser.runtime.sendNativeMessage(
            "application.id",
            request,
        );
        const message = response;
        if (!message || !message.payload) {
            // No configuration received for some reason.
            return null;
        }
        // Extract the configuration from the response payload.
        const configuration = message.payload;
        // If the engine timestamp has been updated, clear the cache and update
        // the timestamp.
        if (configuration.engineTimestamp !== engineTimestamp) {
            cache.clear();
            engineTimestamp = configuration.engineTimestamp;
        }
        // Save the new message in the cache for the given URL.
        const key = cacheKey(url, topUrl);
        cache.set(key, configuration);
        return configuration;
    };
    /**
     * Tries to get rules from the cache. If not found, requests them from the
     * native host.
     *
     * @param message - The original message from the content script.
     * @param url - Page URL for which the rules are requested.
     * @param topUrl - Top-level page URL (to distinguish between frames)
     * @returns The response message from the native host.
     */
    const getConfiguration = async (message, url, topUrl) => {
        const key = cacheKey(url, topUrl);
        // If there is already a cached response for this URL:
        if (cache.has(key)) {
            // Fire off a new request to update the cache in the background.
            requestConfiguration(message, url, topUrl);
            // Retrieve the cached response.
            const cachedConfiguration = cache.get(key);
            // Return the cached message immediately.
            if (cachedConfiguration) {
                return cachedConfiguration;
            }
        }
        // Await the native request to get a fresh response.
        const configuration = await requestConfiguration(message, url, topUrl);
        // Return the new response.
        return configuration;
    };
    /**
     * Message listener that intercepts messages sent to the background script.
     *
     * @param request Message from the content script.
     * @param sender The sender of the message.
     * @returns The response message from the native host.
     */
    const handleMessages = async (request, sender) => {
        var _sender$tab, _sender$tab2;
        // Cast the incoming request to `Message`.
        const message = request;
        if (message && message.action === "getUserScripts") {
            const userScriptRequest = {
                action: "getUserScripts",
                url: message.url,
                requestId: "userscripts-" + Date.now(),
            };

            try {
                const response = await browser.runtime.sendNativeMessage(
                    "application.id",
                    userScriptRequest,
                );
                const scripts =
                    response && response.userScripts
                        ? response.userScripts
                        : [];
                return { userScripts: scripts };
            } catch (error) {
                console.error("[wBlock] Failed to get userscripts:", error);
                return { userScripts: [] };
            }
        }
        const tabId =
            ((_sender$tab = sender.tab) === null || _sender$tab === void 0
                ? void 0
                : _sender$tab.id) ?? 0;
        const frameId = sender.frameId ?? 0;
        let blankFrame = false;
        let url = sender.url || "";
        const topUrl =
            frameId === 0
                ? undefined
                : (_sender$tab2 = sender.tab) === null ||
                    _sender$tab2 === void 0
                  ? void 0
                  : _sender$tab2.url;
        if (!url.startsWith("http") && topUrl) {
            // Handle the case of non-HTTP iframes, i.e. frames created by JS.
            // For instance, frames can be created as 'about:blank' or 'data:text/html'
            url = topUrl;
            blankFrame = true;
        }
        const configuration = await getConfiguration(message, url, topUrl);
        if (!configuration) {
            log.error("No configuration received for ", url);
            return {};
        }
        // Prepare the response.
        const response = {
            type: MessageType.InitContentScript,
        };
        // In the current Safari version we cannot apply rules to blank frames from
        // the background: https://bugs.webkit.org/show_bug.cgi?id=296702
        //
        // In this case we fallback to using the content script to apply rules.
        // The downside here is that the content script cannot override website's
        // CSPs.
        if (!blankFrame) {
            await backgroundScript.applyConfiguration(
                tabId,
                frameId,
                configuration,
            );
        } else {
            // Pass the configuration to the content script.
            response.payload = configuration;
        }
        return response;
    };
    // Start handling messages from content scripts.
    browser.runtime.onMessage.addListener(handleMessages);
})(browser);
