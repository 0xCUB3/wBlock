//
//  UserScriptManagerView.swift
//  wBlock
//
//  Created by Alexander Skula on 6/7/25.
//

import SwiftUI
import wBlockCoreService
import UniformTypeIdentifiers

private extension FilterListCategory {
    static var userScriptCategories: [FilterListCategory] {
        [.scripts, .custom]
    }
}

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
    let updatesAutomatically: Bool
    let isUserStyle: Bool
    let category: FilterListCategory
    let displayCategory: UserScriptDisplayCategory
    let isBuiltIn: Bool
    let isIntegrated: Bool
    let isCustom: Bool
    let isBeta: Bool

    init(
        script: UserScript,
        isDownloaded: Bool,
        isBuiltIn: Bool,
        builtInDisplayRole: BuiltInUserScriptDisplayRole?,
        isBeta: Bool = false
    ) {
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
        self.isDownloaded = isDownloaded
        updatesAutomatically = script.updatesAutomatically
        isUserStyle = script.isUserStyle
        category = script.category
        displayCategory = UserScriptDisplayCategorySupport.category(
            isUserStyle: script.isUserStyle,
            builtInRole: builtInDisplayRole,
            persistedCategory: script.category
        )
        self.isBuiltIn = isBuiltIn
        isIntegrated = isBuiltIn && builtInDisplayRole == .functionality
            && (script.name == "Tube Cleaner" || script.name == "Player Cleaner")
        isCustom = !isBuiltIn
        self.isBeta = isBeta
    }
}

private typealias UserScriptSectionKind = UserScriptDisplayCategory

private struct UserScriptDisplaySection: Identifiable {
    let id: UserScriptSectionKind
    let title: LocalizedStringKey
    let description: LocalizedStringKey?
    let scripts: [UserScriptListItem]
}

private struct SelectedUserScript: Identifiable {
    let id: UUID
    let action: UserScriptContextMenuAction
}

private struct EditorMetadataAutofillState: Equatable {
    private(set) var lastAutofilledName = ""
    private(set) var lastAutofilledDescription = ""
    private(set) var nameWasManuallyEdited = false
    private(set) var descriptionWasManuallyEdited = false

    mutating func autofill(
        name metadataName: String,
        description metadataDescription: String,
        currentName: String,
        currentDescription: String
    ) -> (name: String, description: String) {
        let name = metadataName.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = metadataDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nameWasManuallyEdited {
            lastAutofilledName = name.isEmpty ? "Pasted Userscript" : name
        }
        if !descriptionWasManuallyEdited {
            lastAutofilledDescription = description
        }
        return (
            nameWasManuallyEdited ? currentName : lastAutofilledName,
            descriptionWasManuallyEdited ? currentDescription : lastAutofilledDescription
        )
    }

    mutating func noteNameEdit(_ value: String) {
        if value != lastAutofilledName { nameWasManuallyEdited = true }
    }

    mutating func noteDescriptionEdit(_ value: String) {
        if value != lastAutofilledDescription { descriptionWasManuallyEdited = true }
    }
}

struct UserScriptManagerView: View {
    @ObservedObject var userScriptManager: UserScriptManager
    let hasPendingChanges: Bool
    let isApplyingChanges: Bool
    let onApplyChanges: () -> Void
    let tabSelection: Int

    @State private var scripts: [UserScriptListItem] = []
    @State private var showingAddScriptSheet = false
    @State private var selectedScript: SelectedUserScript?
    @State private var showOnlyEnabled = false
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var downloadingScriptIDs = Set<UUID>()
    @State private var isDropTarget = false
    @State private var isDropProcessing = false
    @State private var dropErrorMessage: String?

    private var totalScriptsCount: Int {
        scripts.filter { !$0.isUserStyle }.count
    }

    private var totalStylesCount: Int {
        scripts.filter(\.isUserStyle).count
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
        let filteredBySearch: [UserScriptListItem]

        if trimmedSearchText.isEmpty {
            filteredBySearch = filteredByEnabled
        } else {
            filteredBySearch = filteredByEnabled.filter { script in
                script.localizedDisplayName.localizedCaseInsensitiveContains(trimmedSearchText)
                    || script.localizedDisplayDescription.localizedCaseInsensitiveContains(trimmedSearchText)
                    || (script.url?.absoluteString.localizedCaseInsensitiveContains(trimmedSearchText)
                        ?? false)
                    || (script.updateURL?.localizedCaseInsensitiveContains(trimmedSearchText) ?? false)
            }
        }

        return filteredBySearch.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var displayedScriptSections: [UserScriptDisplaySection] {
        UserScriptDisplayCategorySupport.orderedGroups(
            displayedScripts,
            category: { $0.displayCategory }
        ).map { group in
            UserScriptDisplaySection(
                id: group.category,
                title: LocalizedStringKey(group.category.rawValue),
                description: LocalizedStringKey(group.category.descriptionKey),
                scripts: group.items
            )
        }
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
            if selection.action == .info {
                UserScriptInfoView(
                    scriptId: selection.id,
                    userScriptManager: userScriptManager
                )
            } else {
                UserScriptContentView(
                    scriptId: selection.id,
                    userScriptManager: userScriptManager,
                    startsEditing: selection.action == .editContent
                )
            }
        }
        .onAppear {
            refreshScripts()
            showOnlyEnabled = ProtobufDataManager.shared.getUserScriptShowEnabledOnly()
        }
        .onReceive(userScriptManager.$userScripts) { _ in
            refreshScripts()
        }
        .onChangeCompat(of: tabSelection) { _, _ in
            searchText = ""
            showSearch = false
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
        let sections = displayedScriptSections
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
            } else if sections.isEmpty {
                Section {
                    noSearchResultsView
                        .padding(.vertical, 40)
                }
            } else {
                ForEach(sections) { scriptSection in
                    Section {
                        ForEach(scriptSection.scripts) { script in
                            scriptRowView(script: script)
                        }
                    } header: {
                        displaySectionHeader(scriptSection)
                    }
                }
            }        }
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
        .searchableCompat(
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
                } else if sections.isEmpty {
                    noSearchResultsView
                        .padding(.top, 40)
                } else {
                    scriptsListView(sections: sections)
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
                if !showSearch {
                    Button {
                        showingAddScriptSheet = true
                    } label: {
                        Label("Add Userscript or Userstyle", systemImage: "plus")
                    }

                    applyChangesToolbarButton
                        .help(
                            hasPendingChanges
                                ? String(localized: "Apply your pending changes")
                                : String(localized: "Apply changes")
                        )

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

            ToolbarItem(placement: .automatic) {
                ToolbarSearchField(
                    text: $searchText,
                    isExpanded: $showSearch,
                    prompt: "Search scripts"
                )
            }
        }
        #endif
    }

    private func refreshScripts() {
        scripts = userScriptManager.userScripts.map { script in
            UserScriptListItem(
                script: script,
                isDownloaded: userScriptManager.hasDownloadedContent(for: script),
                isBuiltIn: userScriptManager.isDefaultUserScript(script),
                builtInDisplayRole: userScriptManager.builtInDisplayRole(for: script),
                isBeta: userScriptManager.isBeta(for: script)
            )
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
                    await ConcurrentLogManager.shared.error(.userScript, LocalizedStrings.text("Failed to load dropped item"), metadata: ["error": error.localizedDescription])
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
                    await ConcurrentLogManager.shared.error(.userScript, LocalizedStrings.text("Could not resolve URL from dropped item."))
                }
                return
            }

            Task {
                await MainActor.run { isDropProcessing = true }

                let error = await userScriptManager.addUserScript(fromLocalFile: resolvedURL)
                if let error {
                    await ConcurrentLogManager.shared.error(.userScript, LocalizedStrings.text("Failed to import dropped userscript"), metadata: ["error": error.localizedDescription])
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
                valueColor: .primary
            )
            #if os(iOS)
            .frame(maxWidth: .infinity, alignment: .leading)
            #endif

            if totalStylesCount > 0 {
                StatCard(
                    title: "Styles",
                    value: "\(totalStylesCount)",
                    icon: "paintbrush",
                    valueColor: .primary
                )
                #if os(iOS)
                .frame(maxWidth: .infinity, alignment: .leading)
                #endif
            }

            StatCard(
                title: "Enabled",
                value: "\(enabledScriptsCount)",
                icon: "checkmark.circle",
                valueColor: .primary
            )
            #if os(iOS)
            .frame(maxWidth: .infinity, alignment: .leading)
            #endif
        }
        .padding(.horizontal)
    }

    private func displaySectionHeader(_ section: UserScriptDisplaySection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(section.title)
            if let description = section.description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    #if os(macOS)
    private func scriptsListView(sections: [UserScriptDisplaySection]) -> some View {
        LazyVStack(spacing: 16) {
            ForEach(sections) { scriptSection in
                macOSUserScriptSectionView(
                    title: scriptSection.title,
                    description: scriptSection.description,
                    scripts: scriptSection.scripts
                )
            }
        }        .padding(.horizontal)
    }

    private func macOSUserScriptSectionView(
        title: LocalizedStringKey,
        description: LocalizedStringKey?,
        scripts: [UserScriptListItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(scripts.indices, id: \.self) { index in
                    scriptRowView(script: scripts[index])

                    if index < scripts.count - 1 {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    #endif

    private func scriptRowView(script: UserScriptListItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(script.localizedDisplayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !script.localizedDisplayDescription.isEmpty {
                    Text(script.localizedDisplayDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    Text(script.isIntegrated ? "Integrated" : (script.isUserStyle ? "Userstyle" : "Userscript"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if script.isLocal {
                        Badge(text: "Local Import", color: .blue)
                    } else if script.isCustom {
                        Badge(text: "Custom", color: .blue)
                    }
                    if script.isBeta {
                        Badge(text: "Beta", color: .orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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
                Toggle("", isOn: Binding(
                    get: { script.isEnabled || downloadingScriptIDs.contains(script.id) },
                    set: { newValue in
                        let shouldDownloadBeforeEnabling =
                            newValue && !script.isDownloaded && !script.isLocal && script.url != nil
                        if shouldDownloadBeforeEnabling {
                            downloadingScriptIDs.insert(script.id)
                        }

                        Task {
                            guard let managedScript = userScriptManager.userScript(withId: script.id) else {
                                await MainActor.run { downloadingScriptIDs.remove(script.id) }
                                return
                            }
                            await ConcurrentLogManager.shared.debug(
                                .userScript,
                                LocalizedStrings.text("Setting userscript enabled state"),
                                metadata: ["script": script.name, "enabled": "\(newValue)"]
                            )
                            await userScriptManager.setUserScript(managedScript, isEnabled: newValue)
                            await MainActor.run {
                                downloadingScriptIDs.remove(script.id)
                                refreshScripts()
                            }
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(downloadingScriptIDs.contains(script.id) || (script.isLocal && !script.isDownloaded))
                .frame(alignment: .center)
            }
        }
        .id(script.id)
        .contentShape(.interaction, Rectangle())
        .onTapGesture {
            if script.isDownloaded {
                // Defer to avoid race with context menu dismissal on iOS
                DispatchQueue.main.async {
                    selectedScript = SelectedUserScript(id: script.id, action: .info)
                }
            }
        }
        .contextMenu {
            let actions = ContextMenuActionAvailability.userScriptActions(
                isBuiltIn: script.isBuiltIn,
                isLocal: script.isLocal
            )
            if actions.contains(.info) {
                Button {
                    selectedScript = SelectedUserScript(id: script.id, action: .info)
                } label: {
                    Label("Info", systemImage: "info.circle")
                }
            }
            if actions.contains(.viewContent) {
                Button {
                    selectedScript = SelectedUserScript(id: script.id, action: .viewContent)
                } label: {
                    Label("View Content", systemImage: "doc.text")
                }
            }
            if actions.contains(.editContent) {
                Button {
                    selectedScript = SelectedUserScript(id: script.id, action: .editContent)
                } label: {
                    Label("Edit Content", systemImage: "pencil")
                }
            }
            if actions.contains(.deleteScript),
               let managedScript = userScriptManager.userScript(withId: script.id) {
                Button(role: .destructive) {
                    Task {
                        await ConcurrentLogManager.shared.info(.userScript, LocalizedStrings.text("Removing userscript"), metadata: ["script": script.name])
                        userScriptManager.removeUserScript(managedScript)
                        refreshScripts()
                    }
                } label: {
                    Label(
                        script.isUserStyle ? "Delete Style" : "Delete Script",
                        systemImage: "trash"
                    )
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
            Text("Add userscripts and userstyles to customize your browsing experience")
                .font(.body)
                .foregroundStyle(.secondary)
            Button {
                showingAddScriptSheet = true
            } label: {
                Label("Add Userscript or Userstyle", systemImage: "plus")
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
    let isBeta: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(script.localizedDisplayName)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                if isBeta {
                    Text("Beta")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .cornerRadius(4)
                }
            }
            if !script.localizedDisplayDescription.isEmpty {
                Text(script.localizedDisplayDescription).font(.body).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ScriptStatusBadgesView: View {
    let script: UserScript
    let isDownloaded: Bool
    let isBuiltIn: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Array(InfoBadgeSupport.userScriptBadges(
                    script,
                    isDownloaded: isDownloaded,
                    isBuiltIn: isBuiltIn
                ).enumerated()), id: \.offset) { _, badge in
                    InfoBadgeView(kind: badge)
                }
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
    let isBundled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Source URL").font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
            if isBundled {
                Text("Ships with the app")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let url = script.url {
                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    #if os(iOS)
                    UIPasteboard.general.string = url.absoluteString
                    #elseif os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    #endif
                } label: {
                    Label("Copy URL", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
            }
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

    /// Userstyles persist serialized @-moz-document conditions in `matches`;
    /// render them in a human-readable form instead of the storage format.
    private func displayPattern(_ pattern: String) -> String {
        guard script.isUserStyle else { return pattern }
        if pattern == "global" {
            return LocalizedStrings.text("All websites", comment: "Userstyle condition that applies everywhere")
        }
        for prefix in ["domain:", "url-prefix:", "url:", "regexp:"] where pattern.hasPrefix(prefix) {
            let value = String(pattern.dropFirst(prefix.count))
            return prefix == "url-prefix:" ? value + "…" : value
        }
        return pattern
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPatternsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(
                        script.isUserStyle
                            ? LocalizedStrings.format(
                                "Applies To (%d)",
                                comment: "Userstyle condition section title",
                                script.matches.count
                            )
                            : LocalizedStrings.format(
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
                            ScriptMatchPatternRowView(
                                index: indexInForEach,
                                pattern: displayPattern(script.matches[indexInForEach])
                            )
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


private struct ScriptUpdateSettingsView: View {
    let updatesAutomatically: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Automatic Updates", isOn: Binding(
                get: { updatesAutomatically },
                set: onChange
            ))
            .toggleStyle(.switch)

            Text("Turn this off to keep the current version when wBlock updates scripts in bulk or on a schedule.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(updatesAutomatically ? 0 : 0.08))
        .cornerRadius(8)
    }
}


struct UserScriptInfoSidebar: View {
    let script: UserScript
    let contentLength: Int
    @Binding var isPatternsExpanded: Bool
    let formatFileSize: (Int) -> String
    let isBundled: Bool
    let isBuiltIn: Bool
    let isBeta: Bool
    let onUpdatesAutomaticallyChanged: (Bool) -> Void
    var fillsAvailableSpace = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScriptNameAndDescriptionView(script: script, isBeta: isBeta)
            ScriptStatusBadgesView(
                script: script,
                isDownloaded: contentLength > 0,
                isBuiltIn: isBuiltIn
            )
            // Bundled scripts update with the app, so auto-update controls are noise.
            if !isBundled && (script.url != nil || script.updateURL != nil || script.downloadURL != nil) {
                ScriptUpdateSettingsView(
                    updatesAutomatically: script.updatesAutomatically,
                    onChange: onUpdatesAutomaticallyChanged
                )
            }
            if contentLength > 0 {
                ScriptFileInfoView(contentLength: contentLength, formatFileSize: formatFileSize)
            }
            if script.url != nil { ScriptURLView(script: script, isBundled: isBundled) }
            if !script.matches.isEmpty { ScriptMatchPatternsView(script: script, isPatternsExpanded: $isPatternsExpanded) }
            if fillsAvailableSpace {
                Spacer()
            }
        }
    }
}

#if os(macOS)
struct ScriptContentMainView: View {
    let previewContent: String
    let contentLength: Int
    let isUserStyle: Bool
    let formatFileSize: (Int) -> String
    let onShowSource: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    (isUserStyle ? Text("Style Content") : Text("Script Content")).font(.headline).fontWeight(.medium)
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

struct UserScriptInfoView: View {
    let scriptId: UUID
    var userScriptManager: UserScriptManager

    @Environment(\.dismiss) private var dismiss
    @State private var script: UserScript?
    @State private var isPatternsExpanded = false
    @State private var isLoading = true

    var body: some View {
        Group {
            if let script {
                #if os(iOS)
                NavigationView {
                    ScrollView {
                        UserScriptInfoSidebar(
                            script: script,
                            contentLength: script.content.count,
                            isPatternsExpanded: $isPatternsExpanded,
                            formatFileSize: formatFileSize,
                            isBundled: userScriptManager.isBundled(for: script),
                            isBuiltIn: userScriptManager.isDefaultUserScript(script),
                            isBeta: userScriptManager.isBeta(for: script),
                            onUpdatesAutomaticallyChanged: setUpdatesAutomatically
                        )
                        .padding()
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
                UserScriptInfoSidebar(
                    script: script,
                    contentLength: script.content.count,
                    isPatternsExpanded: $isPatternsExpanded,
                    formatFileSize: formatFileSize,
                    isBundled: userScriptManager.isBundled(for: script),
                    isBuiltIn: userScriptManager.isDefaultUserScript(script),
                    isBeta: userScriptManager.isBeta(for: script),
                    onUpdatesAutomaticallyChanged: setUpdatesAutomatically,
                    fillsAvailableSpace: false
                )
                .padding(20)
                .frame(width: 460)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                #endif
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Unable to load script")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: scriptId) {
            isLoading = true
            script = await userScriptManager.userScriptEditorSnapshot(withId: scriptId)
            isLoading = false
        }
    }

    private func setUpdatesAutomatically(_ updatesAutomatically: Bool) {
        guard var currentScript = script else { return }
        currentScript.updatesAutomatically = updatesAutomatically
        script = currentScript
        Task {
            await userScriptManager.setUserScript(currentScript, updatesAutomatically: updatesAutomatically)
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct UserScriptContentView: View {
    let scriptId: UUID
    var userScriptManager: UserScriptManager
    var startsEditing: Bool = false
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
                                formatFileSize: formatFileSize,
                                isBundled: userScriptManager.isBundled(for: script),
                                isBuiltIn: userScriptManager.isDefaultUserScript(script),
                                isBeta: userScriptManager.isBeta(for: script),
                                onUpdatesAutomaticallyChanged: setUpdatesAutomatically
                            )
                            .padding(.horizontal)

                            Divider()

                            VStack(alignment: .leading, spacing: 12) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .center, spacing: 12) {
                                        (script.isUserStyle ? Text("Style Content") : Text("Script Content"))
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
                        formatFileSize: formatFileSize,
                        isBundled: userScriptManager.isBundled(for: script),
                        isBuiltIn: userScriptManager.isDefaultUserScript(script),
                        isBeta: userScriptManager.isBeta(for: script),
                        onUpdatesAutomaticallyChanged: setUpdatesAutomatically
                    )
                    .frame(minWidth: minSidebarWidth, idealWidth: sidebarWidth, maxWidth: maxSidebarWidth)
                    .padding(20)

                    ScriptContentMainView(
                        previewContent: previewContent,
                        contentLength: loadedContent.count,
                        isUserStyle: script.isUserStyle,
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
                    canEdit: script.isLocal && !userScriptManager.isDefaultUserScript(script),
                    onSave: { newContent, name, description in
                        await userScriptManager.saveEditedContent(for: script.id, newContent: newContent)
                        await userScriptManager.setUserScriptMetadataOverrides(
                            for: script.id,
                            name: name,
                            description: description
                        )
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
        if startsEditing && metadata.isLocal && !userScriptManager.isDefaultUserScript(metadata) {
            isShowingSourceSheet = true
        }
    }

    private func setUpdatesAutomatically(_ updatesAutomatically: Bool) {
        guard var currentScript = script else { return }
        currentScript.updatesAutomatically = updatesAutomatically
        script = currentScript

        Task {
            await userScriptManager.setUserScript(currentScript, updatesAutomatically: updatesAutomatically)
        }
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
    let canEdit: Bool
    let onSave: (String, String, String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var editorController: CodeMirrorEditorController
    @State private var isEditing: Bool
    @State private var isLineWrappingEnabled = false
    @State private var isSaving = false
    @State private var validationMessage: String?
    @State private var editedName: String
    @State private var editedDescription: String

    init(
        script: UserScript,
        initialContent: String,
        canEdit: Bool,
        onSave: @escaping (String, String, String) async -> Void
    ) {
        self.script = script
        self.initialContent = initialContent
        self.canEdit = canEdit
        self.onSave = onSave
        _editorController = StateObject(wrappedValue: CodeMirrorEditorController(text: initialContent, isUserStyle: script.isUserStyle))
        _isEditing = State(initialValue: false)
        _editedName = State(initialValue: script.name)
        _editedDescription = State(initialValue: script.description)
    }

    var body: some View {
        #if os(iOS)
        CompatibleNavigationStack {
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
                    (script.isUserStyle ? Text("Style Content") : Text("Script Content"))
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
                    .disabled(isSaving || (!editorController.isDirty && !hasMetadataChanges))
                } else {
                    if canEdit {
                        Button("Edit") {
                            isEditing = true
                            DispatchQueue.main.async {
                                editorController.focus()
                            }
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

            if let analysis = editorController.analysis, analysis.isLargeDocument {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.slash")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(LocalizedStrings.text(
                        "Highlighting disabled for performance",
                        comment: "CodeMirror source sheet: large document note"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                Divider()
            }

            if isEditing && canEdit {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Name", text: $editedName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Description", text: $editedDescription)
                        .textFieldStyle(.roundedBorder)
                    if let validationMessage {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }

            CodeMirrorTextEditor(
                controller: editorController,
                isEditable: isEditing && canEdit,
                isLineWrappingEnabled: isLineWrappingEnabled
            )
        }
    }

    private var hasMetadataChanges: Bool {
        editedName.trimmingCharacters(in: .whitespacesAndNewlines) != script.name
            || editedDescription.trimmingCharacters(in: .whitespacesAndNewlines) != script.description
    }

    @MainActor
    private func saveChanges() async {
        let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = LocalizedStrings.text(
                "Title is required.",
                comment: "Userscript metadata validation error"
            )
            return
        }

        isSaving = true
        let newContent = await editorController.currentText()
        await onSave(newContent, trimmedName, editedDescription)
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

private struct AddUserScriptEditorSheet: View {
    @ObservedObject var editorController: CodeMirrorEditorController
    let onTextChanged: (String) -> Void
    let onPaste: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isLineWrappingEnabled = false

    var body: some View {
        Group {
            #if os(iOS)
            CompatibleNavigationStack {
                editorBody
                    .background(Color(.systemGray6))
                    .navigationTitle("Editor")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", action: finish)
                        }
                    }
            }
            #else
            editorBody
                .frame(width: 1000, height: 700)
            #endif
        }
        .onDisappear {
            Task { @MainActor in
                onTextChanged(await editorController.currentText())
            }
        }
    }

    private var editorBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    editorController.openSearch()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .accessibilityLabel("Search")

                Button {
                    isLineWrappingEnabled.toggle()
                } label: {
                    Label("Wrap Lines", systemImage: isLineWrappingEnabled ? "text.justify.left" : "text.alignleft")
                }
                .accessibilityValue(
                    isLineWrappingEnabled
                        ? String(localized: "On")
                        : String(localized: "Off")
                )

                Spacer()

                Button(action: onPaste) {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }

                #if os(macOS)
                Button("Done", action: finish)
                    .buttonStyle(.borderedProminent)
                #endif
            }
            .padding(12)
            .liquidGlassCompat(cornerRadius: 12, material: .regularMaterial)
            .padding(12)

            CodeMirrorTextEditor(
                controller: editorController,
                isEditable: true,
                isLineWrappingEnabled: isLineWrappingEnabled
            )
            .frame(minWidth: 420, minHeight: 360)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private func finish() {
        Task { @MainActor in
            onTextChanged(await editorController.currentText())
            dismiss()
        }
    }
}

struct AddUserScriptView: View {
    var userScriptManager: UserScriptManager
    var onScriptAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var urlInput: String = ""
    @State private var validationState: ValidationState = .idle
    @State private var urlImportError: String?
    @State private var isAdding: Bool = false
    @State private var fileImportError: String?
    @State private var editorImportError: String?
    @State private var textInput = ""
    @State private var isShowingEditor = false
    @State private var showingPasteReplacementConfirmation = false
    @State private var pendingPasteText: String?
    @State private var showingFileImporter = false
    @State private var stagedFile: StagedScriptFile?
    @State private var isStagingFile = false
    @State private var stagingGeneration = 0
    @State private var stagedName = ""
    @State private var stagedDescription = ""
    @State private var selectedCategory: FilterListCategory = .scripts
    @State private var editorMetadataState = EditorMetadataAutofillState()
    @State private var editorMetadataRefreshTask: Task<Void, Never>?
    @State private var metadataRefreshGeneration = 0
    @State private var addMode: AddMode = .url
    @State private var showHints: Bool = false
    @StateObject private var editorController: CodeMirrorEditorController
    @FocusState private var urlFieldFocused: Bool
    @FocusState private var textInputFocused: Bool

    init(userScriptManager: UserScriptManager, onScriptAdded: @escaping () -> Void) {
        self.userScriptManager = userScriptManager
        self.onScriptAdded = onScriptAdded
        _editorController = StateObject(wrappedValue: CodeMirrorEditorController(text: ""))
    }

    private struct StagedScriptFile {
        let filename: String
        let content: String
        let parsed: UserScript
    }

    private enum AddMode: String, CaseIterable, Identifiable, AddContentMode {
        case url = "URL"
        case text = "Text"
        case file = "File"

        var id: String { rawValue }
        var localizedTitle: LocalizedStringKey { LocalizedStringKey(rawValue) }
        var systemImage: String {
            switch self {
            case .url: return "link"
            case .text: return "text.alignleft"
            case .file: return "doc"
            }
        }
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
        .onChangeCompat(of: addMode) { _, newValue in
            urlFieldFocused = newValue == .url
            if newValue == .text {
                scheduleEditorMetadataRefresh()
            }
        }
        #endif
        .onChangeCompat(of: urlInput) { _, newValue in
            validateInput(newValue)
        }
        .onChangeCompat(of: textInput) { _, _ in
            guard addMode == .text else { return }
            scheduleEditorMetadataRefresh()
        }
        .onChangeCompat(of: editorController.documentRevision) { _, _ in
            syncTextFromEditor()
        }
        .onChangeCompat(of: stagedName) { _, newValue in
            guard addMode == .text else { return }
            editorMetadataState.noteNameEdit(newValue)
        }
        .onChangeCompat(of: stagedDescription) { _, newValue in
            guard addMode == .text else { return }
            editorMetadataState.noteDescriptionEdit(newValue)
        }
        .onDisappear {
            editorMetadataRefreshTask?.cancel()
        }
        .alert("Replace Existing Content?", isPresented: $showingPasteReplacementConfirmation) {
            Button("Cancel", role: .cancel) { pendingPasteText = nil }
            Button("Replace", role: .destructive) {
                if let pendingPasteText {
                    replaceEditorText(with: pendingPasteText)
                }
                pendingPasteText = nil
            }
        } message: {
            Text("Pasting will replace the existing content.")
        }
        .sheet(isPresented: $isShowingEditor) {
            AddUserScriptEditorSheet(
                editorController: editorController,
                onTextChanged: applyEditorText,
                onPaste: pasteScriptFromClipboard
            )
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: allowedImportTypes) { result in
            switch result {
            case .success(let url):
                stageFile(at: url)
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled {
                    fileImportError = error.localizedDescription
                }
            }
        }
    }

    #if os(iOS)
    private var iosBody: some View {
        CompatibleNavigationStack {
            addTabs
                .navigationTitle("Add Userscript or Userstyle")
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
                                Text("Add")
                            }
                        }
                        .disabled(!canSubmit || isAdding)
                    }
                }
        }
        .largeSheetPresentationCompat()
    }

    private var addTabs: some View {
        TabView(selection: $addMode) {
            urlTab
                .tag(AddMode.url)
                .tabItem { Label("URL", systemImage: "link") }

            textTab
                .tag(AddMode.text)
                .tabItem { Label("Text", systemImage: "text.alignleft") }

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
                            .foregroundColor(.secondary)
                    ) {
                        Text("Script or Style URL")
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
                Button(action: openEditorSheet) {
                    Label("Use Editor", systemImage: "curlybraces")
                }
            }

            Section {
                requirementsPanel
            }
        }
    }

    private var textTab: some View {
        ScrollView {
            simpleTextContent
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
        .task {
            scheduleEditorMetadataRefresh()
        }
    }

    private var fileTab: some View {
        Form {
            Section {
                fileSelectionButton
                if let stagedFile {
                    TextField("Name", text: $stagedName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    TextField("Description", text: $stagedDescription)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled()
                    userScriptCategoryPicker
                }
            } footer: {
                fileImportMessage
            }

            Section {
                fileRequirementsPanel
            }
        }
    }

    private var fileSelectionButton: some View {
        Button {
            showingFileImporter = true
            fileImportError = nil
        } label: {
            HStack {
                Image(systemName: "doc")
                Text(stagedFile?.filename ?? "Choose File")
                if isStagingFile { ProgressView().controlSize(.small) }
                Spacer()
                if stagedFile != nil {
                    Text("Change File").foregroundStyle(.secondary)
                }
            }
        }
        .disabled(isAdding)
    }
    #endif

    private var simpleTextContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $textInput)
                .font(.body)
                .autocorrectionDisabled()
                .focused($textInputFocused)
                .frame(minHeight: 260, idealHeight: 320, maxHeight: 500)
                .padding(8)
                .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                )
                .accessibilityLabel(Text("Script Content"))

            HStack(spacing: 10) {
                Button(action: pasteScriptFromClipboard) {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .disabled(isAdding)

                Button(action: openEditorSheet) {
                    Label("Use Editor", systemImage: "curlybraces")
                }
                .disabled(isAdding)

                Spacer()
            }
            .buttonStyle(.bordered)

            editorRequirementsPanel
            userScriptMetaFields
        }
    }

    #if os(macOS)
    private var macosBody: some View {
        SheetContainer {
            SheetHeader(title: "Add Userscript or Userstyle", isLoading: isAdding) {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    modePickerCard
                    macosModeContent
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
        AddContentModePicker(selection: $addMode)
    }

    @ViewBuilder
    private var macosModeContent: some View {
        switch addMode {
        case .url:
            VStack(alignment: .leading, spacing: 12) {
                macosURLCard
                validationMessage
                requirementsPanel
            }
        case .text:
            macosTextCard
        case .file:
            macosFileCard
        }
    }

    private var macosURLCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Script or Style URL")
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

            Button(action: openEditorSheet) {
                Label("Use Editor", systemImage: "curlybraces")
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .liquidGlassCompat(cornerRadius: 16, material: .regularMaterial)
    }

    private var macosTextCard: some View {
        simpleTextContent
            .padding(16)
            .liquidGlassCompat(cornerRadius: 16, material: .regularMaterial)
    }

    private var macosFileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Import File")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Local imports won't auto-update; re-import to replace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            fileSelectionButton
            if stagedFile != nil {
                userScriptMetaFields
            }
            fileRequirementsPanel
            if let fileImportError {
                Text(fileImportError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .liquidGlassCompat(cornerRadius: 16, material: .regularMaterial)
    }

    private var fileSelectionButton: some View {
        Button {
            showingFileImporter = true
            fileImportError = nil
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc")
                Text(stagedFile?.filename ?? "Choose File")
                if isStagingFile { ProgressView().controlSize(.small) }
                Spacer()
                if stagedFile != nil {
                    Text("Change File").foregroundStyle(.secondary)
                }
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
    }
    #endif

    private var metadataRequirementText: LocalizedStringKey {
        "Include the // ==UserScript== metadata block (or /* ==UserStyle== */ for userstyles) so wBlock can read the name and URL patterns."
    }

    private var requirementsPanel: some View {
        AddContentRequirementsPanel(requirements: [
            AddContentRequirement(systemImage: "link", text: "Starts with http:// or https://"),
            AddContentRequirement(systemImage: "doc.text", text: "Ends with .js, .user.js, or .user.css"),
            AddContentRequirement(systemImage: "checkmark.shield", text: "Hosted on a trusted source"),
            AddContentRequirement(systemImage: "doc.badge.gearshape", text: metadataRequirementText)
        ])
    }

    private var editorRequirementsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            AddContentRequirementsPanel(requirements: [
                AddContentRequirement(systemImage: "doc.badge.gearshape", text: metadataRequirementText)
            ])
            if let editorImportError {
                Text(editorImportError)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var userScriptCategoryPicker: some View {
        Picker("Category", selection: $selectedCategory) {
            ForEach(FilterListCategory.userScriptCategories) { category in
                Text(category.localizedName).tag(category)
            }
        }
        .pickerStyle(.menu)
    }

    private var userScriptMetaFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Name", text: $stagedName)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            TextField("Description", text: $stagedDescription)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            userScriptCategoryPicker
        }
    }

    private var fileImportMessage: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Local imports won't auto-update; re-import to replace.")
                .foregroundStyle(.secondary)
            if let fileImportError {
                Text(fileImportError)
                    .foregroundStyle(.orange)
            }
        }
        .font(.footnote)
    }

    private var fileRequirementsPanel: some View {
        AddContentRequirementsPanel(requirements: [
            AddContentRequirement(systemImage: "doc.badge.gearshape", text: metadataRequirementText)
        ])
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
        .accessibilityLabel("Paste")
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
        VStack(alignment: .leading, spacing: 4) {
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

            if let urlImportError {
                Text(urlImportError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: validationState)
    }


    private var addButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if isAdding {
                    ProgressView()
                        .scaleEffect(0.9)
                }
                Text(LocalizedStringKey(isAdding ? "Adding…" : "Add"))
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
        case .text:
            return !textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .file:
            return !isStagingFile
                && stagedFile != nil
                && !stagedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func submit() {
        switch addMode {
        case .url:
            guard case .valid(let url) = validationState else { return }

            isAdding = true
            urlImportError = nil

            Task(priority: .userInitiated) {
                await ConcurrentLogManager.shared.info(.userScript, LocalizedStrings.text("Adding new userscript from URL"), metadata: ["url": url.absoluteString])
                let error = await userScriptManager.addUserScript(from: url)

                if let error {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    await ConcurrentLogManager.shared.error(.userScript, LocalizedStrings.text("Failed to add userscript from URL"), metadata: ["url": url.absoluteString, "error": message])

                    await MainActor.run {
                        urlImportError = message
                        isAdding = false
                    }
                } else {
                    await ConcurrentLogManager.shared.info(.userScript, LocalizedStrings.text("Successfully added userscript from URL"), metadata: ["url": url.absoluteString])

                    await MainActor.run {
                        isAdding = false
                        onScriptAdded()
                        dismiss()
                    }
                }
            }
        case .text:
            addScriptFromText()
        case .file:
            guard let stagedFile else { return }
            isAdding = true
            fileImportError = nil
            Task(priority: .userInitiated) {
                let error = await userScriptManager.addUserScript(
                    fromStagedImport: stagedFile.parsed,
                    nameOverride: stagedName,
                    descriptionOverride: stagedDescription,
                    category: selectedCategory
                )
                if let error {
                    await MainActor.run {
                        fileImportError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        isAdding = false
                    }
                } else {
                    await MainActor.run {
                        isAdding = false
                        onScriptAdded()
                        dismiss()
                    }
                }
            }
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

        // Userstyles (.user.css / .css)
        types.append(UTType(filenameExtension: "css") ?? .plainText)

        let userCssTypes = UTType.types(tag: "user.css", tagClass: .filenameExtension, conformingTo: nil)
        if !userCssTypes.isEmpty {
            types.append(contentsOf: userCssTypes)
        } else if let userCssExt = UTType(filenameExtension: "user.css", conformingTo: .data) {
            types.append(userCssExt)
        }

        return types
    }

    private func addScriptFromText() {
        isAdding = true
        editorImportError = nil

        Task(priority: .userInitiated) {
            let content = textInput
            let metadata = editorMetadataOverrides(for: content)
            let error = await userScriptManager.addUserScript(
                fromSourceContent: content,
                nameOverride: metadata.name,
                descriptionOverride: metadata.description,
                category: selectedCategory
            )

            if let error {
                await MainActor.run {
                    editorImportError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isAdding = false
                }
            } else {
                await ConcurrentLogManager.shared.info(.userScript, LocalizedStrings.text("Added userscript from editor"))

                await MainActor.run {
                    isAdding = false
                    onScriptAdded()
                    dismiss()
                }
            }
        }
    }

    private func stageFile(at url: URL) {
        stagingGeneration += 1
        let generation = stagingGeneration
        isStagingFile = true
        fileImportError = nil
        let didAccess = url.startAccessingSecurityScopedResource()

        Task { @MainActor in
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let parsed = try await Task.detached(priority: .userInitiated) {
                    try UserScriptManager.stageUserScriptImport(fromLocalFile: url)
                }.value

                guard generation == stagingGeneration else { return }
                stagedFile = StagedScriptFile(
                    filename: url.lastPathComponent,
                    content: parsed.content,
                    parsed: parsed
                )
                let metadataName = parsed.name.trimmingCharacters(in: .whitespacesAndNewlines)
                stagedName = metadataName.isEmpty
                    ? UserScriptURLSupport.displayName(forFilename: url.lastPathComponent)
                    : metadataName
                stagedDescription = parsed.description.trimmingCharacters(in: .whitespacesAndNewlines)
                selectedCategory = .scripts
                isStagingFile = false
            } catch {
                guard generation == stagingGeneration else { return }
                isStagingFile = false
                fileImportError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func scheduleEditorMetadataRefresh() {
        editorMetadataRefreshTask?.cancel()
        metadataRefreshGeneration &+= 1
        let generation = metadataRefreshGeneration
        let editorRevision = editorController.documentRevision
        let readsEditor = isShowingEditor
        editorMetadataRefreshTask = Task { @MainActor in
            // CodeMirror can emit one revision per keystroke. Debounce the scan and
            // parse only the metadata-sized prefix, never the whole source document.
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled,
                  generation == metadataRefreshGeneration,
                  addMode == .text
            else { return }

            let content: String
            if readsEditor {
                guard editorController.documentRevision == editorRevision else { return }
                content = await editorController.currentText()
                guard !Task.isCancelled,
                      generation == metadataRefreshGeneration,
                      editorController.documentRevision == editorRevision
                else { return }
            } else {
                content = textInput
                guard content == textInput else { return }
            }

            guard generation == metadataRefreshGeneration else { return }
            _ = editorMetadataOverrides(for: content)
        }
    }

    private func editorMetadataOverrides(for content: String) -> (name: String, description: String) {
        let boundedContent = content
            .components(separatedBy: .newlines)
            .prefix(120)
            .joined(separator: "\n")
            .prefix(16_000)
        var parsed = UserScript(
            name: UserScriptURLSupport.displayName(forFilename: "Pasted Userscript"),
            content: String(boundedContent)
        )
        parsed.parseMetadata()

        let values = editorMetadataState.autofill(
            name: parsed.name,
            description: parsed.description,
            currentName: stagedName,
            currentDescription: stagedDescription
        )
        if stagedName != values.name { stagedName = values.name }
        if stagedDescription != values.description { stagedDescription = values.description }
        return values
    }

    private func validateInput(_ newValue: String) {
        urlImportError = nil
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            validationState = .idle
            return
        }

        guard let url = UserScriptURLSupport.validatedRemoteURL(from: trimmed) else {
            validationState = .invalid("Provide a valid http:// or https:// link ending in .js, .user.js, or .user.css")
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

    private func pasteScriptFromClipboard() {
        #if os(iOS)
        guard let string = UIPasteboard.general.string else { return }
        #elseif os(macOS)
        guard let string = NSPasteboard.general.string(forType: .string) else { return }
        #endif

        Task { @MainActor in
            let currentText = isShowingEditor ? await editorController.currentText() : textInput
            if currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                replaceEditorText(with: string)
            } else {
                pendingPasteText = string
                showingPasteReplacementConfirmation = true
            }
        }
    }

    private func replaceEditorText(with string: String) {
        editorImportError = nil
        textInput = string
        editorController.replaceText(string, markClean: true)
        scheduleEditorMetadataRefresh()
        DispatchQueue.main.async {
            if isShowingEditor {
                editorController.focus()
            } else {
                textInputFocused = true
            }
        }
    }

    private func openEditorSheet() {
        addMode = .text
        editorController.replaceText(textInput, markClean: true)
        isShowingEditor = true
    }

    private func applyEditorText(_ text: String) {
        textInput = text
        editorController.replaceText(text, markClean: true)
        scheduleEditorMetadataRefresh()
    }

    private func syncTextFromEditor() {
        guard isShowingEditor else { return }
        Task { @MainActor in
            let text = await editorController.currentText()
            guard text != textInput else { return }
            textInput = text
            scheduleEditorMetadataRefresh()
        }
    }

    private enum ValidationState: Equatable {
        case idle
        case invalid(String)
        case valid(URL)
    }
}
