import SwiftUI

@MainActor
final class AppTabSelection: ObservableObject {
    @Published var value = 0
}

/// Owns selection invalidation while keeping the supplied page values unchanged.
struct AppTabView<Filters: View, Userscripts: View, Settings: View>: View {
    @ObservedObject var selection: AppTabSelection
    let filters: Filters
    let userscripts: Userscripts
    let settings: Settings

    var body: some View {
        #if os(macOS)
        if #available(macOS 26.0, *) {
            nativeTabs
        } else {
            legacyTabs
        }
        #else
        nativeTabs
        #endif
    }

    private var nativeTabs: some View {
        TabView(selection: $selection.value) {
            filters
                .tag(0)
                .tabItem { Label("Filters", systemImage: "list.bullet.rectangle") }
            userscripts
                .tag(1)
                .tabItem { Label("Userscripts", systemImage: "doc.text.fill") }
            settings
                .tag(2)
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        #if os(macOS)
        .frame(minWidth: MacTabWindow.minimumWidth, idealWidth: max(540, MacTabWindow.minimumWidth), minHeight: 550, idealHeight: 720)
        #endif
    }

    #if os(macOS)
    private var legacyTabs: some View {
        Group {
            switch selection.value {
            case 1:
                userscripts
            case 2:
                settings
            default:
                filters
            }
        }
        .frame(minWidth: 480, idealWidth: 540, minHeight: 550, idealHeight: 720)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("wBlock", selection: $selection.value) {
                    Text("Filters").tag(0)
                    Text("Userscripts").tag(1)
                    Text("Settings").tag(2)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
        }
    }
    #endif
}

#if os(macOS)
enum MacTabWindow {
    /// Narrow enough for the toolbar and no narrower. Below it AppKit moved
    /// the tab picker into the overflow menu and packed the other buttons
    /// against it (#1000). The picker's segments share the widest title's
    /// width, about 1.2 times its width at the system font size, so longer
    /// localized titles widen the window instead of hiding the tabs.
    static let minimumWidth: CGFloat = {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let widestTitle = ["Filters", "Userscripts", "Settings"]
            .map { (String(localized: String.LocalizationValue($0)) as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        return max(480, (290 + 3 * 1.2 * widestTitle).rounded(.up))
    }()
}
#endif
