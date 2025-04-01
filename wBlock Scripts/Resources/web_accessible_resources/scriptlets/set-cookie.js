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

  // Scriptlets/src/scriptlets/set-cookie.js
  var set_cookie_exports = {};
  __export(set_cookie_exports, {
    setCookie: () => setCookie,
    setCookieNames: () => setCookieNames
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
  var getLimitedCookieValue = (value) => {
    if (!value) {
      return null;
    }
    const allowedCookieValues = /* @__PURE__ */ new Set([
      "true",
      "t",
      "false",
      "f",
      "yes",
      "y",
      "no",
      "n",
      "ok",
      "on",
      "off",
      "accept",
      "accepted",
      "notaccepted",
      "reject",
      "rejected",
      "allow",
      "allowed",
      "disallow",
      "deny",
      "enable",
      "enabled",
      "disable",
      "disabled",
      "necessary",
      "required",
      "hide",
      "hidden",
      "essential",
      "nonessential",
      "checked",
      "unchecked",
      "forbidden",
      "forever"
    ]);
    let validValue;
    if (allowedCookieValues.has(value.toLowerCase())) {
      validValue = value;
    } else if (/^\d+$/.test(value)) {
      validValue = parseFloat(value);
      if (nativeIsNaN(validValue)) {
        return null;
      }
      if (Math.abs(validValue) < 0 || Math.abs(validValue) > 32767) {
        return null;
      }
    } else {
      return null;
    }
    return validValue;
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

  // Scriptlets/src/scriptlets/set-cookie.js
  function setCookie(source, name, value, path = "/", domain = "") {
    const validValue = getLimitedCookieValue(value);
    if (validValue === null) {
      logMessage(source, `Invalid cookie value: '${validValue}'`);
      return;
    }
    if (!isValidCookiePath(path)) {
      logMessage(source, `Invalid cookie path: '${path}'`);
      return;
    }
    if (!document.location.origin.includes(domain)) {
      logMessage(source, `Cookie domain not matched by origin: '${domain}'`);
      return;
    }
    const cookieToSet = serializeCookie(name, validValue, path, domain);
    if (!cookieToSet) {
      logMessage(source, "Invalid cookie name or value");
      return;
    }
    hit(source);
    document.cookie = cookieToSet;
  }
  var setCookieNames = [
    "set-cookie",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "set-cookie.js",
    "ubo-set-cookie.js",
    "ubo-set-cookie"
  ];
  setCookie.primaryName = setCookieNames[0];
  setCookie.injections = [
    hit,
    logMessage,
    nativeIsNaN,
    isCookieSetWithValue,
    getLimitedCookieValue,
    serializeCookie,
    isValidCookiePath,
    getCookiePath
  ];
  return __toCommonJS(set_cookie_exports);
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
    console.warn("No callable function found for scriptlet module: set-cookie");
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
