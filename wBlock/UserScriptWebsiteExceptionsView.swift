import SwiftUI
import wBlockCoreService

struct UserScriptWebsiteExceptionsView: View {
    let scriptID: UUID
    @ObservedObject var userScriptManager: UserScriptManager
    @ObservedObject private var dataManager = ProtobufDataManager.shared
    @State private var isSaving = false
    @State private var saveFailed = false

    var body: some View {
        let access = dataManager.userScriptSiteAccess(forScriptID: scriptID.uuidString)
        SiteScopeEditor(
            title: "Run on", selectedSites: access.onlySelectedSites ? access.hosts : nil,
            excludedSites: dataManager.getUserScriptDisabledHosts(forScriptID: scriptID.uuidString),
            emptySelectionMessage: "No sites selected. This script will not run.",
            excludedMessage: "This script will not run on excluded sites, even if they are selected.",
            footer: "Sites include their subdomains. The script’s own matching rules still apply. Reload the page after making changes.",
            isSaving: isSaving,
            updateSelected: { hosts in
                save { await userScriptManager.setUserScriptSiteAccess(
                    UserScriptSiteAccess(onlySelectedSites: hosts != nil, hosts: hosts ?? []), for: scriptID
                ) }
            },
            updateExcluded: { hosts in
                save { await dataManager.setUserScriptDisabledHosts(hosts, forScriptID: scriptID.uuidString) }
            }
        )
        .alert("Could not save site settings", isPresented: $saveFailed) {
            Button("OK", role: .cancel) { }
        }
    }

    private func save(_ operation: @escaping () async -> Bool) {
        guard !isSaving else { return }
        isSaving = true
        Task {
            saveFailed = !(await operation())
            isSaving = false
        }
    }
}
