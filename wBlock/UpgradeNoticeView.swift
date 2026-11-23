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
                "wBlock now opens with a simpler layout, with a few switches in place of the long list. It uses the same engine, and every list and userscript you had on is still on. To see the full list view, tap Show All Filter Lists at the bottom of Filters or turn on Show All Lists in Settings → Advanced."
            )
            : (
                "rectangle.split.2x1",
                "A simpler layout option",
                "wBlock has a new simpler layout with a few switches in place of the long list. You have custom lists or userscripts, so wBlock kept showing all your lists and nothing moved. Try the simpler layout below or toggle Show All Lists anytime in Settings → Advanced."
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
        appMode == .basic ? "Show All Lists" : "Try Simpler Layout"
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
