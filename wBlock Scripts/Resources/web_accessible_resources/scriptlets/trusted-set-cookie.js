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

  // Scriptlets/src/scriptlets/trusted-set-cookie.js
  var trusted_set_cookie_exports = {};
  __export(trusted_set_cookie_exports, {
    trustedSetCookie: () => trustedSetCookie,
    trustedSetCookieNames: () => trustedSetCookieNames
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

  // Scriptlets/src/helpers/cookie-utils.ts
  var isValidCookiePath = (rawPath) => rawPath === "/" || rawPath === "none";
  var getCookiePath = (rawPath) => {
    if (rawPath === "/") {
      return "path=/";
    }
    return "";
  };
  var serializeCookie = (name, rawValue, rawPath, domainValue = "", shouldEncodeValue = true) => {
    const HOST_PREFIX = "__Host-";
    const SECURE_PREFIX = "__Secure-";
    const COOKIE_BREAKER = ";";
    if (!shouldEncodeValue && `${rawValue}`.includes(COOKIE_BREAKER) || name.includes(COOKIE_BREAKER)) {
      return null;
    }
    const value = shouldEncodeValue ? encodeURIComponent(rawValue) : rawValue;
    let resultCookie = `${name}=${value}`;
    if (name.startsWith(HOST_PREFIX)) {
      resultCookie += "; path=/; secure";
      if (domainValue) {
        console.debug(
          `Domain value: "${domainValue}" has been ignored, because is not allowed for __Host- prefixed cookies`
        );
      }
      return resultCookie;
    }
    const path = getCookiePath(rawPath);
    if (path) {
      resultCookie += `; ${path}`;
    }
    if (name.startsWith(SECURE_PREFIX)) {
      resultCookie += "; secure";
    }
    if (domainValue) {
      resultCookie += `; domain=${domainValue}`;
    }
    return resultCookie;
  };
  var isCookieSetWithValue = (cookieString, name, value) => {
    return cookieString.split(";").some((cookieStr) => {
      const pos = cookieStr.indexOf("=");
      if (pos === -1) {
        return false;
      }
      const cookieName = cookieStr.slice(0, pos).trim();
      const cookieValue = cookieStr.slice(pos + 1).trim();
      return name === cookieName && value === cookieValue;
    });
  };
  var getTrustedCookieOffsetMs = (offsetExpiresSec) => {
    const ONE_YEAR_EXPIRATION_KEYWORD = "1year";
    const ONE_DAY_EXPIRATION_KEYWORD = "1day";
    const MS_IN_SEC = 1e3;
    const SECONDS_IN_YEAR = 365 * 24 * 60 * 60;
    const SECONDS_IN_DAY = 24 * 60 * 60;
    let parsedSec;
    if (offsetExpiresSec === ONE_YEAR_EXPIRATION_KEYWORD) {
      parsedSec = SECONDS_IN_YEAR;
    } else if (offsetExpiresSec === ONE_DAY_EXPIRATION_KEYWORD) {
      parsedSec = SECONDS_IN_DAY;
    } else {
      parsedSec = Number.parseInt(offsetExpiresSec, 10);
      if (Number.isNaN(parsedSec)) {
        return null;
      }
    }
    return parsedSec * MS_IN_SEC;
  };

  // Scriptlets/src/helpers/parse-keyword-value.ts
  var parseKeywordValue = (rawValue) => {
    const NOW_VALUE_KEYWORD = "$now$";
    const CURRENT_DATE_KEYWORD = "$currentDate$";
    const CURRENT_ISO_DATE_KEYWORD = "$currentISODate$";
    let parsedValue = rawValue;
    if (rawValue === NOW_VALUE_KEYWORD) {
      parsedValue = Date.now().toString();
    } else if (rawValue === CURRENT_DATE_KEYWORD) {
      parsedValue = Date();
    } else if (rawValue === CURRENT_ISO_DATE_KEYWORD) {
      parsedValue = (/* @__PURE__ */ new Date()).toISOString();
    }
    return parsedValue;
  };

  // Scriptlets/src/scriptlets/trusted-set-cookie.js
  function trustedSetCookie(source, name, value, offsetExpiresSec = "", path = "/", domain = "") {
    if (typeof name === "undefined") {
      logMessage(source, "Cookie name should be specified");
      return;
    }
    if (typeof value === "undefined") {
      logMessage(source, "Cookie value should be specified");
      return;
    }
    const parsedValue = parseKeywordValue(value);
    if (!isValidCookiePath(path)) {
      logMessage(source, `Invalid cookie path: '${path}'`);
      return;
    }
    if (!document.location.origin.includes(domain)) {
      logMessage(source, `Cookie domain not matched by origin: '${domain}'`);
      return;
    }
    let cookieToSet = serializeCookie(name, parsedValue, path, domain, false);
    if (!cookieToSet) {
      logMessage(source, "Invalid cookie name or value");
      return;
    }
    if (offsetExpiresSec) {
      const parsedOffsetMs = getTrustedCookieOffsetMs(offsetExpiresSec);
      if (!parsedOffsetMs) {
        logMessage(source, `Invalid offsetExpiresSec value: ${offsetExpiresSec}`);
        return;
      }
      const expires = Date.now() + parsedOffsetMs;
      cookieToSet += `; expires=${new Date(expires).toUTCString()}`;
    }
    document.cookie = cookieToSet;
    hit(source);
  }
  var trustedSetCookieNames = [
    "trusted-set-cookie"
    // trusted scriptlets support no aliases
  ];
  trustedSetCookie.primaryName = trustedSetCookieNames[0];
  trustedSetCookie.injections = [
    hit,
    logMessage,
    nativeIsNaN,
    isCookieSetWithValue,
    serializeCookie,
    isValidCookiePath,
    getTrustedCookieOffsetMs,
    parseKeywordValue,
    getCookiePath
  ];
  return __toCommonJS(trusted_set_cookie_exports);
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
    console.warn("No callable function found for scriptlet module: trusted-set-cookie");
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
