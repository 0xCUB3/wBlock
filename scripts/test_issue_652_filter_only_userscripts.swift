#!/usr/bin/env swift

import Foundation

func read(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

func assertContains(_ haystack: String, _ needle: String, _ message: String) {
    guard haystack.contains(needle) else {
        fputs("FAIL: \(message)\nMissing: \(needle)\n", stderr)
        exit(1)
    }
}

func assertNotContains(_ haystack: String, _ needle: String, _ message: String) {
    guard !haystack.contains(needle) else {
        fputs("FAIL: \(message)\nUnexpected: \(needle)\n", stderr)
        exit(1)
    }
}

let handler = try read("wBlockCoreService/WebExtensionRequestHandler.swift")
let autoUpdate = try read("wBlockCoreService/SharedAutoUpdateManager.swift")
let userScripts = try read("wBlockCoreService/UserScriptManager.swift")
let protobuf = try read("wBlockCoreService/ProtobufDataManager+Extensions.swift")

assertContains(
    handler,
    "let disabledSites = await currentFilterDisabledSites()\n                        let disabled = HostMatcher.isHostDisabled(host: url.host ?? \"\", disabledSites: disabledSites)",
    "Advanced rules must honor filter-only exceptions"
)
assertContains(
    handler,
    "let disabledSites = await currentFilterDisabledSites()\n            let disabled = !host.isEmpty && HostMatcher.isHostDisabled(host: host, disabledSites: disabledSites)",
    "getBlockingState must treat filter-only sites as filter-disabled so cached rules are not replayed"
)
assertContains(
    handler,
    "// Master disable only. Filter-only exceptions must still receive userscripts (issue #652).",
    "getUserScripts must document the master-only gate"
)
assertContains(
    handler,
    "let disabledSites = await currentDisabledSites()\n            if let url = URL(string: urlString) {\n                if HostMatcher.isHostDisabled(host: url.host ?? \"\", disabledSites: disabledSites) {\n                    let response = createResponse(with: userScriptsResponse(userScripts: []))",
    "getUserScripts must skip injection only for the master disable list"
)
assertContains(
    handler,
    "let disabledSites = await currentDisabledSites()\n            if let url = URL(string: urlString),\n               HostMatcher.isHostDisabled(host: url.host ?? \"\", disabledSites: disabledSites)\n            {\n                let response = createResponse(with: [\"userScripts\": []])",
    "Page userscript listings must use the master disable list"
)
assertNotContains(
    userScripts,
    "filterDisabledSites",
    "UserScript matching must not consult the filter-only exception list"
)
assertContains(
    userScripts,
    "let runnableScripts = matchingScripts.filter {\n            !isUserScript($0, disabledOnHost: host)\n        }",
    "Runnable userscripts are gated on per-script host exceptions, not filter-only sites"
)
assertContains(
    autoUpdate,
    "DisabledSitesNormalizer.effectiveFilterDisabledDomains(\n                master: manager.disabledSites,\n                filterOnly: manager.filterDisabledSites\n            )",
    "Background rebuilds must keep filter-only sites unfiltered"
)
assertContains(
    protobuf,
    "UserScriptManager.invalidateDocumentStartExecutionCache()",
    "Master whitelist writes must drop the document-start userscript cache"
)
assertNotContains(
    protobuf,
    "public func setFilterDisabledDomains(_ domains: [String]) async {\n        let normalized = DisabledSitesNormalizer.normalizedDomains(from: domains)\n        await updateDataImmediately { data in\n            data.whitelist.filterDisabledSites = normalized\n            data.whitelist.lastUpdated = Int64(Date().timeIntervalSince1970)\n        }\n        UserScriptManager.invalidateDocumentStartExecutionCache()",
    "Filter-only writes must not flush the userscript execution cache"
)

print("issue 652 filter-only userscripts contract passed")
