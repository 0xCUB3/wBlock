// content.js
(async () => {
  const LOG_PREFIX = "[wBlock Scripts]";

  const log = {
    info: (msg, ...args) => console.log(`${LOG_PREFIX} ${msg}`, ...args),
    error: (msg, ...args) => console.error(`${LOG_PREFIX} ${msg}`, ...args),
    warn: (msg, ...args) => console.warn(`${LOG_PREFIX} ${msg}`, ...args),
  };

  const executeScript = (code) => {
    // log.info(
    //   "Injecting script:",
    //   code.slice(0, 150) + "...",
    // );
    const scriptElement = document.createElement("script");
    scriptElement.textContent = code;
    const container = document.head || document.documentElement;
    container.prepend(scriptElement);
    // Remove after a short delay so that the script has executed.
    setTimeout(() => {
      container.removeChild(scriptElement);
    }, 0);
  };

  const executeScripts = (scripts = []) => {
    const code = scripts.join("\r\n");
    executeScript(code);
  };

  const computeSHA256Hash = async (data) => {
    const encoder = new TextEncoder();
    const dataBuffer = encoder.encode(data);
    const hashBuffer = await crypto.subtle.digest("SHA-256", dataBuffer);
    // Convert the ArrayBuffer to a hex string
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const hashHex = hashArray
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
    return hashHex;
  };

  const injectedScriptRegistry = new Map();

  const applyScripts = async (scripts) => {
    if (!scripts?.length) return;
    log.info(`(applyScripts) Applying scripts...`);
    log.info(`(applyScripts) scripts length: ${scripts.length}`);

    const newScript = scripts.join("\n");
    const scriptHash = await computeSHA256Hash(newScript);

    if (injectedScriptRegistry.has(scriptHash)) {
      log.info(
        `(applyScripts) Scripts with hash ${scriptHash} is already injected. Skipping.`,
      );
      return;
    }

    await onLoad(false);
    executeScripts(scripts.reverse());
    log.info(`(applyScripts) Applied scripts`);

    injectedScriptRegistry.set(scriptHash, true);
    log.info(`(applyScripts) Added scripts to script registry`);
  };

  // const protectStyleElementContent = (protectStyleEl) => {
  //   const MutationObserver =
  //     window.MutationObserver || window.WebKitMutationObserver;
  //   if (!MutationObserver) {
  //     return;
  //   }
  //   /* observer, which observe protectStyleEl inner changes, without deleting styleEl */
  //   const innerObserver = new MutationObserver((mutations) => {
  //     for (let i = 0; i < mutations.length; i += 1) {
  //       const m = mutations[i];
  //       if (
  //         protectStyleEl.hasAttribute("mod") &&
  //         protectStyleEl.getAttribute("mod") === "inner"
  //       ) {
  //         protectStyleEl.removeAttribute("mod");
  //         break;
  //       }

  //       protectStyleEl.setAttribute("mod", "inner");
  //       let isProtectStyleElModified = false;

  //       /**
  //        * further, there are two mutually exclusive situations: either there were changes
  //        * the text of protectStyleEl, either there was removes a whole child "text"
  //        * element of protectStyleEl we'll process both of them
  //        */
  //       if (m.removedNodes.length > 0) {
  //         for (let j = 0; j < m.removedNodes.length; j += 1) {
  //           isProtectStyleElModified = true;
  //           protectStyleEl.appendChild(m.removedNodes[j]);
  //         }
  //       } else if (m.oldValue) {
  //         isProtectStyleElModified = true;
  //         protectStyleEl.textContent = m.oldValue;
  //       }

  //       if (!isProtectStyleElModified) {
  //         protectStyleEl.removeAttribute("mod");
  //       }
  //     }
  //   });

  //   innerObserver.observe(protectStyleEl, {
  //     childList: true,
  //     characterData: true,
  //     subtree: true,
  //     characterDataOldValue: true,
  //   });
  // };

  const injectedCssRegistry = new Map();

  const applyCss = async (styles) => {
    if (!styles?.length) return;
    log.info(`(applyCss) Applying css...`);
    log.info(`(applyCss) css length: ${styles.length}`);

    const newCss = styles.join("\n");
    const cssHash = await computeSHA256Hash(newCss);

    if (injectedCssRegistry.has(cssHash)) {
      log.info(
        `(applyCss) Css with hash ${cssHash} is already injected. Skipping.`,
      );
      return;
    }

    await onLoad(true);
    const styleElement = document.createElement("style");
    styleElement.textContent = styles.join("\n");
    styleElement.setAttribute("type", "text/css");
    document.head.appendChild(styleElement);
    log.info(`(applyCss) Applied css`);

    injectedCssRegistry.set(cssHash, true);
    log.info(`(applyCss) Added css to css registry`);
  };

    // Conditional Wait
    const onLoad = (waitForStylesheets) => {
        return new Promise((resolve) => {
            if (!waitForStylesheets) {
                // For scripts/scriptlets, resolve immediately if DOM is already interactive/complete,
                // or wait only until DOMContentLoaded otherwise.
                if (document.readyState !== 'loading') {
                    resolve();
                } else {
                    document.addEventListener('DOMContentLoaded', resolve, { once: true });
                }
            } else {
                // For CSS, wait for the 'load' event as before.
                if (document.readyState === 'complete') {
                    resolve();
                } else {
                    window.addEventListener('load', resolve, { once: true });
                }
            }
        });
    };

  const injectedExtendedCssRegistry = new Map();

  const applyExtendedCss = async (extendedCss) => {
    if (!extendedCss?.length) return;
    log.info(`(applyExtendedCss) Applying ExtendedCss...`);
    log.info(`(applyExtendedCss) ExtendedCss length: ${extendedCss.length}`);

    const newExtendedCss = extendedCss.join("\n");
    const extendedCssHash = await computeSHA256Hash(newExtendedCss);

    if (injectedExtendedCssRegistry.has(extendedCssHash)) {
      log.info(
        `(applyExtendedCss) ExtendedCss with hash ${extendedCssHash} is already injected. Skipping.`,
      );
      return;
    }

    try {
      if (typeof ExtendedCss === "undefined") {
        throw new Error("ExtendedCss library not loaded");
      }
      const cssRules = extendedCss
        .filter((s) => s.length > 0)
        .map((s) => s.trim())
        .map((s) => (s.endsWith("}") ? s : `${s} {display:none!important;}`));
      const extCss = new ExtendedCss({ cssRules });
      extCss.apply();
    } catch (e) {
      log.error(`(applyExtendedCss) ExtendedCss error:`, e);
    }
    log.info(`(applyExtendedCss) Applied ExtendedCss`);

    injectedExtendedCssRegistry.set(extendedCssHash, true);
    log.info(`(applyExtendedCss) Added ExtendedCss to ExtendedCss registry`);
  };

  const requestScriptlets = async (scriptlets) => {
    try {
      const validated = scriptlets
        .filter((s) => s && typeof s === "object")
        .map((s) => ({
          name: s.name || "unknown-scriptlet",
          args: Array.isArray(s.args) ? s.args : [],
          sourceConfig: {
            engine: "extension",
            version: "1.0.0",
            verbose: true,
            ...(s.sourceConfig || {}),
          },
        }));

      const response = await browser.runtime.sendMessage({
        action: "getScriptlets",
        scriptlets: validated,
      });

      return response || [];
    } catch (error) {
      log.error(`(requestScriptlets) Scriptlet request failed:`, error);
      return [];
    }
  };

  const injectedScriptletRegistry = new Map();

  const applyScriptlets = async (scriptletsData) => {
    if (!scriptletsData?.length) return;
    log.info(`(applyScriptlets) Applying scriptlets...`);
    log.info(`(applyScriptlets) scriptlets length: ${scriptletsData.length}`);

    const newScriptlets = scriptletsData.join("\n");
    const scriptletHash = await computeSHA256Hash(newScriptlets);

    if (injectedScriptletRegistry.has(scriptletHash)) {
      log.info(
        `(applyScriptlets) Scriptlets with hash ${scriptletHash} is already injected. Skipping.`,
      );
      return;
    }

    // Parse JSON strings to objects (if needed)
    const parsedScriptlets = scriptletsData
      .map((s) => {
        try {
          return JSON.parse(s);
        } catch (e) {
          log.error("(applyScriptlets) Failed to parse scriptlet:", s, e);
          return null;
        }
      })
      .filter(Boolean);

    const scriptletPayloads = (await requestScriptlets(parsedScriptlets)) || [];
    // For each payload, inject the code and execute the registered scriptlet function (i.e. main)
    scriptletPayloads.forEach(({ code, source, args }) => {
      const executionCode = `
        (function() {
          console.info("[wBlock Scripts] Starting scriptlet: ${source.name}");
          ${code}
          try {
            var fn = window.adguardScriptlets["${source.name}"];
            if (typeof fn !== "function") {
              throw new Error("[wBlock Scripts] Scriptlet function not found for ${source.name}");
            }
            // Wrap the call in a try-catch to log any synchronous errors.
            try {
              fn(${JSON.stringify(source)}, ...${JSON.stringify(args)});
              console.info("[wBlock Scripts] Successfully executed scriptlet: ${source.name}");
            } catch(innerError) {
              console.error("[wBlock Scripts] Error during scriptlet call (" + "${source.name}" + "):", innerError);
            }
          } catch (e) {
            console.error("[wBlock Scripts] Scriptlet error for ${source.name}:", e);
          }
        })();
      `;

      // Re-use the helper that injects a <script> element with inline code.
      executeScript(executionCode);
    });
    log.info(`(applyScriptlets) Applied scriptlets`);

    injectedScriptletRegistry.set(scriptletHash, true);
    log.info(`(applyScriptlets) Added Scriptlets to scriptlet registry`);
  };


    const applyAdvancedBlockingData = async (data) => {
        log.info(
          `(applyAdvancedBlockingData) Applying scriptlets, scripts, css, ExtendedCss...`,
        );
        log.info(`(applyAdvancedBlockingData) Frame url: ${window.location.href}`);
        log.info(`(applyAdvancedBlockingData) Data: `, data);

        await applyScriptlets(data?.scriptlets);
        await applyScripts(data?.scripts);
        await applyCss(data?.cssInject);
        await applyExtendedCss(data?.cssExtended);

        log.info(
          `(applyAdvancedBlockingData) Applied scriptlets, scripts, css, ExtendedCss`,
        );
      };

  // Simplified request handler
  const requestBlockingData = async (url) => {
    try {
      const response = await browser.runtime.sendMessage({
        action: "getAdvancedBlockingData",
        url: url,
        fromBeginning: true,
      });

      if (response?.error) throw new Error(response.error);
      if (!response?.data) throw new Error("No data received");

      return typeof response.data === "string"
        ? JSON.parse(response.data)
        : response.data;
    } catch (error) {
      log.error(`(requestBlockingData) Request failed:`, error);
      throw error;
    }
  };

  // Initialization
  const initializeAdvancedBlocking = async () => {
    if (!document.documentElement || !location.protocol.startsWith("http"))
      return;

    try {
      const data = await requestBlockingData(location.href);
      if (data) await applyAdvancedBlockingData(data);
    } catch (error) {
      log.error(`(initializeAdvancedBlocking) Initialization failed:`, error);
    }
  };

  await initializeAdvancedBlocking();
})();
