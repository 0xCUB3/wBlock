import Foundation

@main
struct Issue574FiltersScrollResetContract {
    static func main() throws {
        let content = try String(contentsOfFile: "wBlock/ContentView.swift", encoding: .utf8)

        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else {
                fputs("FAIL: \(message)\n", stderr)
                exit(1)
            }
        }

        guard let macOSStart = content.range(of: "#else\n        ScrollView {", range: content.range(of: "private var nativeFiltersListView")!.upperBound..<content.endIndex),
              let macOSEnd = content.range(of: "#endif", range: macOSStart.upperBound..<content.endIndex) else {
            fputs("FAIL: macOS native filters ScrollView not found\n", stderr)
            exit(1)
        }
        let macOSList = String(content[macOSStart.lowerBound..<macOSEnd.lowerBound])

        expect(macOSList.contains("ScrollView {"), "macOS filters must remain in a ScrollView")
        expect(macOSList.contains("LazyVStack"), "macOS filters must remain lazily rendered")
        expect(macOSList.contains(".id("), "macOS filters must reset view identity when filtering changes")
        expect(macOSList.contains("showOnlyEnabledLists"), "view identity must include the enabled-only preference")
        expect(macOSList.contains("filterSearchText"), "view identity must include the search query")

        print("PASS: issue #574 macOS filters scroll reset contract")
    }
}
