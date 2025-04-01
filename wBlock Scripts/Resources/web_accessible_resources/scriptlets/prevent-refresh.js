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

  // Scriptlets/src/scriptlets/prevent-refresh.js
  var prevent_refresh_exports = {};
  __export(prevent_refresh_exports, {
    preventRefresh: () => preventRefresh,
    preventRefreshNames: () => preventRefreshNames
  });

  // Scriptlets/src/helpers/number-utils.ts
  var nativeIsNaN = (num) => {
    const native = Number.isNaN || window.isNaN;
    return native(num);
  };
  var getNumberFromString = (rawString) => {
    const parsedDelay = parseInt(rawString, 10);
    const validDelay = nativeIsNaN(parsedDelay) ? null : parsedDelay;
    return validDelay;
  };

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

  // Scriptlets/src/scriptlets/prevent-refresh.js
  function preventRefresh(source, delaySec) {
    const getMetaElements = () => {
      let metaNodes = [];
      try {
        metaNodes = document.querySelectorAll('meta[http-equiv="refresh" i][content]');
      } catch (e) {
        try {
          metaNodes = document.querySelectorAll('meta[http-equiv="refresh"][content]');
        } catch (e2) {
          logMessage(source, e2);
        }
      }
      return Array.from(metaNodes);
    };
    const getMetaContentDelay = (metaElements) => {
      const delays = metaElements.map((meta) => {
        const contentString = meta.getAttribute("content");
        if (contentString.length === 0) {
          return null;
        }
        let contentDelay;
        const limiterIndex = contentString.indexOf(";");
        if (limiterIndex !== -1) {
          const delaySubstring = contentString.substring(0, limiterIndex);
          contentDelay = getNumberFromString(delaySubstring);
        } else {
          contentDelay = getNumberFromString(contentString);
        }
        return contentDelay;
      }).filter((delay) => delay !== null);
      if (!delays.length) {
        return null;
      }
      const minDelay = delays.reduce((a, b) => Math.min(a, b));
      return minDelay;
    };
    const stop = () => {
      const metaElements = getMetaElements();
      if (metaElements.length === 0) {
        return;
      }
      let secondsToRun = getNumberFromString(delaySec);
      if (secondsToRun === null) {
        secondsToRun = getMetaContentDelay(metaElements);
      }
      if (secondsToRun === null) {
        return;
      }
      const delayMs = secondsToRun * 1e3;
      setTimeout(() => {
        window.stop();
        hit(source);
      }, delayMs);
    };
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", stop, { once: true });
    } else {
      stop();
    }
  }
  var preventRefreshNames = [
    "prevent-refresh",
    // Aliases are needed for matching the related scriptlet converted into our syntax
    // These are used by UBO rules syntax
    // https://github.com/gorhill/uBlock/wiki/Resources-Library#general-purpose-scriptlets
    "prevent-refresh.js",
    "refresh-defuser.js",
    "refresh-defuser",
    // Prefix 'ubo-' is required to run converted rules
    "ubo-prevent-refresh.js",
    "ubo-prevent-refresh",
    "ubo-refresh-defuser.js",
    "ubo-refresh-defuser"
  ];
  preventRefresh.primaryName = preventRefreshNames[0];
  preventRefresh.injections = [
    hit,
    getNumberFromString,
    logMessage,
    nativeIsNaN
  ];
  return __toCommonJS(prevent_refresh_exports);
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
    console.warn("No callable function found for scriptlet module: prevent-refresh");
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
