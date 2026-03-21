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

    /// Runs the migration if needed. Called from GroupIdentifier.init() so it
    /// runs before any other code (ProtobufDataManager, etc.) touches the
    /// group container.
    ///
    /// Takes explicit parameters to avoid accessing GroupIdentifier.shared
    /// (which would be a circular reference since this is called during its init).
    public static func migrateIfNeeded(from legacyGroup: String, to newGroup: String) {
        #if os(macOS)
        let fm = FileManager.default

        guard let newContainer = fm.containerURL(
            forSecurityApplicationGroupIdentifier: newGroup
        ) else {
            os_log(.error, "GroupContainerMigrator: cannot access new container %@", newGroup)
            return
        }

        let migrationMarker = newContainer.appendingPathComponent(".group-migration-done")
        if fm.fileExists(atPath: migrationMarker.path) {
            return
        }

        guard let oldContainer = fm.containerURL(
            forSecurityApplicationGroupIdentifier: legacyGroup
        ) else {
            os_log(.info, "GroupContainerMigrator: no old container to migrate from")
            fm.createFile(atPath: migrationMarker.path, contents: nil)
            return
        }

        os_log(.info, "GroupContainerMigrator: migrating from %@ to %@", oldContainer.path, newContainer.path)

        do {
            let contents = try fm.contentsOfDirectory(
                at: oldContainer,
                includingPropertiesForKeys: nil,
                options: []
            )

            var count = 0
            for item in contents {
                let dest = newContainer.appendingPathComponent(item.lastPathComponent)
                if fm.fileExists(atPath: dest.path) {
                    // Overwrite with old data - the new container may have
                    // empty defaults created during this launch cycle
                    try? fm.removeItem(at: dest)
                }
                try fm.copyItem(at: item, to: dest)
                count += 1
            }

            os_log(.info, "GroupContainerMigrator: migrated %d items", count)
        } catch {
            os_log(.error, "GroupContainerMigrator: migration failed: %@", error.localizedDescription)
        }

        fm.createFile(atPath: migrationMarker.path, contents: nil)
        #endif
    }
}
