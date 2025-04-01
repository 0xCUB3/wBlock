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

  // Scriptlets/src/scriptlets/adjust-setInterval.js
  var adjust_setInterval_exports = {};
  __export(adjust_setInterval_exports, {
    adjustSetInterval: () => adjustSetInterval,
    adjustSetIntervalNames: () => adjustSetIntervalNames
  });

  // Scriptlets/src/helpers/number-utils.ts
  var nativeIsNaN = (num) => {
    const native = Number.isNaN || window.isNaN;
    return native(num);
  };
  var nativeIsFinite = (num) => {
    const native = Number.isFinite || window.isFinite;
    return native(num);
  };

  // Scriptlets/src/helpers/adjust-set-utils.ts
  var shouldMatchAnyDelay = (delay) => delay === "*";
  var getMatchDelay = (delay) => {
    const DEFAULT_DELAY = 1e3;
    const parsedDelay = parseInt(delay, 10);
    const delayMatch = nativeIsNaN(parsedDelay) ? DEFAULT_DELAY : parsedDelay;
    return delayMatch;
  };
  var isDelayMatched = (inputDelay, realDelay) => {
    return shouldMatchAnyDelay(inputDelay) || realDelay === getMatchDelay(inputDelay);
  };
  var getBoostMultiplier = (boost) => {
    const DEFAULT_MULTIPLIER = 0.05;
    const MIN_MULTIPLIER = 1e-3;
    const MAX_MULTIPLIER = 50;
    const parsedBoost = parseFloat(boost);
    let boostMultiplier = nativeIsNaN(parsedBoost) || !nativeIsFinite(parsedBoost) ? DEFAULT_MULTIPLIER : parsedBoost;
    if (boostMultiplier < MIN_MULTIPLIER) {
      boostMultiplier = MIN_MULTIPLIER;
    }
    if (boostMultiplier > MAX_MULTIPLIER) {
      boostMultiplier = MAX_MULTIPLIER;
    }
    return boostMultiplier;
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

  // Scriptlets/src/helpers/string-utils.ts
  var toRegExp = (rawInput) => {
    const input = rawInput || "";
    const DEFAULT_VALUE = ".?";
    const FORWARD_SLASH = "/";
    if (input === "") {
      return new RegExp(DEFAULT_VALUE);
    }
    const delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
    const flagsPart = input.substring(delimiterIndex + 1);
    const regExpPart = input.substring(0, delimiterIndex + 1);
    const isValidRegExpFlag = (flag) => {
      if (!flag) {
        return false;
      }
      try {
        new RegExp("", flag);
        return true;
      } catch (ex) {
        return false;
      }
    };
    const getRegExpFlags = (regExpStr, flagsStr) => {
      if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
        return flagsStr;
      }
      return "";
    };
    const flags = getRegExpFlags(regExpPart, flagsPart);
    if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
      const regExpInput = flags ? regExpPart : input;
      return new RegExp(regExpInput.slice(1, -1), flags);
    }
    const escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    return new RegExp(escaped);
  };

  // Scriptlets/src/helpers/prevent-utils.ts
  var isValidCallback = (callback) => {
    return callback instanceof Function || typeof callback === "string";
  };

  // Scriptlets/src/scriptlets/adjust-setInterval.js
  function adjustSetInterval(source, matchCallback, matchDelay, boost) {
    const nativeSetInterval = window.setInterval;
    const matchRegexp = toRegExp(matchCallback);
    const intervalWrapper = (callback, delay, ...args) => {
      if (!isValidCallback(callback)) {
        const message = `Scriptlet can't be applied because of invalid callback: '${String(callback)}'`;
        logMessage(source, message);
      } else if (matchRegexp.test(callback.toString()) && isDelayMatched(matchDelay, delay)) {
        delay *= getBoostMultiplier(boost);
        hit(source);
      }
      return nativeSetInterval.apply(window, [callback, delay, ...args]);
    };
    window.setInterval = intervalWrapper;
  }
  var adjustSetIntervalNames = [
    "adjust-setInterval",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "nano-setInterval-booster.js",
    "ubo-nano-setInterval-booster.js",
    "nano-sib.js",
    "ubo-nano-sib.js",
    "adjust-setInterval.js",
    "ubo-adjust-setInterval.js",
    "ubo-nano-setInterval-booster",
    "ubo-nano-sib",
    "ubo-adjust-setInterval"
  ];
  adjustSetInterval.primaryName = adjustSetIntervalNames[0];
  adjustSetInterval.injections = [
    hit,
    isValidCallback,
    toRegExp,
    getBoostMultiplier,
    isDelayMatched,
    logMessage,
    // following helpers should be injected as helpers above use them
    nativeIsNaN,
    nativeIsFinite,
    getMatchDelay,
    shouldMatchAnyDelay
  ];
  return __toCommonJS(adjust_setInterval_exports);
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
    console.warn("No callable function found for scriptlet module: adjust-setInterval");
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
