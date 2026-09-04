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
    @State private var isMutating = false
    @State private var mutationVersion = 0
    #if os(macOS)
    @State private var showSearch = false
    #endif

    private enum PendingConfirmation: Identifiable {
        case clear(domain: String)
        var id: String {
            switch self { case .clear(let domain): return domain }
        }
    }

    private struct UndoEntry {
        let rule: String
        let domain: String
        let originalIndex: Int
        let previousRule: String?
        let nextRule: String?
        let version: Int
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
        .disabled(isMutating || ruleManager.isMutationInFlight)
        .navigationTitle("Element Zapper")
        .task { await ruleManager.refreshNow() }
        .alert(item: $pendingConfirmation) { confirmation in
            switch confirmation {
            case .clear(let domain):
                return Alert(
                    title: Text("Clear Element Zapper Rules?"),
                    message: Text(domain),
                    primaryButton: .destructive(Text("Remove")) {
                        clearRules(for: domain)
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
        .noFocusRingCompat()
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
                    .noFocusRingCompat()
                }
                .padding(.vertical, 10)
                .padding(.leading, 32)
                .padding(.trailing, 16)
            }
        }
        Divider().padding(.leading, 16)
        Button {
            pendingConfirmation = .clear(domain: domain)
        } label: {
            HStack {
                Text("Clear Element Zapper Rules")
                    .foregroundStyle(.red)
                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.leading, 32)
            .padding(.trailing, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .noFocusRingCompat()
        Text("Element Zapper changes take full effect after the next apply.")
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
                        invalidateUndoAndStartMutation {
                            await ruleManager.performMutation {
                                await dataManager.setZapperRulesDisabled(!enabled, forHost: domain)
                                await ruleManager.refreshNow()
                                filterManager.markNonSelectionChangesPending()
                            }
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
            Text("No Element Zapper Rules")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Use the element zapper in the wBlock popup in Safari to hide page elements.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
        guard !isMutating else { return }
        let currentRules = ruleManager.rules(for: domain)
        guard index < currentRules.count, currentRules[index] == rule else { return }
        let version = beginMutation(invalidateUndo: true)
        let undo = UndoEntry(
            rule: rule,
            domain: domain,
            originalIndex: index,
            previousRule: index > 0 ? currentRules[index - 1] : nil,
            nextRule: index + 1 < currentRules.count ? currentRules[index + 1] : nil,
            version: version
        )
        Task { @MainActor in
            await ruleManager.performMutation {
                await dataManager.deleteZapperRule(rule, forHost: domain)
                await ruleManager.refreshNow()
                filterManager.markNonSelectionChangesPending()
            }
            guard mutationVersion == version else { return }
            pendingUndo = undo
            isMutating = false
        }
    }

    private func restoreDeletedRule() {
        guard !isMutating, let undo = pendingUndo, undo.version == mutationVersion else { return }
        let currentRules = ruleManager.rules(for: undo.domain)
        guard !currentRules.contains(undo.rule) else {
            pendingUndo = nil
            return
        }
        let version = beginMutation(invalidateUndo: false)
        let insertIndex: Int
        if let nextRule = undo.nextRule, let nextIndex = currentRules.firstIndex(of: nextRule) {
            insertIndex = nextIndex
        } else if let previousRule = undo.previousRule, let previousIndex = currentRules.firstIndex(of: previousRule) {
            insertIndex = previousIndex + 1
        } else {
            insertIndex = min(max(undo.originalIndex, 0), currentRules.count)
        }
        Task { @MainActor in
            await ruleManager.performMutation {
                await dataManager.restoreZapperRule(undo.rule, forHost: undo.domain, at: insertIndex)
                await ruleManager.refreshNow()
                filterManager.markNonSelectionChangesPending()
            }
            guard mutationVersion == version else { return }
            pendingUndo = nil
            isMutating = false
        }
    }

    private func clearRules(for domain: String) {
        guard !isMutating else { return }
        _ = beginMutation(invalidateUndo: true)
        Task { @MainActor in
            await ruleManager.performMutation {
                await dataManager.deleteAllZapperRules(forHost: domain)
                expandedDomains.remove(domain)
                await ruleManager.refreshNow()
                filterManager.markNonSelectionChangesPending()
            }
            isMutating = false
        }
    }

    @discardableResult
    private func beginMutation(invalidateUndo: Bool) -> Int {
        mutationVersion += 1
        if invalidateUndo { pendingUndo = nil }
        isMutating = true
        return mutationVersion
    }

    private func invalidateUndoAndStartMutation(_ operation: @escaping @MainActor () async -> Void) {
        guard !isMutating else { return }
        _ = beginMutation(invalidateUndo: true)
        Task { @MainActor in
            await operation()
            isMutating = false
        }
    }

    private func localizedRuleCount(_ count: Int) -> String {
        let key = count == 1 ? "%d rule" : "%d rules"
        return String.localizedStringWithFormat(NSLocalizedString(key, comment: "Element zapper rule count"), count)
    }
}
