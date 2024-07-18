// document.addEventListener(
//     "DOMContentLoaded",
//     function(event) { safari.extension.dispatchMessage("Hello World!"); });

/**
 * AdGuard Extension Script
 *
 * This content-script serves some assistant requests.
 */

/* global safari */
if (window.top === window) {
    (async () => {
        /**
         * Handles extension message
         * @param {Event} event
         */
        const handleMessage = async (event) => {
            try {
                switch (event.name) {
                case "blockElementPing":
                    safari.extension.dispatchMessage("blockElementPong");
                    break;
                case "blockElement":
                    await handleBlockElement();
                    break;
                default:
                    break;
                }
            } catch (e) {
                console.error(e);
            }
        };
        /**
         * Handles zapper requests. TODO
         */
        const handleBlockElement = async () => {
            if (!document.getElementById("adguard.assistant.embedded")) {
                const newElement = document.createElement("script");
                newElement.src =
                    `${safari.extension.baseURI}assistant.embedded.js`;
                newElement.id = "adguard.assistant.embedded";
                newElement.charset = 'utf-8';
                document.head.appendChild(newElement);
            }
            const runner =
                document.getElementById("adguard.assistant.embedded.runner");
            if (runner && runner.parentNode) {
                runner.parentNode.removeChild(runner);
            }
            const runnerElement = document.createElement("script");
            runnerElement.src = `${safari.extension.baseURI}zapper.runner.js`;
            runnerElement.id = "webshield.zapper.embedded.runner";
            runnerElement.addEventListener(
                "zapper.runner-response", (event) => {
                    safari.extension.dispatchMessage("ruleResponse",
                                                     event.detail);
                });
            document.head.appendChild(runnerElement);
        };
        /**
         * Add event listener
         */
        document.addEventListener(
            "DOMContentLoaded",
            () => { safari.self.addEventListener("message", handleMessage); });
    })();
}
// Script for intercepting adguard subscribe links
(async () => {
    if (!(document instanceof HTMLDocument)) {
        return;
    }
    const getSubscriptionParams = (urlParams) => {
        let title = null;
        let url = null;
        urlParams.forEach(param => {
            const [key, value] = param.split('=', 2);
            if (value) {
                switch (key) {
                case 'title':
                    title = decodeURIComponent(value);
                    break;
                case 'location':
                    url = decodeURIComponent(value);
                    break;
                default:
                    break;
                }
            }
        });
        return {title, url};
    };
    const onLinkClicked = (e) => {
        if (e.button === 2) {
            return;
        }
        let target = e.target;
        while (target) {
            if (target instanceof HTMLAnchorElement) {
                break;
            }
            target = target.parentNode;
        }
        if (!target) {
            return;
        }
        if (target.protocol === 'http:' || target.protocol === 'https:') {
            if (target.host !== 'subscribe.adblockplus.org' ||
                target.pathname !== '/') {
                return;
            }
        } else if (!(/^abp:\/*subscribe\/*\?/i.test(target.href) ||
                     /^adguard:\/*subscribe\/*\?/i.test(target.href))) {
            return;
        }
        e.preventDefault();
        e.stopPropagation();
        const urlParams =
            target.search
                ? target.search.substring(1).replace(/&amp;/g, '&').split('&')
                : target.href.substring(target.href.indexOf('?') + 1)
                      .replace(/&amp;/g, '&')
                      .split('&');
        const {title, url} = getSubscriptionParams(urlParams);
        if (!url) {
            return;
        }
        safari.extension.dispatchMessage(
            'addFilterSubscription',
            {url : url.trim(), title : (title || url).trim()});
    };
    document.addEventListener('click', onLinkClicked);
})();
