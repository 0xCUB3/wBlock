import CryptoKit
import Foundation
import wBlockCoreService

@main
struct SafariAffinitySnapshotBehaviorTests {
    static func main() throws {
        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: .macOS)
        let generalTarget = targets[0]
        let privacyTarget = targets[1]
        let securityTarget = targets[2]
        let filterID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let source = """
        ||default.example^
        !#safari_cb_affinity(general,privacy)
        @@||shared.example^
        !#safari_cb_affinity
        ||after.example^
        !#safari_cb_affinity(security)
        ||security.example^
        !#safari_cb_affinity
        """
        let snapshot = SafariContentBlockerAffinitySnapshot(contentsByFilterID: [filterID: source])
        let filter = FilterList(
            id: filterID,
            name: "fixture",
            url: URL(string: "https://example.com/fixture.txt")!,
            category: .ads
        )

        let expectedGeneral = "||default.example^\n@@||shared.example^\n||after.example^"
        let expectedPrivacy = "@@||shared.example^"
        let expectedSecurity = "||security.example^"
        expect(
            SafariContentBlockerAffinityProcessor.filteredContent(
                from: source,
                includeBaseRules: true,
                target: generalTarget,
                allTargets: targets
            ) == expectedGeneral,
            "grouper output ordering changed for the default target"
        )
        expect(
            SafariContentBlockerAffinityProcessor.filteredContent(
                from: source,
                includeBaseRules: false,
                target: privacyTarget,
                allTargets: targets
            ) == expectedPrivacy,
            "grouper output changed for an affinity-only target"
        )
        expect(
            SafariContentBlockerAffinityProcessor.filteredContent(
                from: source,
                includeBaseRules: false,
                target: securityTarget,
                allTargets: targets
            ) == expectedSecurity,
            "grouper output changed for a cross-target affinity contribution"
        )

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let handle = try FileHandle(forWritingTo: tempURL)
        var hasher = SHA256()
        let wrote = try SafariContentBlockerAffinityProcessor.appendAffinityFilteredContribution(
            for: filter,
            includeBaseRules: false,
            target: securityTarget,
            allTargets: targets,
            affinitySnapshot: snapshot,
            destinationHandle: handle,
            hasher: &hasher,
            newlineData: Data("\n".utf8)
        )
        try handle.close()
        let appended = try String(contentsOf: tempURL, encoding: .utf8)
        expect(wrote, "snapshot contribution should be written")
        expect(appended == expectedSecurity + "\n", "snapshot contribution differs from filtered output")

        print("PASS")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
