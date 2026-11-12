import SwiftUI
import wBlockCoreService

/// Shown once to installs that used wBlock before 4.0, explaining the move to
/// the uBO-semantics engine and lists. New installs never see it.
enum UpgradeNotice {
    private static let seenKey = "wBlock.upgradeNotice.4.0"
    private static var defaults: UserDefaults { UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard }

    /// Marks the notice seen and reports whether this launch should show it:
    /// the first launch of 4.0 on a device that finished onboarding earlier.
    static func shouldShowOnce(hasCompletedOnboarding: Bool) -> Bool {
        guard !defaults.bool(forKey: seenKey) else { return false }
        defaults.set(true, forKey: seenKey)
        return hasCompletedOnboarding
    }
}

struct UpgradeNoticeView: View {
    @Environment(\.dismiss) private var dismiss

    private let sections: [(symbol: String, title: LocalizedStringKey, body: LocalizedStringKey)] = [
        ("gearshape.2", "Why things changed",
         "wBlock used AdGuard's converter to turn filter lists into Safari rules. It skips rules written only for uBlock Origin. That meant many uBO lists didn't work fully in wBlock."),
        ("shield.lefthalf.filled", "A new engine",
         "I built a new engine that reads lists like uBlock Origin. wBlock starts from uBO's lists now. Your enabled AdGuard lists were swapped for matching uBO lists."),
        ("checkmark.circle", "What stays the same",
         "Your custom lists, userscripts, Element Zapper rules and site settings are unchanged. AdGuard lists are still in Filters if you want them back."),
        ("wrench.and.screwdriver", "If a site breaks",
         "Turn wBlock off for that site using the wBlock button in Safari. Then let me know on [GitHub](https://github.com/0xCUB3/wBlock/issues)."),
    ]

    var body: some View {
        SheetContainer(fill: .system) {
            SheetHeader(title: "Welcome to wBlock 4.0") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(sections.indices, id: \.self) { index in
                        let section = sections[index]
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: section.symbol)
                                .font(.title2)
                                .foregroundStyle(.tint)
                                .frame(width: 32)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(section.title).font(.headline)
                                Text(section.body)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(SheetDesign.contentHorizontalPadding)
            }
            SheetBottomToolbar {
                Button { dismiss() } label: {
                    Text("Got It").frame(maxWidth: .infinity)
                }
                .primaryActionButtonStyle()
                .keyboardShortcut(.defaultAction)
            }
        }
        #if os(macOS)
        .frame(width: 480, height: 560)
        #endif
    }
}
