import Foundation

extension URL {
    func withSecurityScopedAccess<T>(_ body: (URL) throws -> T) rethrows -> T {
        let didAccess = startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                stopAccessingSecurityScopedResource()
            }
        }
        return try body(self)
    }
}
