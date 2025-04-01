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

  // Scriptlets/src/scriptlets/metrika-yandex-watch.ts
  var metrika_yandex_watch_exports = {};
  __export(metrika_yandex_watch_exports, {
    metrikaYandexWatch: () => metrikaYandexWatch,
    metrikaYandexWatchNames: () => metrikaYandexWatchNames
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
  var noopArray = () => [];

  // Scriptlets/src/redirects/metrika-yandex-watch.js
  function metrikaYandexWatch(source) {
    const cbName = "yandex_metrika_callbacks";
    const asyncCallbackFromOptions = (options = {}) => {
      let { callback } = options;
      const { ctx } = options;
      if (typeof callback === "function") {
        callback = ctx !== void 0 ? callback.bind(ctx) : callback;
        setTimeout(() => callback());
      }
    };
    function Metrika() {
    }
    Metrika.counters = noopArray;
    Metrika.prototype.addFileExtension = noopFunc;
    Metrika.prototype.getClientID = noopFunc;
    Metrika.prototype.setUserID = noopFunc;
    Metrika.prototype.userParams = noopFunc;
    Metrika.prototype.params = noopFunc;
    Metrika.prototype.counters = noopArray;
    Metrika.prototype.extLink = (url, options) => {
      asyncCallbackFromOptions(options);
    };
    Metrika.prototype.file = (url, options) => {
      asyncCallbackFromOptions(options);
    };
    Metrika.prototype.hit = (url, options) => {
      asyncCallbackFromOptions(options);
    };
    Metrika.prototype.reachGoal = (target, params, cb, ctx) => {
      asyncCallbackFromOptions({ callback: cb, ctx });
    };
    Metrika.prototype.notBounce = asyncCallbackFromOptions;
    if (window.Ya) {
      window.Ya.Metrika = Metrika;
    } else {
      window.Ya = { Metrika };
    }
    if (window[cbName] && Array.isArray(window[cbName])) {
      window[cbName].forEach((func) => {
        if (typeof func === "function") {
          func();
        }
      });
    }
    hit(source);
  }
  var metrikaYandexWatchNames = [
    "metrika-yandex-watch"
  ];
  metrikaYandexWatch.primaryName = metrikaYandexWatchNames[0];
  metrikaYandexWatch.injections = [hit, noopFunc, noopArray];
  return __toCommonJS(metrika_yandex_watch_exports);
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
    console.warn("No callable function found for scriptlet module: metrika-yandex-watch");
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
