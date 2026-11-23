import SwiftUI
import wBlockCoreService

/// Detail popover (Mac/iPad, 320pt) or fitted medium sheet (iPhone) showing every
/// Safari content blocker slot and wBlock Scripts in exact Safari order, plus
/// update timestamps and Check for Updates.
struct SafariHealthDetailView: View {
    @ObservedObject var filterManager: AppFilterManager
    @ObservedObject var safariHealth: SafariHealthMonitor
    let status: SafariHealthStatus
    let lastUpdatedDate: Date?
    let onCheckForUpdates: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var orderedSlots: [SafariExtensionSetupSupport.ContentBlockerSlotState] {
        if !safariHealth.blockerSlots.isEmpty {
            return safariHealth.blockerSlots
        }
        return ContentBlockerTargetManager.shared
            .allTargets(forPlatform: filterManager.currentPlatform)
            .map {
                SafariExtensionSetupSupport.ContentBlockerSlotState(
                    id: $0.slot,
                    name: $0.displayName,
                    bundleIdentifier: $0.bundleIdentifier,
                    isEnabled: false
                )
            }
    }

    var body: some View {
        #if os(macOS)
        detailContent
            .padding(16)
            .frame(width: 320)
        #else
        detailSheetBody
            .modifier(DetailSheetDetentsModifier())
        #endif
    }

    #if os(iOS)
    private var detailSheetBody: some View {
        ScrollView {
            detailContent
                .padding(SheetDesign.contentHorizontalPadding)
        }
        .scrollBounceBasedOnSizeCompat()
        .opaqueSheetBackgroundCompat()
    }
    #endif

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: status.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(status.tone.color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(status.title)
                        .font(.headline)
                    Text(status.subtitle())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                SheetDoneButton { dismiss() }
            }

            // Extensions list in exact Safari order: 5 content blockers + wBlock Scripts
            VStack(alignment: .leading, spacing: 8) {
                Text("Safari Extensions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                VStack(spacing: 0) {
                    ForEach(Array(orderedSlots.enumerated()), id: \.element.id) { index, slot in
                        extensionRow(
                            name: slot.name,
                            isEnabled: slot.isEnabled
                        )
                        Divider().padding(.leading, 30)
                    }

                    scriptsRow
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }

            if status.isExtensionDegraded {
                Button {
                    SafariExtensionSetupSupport.openScriptsExtensionSettings()
                } label: {
                    Label("Open Safari Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(status.tone.color)
            }
        }
        .task {
            await safariHealth.refreshNow()
        }
    }

    private func extensionRow(name: String, isEnabled: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(isEnabled ? Color(red: 0.16, green: 0.78, blue: 0.42) : .orange)
                .frame(width: 18)

            Text(name)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(isEnabled ? String(localized: "On") : String(localized: "Off"))
                .font(.caption.weight(.medium))
                .foregroundStyle(isEnabled ? Color.secondary : Color.orange)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var scriptsRow: some View {
        if safariHealth.isScriptsStateKnowable {
            let enabled = safariHealth.scriptsExtensionEnabled == true
            extensionRow(name: "wBlock Scripts", isEnabled: enabled)
        } else {
            // iOS < 26.2: OS cannot query Safari Web Extension state directly.
            Button {
                SafariExtensionSetupSupport.openScriptsExtensionSettings()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "questionmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    Text("wBlock Scripts")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Text("Check in Safari Settings")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    RowDisclosureChevron()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

#if os(iOS)
private struct DetailSheetDetentsModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}
#endif
