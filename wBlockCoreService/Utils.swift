//
//  Utils.swift
//  safari-blocker
//
//  Created by Andrey Meshkov on 29/01/2025.
//

import Dispatch
import Foundation

func measure<T>(label: String, block: () -> T) -> T {
    let start = DispatchTime.now()  // Start the timer

    let result = block()  // Execute the code block

    let end = DispatchTime.now()  // End the timer
    let elapsedNanoseconds = end.uptimeNanoseconds - start.uptimeNanoseconds
    let elapsedMilliseconds = Double(elapsedNanoseconds) / 1_000_000  // Convert to milliseconds

    // Pretty print elapsed time
    let formattedTime = String(format: "%.3f", elapsedMilliseconds)
    NSLog("[\(label)] Elapsed Time: \(formattedTime) ms")

    return result
}
