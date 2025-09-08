//
//  WhitelistView.swift
//  wBlock
//
//  Created by Alexander Skula on 7/17/25.
//


import SwiftUI
import wBlockCoreService

struct WhitelistView: View {
    @ObservedObject var viewModel: WhitelistViewModel
    @State private var newDomain: String = ""
    @State private var showingAlert = false
    @State private var alertMessage: String = ""

    var body: some View {
        VStack {
            Text("Whitelisted Domains")
                .font(.title2)
                .padding(.top)

            List {
                ForEach(viewModel.whitelistedDomains, id: \.self) { domain in
                    HStack {
                        Text(domain)
                        Spacer()
                        Button(action: {
                            viewModel.removeDomain(domain)
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                    }
                }
            }

            HStack {
                TextField("Enter Domain", text: $newDomain)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addDomain()
                    }

                Button(action: {
                    addDomain()
                }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                }
                .disabled(newDomain.isEmpty)
            }
            .padding()
        }
        .onAppear {
            viewModel.loadWhitelistedDomains()
        }
        .alert(isPresented: $showingAlert) {
            Alert(
                title: Text("Error"),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    private func addDomain() {
        let result = viewModel.addDomain(newDomain)
        switch result {
        case .success:
            newDomain = ""
        case .failure(let error):
            alertMessage = error.localizedDescription
            showingAlert = true
        }
    }
}

class WhitelistViewModel: ObservableObject {
    @Published var whitelistedDomains: [String] = []

    func loadWhitelistedDomains() {
        Task { @MainActor in
            whitelistedDomains = ProtobufDataManager.shared.getWhitelistedDomains()
        }
    }

    func addDomain(_ domain: String) -> Result<Void, Error> {
        guard !domain.isEmpty else { return .failure(WhitelistError.emptyDomain) }
        guard isValidDomain(domain) else {
            return .failure(WhitelistError.invalidDomain)
        }
        if !whitelistedDomains.contains(domain) {
            let updated = whitelistedDomains + [domain]
            whitelistedDomains = updated
            Task { @MainActor in
                await ProtobufDataManager.shared.setWhitelistedDomains(updated)
            }
        }
        return .success(())
    }
    
    func removeDomain(_ domain: String) {
        let updated = whitelistedDomains.filter { $0 != domain }
        whitelistedDomains = updated
        Task { @MainActor in
            await ProtobufDataManager.shared.setWhitelistedDomains(updated)
        }
    }
}

enum WhitelistError: LocalizedError {
    case emptyDomain
    case invalidDomain

    var errorDescription: String? {
        switch self {
        case .emptyDomain:
            return "Domain cannot be empty."
        case .invalidDomain:
            return "Invalid domain format."
        }
    }
}

extension WhitelistViewModel {
    private func isValidDomain(_ domain: String) -> Bool {
        // Enhanced check for domain format
        let domainRegex = #"^(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$"#
        return domain.range(of: domainRegex, options: .regularExpression) != nil
    }
}

