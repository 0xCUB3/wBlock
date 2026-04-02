import Foundation
import Darwin
import os.log

let logger = Logger(subsystem: "skula.wBlock.FilterUpdateAgent", category: "AutoUpdate")
let helperURL = Bundle.main.executableURL?.resolvingSymlinksInPath()
    ?? URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()

guard let appBundleURL = sequence(first: helperURL, next: { url in
    let parent = url.deletingLastPathComponent()
    return parent.path == url.path ? nil : parent
}).first(where: { $0.pathExtension == "app" }) else {
    logger.critical("Could not find app bundle URL from helper path: \(helperURL.path, privacy: .public)")
    exit(EXIT_FAILURE)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
process.arguments = ["-gj", appBundleURL.path, "--args", "--background-filter-update"]

logger.info("Launch agent helper started")

do {
    try process.run()
    process.waitUntilExit()
    logger.info("Launch agent helper finished with status \(process.terminationStatus, privacy: .public)")
    exit(process.terminationStatus)
} catch {
    logger.error("Launch agent helper failed to launch wBlock: \(error.localizedDescription, privacy: .public)")
    exit(EXIT_FAILURE)
}
