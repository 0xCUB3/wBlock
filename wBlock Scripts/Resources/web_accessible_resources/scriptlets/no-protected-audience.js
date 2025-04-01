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

  // Scriptlets/src/scriptlets/no-protected-audience.ts
  var no_protected_audience_exports = {};
  __export(no_protected_audience_exports, {
    noProtectedAudience: () => noProtectedAudience,
    noProtectedAudienceNames: () => noProtectedAudienceNames
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
  var noopStr = () => "";
  var noopResolveVoid = () => Promise.resolve(void 0);
  var noopResolveNull = () => Promise.resolve(null);

  // Scriptlets/src/scriptlets/no-protected-audience.ts
  function noProtectedAudience(source) {
    if (Document instanceof Object === false) {
      return;
    }
    const protectedAudienceMethods = {
      joinAdInterestGroup: noopResolveVoid,
      runAdAuction: noopResolveNull,
      leaveAdInterestGroup: noopResolveVoid,
      clearOriginJoinedAdInterestGroups: noopResolveVoid,
      createAuctionNonce: noopStr,
      updateAdInterestGroups: noopFunc
    };
    for (const key of Object.keys(protectedAudienceMethods)) {
      const methodName = key;
      const prototype = Navigator.prototype;
      if (!Object.prototype.hasOwnProperty.call(prototype, methodName) || prototype[methodName] instanceof Function === false) {
        continue;
      }
      prototype[methodName] = protectedAudienceMethods[methodName];
    }
    hit(source);
  }
  var noProtectedAudienceNames = [
    "no-protected-audience"
  ];
  noProtectedAudience.primaryName = noProtectedAudienceNames[0];
  noProtectedAudience.injections = [
    hit,
    noopStr,
    noopFunc,
    noopResolveVoid,
    noopResolveNull
  ];
  return __toCommonJS(no_protected_audience_exports);
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
    console.warn("No callable function found for scriptlet module: no-protected-audience");
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
