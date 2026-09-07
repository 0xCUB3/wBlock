import SwiftUI
import wBlockCoreService

struct UserScriptWebsiteExceptionsView: View {
    let scriptID: UUID
    @ObservedObject var userScriptManager: UserScriptManager
    @ObservedObject private var dataManager = ProtobufDataManager.shared
    @State private var input = ""
    @State private var isSaving = false

    private var domains: [String] {
        dataManager.getUserScriptDisabledHosts(forScriptID: scriptID.uuidString)
    }

    private var candidate: String? {
        guard let host = DisabledSitesNormalizer.normalizedDomain(input), !domains.contains(host) else { return nil }
        return host
    }

    private var knownSites: [String] {
        let sites = dataManager.disabledSites + dataManager.filterDisabledSites + dataManager.noAutoplayAllowedSites
            + dataManager.getUserScriptDisabledHosts().values.flatMap { $0 }
        return DisabledSitesNormalizer.normalizedDomains(from: sites).filter { !domains.contains($0) }.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Excluded Sites").font(.callout.weight(.medium))
            Text("This script will not run on these sites. Other scripts still run.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("example.com", text: $input, onCommit: addSite)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                Button(action: addSite) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(candidate == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                        #if os(iOS)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                        #endif
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add")
                .disabled(candidate == nil)
                #if os(macOS)
                if !knownSites.isEmpty {
                    Menu {
                        ForEach(knownSites, id: \.self) { site in
                            Button(site) { setExcluded(site, true) }
                        }
                    } label: {
                        Label("Site Settings", systemImage: "globe").labelStyle(.iconOnly)
                    }
                    .help("Site Settings")
                }
                #endif
            }
            ForEach(domains, id: \.self) { site in
                HStack {
                    Text(verbatim: site).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button { setExcluded(site, false) } label: {
                        Image(systemName: "minus.circle").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove")
                    .accessibilityValue(site)
                }
            }
        }
        .disabled(isSaving)
    }

    private func addSite() {
        guard let candidate else { return }
        setExcluded(candidate, true)
    }

    private func setExcluded(_ site: String, _ excluded: Bool) {
        guard !isSaving else { return }
        isSaving = true
        Task {
            let saved = await userScriptManager.setUserScript(withId: scriptID, disabledOnHost: site, disabled: excluded)
            if saved && excluded { input = "" }
            isSaving = false
        }
    }
}
