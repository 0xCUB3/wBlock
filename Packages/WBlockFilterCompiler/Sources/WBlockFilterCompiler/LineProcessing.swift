import Foundation

struct SourceLine: Sendable, Equatable {
    var sourceIdentifier: String
    var sourceDisplayName: String
    var number: Int
    var text: String
}

enum LineReader {
    static func read(source: FilterSource) -> [SourceLine] {
        let normalized = source.text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let rawLines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return foldContinuations(
            rawLines.enumerated().map {
                SourceLine(
                    sourceIdentifier: source.identifier,
                    sourceDisplayName: source.displayName,
                    number: $0.offset + 1,
                    text: $0.element
                )
            }
        )
    }

    private static func foldContinuations(_ lines: [SourceLine]) -> [SourceLine] {
        var result: [SourceLine] = []
        var index = 0

        while index < lines.count {
            var current = lines[index]
            var nextIndex = index + 1

            while current.text.hasSuffix(" \\") && nextIndex < lines.count {
                let next = lines[nextIndex]
                guard next.text.first?.isWhitespace == true else { break }
                current.text.removeLast(2)
                current.text += next.text.trimmingCharacters(in: .whitespaces)
                nextIndex += 1
            }

            result.append(current)
            index = nextIndex
        }

        return result
    }
}
