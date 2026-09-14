import Foundation
import wBlockCoreService

// Compile with FilterListPresentation.swift, ListDisplayOrder.swift, and LocalizationHelpers.swift,
// plus the LogLevel/LogCategory declarations from ConcurrentLogManager.swift.
// Link wBlockCoreService.framework from the signed Debug products directory.
@main
struct FilterListPresentationTests {
    @MainActor
    static func main() async throws {
        let a = FilterList(name: "Alpha", url: URL(string: "https://example.com/a")!, category: .ads,
                           isSelected: true, description: "Unique description")
        let b = FilterList(name: "Bravo", url: URL(string: "https://example.com/b")!, category: .ads)
        let privacy = FilterList(name: "Privacy", url: URL(string: "https://example.com/privacy")!, category: .privacy)
        let regional = FilterList(name: "Regional", url: URL(string: "https://example.com/regional")!, category: .foreign,
                                  isSelected: true, languages: ["fr", "de"], trustLevel: "high")
        let superseded = FilterList(name: "Old regional", url: URL(string: "https://example.com/old")!, category: .foreign,
                                    description: "Already included in Regional", languages: ["fr"], trustLevel: "full")
        let filters = [a, privacy, b, superseded, regional]
        let order = try JSONEncoder().encode([b.id, a.id])
        func input(_ filters: [FilterList], query: String = "", enabled: Bool = false) -> FilterListPresentation.Input {
            .init(filters: filters, order: order, searchText: query, enabledOnly: enabled, localeIdentifier: "en")
        }
        func ids(_ presentation: FilterListPresentation) -> [UUID] {
            presentation.sections.flatMap(\.filters).map(\.id)
        }

        let all = try await FilterListPresentation.prepare(input(filters))
        precondition(all.sections.first { $0.category == .ads }!.filters.map(\.id) == [b.id, a.id])
        precondition(all.sections.first { $0.category == .foreign }!.filters.map(\.id) == [regional.id, superseded.id])
        precondition(all.foreignGroups.first { $0.languageCode == "fr" }!.filters.map(\.id) == [regional.id, superseded.id])
        precondition(all.foreignGroups.first { $0.languageCode == "de" }!.filters.map(\.id) == [regional.id])

        let enabled = try await FilterListPresentation.prepare(input(filters, enabled: true))
        precondition(Set(ids(enabled)) == [a.id, regional.id])
        let descriptionSearch = try await FilterListPresentation.prepare(input(filters, query: "  UNIQUE DESCRIPTION \n"))
        precondition(ids(descriptionSearch) == [a.id])
        let urlSearch = try await FilterListPresentation.prepare(input(filters, query: "EXAMPLE.COM/B"))
        precondition(ids(urlSearch) == [b.id])
        let empty = try await FilterListPresentation.prepare(input(filters, query: "no match"))
        precondition(empty.sections.isEmpty && empty.foreignGroups.isEmpty)

        var changed = a
        changed.category = .privacy
        changed.sourceRuleCount = 123
        changed.isSelected = false
        let refreshed = try await FilterListPresentation.prepare(input([changed, b]))
        precondition(refreshed.sections.first { $0.category == .privacy }!.filters == [changed])
        precondition(refreshed.foreignGroups.isEmpty, "Removed filters must leave no cached groups")
        let disabled = try await FilterListPresentation.prepare(input([changed, b], enabled: true))
        precondition(ids(disabled).isEmpty)

        let cancelled = Task { try await FilterListPresentation.prepare(input(filters)) }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            preconditionFailure("Cancelled preparation must not publish a stale result")
        } catch is CancellationError {}

        print("PASS — display order, regional grouping, search, selection, metadata refresh, and cancellation")
    }
}
