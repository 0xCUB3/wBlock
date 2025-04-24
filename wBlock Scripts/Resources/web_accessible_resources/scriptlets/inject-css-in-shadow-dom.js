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

  // Scriptlets/src/scriptlets/inject-css-in-shadow-dom.js
  var inject_css_in_shadow_dom_exports = {};
  __export(inject_css_in_shadow_dom_exports, {
    injectCssInShadowDom: () => injectCssInShadowDom,
    injectCssInShadowDomNames: () => injectCssInShadowDomNames
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

  // Scriptlets/src/helpers/shadow-dom-utils.ts
  var hijackAttachShadow = (context, hostSelector, callback) => {
    const handlerWrapper = (target, thisArg, args) => {
      const shadowRoot = Reflect.apply(target, thisArg, args);
      if (thisArg && thisArg.matches(hostSelector || "*")) {
        callback(shadowRoot);
      }
      return shadowRoot;
    };
    const attachShadowHandler = {
      apply: handlerWrapper
    };
    context.Element.prototype.attachShadow = new Proxy(
      context.Element.prototype.attachShadow,
      attachShadowHandler
    );
  };

  // Scriptlets/src/scriptlets/inject-css-in-shadow-dom.js
  function injectCssInShadowDom(source, cssRule, hostSelector = "", cssInjectionMethod = "adoptedStyleSheets") {
    if (!Element.prototype.attachShadow || typeof Proxy === "undefined" || typeof Reflect === "undefined") {
      return;
    }
    if (cssInjectionMethod !== "adoptedStyleSheets" && cssInjectionMethod !== "styleTag") {
      logMessage(source, `Unknown cssInjectionMethod: ${cssInjectionMethod}`);
      return;
    }
    if (cssRule.match(/(url|image-set)\(.*\)/i)) {
      logMessage(source, '"url()" function is not allowed for css rules');
      return;
    }
    const injectStyleTag = (shadowRoot) => {
      try {
        const styleTag = document.createElement("style");
        styleTag.innerText = cssRule;
        shadowRoot.appendChild(styleTag);
        hit(source);
      } catch (error) {
        logMessage(source, `Unable to inject style tag due to: 
'${error.message}'`);
      }
    };
    const injectAdoptedStyleSheets = (shadowRoot) => {
      try {
        const stylesheet = new CSSStyleSheet();
        try {
          stylesheet.insertRule(cssRule);
        } catch (e) {
          logMessage(source, `Unable to apply the rule '${cssRule}' due to: 
'${e.message}'`);
          return;
        }
        shadowRoot.adoptedStyleSheets = [...shadowRoot.adoptedStyleSheets, stylesheet];
        hit(source);
      } catch (error) {
        logMessage(source, `Unable to inject adopted style sheet due to: 
'${error.message}'`);
        injectStyleTag(shadowRoot);
      }
    };
    const callback = (shadowRoot) => {
      if (cssInjectionMethod === "adoptedStyleSheets") {
        injectAdoptedStyleSheets(shadowRoot);
      } else if (cssInjectionMethod === "styleTag") {
        injectStyleTag(shadowRoot);
      }
    };
    hijackAttachShadow(window, hostSelector, callback);
  }
  var injectCssInShadowDomNames = [
    "inject-css-in-shadow-dom"
  ];
  injectCssInShadowDom.primaryName = injectCssInShadowDomNames[0];
  injectCssInShadowDom.injections = [
    hit,
    logMessage,
    hijackAttachShadow
  ];
  return __toCommonJS(inject_css_in_shadow_dom_exports);
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
    console.warn("No callable function found for scriptlet module: inject-css-in-shadow-dom");
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
