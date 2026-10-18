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
        precondition(ForeignFilterOrganizer.isRecommended(regional))
        precondition(!ForeignFilterOrganizer.isRecommended(superseded))
        precondition(regional.nativeLanguageNames() == ["Deutsch", "français"])
        precondition(regional.nativeLanguageNames(among: ["fr"]) == ["français"])
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
        precondition(ids(all).count == Set(ids(all)).count, "Each catalog list has one row")

        let reordered = FilterListPresentation.Input(
            filters: filters,
            order: ListDisplayOrder.saving([superseded, regional], in: [a, privacy, b, regional, superseded]),
            searchText: "", enabledOnly: false, localeIdentifier: "en")
        let reorderedPresentation = try await FilterListPresentation.prepare(reordered)
        precondition(reorderedPresentation.sections.first { $0.category == .foreign }!.filters.map(\.id) == [superseded.id, regional.id],
                     "Regional rows must honor saved display order")

        let exported = ListDisplayOrder.exportedKeys(
            FilterListPresentation.ordered(filters, order: ListDisplayOrder.cleared),
            order: reordered.order, key: { $0.url.absoluteString })!
        let otherDevice = filters.map {
            FilterList(name: $0.name, url: $0.url, category: $0.category, languages: $0.languages)
        }
        let imported = ListDisplayOrder.applying(
            exported, to: FilterListPresentation.ordered(otherDevice, order: ListDisplayOrder.cleared),
            current: Data(), baseline: Data(), key: { $0.url.absoluteString })!
        let synced = try await FilterListPresentation.prepare(.init(
            filters: otherDevice, order: imported, searchText: "", enabledOnly: false, localeIdentifier: "en"))
        precondition(synced.sections.first { $0.category == .foreign }!.filters.map(\.url) == [superseded.url, regional.url],
                     "Regional display order must survive sync to different local IDs")

        let enabled = try await FilterListPresentation.prepare(input(filters, enabled: true))
        precondition(Set(ids(enabled)) == [a.id, regional.id])
        let descriptionSearch = try await FilterListPresentation.prepare(input(filters, query: "  UNIQUE DESCRIPTION \n"))
        precondition(ids(descriptionSearch) == [a.id])
        let urlSearch = try await FilterListPresentation.prepare(input(filters, query: "EXAMPLE.COM/B"))
        precondition(ids(urlSearch) == [b.id])
        let empty = try await FilterListPresentation.prepare(input(filters, query: "no match"))
        precondition(empty.sections.isEmpty)
        let languageSearch = try await FilterListPresentation.prepare(input(filters, query: "German"))
        precondition(ids(languageSearch) == [regional.id], "Search finds every language a shared list covers")
        let nativeSearch = try await FilterListPresentation.prepare(input(filters, query: "Deutsch"))
        precondition(ids(nativeSearch) == [regional.id], "Search accepts the language’s native name")

        var changed = a
        changed.category = .privacy
        changed.sourceRuleCount = 123
        changed.isSelected = false
        let refreshed = try await FilterListPresentation.prepare(input([changed, b]))
        precondition(refreshed.sections.first { $0.category == .privacy }!.filters == [changed])
        precondition(refreshed.sections.allSatisfy { $0.category != .foreign }, "Removed filters must leave no cached regional rows")
        precondition(refreshed.rowText[changed.id]!.metadata.isEmpty, "A remote list shows no metadata before it downloads")
        var downloaded = input([changed, b])
        downloaded.downloadedIDs = [changed.id]
        let downloadedText = try await FilterListPresentation.prepare(downloaded).rowText[changed.id]!
        precondition(downloadedText.name == "Alpha" && downloadedText.metadata.contains("123"), "Row text follows the refreshed snapshot")
        precondition(all.rowText[regional.id]!.languages == "Deutsch, français" && all.rowText[a.id]!.languages.isEmpty)
        let disabled = try await FilterListPresentation.prepare(input([changed, b], enabled: true))
        precondition(ids(disabled).isEmpty)

        let cancelled = Task { try await FilterListPresentation.prepare(input(filters)) }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            preconditionFailure("Cancelled preparation must not publish a stale result")
        } catch is CancellationError {}

        print("PASS — display order, flat regional catalog, language search, selection, metadata refresh, and cancellation")
    }
}
