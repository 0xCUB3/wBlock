import Foundation

enum TestError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

@discardableResult
func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws -> Bool {
    if actual != expected {
        throw TestError.failed("\(message) | expected=\(expected) actual=\(actual)")
    }
    return true
}

func fetch(_ url: URL, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
    var request = URLRequest(url: url)
    for (key, value) in headers {
        request.setValue(value, forHTTPHeaderField: key)
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw TestError.failed("Expected HTTP response for \(url.absoluteString)")
    }
    return (data, http)
}

@main
struct Main {
    static func main() async {
        do {
            let base = CommandLine.arguments.dropFirst().first ?? "http://127.0.0.1:18765"
            guard let baseURL = URL(string: base) else {
                throw TestError.failed("Invalid base URL: \(base)")
            }

            let localData = Data("! Title: Example\n! Version: 1\n||ads.example^\n".utf8)

            let (conditionalData, conditionalResponse) = try await fetch(
                baseURL.appendingPathComponent("conditional"),
                headers: ["If-None-Match": "\"etag-a\""]
            )
            let conditionalStatus = FilterUpdateResponseClassifier.classify(
                statusCode: conditionalResponse.statusCode,
                responseData: conditionalData,
                localData: localData
            )
            try assertEqual(conditionalStatus, .notModified, "Conditional 304 should be notModified")

            let (sameData, sameResponse) = try await fetch(baseURL.appendingPathComponent("same-content-new-etag"))
            let sameStatus = FilterUpdateResponseClassifier.classify(
                statusCode: sameResponse.statusCode,
                responseData: sameData,
                localData: localData
            )
            try assertEqual(sameStatus, .unchangedContent, "Same bytes with changed validators should be unchangedContent")

            let (updatedData, updatedResponse) = try await fetch(baseURL.appendingPathComponent("updated-content"))
            let updatedStatus = FilterUpdateResponseClassifier.classify(
                statusCode: updatedResponse.statusCode,
                responseData: updatedData,
                localData: localData
            )
            try assertEqual(updatedStatus, .updatedContent, "Changed bytes should be updatedContent")

            let (htmlData, htmlResponse) = try await fetch(baseURL.appendingPathComponent("html-challenge"))
            let htmlStatus = FilterUpdateResponseClassifier.classify(
                statusCode: htmlResponse.statusCode,
                responseData: htmlData,
                localData: localData
            )
            try assertEqual(htmlStatus, .invalidContent, "HTML challenge body should be invalidContent")

            let (errorData, errorResponse) = try await fetch(baseURL.appendingPathComponent("server-error"))
            let errorStatus = FilterUpdateResponseClassifier.classify(
                statusCode: errorResponse.statusCode,
                responseData: errorData,
                localData: localData
            )
            try assertEqual(errorStatus, .unexpectedStatus(500), "500 should be unexpectedStatus")

            print("All filter update HTTP integration checks passed")
            exit(EXIT_SUCCESS)
        } catch {
            fputs("Test failure: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
