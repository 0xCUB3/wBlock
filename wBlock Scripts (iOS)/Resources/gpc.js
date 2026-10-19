// Global Privacy Control: reports the Sec-GPC header that wBlock sends.
// Registered in the page world only while the header rule is installed.
(() => {
  try {
    Object.defineProperty(Navigator.prototype, "globalPrivacyControl", {
      get() { return true; },
      configurable: true,
      enumerable: true
    });
  } catch (_error) {}
})();
