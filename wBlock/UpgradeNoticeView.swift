import SwiftUI
import wBlockCoreService

/// Shown once to installs that used wBlock before 4.0, explaining the move to
/// the uBO-semantics engine and lists. New installs never see it.
enum UpgradeNotice {
    /// Whether the notice is still owed: a device that finished onboarding before
    /// 4.0 and has not dismissed it. A new install never sees it, so it is marked
    /// seen here.
    static func isPending(hasCompletedOnboarding: Bool) -> Bool {
        guard !UpgradeStateStore.hasSeenUpgradeNotice() else { return false }
        guard hasCompletedOnboarding else {
            markSeen()
            return false
        }
        return true
    }

    /// Called on dismissal, so a notice that never got on screen stays pending.
    static func markSeen() {
        UpgradeStateStore.markUpgradeNoticeSeen()
    }
}

struct UpgradeNoticeView: View {
    @Environment(\.dismiss) private var dismiss

    private let sections: [(symbol: String, title: LocalizedStringKey, body: LocalizedStringKey)] = [
        ("gearshape.2", "Why things changed",
         "wBlock used AdGuard's converter to turn filter lists into Safari rules. It skips rules written only for uBlock Origin. That meant many uBO lists didn't work fully in wBlock."),
        ("shield.lefthalf.filled", "A new engine",
         "wBlock's new engine reads lists like uBlock Origin. Your enabled AdGuard lists were swapped for matching uBO lists."),
        ("checkmark.circle", "What stays the same",
         "Your custom lists, userscripts, Element Zapper rules and site settings are unchanged. Most AdGuard lists are still in Filters if you want them back."),
        ("wrench.and.screwdriver", "If a site breaks",
         "Turn wBlock off for that site using the wBlock button in Safari, then report it on [GitHub](https://github.com/0xCUB3/wBlock/issues)."),
    ]

    var body: some View {
        SheetContainer(fill: .system) {
            SheetHeader(title: "Welcome to wBlock 4.0") {
                UpgradeNotice.markSeen()
                dismiss()
            }
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
                Button {
                    UpgradeNotice.markSeen()
                    dismiss()
                } label: {
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
