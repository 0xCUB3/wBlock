import SwiftUI
import wBlockCoreService

/// The cosmetic filtering switch and its independent site scope.
/// Both lists are saved while the mode picks which one applies.
struct CosmeticFilteringSitesView: View {
    @ObservedObject var filterManager: AppFilterManager
    @State private var isEnabled = CosmeticFilteringPreference.isEnabled()
    @State private var sites = CosmeticFilteringPreference.sites()
    @State private var searchText = ""
    /// Every change is kept, as in Site Settings, so several edits can each
    /// be undone (#1096).
    @State private var undoStack: [Change] = []
    @State private var redoStack: [Change] = []

    private struct Snapshot: Equatable {
        var isEnabled: Bool
        var sites: CosmeticFilteringPreference.Sites
    }

    private struct Change {
        let before: Snapshot
        let after: Snapshot
    }

    private var snapshot: Snapshot { Snapshot(isEnabled: isEnabled, sites: sites) }

    var body: some View {
        SettingsPage {
            // Not locked during an apply (#936): the run snapshots this setting
            // and a change made meanwhile stays pending for the next one.
            // Generic Rules shares the box since it only narrows cosmetic
            // filtering (#999).
            SettingsGroup {
                Toggle(isOn: Binding(get: { isEnabled }, set: setEnabled)) {
                    toggleLabel("Cosmetic Filtering", detail: "Hides ad placeholders and other page elements with CSS. Turning this off leaves only network blocking, which uses fewer rules and less CPU.")
                }
                .settingsSwitch()
                if isEnabled {
                    Toggle(isOn: Binding(
                        get: { sites.includesGeneric },
                        set: { update(sites.selectedSites, sites.excludedSites, includesGeneric: $0) }
                    )) {
                        toggleLabel("Generic Rules", detail: "Hides elements on every site with rules that don't name one. Turning this off keeps site-specific hiding and makes pages lighter, especially busy web apps.")
                    }
                    .settingsSwitch()
                }
            }
            if isEnabled {
                SiteScopeEditor(
                    title: "Apply on", onlySelectedSites: sites.onlySelectedSites,
                    selectedSites: sites.selectedSites ?? [],
                    excludedSites: sites.onlySelectedSites ? nil : sites.excludedSites,
                    emptySelectionMessage: "No sites selected, so cosmetic filtering is off.",
                    excludedMessage: "Cosmetic filtering skips these sites. Network blocking still applies.",
                    footer: "Sites include their subdomains. Use * for any top-level domain, as in amazon.*.",
                    query: searchText,
                    updateMode: { update(sites.selectedSites, sites.excludedSites, onlySelectedSites: $0) },
                    updateSelected: { update($0, sites.excludedSites) },
                    updateExcluded: { update(sites.selectedSites, $0) }
                )
            }
        }
        .pageTitle("Cosmetic Filtering")
        .modifier(SitePageToolbar(
            canUndo: !undoStack.isEmpty, canRedo: !redoStack.isEmpty,
            undo: undo, redo: redo, searchText: $searchText
        ))
    }

    private func toggleLabel(_ title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func setEnabled(_ enabled: Bool) {
        commit(Snapshot(isEnabled: enabled, sites: sites))
    }

    private func update(_ selected: [String]?, _ excluded: [String], includesGeneric: Bool? = nil, onlySelectedSites: Bool? = nil) {
        var newSites = CosmeticFilteringPreference.Sites(
            selectedSites: selected, excludedSites: excluded,
            includesGeneric: includesGeneric ?? sites.includesGeneric
        )
        newSites.onlySelectedSites = onlySelectedSites ?? sites.onlySelectedSites
        commit(Snapshot(isEnabled: isEnabled, sites: newSites))
    }

    private func commit(_ next: Snapshot) {
        guard next != snapshot else { return }
        undoStack.append(Change(before: snapshot, after: next))
        redoStack = []
        apply(next)
    }

    private func undo() {
        guard let change = undoStack.popLast() else { return }
        redoStack.append(change)
        apply(change.before)
    }

    private func redo() {
        guard let change = redoStack.popLast() else { return }
        undoStack.append(change)
        apply(change.after)
    }

    private func apply(_ next: Snapshot) {
        if next.isEnabled != isEnabled {
            isEnabled = next.isEnabled
            CosmeticFilteringPreference.setEnabled(next.isEnabled)
        }
        if next.sites != sites {
            sites = next.sites
            CosmeticFilteringPreference.setSites(next.sites)
        }
        filterManager.markNonSelectionChangesPending()
    }
}
