"use strict";
var main = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // Scriptlets/src/scriptlets/google-analytics-ga.ts
  var google_analytics_ga_exports = {};
  __export(google_analytics_ga_exports, {
    GoogleAnalyticsGa: () => GoogleAnalyticsGa,
    GoogleAnalyticsGaNames: () => GoogleAnalyticsGaNames
  });

  // Scriptlets/src/helpers/log-message.ts
  var logMessage = (source, message, forced = false, convertMessageToString = true) => {
    const {
      name,
      verbose
    } = source;
    if (!forced && !verbose) {
      return;
    }
    const nativeConsole = console.log;
    if (!convertMessageToString) {
      nativeConsole(`${name}:`, message);
      return;
    }
    nativeConsole(`${name}: ${message}`);
  };

  // Scriptlets/src/helpers/hit.ts
  var hit = (source) => {
    const ADGUARD_PREFIX = "[AdGuard]";
    if (!source.verbose) {
      return;
    }
    try {
      const trace = console.trace.bind(console);
      let label = `${ADGUARD_PREFIX} `;
      if (source.engine === "corelibs") {
        label += source.ruleText;
      } else {
        if (source.domainName) {
          label += `${source.domainName}`;
        }
        if (source.args) {
          label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
        } else {
          label += `#%#//scriptlet('${source.name}')`;
        }
      }
      if (trace) {
        trace(label);
      }
    } catch (e) {
    }
    if (typeof window.__debug === "function") {
      window.__debug(source);
    }
  };

  // Scriptlets/src/helpers/noop-utils.ts
  var noopFunc = () => {
  };

  // Scriptlets/src/redirects/google-analytics-ga.js
  function GoogleAnalyticsGa(source) {
    function Gaq() {
    }
    Gaq.prototype.Na = noopFunc;
    Gaq.prototype.O = noopFunc;
    Gaq.prototype.Sa = noopFunc;
    Gaq.prototype.Ta = noopFunc;
    Gaq.prototype.Va = noopFunc;
    Gaq.prototype._createAsyncTracker = noopFunc;
    Gaq.prototype._getAsyncTracker = noopFunc;
    Gaq.prototype._getPlugin = noopFunc;
    Gaq.prototype.push = (data) => {
      if (typeof data === "function") {
        data();
        return;
      }
      if (Array.isArray(data) === false) {
        return;
      }
      if (typeof data[0] === "string" && /(^|\.)_link$/.test(data[0]) && typeof data[1] === "string") {
        window.location.assign(data[1]);
      }
      if (data[0] === "_set" && data[1] === "hitCallback" && typeof data[2] === "function") {
        data[2]();
      }
    };
    const gaq = new Gaq();
    const asyncTrackers = window._gaq || [];
    if (Array.isArray(asyncTrackers)) {
      while (asyncTrackers[0]) {
        gaq.push(asyncTrackers.shift());
      }
    }
    window._gaq = gaq.qf = gaq;
    function Gat() {
    }
    const api = [
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
      "_visitCode"
    ];
    const tracker = api.reduce((res, funcName) => {
      res[funcName] = noopFunc;
      return res;
    }, {});
    tracker._getLinkerUrl = (a) => a;
    tracker._link = (url) => {
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
    Gat.prototype._getTracker = () => tracker;
    Gat.prototype._getTrackerByName = () => tracker;
    Gat.prototype._getTrackers = noopFunc;
    Gat.prototype.aa = noopFunc;
    Gat.prototype.ab = noopFunc;
    Gat.prototype.hb = noopFunc;
    Gat.prototype.la = noopFunc;
    Gat.prototype.oa = noopFunc;
    Gat.prototype.pa = noopFunc;
    Gat.prototype.u = noopFunc;
    const gat = new Gat();
    window._gat = gat;
    hit(source);
  }
  var GoogleAnalyticsGaNames = [
    "google-analytics-ga",
    "ubo-google-analytics_ga.js",
    "google-analytics_ga.js"
  ];
  GoogleAnalyticsGa.primaryName = GoogleAnalyticsGaNames[0];
  GoogleAnalyticsGa.injections = [
    hit,
    noopFunc,
    logMessage
  ];
  return __toCommonJS(google_analytics_ga_exports);
})();

;(function(){
  window.adguardScriptlets = window.adguardScriptlets || {};
  var fn = null;

  // Unwrap the export from "main"
  if (typeof main === 'function') {
    fn = main;
  } else if (main && typeof main.default === 'function') {
    fn = main.default;
  } else {
    for (var key in main) {
      if (typeof main[key] === 'function') {
        fn = main[key];
        break;
      }
    }
  }

  if (!fn) {
    console.warn("No callable function found for scriptlet module: google-analytics-ga");
  }

  var aliases = [];
  Object.keys(main).forEach(function(key) {
    if (/Names$/.test(key)) {
      var arr = main[key];
      if (Array.isArray(arr)) {
        aliases = aliases.concat(arr);
      }
    }
  });

  if (aliases.length === 0 && fn && fn.primaryName) {
    aliases.push(fn.primaryName);
  }

  aliases.forEach(function(alias) {
    window.adguardScriptlets[alias] = fn;
  });
})();
