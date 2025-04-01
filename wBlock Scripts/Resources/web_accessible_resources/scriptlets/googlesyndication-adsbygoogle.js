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

  // Scriptlets/src/scriptlets/googlesyndication-adsbygoogle.ts
  var googlesyndication_adsbygoogle_exports = {};
  __export(googlesyndication_adsbygoogle_exports, {
    GoogleSyndicationAdsByGoogle: () => GoogleSyndicationAdsByGoogle,
    GoogleSyndicationAdsByGoogleNames: () => GoogleSyndicationAdsByGoogleNames
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

  // Scriptlets/src/redirects/googlesyndication-adsbygoogle.js
  function GoogleSyndicationAdsByGoogle(source) {
    window.adsbygoogle = {
      // https://github.com/AdguardTeam/Scriptlets/issues/113
      // length: 0,
      loaded: true,
      // https://github.com/AdguardTeam/Scriptlets/issues/184
      push(arg) {
        if (typeof this.length === "undefined") {
          this.length = 0;
          this.length += 1;
        }
        if (arg !== null && arg instanceof Object && arg.constructor.name === "Object") {
          for (const key of Object.keys(arg)) {
            if (typeof arg[key] === "function") {
              try {
                arg[key].call(this, {});
              } catch {
              }
            }
          }
        }
      }
    };
    const adElems = document.querySelectorAll(".adsbygoogle");
    const css = "height:1px!important;max-height:1px!important;max-width:1px!important;width:1px!important;";
    const statusAttrName = "data-adsbygoogle-status";
    const ASWIFT_IFRAME_MARKER = "aswift_";
    const GOOGLE_ADS_IFRAME_MARKER = "google_ads_iframe_";
    let executed = false;
    for (let i = 0; i < adElems.length; i += 1) {
      const adElemChildNodes = adElems[i].childNodes;
      const childNodesQuantity = adElemChildNodes.length;
      let areIframesDefined = false;
      if (childNodesQuantity > 0) {
        areIframesDefined = childNodesQuantity === 2 && adElemChildNodes[0].nodeName.toLowerCase() === "iframe" && adElemChildNodes[0].id.includes(ASWIFT_IFRAME_MARKER) && adElemChildNodes[1].nodeName.toLowerCase() === "iframe" && adElemChildNodes[1].id.includes(GOOGLE_ADS_IFRAME_MARKER);
      }
      if (!areIframesDefined) {
        adElems[i].setAttribute(statusAttrName, "done");
        const aswiftIframe = document.createElement("iframe");
        aswiftIframe.id = `${ASWIFT_IFRAME_MARKER}${i}`;
        aswiftIframe.style = css;
        adElems[i].appendChild(aswiftIframe);
        const innerAswiftIframe = document.createElement("iframe");
        aswiftIframe.contentWindow.document.body.appendChild(innerAswiftIframe);
        const googleadsIframe = document.createElement("iframe");
        googleadsIframe.id = `${GOOGLE_ADS_IFRAME_MARKER}${i}`;
        googleadsIframe.style = css;
        adElems[i].appendChild(googleadsIframe);
        const innerGoogleadsIframe = document.createElement("iframe");
        googleadsIframe.contentWindow.document.body.appendChild(innerGoogleadsIframe);
        executed = true;
      }
    }
    if (executed) {
      hit(source);
    }
  }
  var GoogleSyndicationAdsByGoogleNames = [
    "googlesyndication-adsbygoogle",
    "ubo-googlesyndication_adsbygoogle.js",
    "googlesyndication_adsbygoogle.js"
  ];
  GoogleSyndicationAdsByGoogle.primaryName = GoogleSyndicationAdsByGoogleNames[0];
  GoogleSyndicationAdsByGoogle.injections = [
    hit
  ];
  return __toCommonJS(googlesyndication_adsbygoogle_exports);
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
    console.warn("No callable function found for scriptlet module: googlesyndication-adsbygoogle");
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
