import Foundation
import os.log

/// Migrates data from the plain `group.skula.wBlock` container to the
/// team-prefixed container used by direct distribution builds on macOS Sequoia.
///
/// On Sequoia, non-MAS apps accessing a group container without a team ID
/// prefix trigger repeated "access data from other apps" TCC prompts.
/// Direct distribution builds now use `<TeamID>.group.skula.wBlock` instead.
/// This migrator copies existing data from the old container so users don't
/// lose their filter rules after updating.
public enum GroupContainerMigrator {

    /// Runs the migration if needed. Safe to call multiple times (idempotent).
    public static func migrateIfNeeded() {
        #if os(macOS)
        let currentGroup = GroupIdentifier.shared.value
        let legacyGroup = GroupIdentifier.plainGroupIdentifier

        // Only migrate if we're actually using a different (team-prefixed) group
        guard currentGroup != legacyGroup else { return }

        guard let newContainer = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: currentGroup
        ) else {
            os_log(.error, "GroupContainerMigrator: cannot access new container %@", currentGroup)
            return
        }

        guard let oldContainer = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: legacyGroup
        ) else {
            os_log(.info, "GroupContainerMigrator: no old container to migrate from")
            return
        }

        let migrationMarker = newContainer.appendingPathComponent(".group-migration-done")
        if FileManager.default.fileExists(atPath: migrationMarker.path) {
            return
        }

        os_log(.info, "GroupContainerMigrator: migrating from %@ to %@", oldContainer.path, newContainer.path)

        let fm = FileManager.default
        do {
            let contents = try fm.contentsOfDirectory(
                at: oldContainer,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            for item in contents {
                let dest = newContainer.appendingPathComponent(item.lastPathComponent)
                if fm.fileExists(atPath: dest.path) {
                    continue
                }
                try fm.copyItem(at: item, to: dest)
            }

            os_log(.info, "GroupContainerMigrator: migrated %d items", contents.count)
        } catch {
            os_log(.error, "GroupContainerMigrator: migration failed: %@", error.localizedDescription)
        }

        // Write marker even on partial failure so we don't retry every launch
        fm.createFile(atPath: migrationMarker.path, contents: nil)
        #endif
    }
}
