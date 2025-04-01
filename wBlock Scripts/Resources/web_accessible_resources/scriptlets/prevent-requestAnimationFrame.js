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

  // Scriptlets/src/scriptlets/prevent-requestAnimationFrame.js
  var prevent_requestAnimationFrame_exports = {};
  __export(prevent_requestAnimationFrame_exports, {
    preventRequestAnimationFrame: () => preventRequestAnimationFrame,
    preventRequestAnimationFrameNames: () => preventRequestAnimationFrameNames
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

  // Scriptlets/src/helpers/string-utils.ts
  var escapeRegExp = (str) => str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
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
  var isValidStrPattern = (input) => {
    const FORWARD_SLASH = "/";
    let str = escapeRegExp(input);
    if (input[0] === FORWARD_SLASH && input[input.length - 1] === FORWARD_SLASH) {
      str = input.slice(1, -1);
    }
    let isValid;
    try {
      isValid = new RegExp(str);
      isValid = true;
    } catch (e) {
      isValid = false;
    }
    return isValid;
  };
  var parseMatchArg = (match) => {
    const INVERT_MARKER = "!";
    const isInvertedMatch = match ? match?.startsWith(INVERT_MARKER) : false;
    const matchValue = isInvertedMatch ? match.slice(1) : match;
    const matchRegexp = toRegExp(matchValue);
    return { isInvertedMatch, matchRegexp, matchValue };
  };

  // Scriptlets/src/helpers/prevent-utils.ts
  var isValidCallback = (callback) => {
    return callback instanceof Function || typeof callback === "string";
  };

  // Scriptlets/src/scriptlets/prevent-requestAnimationFrame.js
  function preventRequestAnimationFrame(source, match) {
    const nativeRequestAnimationFrame = window.requestAnimationFrame;
    const shouldLog = typeof match === "undefined";
    const { isInvertedMatch, matchRegexp } = parseMatchArg(match);
    const rafWrapper = (callback, ...args) => {
      let shouldPrevent = false;
      if (shouldLog) {
        hit(source);
        logMessage(source, `requestAnimationFrame(${String(callback)})`, true);
      } else if (isValidCallback(callback) && isValidStrPattern(match)) {
        shouldPrevent = matchRegexp.test(callback.toString()) !== isInvertedMatch;
      }
      if (shouldPrevent) {
        hit(source);
        return nativeRequestAnimationFrame(noopFunc);
      }
      return nativeRequestAnimationFrame.apply(window, [callback, ...args]);
    };
    window.requestAnimationFrame = rafWrapper;
  }
  var preventRequestAnimationFrameNames = [
    "prevent-requestAnimationFrame",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "no-requestAnimationFrame-if.js",
    "ubo-no-requestAnimationFrame-if.js",
    "norafif.js",
    "ubo-norafif.js",
    "ubo-no-requestAnimationFrame-if",
    "ubo-norafif"
  ];
  preventRequestAnimationFrame.primaryName = preventRequestAnimationFrameNames[0];
  preventRequestAnimationFrame.injections = [
    hit,
    noopFunc,
    parseMatchArg,
    isValidStrPattern,
    isValidCallback,
    logMessage,
    // following helpers should be injected as helpers above use them
    escapeRegExp,
    toRegExp
  ];
  return __toCommonJS(prevent_requestAnimationFrame_exports);
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
    console.warn("No callable function found for scriptlet module: prevent-requestAnimationFrame");
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
