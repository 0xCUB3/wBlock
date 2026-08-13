import Foundation
import wBlockCoreService

@main
struct Issue508OversizedImportTests {
    static func main() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-issue-508-oversized.user.js")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data(repeating: 0x20, count: UserScriptImportLimits.maximumSourceFileBytes + 1)
        try data.write(to: url)

        do {
            _ = try UserScriptManager.stageUserScriptImport(fromLocalFile: url)
            fatalError("oversized userscript was accepted")
        } catch UserScriptImportError.fileTooLarge {
            print("PASS: oversized userscript rejected before read")
        }
    }
}
