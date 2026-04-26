/**
 * macOS version compatibility layer for wBlock.
 * Provides fallbacks for APIs unavailable on older macOS versions.
 */

export const MACOS_VERSIONS = {
  VENTURA: 13,
  MONTEREY: 12,
  BIG_SUR: 11,
  CATALINA: 10.15,
  MOJAVE: 10.14,
} as const;

function getMacOSVersion(): number {
  try {
    const ua = navigator.userAgent;
    const match = ua.match(/Mac OS X ([\d_]+)/);
    if (match) return parseFloat(match[1].replace(/_/g, "."));
  } catch {}
  return 0;
}

export const currentVersion = getMacOSVersion();

export function requiresVersion(minVersion: number): boolean {
  return currentVersion >= minVersion || currentVersion === 0; // 0 = unknown, assume supported
}

export const compat = {
  // Screen capture API (macOS 12.3+)
  screenCapture: requiresVersion(MACOS_VERSIONS.MONTEREY),
  // Notification API full support (macOS 11+)
  notifications: requiresVersion(MACOS_VERSIONS.BIG_SUR),
  // WebCrypto (always available)
  webCrypto: true,
};

export function getFallback(feature: string): string | null {
  const fallbacks: Record<string, string> = {
    screenCapture: "Use legacy screenshot approach via desktopCapturer",
    notifications: "Use basic alert() fallback",
  };
  return fallbacks[feature] || null;
}