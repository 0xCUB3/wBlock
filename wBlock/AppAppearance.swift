import SwiftUI
#if os(macOS)
import AppKit
#endif

/// In-app appearance override (#623). System follows the OS; Light and Dark
/// pin the whole app regardless of the device setting.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appAppearance"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    #if os(macOS)
    @MainActor
    func applyNativeAppearance() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
    #endif

    var title: LocalizedStringKey {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// SwiftUI preferences do not set the appearance of AppKit-owned menus.
struct AppAppearanceModifier: ViewModifier {
    let appearance: AppAppearance

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .preferredColorScheme(appearance.colorScheme)
            .onAppear { appearance.applyNativeAppearance() }
            .onChangeCompat(of: appearance) { _, value in value.applyNativeAppearance() }
        #else
        if #available(iOS 16.0, *) {
            content
                .preferredColorScheme(appearance.colorScheme)
                .toolbarColorScheme(appearance.colorScheme, for: .navigationBar, .tabBar)
        } else {
            content.preferredColorScheme(appearance.colorScheme)
        }
        #endif
    }
}
