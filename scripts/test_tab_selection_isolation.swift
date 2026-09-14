// Run with swiftc wBlock/AppTabView.swift scripts/test_tab_selection_isolation.swift -o /tmp/wblock-tab-isolation && /tmp/wblock-tab-isolation
import AppKit
import SwiftUI

@MainActor
private final class Counts {
    var parents = 0
    var pages: [String: Int] = [:]
    var values: [String: Int] = [:]
    var identities: [String: UUID] = [:]
}

@MainActor
private final class ContentModel: ObservableObject {
    @Published var value = 0
}

private struct Page: View {
    let name: String
    let value: Int
    let counts: Counts
    @State private var identity = UUID()
    var body: some View {
        let _ = record()
        Text("\(name) \(value)")
    }
    private func record() {
        counts.pages[name, default: 0] += 1
        counts.values[name] = value
        counts.identities[name] = identity
    }
}

private struct Fixture: View {
    @State var selection: AppTabSelection
    @ObservedObject var model: ContentModel
    let counts: Counts
    var body: some View {
        let _ = { counts.parents += 1 }()
        AppTabView(selection: selection,
                   filters: Page(name: "Filters", value: model.value, counts: counts),
                   userscripts: Page(name: "Userscripts", value: model.value, counts: counts),
                   settings: Page(name: "Settings", value: model.value, counts: counts))
    }
}

@main
struct TabSelectionIsolationTests {
    @MainActor
    static func main() {
        guard #available(macOS 26.0, *) else {
            print("SKIP — native macOS tabs require macOS 26")
            return
        }
        _ = NSApplication.shared
        let selection = AppTabSelection()
        let model = ContentModel()
        let counts = Counts()
        let host = NSHostingView(rootView: Fixture(selection: selection, model: model, counts: counts))
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        func settle() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            host.layoutSubtreeIfNeeded()
        }
        settle()
        for tab in [1, 2, 0] { selection.value = tab; settle() }
        let parentCount = counts.parents
        let pageCounts = counts.pages
        let identities = counts.identities
        precondition(Set(pageCounts.keys) == ["Filters", "Userscripts", "Settings"], "All native pages must be realized")
        for tab in [1, 2, 0, 2, 1, 0] { selection.value = tab; settle() }
        precondition(counts.parents == parentCount, "Selection must not rebuild the page-owning parent")
        precondition(counts.pages == pageCounts, "Selection must not rebuild unchanged page bodies")
        precondition(counts.identities == identities, "Selection must retain page state")
        model.value = 1
        settle()
        for tab in [1, 2, 0] { selection.value = tab; settle() }
        precondition(counts.values.values.allSatisfy { $0 == 1 }, "Model updates must still reach every page")
        precondition(counts.identities == identities, "Data updates must preserve local page state")
        print("PASS — selection isolation, retained page state, and live model updates")
    }
}
