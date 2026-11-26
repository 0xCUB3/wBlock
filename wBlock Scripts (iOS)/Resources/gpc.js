// Global Privacy Control: reports the Sec-GPC header that wBlock sends.
// Registered in the page world only while the header rule is installed.
(() => {
  try {
    const host = location && typeof location.hostname === "string" ? location.hostname : "";
    const path = location && typeof location.pathname === "string" ? location.pathname : "";
    if (host === "challenges.cloudflare.com"
      || host.endsWith(".challenges.cloudflare.com")
      || path.startsWith("/cdn-cgi/challenge")) {
      return;
    }
    Object.defineProperty(Navigator.prototype, "globalPrivacyControl", {
      get() { return true; },
      configurable: true,
      enumerable: true
    });
  } catch (_error) {}
})();
