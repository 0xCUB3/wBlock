import SwiftUI
import wBlockCoreService

struct UserScriptWebsiteExceptionsView: View {
    let scriptID: UUID
    @ObservedObject var userScriptManager: UserScriptManager
    @ObservedObject private var dataManager = ProtobufDataManager.shared
    @State private var isSaving = false
    @State private var saveFailed = false

    private var access: UserScriptSiteAccess {
        dataManager.userScriptSiteAccess(forScriptID: scriptID.uuidString)
    }

    private var excludedHosts: [String] {
        dataManager.getUserScriptDisabledHosts(forScriptID: scriptID.uuidString)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Run on", selection: Binding(
                get: { access.onlySelectedSites },
                set: { onlySelected in
                    save { await userScriptManager.setUserScriptSiteAccess(
                        UserScriptSiteAccess(onlySelectedSites: onlySelected), for: scriptID
                    ) }
                }
            )) {
                Text("All matching sites").tag(false)
                Text("Only selected sites").tag(true)
            }
            .pickerStyle(.menu)

            if access.onlySelectedSites {
                hostList("Selected Sites", hosts: access.hosts) { hosts in
                    await userScriptManager.setUserScriptSiteAccess(
                        UserScriptSiteAccess(onlySelectedSites: true, hosts: hosts), for: scriptID
                    )
                }
                if access.hosts.isEmpty {
                    Text("No sites selected. This script will not run.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !access.onlySelectedSites || !excludedHosts.isEmpty {
                hostList("Excluded Sites", hosts: excludedHosts) { hosts in
                    await dataManager.setUserScriptDisabledHosts(hosts, forScriptID: scriptID.uuidString)
                }
                Text("This script will not run on excluded sites, even if they are selected.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Sites include their subdomains. The script’s own matching rules still apply. Reload the page after making changes.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .disabled(isSaving)
        .alert("Could not save site settings", isPresented: $saveFailed) {
            Button("OK", role: .cancel) { }
        }
    }

    private func hostList(
        _ title: LocalizedStringKey, hosts: [String], update: @escaping ([String]) async -> Bool
    ) -> some View {
        SiteHostListEditor(title: title, hosts: hosts) { updated in
            save { await update(updated) }
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
