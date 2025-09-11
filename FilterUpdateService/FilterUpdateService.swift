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
            await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "XPCService", force: true)
            reply(true)
        }
    }
}
