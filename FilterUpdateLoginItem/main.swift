import Foundation
import Darwin
import os.log
import wBlockCoreService

let logger = Logger(subsystem: "skula.wBlock.FilterUpdateLoginItem", category: "AutoUpdate")

if #available(macOS 13.0, *) {
    logger.info("Legacy login item is not used on macOS 13 or newer")
    exit(EXIT_SUCCESS)
}

Task {
    logger.info("Legacy login item helper started")

    while !Task.isCancelled {
        _ = await FilterAutoUpdateRunner.run(trigger: "LegacyLoginItem", timeout: 180)
        try? await TaskSleep.sleep(for: .seconds(15 * 60))
    }

    exit(EXIT_SUCCESS)
}

dispatchMain()
