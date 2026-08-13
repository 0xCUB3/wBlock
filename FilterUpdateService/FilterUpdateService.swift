//
//  FilterUpdateService.swift
//  FilterUpdateService
//
//  Created by Alexander Skula on 9/11/25.
//

import Foundation
import wBlockCoreService

/// This object implements the protocol which we have defined. It provides the actual behavior for the service. It is 'exported' by the service to make it available to the process hosting the service over an NSXPCConnection.
class FilterUpdateService: NSObject, FilterUpdateProtocol {
    func updateFilters(_ reply: @escaping (Bool) -> Void) {
        Task {
            let outcome = await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "XPCService")
            reply(outcome.isSuccessfulForBackgroundTask)
        }
    }

    func startFilterUpdate(_ reply: @escaping (Bool) -> Void) {
        guard FilterUpdatePopupStatus.beginIfIdle() else {
            reply(false)
            return
        }

        // Acknowledge after claiming the shared status, then keep the existing
        // updater alive in the background. No containing-app activation occurs.
        reply(true)
        Task {
            let outcome = await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(
                trigger: "XPCService",
                force: true
            )
            FilterUpdatePopupStatus.finish(outcome)
        }
    }
}
