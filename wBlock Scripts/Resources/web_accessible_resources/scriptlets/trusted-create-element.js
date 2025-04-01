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

  // Scriptlets/src/scriptlets/trusted-create-element.ts
  var trusted_create_element_exports = {};
  __export(trusted_create_element_exports, {
    trustedCreateElement: () => trustedCreateElement,
    trustedCreateElementNames: () => trustedCreateElementNames
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

  // Scriptlets/src/helpers/attribute-utils.ts
  var parseAttributePairs = (input) => {
    if (!input) {
      return [];
    }
    const NAME_VALUE_SEPARATOR = "=";
    const PAIRS_SEPARATOR = " ";
    const SINGLE_QUOTE = "'";
    const DOUBLE_QUOTE = '"';
    const BACKSLASH = "\\";
    const pairs = [];
    for (let i = 0; i < input.length; i += 1) {
      let name = "";
      let value = "";
      while (i < input.length && input[i] !== NAME_VALUE_SEPARATOR && input[i] !== PAIRS_SEPARATOR) {
        name += input[i];
        i += 1;
      }
      if (i < input.length && input[i] === NAME_VALUE_SEPARATOR) {
        i += 1;
        let quote = null;
        if (input[i] === SINGLE_QUOTE || input[i] === DOUBLE_QUOTE) {
          quote = input[i];
          i += 1;
          for (; i < input.length; i += 1) {
            if (input[i] === quote) {
              if (input[i - 1] === BACKSLASH) {
                value = `${value.slice(0, -1)}${quote}`;
              } else {
                i += 1;
                quote = null;
                break;
              }
            } else {
              value += input[i];
            }
          }
          if (quote !== null) {
            throw new Error(`Unbalanced quote for attribute value: '${input}'`);
          }
        } else {
          throw new Error(`Attribute value should be quoted: "${input.slice(i)}"`);
        }
      }
      name = name.trim();
      value = value.trim();
      if (!name) {
        if (!value) {
          continue;
        }
        throw new Error(`Attribute name before '=' should be specified: '${input}'`);
      }
      pairs.push({
        name,
        value
      });
      if (input[i] && input[i] !== PAIRS_SEPARATOR) {
        throw new Error(`No space before attribute: '${input.slice(i)}'`);
      }
    }
    return pairs;
  };

  // Scriptlets/src/helpers/get-error-message.ts
  var getErrorMessage = (error) => {
    const isErrorWithMessage = (e) => typeof e === "object" && e !== null && "message" in e && typeof e.message === "string";
    if (isErrorWithMessage(error)) {
      return error.message;
    }
    try {
      return new Error(JSON.stringify(error)).message;
    } catch {
      return new Error(String(error)).message;
    }
  };

  // Scriptlets/src/helpers/observer.ts
  var observeDocumentWithTimeout = (callback, options = { subtree: true, childList: true }, timeout = 1e4) => {
    const documentObserver = new MutationObserver((mutations, observer) => {
      observer.disconnect();
      callback(mutations, observer);
      observer.observe(document.documentElement, options);
    });
    documentObserver.observe(document.documentElement, options);
    if (typeof timeout === "number") {
      setTimeout(() => documentObserver.disconnect(), timeout);
    }
  };

  // Scriptlets/src/scriptlets/trusted-create-element.ts
  function trustedCreateElement(source, parentSelector, tagName, attributePairs = "", textContent = "", cleanupDelayMs = NaN) {
    if (!parentSelector || !tagName) {
      return;
    }
    const IFRAME_WINDOW_NAME = "trusted-create-element-window";
    if (window.name === IFRAME_WINDOW_NAME) {
      return;
    }
    const logError = (prefix, error) => {
      logMessage(source, `${prefix} due to ${getErrorMessage(error)}`);
    };
    let element;
    try {
      element = document.createElement(tagName);
      element.textContent = textContent;
    } catch (e) {
      logError(`Cannot create element with tag name '${tagName}'`, e);
      return;
    }
    let attributes = [];
    try {
      attributes = parseAttributePairs(attributePairs);
    } catch (e) {
      logError(`Cannot parse attributePairs param: '${attributePairs}'`, e);
      return;
    }
    attributes.forEach((attr) => {
      try {
        element.setAttribute(attr.name, attr.value);
      } catch (e) {
        logError(`Cannot set attribute '${attr.name}' with value '${attr.value}'`, e);
      }
    });
    let timerId;
    let elementCreated = false;
    let elementRemoved = false;
    const findParentAndAppendEl = (parentElSelector, el, removeElDelayMs) => {
      let parentEl;
      try {
        parentEl = document.querySelector(parentElSelector);
      } catch (e) {
        logError(`Cannot find parent element by selector '${parentElSelector}'`, e);
        return false;
      }
      if (!parentEl) {
        logMessage(source, `No parent element found by selector: '${parentElSelector}'`);
        return false;
      }
      try {
        if (!parentEl.contains(el)) {
          parentEl.append(el);
        }
        if (el instanceof HTMLIFrameElement && el.contentWindow) {
          el.contentWindow.name = IFRAME_WINDOW_NAME;
        }
        elementCreated = true;
        hit(source);
      } catch (e) {
        logError(`Cannot append child to parent by selector '${parentElSelector}'`, e);
        return false;
      }
      if (!nativeIsNaN(removeElDelayMs)) {
        timerId = setTimeout(() => {
          el.remove();
          elementRemoved = true;
          clearTimeout(timerId);
        }, removeElDelayMs);
      }
      return true;
    };
    if (!findParentAndAppendEl(parentSelector, element, cleanupDelayMs)) {
      observeDocumentWithTimeout((mutations, observer) => {
        if (elementRemoved || elementCreated || findParentAndAppendEl(parentSelector, element, cleanupDelayMs)) {
          observer.disconnect();
        }
      });
    }
  }
  var trustedCreateElementNames = [
    "trusted-create-element"
    // trusted scriptlets support no aliases
  ];
  trustedCreateElement.primaryName = trustedCreateElementNames[0];
  trustedCreateElement.injections = [
    hit,
    logMessage,
    observeDocumentWithTimeout,
    nativeIsNaN,
    parseAttributePairs,
    getErrorMessage
  ];
  return __toCommonJS(trusted_create_element_exports);
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
    console.warn("No callable function found for scriptlet module: trusted-create-element");
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
