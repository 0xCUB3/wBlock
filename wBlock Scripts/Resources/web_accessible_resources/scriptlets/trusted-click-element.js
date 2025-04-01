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

  // Scriptlets/src/scriptlets/trusted-click-element.ts
  var trusted_click_element_exports = {};
  __export(trusted_click_element_exports, {
    trustedClickElement: () => trustedClickElement,
    trustedClickElementNames: () => trustedClickElementNames
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

  // Scriptlets/src/helpers/cookie-utils.ts
  var parseCookieString = (cookieString) => {
    const COOKIE_DELIMITER = "=";
    const COOKIE_PAIRS_DELIMITER = ";";
    const cookieChunks = cookieString.split(COOKIE_PAIRS_DELIMITER);
    const cookieData = {};
    cookieChunks.forEach((singleCookie) => {
      let cookieKey;
      let cookieValue = "";
      const delimiterIndex = singleCookie.indexOf(COOKIE_DELIMITER);
      if (delimiterIndex === -1) {
        cookieKey = singleCookie.trim();
      } else {
        cookieKey = singleCookie.slice(0, delimiterIndex).trim();
        cookieValue = singleCookie.slice(delimiterIndex + 1);
      }
      cookieData[cookieKey] = cookieValue || null;
    });
    return cookieData;
  };

  // Scriptlets/src/helpers/string-utils.ts
  var toRegExp = (rawInput) => {
    const input = rawInput || "";
    const DEFAULT_VALUE = ".?";
    const FORWARD_SLASH = "/";
    if (input === "") {
      return new RegExp(DEFAULT_VALUE);
    }
    const delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
    const flagsPart = input.substring(delimiterIndex + 1);
    const regExpPart = input.substring(0, delimiterIndex + 1);
    const isValidRegExpFlag = (flag) => {
      if (!flag) {
        return false;
      }
      try {
        new RegExp("", flag);
        return true;
      } catch (ex) {
        return false;
      }
    };
    const getRegExpFlags = (regExpStr, flagsStr) => {
      if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
        return flagsStr;
      }
      return "";
    };
    const flags = getRegExpFlags(regExpPart, flagsPart);
    if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
      const regExpInput = flags ? regExpPart : input;
      return new RegExp(regExpInput.slice(1, -1), flags);
    }
    const escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    return new RegExp(escaped);
  };
  var parseMatchArg = (match) => {
    const INVERT_MARKER = "!";
    const isInvertedMatch = match ? match?.startsWith(INVERT_MARKER) : false;
    const matchValue = isInvertedMatch ? match.slice(1) : match;
    const matchRegexp = toRegExp(matchValue);
    return { isInvertedMatch, matchRegexp, matchValue };
  };

  // Scriptlets/src/helpers/open-shadow-dom-utils.ts
  function doesElementContainText(element, matchRegexp) {
    const { textContent } = element;
    if (!textContent) {
      return false;
    }
    return matchRegexp.test(textContent);
  }
  function findElementWithText(rootElement, selector, matchRegexp) {
    const elements = rootElement.querySelectorAll(selector);
    for (let i = 0; i < elements.length; i += 1) {
      if (doesElementContainText(elements[i], matchRegexp)) {
        return elements[i];
      }
    }
    return null;
  }
  function queryShadowSelector(selector, context = document.documentElement, textContent = null) {
    const SHADOW_COMBINATOR = " >>> ";
    const pos = selector.indexOf(SHADOW_COMBINATOR);
    if (pos === -1) {
      if (textContent) {
        return findElementWithText(context, selector, textContent);
      }
      return context.querySelector(selector);
    }
    const shadowHostSelector = selector.slice(0, pos).trim();
    const elem = context.querySelector(shadowHostSelector);
    if (!elem || !elem.shadowRoot) {
      return null;
    }
    const shadowRootSelector = selector.slice(pos + SHADOW_COMBINATOR.length).trim();
    return queryShadowSelector(shadowRootSelector, elem.shadowRoot, textContent);
  }

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

  // Scriptlets/src/scriptlets/trusted-click-element.ts
  function trustedClickElement(source, selectors, extraMatch = "", delay = NaN, reload = "") {
    if (!selectors) {
      return;
    }
    const SHADOW_COMBINATOR = " >>> ";
    const OBSERVER_TIMEOUT_MS = 1e4;
    const THROTTLE_DELAY_MS = 20;
    const STATIC_CLICK_DELAY_MS = 150;
    const STATIC_RELOAD_DELAY_MS = 500;
    const COOKIE_MATCH_MARKER = "cookie:";
    const LOCAL_STORAGE_MATCH_MARKER = "localStorage:";
    const TEXT_MATCH_MARKER = "containsText:";
    const RELOAD_ON_FINAL_CLICK_MARKER = "reloadAfterClick";
    const SELECTORS_DELIMITER = ",";
    const COOKIE_STRING_DELIMITER = ";";
    const COLON = ":";
    const EXTRA_MATCH_DELIMITER = /(,\s*){1}(?=!?cookie:|!?localStorage:|containsText:)/;
    const sleep = (delayMs) => {
      return new Promise((resolve) => {
        setTimeout(resolve, delayMs);
      });
    };
    if (selectors.includes(SHADOW_COMBINATOR)) {
      const attachShadowWrapper = (target, thisArg, argumentsList) => {
        const mode = argumentsList[0]?.mode;
        if (mode === "closed") {
          argumentsList[0].mode = "open";
        }
        return Reflect.apply(target, thisArg, argumentsList);
      };
      const attachShadowHandler = {
        apply: attachShadowWrapper
      };
      window.Element.prototype.attachShadow = new Proxy(window.Element.prototype.attachShadow, attachShadowHandler);
    }
    let parsedDelay;
    if (delay) {
      parsedDelay = parseInt(String(delay), 10);
      const isValidDelay = !Number.isNaN(parsedDelay) || parsedDelay < OBSERVER_TIMEOUT_MS;
      if (!isValidDelay) {
        const message = `Passed delay '${delay}' is invalid or bigger than ${OBSERVER_TIMEOUT_MS} ms`;
        logMessage(source, message);
        return;
      }
    }
    let canClick = !parsedDelay;
    const cookieMatches = [];
    const localStorageMatches = [];
    let textMatches = "";
    let isInvertedMatchCookie = false;
    let isInvertedMatchLocalStorage = false;
    if (extraMatch) {
      const parsedExtraMatch = extraMatch.split(EXTRA_MATCH_DELIMITER).map((matchStr) => matchStr.trim());
      parsedExtraMatch.forEach((matchStr) => {
        if (matchStr.includes(COOKIE_MATCH_MARKER)) {
          const { isInvertedMatch, matchValue } = parseMatchArg(matchStr);
          isInvertedMatchCookie = isInvertedMatch;
          const cookieMatch = matchValue.replace(COOKIE_MATCH_MARKER, "");
          cookieMatches.push(cookieMatch);
        }
        if (matchStr.includes(LOCAL_STORAGE_MATCH_MARKER)) {
          const { isInvertedMatch, matchValue } = parseMatchArg(matchStr);
          isInvertedMatchLocalStorage = isInvertedMatch;
          const localStorageMatch = matchValue.replace(LOCAL_STORAGE_MATCH_MARKER, "");
          localStorageMatches.push(localStorageMatch);
        }
        if (matchStr.includes(TEXT_MATCH_MARKER)) {
          const { matchValue } = parseMatchArg(matchStr);
          const textMatch = matchValue.replace(TEXT_MATCH_MARKER, "");
          textMatches = textMatch;
        }
      });
    }
    if (cookieMatches.length > 0) {
      const parsedCookieMatches = parseCookieString(cookieMatches.join(COOKIE_STRING_DELIMITER));
      const parsedCookies = parseCookieString(document.cookie);
      const cookieKeys = Object.keys(parsedCookies);
      if (cookieKeys.length === 0) {
        return;
      }
      const cookiesMatched = Object.keys(parsedCookieMatches).every((key) => {
        const valueMatch = parsedCookieMatches[key] ? toRegExp(parsedCookieMatches[key]) : null;
        const keyMatch = toRegExp(key);
        return cookieKeys.some((cookieKey) => {
          const keysMatched = keyMatch.test(cookieKey);
          if (!keysMatched) {
            return false;
          }
          if (!valueMatch) {
            return true;
          }
          const parsedCookieValue = parsedCookies[cookieKey];
          if (!parsedCookieValue) {
            return false;
          }
          return valueMatch.test(parsedCookieValue);
        });
      });
      const shouldRun = cookiesMatched !== isInvertedMatchCookie;
      if (!shouldRun) {
        return;
      }
    }
    if (localStorageMatches.length > 0) {
      const localStorageMatched = localStorageMatches.every((str) => {
        const itemValue = window.localStorage.getItem(str);
        return itemValue || itemValue === "";
      });
      const shouldRun = localStorageMatched !== isInvertedMatchLocalStorage;
      if (!shouldRun) {
        return;
      }
    }
    const textMatchRegexp = textMatches ? toRegExp(textMatches) : null;
    let selectorsSequence = selectors.split(SELECTORS_DELIMITER).map((selector) => selector.trim());
    const createElementObj = (element, selector) => {
      return {
        element: element || null,
        clicked: false,
        selectorText: selector || null
      };
    };
    const elementsSequence = Array(selectorsSequence.length).fill(createElementObj(null));
    const findAndClickElement = (elementObj) => {
      try {
        if (!elementObj.selectorText) {
          return;
        }
        const element = queryShadowSelector(elementObj.selectorText);
        if (!element) {
          logMessage(source, `Could not find element: '${elementObj.selectorText}'`);
          return;
        }
        element.click();
        elementObj.clicked = true;
      } catch (error) {
        logMessage(source, `Could not click element: '${elementObj.selectorText}'`);
      }
    };
    let shouldReloadAfterClick = false;
    let reloadDelayMs = STATIC_RELOAD_DELAY_MS;
    if (reload) {
      const reloadSplit = reload.split(COLON);
      const reloadMarker = reloadSplit[0];
      const reloadValue = reloadSplit[1];
      if (reloadMarker !== RELOAD_ON_FINAL_CLICK_MARKER) {
        logMessage(source, `Passed reload option '${reload}' is invalid`);
        return;
      }
      if (reloadValue) {
        const passedReload = Number(reloadValue);
        if (Number.isNaN(passedReload)) {
          logMessage(source, `Passed reload delay value '${passedReload}' is invalid`);
          return;
        }
        if (passedReload > OBSERVER_TIMEOUT_MS) {
          logMessage(source, `Passed reload delay value '${passedReload}' is bigger than maximum ${OBSERVER_TIMEOUT_MS} ms`);
          return;
        }
        reloadDelayMs = passedReload;
      }
      shouldReloadAfterClick = true;
    }
    let canReload = true;
    const clickElementsBySequence = async () => {
      for (let i = 0; i < elementsSequence.length; i += 1) {
        const elementObj = elementsSequence[i];
        if (i >= 1) {
          await sleep(STATIC_CLICK_DELAY_MS);
        }
        if (!elementObj.element) {
          break;
        }
        if (!elementObj.clicked) {
          if (elementObj.element.isConnected) {
            elementObj.element.click();
            elementObj.clicked = true;
          } else {
            findAndClickElement(elementObj);
          }
        }
      }
      const allElementsClicked = elementsSequence.every((elementObj) => elementObj.clicked === true);
      if (allElementsClicked) {
        if (shouldReloadAfterClick && canReload) {
          canReload = false;
          setTimeout(() => {
            window.location.reload();
          }, reloadDelayMs);
        }
        hit(source);
      }
    };
    const handleElement = (element, i, selector) => {
      const elementObj = createElementObj(element, selector);
      elementsSequence[i] = elementObj;
      if (canClick) {
        clickElementsBySequence();
      }
    };
    const fulfillAndHandleSelectors = () => {
      const fulfilledSelectors = [];
      selectorsSequence.forEach((selector, i) => {
        if (!selector) {
          return;
        }
        const element = queryShadowSelector(selector, document.documentElement, textMatchRegexp);
        if (!element) {
          return;
        }
        handleElement(element, i, selector);
        fulfilledSelectors.push(selector);
      });
      selectorsSequence = selectorsSequence.map((selector) => {
        return selector && fulfilledSelectors.includes(selector) ? null : selector;
      });
      return selectorsSequence;
    };
    const findElements = (mutations, observer) => {
      selectorsSequence = fulfillAndHandleSelectors();
      const allSelectorsFulfilled = selectorsSequence.every((selector) => selector === null);
      if (allSelectorsFulfilled) {
        observer.disconnect();
      }
    };
    const initializeMutationObserver = () => {
      const observer = new MutationObserver(throttle(findElements, THROTTLE_DELAY_MS));
      observer.observe(document.documentElement, {
        attributes: true,
        childList: true,
        subtree: true
      });
      setTimeout(() => observer.disconnect(), OBSERVER_TIMEOUT_MS);
    };
    const checkInitialElements = () => {
      const foundElements = selectorsSequence.every((selector) => {
        if (!selector) {
          return false;
        }
        const element = queryShadowSelector(selector, document.documentElement, textMatchRegexp);
        return !!element;
      });
      if (foundElements) {
        fulfillAndHandleSelectors();
      } else {
        initializeMutationObserver();
      }
    };
    checkInitialElements();
    if (parsedDelay) {
      setTimeout(() => {
        clickElementsBySequence();
        canClick = true;
      }, parsedDelay);
    }
  }
  var trustedClickElementNames = [
    "trusted-click-element"
    // trusted scriptlets support no aliases
  ];
  trustedClickElement.primaryName = trustedClickElementNames[0];
  trustedClickElement.injections = [
    hit,
    toRegExp,
    parseCookieString,
    throttle,
    logMessage,
    parseMatchArg,
    queryShadowSelector,
    doesElementContainText,
    findElementWithText
  ];
  return __toCommonJS(trusted_click_element_exports);
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
    console.warn("No callable function found for scriptlet module: trusted-click-element");
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
