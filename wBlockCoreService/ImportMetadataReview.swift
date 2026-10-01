import Foundation

/// Decides which reviewed import metadata the user actually chose. Fields are
/// prefilled with fetched or parsed metadata, so an untouched or unchanged field
/// stays automatic and future refreshes may replace it.
public enum ImportMetadataReview {
    /// Returns the trimmed edit when it differs from the automatic value.
    /// An intentionally cleared field returns an empty string, not nil.
    public static func userProvided(_ edited: String?, automatic: String?) -> String? {
        guard let edited else { return nil }
        let value = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        let automatic = automatic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value == automatic ? nil : value
    }
}
