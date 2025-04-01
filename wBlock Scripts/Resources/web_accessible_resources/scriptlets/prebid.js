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

  // Scriptlets/src/scriptlets/prebid.ts
  var prebid_exports = {};
  __export(prebid_exports, {
    Prebid: () => Prebid,
    PrebidNames: () => PrebidNames
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
  var noopArray = () => [];

  // Scriptlets/src/redirects/prebid.js
  function Prebid(source) {
    const pushFunction = function(arg) {
      if (typeof arg === "function") {
        try {
          arg.call();
        } catch (ex) {
        }
      }
    };
    const pbjsWrapper = {
      addAdUnits() {
      },
      adServers: {
        dfp: {
          // https://docs.prebid.org/dev-docs/publisher-api-reference/adServers.dfp.buildVideoUrl.html
          // returns ad URL
          buildVideoUrl: noopStr
        }
      },
      adUnits: [],
      aliasBidder() {
      },
      cmd: [],
      enableAnalytics() {
      },
      getHighestCpmBids: noopArray,
      libLoaded: true,
      que: [],
      requestBids(arg) {
        if (arg instanceof Object && arg.bidsBackHandler) {
          try {
            arg.bidsBackHandler.call();
          } catch (ex) {
          }
        }
      },
      removeAdUnit() {
      },
      setBidderConfig() {
      },
      setConfig() {
      },
      setTargetingForGPTAsync() {
      }
    };
    pbjsWrapper.cmd.push = pushFunction;
    pbjsWrapper.que.push = pushFunction;
    window.pbjs = pbjsWrapper;
    hit(source);
  }
  var PrebidNames = ["prebid"];
  Prebid.primaryName = PrebidNames[0];
  Prebid.injections = [hit, noopFunc, noopStr, noopArray];
  return __toCommonJS(prebid_exports);
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
    console.warn("No callable function found for scriptlet module: prebid");
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
