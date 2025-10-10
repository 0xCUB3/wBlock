//
//  LogsView.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import SwiftUI

struct LogsView: View {
    @State private var entries: [LogEntry] = []
    @State private var selectedLevel: LogLevel? = nil
    @State private var selectedCategory: LogCategory? = nil
    @State private var searchText = ""
    @State private var expandedEntries: Set<UUID> = []
    @State private var showingShareSheet = false
    @Environment(\.dismiss) private var dismiss

    var filteredEntries: [LogEntry] {
        var result = entries

        // Filter by level
        if let minLevel = selectedLevel {
            result = result.filter { $0.level >= minLevel }
        }

        // Filter by category
        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }

        // Search filter
        if !searchText.isEmpty {
            result = result.filter {
                $0.message.localizedCaseInsensitiveContains(searchText) ||
                $0.category.rawValue.localizedCaseInsensitiveContains(searchText) ||
                ($0.metadata?.values.contains(where: { $0.localizedCaseInsensitiveContains(searchText) }) ?? false)
            }
        }

        return result.reversed() // Show newest first
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter toolbar
                filterToolbar

                Divider()

                // Log entries list
                if filteredEntries.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredEntries) { entry in
                                LogEntryRow(
                                    entry: entry,
                                    isExpanded: expandedEntries.contains(entry.id)
                                ) {
                                    toggleExpanded(entry.id)
                                }
                                Divider()
                                    .padding(.leading, 48)
                            }
                        }
                    }
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Logs")
                        .font(.headline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button {
                            showingShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Button {
                            Task {
                                await ConcurrentLogManager.shared.clearLogs()
                                await loadLogs()
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(entries.isEmpty)
                    }
                }
            }
            #endif
        }
        .searchable(text: $searchText, prompt: "Search logs")
        .task {
            await loadLogs()
        }
        #if os(iOS)
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: [exportLogsAsText()])
        }
        #endif
    }

    private var filterToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Level filter
                Menu {
                    Button("All Levels") {
                        selectedLevel = nil
                    }
                    Divider()
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Button {
                            selectedLevel = level
                        } label: {
                            HStack {
                                Text("\(level.emoji) \(level.rawValue.capitalized)")
                                if selectedLevel == level {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if let level = selectedLevel {
                            Text(level.emoji)
                            Text(level.rawValue.capitalized)
                        } else {
                            Text("All Levels")
                        }
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                }

                // Category filter
                Menu {
                    Button("All Categories") {
                        selectedCategory = nil
                    }
                    Divider()
                    ForEach([LogCategory.system, .filterUpdate, .filterApply, .userScript, .network, .whitelist, .autoUpdate, .startup], id: \.self) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            HStack {
                                Text(category.rawValue)
                                if selectedCategory == category {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if let category = selectedCategory {
                            Text(category.rawValue)
                        } else {
                            Text("All Categories")
                        }
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                }

                // Stats
                Text("\(filteredEntries.count) entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No logs found")
                .font(.headline)
            Text("Logs will appear here as the app runs")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggleExpanded(_ id: UUID) {
        if expandedEntries.contains(id) {
            expandedEntries.remove(id)
        } else {
            expandedEntries.insert(id)
        }
    }

    private func loadLogs() async {
        await ConcurrentLogManager.shared.ingestSharedAutoUpdateLog()
        entries = await ConcurrentLogManager.shared.getEntries()
    }

    private func exportLogsAsText() -> String {
        Task {
            return await ConcurrentLogManager.shared.exportAsText()
        }
        // Fallback synchronous version
        return entries.map { $0.exportFormat }.joined(separator: "\n\n")
    }
}

struct LogEntryRow: View {
    let entry: LogEntry
    let isExpanded: Bool
    let onTap: () -> Void

    private var levelColor: Color {
        switch entry.level {
        case .trace: return .gray
        case .debug: return .blue
        case .info: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Level indicator
                VStack(spacing: 4) {
                    Text(entry.level.emoji)
                        .font(.caption)
                    if entry.count > 1 {
                        Text("×\(entry.count)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 32)

                // Main content
                VStack(alignment: .leading, spacing: 4) {
                    // Time and category
                    HStack(spacing: 8) {
                        Text(timeString(from: entry.timestamp))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)

                        Text(entry.category.rawValue)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(levelColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(levelColor.opacity(0.15), in: Capsule())
                    }

                    // Message
                    Text(entry.message)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(isExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)

                    // Metadata (if expanded)
                    if isExpanded, let metadata = entry.metadata, !metadata.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(metadata.keys.sorted()), id: \.self) { key in
                                HStack(spacing: 6) {
                                    Text(key)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .fontWeight(.medium)
                                    Text(metadata[key] ?? "")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.top, 4)
                        .padding(.leading, 8)
                    }
                }

                Spacer()

                // Expand indicator
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .opacity((entry.metadata?.isEmpty ?? true) ? 0 : 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
