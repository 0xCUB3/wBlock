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

  // Scriptlets/src/scriptlets/google-analytics.ts
  var google_analytics_exports = {};
  __export(google_analytics_exports, {
    GoogleAnalytics: () => GoogleAnalytics,
    GoogleAnalyticsNames: () => GoogleAnalyticsNames
  });

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
  var noopNull = () => null;
  var noopArray = () => [];

  // Scriptlets/src/redirects/google-analytics.js
  function GoogleAnalytics(source) {
    const Tracker = function() {
    };
    const proto = Tracker.prototype;
    proto.get = noopFunc;
    proto.set = noopFunc;
    proto.send = noopFunc;
    const googleAnalyticsName = window.GoogleAnalyticsObject || "ga";
    const queue = window[googleAnalyticsName]?.q;
    function ga(a) {
      const len = arguments.length;
      if (len === 0) {
        return;
      }
      const lastArg = arguments[len - 1];
      let replacer;
      if (lastArg instanceof Object && lastArg !== null && typeof lastArg.hitCallback === "function") {
        replacer = lastArg.hitCallback;
      } else if (typeof lastArg === "function") {
        replacer = () => {
          lastArg(ga.create());
        };
      }
      try {
        setTimeout(replacer, 1);
      } catch (ex) {
      }
    }
    ga.create = () => new Tracker();
    ga.getByName = () => new Tracker();
    ga.getAll = () => [new Tracker()];
    ga.remove = noopFunc;
    ga.loaded = true;
    window[googleAnalyticsName] = ga;
    if (Array.isArray(queue)) {
      const push = (arg) => {
        ga(...arg);
      };
      queue.push = push;
      queue.forEach(push);
    }
    const { dataLayer, google_optimize } = window;
    if (dataLayer instanceof Object === false) {
      return;
    }
    if (dataLayer.hide instanceof Object && typeof dataLayer.hide.end === "function") {
      dataLayer.hide.end();
    }
    const handleCallback = (dataObj, funcName) => {
      if (dataObj && typeof dataObj[funcName] === "function") {
        setTimeout(dataObj[funcName]);
      }
    };
    if (typeof dataLayer.push === "function") {
      dataLayer.push = (data) => {
        if (data instanceof Object) {
          handleCallback(data, "eventCallback");
          for (const key in data) {
            handleCallback(data[key], "event_callback");
          }
          if (!data.hasOwnProperty("eventCallback") && !data.hasOwnProperty("eventCallback")) {
            [].push.call(window.dataLayer, data);
          }
        }
        if (Array.isArray(data)) {
          data.forEach((arg) => {
            handleCallback(arg, "callback");
          });
        }
        return noopFunc;
      };
    }
    if (google_optimize instanceof Object && typeof google_optimize.get === "function") {
      const googleOptimizeWrapper = {
        get: noopFunc
      };
      window.google_optimize = googleOptimizeWrapper;
    }
    hit(source);
  }
  var GoogleAnalyticsNames = [
    "google-analytics",
    "ubo-google-analytics_analytics.js",
    "google-analytics_analytics.js",
    // https://github.com/AdguardTeam/Scriptlets/issues/127
    "googletagmanager-gtm",
    "ubo-googletagmanager_gtm.js",
    "googletagmanager_gtm.js"
  ];
  GoogleAnalytics.primaryName = GoogleAnalyticsNames[0];
  GoogleAnalytics.injections = [
    hit,
    noopFunc,
    noopNull,
    noopArray
  ];
  return __toCommonJS(google_analytics_exports);
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
    console.warn("No callable function found for scriptlet module: google-analytics");
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
