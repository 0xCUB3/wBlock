// Replays this origin's last known untrusted uBO scriptlets synchronously at
// document_start in MAIN world so inline <head> checks cannot outrun the
// background round-trip. Registered dynamically per origin by background.js
// (only for origins whose active filters match scriptlets) and unregistered
// whenever blocking is paused, disabled, or rules change.
(function () {
  try {
    var host = location && typeof location.hostname === 'string' ? location.hostname : '';
    var path = location && typeof location.pathname === 'string' ? location.pathname : '';
    if (host === 'challenges.cloudflare.com' || host.endsWith('.challenges.cloudflare.com') || path.startsWith('/cdn-cgi/challenge')) {
      return null;
    }
    var raw = localStorage.getItem('__wblock_scriptlets_v1');
    if (!raw) return null;
    var entry = JSON.parse(raw);
    if (!entry || !Array.isArray(entry.calls) || typeof entry.exp !== 'number' || Date.now() > entry.exp) {
      return null;
    }
    var queue = globalThis.__wbeScriptletCalls || (globalThis.__wbeScriptletCalls = {});
    var keySym = Symbol.for('wbe.warmScriptletKeys');
    var ran = globalThis[keySym];
    if (!ran) {
      ran = new Set();
      try {
        Object.defineProperty(globalThis, keySym, { value: ran, configurable: true });
      } catch (_) {}
    }
    for (var i = 0; i < entry.calls.length; i += 1) {
      var call = entry.calls[i];
      if (!Array.isArray(call) || typeof call[0] !== 'string') continue;
      var name = call[0];
      if (!name || name.startsWith('trusted-') || name.startsWith('adg:')) continue;
      var args = call.slice(1);
      var pending = queue[name] || (queue[name] = []);
      if (!pending.some(function (c) { return c.length === args.length && c.every(function (v, idx) { return v === args[idx]; }); })) {
        pending.push(args);
      }
      try { ran.add(JSON.stringify(call)); } catch (_) {}
    }
  } catch (_) {}
  return null;
})();
