import Foundation

public enum SafariContentBlockerJSONValidator {
    public static func ruleCount(in json: String) throws -> Int {
        let data = Data(json.utf8)
        let rules = try JSONDecoder().decode([ValidationRule].self, from: data)
        return rules.count
    }

    public static func validate(_ json: String, expectedRuleCount: Int? = nil) throws {
        let count = try ruleCount(in: json)
        if let expectedRuleCount, count != expectedRuleCount {
            throw ValidationError.ruleCountMismatch(expected: expectedRuleCount, actual: count)
        }
    }

    public enum ValidationError: Error, Equatable {
        case ruleCountMismatch(expected: Int, actual: Int)
    }
}

private struct ValidationRule: Decodable {
    let action: ValidationAction
    let trigger: ValidationTrigger
}

private struct ValidationAction: Decodable {
    let type: String
    let selector: String?
}

private struct ValidationTrigger: Decodable {
    let urlFilter: String

    enum CodingKeys: String, CodingKey {
        case urlFilter = "url-filter"
    }
}
