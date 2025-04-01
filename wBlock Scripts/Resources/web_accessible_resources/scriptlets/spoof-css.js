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

  // Scriptlets/src/scriptlets/spoof-css.js
  var spoof_css_exports = {};
  __export(spoof_css_exports, {
    spoofCSS: () => spoofCSS,
    spoofCSSNames: () => spoofCSSNames
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

  // Scriptlets/src/scriptlets/spoof-css.js
  function spoofCSS(source, selectors, cssPropertyName, cssPropertyValue) {
    if (!selectors) {
      return;
    }
    const uboAliases = [
      "spoof-css.js",
      "ubo-spoof-css.js",
      "ubo-spoof-css"
    ];
    function convertToCamelCase(cssProperty) {
      if (!cssProperty.includes("-")) {
        return cssProperty;
      }
      const splittedProperty = cssProperty.split("-");
      const firstPart = splittedProperty[0];
      const secondPart = splittedProperty[1];
      return `${firstPart}${secondPart[0].toUpperCase()}${secondPart.slice(1)}`;
    }
    const shouldDebug = !!(cssPropertyName === "debug" && cssPropertyValue);
    const propToValueMap = /* @__PURE__ */ new Map();
    if (uboAliases.includes(source.name)) {
      const { args } = source;
      let arrayOfProperties = [];
      const isDebug = args.at(-2);
      if (isDebug === "debug") {
        arrayOfProperties = args.slice(1, -2);
      } else {
        arrayOfProperties = args.slice(1);
      }
      for (let i = 0; i < arrayOfProperties.length; i += 2) {
        if (arrayOfProperties[i] === "") {
          break;
        }
        propToValueMap.set(convertToCamelCase(arrayOfProperties[i]), arrayOfProperties[i + 1]);
      }
    } else if (cssPropertyName && cssPropertyValue && !shouldDebug) {
      propToValueMap.set(convertToCamelCase(cssPropertyName), cssPropertyValue);
    }
    const spoofStyle = (cssProperty, realCssValue) => {
      return propToValueMap.has(cssProperty) ? propToValueMap.get(cssProperty) : realCssValue;
    };
    const setRectValue = (rect, prop, value) => {
      Object.defineProperty(
        rect,
        prop,
        {
          value: parseFloat(value)
        }
      );
    };
    const getter = (target, prop, receiver) => {
      hit(source);
      if (prop === "toString") {
        return target.toString.bind(target);
      }
      return Reflect.get(target, prop, receiver);
    };
    const getComputedStyleWrapper = (target, thisArg, args) => {
      if (shouldDebug) {
        debugger;
      }
      const style = Reflect.apply(target, thisArg, args);
      if (!args[0].matches(selectors)) {
        return style;
      }
      const proxiedStyle = new Proxy(style, {
        get(target2, prop) {
          const CSSStyleProp = target2[prop];
          if (typeof CSSStyleProp !== "function") {
            return spoofStyle(prop, CSSStyleProp || "");
          }
          if (prop !== "getPropertyValue") {
            return CSSStyleProp.bind(target2);
          }
          const getPropertyValueFunc = new Proxy(CSSStyleProp, {
            apply(target3, thisArg2, args2) {
              const cssName = args2[0];
              const cssValue = thisArg2[cssName];
              return spoofStyle(cssName, cssValue);
            },
            get: getter
          });
          return getPropertyValueFunc;
        },
        getOwnPropertyDescriptor(target2, prop) {
          if (propToValueMap.has(prop)) {
            return {
              configurable: true,
              enumerable: true,
              value: propToValueMap.get(prop),
              writable: true
            };
          }
          return Reflect.getOwnPropertyDescriptor(target2, prop);
        }
      });
      hit(source);
      return proxiedStyle;
    };
    const getComputedStyleHandler = {
      apply: getComputedStyleWrapper,
      get: getter
    };
    window.getComputedStyle = new Proxy(window.getComputedStyle, getComputedStyleHandler);
    const getBoundingClientRectWrapper = (target, thisArg, args) => {
      if (shouldDebug) {
        debugger;
      }
      const rect = Reflect.apply(target, thisArg, args);
      if (!thisArg.matches(selectors)) {
        return rect;
      }
      const {
        top,
        bottom,
        height,
        width,
        left,
        right
      } = rect;
      const newDOMRect = new window.DOMRect(rect.x, rect.y, top, bottom, width, height, left, right);
      if (propToValueMap.has("top")) {
        setRectValue(newDOMRect, "top", propToValueMap.get("top"));
      }
      if (propToValueMap.has("bottom")) {
        setRectValue(newDOMRect, "bottom", propToValueMap.get("bottom"));
      }
      if (propToValueMap.has("left")) {
        setRectValue(newDOMRect, "left", propToValueMap.get("left"));
      }
      if (propToValueMap.has("right")) {
        setRectValue(newDOMRect, "right", propToValueMap.get("right"));
      }
      if (propToValueMap.has("height")) {
        setRectValue(newDOMRect, "height", propToValueMap.get("height"));
      }
      if (propToValueMap.has("width")) {
        setRectValue(newDOMRect, "width", propToValueMap.get("width"));
      }
      hit(source);
      return newDOMRect;
    };
    const getBoundingClientRectHandler = {
      apply: getBoundingClientRectWrapper,
      get: getter
    };
    window.Element.prototype.getBoundingClientRect = new Proxy(
      window.Element.prototype.getBoundingClientRect,
      getBoundingClientRectHandler
    );
  }
  var spoofCSSNames = [
    "spoof-css",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "spoof-css.js",
    "ubo-spoof-css.js",
    "ubo-spoof-css"
  ];
  spoofCSS.primaryName = spoofCSSNames[0];
  spoofCSS.injections = [
    hit
  ];
  return __toCommonJS(spoof_css_exports);
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
    console.warn("No callable function found for scriptlet module: spoof-css");
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
