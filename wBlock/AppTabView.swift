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
