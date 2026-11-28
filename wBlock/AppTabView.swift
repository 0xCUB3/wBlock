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
        iosTabs.modifier(
            TabBottomAccessoryCompat(
                isEnabled: isBottomAccessoryEnabled,
                accessory: bottomAccessory
            )
        )
        #endif
    }

    #if os(macOS)
    private var nativeTabs: some View {
        // Recreate the macOS 26 tab bar when the second tab's title changes
        // ("Extras" <-> "Userscripts") so AppKit does not leave a stale
        // selection pill rendered on the resized segment.
        TabView(selection: $selection.value) {
            filters
                .tag(0)
                .tabItem { Label("Filters", systemImage: "shield.lefthalf.filled") }
            userscripts
                .tag(1)
                .tabItem { Label(secondTabTitle, systemImage: "puzzlepiece.extension") }
            settings
                .tag(2)
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .id(tabBarIdentity)
        .frame(minWidth: MacTabWindow.minimumWidth, idealWidth: max(540, MacTabWindow.minimumWidth), minHeight: 550, idealHeight: 720)
    }
    #else
    /// Hosts each tab's `NavigationStack` directly inside iOS 18+ `Tab` (and
    /// `TabView` on older iOS) with no conditional wrapper around the stack so
    /// iPadOS's floating tab bar merges cleanly with each tab's navigation bar
    /// instead of pushing the toolbar and content down (#1162, #1168).
    @ViewBuilder
    private var iosTabs: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $selection.value) {
                Tab("Filters", systemImage: "shield.lefthalf.filled", value: 0) {
                    NavigationStack {
                        filters.background(tabBarLayoutReconciler)
                    }
                }
                Tab(secondTabTitle, systemImage: "puzzlepiece.extension", value: 1) {
                    NavigationStack {
                        userscripts.background(tabBarLayoutReconciler)
                    }
                }
                Tab("Settings", systemImage: "gear", value: 2) {
                    NavigationStack {
                        settings.background(tabBarLayoutReconciler)
                    }
                }
            }
        } else if #available(iOS 16.0, *) {
            TabView(selection: $selection.value) {
                NavigationStack { filters }
                    .tag(0)
                    .tabItem { Label("Filters", systemImage: "shield.lefthalf.filled") }
                NavigationStack { userscripts }
                    .tag(1)
                    .tabItem { Label(secondTabTitle, systemImage: "puzzlepiece.extension") }
                NavigationStack { settings }
                    .tag(2)
                    .tabItem { Label("Settings", systemImage: "gear") }
            }
        } else {
            TabView(selection: $selection.value) {
                NavigationView { filters }
                    .navigationViewStyle(StackNavigationViewStyle())
                    .tag(0)
                    .tabItem { Label("Filters", systemImage: "shield.lefthalf.filled") }
                NavigationView { userscripts }
                    .navigationViewStyle(StackNavigationViewStyle())
                    .tag(1)
                    .tabItem { Label(secondTabTitle, systemImage: "puzzlepiece.extension") }
                NavigationView { settings }
                    .navigationViewStyle(StackNavigationViewStyle())
                    .tag(2)
                    .tabItem { Label("Settings", systemImage: "gear") }
            }
        }
    }

    @available(iOS 18.0, *)
    private var tabBarLayoutReconciler: some View {
        FloatingTabBarLayoutReconciler()
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
    #endif

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
/// Reconciles iPadOS 18+ floating tab bar safe-area integration on initial
/// launch. SwiftUI's `TabHostingController` is initially laid out by
/// `UITabBarController` before its child `NavigationStack` registers, leaving
/// `safeAreaInsets.top` inflated by the floating tab bar height (pushing both
/// the navigation toolbar and scroll content down until `didBecomeActive`
/// triggers a bar layout pass). Toggling `setTabBarHidden` once without
/// animation before the first frame forces `UITabBarController` to recompute
/// its integrated bar layout immediately (#1168).
@available(iOS 18.0, *)
private struct FloatingTabBarLayoutReconciler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ReconcilerViewController {
        ReconcilerViewController()
    }

    func updateUIViewController(_ uiViewController: ReconcilerViewController, context: Context) {
        uiViewController.reconcileIfNeeded()
    }

    final class ReconcilerViewController: UIViewController {
        private var didReconcile = false

        override func loadView() {
            let emptyView = UIView(frame: .zero)
            emptyView.isUserInteractionEnabled = false
            emptyView.isHidden = true
            view = emptyView
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            reconcileIfNeeded()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            reconcileIfNeeded()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            reconcileIfNeeded()
            didReconcile = true
        }

        func reconcileIfNeeded() {
            guard !didReconcile,
                  let tabBarController = tabBarController,
                  let selected = tabBarController.selectedViewController,
                  !tabBarController.isTabBarHidden,
                  selected.children.contains(where: { $0 is UINavigationController }),
                  selected.view.safeAreaInsets.top > tabBarController.view.safeAreaInsets.top + 1
            else { return }

            didReconcile = true
            UIView.performWithoutAnimation {
                tabBarController.setTabBarHidden(true, animated: false)
                tabBarController.view.layoutIfNeeded()
                tabBarController.setTabBarHidden(false, animated: false)
                tabBarController.view.layoutIfNeeded()
            }
        }
    }
}

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
