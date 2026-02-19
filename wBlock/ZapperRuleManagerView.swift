import SwiftUI

struct ZapperRuleManagerView: View {
    @ObservedObject private var ruleManager = ZapperRuleManager.shared
    @State private var expandedDomains: Set<String> = []
    @State private var pendingUndo: (rule: String, domain: String, index: Int)? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 20) {
                    if ruleManager.domains.isEmpty {
                        emptyStateView
                    } else {
                        domainListView
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
        .navigationTitle("Element Zapper Rules")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            ruleManager.refresh()
            for domain in ruleManager.domains {
                if ruleManager.ruleCount(forDomain: domain) <= 5 {
                    expandedDomains.insert(domain)
                }
            }
        }
    }

    // MARK: - Domain list

    private var domainListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Element Zapper Rules")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(ruleManager.domains.indices, id: \.self) { domainIndex in
                    let domain = ruleManager.domains[domainIndex]

                    domainHeaderRow(domain: domain)

                    if expandedDomains.contains(domain) {
                        ruleRows(for: domain)
                    }

                    if domainIndex < ruleManager.domains.count - 1 {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func domainHeaderRow(domain: String) -> some View {
        let isExpanded = expandedDomains.contains(domain)
        let count = ruleManager.ruleCount(forDomain: domain)

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isExpanded {
                    expandedDomains.remove(domain)
                } else {
                    expandedDomains.insert(domain)
                }
            }
        } label: {
            HStack {
                Text(domain)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text("\(count) \(count == 1 ? "rule" : "rules")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.trailing, 4)

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func ruleRows(for domain: String) -> some View {
        let domainRules = ruleManager.rules(for: domain)
        return ForEach(domainRules.indices, id: \.self) { ruleIndex in
            let rule = domainRules[ruleIndex]

            VStack(spacing: 0) {
                Divider()
                    .padding(.leading, 16)

                HStack(alignment: .center, spacing: 12) {
                    Text(rule)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    Button {
                        deleteRule(rule, from: domain, at: ruleIndex)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 10)
                .padding(.leading, 32)
                .padding(.trailing, 16)
            }
        }
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.6))

            Text("No Element Zapper Rules")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Zap elements on any website using the wBlock extension in Safari, then manage them here.")
                .font(.body)
                .foregroundColor(.secondary)
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
                .foregroundColor(.primary)

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
            try? await Task.sleep(for: .seconds(5))
            await MainActor.run {
                pendingUndo = nil
            }
        }
    }

    // MARK: - Actions

    private func deleteRule(_ rule: String, from domain: String, at index: Int) {
        pendingUndo = (rule: rule, domain: domain, index: index)
        ruleManager.deleteRule(rule, forDomain: domain)
    }
}
