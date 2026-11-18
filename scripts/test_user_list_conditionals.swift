import Foundation
import wBlockCoreService

// Pasted rules keep their !#if blocks as typed; the engine gets them resolved.
@main
struct UserListConditionalsTest {
    static func main() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("rules.txt")
        try """
        example.com##.always
        !#if ext_ublock
        example.com##.wblock
        !#else
        example.com#%#//scriptlet('trusted-set-attr', 'path', 'd', 'M0 0')
        !#endif
        """.write(to: file, atomically: true, encoding: .utf8)

        let pasted = FilterList(id: UUID(), name: "Mine", url: URL(string: "wblock://userlist/\(UUID().uuidString)")!, category: .custom, isCustom: true)
        let resolved = pasted.engineInputURL(at: file)
        precondition(resolved != file, "pasted rules with !#if go to the engine resolved")
        let lines = try String(contentsOf: resolved, encoding: .utf8).components(separatedBy: "\n")
        precondition(lines == ["example.com##.always", "example.com##.wblock"], "resolved: \(lines)")
        let typed = try String(contentsOf: file, encoding: .utf8)
        precondition(typed.contains("!#else"), "the typed rules stay as typed")

        let downloaded = FilterList(id: UUID(), name: "List", url: URL(string: "https://example.com/list.txt")!, category: .custom, isCustom: true)
        precondition(downloaded.engineInputURL(at: file) == file, "downloaded lists resolved on download")
        let plain = dir.appendingPathComponent("plain.txt")
        try "example.com##.ad".write(to: plain, atomically: true, encoding: .utf8)
        precondition(pasted.engineInputURL(at: plain) == plain, "rules without !#if are read as they are")
        print("All user list conditional checks passed")
    }
}
