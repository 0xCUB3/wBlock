import Foundation

/// Compiled url-filters, as a test asks about several URLs of large lists.
nonisolated(unsafe) private var verdictPatterns: [String: NSRegularExpression] = [:]

/// Whether Safari blocks `url`, loaded as `type` on a page of `host`, given
/// the rule lists of every content blocker. Each blocker decides on its own,
/// in rule order, and an exception lifts only its own blocker's blocks; a load
/// is blocked when any blocker blocks it. Covers the triggers wBlock's network
/// rules use: url-filter, resource-type, if/unless-domain and if-top-url.
func safariBlocks(_ url: String, on host: String, type: String = "script", in blockers: [[[String: Any]]]) -> Bool {
    let page = "https://\(host)/"
    func matches(_ pattern: String, _ text: String, caseSensitive: Bool = false) -> Bool {
        let key = "\(caseSensitive)\(pattern)"
        guard let regex = verdictPatterns[key] ?? (try? NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : .caseInsensitive))
        else { return false }
        verdictPatterns[key] = regex
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
    func onSite(_ domains: [String]) -> Bool {
        domains.contains { domain in
            let site = domain.hasPrefix("*") ? String(domain.dropFirst()) : domain
            return host == site || host.hasSuffix("." + site)
        }
    }
    return blockers.contains { rules in
        var blocked = false
        for rule in rules {
            let trigger = rule["trigger"] as? [String: Any] ?? [:]
            guard let filter = trigger["url-filter"] as? String,
                  matches(filter, url, caseSensitive: trigger["url-filter-is-case-sensitive"] as? Bool == true)
            else { continue }
            if let types = trigger["resource-type"] as? [String], !types.contains(type) { continue }
            if let only = trigger["if-domain"] as? [String], !onSite(only) { continue }
            if let except = trigger["unless-domain"] as? [String], onSite(except) { continue }
            if let pages = trigger["if-top-url"] as? [String], !pages.contains(where: { matches($0, page) }) { continue }
            switch (rule["action"] as? [String: Any])?["type"] as? String {
            case "block": blocked = true
            case "ignore-previous-rules": blocked = false
            default: break
            }
        }
        return blocked
    }
}
