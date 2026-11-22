import SwiftUI

@MainActor
final class AppTabSelection: ObservableObject {
    @Published var value = 0
}

/// Owns selection invalidation while keeping the supplied page values unchanged.
struct AppTabView<Filters: View, Userscripts: View, Settings: View, Accessory: View>: View {
    @ObservedObject var selection: AppTabSelection
    let filters: Filters
    let userscripts: Userscripts
    let settings: Settings
    var secondTabTitle: LocalizedStringKey = "Userscripts"
    var tabBarIdentity: String = "advanced"
    var isBottomAccessoryEnabled: Bool = false
    let bottomAccessory: () -> Accessory

    init(
        selection: AppTabSelection,
        filters: Filters,
        userscripts: Userscripts,
        settings: Settings,
        secondTabTitle: LocalizedStringKey = "Userscripts",
        tabBarIdentity: String = "advanced",
        isBottomAccessoryEnabled: Bool = false,
        @ViewBuilder bottomAccessory: @escaping () -> Accessory
    ) {
        self.selection = selection
        self.filters = filters
        self.userscripts = userscripts
        self.settings = settings
        self.secondTabTitle = secondTabTitle
        self.tabBarIdentity = tabBarIdentity
        self.isBottomAccessoryEnabled = isBottomAccessoryEnabled
        self.bottomAccessory = bottomAccessory
    }

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
        let tabs = TabView(selection: $selection.value) {
            filters
                .tag(0)
                .tabItem { Label("Filters", systemImage: "list.bullet.rectangle") }
            userscripts
                .tag(1)
                .tabItem { Label(secondTabTitle, systemImage: "doc.text.fill") }
            settings
                .tag(2)
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        #if os(macOS)
        // Recreate the macOS 26 tab bar when the second tab's title changes
        // ("Extras" <-> "Userscripts") so AppKit does not leave a stale
        // selection pill rendered on the resized segment.
        return tabs
            .id(tabBarIdentity)
            .frame(minWidth: MacTabWindow.minimumWidth, idealWidth: max(540, MacTabWindow.minimumWidth), minHeight: 550, idealHeight: 720)
        #else
        return tabs.modifier(
            TabBottomAccessoryCompat(
                isEnabled: isBottomAccessoryEnabled,
                accessory: bottomAccessory
            )
        )
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
                    Text(secondTabTitle).tag(1)
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

extension AppTabView where Accessory == EmptyView {
    init(
        selection: AppTabSelection,
        filters: Filters,
        userscripts: Userscripts,
        settings: Settings,
        secondTabTitle: LocalizedStringKey = "Userscripts"
    ) {
        self.init(
            selection: selection,
            filters: filters,
            userscripts: userscripts,
            settings: settings,
            secondTabTitle: secondTabTitle,
            isBottomAccessoryEnabled: false,
            bottomAccessory: { EmptyView() }
        )
    }
}

#if os(iOS)
private struct TabBottomAccessoryCompat<Accessory: View>: ViewModifier {
    let isEnabled: Bool
    let accessory: () -> Accessory

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: isEnabled) {
                accessory()
            }
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                if isEnabled {
                    accessory()
                        .background(.bar, in: Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                }
            }
        }
    }
}
#endif

#if os(macOS)
enum MacTabWindow {
    /// Narrow enough for the toolbar and no narrower. Below it AppKit moved
    /// the tab picker into the overflow menu and packed the other buttons
    /// against it (#1000). The picker's segments share the widest title's
    /// width, about 1.2 times its width at the system font size, so longer
    /// localized titles widen the window instead of hiding the tabs.
    /// Measures both "Userscripts" and "Extras" so switching modes never resizes
    /// the window (#404).
    static let minimumWidth: CGFloat = {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let widestTitle = ["Filters", "Userscripts", "Extras", "Settings"]
            .map { (String(localized: String.LocalizationValue($0)) as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        return max(480, (290 + 3 * 1.2 * widestTitle).rounded(.up))
    }()
}
#endif
