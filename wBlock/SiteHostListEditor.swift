import SwiftUI
import wBlockCoreService

struct SiteHostListEditor: View {
    let title: LocalizedStringKey
    let hosts: [String]
    let update: ([String]) -> Void
    @State private var input = ""

    private var candidate: String? {
        guard let host = DisabledSitesNormalizer.normalizedDomain(input), !hosts.contains(host) else { return nil }
        return host
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.callout.weight(.medium))
            HStack {
                TextField("example.com", text: $input, onCommit: addSite)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                Button(action: addSite) {
                    Image(systemName: "plus.circle.fill").font(.title2)
                        .frame(minWidth: 28, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add")
                .disabled(candidate == nil)
            }
            ForEach(hosts, id: \.self) { site in
                HStack {
                    Text(verbatim: site).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button { update(hosts.filter { $0 != site }) } label: {
                        Image(systemName: "minus.circle").foregroundStyle(.secondary)
                            .frame(minWidth: 28, minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove")
                    .accessibilityValue(site)
                }
            }
        }
    }

    private func addSite() {
        guard let candidate else { return }
        update((hosts + [candidate]).sorted())
        input = ""
    }
}
