import SwiftUI
import wBlockCoreService

/// Shown once to installs that used wBlock before 4.0, explaining the move to
/// Standard/Advanced modes and the uBO-semantics engine. New installs never see it.
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
    @AppStorage(AppMode.storageKey) private var appMode: AppMode = .basic

    private var sections: [(symbol: String, title: LocalizedStringKey, body: LocalizedStringKey)] {
        let modeSection: (String, LocalizedStringKey, LocalizedStringKey) = appMode == .basic
            ? (
                "rectangle.split.2x1",
                "A simpler wBlock",
                "wBlock now opens in Standard mode, with a few switches in place of the long list. It uses the same engine, and every list and userscript you had on is still on. If you want the full list view, switch to Advanced below or anytime in Settings."
            )
            : (
                "rectangle.split.2x1",
                "Standard and Advanced modes",
                "wBlock has a new Standard mode with a few switches in place of the long list. You have custom lists or userscripts, so you stayed in Advanced and nothing moved. Standard blocks the same things. Try it below or anytime in Settings."
            )

        return [
            modeSection,
            ("shield.lefthalf.filled", "A new engine",
             "This upgrade replaces the AdGuard converter with wBlock's own engine built for uBlock Origin rules, so more rules work in Safari. Your enabled AdGuard lists were swapped for matching uBO lists."),
            ("checkmark.circle", "What stays the same",
             "Your custom lists, userscripts, Element Zapper rules and site settings are unchanged. Most AdGuard lists are still in Filters if you want them back."),
            ("wrench.and.screwdriver", "If a site breaks",
             "Turn wBlock off for that site using the wBlock button in Safari, then report it on [GitHub](https://github.com/0xCUB3/wBlock/issues)."),
        ]
    }

    private var alternateModeLabel: LocalizedStringKey {
        appMode == .basic ? "Use Advanced Mode" : "Try Standard Mode"
    }

    private func switchToAlternateMode() {
        appMode = appMode == .basic ? .advanced : .basic
        UpgradeNotice.markSeen()
        dismiss()
    }

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
                #if os(iOS)
                VStack(spacing: 10) {
                    Button {
                        UpgradeNotice.markSeen()
                        dismiss()
                    } label: {
                        Text("Got It").frame(maxWidth: .infinity)
                    }
                    .primaryActionButtonStyle()

                    Button(action: switchToAlternateMode) {
                        Text(alternateModeLabel).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                #else
                Button(action: switchToAlternateMode) {
                    Text(alternateModeLabel).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    UpgradeNotice.markSeen()
                    dismiss()
                } label: {
                    Text("Got It").frame(maxWidth: .infinity)
                }
                .primaryActionButtonStyle()
                .keyboardShortcut(.defaultAction)
                #endif
            }
        }
        #if os(macOS)
        .frame(width: 480, height: 560)
        #endif
    }
}
