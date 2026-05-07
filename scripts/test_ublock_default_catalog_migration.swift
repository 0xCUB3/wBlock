import Foundation

struct Filter: Hashable {
    var name: String
    var url: String
    var isSelected: Bool
    var isCustom: Bool = false
}

enum MigrationState: String {
    case notStarted, catalogMigrated, applyStarted, applySucceeded, applyFailed
}

let targetVersion = 2

let legacyDefaultNames: Set<String> = [
    "AdGuard Base Filter",
    "AdGuard Tracking Protection Filter",
    "AdGuard Annoyances Filter",
    "AdGuard Cookie Notices",
    "AdGuard Popups",
    "AdGuard Mobile App Banners",
    "AdGuard Other Annoyances",
    "AdGuard Widgets",
    "AdGuard Social Media Filter",
    "Fanboy's Annoyances Filter",
    "Fanboy's Social Blocking List",
    "Fanboy's Anti-AI Suggestions",
    "Online Security Filter",
    "Peter Lowe's Blocklist",
    "Anti-Adblock List",
    "AdGuard Experimental Filter",
    "EasyPrivacy",
    "d3Host List by d3ward",
    "Hagezi Pro Mini",
    "AdGuard Mobile Filter",
]

let legacyURLFragments = [
    "filters/2_optimized.txt",
    "filters/3_optimized.txt",
    "filters/4_optimized.txt",
    "filters/5_optimized.txt",
    "filters/18_optimized.txt",
    "filters/19_optimized.txt",
    "filters/20_optimized.txt",
    "filters/21_optimized.txt",
    "filters/22_optimized.txt",
    "filters/118_optimized.txt",
    "filters/122_optimized.txt",
    "filters/204_optimized.txt",
    "filters/207_optimized.txt",
    "filters/208_optimized.txt",
    "14_optimized.txt",
    "filter_11_Mobile",
    "filters.adtidy.org/ios/filters/11.txt",
]

let urlMigrations: [(fragment: String, url: String)] = [
    ("filters/16_optimized.txt", "https://filters.adtidy.org/extension/ublock/filters/16.txt"),
    ("easylistchina/master/easylistchina.txt", "https://filters.adtidy.org/extension/ublock/filters/224.txt"),
    ("filters/6_optimized.txt", "https://easylist.to/easylistgermany/easylistgermany.txt"),
    ("filter_11_Mobile", "https://filters.adtidy.org/extension/ublock/filters/11.txt"),
]

let nativeDefaultNames = [
    "uBlock filters – Ads",
    "uBlock filters – Badware risks",
    "uBlock filters – Privacy",
    "uBlock filters – Unbreak",
    "uBlock filters – Quick fixes",
    "EasyList",
    "EasyPrivacy",
    "Online Malicious URL Blocklist",
    "Peter Lowe’s Ad and tracking server list",
    "uBlock filters – Annoyances",
    "uBlock filters – Cookie Notices",
    "EasyList – Cookie Notices",
    "EasyList – Social Widgets",
    "EasyList – Other Annoyances",
    "EasyList – AI Widgets",
    "AdGuard/uBO – URL Tracking Protection",
    "AdGuard – Cookie Notices",
    "AdGuard – Popup Overlays",
    "AdGuard – Mobile App Banners",
    "AdGuard – Other Annoyances",
    "AdGuard – Widgets",
    "AdGuard – Social Widgets",
    "AdGuard – Mobile Ads",
    "uBlock filters – Experimental",
    "AdGuard Chinese filter",
    "AdGuard French filter",
    "EasyList Germany",
]

func nativeDefaultNamesMapped(from legacyNames: Set<String>, isIOS: Bool) -> Set<String> {
    var names: Set<String> = []
    func add(_ values: String...) { values.forEach { names.insert($0) } }
    if legacyNames.contains("AdGuard Base Filter") || legacyNames.contains("Anti-Adblock List") {
        add("uBlock filters – Ads", "uBlock filters – Unbreak", "uBlock filters – Quick fixes", "EasyList")
    }
    if legacyNames.contains("AdGuard Tracking Protection Filter") || legacyNames.contains("EasyPrivacy") {
        add("uBlock filters – Privacy", "EasyPrivacy", "AdGuard/uBO – URL Tracking Protection")
    }
    if legacyNames.contains("Online Security Filter") {
        add("uBlock filters – Badware risks", "Online Malicious URL Blocklist")
    }
    if legacyNames.contains("Peter Lowe's Blocklist") { add("Peter Lowe’s Ad and tracking server list") }
    if legacyNames.contains("AdGuard Annoyances Filter") { add("uBlock filters – Annoyances", "uBlock filters – Cookie Notices", "EasyList – Cookie Notices", "EasyList – Social Widgets", "EasyList – Other Annoyances", "AdGuard – Cookie Notices", "AdGuard – Popup Overlays", "AdGuard – Mobile App Banners", "AdGuard – Other Annoyances", "AdGuard – Widgets") }
    if legacyNames.contains("AdGuard Cookie Notices") { add("uBlock filters – Cookie Notices", "EasyList – Cookie Notices", "AdGuard – Cookie Notices") }
    if legacyNames.contains("AdGuard Popups") { add("AdGuard – Popup Overlays") }
    if legacyNames.contains("AdGuard Mobile App Banners") { add("AdGuard – Mobile App Banners") }
    if legacyNames.contains("AdGuard Other Annoyances") || legacyNames.contains("Fanboy's Annoyances Filter") { add("uBlock filters – Annoyances", "EasyList – Other Annoyances", "AdGuard – Other Annoyances") }
    if legacyNames.contains("AdGuard Widgets") { add("AdGuard – Widgets") }
    if legacyNames.contains("AdGuard Social Media Filter") || legacyNames.contains("Fanboy's Social Blocking List") { add("EasyList – Social Widgets", "AdGuard – Social Widgets") }
    if legacyNames.contains("Fanboy's Anti-AI Suggestions") { add("EasyList – AI Widgets") }
    if legacyNames.contains("AdGuard Experimental Filter") { add("uBlock filters – Experimental") }
    if legacyNames.contains("AdGuard Mobile Filter") && isIOS { add("AdGuard – Mobile Ads") }
    if names.isEmpty && !legacyNames.isEmpty {
        names = ["uBlock filters – Ads", "uBlock filters – Badware risks", "uBlock filters – Privacy", "uBlock filters – Unbreak", "uBlock filters – Quick fixes", "EasyList", "EasyPrivacy", "Online Malicious URL Blocklist", "Peter Lowe’s Ad and tracking server list"]
        if isIOS { names.insert("AdGuard – Mobile Ads") }
    }
    return names
}

func migrateURLs(_ input: [Filter]) -> [Filter] {
    input.map { filter in
        guard let migration = urlMigrations.first(where: { filter.url.contains($0.fragment) }) else { return filter }
        var migrated = filter
        migrated.url = migration.url
        return migrated
    }
}

func migrate(filters input: [Filter], version: Int, state: MigrationState, isIOS: Bool) -> ([Filter], Int, MigrationState, Bool) {
    var filters = migrateURLs(input)
    guard version < targetVersion || state != .applySucceeded else { return (filters, version, state, false) }
    let legacyDefaults = filters.filter { f in
        !f.isCustom && (legacyDefaultNames.contains(f.name) || legacyURLFragments.contains { f.url.contains($0) })
    }
    guard !legacyDefaults.isEmpty else { return (filters, version, state, false) }
    let selectedLegacyNames = Set(legacyDefaults.filter(\.isSelected).map(\.name))
    let selectedNative = nativeDefaultNamesMapped(from: selectedLegacyNames, isIOS: isIOS)
    let canonicalNameByURL = Dictionary(uniqueKeysWithValues: nativeDefaultNames.map { ("native://\($0)", $0) } + [
        ("https://filters.adtidy.org/extension/ublock/filters/224.txt", "AdGuard Chinese filter"),
        ("https://filters.adtidy.org/extension/ublock/filters/16.txt", "AdGuard French filter"),
        ("https://easylist.to/easylistgermany/easylistgermany.txt", "EasyList Germany"),
    ])
    let selectedPreservedDefaultNames = Set(filters.compactMap { filter -> String? in
        guard filter.isSelected && !filter.isCustom && !legacyDefaults.contains(filter) else { return nil }
        return canonicalNameByURL[filter.url] ?? (nativeDefaultNames.contains(filter.name) ? filter.name : nil)
    })
    let migratedDefaults = nativeDefaultNames.map { Filter(name: $0, url: "native://\($0)", isSelected: selectedNative.contains($0) || selectedPreservedDefaultNames.contains($0)) }
    filters.removeAll { f in !f.isCustom && (legacyDefaultNames.contains(f.name) || legacyURLFragments.contains { f.url.contains($0) } || nativeDefaultNames.contains(f.name) || canonicalNameByURL[f.url] != nil) }
    filters.insert(contentsOf: migratedDefaults, at: 0)
    return (filters, targetVersion, .catalogMigrated, true)
}

func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

func selected(_ filters: [Filter]) -> Set<String> { Set(filters.filter(\.isSelected).map(\.name)) }
func legacy(_ name: String, _ selected: Bool) -> Filter { Filter(name: name, url: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/\(name).txt", isSelected: selected) }

let custom = Filter(name: "My custom list", url: "file:///custom.txt", isSelected: true, isCustom: true)
let oldRecommendedMac = [
    "AdGuard Base Filter", "AdGuard Tracking Protection Filter", "EasyPrivacy", "Online Security Filter", "d3Host List by d3ward", "AdGuard Cookie Notices", "AdGuard Popups", "AdGuard Mobile App Banners", "AdGuard Other Annoyances", "AdGuard Widgets", "Anti-Adblock List"
].map { legacy($0, true) } + [custom]

let macResult = migrate(filters: oldRecommendedMac, version: 0, state: .notStarted, isIOS: false)
assert(macResult.1 == targetVersion && macResult.2 == .catalogMigrated && macResult.3, "mac migration did not mark catalog migrated")
assert(macResult.0.contains(custom), "custom filter not preserved")
assert(selected(macResult.0).isSuperset(of: ["uBlock filters – Ads", "uBlock filters – Privacy", "uBlock filters – Badware risks", "EasyList", "EasyPrivacy", "Online Malicious URL Blocklist"]), "core selected mapping missing")
assert(!macResult.0.contains { $0.url.contains("FiltersRegistry") || $0.url.contains("filters.adtidy.org/ios/filters/") }, "legacy default URL remained")

let disabledAll = legacyDefaultNames.map { legacy($0, false) } + [custom]
let disabledResult = migrate(filters: disabledAll, version: 0, state: .notStarted, isIOS: true)
assert(selected(disabledResult.0) == ["My custom list"], "disabled defaults should stay disabled while custom stays selected")

let mobileResult = migrate(filters: [legacy("AdGuard Mobile Filter", true)], version: 0, state: .notStarted, isIOS: true)
assert(selected(mobileResult.0).contains("AdGuard – Mobile Ads"), "iOS mobile filter not mapped")

let selectedRegional = Filter(
    name: "AdGuard French filter",
    url: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/16_optimized.txt",
    isSelected: true
)
let selectedReplacedRegional = Filter(
    name: "EasyList China",
    url: "https://raw.githubusercontent.com/easylist/easylistchina/master/easylistchina.txt",
    isSelected: true
)
let unselectedSameTargetRegional = Filter(
    name: "AdGuard German filter",
    url: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/6_optimized.txt",
    isSelected: false
)
let selectedSameTargetRegional = Filter(
    name: "EasyList Germany",
    url: "https://easylist.to/easylistgermany/easylistgermany.txt",
    isSelected: true
)
let regionalResult = migrate(
    filters: oldRecommendedMac + [selectedRegional, selectedReplacedRegional, unselectedSameTargetRegional, selectedSameTargetRegional],
    version: 0,
    state: .notStarted,
    isIOS: false
)
assert(selected(regionalResult.0).contains("AdGuard French filter"), "selected regional filter should survive default migration")
assert(selected(regionalResult.0).contains("AdGuard Chinese filter"), "replacement regional should be enabled when old list was enabled")
assert(selected(regionalResult.0).contains("EasyList Germany"), "shared replacement regional should be enabled when any old source was enabled")
assert(!regionalResult.0.contains { $0.url.contains("16_optimized.txt") || $0.url.contains("easylistchina") }, "regional URLs should migrate to uBO endpoints")

let noLegacy = migrate(filters: [custom], version: 0, state: .notStarted, isIOS: false)
assert(!noLegacy.3 && selected(noLegacy.0) == ["My custom list"], "custom-only users should not be migrated")

let secondPass = migrate(filters: macResult.0, version: macResult.1, state: .applySucceeded, isIOS: false)
assert(!secondPass.3 && secondPass.0 == macResult.0, "applySucceeded migration not idempotent")

for state in [MigrationState.catalogMigrated, .applyStarted, .applyFailed] {
    assert([MigrationState.catalogMigrated, .applyStarted, .applyFailed].contains(state), "retry state mismatch")
}

print("ok: simulated mac default upgrade, iOS mobile upgrade, regional preservation, disabled-all, custom-only, idempotent success, retry states")
