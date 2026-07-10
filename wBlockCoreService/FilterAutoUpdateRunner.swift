import Foundation
import os.log

public enum FilterAutoUpdateRunner {
    public static func run(trigger: String, timeout: TimeInterval = 180) async -> Bool {
        let logger = Logger(subsystem: "wBlockCoreService", category: "FilterAutoUpdateRunner")
        #if os(macOS)
        switch await FilterUpdateClient.shared.updateFilters(timeout: timeout) {
        case .succeeded:
            return true
        case .timedOut:
            logger.error("XPC update timed out; skipping fallback to avoid overlapping the remote update")
            return false
        case .unavailable:
            logger.info("XPC update unavailable, running shared auto-update fallback for trigger=\(trigger, privacy: .public)")
        }
        #else
        logger.info("Running shared auto-update for trigger=\(trigger, privacy: .public)")
        #endif
        let outcome = await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: trigger)
        return outcome.isSuccessfulForBackgroundTask
    }
}
