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
        FilterUpdateWorkLifetime.start {
            let outcome = await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "XPCService")
            reply(outcome.isSuccessfulForBackgroundTask)
        }
    }

    func startFilterUpdate(_ reply: @escaping (Bool) -> Void) {
        guard let claim = FilterUpdatePopupStatus.beginIfIdle() else {
            reply(false)
            return
        }

        // The service owns an XPC transaction before replying, independent of
        // the client connection. Release only after publishing the final status.
        FilterUpdateWorkLifetime.start(acknowledge: { reply(true) }) {
            let outcome = await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(
                trigger: "XPCService",
                force: true
            )
            FilterUpdatePopupStatus.finish(outcome, claim: claim)
        }
    }
}
