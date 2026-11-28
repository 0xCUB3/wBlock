import SwiftUI
import wBlockCoreService

/// Basic mode Extras tab: curated Video & Reading cards with bespoke IconBadges,
/// Dark Reader live appearance swatch badge, inline settings pills revealed only
/// when enabled, automatic scripts hidden, and active advanced/custom scripts
/// surfaced truthfully under "Also on".
struct BasicExtrasView: View {
    @ObservedObject var userScriptManager: UserScriptManager
    @ObservedObject var filterManager: AppFilterManager
    let onRefresh: () async -> Void
    let onSwitchToAdvanced: () -> Void

    private static let rememberedAlsoOnScriptIDsKey = "wBlock.basicRememberedAlsoOnScriptIDs"
    @State private var downloadingScriptIDs = Set<UUID>()
    @State private var pendingBetaScript: UserScript?
    @State private var rememberedAlsoOnScriptIDs: Set<UUID> = BasicExtrasView.readRememberedAlsoOnScriptIDs()
    @Environment(\.colorScheme) private var colorScheme

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard
    }

    private var activeLanguageCodes: Set<String> {
        var codes = Set(Locale.preferredLanguages.compactMap {
            Locale(identifier: $0).languageCode?.lowercased()
        })
        if let stored = Self.sharedDefaults.stringArray(forKey: OnboardingView.selectedLanguagesDefaultsKey) {
            codes.formUnion(stored.map { $0.lowercased() })
        }
        return codes
    }

    private func featuredScripts(in group: BuiltInUserScriptBasicGroup) -> [UserScript] {
        let preferredOrder: [String]
        switch group {
        case .video:
            preferredOrder = ["Tube Cleaner", "Player Cleaner", "DeArrow", "Return YouTube Dislike", "TwitchAdSolutions (vaft)"]
        case .reading:
            preferredOrder = ["Dark Reader", "Disable AMP", "Bypass Paywalls Clean"]
        case .protection:
            preferredOrder = ["tinyShield", "AdGuard Popup Blocker", "AdGuard Extra"]
        }

        let langs = activeLanguageCodes
        let matching = userScriptManager.userScripts.filter { script in
            guard userScriptManager.builtInTier(for: script) == .featured,
                  userScriptManager.builtInBasicGroup(for: script) == group else {
                return false
            }
            let scriptLangs = userScriptManager.builtInLanguages(for: script)
            if scriptLangs.isEmpty || script.isEnabled {
                return true
            }
            return !Set(scriptLangs).isDisjoint(with: langs)
        }
        return matching.sorted { lhs, rhs in
            let lIdx = preferredOrder.firstIndex(of: lhs.name) ?? Int.max
            let rIdx = preferredOrder.firstIndex(of: rhs.name) ?? Int.max
            if lIdx != rIdx { return lIdx < rIdx }
            return lhs.localizedDisplayName.localizedCaseInsensitiveCompare(rhs.localizedDisplayName) == .orderedAscending
        }
    }

    /// Advanced-only built-in scripts and custom user-added scripts/styles
    /// surfaced under "Also on". Custom scripts stay listed even when turned
    /// off until explicitly deleted; advanced-only built-in scripts stay
    /// listed once enabled until explicitly removed. Automatic scripts stay
    /// hidden with their state untouched.
    private var alsoOnScripts: [UserScript] {
        userScriptManager.userScripts.filter { script in
            let tier = userScriptManager.builtInTier(for: script)
            guard tier == .advancedOnly || tier == nil else { return false }
            let isEnabled = userScriptManager.userScriptToggleState(for: script.id)?.desired ?? script.isEnabled
            return isEnabled || tier == nil || rememberedAlsoOnScriptIDs.contains(script.id)
        }
    }

    private static func readRememberedAlsoOnScriptIDs() -> Set<UUID> {
        let raw = UserDefaults.standard.stringArray(forKey: rememberedAlsoOnScriptIDsKey) ?? []
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    private func saveRememberedAlsoOnScriptIDs(_ ids: Set<UUID>) {
        guard ids != rememberedAlsoOnScriptIDs else { return }
        rememberedAlsoOnScriptIDs = ids
        UserDefaults.standard.set(ids.map(\.uuidString).sorted(), forKey: Self.rememberedAlsoOnScriptIDsKey)
    }

    private func syncRememberedAlsoOnScriptIDs() {
        let advancedOnlyScripts = userScriptManager.userScripts.filter {
            userScriptManager.builtInTier(for: $0) == .advancedOnly
        }
        let validIDs = Set(advancedOnlyScripts.map(\.id))
        let activeIDs = Set(advancedOnlyScripts.filter { script in
            userScriptManager.userScriptToggleState(for: script.id)?.desired ?? script.isEnabled
        }.map(\.id))
        let next = rememberedAlsoOnScriptIDs.intersection(validIDs).union(activeIDs)
        saveRememberedAlsoOnScriptIDs(next)
    }

    private func removeAlsoOnScript(_ script: UserScript) {
        var next = rememberedAlsoOnScriptIDs
        next.remove(script.id)
        saveRememberedAlsoOnScriptIDs(next)

        if userScriptManager.builtInTier(for: script) == nil {
            Task {
                await userScriptManager.removeUserScript(script)
            }
        } else if script.isEnabled {
            setScriptEnabled(script, enabled: false)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                let protection = featuredScripts(in: .protection)
                if !protection.isEmpty {
                    groupSection(title: "Protection", scripts: protection)
                }

                let video = featuredScripts(in: .video)
                if !video.isEmpty {
                    groupSection(title: "Video", scripts: video)
                }

                let reading = featuredScripts(in: .reading)
                if !reading.isEmpty {
                    groupSection(title: "Reading", scripts: reading)
                }

                if !alsoOnScripts.isEmpty {
                    groupSection(title: "Also on", scripts: alsoOnScripts, allowsRemove: true)
                }

                Button {
                    onSwitchToAdvanced()
                } label: {
                    Text("Show All Userscripts")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .noFocusRingCompat()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .refreshable {
            await onRefresh()
        }
        .alert("Enable Beta Feature?", isPresented: Binding(
            get: { pendingBetaScript != nil },
            set: { if !$0 { pendingBetaScript = nil } }
        ), presenting: pendingBetaScript) { script in
            Button("Cancel", role: .cancel) { pendingBetaScript = nil }
            Button("Enable") {
                pendingBetaScript = nil
                BetaUserscriptWarning.acknowledge()
                setScriptEnabled(script, enabled: true)
            }
        } message: { _ in
            Text("These are beta features that we're still testing. They may behave strangely on some sites. You can disable them anytime.")
        }
        .onAppear {
            syncRememberedAlsoOnScriptIDs()
        }
        .onChangeCompat(of: userScriptManager.userScripts) { _, _ in
            syncRememberedAlsoOnScriptIDs()
        }
    }

    private func groupSection(title: LocalizedStringKey, scripts: [UserScript], allowsRemove: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(scripts.enumerated()), id: \.element.id) { index, script in
                    extraRow(script, allowsRemove: allowsRemove)
                    if index < scripts.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(cardBackground)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(cardBorderColor, lineWidth: 1)
            }
        }
    }

    private func extraRow(_ script: UserScript, allowsRemove: Bool = false) -> some View {
        let toggleState = userScriptManager.userScriptToggleState(for: script.id)
        let isEnabled = toggleState?.desired ?? script.isEnabled
        let isInFlight = (toggleState?.isInFlight ?? false) || downloadingScriptIDs.contains(script.id)
        let isBeta = userScriptManager.isBeta(for: script)
        let isCustom = userScriptManager.builtInTier(for: script) == nil
        let ringPhase: BadgeRingPhase = isInFlight ? .applying(progress: nil) : .idle
        let removeLabel = isCustom
            ? NSLocalizedString(script.isUserStyle ? "Delete Style" : "Delete Script", comment: "Delete custom script or style action")
            : NSLocalizedString("Remove", comment: "Remove script from Also on action")

        return HStack(alignment: .top, spacing: 12) {
            badgeView(for: script, isOn: isEnabled, ringPhase: ringPhase)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(script.localizedDisplayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if isBeta {
                        Text("Beta")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.07), in: Capsule())
                    }
                }

                let subtitle = plainDescription(for: script)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Inline settings pills reveal ONLY when toggled ON.
                if isEnabled {
                    inlineSettingsControls(for: script)
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Spacer(minLength: 8)

            if allowsRemove && !isEnabled && !isInFlight {
                Button {
                    removeAlsoOnScript(script)
                } label: {
                    Image(systemName: isCustom ? "trash" : "minus.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .noFocusRingCompat()
                .accessibilityLabel(removeLabel)
                .help(removeLabel)
                .padding(.top, 2)
            }

            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { newValue in
                    handleToggle(script, enabled: newValue)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .fixedSize()
            .disabled(isInFlight)
            .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
        .contextMenu {
            if allowsRemove {
                Button(role: .destructive) {
                    removeAlsoOnScript(script)
                } label: {
                    Label(removeLabel, systemImage: isCustom ? "trash" : "minus.circle")
                }
            }
        }
    }

    @ViewBuilder
    private func badgeView(for script: UserScript, isOn: Bool, ringPhase: BadgeRingPhase) -> some View {
        if userScriptManager.isDarkReader(script) {
            DarkReaderSwatchBadge(
                isOn: isOn,
                followsSystem: userScriptManager.darkReaderFollowsSystemAppearance,
                pureBlack: userScriptManager.darkReaderPureBlack,
                ringPhase: ringPhase
            )
        } else {
            let style = Self.badgeStyle(for: script, userScriptManager: userScriptManager)
            IconBadge(
                systemName: style.symbol,
                tint: style.tint,
                isOn: isOn,
                ringPhase: ringPhase
            )
        }
    }

    @ViewBuilder
    private func inlineSettingsControls(for script: UserScript) -> some View {
        if userScriptManager.isDarkReader(script) {
            DarkReaderAppearancePicker(
                followsSystemAppearance: Binding(
                    get: { userScriptManager.darkReaderFollowsSystemAppearance },
                    set: { userScriptManager.setDarkReaderFollowsSystemAppearance($0) }
                ),
                pureBlack: Binding(
                    get: { userScriptManager.darkReaderPureBlack },
                    set: { userScriptManager.setDarkReaderPureBlack($0) }
                )
            )
        } else if userScriptManager.isTubeCleaner(script) {
            if #available(iOS 16.0, macOS 13.0, *) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { tubeCleanerControls(script) }
                    VStack(alignment: .leading, spacing: 4) { tubeCleanerControls(script) }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) { tubeCleanerControls(script) }
            }
        } else if userScriptManager.isPlayerCleaner(script) {
            PlayerCleanerFeaturesPicker(
                features: Binding(
                    get: { userScriptManager.playerCleanerFeatures },
                    set: { userScriptManager.setPlayerCleanerFeatures($0) }
                )
            )
        } else if userScriptManager.isDeArrow(script) {
            DeArrowSettingsPicker(
                settings: Binding(
                    get: { userScriptManager.tubeCleanerDeArrow },
                    set: { userScriptManager.setTubeCleanerDeArrow($0) }
                )
            )
        }
    }

    @ViewBuilder
    private func tubeCleanerControls(_ script: UserScript) -> some View {
        SponsorBlockTransferButton(scriptID: script.id)
        TubeCleanerFeaturesPicker(
            features: Binding(
                get: { userScriptManager.tubeCleanerFeatures },
                set: { userScriptManager.setTubeCleanerFeatures($0) }
            )
        )
    }

    private func handleToggle(_ script: UserScript, enabled: Bool) {
        if enabled && userScriptManager.isBeta(for: script) && !BetaUserscriptWarning.hasAcknowledged {
            pendingBetaScript = script
            return
        }
        setScriptEnabled(script, enabled: enabled)
    }

    private func setScriptEnabled(_ script: UserScript, enabled: Bool) {
        let needsDownload = enabled && !userScriptManager.hasDownloadedContent(for: script) && !script.isLocal && script.url != nil
        if needsDownload {
            downloadingScriptIDs.insert(script.id)
        }

        // Pairing Bypass Paywalls Clean with its filter list (same as OnboardingView.swift:936).
        if userScriptManager.isBypassPaywallsClean(script) {
            togglePairedBypassPaywallsFilter(enabled: enabled)
        }

        Task {
            await userScriptManager.setUserScript(script, isEnabled: enabled)
            await MainActor.run {
                _ = downloadingScriptIDs.remove(script.id)
            }
        }
    }

    private func togglePairedBypassPaywallsFilter(enabled: Bool) {
        guard let filter = filterManager.filterLists.first(where: BasicBundle.isPairedBypassPaywallsFilter) else { return }
        if filterManager.setFilterListSelection(id: filter.id, selected: enabled) {
            filterManager.flushPendingSave()
            filterManager.scheduleBasicAutoApply()
        }
    }

    static func badgeStyle(for script: UserScript, userScriptManager: UserScriptManager) -> (symbol: String, tint: Color) {
        if userScriptManager.isTubeCleaner(script) {
            return ("play.rectangle.fill", .accentColor)
        }
        if userScriptManager.isPlayerCleaner(script) {
            return ("pip.enter", .accentColor)
        }
        if userScriptManager.isDeArrow(script) {
            return ("text.badge.checkmark", .accentColor)
        }
        if script.name.localizedCaseInsensitiveContains("return youtube dislike") {
            return ("hand.thumbsdown.fill", .accentColor)
        }
        if script.name.localizedCaseInsensitiveContains("twitch") {
            return ("tv.fill", .accentColor)
        }
        if script.name.localizedCaseInsensitiveContains("disable amp") {
            return ("bolt.slash.fill", .accentColor)
        }
        if userScriptManager.isBypassPaywallsClean(script) {
            return ("newspaper.fill", .accentColor)
        }
        if script.name.localizedCaseInsensitiveContains("tinyshield") {
            return ("hand.raised.fill", .accentColor)
        }
        if script.name.localizedCaseInsensitiveContains("popup blocker") {
            return ("macwindow.badge.plus", .accentColor)
        }
        if script.name.localizedCaseInsensitiveContains("adguard extra") {
            return ("sparkles", .accentColor)
        }
        return ("puzzlepiece.extension.fill", .accentColor)
    }

    private func plainDescription(for script: UserScript) -> String {
        let lower = script.name.lowercased()
        if lower.contains("return youtube dislike") {
            return NSLocalizedString(
                "Shows dislike counts on YouTube again, using data from the Return YouTube Dislike community.",
                comment: "Default userscript description"
            )
        }
        if lower.contains("bypass paywalls") {
            return NSLocalizedString(
                "Gets past paywalls on English-language news sites, and some in other languages.",
                comment: "Default userscript description"
            )
        }
        let desc = script.localizedDisplayDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if desc.lowercased() == "default userscript" {
            return ""
        }
        return desc
    }

    private var cardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.82)
        #endif
    }

    private var cardBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
}
