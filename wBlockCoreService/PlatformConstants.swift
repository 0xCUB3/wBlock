//
//  PlatformConstants.swift
//  wBlockCoreService
//

import Foundation

/// Platform constants table for evaluating `!#if` conditional directives in filter lists.
///
/// wBlock identifies as an AdGuard-syntax Safari content blocker. All constants follow
/// the AdGuard/uBlock Origin convention: only the constants that accurately describe
/// wBlock's identity are `true`; everything else is `false`.
///
/// Unknown constant names always return `false` (PREP-08).
public enum PlatformConstants {

    // MARK: - wBlock identity (true)

    /// wBlock uses AdGuard syntax and SafariConverterLib.
    public static let adguard = true

    /// wBlock is a Safari content blocker extension.
    public static let adguard_ext_safari = true

    /// Running in a Safari environment.
    public static let env_safari = true

    // MARK: - Platform detection (compile-time)

    /// `true` on iOS, `false` on macOS. Resolved at compile time.
    #if os(iOS)
    public static let env_mobile = true
    #else
    public static let env_mobile = false
    #endif

    // MARK: - What wBlock is NOT (false)

    /// Not the native AdGuard macOS app.
    public static let adguard_app_mac = false

    /// Not the native AdGuard iOS app.
    public static let adguard_app_ios = false

    public static let adguard_app_windows = false
    public static let adguard_app_android = false
    public static let adguard_ext_chromium = false
    public static let adguard_ext_chromium_mv3 = false
    public static let adguard_ext_firefox = false
    public static let adguard_ext_edge = false
    public static let adguard_ext_opera = false
    public static let adguard_ext_android_cb = false

    public static let ext_ublock = false
    public static let ext_ubol = false
    public static let ext_abp = false

    public static let env_chromium = false
    public static let env_firefox = false
    public static let env_edge = false
    public static let env_mv3 = false

    public static let cap_html_filtering = false
    public static let cap_user_stylesheet = false

    // MARK: - Lookup

    /// Evaluates a single constant name. Returns `false` for any unrecognized name (PREP-08).
    public static func value(for name: String) -> Bool {
        switch name {
        // Literal boolean keywords
        case "true":  return true
        case "false": return false

        // wBlock identity
        case "adguard":             return adguard
        case "adguard_ext_safari":  return adguard_ext_safari
        case "env_safari":          return env_safari
        case "env_mobile":          return env_mobile

        // Native AdGuard apps (false)
        case "adguard_app_mac":     return adguard_app_mac
        case "adguard_app_ios":     return adguard_app_ios
        case "adguard_app_windows": return adguard_app_windows
        case "adguard_app_android": return adguard_app_android

        // Other browser extensions (false)
        case "adguard_ext_chromium":    return adguard_ext_chromium
        case "adguard_ext_chromium_mv3": return adguard_ext_chromium_mv3
        case "adguard_ext_firefox":     return adguard_ext_firefox
        case "adguard_ext_edge":        return adguard_ext_edge
        case "adguard_ext_opera":       return adguard_ext_opera
        case "adguard_ext_android_cb":  return adguard_ext_android_cb

        // uBlock / ABP variants (false)
        case "ext_ublock": return ext_ublock
        case "ext_ubol":   return ext_ubol
        case "ext_abp":    return ext_abp

        // Browser environments (false)
        case "env_chromium": return env_chromium
        case "env_firefox":  return env_firefox
        case "env_edge":     return env_edge
        case "env_mv3":      return env_mv3

        // Capabilities (false)
        case "cap_html_filtering":   return cap_html_filtering
        case "cap_user_stylesheet":  return cap_user_stylesheet

        // Unknown constant — default to false (PREP-08)
        default: return false
        }
    }
}
