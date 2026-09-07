import Foundation
import CryptoKit

public enum StableRecordIdentifier {
    public static func uuid(rawValue: String, namespace: String, source: String) -> UUID {
        if let id = UUID(uuidString: rawValue) { return id }
        let key = ["wblock-record-repair", namespace, rawValue, source].joined(separator: "\u{0}")
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
