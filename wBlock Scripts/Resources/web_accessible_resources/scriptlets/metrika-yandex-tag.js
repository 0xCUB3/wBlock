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

  // Scriptlets/src/scriptlets/metrika-yandex-tag.ts
  var metrika_yandex_tag_exports = {};
  __export(metrika_yandex_tag_exports, {
    metrikaYandexTag: () => metrikaYandexTag,
    metrikaYandexTagNames: () => metrikaYandexTagNames
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

  // Scriptlets/src/redirects/metrika-yandex-tag.js
  function metrikaYandexTag(source) {
    const asyncCallbackFromOptions = (id, param, options = {}) => {
      let { callback } = options;
      const { ctx } = options;
      if (typeof callback === "function") {
        callback = ctx !== void 0 ? callback.bind(ctx) : callback;
        setTimeout(() => callback());
      }
    };
    const addFileExtension = noopFunc;
    const extLink = asyncCallbackFromOptions;
    const file = asyncCallbackFromOptions;
    const getClientID = (id, cb) => {
      if (!cb) {
        return;
      }
      setTimeout(cb(null));
    };
    const hitFunc = asyncCallbackFromOptions;
    const notBounce = asyncCallbackFromOptions;
    const params = noopFunc;
    const reachGoal = (id, target, params2, callback, ctx) => {
      asyncCallbackFromOptions(null, null, { callback, ctx });
    };
    const setUserID = noopFunc;
    const userParams = noopFunc;
    const destruct = noopFunc;
    const api = {
      addFileExtension,
      extLink,
      file,
      getClientID,
      hit: hitFunc,
      notBounce,
      params,
      reachGoal,
      setUserID,
      userParams,
      destruct
    };
    function init(id) {
      window[`yaCounter${id}`] = api;
      document.dispatchEvent(new Event(`yacounter${id}inited`));
    }
    function ym(id, funcName, ...args) {
      if (funcName === "init") {
        return init(id);
      }
      return api[funcName] && api[funcName](id, ...args);
    }
    if (typeof window.ym === "undefined") {
      window.ym = ym;
      ym.a = [];
    } else if (window.ym && window.ym.a) {
      ym.a = window.ym.a;
      window.ym = ym;
      window.ym.a.forEach((params2) => {
        const id = params2[0];
        init(id);
      });
    }
    hit(source);
  }
  var metrikaYandexTagNames = [
    "metrika-yandex-tag"
  ];
  metrikaYandexTag.primaryName = metrikaYandexTagNames[0];
  metrikaYandexTag.injections = [hit, noopFunc];
  return __toCommonJS(metrika_yandex_tag_exports);
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
    console.warn("No callable function found for scriptlet module: metrika-yandex-tag");
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
