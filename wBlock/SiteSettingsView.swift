import SwiftUI
import wBlockCoreService

/// Unified per-site settings: whitelist state, per-site userscript exceptions,
/// and element zapper rules. One card, one expandable row per domain.
struct SiteSettingsView: View {
    @ObservedObject var filterManager: AppFilterManager
    @ObservedObject private var dataManager = ProtobufDataManager.shared
    @ObservedObject private var ruleManager = ZapperRuleManager.shared
    @ObservedObject private var userScriptManager = UserScriptManager.shared
    @State private var newDomain: String = ""
    @State private var isAddingDomain: Bool = false
    @State private var searchText: String = ""
    @State private var showSearch: Bool = false
    @State private var expandedDomains: Set<String> = []
    @State private var domainPendingReset: String? = nil
    @State private var pendingUndo: (rule: String, domain: String, index: Int)? = nil
    @FocusState private var isTextFieldFocused: Bool

    private struct SiteSummary: Identifiable {
        let domain: String
        let isWhitelisted: Bool
        let scriptsOffCount: Int
        let zapperRuleCount: Int
        let isZapperDisabled: Bool

        var id: String { domain }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 20) {
                    addSiteSection

                    let sites = filteredSites
                    if !sites.isEmpty {
                        sitesCard(sites)
                    } else if allSites.isEmpty {
                        emptyStateView
                    }

                    Spacer(minLength: pendingUndo != nil ? 72 : 20)
                }
                .padding(.vertical)
                .padding(.horizontal)
            }

            if pendingUndo != nil {
                undoBanner
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: pendingUndo?.rule)
        .navigationTitle("Site Settings")
        .task {
            await ruleManager.refreshNow()
        }
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                ToolbarSearchField(text: $searchText, isExpanded: $showSearch)
            }
        }
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .searchableCompat(text: $searchText, isPresented: $showSearch, prompt: "Search")
        #endif
        .alert(
            "Reset Site Settings",
            isPresented: Binding(
                get: { domainPendingReset != nil },
                set: { if !$0 { domainPendingReset = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { domainPendingReset = nil }
            Button("Remove", role: .destructive) {
                if let domain = domainPendingReset {
                    resetSite(domain)
                }
                domainPendingReset = nil
            }
        } message: {
            Text(
                String(
                    format: NSLocalizedString(
                        "This removes the whitelist entry, userscript exceptions, and zapper rules for %@.",
                        comment: "Reset site settings confirmation message"
                    ),
                    domainPendingReset ?? ""
                )
            )
        }
    }

    // MARK: - Add site

    private var addableDomain: String? {
        guard let normalized = DisabledSitesNormalizer.normalizedDomain(newDomain) else { return nil }
        let existing = DisabledSitesNormalizer.normalizedDomains(from: dataManager.disabledSites)
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
        let exceptionsByScript = dataManager.getUserScriptDisabledHosts()
        var scriptsOffByHost: [String: Int] = [:]
        for hosts in exceptionsByScript.values {
            for host in hosts {
                scriptsOffByHost[host, default: 0] += 1
            }
        }

        var domains = whitelisted
        domains.formUnion(ruleManager.domains)
        domains.formUnion(scriptsOffByHost.keys)

        return domains.sorted().map { domain in
            SiteSummary(
                domain: domain,
                isWhitelisted: whitelisted.contains(domain),
                scriptsOffCount: scriptsOffByHost[domain] ?? 0,
                zapperRuleCount: ruleManager.ruleCount(forDomain: domain),
                isZapperDisabled: ruleManager.isDisabled(domain)
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
                    }
                    if site.scriptsOffCount > 0 {
                        summaryBadge(
                            Text(localizedScriptsOffCount(site.scriptsOffCount)),
                            systemImage: "scroll"
                        )
                    }
                    if site.zapperRuleCount > 0 {
                        summaryBadge(
                            Text(localizedRuleCount(site.zapperRuleCount)),
                            systemImage: "wand.and.stars",
                            struckThrough: site.isZapperDisabled
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
                domainPendingReset = site.domain
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

        ForEach(siteUserScripts(for: site.domain)) { script in
            toggleRow(isOn: Binding(
                get: { !userScriptManager.isUserScript(script, disabledOnHost: site.domain) },
                set: { runs in
                    Task { @MainActor in
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

        let rules = ruleManager.rules(for: site.domain)
        if !rules.isEmpty {
            toggleRow(isOn: Binding(
                get: { !ruleManager.isDisabled(site.domain) },
                set: { apply in
                    ruleManager.setDisabled(!apply, forDomain: site.domain)
                    filterManager.markNonSelectionChangesPending()
                }
            )) {
                Text("Apply rules on this site")
                    .font(.body)
            }

            ForEach(rules.indices, id: \.self) { ruleIndex in
                let rule = rules[ruleIndex]

                VStack(spacing: 0) {
                    Divider()
                        .padding(.leading, 16)

                    HStack(alignment: .center, spacing: 12) {
                        Text(rule)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer()

                        Button {
                            deleteRule(rule, from: site.domain, at: ruleIndex)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 18))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 10)
                    .padding(.leading, 32)
                    .padding(.trailing, 16)
                }
            }

            Text("Changes take full effect after the next apply.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 32)
                .padding(.trailing, 16)
                .padding(.bottom, 12)
        }

        VStack(spacing: 0) {
            Divider()
                .padding(.leading, 16)

            Button {
                domainPendingReset = site.domain
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

    // MARK: - Undo banner

    private var undoBanner: some View {
        HStack {
            Text("Rule deleted")
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            Button("Undo") {
                if let undo = pendingUndo {
                    ruleManager.restoreRule(undo.rule, forDomain: undo.domain, at: undo.index)
                    pendingUndo = nil
                }
            }
            .font(.subheadline.bold())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        .task(id: pendingUndo?.rule) {
            guard pendingUndo != nil else { return }
            try? await TaskSleep.sleep(for: .seconds(5))
            await MainActor.run {
                pendingUndo = nil
            }
        }
    }

    // MARK: - State helpers

    private func isWhitelisted(_ domain: String) -> Bool {
        DisabledSitesNormalizer.normalizedDomains(from: dataManager.disabledSites).contains(domain)
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
        guard let normalizedDomain = addableDomain else { return }

        isAddingDomain = true

        Task { @MainActor in
            let currentDomains = DisabledSitesNormalizer.normalizedDomains(from: dataManager.disabledSites)
            let updatedDomains = DisabledSitesNormalizer.normalizedDomains(
                from: currentDomains + [normalizedDomain]
            )
            await dataManager.setWhitelistedDomains(updatedDomains)
            newDomain = ""
            isAddingDomain = false
            isTextFieldFocused = true
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedDomains.insert(normalizedDomain)
            }
        }
    }

    private func setWhitelisted(_ whitelisted: Bool, domain: String) {
        Task { @MainActor in
            let currentDomains = DisabledSitesNormalizer.normalizedDomains(from: dataManager.disabledSites)
            let updatedDomains: [String]
            if whitelisted {
                guard !currentDomains.contains(domain) else { return }
                updatedDomains = DisabledSitesNormalizer.normalizedDomains(from: currentDomains + [domain])
            } else {
                updatedDomains = currentDomains.filter { $0 != domain }
            }
            await dataManager.setWhitelistedDomains(updatedDomains)
        }
    }

    private func deleteRule(_ rule: String, from domain: String, at index: Int) {
        pendingUndo = (rule: rule, domain: domain, index: index)
        ruleManager.deleteRule(rule, forDomain: domain)
        filterManager.markNonSelectionChangesPending()
    }

    private func resetSite(_ domain: String) {
        Task { @MainActor in
            let currentDomains = DisabledSitesNormalizer.normalizedDomains(from: dataManager.disabledSites)
            if currentDomains.contains(domain) {
                await dataManager.setWhitelistedDomains(currentDomains.filter { $0 != domain })
            }

            for (scriptID, hosts) in dataManager.getUserScriptDisabledHosts() where hosts.contains(domain) {
                await dataManager.setUserScriptDisabledHosts(
                    hosts.filter { $0 != domain },
                    forScriptID: scriptID
                )
            }

            if ruleManager.ruleCount(forDomain: domain) > 0 {
                ruleManager.deleteAllRules(forDomain: domain)
                filterManager.markNonSelectionChangesPending()
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

    private func localizedRuleCount(_ count: Int) -> String {
        let key = count == 1 ? "%d rule" : "%d rules"
        return String.localizedStringWithFormat(
            NSLocalizedString(key, comment: "Element zapper rule count"),
            count
        )
    }
}
