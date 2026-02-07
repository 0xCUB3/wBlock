/**
 * Safari App Extension API bridge for the unified content script running
 * inside Safari Web Extensions.
 */

(function () {
  'use strict';

  if (typeof safari !== 'undefined' && safari && safari.extension && safari.self) {
    return;
  }

  if (typeof browser === 'undefined' || !browser.runtime || !browser.runtime.sendMessage) {
    return;
  }

  const listeners = new Set();
  const pendingEvents = [];
  const MAX_PENDING_EVENTS = 32;

  function emitMessage(name, message) {
    const event = { name, message: message || {} };

    if (listeners.size === 0) {
      pendingEvents.push(event);
      if (pendingEvents.length > MAX_PENDING_EVENTS) {
        pendingEvents.splice(0, pendingEvents.length - MAX_PENDING_EVENTS);
      }
      return;
    }

    for (const listener of listeners) {
      try {
        listener(event);
      } catch (error) {
        console.error('[wBlock] Safari bridge listener failed:', error);
      }
    }
  }

  async function dispatchMessage(name, message) {
    try {
      const response = await browser.runtime.sendMessage({
        action: name,
        payload: message || {},
      });

      if (!response) {
        return;
      }

      // Mirror Safari-style message dispatch semantics back to the same page.
      emitMessage(name, response);
    } catch (error) {
      console.error('[wBlock] Safari bridge dispatch failed:', error);
    }
  }

  browser.runtime.onMessage.addListener((message) => {
    if (!message || typeof message !== 'object') {
      return;
    }

    if (message.type === 'wblock:zapper:activate') {
      emitMessage('zapperController', { action: 'activateZapper' });
      return;
    }

    if (message.type === 'wblock:zapper:reloadRules') {
      const hostname = typeof location !== 'undefined' ? location.hostname : '';
      dispatchMessage('zapperController', {
        action: 'loadRules',
        hostname,
      });
    }
  });

  const safariBridge = {
    extension: {
      dispatchMessage,
    },
    self: {
      addEventListener(eventName, listener) {
        if (eventName !== 'message' || typeof listener !== 'function') {
          return;
        }
        listeners.add(listener);
        if (pendingEvents.length) {
          for (const event of pendingEvents.splice(0, pendingEvents.length)) {
            try {
              listener(event);
            } catch (error) {
              console.error('[wBlock] Safari bridge listener failed:', error);
            }
          }
        }
      },
      removeEventListener(eventName, listener) {
        if (eventName !== 'message' || typeof listener !== 'function') {
          return;
        }
        listeners.delete(listener);
      },
    },
  };

  Object.defineProperty(globalThis, 'safari', {
    configurable: true,
    enumerable: true,
    value: safariBridge,
    writable: false,
  });
})();
