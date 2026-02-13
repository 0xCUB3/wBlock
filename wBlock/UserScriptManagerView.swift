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

struct UserScriptManagerView: View {
    @ObservedObject var userScriptManager: UserScriptManager

    @State private var scripts: [UserScript] = []
    @State private var isLoading: Bool = false
    @State private var isRefreshing: Bool = false
    @State private var refreshProgress: Double = 0.0
    @State private var refreshStatus: String = ""
    @State private var showingRefreshProgress = false
    @State private var statusDescription: String = ""
    @State private var showingAddScriptSheet = false
    @State private var selectedScript: UserScript?
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

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedScripts: [UserScript] {
        let filteredByEnabled = showOnlyEnabled ? scripts.filter(\.isEnabled) : scripts
        guard !trimmedSearchText.isEmpty else {
            return filteredByEnabled
        }

        return filteredByEnabled.filter { script in
            script.name.localizedCaseInsensitiveContains(trimmedSearchText)
                || script.description.localizedCaseInsensitiveContains(trimmedSearchText)
                || (script.url?.absoluteString.localizedCaseInsensitiveContains(trimmedSearchText)
                    ?? false)
                || (script.updateURL?.localizedCaseInsensitiveContains(trimmedSearchText) ?? false)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Stats cards
                statsCardsView

                // Scripts list
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
        #if os(macOS)
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
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(12)
                }
            }
        }
        #endif
        #if os(iOS)
        .padding(.horizontal, 16)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if #unavailable(iOS 26.0) {
                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
                if !scripts.filter(\.isDownloaded).isEmpty {
                    Button {
                        refreshAllUserScripts()
                    } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                    .disabled(isRefreshing)
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
        #elseif os(macOS)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                ToolbarSearchField(
                    text: $searchText,
                    isExpanded: $showSearch,
                    prompt: "Search scripts"
                )

                if !showSearch {
                    if !scripts.filter(\.isDownloaded).isEmpty {
                        Button {
                            refreshAllUserScripts()
                        } label: {
                            Label("Check for Updates", systemImage: "arrow.down.circle")
                        }
                        .disabled(isRefreshing)
                    }

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
        #if os(iOS)
        .searchable(
            text: $searchText,
            isPresented: $showSearch,
            prompt: "Search scripts"
        )
        .modifier(SearchMinimizeBehavior())
        #endif
        .sheet(isPresented: $showingAddScriptSheet, onDismiss: {
            refreshScripts()
        }) {
            AddUserScriptView(userScriptManager: userScriptManager, onScriptAdded: {
                refreshScripts()
            })
        }
        .sheet(item: $selectedScript) { script in
            UserScriptContentView(script: script)
        }
        .onAppear {
            refreshScripts()
            showOnlyEnabled = ProtobufDataManager.shared.getUserScriptShowEnabledOnly()
        }
        .alert("Duplicate Userscripts Found", isPresented: $userScriptManager.showingDuplicatesAlert) {
            Button("Remove Older Versions", role: .destructive) {
                userScriptManager.confirmDuplicateRemoval()
                refreshScripts()
            }
            Button("Keep All", role: .cancel) {
                userScriptManager.cancelDuplicateRemoval()
            }
        } message: {
            Text(userScriptManager.duplicatesMessage)
        }
        .alert("Import Failed", isPresented: Binding(
            get: { dropErrorMessage != nil },
            set: { newValue in if !newValue { dropErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { dropErrorMessage = nil }
        } message: {
            Text(dropErrorMessage ?? "")
        }
        .overlay {
            if showingRefreshProgress {
                ZStack {
                    Color.black.opacity(0.1).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView(value: refreshProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 200)
                        Text(refreshStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(Int(refreshProgress * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 10)
                }
            }
        }
    }

    private func refreshScripts() {
        scripts = userScriptManager.userScripts
        statusDescription = userScriptManager.statusDescription
        isLoading = userScriptManager.isLoading
    }

    private func refreshAllUserScripts() {
        let downloadedScripts = scripts.filter { $0.isDownloaded }
        guard !downloadedScripts.isEmpty else { return }

        isRefreshing = true
        showingRefreshProgress = true
        refreshProgress = 0.0
        refreshStatus = "Starting refresh..."

        Task {
            await ConcurrentLogManager.shared.info(.userScript, "Starting userscript refresh", metadata: ["count": "\(downloadedScripts.count)"])

            for (index, script) in downloadedScripts.enumerated() {
                await MainActor.run {
                    refreshStatus = "Updating \(script.name)..."
                    refreshProgress = Double(index) / Double(downloadedScripts.count)
                }

                await ConcurrentLogManager.shared.debug(.userScript, "Updating userscript", metadata: ["script": script.name])
                await userScriptManager.updateUserScript(script)

                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            await MainActor.run {
                refreshProgress = 1.0
                refreshStatus = "Refresh complete!"

                scripts = userScriptManager.userScripts
                statusDescription = userScriptManager.statusDescription
                isLoading = userScriptManager.isLoading
            }

            await ConcurrentLogManager.shared.info(.userScript, "Userscript refresh completed successfully", metadata: [:])

            try? await Task.sleep(nanoseconds: 1_000_000_000)

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    showingRefreshProgress = false
                    isRefreshing = false
                }
            }
        }
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

            StatCard(
                title: "Enabled",
                value: "\(enabledScriptsCount)",
                icon: "checkmark.circle",
                pillColor: .clear,
                valueColor: .primary
            )
        }
        .padding(.horizontal)
    }

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

    private func scriptRowView(script: UserScript) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(script.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if !script.description.isEmpty {
                    Text(script.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 4) {
                    if !script.version.isEmpty {
                        Text("Version \(script.version)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    if let lastUpdated = script.lastUpdatedFormatted {
                        if !script.version.isEmpty {
                            Text("·")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        Text(lastUpdated)
                            .font(.caption2)
                            .foregroundColor(.gray)
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
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }

                if !script.isDownloaded {
                    Text("Not Downloaded")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                        .cornerRadius(4)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if !script.isDownloaded, !script.isLocal, script.url != nil {
                    Button {
                        Task {
                            await ConcurrentLogManager.shared.debug(.userScript, "Downloading userscript", metadata: ["script": script.name])
                            await userScriptManager.downloadUserScript(script)
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

                if script.isDownloaded {
                    Button {
                        Task {
                            await ConcurrentLogManager.shared.debug(.userScript, "Updating userscript", metadata: ["script": script.name])
                            await userScriptManager.updateUserScript(script)
                            await ConcurrentLogManager.shared.info(.userScript, "Successfully updated userscript", metadata: ["script": script.name])
                            refreshScripts()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    #if os(macOS)
                    .help("Update Script")
                    #endif
                }

                Toggle("", isOn: Binding(
                    get: { script.isEnabled },
                    set: { _ in
                        Task {
                            await ConcurrentLogManager.shared.debug(.userScript, "Toggling userscript", metadata: ["script": script.name])
                            await userScriptManager.toggleUserScript(script)
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
        .padding(16)
        .id(script.id)
        .contentShape(.interaction, Rectangle())
        .onTapGesture {
            if script.isDownloaded {
                selectedScript = script
            }
        }
        .contextMenu {
            #if os(macOS)
            if script.isDownloaded {
                Button {
                    selectedScript = script
                } label: {
                    Label("View Content", systemImage: "doc.text")
                }
            }
            #endif
            if script.isDownloaded {
                Button {
                    Task {
                        await userScriptManager.updateUserScript(script)
                        refreshScripts()
                    }
                } label: {
                    Label("Update", systemImage: "arrow.clockwise")
                }
            }
            if !userScriptManager.isDefaultUserScript(script) {
                Button(role: .destructive) {
                    Task {
                        await ConcurrentLogManager.shared.info(.userScript, "Removing userscript", metadata: ["script": script.name])
                    }
                    userScriptManager.removeUserScript(script)
                    refreshScripts()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.6))
            Text("No Userscripts")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Add userscripts to customize your browsing experience")
                .font(.body)
                .foregroundColor(.secondary)
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
                .foregroundColor(.secondary.opacity(0.7))
            Text("No matching userscripts")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - UserScriptInfoSidebar Subviews

private struct ScriptNameAndDescriptionView: View {
    let script: UserScript
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(script.name).font(.title2).fontWeight(.semibold).foregroundColor(.primary).textSelection(.enabled)
            if !script.description.isEmpty {
                Text(script.description).font(.body).foregroundColor(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ScriptStatusBadgesView: View {
    let script: UserScript
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if !script.version.isEmpty {
                    Badge(text: "v\(script.version)", color: .blue)
                }
                Badge(text: script.isEnabled ? "Enabled" : "Disabled", color: script.isEnabled ? .green : .secondary)
            }
            if !script.isDownloaded {
                Badge(text: "Not Downloaded", color: .red)
            } else {
                Badge(text: "Downloaded", color: .green)
            }
        }
    }
}

private struct ScriptFileInfoView: View {
    let script: UserScript
    let formatFileSize: (Int) -> String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("File Information").font(.caption).fontWeight(.medium).foregroundColor(.secondary)
            HStack {
                Text("Size:").font(.caption2).foregroundColor(.secondary)
                Text(formatFileSize(script.content.count)).font(.caption).fontWeight(.medium).foregroundColor(.primary)
                Spacer()
            }.padding(.horizontal, 8).padding(.vertical, 6).cornerRadius(6)
        }
    }
}

private struct ScriptURLView: View {
    let script: UserScript
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Source URL").font(.caption).fontWeight(.medium).foregroundColor(.secondary)
            Text(script.url?.absoluteString ?? "N/A").font(.caption).foregroundColor(.blue).textSelection(.enabled).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ScriptMatchPatternRowView: View {
    let index: Int
    let pattern: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(index + 1).")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 18, alignment: .trailing)

            Text(pattern)
                .font(.caption)
                .foregroundColor(.orange)
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
                    Text("URL Patterns (\(script.matches.count))")
                        .font(.caption).fontWeight(.medium).foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: isPatternsExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundColor(.secondary)
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
    @Binding var isPatternsExpanded: Bool
    let formatFileSize: (Int) -> String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScriptNameAndDescriptionView(script: script)
            ScriptStatusBadgesView(script: script)
            if !script.content.isEmpty { ScriptFileInfoView(script: script, formatFileSize: formatFileSize) }
            if script.url != nil { ScriptURLView(script: script) }
            if !script.matches.isEmpty { ScriptMatchPatternsView(script: script, isPatternsExpanded: $isPatternsExpanded) }
            Spacer()
        }
    }
}

#if os(macOS)
struct ScriptContentMainView: View {
    let script: UserScript
    @Binding var displayedContent: String
    @Binding var isLoadingContent: Bool
    @Binding var showFullContent: Bool
    let previewLength: Int
    let formatFileSize: (Int) -> String
    let toggleContentViewAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Script Content").font(.headline).fontWeight(.medium)
                    if !script.content.isEmpty && script.content.count > previewLength && !showFullContent {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle").font(.caption2).foregroundColor(.orange)
                            Text("Showing preview (\(formatFileSize(previewLength)) of \(formatFileSize(script.content.count)))")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    } else if showFullContent && script.content.count > previewLength {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle").font(.caption2).foregroundColor(.green)
                            Text("Full content loaded").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                Spacer()
                HStack(spacing: 12) {
                    if !script.content.isEmpty && script.content.count > previewLength {
                        Button { toggleContentViewAction() } label: {
                            HStack(spacing: 6) {
                                if isLoadingContent { ProgressView().scaleEffect(0.8).frame(width: 12, height: 12) }
                                else { Image(systemName: showFullContent ? "eye.slash" : "eye") }
                                Text(showFullContent ? "Show Preview" : "Show All")
                            }
                        }.buttonStyle(.borderless).disabled(isLoadingContent)
                         .help(showFullContent ? "Show preview only" : "Load full content")
                    }
                }
            }.padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            if script.content.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text").font(.system(size: 48)).foregroundColor(.secondary.opacity(0.6))
                    Text("No Content Available").font(.headline).foregroundColor(.secondary)
                    Text("This script hasn't been downloaded yet.").font(.body).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Text(displayedContent).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                    }
                }
                .overlay( Group {
                    if script.content.count > 100000 && showFullContent {
                        VStack { Spacer(); HStack { Spacer()
                            HStack(spacing: 6) { Image(systemName: "info.circle.fill").foregroundColor(.orange)
                                Text("Large file - scrolling may be slow")
                            }.padding(.horizontal, 8).padding(.vertical, 4).background(Color.orange.opacity(0.1)).cornerRadius(6).padding()
                        }}
                    }
                }, alignment: .bottomTrailing)
            }
        }
    }
}
#endif

struct UserScriptContentView: View {
    let script: UserScript
    @Environment(\.dismiss) private var dismiss
    @State private var displayedContent: String = ""
    @State private var isLoadingContent = false
    @State private var showFullContent = false
    @State private var sidebarWidth: CGFloat = 280
    @State private var isPatternsExpanded = false

    private let previewLength = 10000
    #if os(macOS)
    private let minSidebarWidth: CGFloat = 250
    private let maxSidebarWidth: CGFloat = 500
    #endif

    var body: some View {
        #if os(iOS)
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    UserScriptInfoSidebar(
                        script: script,
                        isPatternsExpanded: $isPatternsExpanded,
                        formatFileSize: formatFileSize
                    )
                    .padding(.horizontal)

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Script Content")
                            .font(.headline)
                            .fontWeight(.medium)

                        if script.content.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary.opacity(0.6))
                                Text("No Content Available")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("This script hasn't been downloaded yet.")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            Text(displayedContent)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle(script.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { loadInitialContent() }
        #else
        HSplitView {
            UserScriptInfoSidebar(
                script: script,
                isPatternsExpanded: $isPatternsExpanded,
                formatFileSize: formatFileSize
            )
            .frame(minWidth: minSidebarWidth, idealWidth: sidebarWidth, maxWidth: maxSidebarWidth)
            .padding(20)

            ScriptContentMainView(
                script: script,
                displayedContent: $displayedContent,
                isLoadingContent: $isLoadingContent,
                showFullContent: $showFullContent,
                previewLength: previewLength,
                formatFileSize: formatFileSize,
                toggleContentViewAction: toggleContentView
            )
            .frame(minWidth: 400)
        }
        .navigationTitle("")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .frame(width: 1000, height: 700)
        .onAppear { loadInitialContent() }
        #endif
    }

    private func loadInitialContent() {
        if script.content.isEmpty { displayedContent = ""; return }
        if script.content.count <= previewLength {
            displayedContent = script.content; showFullContent = true
        } else {
            displayedContent = String(script.content.prefix(previewLength)); showFullContent = false
        }
    }

    private func toggleContentView() {
        if showFullContent {
            displayedContent = String(script.content.prefix(previewLength))
            showFullContent = false
        } else {
            isLoadingContent = true

            DispatchQueue.global(qos: .userInitiated).async {
                let fullContent = script.content

                DispatchQueue.main.async {
                    displayedContent = fullContent
                    showFullContent = true
                    isLoadingContent = false
                }
            }
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter(); formatter.allowedUnits = [.useKB, .useMB]; formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(LocalizedStringKey(text)).font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15)).foregroundColor(color).cornerRadius(4)
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
        .onAppear {
            urlFieldFocused = addMode == .url
        }
        .onChange(of: addMode) { _, newValue in
            urlFieldFocused = newValue == .url
        }
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
                Text("Paste the direct .user.js link. wBlock will download and install it for you.")
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
                requirementRow(icon: "link", text: "Starts with https://")
                requirementRow(icon: "doc.text", text: "Ends with .user.js")
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
                requirementRow(icon: "link", text: "Starts with https://")
                requirementRow(icon: "doc.text", text: "Ends with .user.js")
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

        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              let host = components.host,
              !host.isEmpty,
              trimmed.lowercased().hasSuffix(".user.js"),
              let url = components.url else {
            validationState = .invalid(String(localized: "Provide a valid https:// link ending in .user.js"))
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
