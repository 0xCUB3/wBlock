import Foundation
import wBlockCoreService

class WhitelistViewModel: ObservableObject {
    @Published var whitelistedDomains: [String] = []
    private let userDefaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? UserDefaults.standard
    private let disabledSitesKey = "disabledSites"

    func loadWhitelistedDomains() {
        whitelistedDomains = userDefaults.stringArray(forKey: disabledSitesKey) ?? []
    }

    func addDomain(_ domain: String) -> Result<Void, Error> {
        guard !domain.isEmpty else { return .failure(WhitelistError.emptyDomain) }
        guard isValidDomain(domain) else {
            return .failure(WhitelistError.invalidDomain)
        }
        if !whitelistedDomains.contains(domain) {
            let updated = whitelistedDomains + [domain]
            whitelistedDomains = updated
            userDefaults.set(updated, forKey: disabledSitesKey)
        }
        return .success(())
    }

    func removeDomain(_ domain: String) {
        let updated = whitelistedDomains.filter { $0 != domain }
        whitelistedDomains = updated
        userDefaults.set(updated, forKey: disabledSitesKey)
    }

    private func isValidDomain(_ domain: String) -> Bool {
        let domainRegex = #"^(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$"#
        return domain.range(of: domainRegex, options: .regularExpression) != nil
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
