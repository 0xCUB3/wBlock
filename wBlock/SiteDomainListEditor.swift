import SwiftUI
import wBlockCoreService

struct SiteDomainListEditor: View {
    let sites: [String]
    var knownSites: [String] = []
    let onChange: ([String]) -> Void
    @State private var input = ""

    private var candidate: String? {
        guard let domain = DisabledSitesNormalizer.normalizedDomain(input), !sites.contains(domain) else { return nil }
        return domain
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("example.com", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .onSubmit { add() }
                if !knownSites.isEmpty {
                    Menu {
                        ForEach(knownSites.filter { !sites.contains($0) }, id: \.self) { site in
                            Button(site) { onChange(sites + [site]) }
                        }
                    } label: { Image(systemName: "list.bullet") }
                    .accessibilityLabel("Site Settings")
                }
                Button(action: add) { Image(systemName: "plus.circle.fill") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add")
                    .disabled(candidate == nil)
            }
            ForEach(sites, id: \.self) { site in
                HStack {
                    Text(site).textSelection(.enabled)
                    Spacer()
                    Button { onChange(sites.filter { $0 != site }) } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove")
                }
            }
        }
    }

    private func add() {
        guard let candidate else { return }
        onChange(sites + [candidate])
        input = ""
    }

    @MainActor static func knownSites(in manager: ProtobufDataManager) -> [String] {
        let sites = manager.disabledSites + manager.filterDisabledSites + manager.noAutoplayAllowedSites
            + manager.getZapperDomains() + manager.getUserScriptDisabledHosts().values.flatMap { $0 }
        return DisabledSitesNormalizer.normalizedDomains(from: sites).sorted()
    }
}
