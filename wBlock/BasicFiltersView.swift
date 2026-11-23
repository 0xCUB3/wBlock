import SwiftUI
import wBlockCoreService

/// Basic mode Filters screen: atmospheric Hero, switchless 3-up Core Trio with
/// Peek + scoped All Lists, 7 Annoyances rows, More (Languages + Also on), and
/// a plain footer button to view all filter lists.
struct BasicFiltersView: View {
    @ObservedObject var filterManager: AppFilterManager
    @ObservedObject var safariHealth: SafariHealthMonitor
    @ObservedObject private var userScriptManager = UserScriptManager.shared

    let lastUpdatedDate: Date?
    let onOpenHealthDetail: () -> Void
    let onCheckForUpdates: () -> Void
    let onHealthAction: (SafariHealthStatus.Action) -> Void
    let onHeroVisibilityChange: (Bool) -> Void
    let onSwitchToAdvanced: () -> Void

    private struct AlsoOnSheetItem: Identifiable {
        let id = "alsoOn"
    }

    @AppStorage(ListDisplayOrder.filtersKey) private var filterDisplayOrder = Data()
    @State private var toggleMemory = BasicBundleToggleMemory()
    @State private var peekBundle: BasicBundle?
    @State private var unownedSheetItem: AlsoOnSheetItem?
    @State private var showingLanguagesSheet = false
    @State private var storedLanguageCodes: Set<String> = BasicFiltersView.readStoredLanguageCodes()
    @State private var hasPendingLanguageApply = false
    @State private var showingHeroPopover = false
    private static let stricterBlockingExpandedKey = "wBlock.basicStricterBlockingExpanded"
    @State private var showStricterBlocking: Bool
    @State private var scrollOffset: CGFloat = 0

    init(
        filterManager: AppFilterManager,
        safariHealth: SafariHealthMonitor,
        lastUpdatedDate: Date?,
        onOpenHealthDetail: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onHealthAction: @escaping (SafariHealthStatus.Action) -> Void,
        onHeroVisibilityChange: @escaping (Bool) -> Void,
        onSwitchToAdvanced: @escaping () -> Void
    ) {
        self.filterManager = filterManager
        self.safariHealth = safariHealth
        self.lastUpdatedDate = lastUpdatedDate
        self.onOpenHealthDetail = onOpenHealthDetail
        self.onCheckForUpdates = onCheckForUpdates
        self.onHealthAction = onHealthAction
        self.onHeroVisibilityChange = onHeroVisibilityChange
        self.onSwitchToAdvanced = onSwitchToAdvanced

        // Respect the user's saved dropdown state when set; on first visit,
        // start already expanded (without an appear animation) if any stricter
        // annoyance list is active (#1150).
        let initialExpanded: Bool
        if UserDefaults.standard.object(forKey: Self.stricterBlockingExpandedKey) != nil {
            initialExpanded = UserDefaults.standard.bool(forKey: Self.stricterBlockingExpandedKey)
        } else {
            initialExpanded = AnnoyanceChoice.basicStricterChoices.contains {
                BasicBundle.annoyance($0).state(in: filterManager.filterLists) != .off
            }
        }
        _showStricterBlocking = State(initialValue: initialExpanded)
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard
    }

    private var healthStatus: SafariHealthStatus {
        safariHealth.status(filterManager: filterManager, lastUpdatedDate: lastUpdatedDate)
    }

    private var applyProgress: Double? {
        guard filterManager.isApplyInFlight else { return nil }
        let p = Double(filterManager.progress)
        return p >= 0.02 ? min(1, p) : nil
    }

    private var isBypassPaywallsCleanEnabled: Bool {
        userScriptManager.userScripts.contains {
            userScriptManager.isBypassPaywallsClean($0) && $0.isEnabled
        }
    }

    private var unownedActiveFilters: [FilterList] {
        BasicBundle.unownedActiveFilters(
            in: filterManager.filterLists,
            isBypassPaywallsCleanEnabled: isBypassPaywallsCleanEnabled
        )
    }

    private var languageOptions: [RegionalLanguageOption] {
        RegionalLanguageOption.fromForeignFilters(filterManager.filterLists)
    }

    private static func readStoredLanguageCodes() -> Set<String> {
        Set((sharedDefaults.stringArray(forKey: OnboardingView.selectedLanguagesDefaultsKey) ?? [])
            .map(RegionalLanguageOption.canonicalCode))
    }

    private var activeLanguageCodes: Set<String> {
        BasicBundle.activeRegionalLanguageCodes(
            in: filterManager.filterLists,
            storedCodes: storedLanguageCodes
        )
    }

    private var languageSelectionBinding: Binding<Set<String>> {
        Binding(
            get: { activeLanguageCodes },
            set: { newVisible in
                let nextStored = BasicBundle.updatedStoredRegionalLanguageCodes(
                    previousVisible: activeLanguageCodes,
                    newVisible: newVisible,
                    storedCodes: storedLanguageCodes,
                    in: filterManager.filterLists
                )
                applyLanguageSelection(nextStored)
            }
        )
    }

    private var languageSummary: String {
        let codes = activeLanguageCodes
        guard !codes.isEmpty else { return String(localized: "None") }
        let displayLocale = RegionalLanguageOption.displayLocale
        let names = codes
            .map { code -> (sortKey: String, native: String) in
                let display = displayLocale.localizedString(forLanguageCode: code) ?? code
                let native = Locale.nativeLanguageName(for: code) ?? display
                return (display, native)
            }
            .sorted { $0.sortKey.localizedCaseInsensitiveCompare($1.sortKey) == .orderedAscending }
            .map(\.native)
        return ListFormatter.localizedString(byJoining: names)
    }

    private var atmosphereFade: Double {
        let fadeDistance: CGFloat = 110
        return max(0, min(1, Double(1 - max(0, scrollOffset) / fadeDistance)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroSection
                    .background(ScrollOffsetTracker())

                coreTrioSection

                annoyancesSection

                moreSection

                footerSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 28)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(alignment: .top) {
            ProtectionAtmosphereWash(tone: healthStatus.tone, scrollFade: atmosphereFade)
        }
        .coordinateSpace(name: "basicFiltersScroll")
        .onPreferenceChange(BasicScrollOffsetKey.self) { offset in
            scrollOffset = offset
            onHeroVisibilityChange(offset < 110)
        }
        #if os(iOS)
        .refreshable {
            guard !filterManager.isLoading else { return }
            await filterManager.checkForUpdates(scope: .filters, presentation: .refresh, autoApply: true)
        }
        #endif
        .infoPresentation(item: $peekBundle) { bundle in
            BasicBundlePeekView(
                bundle: bundle,
                filterManager: filterManager,
                state: bundle.state(in: filterManager.filterLists),
                onToggle: { turnOn in
                    toggleBundle(bundle, turnOn: turnOn)
                },
                onResetToRecommended: {
                    resetBundleToRecommended(bundle)
                }
            )
            .id(bundle.id)
        }
        .infoPresentation(item: $unownedSheetItem) { _ in
            ScopedBundleListsSheet(
                title: String(localized: "Also on"),
                filters: FilterListPresentation.ordered(unownedActiveFilters, order: filterDisplayOrder),
                filterManager: filterManager,
                onMutation: {
                    filterManager.scheduleBasicAutoApply()
                }
            )
        }
        #if os(iOS)
        .sheet(isPresented: $showingLanguagesSheet) {
            RegionalLanguageList(
                selectedLanguages: languageSelectionBinding,
                options: languageOptions
            )
        }
        #endif
        .onAppear {
            storedLanguageCodes = Self.readStoredLanguageCodes()
        }
        .onDisappear {
            if hasPendingLanguageApply {
                hasPendingLanguageApply = false
                filterManager.flushPendingSave()
                filterManager.scheduleBasicAutoApply()
            }
        }
        .onChangeCompat(of: showingLanguagesSheet) { _, isShowing in
            if isShowing {
                storedLanguageCodes = Self.readStoredLanguageCodes()
            } else if hasPendingLanguageApply {
                hasPendingLanguageApply = false
                filterManager.flushPendingSave()
                filterManager.scheduleBasicAutoApply()
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ProtectionHero(
            status: healthStatus,
            arcStates: safariHealth.arcStates,
            isWelded: safariHealth.hysteresis.isWelded,
            weldCelebrationCount: safariHealth.weldCelebrationCount,
            applyProgress: applyProgress,
            statusSubtitleOverride: filterManager.showingBasicUpToDateStatus
                ? String(localized: "Filters are up to date.")
                : nil,
            onTapHero: {
                #if os(macOS)
                showingHeroPopover = true
                #else
                onOpenHealthDetail()
                #endif
            },
            onAction: onHealthAction
        )
        #if os(macOS)
        .modalPopover(isPresented: $showingHeroPopover, arrowEdge: .bottom) {
            SafariHealthDetailView(
                filterManager: filterManager,
                safariHealth: safariHealth,
                status: healthStatus,
                lastUpdatedDate: lastUpdatedDate,
                onCheckForUpdates: onCheckForUpdates
            )
        }
        #endif
        .modifier(HeroScrollVisibilityCompat(onVisibilityChange: onHeroVisibilityChange))
    }

    // MARK: - Core Protection Trio

    private var coreTrioSection: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedCoreCard
            } else if #available(iOS 16.0, macOS 13.0, *) {
                ViewThatFits(in: .horizontal) {
                    horizontalCoreTrio
                    stackedCoreCard
                }
            } else {
                horizontalCoreTrio
            }
        }
    }

    private var horizontalCoreTrio: some View {
        HStack(spacing: 10) {
            ForEach(CoreProtectionBundle.allCases) { core in
                coreTile(core)
            }
        }
    }

    private func coreTile(_ core: CoreProtectionBundle) -> some View {
        let bundle = BasicBundle.core(core)
        let state = bundle.state(in: filterManager.filterLists)

        return Button {
            peekBundle = bundle
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    CoreTileBadge(
                        bundle: core,
                        state: state,
                        size: IconBadge.defaultSize,
                        ringPhase: ringPhase(for: bundle),
                        showsFailedDot: hasFailed(for: bundle),
                        cutoutBackground: cardBackground
                    )
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    // fixedSize(horizontal: true) lets ViewThatFits fall back to
                    // stacked rows whenever a long localized title (Russian,
                    // Polish, French) would otherwise truncate on one line.
                    Text(core.localizedTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Text(state.accessibilityLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(state == .partlyOn ? Color.orange : Color.secondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(cardBackground)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(cardBorderColor, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .noFocusRingCompat()
        .infoPopoverAnchor(bundle.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(core.localizedTitle))
        .accessibilityValue(Text(state.accessibilityLabel))
        .accessibilityAddTraits(.isButton)
    }

    private var stackedCoreCard: some View {
        groupedCard {
            ForEach(Array(CoreProtectionBundle.allCases.enumerated()), id: \.element.id) { index, core in
                let bundle = BasicBundle.core(core)
                let state = bundle.state(in: filterManager.filterLists)

                Button {
                    peekBundle = bundle
                } label: {
                    HStack(spacing: 12) {
                        CoreTileBadge(
                            bundle: core,
                            state: state,
                            size: IconBadge.defaultSize,
                            ringPhase: ringPhase(for: bundle),
                            showsFailedDot: hasFailed(for: bundle),
                            cutoutBackground: cardBackground
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(core.localizedTitle)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(core.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 8)

                        Text(state.accessibilityLabel)
                            .font(.subheadline)
                            .foregroundStyle(state == .partlyOn ? Color.orange : Color.secondary)

                        RowDisclosureChevron()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .noFocusRingCompat()
                .infoPopoverAnchor(bundle.id)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(core.localizedTitle))
                .accessibilityValue(Text(state.accessibilityLabel))
                .accessibilityAddTraits(.isButton)

                if index < CoreProtectionBundle.allCases.count - 1 {
                    Divider().padding(.leading, 56)
                }
            }
        }
    }

    // MARK: - Annoyances

    private var primaryAnnoyances: [AnnoyanceChoice] {
        AnnoyanceChoice.basicPrimaryChoices()
    }

    private var stricterAnnoyances: [AnnoyanceChoice] {
        AnnoyanceChoice.basicStricterChoices
    }

    private var activeStricterAnnoyanceCount: Int {
        stricterAnnoyances.filter {
            BasicBundle.annoyance($0).state(in: filterManager.filterLists) != .off
        }.count
    }

    private var hasActiveStricterAnnoyance: Bool {
        activeStricterAnnoyanceCount > 0
    }

    private var annoyancesSection: some View {
        let primary = primaryAnnoyances
        let stricter = stricterAnnoyances

        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Annoyances")
            groupedCard {
                ForEach(Array(primary.enumerated()), id: \.element.id) { index, choice in
                    annoyanceRow(choice)
                    Divider().padding(.leading, 56)
                }

                stricterBlockingRow

                VStack(spacing: 0) {
                    if showStricterBlocking {
                        VStack(spacing: 0) {
                            ForEach(Array(stricter.enumerated()), id: \.element.id) { _, choice in
                                Divider().padding(.leading, 56)
                                annoyanceRow(choice)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .clipped()
            }
            .clipped()
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: showStricterBlocking)
            Text("Cookie Notices is recommended by default. The other filters can sometimes break parts of a website.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stricterBlockingRow: some View {
        let activeCount = activeStricterAnnoyanceCount
        let summaryValue: String = activeCount > 0
            ? String.localizedStringWithFormat(
                NSLocalizedString("%d On", comment: "Count of active stricter blocking toggles"),
                activeCount
            )
            : NSLocalizedString("Off", comment: "Stricter blocking inactive value")

        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                showStricterBlocking.toggle()
            }
            UserDefaults.standard.set(showStricterBlocking, forKey: Self.stricterBlockingExpandedKey)
        } label: {
            HStack(spacing: 12) {
                IconBadge(
                    systemName: "slider.horizontal.3",
                    tint: .accentColor,
                    isOn: activeCount > 0
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Stricter Blocking")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("Social, chat, AI, and general")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                Text(summaryValue)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(showStricterBlocking ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .noFocusRingCompat()
    }

    private func annoyanceRow(_ choice: AnnoyanceChoice) -> some View {
        let bundle = BasicBundle.annoyance(choice)
        let state = bundle.state(in: filterManager.filterLists)
        let isOn = state != .off
        let rowSubtitle: String = choice == .general
            ? "\(choice.subtitle) \(NSLocalizedString("Also hides Google AI Overview.", comment: "General annoyance caveat"))"
            : choice.subtitle

        return HStack(spacing: 12) {
            Button {
                peekBundle = bundle
            } label: {
                HStack(spacing: 12) {
                    IconBadge(
                        systemName: choice.symbolName,
                        tint: choice.tint,
                        isOn: isOn,
                        ringPhase: ringPhase(for: bundle),
                        showsFailedDot: hasFailed(for: bundle)
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(LocalizedStringKey(choice.title))
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            if choice == .cookies {
                                Text("Recommended")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if state == .partlyOn {
                                Text("Custom")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.14), in: Capsule())
                            }
                        }
                        Text(rowSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .noFocusRingCompat()
            .infoPopoverAnchor(bundle.id)
            .accessibilityLabel(Text(LocalizedStringKey(choice.title)))
            .accessibilityValue(Text(state.accessibilityLabel))

            Toggle("", isOn: Binding(
                get: { isOn },
                set: { newValue in
                    toggleBundle(bundle, turnOn: newValue)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - More

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("More")
            groupedCard {
                languagesRow

                if !unownedActiveFilters.isEmpty {
                    Divider().padding(.leading, 56)
                    alsoOnRow
                }
            }
        }
    }

    private var languagesRow: some View {
        let isDirty = BasicBundle.isLanguagesDirty(
            in: filterManager.filterLists,
            appliedSelectedIDs: filterManager.appliedSelectedFilterIDs
        )
        let hasActiveForeign = filterManager.filterLists.contains { !$0.isCustom && $0.category == .foreign && $0.isSelected }

        return Button {
            showingLanguagesSheet = true
        } label: {
            HStack(spacing: 12) {
                IconBadge(
                    systemName: "globe",
                    tint: .accentColor,
                    isOn: hasActiveForeign,
                    ringPhase: rowRingPhase(isDirty: isDirty),
                    showsFailedDot: filterManager.lastBasicApplyFailed && isDirty
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Languages")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(verbatim: languageSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                RowDisclosureChevron()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .noFocusRingCompat()
        #if os(macOS)
        .popover(isPresented: $showingLanguagesSheet) {
            RegionalLanguageList(
                selectedLanguages: languageSelectionBinding,
                options: languageOptions
            )
        }
        #endif
    }

    private var alsoOnSummary: String {
        let active = unownedActiveFilters
        let customCount = active.filter(\.isCustom).count
        let otherCount = active.count - customCount
        if customCount > 0 && otherCount > 0 {
            return String.localizedStringWithFormat(
                NSLocalizedString("%d custom, %d other", comment: "Also on custom and built-in list count"),
                customCount,
                otherCount
            )
        }
        if customCount > 0 {
            return customCount == 1
                ? NSLocalizedString("1 custom list", comment: "Also on single custom list")
                : String.localizedStringWithFormat(
                    NSLocalizedString("%d custom lists", comment: "Also on multiple custom lists"),
                    customCount
                )
        }
        return active.count == 1
            ? NSLocalizedString("1 list", comment: "Also on single list")
            : String.localizedStringWithFormat(
                NSLocalizedString("%d lists", comment: "Also on active unowned lists count"),
                active.count
            )
    }

    private var alsoOnRow: some View {
        let isDirty = BasicBundle.isUnownedDirty(
            in: filterManager.filterLists,
            appliedSelectedIDs: filterManager.appliedSelectedFilterIDs,
            isBypassPaywallsCleanEnabled: isBypassPaywallsCleanEnabled
        )
        return Button {
            unownedSheetItem = AlsoOnSheetItem()
        } label: {
            HStack(spacing: 12) {
                IconBadge(
                    systemName: "square.stack.3d.up.fill",
                    tint: .accentColor,
                    isOn: true,
                    ringPhase: rowRingPhase(isDirty: isDirty),
                    showsFailedDot: filterManager.lastBasicApplyFailed && isDirty
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Also on")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(alsoOnSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                RowDisclosureChevron()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .noFocusRingCompat()
        .infoPopoverAnchor("alsoOn")
    }

    // MARK: - Footer

    private var footerSection: some View {
        Button {
            onSwitchToAdvanced()
        } label: {
            Text("Show All Filter Lists")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .noFocusRingCompat()
    }

    // MARK: - Actions & Derivation

    private func toggleBundle(_ bundle: BasicBundle, turnOn: Bool) {
        let changes = toggleMemory.selectionChanges(
            for: bundle,
            turnOn: turnOn,
            in: filterManager.filterLists
        )
        guard !changes.isEmpty else { return }
        for change in changes {
            filterManager.setFilterListSelection(id: change.id, selected: change.selected)
        }
        filterManager.flushPendingSave()
        filterManager.scheduleBasicAutoApply()
    }

    private func resetBundleToRecommended(_ bundle: BasicBundle) {
        let changes = toggleMemory.resetToRecommendedChanges(
            for: bundle,
            in: filterManager.filterLists
        )
        guard !changes.isEmpty else { return }
        for change in changes {
            filterManager.setFilterListSelection(id: change.id, selected: change.selected)
        }
        filterManager.flushPendingSave()
        filterManager.scheduleBasicAutoApply()
    }

    private func applyLanguageSelection(_ languages: Set<String>) {
        let normalized = Set(languages.map(RegionalLanguageOption.canonicalCode))
        storedLanguageCodes = normalized
        Self.sharedDefaults.set(Array(normalized).sorted(), forKey: OnboardingView.selectedLanguagesDefaultsKey)

        let foreignLists = filterManager.filterLists.filter { !$0.isCustom && $0.category == .foreign }
        let recommendedIDs = BasicBundle.recommendedRegionalFilterIDs(for: normalized, in: foreignLists)
        let updates = foreignLists.compactMap { filter -> (id: UUID, selected: Bool)? in
            let shouldBeSelected = recommendedIDs.contains(filter.id)
            return filter.isSelected != shouldBeSelected ? (id: filter.id, selected: shouldBeSelected) : nil
        }

        if !updates.isEmpty, filterManager.setFilterListSelections(updates) {
            if showingLanguagesSheet {
                // Wait until the picker closes before starting compile/reload
                // work so toggling multiple languages stays instant.
                hasPendingLanguageApply = true
                filterManager.markPendingBasicAutoApply()
            } else {
                filterManager.flushPendingSave()
                filterManager.scheduleBasicAutoApply()
            }
        }
    }

    private func ringPhase(for bundle: BasicBundle) -> BadgeRingPhase {
        let isDirty = bundle.isDirty(
            in: filterManager.filterLists,
            appliedSelectedIDs: filterManager.appliedSelectedFilterIDs
        )
        return rowRingPhase(isDirty: isDirty)
    }

    private func rowRingPhase(isDirty: Bool) -> BadgeRingPhase {
        if filterManager.isApplyInFlight && isDirty {
            return .applying(progress: applyProgress)
        }
        if filterManager.hasQueuedBasicAutoApply && isDirty {
            return .queued
        }
        if filterManager.lastBasicApplyFailed && isDirty {
            return .failed
        }
        return .idle
    }

    private func hasFailed(for bundle: BasicBundle) -> Bool {
        guard filterManager.lastBasicApplyFailed else { return false }
        let ownedIDs = Set(bundle.ownedFilters(in: filterManager.filterLists).map(\.id))
        return !ownedIDs.isDisjoint(with: filterManager.lastBasicApplyFailedFilterIDs)
    }

    // MARK: - Chrome Helpers

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    private func groupedCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
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

// MARK: - Peek Popover / Sheet

struct BasicBundlePeekView: View {
    let bundle: BasicBundle
    @ObservedObject var filterManager: AppFilterManager
    let state: BasicBundleState
    let onToggle: (Bool) -> Void
    let onResetToRecommended: () -> Void

    @AppStorage(ListDisplayOrder.filtersKey) private var filterDisplayOrder = Data()
    @State private var showAllLists = false
    @Environment(\.dismiss) private var dismiss

    private var scopedFilters: [FilterList] {
        FilterListPresentation.ordered(
            bundle.scopedFilters(in: filterManager.filterLists),
            order: filterDisplayOrder
        )
    }

    var body: some View {
        #if os(macOS)
        peekBody
            .padding(16)
            .frame(width: 360)
        #else
        if #available(iOS 16.0, *) {
            PeekSheetDetentsHost(showAllLists: $showAllLists) {
                ScrollView {
                    peekBody
                        .padding(SheetDesign.contentHorizontalPadding)
                }
                .scrollBounceBasedOnSizeCompat()
                .opaqueSheetBackgroundCompat()
            }
        } else {
            ScrollView {
                peekBody
                    .padding(SheetDesign.contentHorizontalPadding)
            }
        }
        #endif
    }

    private var peekBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconBadge(
                    systemName: bundle.symbolName,
                    tint: bundle.tint,
                    isOn: state != .off,
                    size: 34
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(bundle.localizedTitle)
                        .font(.headline)
                    Text(state.accessibilityLabel)
                        .font(.caption)
                        .foregroundStyle(state == .partlyOn ? Color.orange : Color.secondary)
                }

                Spacer(minLength: 8)

                SheetDoneButton { dismiss() }
            }

            Text(bundle.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Deliberate master switch (+ Reset to Recommended when customized)
            VStack(spacing: 0) {
                HStack {
                    Text("Enabled")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 12)
                    Toggle("", isOn: Binding(
                        get: { state != .off },
                        set: { onToggle($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .fixedSize()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                if state == .partlyOn {
                    Divider().padding(.leading, 12)
                    Button {
                        Haptics.play(.tap)
                        onResetToRecommended()
                    } label: {
                        HStack {
                            Text("Reset to Recommended")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .noFocusRingCompat()
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            // 3 plain examples
            VStack(alignment: .leading, spacing: 6) {
                Text("What this blocks")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ForEach(bundle.examples, id: \.self) { example in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(bundle.tint)
                        Text(example)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        showAllLists.toggle()
                    }
                } label: {
                    HStack {
                        Text("Customize Lists")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(showAllLists ? 180 : 0))
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .noFocusRingCompat()

                VStack(spacing: 0) {
                    if showAllLists {
                        inlineScopedLists
                            .padding(.horizontal, 6)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .clipped()
                .padding(.horizontal, -6)
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: showAllLists)
        }
    }

    @ViewBuilder
    private var inlineScopedLists: some View {
        let lists = scopedFilters
        let rows = VStack(spacing: 0) {
            ForEach(Array(lists.enumerated()), id: \.element.id) { index, filter in
                inlineScopedRow(filter)
                if index < lists.count - 1 {
                    Divider()
                }
            }
        }
        #if os(macOS)
        if lists.count > 4 {
            ScrollView {
                rows
                    .padding(.trailing, 4)
            }
            .frame(height: 220)
        } else {
            rows
        }
        #else
        rows
        #endif
    }

    private func inlineScopedRow(_ filter: FilterList) -> some View {
        let note = BasicBundle.concisePeekNote(for: filter)
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(filter.localizedDisplayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if filter.isCustom {
                        Text("Custom")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                }
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { filter.isSelected },
                set: { newValue in
                    if filterManager.setFilterListSelection(id: filter.id, selected: newValue) {
                        filterManager.flushPendingSave()
                        filterManager.scheduleBasicAutoApply()
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            #if os(macOS)
            .controlSize(.small)
            #endif
            .fixedSize()
        }
        .padding(.vertical, 7)
    }
}

#if os(iOS)
@available(iOS 16.0, *)
private struct PeekSheetDetentsHost<Content: View>: View {
    @Binding var showAllLists: Bool
    @ViewBuilder let content: () -> Content
    @State private var selectedDetent: PresentationDetent = .medium

    private var availableDetents: Set<PresentationDetent> {
        showAllLists ? [.medium, .large] : [.medium]
    }

    var body: some View {
        Group {
            if #available(iOS 16.4, *) {
                content()
                    .presentationContentInteraction(.scrolls)
            } else {
                content()
            }
        }
        .presentationDetents(availableDetents, selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .onAppear {
            if !showAllLists, selectedDetent != .medium {
                selectedDetent = .medium
            }
        }
        .onChangeCompat(of: showAllLists) { _, expanded in
            let target: PresentationDetent = expanded ? .large : .medium
            if selectedDetent != target {
                selectedDetent = target
            }
        }
        .onChangeCompat(of: selectedDetent) { _, detent in
            if detent == .medium, showAllLists {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    showAllLists = false
                }
            }
        }
    }
}
#endif

// MARK: - Scoped Category / Unowned Lists Sheet

/// Shows ONLY a single category's or unowned group's real filter lists and
/// returns straight to Basic on dismiss without ever flipping global AppMode.
/// Snapshots the presented filter IDs on open so toggling a custom or unowned
/// list off keeps its row visible until the sheet closes.
struct ScopedBundleListsSheet: View {
    let title: String
    @ObservedObject var filterManager: AppFilterManager
    let onMutation: () -> Void

    @State private var capturedFilterIDs: [UUID]
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        filters: [FilterList],
        filterManager: AppFilterManager,
        onMutation: @escaping () -> Void
    ) {
        self.title = title
        self.filterManager = filterManager
        self.onMutation = onMutation
        _capturedFilterIDs = State(initialValue: filters.map(\.id))
    }

    private var liveFilters: [FilterList] {
        let byID = Dictionary(uniqueKeysWithValues: filterManager.filterLists.map { ($0.id, $0) })
        return capturedFilterIDs.compactMap { byID[$0] }
    }

    var body: some View {
        #if os(macOS)
        sheetBody
            .padding(16)
            .frame(width: 360)
        #else
        ScrollView {
            sheetBody
                .padding(SheetDesign.contentHorizontalPadding)
        }
        .scrollBounceBasedOnSizeCompat()
        .opaqueSheetBackgroundCompat()
        .modifier(AlsoOnSheetDetentsCompat())
        #endif
    }

    private var sheetBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconBadge(
                    systemName: "square.stack.3d.up.fill",
                    tint: .accentColor,
                    isOn: liveFilters.contains(where: \.isSelected),
                    size: 34
                )

                Text(title)
                    .font(.headline)

                Spacer(minLength: 8)

                SheetDoneButton { dismiss() }
            }

            Divider()

            let rows = VStack(spacing: 0) {
                ForEach(Array(liveFilters.enumerated()), id: \.element.id) { index, filter in
                    scopedRow(filter)
                    if index < liveFilters.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 6)

            #if os(macOS)
            if liveFilters.count > 5 {
                ScrollView {
                    rows
                        .padding(.trailing, 4)
                }
                .frame(height: 260)
                .padding(.horizontal, -6)
            } else {
                rows
                    .padding(.horizontal, -6)
            }
            #else
            rows
                .padding(.horizontal, -6)
            #endif
        }
    }

    private func scopedRow(_ filter: FilterList) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(filter.localizedDisplayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if filter.isCustom {
                        Text("Custom")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                }
                if !filter.localizedDisplayDescription.isEmpty {
                    Text(filter.localizedDisplayDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { filter.isSelected },
                set: { newValue in
                    if filterManager.setFilterListSelection(id: filter.id, selected: newValue) {
                        filterManager.flushPendingSave()
                        onMutation()
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            #if os(macOS)
            .controlSize(.small)
            #endif
            .fixedSize()
        }
        .padding(.vertical, 7)
    }
}

#if os(iOS)
private struct AlsoOnSheetDetentsCompat: ViewModifier {
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

// MARK: - Scroll Tracking

private struct BasicScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ScrollOffsetTracker: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: BasicScrollOffsetKey.self,
                value: -proxy.frame(in: .named("basicFiltersScroll")).minY
            )
        }
    }
}

private struct HeroScrollVisibilityCompat: ViewModifier {
    let onVisibilityChange: (Bool) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.onScrollVisibilityChange(threshold: 0.15) { visible in
                onVisibilityChange(visible)
            }
        } else {
            content
        }
    }
}
