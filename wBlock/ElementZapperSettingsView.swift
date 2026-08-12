import SwiftUI
import wBlockCoreService

/// Per-domain element zapper rules and their apply switches.
struct ElementZapperSettingsView: View {
    @ObservedObject var filterManager: AppFilterManager
    @ObservedObject private var dataManager = ProtobufDataManager.shared
    @ObservedObject private var ruleManager = ZapperRuleManager.shared
    @State private var searchText = ""
    @State private var expandedDomains: Set<String> = []
    @State private var pendingConfirmation: PendingConfirmation?
    @State private var pendingUndo: UndoEntry?
    #if os(macOS)
    @State private var showSearch = false
    #endif

    private enum PendingConfirmation: Identifiable {
        case clearAll
        var id: String { "clear-all" }
    }

    private struct UndoEntry {
        let rule: String
        let domain: String
        let index: Int
    }

    private var filteredDomains: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return ruleManager.domains }
        return ruleManager.domains.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 16) {
                    if !ruleManager.domains.isEmpty {
                        Button(role: .destructive) {
                            pendingConfirmation = .clearAll
                        } label: {
                            Label("Clear Element Zapper Rules", systemImage: "trash")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }

                    if filteredDomains.isEmpty {
                        emptyState
                    } else {
                        rulesCard
                    }

                    Spacer(minLength: pendingUndo == nil ? 20 : 72)
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
        .navigationTitle("Element Zapper")
        .task { await ruleManager.refreshNow() }
        .alert(item: $pendingConfirmation) { confirmation in
            switch confirmation {
            case .clearAll:
                return Alert(
                    title: Text("Clear Element Zapper Rules?"),
                    message: Text("This removes all saved element zapper rules from every site."),
                    primaryButton: .destructive(Text("Clear All")) {
                        clearAllRules()
                    },
                    secondaryButton: .cancel(Text("Cancel"))
                )
            }
        }
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
    }

    private var rulesCard: some View {
        VStack(spacing: 0) {
            ForEach(filteredDomains, id: \.self) { domain in
                domainHeader(domain)
                if expandedDomains.contains(domain) {
                    domainRules(domain)
                }
                if domain != filteredDomains.last {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func domainHeader(_ domain: String) -> some View {
        let expanded = expandedDomains.contains(domain)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if expanded { expandedDomains.remove(domain) }
                else { expandedDomains.insert(domain) }
            }
        } label: {
            HStack {
                Text(domain)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(localizedRuleCount(ruleManager.ruleCount(forDomain: domain)))
                    .strikethrough(ruleManager.isDisabled(domain))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func domainRules(_ domain: String) -> some View {
        zapperToggle(domain)
        ForEach(ruleManager.rules(for: domain).indices, id: \.self) { index in
            let rule = ruleManager.rules(for: domain)[index]
            VStack(spacing: 0) {
                Divider().padding(.leading, 16)
                HStack(spacing: 12) {
                    Text(rule)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Button {
                        deleteRule(rule, from: domain, at: index)
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

    private func zapperToggle(_ domain: String) -> some View {
        VStack(spacing: 0) {
            Divider().padding(.leading, 16)
            HStack {
                Text("Apply rules on this site")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { !ruleManager.isDisabled(domain) },
                    set: { enabled in
                        Task { @MainActor in
                            await dataManager.setZapperRulesDisabled(!enabled, forHost: domain)
                            await ruleManager.refreshNow()
                            filterManager.markNonSelectionChangesPending()
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            .padding(.vertical, 10)
            .padding(.leading, 32)
            .padding(.trailing, 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 44))
                .foregroundStyle(.secondary.opacity(0.6))
            Text("No zapper rules for this site.")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var undoBanner: some View {
        HStack {
            Text("Rule deleted")
            Spacer()
            Button("Undo") { restoreDeletedRule() }
            .font(.subheadline.bold())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        .task(id: pendingUndo?.rule) {
            guard pendingUndo != nil else { return }
            try? await TaskSleep.sleep(for: .seconds(5))
            pendingUndo = nil
        }
    }

    private func deleteRule(_ rule: String, from domain: String, at index: Int) {
        Task { @MainActor in
            await dataManager.deleteZapperRule(rule, forHost: domain)
            await ruleManager.refreshNow()
            pendingUndo = UndoEntry(rule: rule, domain: domain, index: index)
            filterManager.markNonSelectionChangesPending()
        }
    }

    private func restoreDeletedRule() {
        guard let undo = pendingUndo else { return }
        Task { @MainActor in
            await dataManager.restoreZapperRule(undo.rule, forHost: undo.domain, at: undo.index)
            await ruleManager.refreshNow()
            pendingUndo = nil
            filterManager.markNonSelectionChangesPending()
        }
    }

    private func clearAllRules() {
        Task { @MainActor in
            for domain in dataManager.getZapperDomains() {
                await dataManager.deleteAllZapperRules(forHost: domain)
            }
            await ruleManager.refreshNow()
            pendingUndo = nil
            filterManager.markNonSelectionChangesPending()
        }
    }

    private func localizedRuleCount(_ count: Int) -> String {
        let key = count == 1 ? "%d rule" : "%d rules"
        return String.localizedStringWithFormat(NSLocalizedString(key, comment: "Element zapper rule count"), count)
    }
}
