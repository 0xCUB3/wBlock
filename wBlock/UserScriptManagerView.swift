//
//  UserScriptManagerView.swift
//  wBlock
//
//  Created by Alexander Skula on 6/7/25.
//

import SwiftUI
import wBlockCoreService
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private struct UserScriptListItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let localizedDisplayName: String
    let localizedDisplayDescription: String
    let url: URL?
    let updateURL: String?
    let isEnabled: Bool
    let version: String
    let lastUpdatedFormatted: String?
    let isLocal: Bool
    let isDownloaded: Bool

    init(script: UserScript) {
        id = script.id
        name = script.name
        localizedDisplayName = script.localizedDisplayName
        localizedDisplayDescription = script.localizedDisplayDescription
        url = script.url
        updateURL = script.updateURL
        isEnabled = script.isEnabled
        version = script.version
        lastUpdatedFormatted = script.lastUpdatedFormatted
        isLocal = script.isLocal
        isDownloaded = script.isDownloaded
    }
}

private struct SelectedUserScript: Identifiable {
    let id: UUID
}

struct UserScriptManagerView: View {
    @ObservedObject var userScriptManager: UserScriptManager
    let hasPendingChanges: Bool
    let isApplyingChanges: Bool
    let onApplyChanges: () -> Void

    @State private var scripts: [UserScriptListItem] = []
    @State private var showingAddScriptSheet = false
    @State private var selectedScript: SelectedUserScript?
    @State private var showOnlyEnabled = false
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var isDropTarget = false
    @State private var isDropProcessing = false
    @State private var dropErrorMessage: String?

    private var totalScriptsCount: Int {
        scripts.count
    }

    private var enabledScriptsCount: Int {
        scripts.filter(\.isEnabled).count
    }

    private var applyChangesToolbarButton: some View {
        Button {
            onApplyChanges()
        } label: {
            if hasPendingChanges {
                Text("Apply")
                    .fontWeight(.semibold)
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        }
        .disabled(isApplyingChanges)
        .accessibilityLabel("Apply Changes")
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedScripts: [UserScriptListItem] {
        let filteredByEnabled = showOnlyEnabled ? scripts.filter(\.isEnabled) : scripts
        guard !trimmedSearchText.isEmpty else {
            return filteredByEnabled.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        return filteredByEnabled.filter { script in
            script.localizedDisplayName.localizedCaseInsensitiveContains(trimmedSearchText)
                || script.localizedDisplayDescription.localizedCaseInsensitiveContains(trimmedSearchText)
                || (script.url?.absoluteString.localizedCaseInsensitiveContains(trimmedSearchText)
                    ?? false)
                || (script.updateURL?.localizedCaseInsensitiveContains(trimmedSearchText) ?? false)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func copyScriptURL(_ url: URL) {
        #if os(iOS)
        UIPasteboard.general.string = url.absoluteString
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #endif
    }

    var body: some View {
        userScriptContent
        .sheet(isPresented: $showingAddScriptSheet, onDismiss: {
            refreshScripts()
        }) {
            AddUserScriptView(userScriptManager: userScriptManager, onScriptAdded: {
                refreshScripts()
            })
        }
        .sheet(item: $selectedScript, onDismiss: {
            refreshScripts()
        }) { selection in
            UserScriptContentView(scriptId: selection.id, userScriptManager: userScriptManager)
        }
        .onAppear {
            refreshScripts()
            showOnlyEnabled = ProtobufDataManager.shared.getUserScriptShowEnabledOnly()
        }
        .alert("Import Failed", isPresented: Binding(
            get: { dropErrorMessage != nil },
            set: { newValue in if !newValue { dropErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { dropErrorMessage = nil }
        } message: {
            Text(dropErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private var userScriptContent: some View {
        #if os(iOS)
        List {
            Section {
                statsCardsView
                    .unifiedTabCardSectionRow()
            }

            if scripts.isEmpty {
                Section {
                    emptyStateView
                        .padding(.vertical, 40)
                }
            } else if displayedScripts.isEmpty {
                Section {
                    noSearchResultsView
                        .padding(.vertical, 40)
                }
            } else {
                Section("Userscripts") {
                    ForEach(displayedScripts) { script in
                        scriptRowView(script: script)
                    }
                }
            }
        }
        .unifiedTabListStyle()
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if #unavailable(iOS 26.0) {
                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
                Button {
                    showingAddScriptSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                Button {
                    showOnlyEnabled.toggle()
                    ProtobufDataManager.shared.setUserScriptShowEnabledOnly(showOnlyEnabled)
                } label: {
                    Image(
                        systemName: showOnlyEnabled
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                }
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $showSearch,
            prompt: "Search scripts"
        )
        .modifier(SearchMinimizeBehavior())
        #else
        ScrollView {
            VStack(spacing: 20) {
                statsCardsView

                if scripts.isEmpty {
                    emptyStateView
                        .padding(.top, 40)
                } else if displayedScripts.isEmpty {
                    noSearchResultsView
                        .padding(.top, 40)
                } else {
                    scriptsListView
                }

                Spacer(minLength: 20)
            }
            .padding(.vertical)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget, perform: handleDrop(providers:))
        .overlay(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                if isDropTarget {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .padding(8)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.accentColor.opacity(0.05))
                                .padding(8)
                        }
                }

                if isDropProcessing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Importing…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(12)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                ToolbarSearchField(
                    text: $searchText,
                    isExpanded: $showSearch,
                    prompt: "Search scripts"
                )

                if !showSearch {
                    applyChangesToolbarButton
                        .help(
                            hasPendingChanges
                                ? String(localized: "Apply your pending changes")
                                : String(localized: "Apply changes")
                        )

                    Button {
                        showingAddScriptSheet = true
                    } label: {
                        Label("Add Userscript", systemImage: "plus")
                    }

                    Button {
                        showOnlyEnabled.toggle()
                        ProtobufDataManager.shared.setUserScriptShowEnabledOnly(showOnlyEnabled)
                    } label: {
                        Label(
                            "Show Enabled Only",
                            systemImage: showOnlyEnabled
                                ? "line.3.horizontal.decrease.circle.fill"
                                : "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        #endif
    }

    private func refreshScripts() {
        scripts = userScriptManager.userScripts.map(UserScriptListItem.init)
    }

    #if os(macOS)
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            if let error {
                Task {
                    await ConcurrentLogManager.shared.error(.userScript, "Failed to load dropped item", metadata: ["error": error.localizedDescription])
                }
                return
            }

            var url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let droppedURL = item as? URL {
                url = droppedURL
            }

            guard let resolvedURL = url else {
                Task {
                    await ConcurrentLogManager.shared.error(.userScript, "Could not resolve URL from dropped item.")
                }
                return
            }

            Task {
                await MainActor.run { isDropProcessing = true }

                let error = await userScriptManager.addUserScript(fromLocalFile: resolvedURL)
                if let error {
                    await ConcurrentLogManager.shared.error(.userScript, "Failed to import dropped userscript", metadata: ["error": error.localizedDescription])
                    await MainActor.run {
                        dropErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                } else {
                    await MainActor.run {
                        refreshScripts()
                    }
                }

                await MainActor.run { isDropProcessing = false }
            }
        }

        return true
    }
    #endif

    private var statsCardsView: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Scripts",
                value: "\(totalScriptsCount)",
                icon: "doc.text",
                pillColor: .clear,
                valueColor: .primary
            )
            #if os(iOS)
            .frame(maxWidth: .infinity, alignment: .leading)
            #endif

            StatCard(
                title: "Enabled",
                value: "\(enabledScriptsCount)",
                icon: "checkmark.circle",
                pillColor: .clear,
                valueColor: .primary
            )
            #if os(iOS)
            .frame(maxWidth: .infinity, alignment: .leading)
            #endif
        }
        .padding(.horizontal)
    }

    #if os(macOS)
    private var scriptsListView: some View {
        LazyVStack(spacing: 16) {
            VStack(spacing: 0) {
                ForEach(displayedScripts.indices, id: \.self) { index in
                    scriptRowView(script: displayedScripts[index])

                    if index < displayedScripts.count - 1 {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal)
    }
    #endif

    private func scriptRowView(script: UserScriptListItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(script.localizedDisplayName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if !script.localizedDisplayDescription.isEmpty {
                    Text(script.localizedDisplayDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 4) {
                    if !script.version.isEmpty {
                        Text(
                            LocalizedStrings.format(
                                "Version %@",
                                comment: "Userscript version label",
                                script.version
                            )
                        )
                            .font(.caption2)
                            .foregroundStyle(.gray)
                    }
                    if let lastUpdated = script.lastUpdatedFormatted {
                        if !script.version.isEmpty {
                            Text("·")
                                .font(.caption2)
                                .foregroundStyle(.gray)
                        }
                        Text(lastUpdated)
                            .font(.caption2)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if script.isLocal {
                    Text("Local Import")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .cornerRadius(4)
                }

                if script.isEnabled && !script.isDownloaded {
                    Text("Not Downloaded")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .foregroundStyle(.red)
                        .cornerRadius(4)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if !script.isDownloaded, !script.isLocal, script.url != nil {
                    Button {
                        Task {
                            guard let managedScript = userScriptManager.userScript(withId: script.id) else { return }
                            await ConcurrentLogManager.shared.debug(.userScript, "Downloading userscript", metadata: ["script": script.name])
                            await userScriptManager.downloadUserScript(managedScript)
                            refreshScripts()
                        }
                    } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                    .buttonStyle(.borderless)
                    #if os(macOS)
                    .help("Download Script")
                    #endif
                }


                Toggle("", isOn: Binding(
                    get: { script.isEnabled },
                    set: { _ in
                        Task {
                            guard let managedScript = userScriptManager.userScript(withId: script.id) else { return }
                            await ConcurrentLogManager.shared.debug(.userScript, "Toggling userscript", metadata: ["script": script.name])
                            await userScriptManager.toggleUserScript(managedScript)
                            await MainActor.run {
                                refreshScripts()
                            }
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!script.isDownloaded)
                .frame(alignment: .center)
            }
        }
        .id(script.id)
        .contentShape(.interaction, Rectangle())
        .onTapGesture {
            if script.isDownloaded {
                // Defer to avoid race with context menu dismissal on iOS
                DispatchQueue.main.async {
                    selectedScript = SelectedUserScript(id: script.id)
                }
            }
        }
        .contextMenu {
            #if os(macOS)
            if script.isDownloaded {
                Button {
                    selectedScript = SelectedUserScript(id: script.id)
                } label: {
                    Label("View Content", systemImage: "doc.text")
                }
            }
            #endif
            if let url = script.url {
                Button {
                    copyScriptURL(url)
                } label: {
                    Label("Copy URL", systemImage: "doc.on.doc")
                }
            }
            if let managedScript = userScriptManager.userScript(withId: script.id),
                !userScriptManager.isDefaultUserScript(managedScript)
            {
                Button(role: .destructive) {
                    Task {
                        guard let managedScript = userScriptManager.userScript(withId: script.id) else { return }
                        await ConcurrentLogManager.shared.info(.userScript, "Removing userscript", metadata: ["script": script.name])
                        userScriptManager.removeUserScript(managedScript)
                        refreshScripts()
                    }
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
        #if os(macOS)
        .padding(16)
        #endif
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.6))
            Text("No Userscripts")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Add userscripts to customize your browsing experience")
                .font(.body)
                .foregroundStyle(.secondary)
            Button {
                showingAddScriptSheet = true
            } label: {
                Label("Add Userscript", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
    }

    private var noSearchResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary.opacity(0.7))
            Text("No matching userscripts")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - UserScriptInfoSidebar Subviews

private struct ScriptNameAndDescriptionView: View {
    let script: UserScript
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(script.localizedDisplayName).font(.title2).fontWeight(.semibold).foregroundStyle(.primary).textSelection(.enabled)
            if !script.localizedDisplayDescription.isEmpty {
                Text(script.localizedDisplayDescription).font(.body).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ScriptStatusBadgesView: View {
    let script: UserScript
    let isDownloaded: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if !script.version.isEmpty {
                    Badge(
                        text: LocalizedStrings.format(
                            "v%@",
                            comment: "Userscript version badge",
                            script.version
                        ),
                        color: .blue
                    )
                }
                Badge(text: script.isEnabled ? "Enabled" : "Disabled", color: script.isEnabled ? .green : .secondary)
            }
            if script.isEnabled && !isDownloaded {
                Badge(text: "Not Downloaded", color: .red)
            } else if isDownloaded {
                Badge(text: "Downloaded", color: .green)
            }
        }
    }
}

private struct ScriptFileInfoView: View {
    let contentLength: Int
    let formatFileSize: (Int) -> String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("File Information").font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
            HStack {
                Text("Size:").font(.caption2).foregroundStyle(.secondary)
                Text(formatFileSize(contentLength)).font(.caption).fontWeight(.medium).foregroundStyle(.primary)
                Spacer()
            }.padding(.horizontal, 8).padding(.vertical, 6).cornerRadius(6)
        }
    }
}

private struct ScriptURLView: View {
    let script: UserScript
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Source URL").font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
            Text(script.url?.absoluteString ?? "N/A").font(.caption).foregroundStyle(.blue).textSelection(.enabled).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ScriptMatchPatternRowView: View {
    let index: Int
    let pattern: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(
                LocalizedStrings.format(
                    "%d.",
                    comment: "Userscript URL pattern row index",
                    index + 1
                )
            )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)

            Text(pattern)
                .font(.caption)
                .foregroundStyle(.orange)
                .textSelection(.enabled)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

private struct ScriptMatchPatternsView: View {
    let script: UserScript
    @Binding var isPatternsExpanded: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPatternsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(
                        LocalizedStrings.format(
                            "URL Patterns (%d)",
                            comment: "Userscript URL pattern section title",
                            script.matches.count
                        )
                    )
                        .font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: isPatternsExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain).padding(.horizontal, 8).padding(.vertical, 6).cornerRadius(6).onHover { _ in }

            if isPatternsExpanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(script.matches.indices, id: \.self) { indexInForEach in
                            ScriptMatchPatternRowView(index: indexInForEach, pattern: script.matches[indexInForEach])
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxHeight: 200)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5), lineWidth: 0.5))
            }
        }
    }
}


struct UserScriptInfoSidebar: View {
    let script: UserScript
    let contentLength: Int
    @Binding var isPatternsExpanded: Bool
    let formatFileSize: (Int) -> String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScriptNameAndDescriptionView(script: script)
            ScriptStatusBadgesView(script: script, isDownloaded: contentLength > 0)
            if contentLength > 0 {
                ScriptFileInfoView(contentLength: contentLength, formatFileSize: formatFileSize)
            }
            if script.url != nil { ScriptURLView(script: script) }
            if !script.matches.isEmpty { ScriptMatchPatternsView(script: script, isPatternsExpanded: $isPatternsExpanded) }
            Spacer()
        }
    }
}

#if os(macOS)
struct ScriptContentMainView: View {
    let previewContent: String
    let contentLength: Int
    let formatFileSize: (Int) -> String
    let onShowSource: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Script Content").font(.headline).fontWeight(.medium)
                    if contentLength > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle").font(.caption2).foregroundStyle(.orange)
                            Text(
                                LocalizedStrings.format(
                                    "Showing preview (%@ of %@)",
                                    comment: "Userscript content preview status",
                                    formatFileSize(previewContent.count),
                                    formatFileSize(contentLength)
                                )
                            )
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                HStack(spacing: 12) {
                    if contentLength > 0 {
                        Button {
                            onShowSource()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "eye")
                                Text("Show All")
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }.padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            if contentLength == 0 {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text").font(.system(size: 48)).foregroundStyle(.secondary.opacity(0.6))
                    Text("No Content Available").font(.headline).foregroundStyle(.secondary)
                    Text("This script hasn't been downloaded yet.").font(.body).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MonospacedTextView(
                    text: Binding(
                        get: { previewContent },
                        set: { _ in }
                    )
                )
            }
        }
    }
}
#endif

struct UserScriptContentView: View {
    let scriptId: UUID
    var userScriptManager: UserScriptManager
    @Environment(\.dismiss) private var dismiss
    @State private var script: UserScript?
    @State private var loadedContent = ""
    @State private var previewContent = ""
    @State private var isLoadingContent = false
    @State private var sidebarWidth: CGFloat = 280
    @State private var isPatternsExpanded = false
    @State private var isShowingSourceSheet = false

    private let previewLength = 10000
    #if os(macOS)
    private let minSidebarWidth: CGFloat = 250
    private let maxSidebarWidth: CGFloat = 500
    #endif

    var body: some View {
        Group {
            if let script {
                #if os(iOS)
                NavigationView {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            UserScriptInfoSidebar(
                                script: script,
                                contentLength: loadedContent.count,
                                isPatternsExpanded: $isPatternsExpanded,
                                formatFileSize: formatFileSize
                            )
                            .padding(.horizontal)

                            Divider()

                            VStack(alignment: .leading, spacing: 12) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .center, spacing: 12) {
                                        Text("Script Content")
                                            .font(.headline)
                                            .fontWeight(.medium)
                                        Spacer()
                                        if !loadedContent.isEmpty {
                                            Button {
                                                isShowingSourceSheet = true
                                            } label: {
                                                Label("Show All", systemImage: "eye")
                                            }
                                            .buttonStyle(.plain)
                                            .font(.body)
                                            .foregroundStyle(Color.accentColor)
                                        }
                                    }

                                    if !loadedContent.isEmpty {
                                        HStack(spacing: 4) {
                                            Image(systemName: "info.circle")
                                                .font(.caption2)
                                                .foregroundStyle(.orange)
                                            Text(
                                                LocalizedStrings.format(
                                                    "Showing preview (%@ of %@)",
                                                    comment: "Userscript content preview status",
                                                    formatFileSize(previewContent.count),
                                                    formatFileSize(loadedContent.count)
                                                )
                                            )
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                if loadedContent.isEmpty {
                                    VStack(spacing: 16) {
                                        Image(systemName: "doc.text")
                                            .font(.system(size: 48))
                                            .foregroundStyle(.secondary.opacity(0.6))
                                        Text("No Content Available")
                                            .font(.headline)
                                            .foregroundStyle(.secondary)
                                        Text("This script hasn't been downloaded yet.")
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 40)
                                } else {
                                    MonospacedTextView(
                                        text: Binding(
                                            get: { previewContent },
                                            set: { _ in }
                                        )
                                    )
                                        .frame(minHeight: 300)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.vertical)
                    }
                    .navigationTitle(script.localizedDisplayName)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { dismiss() }
                        }
                    }
                }
                #else
                HSplitView {
                    UserScriptInfoSidebar(
                        script: script,
                        contentLength: loadedContent.count,
                        isPatternsExpanded: $isPatternsExpanded,
                        formatFileSize: formatFileSize
                    )
                    .frame(minWidth: minSidebarWidth, idealWidth: sidebarWidth, maxWidth: maxSidebarWidth)
                    .padding(20)

                    ScriptContentMainView(
                        previewContent: previewContent,
                        contentLength: loadedContent.count,
                        formatFileSize: formatFileSize,
                        onShowSource: { isShowingSourceSheet = true }
                    )
                    .frame(minWidth: 400)
                }
                .navigationTitle("")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                .frame(width: 1000, height: 700)
                #endif
            } else if isLoadingContent {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Unable to load script")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: scriptId) {
            await loadScript()
        }
        .sheet(isPresented: $isShowingSourceSheet) {
            if let script {
                UserScriptSourceSheet(
                    script: script,
                    initialContent: loadedContent,
                    onSave: { newContent in
                        await userScriptManager.saveEditedContent(for: script.id, newContent: newContent)
                        await MainActor.run {
                            loadedContent = newContent
                            updatePreview()
                        }
                    }
                )
            }
        }
    }

    @MainActor
    private func loadScript() async {
        isLoadingContent = true
        guard let loadedScript = await userScriptManager.userScriptEditorSnapshot(withId: scriptId) else {
            script = nil
            loadedContent = ""
            previewContent = ""
            isLoadingContent = false
            return
        }

        var metadata = loadedScript
        loadedContent = loadedScript.content
        metadata.content = ""
        script = metadata
        updatePreview()
        isLoadingContent = false
    }

    private func updatePreview() {
        previewContent = String(loadedContent.prefix(previewLength))
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter(); formatter.allowedUnits = [.useKB, .useMB]; formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

private struct UserScriptSourceSheet: View {
    let script: UserScript
    let initialContent: String
    let onSave: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var editorController: CodeMirrorEditorController
    @State private var isEditing: Bool
    @State private var isLineWrappingEnabled = false
    @State private var isSaving = false

    init(
        script: UserScript,
        initialContent: String,
        onSave: @escaping (String) async -> Void
    ) {
        self.script = script
        self.initialContent = initialContent
        self.onSave = onSave
        _editorController = StateObject(wrappedValue: CodeMirrorEditorController(text: initialContent))
        _isEditing = State(initialValue: false)
    }

    var body: some View {
        #if os(iOS)
        NavigationStack {
            sourceSheetBody
                .background(Color(.systemGray6))
                .navigationTitle("Script Content")
                .navigationBarTitleDisplayMode(.inline)
        }
        #else
        sourceSheetBody
            .frame(width: 1000, height: 700)
        #endif
    }

    private var sourceSheetBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                #if os(macOS)
                VStack(alignment: .leading, spacing: 2) {
                    Text(script.localizedDisplayName)
                        .font(.headline)
                    Text("Script Content")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                #endif

                Button {
                    editorController.openSearch()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search")

                Button {
                    isLineWrappingEnabled.toggle()
                } label: {
                    Image(systemName: isLineWrappingEnabled ? "text.justify.left" : "text.alignleft")
                        .frame(width: 28, height: 28)
                        .foregroundStyle(isLineWrappingEnabled ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Wrap Lines")

                Spacer()

                if isEditing {
                    Button("Cancel") {
                        handleCancel()
                    }

                    Button {
                        Task {
                            await saveChanges()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isSaving {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .frame(width: 12, height: 12)
                            }
                            Text("Save")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || !editorController.isDirty)
                } else {
                    Button("Edit") {
                        isEditing = true
                        DispatchQueue.main.async {
                            editorController.focus()
                        }
                    }

                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            CodeMirrorTextEditor(
                controller: editorController,
                isEditable: isEditing,
                isLineWrappingEnabled: isLineWrappingEnabled
            )
        }
    }

    @MainActor
    private func saveChanges() async {
        isSaving = true
        let newContent = await editorController.currentText()
        await onSave(newContent)
        isSaving = false
        dismiss()
    }

    private func handleCancel() {
        editorController.discardChanges()
        isEditing = false
    }
}

struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(LocalizedStringKey(text)).font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15)).foregroundStyle(color).cornerRadius(4)
    }
}

struct AddUserScriptView: View {
    var userScriptManager: UserScriptManager
    var onScriptAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var urlInput: String = ""
    @State private var validationState: ValidationState = .idle
    @State private var isAdding: Bool = false
    @State private var fileImportError: String?
    @State private var showingFileImporter = false
    @State private var addMode: AddMode = .url
    @State private var showHints: Bool = false
    @FocusState private var urlFieldFocused: Bool

    private enum AddMode: String, CaseIterable, Identifiable {
        case url = "URL"
        case file = "File"

        var id: String { rawValue }
    }

    var body: some View {
        Group {
            #if os(iOS)
            iosBody
            #elseif os(macOS)
            macosBody
            #endif
        }
        .interactiveDismissDisabled(isAdding)
        #if os(macOS)
        .onAppear {
            urlFieldFocused = addMode == .url
        }
        .onChange(of: addMode) { _, newValue in
            urlFieldFocused = newValue == .url
        }
        #endif
        .onChange(of: urlInput) { _, newValue in
            validateInput(newValue)
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: allowedImportTypes) { result in
            switch result {
            case .success(let url):
                importFile(at: url)
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled {
                    fileImportError = error.localizedDescription
                }
            }
        }
    }

    #if os(iOS)
    private var iosBody: some View {
        NavigationStack {
            addTabs
                .navigationTitle("Add Userscript")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(isAdding)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: submit) {
                            if isAdding {
                                ProgressView()
                            } else {
                                Text(LocalizedStringKey(addButtonTitle))
                            }
                        }
                        .disabled(!canSubmit || isAdding)
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var addTabs: some View {
        TabView(selection: $addMode) {
            urlTab
                .tag(AddMode.url)
                .tabItem { Label("URL", systemImage: "link") }

            fileTab
                .tag(AddMode.file)
                .tabItem { Label("File", systemImage: "doc") }
        }
    }

    private var urlTab: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    TextField(
                        text: $urlInput,
                        prompt: Text(verbatim: "https://example.com/script.user.js")
                            .foregroundStyle(.secondary)
                    ) {
                        Text("Script URL")
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .focused($urlFieldFocused)
                    .onSubmit {
                        if canSubmit {
                            submit()
                        } else {
                            urlFieldFocused = false
                        }
                    }

                    compactPasteButton
                }
            } footer: {
                validationMessage
            }

            Section {
                requirementsDisclosure
            }
        }
    }

    private var fileTab: some View {
        Form {
            Section {
                Button {
                    showingFileImporter = true
                    fileImportError = nil
                } label: {
                    Label("Choose File…", systemImage: "tray.and.arrow.down")
                }
                .disabled(isAdding)
            } footer: {
                fileImportMessage
            }

            Section {
                requirementsDisclosure
            }
        }
    }
    #endif

    #if os(macOS)
    private var macosBody: some View {
        SheetContainer {
            SheetHeader(title: "Add Userscript", isLoading: isAdding) {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    modePickerCard
                    macosModeContent
                    requirementsCard
                }
                .padding(.horizontal, SheetDesign.contentHorizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }

            SheetBottomToolbar {
                Spacer()
                addButton
            }
        }
        .frame(minWidth: 560, minHeight: 500)
    }

    private var modePickerCard: some View {
        HStack(spacing: 10) {
            Text("Add Mode")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: $addMode) {
                ForEach(AddMode.allCases) { mode in
                    Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .animation(.easeInOut(duration: 0.15), value: addMode)

            Spacer(minLength: 0)
        }
        .padding(16)
        .liquidGlassCompat(cornerRadius: 16, material: .regularMaterial)
    }

    @ViewBuilder
    private var macosModeContent: some View {
        switch addMode {
        case .url:
            macosURLCard
        case .file:
            macosFileCard
        }
    }

    private var macosURLCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Script URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Paste the direct .user.js or .js link. wBlock will download and install it for you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    TextField("https://example.com/script.user.js", text: $urlInput)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($urlFieldFocused)
                        .onSubmit {
                            if canSubmit {
                                submit()
                            } else {
                                urlFieldFocused = false
                            }
                        }

                    compactPasteButton
                }

                HStack {
                    Spacer()
                    validationBadge
                }
            }

            validationMessage
        }
        .padding(16)
        .liquidGlassCompat(cornerRadius: 16, material: .regularMaterial)
    }

    private var macosFileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Import File")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Supports .user.js or .js files. Local imports won't auto-update; re-import to replace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                showingFileImporter = true
                fileImportError = nil
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                    Text("Choose File…")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isAdding)

            if let fileImportError {
                Text(fileImportError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .liquidGlassCompat(cornerRadius: 16, material: .regularMaterial)
    }
    #endif

    private var addButtonTitle: String {
        switch addMode {
        case .url:
            return "Add"
        case .file:
            return "Import"
        }
    }

    private var requirementsCard: some View {
        DisclosureGroup(isExpanded: $showHints.animation(.easeInOut(duration: 0.2))) {
            VStack(alignment: .leading, spacing: 8) {
                requirementRow(icon: "link", text: "Starts with http:// or https://")
                requirementRow(icon: "doc.text", text: "Ends with .js or .user.js")
                requirementRow(icon: "checkmark.shield", text: "Hosted on a trusted source")
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("URL requirements")
                        .font(.headline)
                    Text("Tap to review userscript guidelines.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var fileImportMessage: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Supports .user.js or .js files. Local imports won't auto-update; re-import to replace.")
                .foregroundStyle(.secondary)
            if let fileImportError {
                Text(fileImportError)
                    .foregroundStyle(.orange)
            }
        }
        .font(.footnote)
    }

    private var requirementsDisclosure: some View {
        DisclosureGroup(isExpanded: $showHints.animation(.easeInOut(duration: 0.2))) {
            VStack(alignment: .leading, spacing: 8) {
                requirementRow(icon: "link", text: "Starts with http:// or https://")
                requirementRow(icon: "doc.text", text: "Ends with .js or .user.js")
                requirementRow(icon: "checkmark.shield", text: "Hosted on a trusted source")
            }
            .padding(.top, 8)
        } label: {
            Label("Requirements", systemImage: "info.circle")
                .foregroundStyle(.secondary)
        }
    }

    private var compactPasteButton: some View {
        Button {
            pasteFromClipboard()
        } label: {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color.secondary.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isAdding)
        .accessibilityLabel("Paste from Clipboard")
    }

    private var validationBadge: some View {
        Group {
            switch validationState {
            case .idle:
                EmptyView()
            case .invalid:
                Label("Invalid", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .valid:
                Label("Ready", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: validationState)
    }

    private var validationMessage: some View {
        Group {
            switch validationState {
            case .idle:
                Text("wBlock will fetch and enable the script automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .invalid(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .valid:
                Text("Looks good! Tap Add to continue.")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: validationState)
    }

    private func requirementRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(LocalizedStringKey(text))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var addButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if isAdding {
                    ProgressView()
                        .scaleEffect(0.9)
                }
                Text(LocalizedStringKey(isAdding ? "Adding…" : addButtonTitle))
                    .fontWeight(.semibold)
            }
        }
        .primaryActionButtonStyle()
        .disabled(!canSubmit || isAdding)
        .keyboardShortcut(.defaultAction)
    }

    private var canSubmit: Bool {
        if isAdding { return false }
        switch addMode {
        case .url:
            if case .valid = validationState { return true }
            return false
        case .file:
            return true
        }
    }

    private func submit() {
        switch addMode {
        case .url:
            guard case .valid(let url) = validationState else { return }

            isAdding = true

            Task(priority: .userInitiated) {
                await ConcurrentLogManager.shared.info(.userScript, "Adding new userscript from URL", metadata: ["url": url.absoluteString])
                await userScriptManager.addUserScript(from: url)
                await ConcurrentLogManager.shared.info(.userScript, "Successfully added userscript from URL", metadata: ["url": url.absoluteString])

                await MainActor.run {
                    isAdding = false
                    onScriptAdded()
                    dismiss()
                }
            }
        case .file:
            fileImportError = nil
            showingFileImporter = true
        }
    }

    private var allowedImportTypes: [UTType] {
        var types: [UTType] = []

        types.append(UTType.javaScript)

        // Add fallback for .js extension
        if let jsExt = UTType(filenameExtension: "js") {
            types.append(jsExt)
        }

        let userJsTypes = UTType.types(tag: "user.js", tagClass: .filenameExtension, conformingTo: nil)
        if !userJsTypes.isEmpty {
            types.append(contentsOf: userJsTypes)
        } else if let userJsExt = UTType(filenameExtension: "user.js", conformingTo: .data) {
            types.append(userJsExt)
        }

        return types
    }

    private func importFile(at url: URL) {
        isAdding = true
        fileImportError = nil

        Task(priority: .userInitiated) {
            let error = await userScriptManager.addUserScript(fromLocalFile: url)

            if let error {
                await MainActor.run {
                    fileImportError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isAdding = false
                }
            } else {
                await ConcurrentLogManager.shared.info(.userScript, "Imported userscript from file", metadata: ["file": url.lastPathComponent])

                await MainActor.run {
                    isAdding = false
                    onScriptAdded()
                    dismiss()
                }
            }
        }
    }

    private func validateInput(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            validationState = .idle
            return
        }

        guard let url = UserScriptURLSupport.validatedRemoteURL(from: trimmed) else {
            validationState = .invalid("Provide a valid http:// or https:// link ending in .js or .user.js")
            return
        }

        validationState = .valid(url)
    }

    private func pasteFromClipboard() {
        #if os(iOS)
        if let string = UIPasteboard.general.string {
            urlInput = string
        }
        #elseif os(macOS)
        if let string = NSPasteboard.general.string(forType: .string) {
            urlInput = string
        }
        #endif
    }

    private enum ValidationState: Equatable {
        case idle
        case invalid(String)
        case valid(URL)
    }
}
