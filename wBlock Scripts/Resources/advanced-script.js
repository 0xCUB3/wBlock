//
//  t.js
//  WebShield
//
//  Created by Arjun on 2024-07-13.
//
/* global safari, ExtendedCss */
(() => {
    /**
     * Executes code in the context of the page via a new script tag and text
     * content.
     * @param {string} code - String of scripts to be executed.
     * @returns {boolean} Returns true if code was executed, otherwise returns
     *     false.
     */
    const executeScriptsViaTextContent = (code) => {
        const scriptTag = document.createElement('script');
        scriptTag.type = 'text/javascript';
        scriptTag.textContent = code;
        const parent = document.head || document.documentElement;
        parent.appendChild(scriptTag);
        if (scriptTag.parentNode) {
            scriptTag.parentNode.removeChild(scriptTag);
            return false;
        }
        return true;
    };
    /**
     * Executes code in the context of the page via a new script tag and blob.
     * We use this way as a fallback if we fail to inject via textContent.
     * @param {string} code - String of scripts to be executed.
     * @returns {boolean} Returns true if code was executed, otherwise returns
     *     false.
     */
    const executeScriptsViaBlob = (code) => {
        const blob = new Blob([ code ], {type : 'text/javascript'});
        const url = URL.createObjectURL(blob);
        const scriptTag = document.createElement('script');
        scriptTag.src = url;
        const parent = document.head || document.documentElement;
        parent.appendChild(scriptTag);
        URL.revokeObjectURL(url);
        if (scriptTag.parentNode) {
            scriptTag.parentNode.removeChild(scriptTag);
            return false;
        }
        return true;
    };
    /**
     * Execute scripts in a page context and clean up itself when execution
     * completes.
     * @param {string[]} scripts - Array of scripts to execute.
     * @param {boolean} verbose - Enable verbose logging.
     */
    const executeScripts = async (scripts = [], verbose) => {
        logMessage(verbose, "Executing scripts...");
        scripts.unshift('(function () { try {');
        scripts.push(';document.currentScript.remove();');
        scripts.push(
                     "} catch (ex) { console.error('Error executing AG js: ' + ex); } })();");
        const code = scripts.join('\r\n');
        if (!executeScriptsViaTextContent(code)) {
            logMessage(verbose, 'Unable to inject via text content');
            if (!executeScriptsViaBlob(code)) {
                logMessage(verbose, 'Unable to inject via blob');
            }
        }
    };
    /**
     * Applies JS injections.
     * @param {string[]} scripts - Array with JS scripts.
     * @param {boolean} verbose - Enable verbose logging.
     */
    const applyScripts = async (scripts, verbose) => {
        if (!scripts || scripts.length === 0)
            return;
        logMessage(verbose, "Applying script injections...");
        logMessage(verbose, `scripts length: ${scripts.length}`);
        await executeScripts(scripts.reverse(), verbose);
    };
    /**
     * Protects specified style element from changes to the current document.
     * Adds a mutation observer, which re-adds our rules if they were removed.
     * @param {HTMLElement} protectStyleEl - Protected style element.
     */
    const protectStyleElementContent = (protectStyleEl) => {
        const MutationObserver =
        window.MutationObserver || window.WebKitMutationObserver;
        if (!MutationObserver)
            return;
        const innerObserver = new MutationObserver((mutations) => {
            for (const m of mutations) {
                if (protectStyleEl.hasAttribute('mod') &&
                    protectStyleEl.getAttribute('mod') === 'inner') {
                    protectStyleEl.removeAttribute('mod');
                    break;
                }
                protectStyleEl.setAttribute('mod', 'inner');
                let isProtectStyleElModified = false;
                if (m.removedNodes.length > 0) {
                    for (const node of m.removedNodes) {
                        isProtectStyleElModified = true;
                        protectStyleEl.appendChild(node);
                    }
                } else if (m.oldValue) {
                    isProtectStyleElModified = true;
                    protectStyleEl.textContent = m.oldValue;
                }
                if (!isProtectStyleElModified) {
                    protectStyleEl.removeAttribute('mod');
                }
            }
        });
        innerObserver.observe(protectStyleEl, {
            childList : true,
            characterData : true,
            subtree : true,
            characterDataOldValue : true,
        });
    };
    /**
     * Applies CSS stylesheet.
     * @param {string[]} styleSelectors - Array of stylesheets or selectors.
     * @param {boolean} verbose - Enable verbose logging.
     */
    const applyCss = async (styleSelectors, verbose) => {
        if (!styleSelectors || !styleSelectors.length)
            return;
        logMessage(verbose, "Applying CSS stylesheets...");
        logMessage(verbose, `css length: ${styleSelectors.length}`);
        const styleElement = document.createElement('style');
        styleElement.type = 'text/css';
        (document.head || document.documentElement).appendChild(styleElement);
        for (const selector of styleSelectors.map(s => s.trim())) {
            styleElement.sheet.insertRule(selector);
        }
        protectStyleElementContent(styleElement);
    };
    /**
     * Applies Extended CSS stylesheet.
     * @param {string[]} extendedCss - Array with ExtendedCss stylesheets.
     * @param {boolean} verbose - Enable verbose logging.
     */
    const applyExtendedCss = async (extendedCss, verbose) => {
        if (!extendedCss || !extendedCss.length)
            return;
        logMessage(verbose, "Applying extended CSS stylesheets...");
        logMessage(verbose, `extended css length: ${extendedCss.length}`);
        const cssRules = extendedCss.filter(s => s.length > 0)
        .map(s => s.trim())
        .map(s => (s[s.length - 1] !== '}'
                   ? `${s} {display:none!important;}`
                   : s));
        const extCss = new ExtendedCss({cssRules});
        extCss.apply();
    };
    /**
     * Applies scriptlets.
     * @param {string[]} scriptletsData - Array with scriptlets data.
     * @param {boolean} verbose - Enable verbose logging.
     */
    const applyScriptlets = async (scriptletsData, verbose) => {
        if (!scriptletsData || !scriptletsData.length)
            return;
        logMessage(verbose, "Applying scriptlets...");
        logMessage(verbose, `scriptlets length: ${scriptletsData.length}`);
        const scriptletExecutableScripts = scriptletsData.map(s => {
            const param = JSON.parse(s);
            param.engine = "safari-extension";
            if (verbose)
                param.verbose = true;
            let code = '';
            try {
                code = scriptlets && scriptlets.invoke(param);
            } catch (e) {
                logMessage(verbose, e.message);
            }
            return code;
        });
        await executeScripts(scriptletExecutableScripts, verbose);
    };
    /**
     * Applies injected script and CSS.
     * @param {Object} data - Data containing scripts and CSS to be applied.
     * @param {boolean} verbose - Enable verbose logging.
     */
    const applyAdvancedBlockingData = async (data, verbose) => {
        logMessage(verbose, 'Applying scripts and css..');
        logMessage(verbose, `Frame url: ${window.location.href}`);
        await Promise.all([
            applyScripts(data.scripts, verbose),
            applyCss(data.cssInject, verbose),
            applyExtendedCss(data.cssExtended, verbose),
            applyScriptlets(data.scriptlets, verbose)
        ]);
        logMessage(verbose, 'Applying scripts and css - done');
        safari.self.removeEventListener('message', handleMessage);
    };
    /**
     * Logs a message if verbose is true.
     * @param {boolean} verbose - Enable verbose logging.
     * @param {string} message - Message to be logged.
     */
    const logMessage = (verbose, message) => {
        if (verbose) {
            console.log(`(WebShield Extra) ${message}`);
        }
    };
    /**
     * Handles event from application.
     * @param {Event} event - Event to be handled.
     */
    const handleMessage = async (event) => {
        if (event.name === 'advancedBlockingData') {
            try {
                const data = JSON.parse(event.message.data);
                const verbose = JSON.parse(event.message.verbose);
                logMessage(verbose, "Received advancedBlockingData message...");
                logMessage(verbose, "Message Data (below):");
                logMessage(verbose, data);
                if (window.location.href === event.message.url) {
                    await applyAdvancedBlockingData(data, verbose);
                }
            } catch (e) {
                console.error(e);
            }
        }
    };
    /**
     * Fixes some troubles with Gmail and scrolling on various websites.
     * https://github.com/AdguardTeam/AdGuardForSafari/issues/433
     * https://github.com/AdguardTeam/AdGuardForSafari/issues/441
     */
    if (document instanceof HTMLDocument) {
        if (window.location.href && window.location.href.startsWith('http')) {
            safari.self.addEventListener('message', handleMessage);
            logMessage(true, "Sending getAdvancedBlockingData message...");
            safari.extension.dispatchMessage('getAdvancedBlockingData',
                                             {url : window.location.href});
        }
    }
})()
