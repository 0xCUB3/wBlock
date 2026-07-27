//
//  LaunchSetup.swift
//  wBlock
//

import Foundation
import wBlockCoreService

/// Centralized, idempotent launch setup: loads protobuf data, runs one-time migrations,
/// waits for the user-script manager, then activates CloudKit observers.
///
/// iOS can cold-launch the app for a `BGAppRefreshTask` or a silent push without ever
/// running the SwiftUI scene's `onAppear`, so setup can't live only on the UI launch path.
/// Both the UI (from `wBlockApp`) and the background entry points (in `AppDelegate`)
/// funnel through here so migrations always apply before a sync reads or writes state.
enum LaunchSetup {
    private static var hasStarted = false

    @MainActor
    static func runIfNeeded() async {
        if hasStarted {
            // Another caller (often the UI path) is running setup; wait for it.
            await CloudSyncManager.shared.waitUntilLaunchSetupComplete()
            return
        }
        hasStarted = true

        let dataManager = ProtobufDataManager.shared
        await dataManager.waitUntilLoaded()
        await dataManager.migrateLegacyFilterURLs()
        await dataManager.migrateMultipurposeToAnnoyances()
        await dataManager.migrateAnnoyancesFilterToSplitFilters()
        await dataManager.migrateMobileFilterToAdsCategory()
        await dataManager.migrateAllowlistsToDedicatedCategory()
        await UserScriptManager.shared.waitUntilReady()

        CloudSyncManager.shared.activateAfterLaunchSetup()
    }
}
