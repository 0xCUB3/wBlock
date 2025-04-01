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

  // Scriptlets/src/scriptlets/href-sanitizer.ts
  var href_sanitizer_exports = {};
  __export(href_sanitizer_exports, {
    hrefSanitizer: () => hrefSanitizer,
    hrefSanitizerNames: () => hrefSanitizerNames
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

  // Scriptlets/src/helpers/throttle.ts
  var throttle = (cb, delay) => {
    let wait = false;
    let savedArgs;
    const wrapper = (...args) => {
      if (wait) {
        savedArgs = args;
        return;
      }
      cb(...args);
      wait = true;
      setTimeout(() => {
        wait = false;
        if (savedArgs) {
          wrapper(...savedArgs);
          savedArgs = null;
        }
      }, delay);
    };
    return wrapper;
  };

  // Scriptlets/src/helpers/observer.ts
  var observeDOMChanges = (callback, observeAttrs = false, attrsToObserve = []) => {
    const THROTTLE_DELAY_MS = 20;
    const observer = new MutationObserver(throttle(callbackWrapper, THROTTLE_DELAY_MS));
    const connect = () => {
      if (attrsToObserve.length > 0) {
        observer.observe(document.documentElement, {
          childList: true,
          subtree: true,
          attributes: observeAttrs,
          attributeFilter: attrsToObserve
        });
      } else {
        observer.observe(document.documentElement, {
          childList: true,
          subtree: true,
          attributes: observeAttrs
        });
      }
    };
    const disconnect = () => {
      observer.disconnect();
    };
    function callbackWrapper() {
      disconnect();
      callback();
      connect();
    }
    connect();
  };

  // Scriptlets/src/scriptlets/href-sanitizer.ts
  function hrefSanitizer(source, selector, attribute = "text", transform = "") {
    if (!selector) {
      logMessage(source, "Selector is required.");
      return;
    }
    const BASE64_DECODE_TRANSFORM_MARKER = "base64decode";
    const REMOVE_HASH_TRANSFORM_MARKER = "removeHash";
    const REMOVE_PARAM_TRANSFORM_MARKER = "removeParam";
    const MARKER_SEPARATOR = ":";
    const COMMA = ",";
    const regexpNotValidAtStart = /^[^\x21-\x7e\p{Letter}]+/u;
    const regexpNotValidAtEnd = /[^\x21-\x7e\p{Letter}]+$/u;
    const extractNewHref = (anchor, attr) => {
      if (attr === "text") {
        if (!anchor.textContent) {
          return "";
        }
        return anchor.textContent.replace(regexpNotValidAtStart, "").replace(regexpNotValidAtEnd, "");
      }
      if (attr.startsWith("?")) {
        try {
          const url = new URL(anchor.href, document.location.href);
          return url.searchParams.get(attr.slice(1)) || "";
        } catch (ex) {
          logMessage(
            source,
            `Cannot retrieve the parameter '${attr.slice(1)}' from the URL '${anchor.href}`
          );
          return "";
        }
      }
      if (attr.startsWith("[") && attr.endsWith("]")) {
        return anchor.getAttribute(attr.slice(1, -1)) || "";
      }
      return "";
    };
    const isValidURL = (url) => {
      try {
        new URL(url);
        return true;
      } catch {
        return false;
      }
    };
    const getValidURL = (text) => {
      if (!text) {
        return null;
      }
      try {
        const { href, protocol } = new URL(text, document.location.href);
        if (protocol !== "http:" && protocol !== "https:") {
          logMessage(source, `Protocol not allowed: "${protocol}", from URL: "${href}"`);
          return null;
        }
        return href;
      } catch {
        return null;
      }
    };
    const isSanitizableAnchor = (element) => {
      return element.nodeName.toLowerCase() === "a" && element.hasAttribute("href");
    };
    const extractURLFromObject = (obj) => {
      for (const key in obj) {
        if (!Object.prototype.hasOwnProperty.call(obj, key)) {
          continue;
        }
        const value = obj[key];
        if (typeof value === "string" && isValidURL(value)) {
          return value;
        }
        if (typeof value === "object" && value !== null) {
          const result = extractURLFromObject(value);
          if (result) {
            return result;
          }
        }
      }
      return null;
    };
    const isStringifiedObject = (content) => content.startsWith("{") && content.endsWith("}");
    const decodeBase64SeveralTimes = (text, times) => {
      let result = text;
      for (let i = 0; i < times; i += 1) {
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
          const parsedResult = JSON.parse(result);
          return extractURLFromObject(parsedResult);
        } catch (ex) {
          return "";
        }
      }
      logMessage(source, `Failed to decode base64 string: ${text}`);
      return "";
    };
    const SEARCH_QUERY_MARKER = "?";
    const SEARCH_PARAMS_MARKER = "&";
    const HASHBANG_MARKER = "#!";
    const ANCHOR_MARKER = "#";
    const DECODE_ATTEMPTS_NUMBER = 10;
    const decodeSearchString = (search) => {
      const searchString = search.replace(SEARCH_QUERY_MARKER, "");
      let decodedParam;
      let validEncodedParam;
      if (searchString.includes(SEARCH_PARAMS_MARKER)) {
        const searchParamsArray = searchString.split(SEARCH_PARAMS_MARKER);
        searchParamsArray.forEach((param) => {
          decodedParam = decodeBase64SeveralTimes(param, DECODE_ATTEMPTS_NUMBER);
          if (decodedParam && decodedParam.length > 0) {
            validEncodedParam = decodedParam;
          }
        });
        return validEncodedParam;
      }
      return decodeBase64SeveralTimes(searchString, DECODE_ATTEMPTS_NUMBER);
    };
    const decodeHashString = (hash) => {
      let validEncodedHash = "";
      if (hash.includes(HASHBANG_MARKER)) {
        validEncodedHash = hash.replace(HASHBANG_MARKER, "");
      } else if (hash.includes(ANCHOR_MARKER)) {
        validEncodedHash = hash.replace(ANCHOR_MARKER, "");
      }
      return validEncodedHash ? decodeBase64SeveralTimes(validEncodedHash, DECODE_ATTEMPTS_NUMBER) : "";
    };
    const removeHash = (url) => {
      const urlObj = new URL(url, window.location.origin);
      if (!urlObj.hash) {
        return "";
      }
      urlObj.hash = "";
      return urlObj.toString();
    };
    const removeParam = (url, transformValue) => {
      const urlObj = new URL(url, window.location.origin);
      const paramNamesToRemoveStr = transformValue.split(MARKER_SEPARATOR)[1];
      if (!paramNamesToRemoveStr) {
        urlObj.search = "";
        return urlObj.toString();
      }
      const initSearchParamsLength = urlObj.searchParams.toString().length;
      const removeParams = paramNamesToRemoveStr.split(COMMA);
      removeParams.forEach((param) => {
        if (urlObj.searchParams.has(param)) {
          urlObj.searchParams.delete(param);
        }
      });
      if (initSearchParamsLength === urlObj.searchParams.toString().length) {
        return "";
      }
      return urlObj.toString();
    };
    const decodeBase64URL = (url) => {
      const { search, hash } = new URL(url, document.location.href);
      if (search.length > 0) {
        return decodeSearchString(search);
      }
      if (hash.length > 0) {
        return decodeHashString(hash);
      }
      logMessage(source, `Failed to execute base64 from URL: ${url}`);
      return null;
    };
    const base64Decode = (href) => {
      if (isValidURL(href)) {
        return decodeBase64URL(href) || "";
      }
      return decodeBase64SeveralTimes(href, DECODE_ATTEMPTS_NUMBER) || "";
    };
    const sanitize = (elementSelector) => {
      let elements;
      try {
        elements = document.querySelectorAll(elementSelector);
      } catch (e) {
        logMessage(source, `Invalid selector "${elementSelector}"`);
        return;
      }
      elements.forEach((elem) => {
        try {
          if (!isSanitizableAnchor(elem)) {
            logMessage(source, `${elem} is not a valid element to sanitize`);
            return;
          }
          let newHref = extractNewHref(elem, attribute);
          if (transform) {
            switch (true) {
              case transform === BASE64_DECODE_TRANSFORM_MARKER:
                newHref = base64Decode(newHref);
                break;
              case transform === REMOVE_HASH_TRANSFORM_MARKER:
                newHref = removeHash(newHref);
                break;
              case transform.startsWith(REMOVE_PARAM_TRANSFORM_MARKER): {
                newHref = removeParam(newHref, transform);
                break;
              }
              default:
                logMessage(source, `Invalid transform option: "${transform}"`);
                return;
            }
          }
          const newValidHref = getValidURL(newHref);
          if (!newValidHref) {
            logMessage(source, `Invalid URL: ${newHref}`);
            return;
          }
          const oldHref = elem.href;
          elem.setAttribute("href", newValidHref);
          if (newValidHref !== oldHref) {
            logMessage(source, `Sanitized "${oldHref}" to "${newValidHref}".`);
          }
        } catch (ex) {
          logMessage(source, `Failed to sanitize ${elem}.`);
        }
      });
      hit(source);
    };
    const run = () => {
      sanitize(selector);
      observeDOMChanges(() => sanitize(selector), true);
    };
    if (document.readyState === "loading") {
      window.addEventListener("DOMContentLoaded", run, { once: true });
    } else {
      run();
    }
  }
  var hrefSanitizerNames = [
    "href-sanitizer",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "href-sanitizer.js",
    "ubo-href-sanitizer.js",
    "ubo-href-sanitizer"
  ];
  hrefSanitizer.primaryName = hrefSanitizerNames[0];
  hrefSanitizer.injections = [
    observeDOMChanges,
    hit,
    logMessage,
    // following helpers should be imported and injected
    // because they are used by helpers above
    throttle
  ];
  return __toCommonJS(href_sanitizer_exports);
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
    console.warn("No callable function found for scriptlet module: href-sanitizer");
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
