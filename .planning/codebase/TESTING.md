# Testing Patterns

**Analysis Date:** 2026-02-17

## Test Framework

**Runner:** None configured via XCTest or Swift Testing.

The Xcode scheme (`wBlock.xcodeproj/xcshareddata/xcschemes/wBlock.xcscheme`) has `shouldAutocreateTestPlan = "YES"` and `buildForTesting = "YES"` set, but no test targets are linked and no XCTest files exist in the project. The test action section is empty.

**Integration test runner (manual/CI):**
- Shell script: `scripts/run_filter_update_integration_tests.sh`
- Test binary: compiled via `swiftc` from `scripts/test_filter_update_http.swift`
- Mock server: `scripts/mock_filter_server.py` (Python 3, HTTP)

**Run Commands:**
```bash
# Run the one existing integration test suite
./scripts/run_filter_update_integration_tests.sh

# With custom port
./scripts/run_filter_update_integration_tests.sh 9999
```

## Test File Organization

**Location:** Tests live in `scripts/`, not co-located with source or in an `*Tests/` folder.

**Naming:**
- Test entry point: `scripts/test_filter_update_http.swift`
- Mock server: `scripts/mock_filter_server.py`
- Runner shell script: `scripts/run_filter_update_integration_tests.sh`

**Structure:**
```
scripts/
├── test_filter_update_http.swift   # Integration test logic
├── mock_filter_server.py           # HTTP mock server
├── run_filter_update_integration_tests.sh  # Orchestrator script
└── .mock_filter_server.log         # Server output (gitignored)
```

## Test Structure

**Suite Organization (integration tests):**
The test script uses a `@main` struct with a single `async` entry point. Assertions use a custom `assertEqual` helper, not XCTest:

```swift
func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws -> Bool {
    if actual != expected {
        throw TestError.failed("\(message) | expected=\(expected) actual=\(actual)")
    }
    return true
}

@main
struct Main {
    static func main() async {
        do {
            // Each test case is a top-level assertion block
            let (data, response) = try await fetch(baseURL.appendingPathComponent("conditional"),
                headers: ["If-None-Match": "\"etag-a\""])
            let status = FilterUpdateResponseClassifier.classify(
                statusCode: response.statusCode, responseData: data, localData: localData)
            try assertEqual(status, .notModified, "Conditional 304 should be notModified")

            // ...more assertions
            print("All filter update HTTP integration checks passed")
            exit(EXIT_SUCCESS)
        } catch {
            fputs("Test failure: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
```

**Patterns:**
- Setup: local reference data defined inline (`let localData = Data(...)`)
- Each scenario: fetch a specific mock endpoint, classify response, assert result
- Teardown: mock server killed via shell `trap` on script exit
- Failure: throws `TestError.failed(message)`, printed to stderr, process exits with code 1

## Mocking

**Framework:** Python 3 `http.server` via `scripts/mock_filter_server.py`

**What is mocked:**
- HTTP filter update server with fixed endpoints
- `/conditional` → returns `304 Not Modified` when `If-None-Match` header matches
- `/same-content-new-etag` → returns `200` with same bytes as local data but new ETag
- `/updated-content` → returns `200` with different bytes
- `/html-challenge` → returns `200` with HTML body (simulates Cloudflare challenge page)
- `/server-error` → returns `500`
- `/health` → returns `200` for readiness check

**What is NOT mocked:**
- The `FilterUpdateResponseClassifier` under test runs as real production code compiled from source
- No mock `URLSession` or protocol-based injection in production code

## Fixtures and Factories

**Test Data:**
```swift
// Inline in test_filter_update_http.swift
let localData = Data("! Title: Example\n! Version: 1\n||ads.example^\n".utf8)
```

**Location:** Fixtures are inline in test files, not in a separate directory.

## Coverage

**Requirements:** None enforced. No `.xcov`, Codecov config, or coverage scheme setting exists.

**View Coverage:**
```bash
# No automated coverage reporting configured
```

## Test Types

**Unit Tests:**
- Not present. No XCTest targets, no `@Test` functions, no Swift Testing framework usage.

**Integration Tests:**
- One integration test suite covering `FilterUpdateResponseClassifier` (`wBlockCoreService/FilterUpdateResponseClassifier.swift`)
- Tests the HTTP response classification logic end-to-end with a real HTTP server
- Compiled and run outside Xcode via `swiftc` on the command line

**E2E Tests:**
- Not present. No UI automation (XCUITest), Instruments scripts, or similar tooling.

## Common Patterns

**Custom Assert:**
```swift
@discardableResult
func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws -> Bool {
    if actual != expected {
        throw TestError.failed("\(message) | expected=\(expected) actual=\(actual)")
    }
    return true
}
```

**Custom Error:**
```swift
enum TestError: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self { case .failed(let message): return message }
    }
}
```

**Async fetch helper:**
```swift
func fetch(_ url: URL, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
    var request = URLRequest(url: url)
    for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw TestError.failed("Expected HTTP response for \(url.absoluteString)")
    }
    return (data, http)
}
```

## Adding Tests

There is no existing XCTest target. To add unit tests:

1. Add a new target in Xcode: File > New > Target > Unit Testing Bundle
2. Link `wBlockCoreService.framework` if testing core logic
3. Place test files in a new `wBlockTests/` directory
4. Use Swift Testing (`import Testing`, `@Test`, `#expect`) or XCTest (`import XCTest`, `XCTestCase`)
5. Good candidates for initial unit tests:
   - `FilterUpdateResponseClassifier` (already has integration coverage, easy to unit test)
   - `FilterListMetadataParser` in `wBlockCoreService/Utils.swift`
   - `ContentBlockerIncrementalCache` signature computation in `wBlockCoreService/Utils.swift`
   - `FilterList.flagEmojis` and `FilterList.lastUpdatedFormatted` computed properties

---

*Testing analysis: 2026-02-17*
