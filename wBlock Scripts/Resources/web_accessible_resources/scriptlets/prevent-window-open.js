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

  // Scriptlets/src/scriptlets/prevent-window-open.js
  var prevent_window_open_exports = {};
  __export(prevent_window_open_exports, {
    preventWindowOpen: () => preventWindowOpen,
    preventWindowOpenNames: () => preventWindowOpenNames
  });

  // Scriptlets/src/helpers/number-utils.ts
  var nativeIsNaN = (num) => {
    const native = Number.isNaN || window.isNaN;
    return native(num);
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

  // Scriptlets/src/helpers/noop-utils.ts
  var noopFunc = () => {
  };
  var noopNull = () => null;
  var trueFunc = () => true;

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
  var substringAfter = (str, separator) => {
    if (!str) {
      return str;
    }
    const index = str.indexOf(separator);
    return index < 0 ? "" : str.substring(index + separator.length);
  };
  var substringBefore = (str, separator) => {
    if (!str || !separator) {
      return str;
    }
    const index = str.indexOf(separator);
    return index < 0 ? str : str.substring(0, index);
  };
  var isValidMatchStr = (match) => {
    const INVERT_MARKER = "!";
    let str = match;
    if (match?.startsWith(INVERT_MARKER)) {
      str = match.slice(1);
    }
    return isValidStrPattern(str);
  };
  var parseMatchArg = (match) => {
    const INVERT_MARKER = "!";
    const isInvertedMatch = match ? match?.startsWith(INVERT_MARKER) : false;
    const matchValue = isInvertedMatch ? match.slice(1) : match;
    const matchRegexp = toRegExp(matchValue);
    return { isInvertedMatch, matchRegexp, matchValue };
  };

  // Scriptlets/src/helpers/prevent-window-open-utils.ts
  var handleOldReplacement = (replacement) => {
    let result;
    if (!replacement) {
      result = noopFunc;
    } else if (replacement === "trueFunc") {
      result = trueFunc;
    } else if (replacement.includes("=")) {
      const isProp = replacement.startsWith("{") && replacement.endsWith("}");
      if (isProp) {
        const propertyPart = replacement.slice(1, -1);
        const propertyName = substringBefore(propertyPart, "=");
        const propertyValue = substringAfter(propertyPart, "=");
        if (propertyValue === "noopFunc") {
          result = {};
          result[propertyName] = noopFunc;
        }
      }
    }
    return result;
  };
  var createDecoy = (args) => {
    let TagName;
    ((TagName2) => {
      TagName2["Object"] = "object";
      TagName2["Iframe"] = "iframe";
    })(TagName || (TagName = {}));
    let UrlPropNameOf;
    ((UrlPropNameOf2) => {
      UrlPropNameOf2["Object"] = "data";
      UrlPropNameOf2["Iframe"] = "src";
    })(UrlPropNameOf || (UrlPropNameOf = {}));
    const { replacement, url, delay } = args;
    let tag;
    if (replacement === "obj") {
      tag = "object" /* Object */;
    } else {
      tag = "iframe" /* Iframe */;
    }
    const decoy = document.createElement(tag);
    if (decoy instanceof HTMLObjectElement) {
      decoy["data" /* Object */] = url;
    } else if (decoy instanceof HTMLIFrameElement) {
      decoy["src" /* Iframe */] = url;
    }
    decoy.style.setProperty("height", "1px", "important");
    decoy.style.setProperty("position", "fixed", "important");
    decoy.style.setProperty("top", "-1px", "important");
    decoy.style.setProperty("width", "1px", "important");
    document.body.appendChild(decoy);
    setTimeout(() => decoy.remove(), delay * 1e3);
    return decoy;
  };
  var getPreventGetter = (nativeGetter) => {
    const preventGetter = (target, prop) => {
      if (prop && prop === "closed") {
        return false;
      }
      if (typeof nativeGetter === "function") {
        return noopFunc;
      }
      return prop && target[prop];
    };
    return preventGetter;
  };

  // Scriptlets/src/scriptlets/prevent-window-open.js
  function preventWindowOpen(source, match = "*", delay, replacement) {
    const nativeOpen = window.open;
    const isNewSyntax = match !== "0" && match !== "1";
    const oldOpenWrapper = (str, ...args) => {
      match = Number(match) > 0;
      if (!isValidStrPattern(delay)) {
        logMessage(source, `Invalid parameter: ${delay}`);
        return nativeOpen.apply(window, [str, ...args]);
      }
      const searchRegexp = toRegExp(delay);
      if (match !== searchRegexp.test(str)) {
        return nativeOpen.apply(window, [str, ...args]);
      }
      hit(source);
      return handleOldReplacement(replacement);
    };
    const newOpenWrapper = (url, ...args) => {
      const shouldLog = replacement && replacement.includes("log");
      if (shouldLog) {
        const argsStr = args && args.length > 0 ? `, ${args.join(", ")}` : "";
        const message = `${url}${argsStr}`;
        logMessage(source, message, true);
        hit(source);
      }
      let shouldPrevent = false;
      if (match === "*") {
        shouldPrevent = true;
      } else if (isValidMatchStr(match)) {
        const { isInvertedMatch, matchRegexp } = parseMatchArg(match);
        shouldPrevent = matchRegexp.test(url) !== isInvertedMatch;
      } else {
        logMessage(source, `Invalid parameter: ${match}`);
        shouldPrevent = false;
      }
      if (shouldPrevent) {
        const parsedDelay = parseInt(delay, 10);
        let result;
        if (nativeIsNaN(parsedDelay)) {
          result = noopNull();
        } else {
          const decoyArgs = { replacement, url, delay: parsedDelay };
          const decoy = createDecoy(decoyArgs);
          let popup = decoy.contentWindow;
          if (typeof popup === "object" && popup !== null) {
            Object.defineProperty(popup, "closed", { value: false });
            Object.defineProperty(popup, "opener", { value: window });
            Object.defineProperty(popup, "frameElement", { value: null });
          } else {
            const nativeGetter = decoy.contentWindow && decoy.contentWindow.get;
            Object.defineProperty(decoy, "contentWindow", {
              get: getPreventGetter(nativeGetter)
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
  var preventWindowOpenNames = [
    "prevent-window-open",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "window.open-defuser.js",
    "ubo-window.open-defuser.js",
    "ubo-window.open-defuser",
    "nowoif.js",
    "ubo-nowoif.js",
    "ubo-nowoif",
    "no-window-open-if.js",
    "ubo-no-window-open-if.js",
    "ubo-no-window-open-if"
  ];
  preventWindowOpen.primaryName = preventWindowOpenNames[0];
  preventWindowOpen.injections = [
    hit,
    isValidStrPattern,
    escapeRegExp,
    isValidMatchStr,
    toRegExp,
    nativeIsNaN,
    parseMatchArg,
    handleOldReplacement,
    createDecoy,
    getPreventGetter,
    noopNull,
    logMessage,
    noopFunc,
    trueFunc,
    substringBefore,
    substringAfter
  ];
  return __toCommonJS(prevent_window_open_exports);
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
    console.warn("No callable function found for scriptlet module: prevent-window-open");
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
