import Foundation

@main
struct StableRecordIdentifierTests {
    static func main() {
        let valid = UUID()
        precondition(StableRecordIdentifier.uuid(rawValue: valid.uuidString.lowercased(), namespace: "filter", source: "anything") == valid)
        for raw in ["", "corrupt", "not-a-uuid", "0000"] {
            let repaired = StableRecordIdentifier.uuid(rawValue: raw, namespace: "filter", source: "https://example.com/a.txt")
            for _ in 0..<100 {
                precondition(StableRecordIdentifier.uuid(rawValue: raw, namespace: "filter", source: "https://example.com/a.txt") == repaired)
            }
            precondition(StableRecordIdentifier.uuid(rawValue: raw, namespace: "script", source: "https://example.com/a.txt") != repaired)
            precondition(StableRecordIdentifier.uuid(rawValue: raw, namespace: "filter", source: "https://example.com/b.txt") != repaired)
            precondition(StableRecordIdentifier.uuid(rawValue: repaired.uuidString, namespace: "filter", source: "changed") == repaired)
        }
        print("PASS: stable record identifiers")
    }
}
