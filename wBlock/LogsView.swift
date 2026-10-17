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
    @State private var hasLoadedLogs = false
    @State private var selectedLevel: LogLevel? = nil
    @State private var selectedCategory: LogCategory? = nil
    @State private var searchText = ""
    #if os(iOS)
    /// The export is written to a file first and the sheet is keyed on the
    /// URL, so the share never presents before the text exists (#682).
    @State private var exportFile: LogExportFile?
    #endif
    /// Set when presented as a sheet so the navigation bar carries the close
    /// button instead of a second "Logs" header above it.
    private let onDismiss: (() -> Void)?

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

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
        CompatibleNavigationStack {
            VStack(spacing: 0) {
                #if os(macOS)
                filterToolbar
                Divider()
                #endif

                if filteredEntries.isEmpty {
                    emptyStateView
                } else {
                    List {
                        Section {
                            ForEach(filteredEntries) { entry in
                                LogEntryRow(entry: entry)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                        } header: {
                            #if os(iOS)
                            statsLabel
                            #endif
                        }
                    }
                    .listStyle(.plain)
                }
            }
            #if os(iOS)
            .navigationTitle("Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // A conditional ToolbarItem needs iOS 16; a conditional view inside one doesn't.
                ToolbarItem(placement: .cancellationAction) {
                    if let onDismiss {
                        SheetDoneButton(action: onDismiss)
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        levelFilterPicker
                        categoryFilterPicker
                    } label: {
                        Label(
                            "Filter Logs",
                            systemImage: selectedLevel == nil && selectedCategory == nil
                                ? "line.3.horizontal.decrease.circle"
                                : "line.3.horizontal.decrease.circle.fill"
                        )
                    }

                    Button {
                        Task {
                            let text = await ConcurrentLogManager.shared.exportAsText(
                                entries: Array(filteredEntries.reversed())
                            )
                            exportFile = LogExportFile.write(text)
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export")

                    Button {
                        Task {
                            await ConcurrentLogManager.shared.clearLogs()
                            await loadLogs()
                        }
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(hasLoadedLogs && entries.isEmpty)
                    .accessibilityLabel("Clear")
                }
            }
            #else
            .modifier(MacPushedActionsToolbar {
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
            })
            #endif
        }
        .searchable(text: $searchText, prompt: "Search logs")
        .task {
            await loadLogs()
            hasLoadedLogs = true
            updateFilteredEntries()
        }
        .onChangeCompat(of: entries) { _, _ in
            updateFilteredEntries()
        }
        .onChangeCompat(of: selectedLevel) { _, _ in
            updateFilteredEntries()
        }
        .onChangeCompat(of: selectedCategory) { _, _ in
            updateFilteredEntries()
        }
        .onChangeCompat(of: searchText) { _, _ in
            updateFilteredEntries()
        }
        #if os(iOS)
        .sheet(item: $exportFile) { file in
            ShareSheet(items: [file.url])
        }
        #endif
    }

    #if os(macOS)
    private var filterToolbar: some View {
        HStack(spacing: 12) {
            levelFilterPicker
            categoryFilterPicker

            statsLabel

            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    #endif

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
                .scaledSystemFont(size: 48, relativeTo: .largeTitle)
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

    #if os(macOS)
    private func exportLogsToFile() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "wBlock_logs_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).txt"
        savePanel.canCreateDirectories = true

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            Task {
                let logsText = await ConcurrentLogManager.shared.exportAsText(
                    entries: Array(filteredEntries.reversed())
                )
                do {
                    try url.withSecurityScopedAccess { accessibleURL in
                        try logsText.write(to: accessibleURL, atomically: true, encoding: .utf8)
                    }
                } catch {
                    await ConcurrentLogManager.shared.error(.system, LocalizedStrings.text("Failed to export logs"), error: error)
                }
            }
        }
    }
    #endif
}

struct LogEntryRow: View {
    let entry: LogEntry

    private var levelColor: Color {
        switch entry.level {
        case .trace: return .gray
        case .debug: return .purple
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var levelSymbol: String {
        switch entry.level {
        case .trace: return "magnifyingglass.circle.fill"
        case .debug: return "ant.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    @State private var isExpanded = false

    private var hasDetails: Bool {
        entry.message.count > 80 || !(entry.metadata?.isEmpty ?? true)
    }

    var body: some View {
        if hasDetails {
            DisclosureGroup(isExpanded: $isExpanded) {
                detailContent
            } label: {
                summaryContent
            }
            .tint(.secondary)
        } else {
            summaryContent
        }
    }

    private var summaryContent: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 2) {
                Image(systemName: levelSymbol)
                    .font(.body)
                    .foregroundStyle(levelColor)
                    .accessibilityLabel(entry.level.localizedName)

                if entry.count > 1 {
                    Text(String.localizedStringWithFormat(
                        NSLocalizedString("×%d", comment: "Collapsed duplicate log entry count"),
                        entry.count
                    ))
                    .scaledSystemFont(size: 9, relativeTo: .caption2)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(LogDateFormatters.timeFormatter.string(from: entry.timestamp))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Text(entry.category.localizedName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }

                Text(entry.message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(isExpanded ? nil : 2)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let metadata = entry.metadata, !metadata.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(metadata.keys.sorted(), id: \.self) { key in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(key)
                                .foregroundStyle(.secondary)
                                .frame(width: 96, alignment: .leading)
                            Text(metadata[key] ?? "")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .font(.caption)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.leading, 34)
        .padding(.vertical, 4)
    }

}

#if os(iOS)
struct LogExportFile: Identifiable {
    let url: URL
    var id: String { url.path }

    static func write(_ text: String) -> LogExportFile? {
        let stamp = Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wBlock_logs_\(stamp).txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return LogExportFile(url: url)
        } catch {
            Task { await ConcurrentLogManager.shared.error(.system, LocalizedStrings.text("Failed to export logs"), error: error) }
            return nil
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
