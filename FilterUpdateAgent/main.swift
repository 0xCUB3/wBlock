import Foundation
import Darwin
import os.log
import wBlockCoreService

let logger = Logger(subsystem: "skula.wBlock.FilterUpdateAgent", category: "AutoUpdate")

Task {
    logger.info("Launch agent helper started")
    let success = await FilterUpdateClient.shared.updateFilters(timeout: 180)
    logger.info("Launch agent helper finished with success=\(success, privacy: .public)")
    exit(success ? EXIT_SUCCESS : EXIT_FAILURE)
}

dispatchMain()
