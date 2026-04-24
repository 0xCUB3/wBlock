//
//  LogsView.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct LogsView: View {
    private static let availableCategories: [LogCategory] = [
        .system,
        .filterUpdate,
        .filterApply,
        .userScript,
        .network,
        .whitelist,
        .autoUpdate,
        .startup,
    ]

    @State private var entries: [LogEntry] = []
    @State private var selectedLevel: LogLevel? = nil
    @State private var selectedCategory: LogCategory? = nil
    @State private var searchText = ""
    @State private var showingShareSheet = false
    @Environment(\.dismiss) private var dismiss

    // Cached filtered entries to avoid repeated filtering on scroll
    @State private var cachedFilteredEntries: [LogEntry] = []

    private var filteredEntries: [LogEntry] {
        cachedFilteredEntries
    }

    private func updateFilteredEntries() {
        var result = entries

        // Filter by level (exact match)
        if let level = selectedLevel {
            result = result.filter { $0.level == level }
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

        cachedFilteredEntries = result.reversed() // Show newest first
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
                    List(filteredEntries) { entry in
                        LogEntryRow(entry: entry)
                            .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                    }
                    .listStyle(.plain)
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
            #else
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        Button {
                            exportLogsToFile()
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .disabled(entries.isEmpty)

                        Button {
                            Task {
                                await ConcurrentLogManager.shared.clearLogs()
                                await loadLogs()
                            }
                        } label: {
                            Label("Clear", systemImage: "trash")
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
            updateFilteredEntries()
        }
        .onChange(of: entries) { _, _ in
            updateFilteredEntries()
        }
        .onChange(of: selectedLevel) { _, _ in
            updateFilteredEntries()
        }
        .onChange(of: selectedCategory) { _, _ in
            updateFilteredEntries()
        }
        .onChange(of: searchText) { _, _ in
            updateFilteredEntries()
        }
        #if os(iOS)
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: [exportLogsAsText()])
        }
        #endif
    }

    private var filterToolbar: some View {
        #if os(macOS)
        HStack(spacing: 12) {
            levelFilterPicker
            categoryFilterPicker

            statsLabel

            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        #else
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                levelFilterPicker
                categoryFilterPicker

                // Stats
                statsLabel
                    .padding(.leading, 8)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        #endif
    }

    private var levelFilterPicker: some View {
        Picker("All Levels", selection: $selectedLevel) {
            Text("All Levels").tag(nil as LogLevel?)
            ForEach(LogLevel.allCases, id: \.self) { level in
                Text(level.localizedName)
                    .tag(level as LogLevel?)
            }
        }
        .labelsHidden()
        .accessibilityLabel("All Levels")
        #if os(macOS)
        .controlSize(.small)
        #else
        .pickerStyle(.menu)
        #endif
    }

    private var categoryFilterPicker: some View {
        Picker("All Categories", selection: $selectedCategory) {
            Text("All Categories").tag(nil as LogCategory?)
            ForEach(Self.availableCategories, id: \.self) { category in
                Text(category.localizedName)
                    .tag(category as LogCategory?)
            }
        }
        .labelsHidden()
        .accessibilityLabel("All Categories")
        #if os(macOS)
        .controlSize(.small)
        #else
        .pickerStyle(.menu)
        #endif
    }

    private var statsLabel: some View {
        Text(
            LocalizedStrings.format(
                "%d entries",
                comment: "Log entry count label",
                filteredEntries.count
            )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No logs found")
                .font(.headline)
            Text("Logs will appear here as the app runs")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadLogs() async {
        await ConcurrentLogManager.shared.ingestSharedAutoUpdateLog()
        await ConcurrentLogManager.shared.ingestSharedWebExtensionLog()
        entries = await ConcurrentLogManager.shared.getEntries()
    }

    private func exportLogsAsText() -> String {
        Task {
            return await ConcurrentLogManager.shared.exportAsText()
        }
        // Fallback synchronous version
        return entries.map { $0.exportFormat }.joined(separator: "\n\n")
    }

    #if os(macOS)
    private func exportLogsToFile() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "wBlock_logs_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).txt"
        savePanel.canCreateDirectories = true

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            Task {
                let logsText = await ConcurrentLogManager.shared.exportAsText()
                do {
                    try url.withSecurityScopedAccess { accessibleURL in
                        try logsText.write(to: accessibleURL, atomically: true, encoding: .utf8)
                    }
                } catch {
                    await ConcurrentLogManager.shared.error(.system, "Failed to export logs", metadata: ["error": "\(error)"])
                }
            }
        }
    }
    #endif
}

struct LogEntryRow: View {
    let entry: LogEntry

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var levelColor: Color {
        switch entry.level {
        case .trace: return .gray
        case .debug: return .blue
        case .info: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var hasDetails: Bool {
        entry.message.count > 80 || !(entry.metadata?.isEmpty ?? true)
    }

    var body: some View {
        if hasDetails {
            DisclosureGroup {
                detailContent
            } label: {
                summaryContent
            }
        } else {
            summaryContent
        }
    }

    private var summaryContent: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 2) {
                Text(entry.level.emoji)
                    .font(.caption)

                if entry.count > 1 {
                    Text(String.localizedStringWithFormat(
                        NSLocalizedString("×%d", comment: "Collapsed duplicate log entry count"),
                        entry.count
                    ))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                }
            }
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(Self.timeFormatter.string(from: entry.timestamp))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Text(entry.category.localizedName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(levelColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(levelColor.opacity(0.15), in: Capsule())
                }

                Text(entry.message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(entry.message.count > 80 ? 2 : nil)
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if entry.message.count > 80 {
                Text(entry.message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }

            if let metadata = entry.metadata, !metadata.isEmpty {
                ForEach(metadata.keys.sorted(), id: \.self) { key in
                    LabeledContent(key, value: metadata[key] ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.leading, 32)
        .padding(.vertical, 2)
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
