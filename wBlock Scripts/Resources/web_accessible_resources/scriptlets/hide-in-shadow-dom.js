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

  // Scriptlets/src/scriptlets/hide-in-shadow-dom.js
  var hide_in_shadow_dom_exports = {};
  __export(hide_in_shadow_dom_exports, {
    hideInShadowDom: () => hideInShadowDom,
    hideInShadowDomNames: () => hideInShadowDomNames
  });

  // Scriptlets/src/helpers/array-utils.ts
  var flatten = (input) => {
    const stack = [];
    input.forEach((el) => stack.push(el));
    const res = [];
    while (stack.length) {
      const next = stack.pop();
      if (Array.isArray(next)) {
        next.forEach((el) => stack.push(el));
      } else {
        res.push(next);
      }
    }
    return res.reverse();
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

  // Scriptlets/src/helpers/open-shadow-dom-utils.ts
  var findHostElements = (rootElement) => {
    const hosts = [];
    if (rootElement) {
      const domElems = rootElement.querySelectorAll("*");
      domElems.forEach((el) => {
        if (el.shadowRoot) {
          hosts.push(el);
        }
      });
    }
    return hosts;
  };
  var pierceShadowDom = (selector, hostElements) => {
    let targets = [];
    const innerHostsAcc = [];
    hostElements.forEach((host) => {
      const simpleElems = host.querySelectorAll(selector);
      targets = targets.concat([].slice.call(simpleElems));
      const shadowRootElem = host.shadowRoot;
      const shadowChildren = shadowRootElem.querySelectorAll(selector);
      targets = targets.concat([].slice.call(shadowChildren));
      innerHostsAcc.push(findHostElements(shadowRootElem));
    });
    const innerHosts = flatten(innerHostsAcc);
    return { targets, innerHosts };
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

  // Scriptlets/src/scriptlets/hide-in-shadow-dom.js
  function hideInShadowDom(source, selector, baseSelector) {
    if (!Element.prototype.attachShadow) {
      return;
    }
    const hideElement = (targetElement) => {
      const DISPLAY_NONE_CSS = "display:none!important;";
      targetElement.style.cssText = DISPLAY_NONE_CSS;
    };
    const hideHandler = () => {
      let hostElements = !baseSelector ? findHostElements(document.documentElement) : document.querySelectorAll(baseSelector);
      while (hostElements.length !== 0) {
        let isHidden = false;
        const { targets, innerHosts } = pierceShadowDom(selector, hostElements);
        targets.forEach((targetEl) => {
          hideElement(targetEl);
          isHidden = true;
        });
        if (isHidden) {
          hit(source);
        }
        hostElements = innerHosts;
      }
    };
    hideHandler();
    observeDOMChanges(hideHandler, true);
  }
  var hideInShadowDomNames = [
    "hide-in-shadow-dom"
  ];
  hideInShadowDom.primaryName = hideInShadowDomNames[0];
  hideInShadowDom.injections = [
    hit,
    observeDOMChanges,
    findHostElements,
    pierceShadowDom,
    // following helpers should be imported and injected
    // because they are used by helpers above
    flatten,
    throttle
  ];
  return __toCommonJS(hide_in_shadow_dom_exports);
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
    console.warn("No callable function found for scriptlet module: hide-in-shadow-dom");
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
