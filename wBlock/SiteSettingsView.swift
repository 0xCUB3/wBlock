import SwiftUI
import wBlockCoreService

/// Per-site blocking and userscript settings. Element Zapper has its own destination.
struct SiteSettingsView: View {
    @ObservedObject private var dataManager = ProtobufDataManager.shared
    @ObservedObject private var userScriptManager = UserScriptManager.shared
    @State private var newDomain: String = ""
    @State private var isAddingDomain: Bool = false
    @State private var searchText: String = ""
    #if os(macOS)
    @State private var showSearch: Bool = false
    #endif
    @State private var expandedDomains: Set<String> = []
    private enum PendingConfirmation: Identifiable {
        case reset(domain: String)

        var id: String {
            switch self {
            case .reset(let domain): return "reset:\(domain)"
            }
        }
    }

    private struct SiteSettingsSnapshot: Equatable {
        let isWhitelisted: Bool
        let isFilterDisabled: Bool
        let isAutoplayAllowed: Bool
        let disabledScriptIDs: Set<String>
    }

    private struct SiteUndoState {
        let id = UUID()
        let domain: String
        let before: SiteSettingsSnapshot
        let after: SiteSettingsSnapshot
    }

    @State private var pendingConfirmation: PendingConfirmation?
    @State private var pendingUndo: SiteUndoState?
    @State private var pendingRedo: SiteUndoState?
    @State private var isMutationInFlight = false
    @State private var mutationGeneration = 0
    @FocusState private var isTextFieldFocused: Bool

    private struct SiteSummary: Identifiable {
        let domain: String
        let isWhitelisted: Bool
        let isFilterDisabled: Bool
        let isAutoplayAllowed: Bool
        let scriptsOffCount: Int

        var id: String { domain }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 20) {
                    addSiteSection
                        .disabled(isMutationInFlight)

                    let sites = filteredSites
                    if !sites.isEmpty {
                        sitesCard(sites)
                            .disabled(isMutationInFlight)
                    } else if allSites.isEmpty {
                        emptyStateView
                    }

                    Spacer(minLength: pendingUndo != nil || pendingRedo != nil ? 72 : 20)
                }
                .padding(.vertical)
                .padding(.horizontal)
            }

            if pendingUndo != nil || pendingRedo != nil {
                undoBanner
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: pendingUndo?.id)
        .animation(.easeInOut(duration: 0.25), value: pendingRedo?.id)
        .navigationTitle("Site Settings")
        #if os(iOS)
        .searchable(text: $searchText, prompt: "Search")
        .navigationBarTitleDisplayMode(.inline)
        #else
        .toolbar {
            ToolbarItem(placement: .automatic) {
                ToolbarSearchField(text: $searchText, isExpanded: $showSearch)
            }
        }
        #endif
        .alert(item: $pendingConfirmation) { confirmation in
            switch confirmation {
            case .reset(let domain):
                return Alert(
                    title: Text("Reset Site Settings"),
                    message: Text(
                        String.localizedStringWithFormat(
                            NSLocalizedString(
                                "This removes all settings for %@.",
                                comment: "Reset site settings confirmation message"
                            ),
                            domain
                        )
                    ),
                    primaryButton: .destructive(Text("Remove")) {
                        resetSite(domain)
                    },
                    secondaryButton: .cancel(Text("Cancel"))
                )
            }
        }
    }

    // MARK: - Add site

    private var addableDomain: String? {
        guard let normalized = DisabledSitesNormalizer.normalizedDomain(newDomain) else { return nil }
        let existing = Set(DisabledSitesNormalizer.normalizedDomains(from: dataManager.disabledSites))
            .union(DisabledSitesNormalizer.normalizedDomains(from: dataManager.filterDisabledSites))
            .union(DisabledSitesNormalizer.normalizedDomains(from: dataManager.noAutoplayAllowedSites))
        return existing.contains(normalized) ? nil : normalized
    }

    private var addSiteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                TextField("example.com", text: $newDomain)
                    .textFieldStyle(.plain)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        addDomain()
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                Button {
                    addDomain()
                } label: {
                    Image(systemName: isAddingDomain ? "hourglass" : "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(addableDomain == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                }
                .buttonStyle(.plain)
                .disabled(addableDomain == nil || isAddingDomain)
            }

            Text("Added sites are whitelisted: wBlock is completely turned off on them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Site list

    private var allSites: [SiteSummary] {
        let whitelisted = Set(DisabledSitesNormalizer.normalizedDomains(from: dataManager.disabledSites))
        let filterDisabled = Set(DisabledSitesNormalizer.normalizedDomains(from: dataManager.filterDisabledSites))
        let autoplayAllowed = Set(DisabledSitesNormalizer.normalizedDomains(from: dataManager.noAutoplayAllowedSites))
        let exceptionsByScript = dataManager.getUserScriptDisabledHosts()
        var scriptsOffByHost: [String: Int] = [:]
        for hosts in exceptionsByScript.values {
            for host in hosts {
                scriptsOffByHost[host, default: 0] += 1
            }
        }

        var domains = whitelisted
        domains.formUnion(filterDisabled)
        domains.formUnion(autoplayAllowed)
        domains.formUnion(scriptsOffByHost.keys)

        return domains.sorted().map { domain in
            SiteSummary(
                domain: domain,
                isWhitelisted: whitelisted.contains(domain),
                isFilterDisabled: filterDisabled.contains(domain),
                isAutoplayAllowed: autoplayAllowed.contains(domain),
                scriptsOffCount: scriptsOffByHost[domain] ?? 0,
            )
        }

    }

    private var filteredSites: [SiteSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return allSites }
        return allSites.filter { $0.domain.contains(query) }
    }

    private func sitesCard(_ sites: [SiteSummary]) -> some View {
        VStack(spacing: 0) {
            ForEach(sites.indices, id: \.self) { index in
                let site = sites[index]

                siteHeaderRow(site)

                if expandedDomains.contains(site.domain) {
                    expansionRows(site)
                }

                if index < sites.count - 1 {
                    Divider()
                        .padding(.leading, 16)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func siteHeaderRow(_ site: SiteSummary) -> some View {
        let isExpanded = expandedDomains.contains(site.domain)

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isExpanded {
                    expandedDomains.remove(site.domain)
                } else {
                    expandedDomains.insert(site.domain)
                }
            }
        } label: {
            HStack {
                Text(site.domain)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                HStack(spacing: 8) {
                    if site.isWhitelisted {
                        summaryBadge(Text("Whitelisted"), systemImage: "shield.slash")
                    } else if site.isFilterDisabled {
                        summaryBadge(Text("Filtering off"), systemImage: "line.3.horizontal.decrease.circle")
                    }
                    if site.isAutoplayAllowed {
                        summaryBadge(Text("Autoplay on"), systemImage: "play.circle")
                    }
                    if site.scriptsOffCount > 0 {
                        summaryBadge(
                            Text(localizedScriptsOffCount(site.scriptsOffCount)),
                            systemImage: "scroll"
                        )
                    }
                }
                .padding(.trailing, 4)

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                pendingConfirmation = .reset(domain: site.domain)
            } label: {
                Label("Reset Site Settings", systemImage: "trash")
            }
        }
    }

    private func summaryBadge(_ text: Text, systemImage: String, struckThrough: Bool = false) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            text.strikethrough(struckThrough)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Expanded rows

    @ViewBuilder
    private func expansionRows(_ site: SiteSummary) -> some View {
        toggleRow(isOn: Binding(
            get: { isWhitelisted(site.domain) },
            set: { setWhitelisted($0, domain: site.domain) }
        )) {
            Text("Disable on this site")
                .font(.body)
        }

        toggleRow(isOn: Binding(
            get: { !isFilterDisabled(site.domain) },
            set: { setFilterDisabled(!$0, domain: site.domain) }
        )) {
            Text("Content filtering")
                .font(.body)
        }
        .disabled(site.isWhitelisted)

        toggleRow(isOn: Binding(
            get: { isAutoplayAllowed(site.domain) },
            set: { setAutoplayAllowed($0, domain: site.domain) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Allow autoplay on this site")
                    .font(.body)
                Text("Takes effect when No Autoplay is on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(site.isWhitelisted)

        ForEach(siteUserScripts(for: site.domain)) { script in
            toggleRow(isOn: Binding(
                get: { !userScriptManager.isUserScript(script, disabledOnHost: site.domain) },
                set: { runs in
                    mutateSite(site.domain) {
                        await userScriptManager.setUserScript(
                            withId: script.id,
                            disabledOnHost: site.domain,
                            disabled: !runs
                        )
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(script.name)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("Run on this site")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        VStack(spacing: 0) {
            Divider()
                .padding(.leading, 16)

            Button {
                pendingConfirmation = .reset(domain: site.domain)
            } label: {
                HStack {
                    Text("Reset Site Settings")
                        .font(.body)
                        .foregroundStyle(.red)

                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.leading, 32)
                .padding(.trailing, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func toggleRow<Label: View>(
        isOn: Binding<Bool>,
        @ViewBuilder label: () -> Label
    ) -> some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.leading, 16)

            HStack {
                label()

                Spacer()

                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(.vertical, 10)
            .padding(.leading, 32)
            .padding(.trailing, 16)
        }
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "globe")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.6))

            Text("No Site Settings")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Whitelist a site here, or adjust userscripts and element zapper rules per site from the wBlock popup in Safari.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Undo and redo

    private var undoBanner: some View {
        HStack {
            Text("Site Settings")
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            if pendingUndo != nil {
                Button("Undo") { undoSiteMutation() }
                    .font(.subheadline.bold())
                    .disabled(isMutationInFlight)
            }
            if pendingRedo != nil {
                Button("Redo") { redoSiteMutation() }
                    .font(.subheadline.bold())
                    .disabled(isMutationInFlight)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
    }

    private func undoSiteMutation() {
        guard let state = pendingUndo, let generation = beginMutation() else { return }
        Task { @MainActor in
            defer { finishMutation(generation) }
            await apply(state.before, to: state.domain)
            guard generation == mutationGeneration else { return }
            pendingUndo = nil
            pendingRedo = state
        }
    }

    private func redoSiteMutation() {
        guard let state = pendingRedo, let generation = beginMutation() else { return }
        Task { @MainActor in
            defer { finishMutation(generation) }
            await apply(state.after, to: state.domain)
            guard generation == mutationGeneration else { return }
            pendingRedo = nil
            pendingUndo = state
        }
    }

    // MARK: - State helpers

    private func siteSnapshot(_ domain: String) -> SiteSettingsSnapshot {
        let disabledHosts = dataManager.getUserScriptDisabledHosts()
        return SiteSettingsSnapshot(
            isWhitelisted: isWhitelisted(domain),
            isFilterDisabled: isFilterDisabled(domain),
            isAutoplayAllowed: isAutoplayAllowed(domain),
            disabledScriptIDs: Set(disabledHosts.compactMap { scriptID, hosts in
                hosts.contains(domain) ? scriptID : nil
            })
        )
    }

    private func mutateSite(_ domain: String, operation: @escaping @MainActor () async -> Void) {
        guard let generation = beginMutation() else { return }
        Task { @MainActor in
            defer { finishMutation(generation) }
            let before = siteSnapshot(domain)
            await operation()
            guard generation == mutationGeneration else { return }
            let after = siteSnapshot(domain)
            guard before != after else { return }
            pendingUndo = SiteUndoState(domain: domain, before: before, after: after)
            pendingRedo = nil
        }
    }

    private func beginMutation() -> Int? {
        guard !isMutationInFlight else { return nil }
        mutationGeneration += 1
        isMutationInFlight = true
        return mutationGeneration
    }

    private func finishMutation(_ generation: Int) {
        guard generation == mutationGeneration else { return }
        isMutationInFlight = false
    }

    private func apply(_ snapshot: SiteSettingsSnapshot, to domain: String) async {
        let domains = DisabledSitesNormalizer.normalizedDomains(from: dataManager.disabledSites)
        await dataManager.setWhitelistedDomains(snapshot.isWhitelisted ? DisabledSitesNormalizer.normalizedDomains(from: domains + [domain]) : domains.filter { $0 != domain })
        let filterDomains = DisabledSitesNormalizer.normalizedDomains(from: dataManager.filterDisabledSites)
        await dataManager.setFilterDisabledDomains(snapshot.isFilterDisabled ? DisabledSitesNormalizer.normalizedDomains(from: filterDomains + [domain]) : filterDomains.filter { $0 != domain })
        await dataManager.setNoAutoplaySiteAllowed(snapshot.isAutoplayAllowed, onHost: domain)
        let disabledHosts = dataManager.getUserScriptDisabledHosts()
        for scriptID in Set(disabledHosts.keys).union(snapshot.disabledScriptIDs) {
            var hosts = disabledHosts[scriptID] ?? []
            hosts.removeAll { $0 == domain }
            if snapshot.disabledScriptIDs.contains(scriptID) { hosts.append(domain) }
            await dataManager.setUserScriptDisabledHosts(Array(Set(hosts)).sorted(), forScriptID: scriptID)
        }
    }

    private func isWhitelisted(_ domain: String) -> Bool {
        DisabledSitesNormalizer.normalizedDomains(from: dataManager.disabledSites).contains(domain)
    }

    private func isFilterDisabled(_ domain: String) -> Bool {
        DisabledSitesNormalizer.normalizedDomains(from: dataManager.filterDisabledSites).contains(domain)
    }

    private func isAutoplayAllowed(_ domain: String) -> Bool {
        DisabledSitesNormalizer.normalizedDomains(from: dataManager.noAutoplayAllowedSites).contains(domain)
    }

    private func siteUserScripts(for domain: String) -> [UserScript] {
        let syntheticURL = "https://\(domain)/"
        let exceptions = dataManager.getUserScriptDisabledHosts()
        return userScriptManager.userScripts
            .filter { script in
                guard script.isEnabled else { return false }
                if script.matches(url: syntheticURL) { return true }
                return exceptions[script.id.uuidString]?.contains(domain) ?? false
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Actions

    private func addDomain() {
        guard !isMutationInFlight, let normalizedDomain = addableDomain else { return }
        isAddingDomain = true
        mutateSite(normalizedDomain) {
            let currentDomains = DisabledSitesNormalizer.normalizedDomains(from: dataManager.disabledSites)
            await dataManager.setWhitelistedDomains(DisabledSitesNormalizer.normalizedDomains(from: currentDomains + [normalizedDomain]))
            newDomain = ""
            isAddingDomain = false
            isTextFieldFocused = true
            withAnimation(.easeInOut(duration: 0.2)) { _ = expandedDomains.insert(normalizedDomain) }
        }
    }

    private func setFilterDisabled(_ disabled: Bool, domain: String) {
        mutateSite(domain) {
            let currentDomains = DisabledSitesNormalizer.normalizedDomains(from: dataManager.filterDisabledSites)
            let updated = disabled ? DisabledSitesNormalizer.normalizedDomains(from: currentDomains + [domain]) : currentDomains.filter { $0 != domain }
            await dataManager.setFilterDisabledDomains(updated)
        }
    }

    private func setWhitelisted(_ whitelisted: Bool, domain: String) {
        mutateSite(domain) {
            let currentDomains = DisabledSitesNormalizer.normalizedDomains(from: dataManager.disabledSites)
            let updated = whitelisted ? DisabledSitesNormalizer.normalizedDomains(from: currentDomains + [domain]) : currentDomains.filter { $0 != domain }
            await dataManager.setWhitelistedDomains(updated)
        }
    }

    private func setAutoplayAllowed(_ allowed: Bool, domain: String) {
        mutateSite(domain) {
            await dataManager.setNoAutoplaySiteAllowed(allowed, onHost: domain)
        }
    }

    private func resetSite(_ domain: String) {
        mutateSite(domain) {
            let currentDomains = DisabledSitesNormalizer.normalizedDomains(from: dataManager.disabledSites)
            if currentDomains.contains(domain) { await dataManager.setWhitelistedDomains(currentDomains.filter { $0 != domain }) }
            let filterDomains = DisabledSitesNormalizer.normalizedDomains(from: dataManager.filterDisabledSites)
            if filterDomains.contains(domain) { await dataManager.setFilterDisabledDomains(filterDomains.filter { $0 != domain }) }
            let autoplaySites = DisabledSitesNormalizer.normalizedDomains(from: dataManager.noAutoplayAllowedSites)
            if autoplaySites.contains(domain) { await dataManager.setNoAutoplaySiteAllowed(false, onHost: domain) }
            for (scriptID, hosts) in dataManager.getUserScriptDisabledHosts() where hosts.contains(domain) {
                await dataManager.setUserScriptDisabledHosts(hosts.filter { $0 != domain }, forScriptID: scriptID)
            }
            expandedDomains.remove(domain)
        }
    }

    private func localizedScriptsOffCount(_ count: Int) -> String {
        let key = count == 1 ? "%d script off" : "%d scripts off"
        return String.localizedStringWithFormat(
            NSLocalizedString(key, comment: "Per-site disabled userscript count"),
            count
        )
    }

}
