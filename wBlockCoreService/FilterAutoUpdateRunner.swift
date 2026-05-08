import Foundation
import os.log

public enum FilterAutoUpdateRunner {
    public static func run(trigger: String, timeout _: TimeInterval = 180) async -> Bool {
        let logger = Logger(subsystem: "wBlockCoreService", category: "FilterAutoUpdateRunner")
        logger.info("Running shared auto-update for trigger=\(trigger, privacy: .public)")
        let outcome = await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: trigger)
        return outcome.isSuccessfulForBackgroundTask
    }
}
