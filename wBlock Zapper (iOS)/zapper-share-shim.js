// Stands in for the WebExtension APIs zapper-content.js uses, so the share
// sheet action runs the same Zapper in its own web view (#1074). Runs in an
// isolated content world; the native side fills in the strings below.
(() => {
  'use strict';

  const messages = WBLOCK_MESSAGES;
  const listeners = new Set();
  const storage = new Map();
  const native = (message) => window.webkit.messageHandlers.wblock.postMessage(message);

  const dispatch = async (message) => {
    const replies = await Promise.all([...listeners].map((listener) => listener(message, {})));
    return replies.find((reply) => reply !== undefined);
  };

  const relay = {
    'wblock:getSiteDisabledState': async ({ host }) => {
      const response = await native({ action: 'getSiteDisabledState', host });
      return { ok: true, disabled: Boolean(response && response.disabled) };
    },
    'wblock:zapper:getRules': ({ hostname }) => native({ action: 'getZapperRules', hostname }),
    'wblock:zapper:syncRules': ({ hostname, rules }) => native({ action: 'syncZapperRules', hostname, rules }),
    'wblock:zapper:setDisabled': ({ hostname, disabled }) =>
      native({ action: 'setSiteZapperDisabled', hostname, disabled: disabled === true }),
    'wblock:zapper:broadcastReload': async () => {
      await dispatch({ type: 'wblock:zapper:reloadRules' });
      return { ok: true };
    },
  };

  window.wblockShareDispatch = dispatch;
  window.browser = {
    i18n: {
      getMessage(key, substitutions) {
        const message = messages[key];
        if (typeof message !== 'string') return '';
        const values = substitutions == null ? [] : [].concat(substitutions);
        return message.replace(/\$(\d)/g, (match, index) => values[index - 1] ?? match);
      },
    },
    storage: {
      local: {
        async get(keys) {
          const wanted = keys == null ? [...storage.keys()] : [].concat(keys);
          return Object.fromEntries(wanted.filter((key) => storage.has(key)).map((key) => [key, storage.get(key)]));
        },
        async set(items) {
          for (const [key, value] of Object.entries(items)) storage.set(key, value);
        },
        async remove(keys) {
          for (const key of [].concat(keys)) storage.delete(key);
        },
      },
    },
    runtime: {
      onMessage: {
        addListener: (listener) => listeners.add(listener),
        removeListener: (listener) => listeners.delete(listener),
        hasListener: (listener) => listeners.has(listener),
      },
      async sendMessage(message) {
        const handler = message && relay[message.action];
        if (!handler) throw new Error(`Unsupported message: ${message && message.action}`);
        return handler(message);
      },
    },
  };
})();
