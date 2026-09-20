import Foundation
import wBlockCoreService

@main
struct ContextMenuActionAvailabilityTest {
    static func main() {
        let remoteURL = URL(string: "https://example.com/list.txt")!
        let inlineURL = URL(string: "wblock://userlist/local-rules")!

        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else {
                fputs("FAIL: \(message)\n", stderr)
                exit(1)
            }
        }

        func filter(
            _ name: String,
            category: FilterListCategory,
            custom: Bool,
            url: URL = remoteURL
        ) -> FilterList {
            FilterList(name: name, url: url, category: category, isCustom: custom)
        }

        func filterActions(_ list: FilterList, downloaded: Bool) -> [FilterContextMenuAction] {
            ContextMenuActionAvailability.filterActions(for: list, isDownloaded: downloaded)
        }

        let builtIn = filter("Built-in", category: .ads, custom: false)
        let custom = filter("Custom", category: .ads, custom: true)
        let foreignBuiltIn = filter("Foreign built-in", category: .foreign, custom: false)
        let foreignCustom = filter("Foreign custom", category: .foreign, custom: true)
        let inlineCustom = filter("Inline custom", category: .custom, custom: true, url: inlineURL)

        check(filterActions(builtIn, downloaded: false) == [.info, .settings, .moveTo],
              "undownloaded built-in nonforeign filters can move but cannot edit metadata")
        check(filterActions(builtIn, downloaded: true) == [.info, .settings, .viewRules, .moveTo],
              "downloaded built-in filters expose rules and move only")
        check(filterActions(custom, downloaded: false) == [.info, .settings, .moveTo, .editInfo, .deleteList],
              "undownloaded custom nonforeign filters expose custom metadata actions")
        check(filterActions(custom, downloaded: true) == [.info, .settings, .viewRules, .moveTo, .editInfo, .deleteList],
              "downloaded custom nonforeign filters expose rules and custom metadata actions")
        check(!filterActions(foreignBuiltIn, downloaded: true).contains(.moveTo),
              "foreign built-in filters never expose move")
        check(!filterActions(foreignCustom, downloaded: true).contains(.moveTo),
              "foreign custom filters never expose move")
        check(!filterActions(builtIn, downloaded: true).contains(.editInfo),
              "built-in filters never expose edit metadata")
        check(!filterActions(builtIn, downloaded: true).contains(.deleteList),
              "built-in filters never expose delete")
        check(filterActions(inlineCustom, downloaded: false) == [.info, .settings, .editRules, .moveTo, .editInfo, .deleteList],
              "local custom inline filters expose editable rules without a download")
        check(filterActions(custom, downloaded: true).contains(.viewRules),
              "remote custom filters expose view rules after download")
        check(!filterActions(custom, downloaded: true).contains(.editRules),
              "remote custom filters do not expose editable rules")

        func scriptActions(builtIn: Bool, local: Bool, downloaded: Bool) -> [UserScriptContextMenuAction] {
            ContextMenuActionAvailability.userScriptActions(
                isBuiltIn: builtIn, isLocal: local, isDownloaded: downloaded
            )
        }

        let expectedBuiltInRemoteUndownloaded: [UserScriptContextMenuAction] = [.info, .settings, .download, .moveTo]
        let expectedBuiltInRemoteDownloaded: [UserScriptContextMenuAction] = [.info, .settings, .viewContent, .moveTo]
        let expectedBuiltInLocalUndownloaded: [UserScriptContextMenuAction] = [.info, .settings, .moveTo]
        let expectedBuiltInLocalDownloaded: [UserScriptContextMenuAction] = [.info, .settings, .viewContent, .moveTo]
        check(scriptActions(builtIn: true, local: false, downloaded: false) == expectedBuiltInRemoteUndownloaded,
              "undownloaded remote built-in scripts offer download and move only")
        check(scriptActions(builtIn: true, local: false, downloaded: true) == expectedBuiltInRemoteDownloaded,
              "downloaded remote built-in scripts offer view content and move")
        check(scriptActions(builtIn: true, local: true, downloaded: false) == expectedBuiltInLocalUndownloaded,
              "undownloaded local built-in scripts offer move without download")
        check(scriptActions(builtIn: true, local: true, downloaded: true) == expectedBuiltInLocalDownloaded,
              "downloaded local built-in scripts offer view content and move")

        let expectedCustomRemoteUndownloaded: [UserScriptContextMenuAction] = [.info, .settings, .download, .moveTo, .editInfo, .deleteScript]
        let expectedCustomRemoteDownloaded: [UserScriptContextMenuAction] = [.info, .settings, .viewContent, .moveTo, .editInfo, .deleteScript]
        let expectedCustomLocalUndownloaded: [UserScriptContextMenuAction] = [.info, .settings, .moveTo, .editInfo, .deleteScript]
        let expectedCustomLocalDownloaded: [UserScriptContextMenuAction] = [.info, .settings, .editContent, .moveTo, .editInfo, .deleteScript]
        check(scriptActions(builtIn: false, local: false, downloaded: false) == expectedCustomRemoteUndownloaded,
              "undownloaded remote custom scripts offer download and custom metadata actions")
        check(scriptActions(builtIn: false, local: false, downloaded: true) == expectedCustomRemoteDownloaded,
              "downloaded remote custom scripts offer view content, not edit content")
        check(scriptActions(builtIn: false, local: true, downloaded: false) == expectedCustomLocalUndownloaded,
              "undownloaded local custom scripts offer custom metadata actions without download")
        check(scriptActions(builtIn: false, local: true, downloaded: true) == expectedCustomLocalDownloaded,
              "downloaded local custom scripts offer edit content and custom metadata actions")

        for combination in [
            (false, false, false), (false, false, true), (false, true, false), (false, true, true),
            (true, false, false), (true, false, true), (true, true, false), (true, true, true)
        ] {
            check(scriptActions(builtIn: combination.0, local: combination.1, downloaded: combination.2).contains(.moveTo),
                  "every built-in and custom remote/local script exposes move")
        }
        for combination in [(true, false), (true, true), (false, false), (false, true)] {
            let actions = scriptActions(builtIn: combination.0, local: combination.1, downloaded: false)
            check(!actions.contains(.viewContent), "undownloaded scripts never expose view content")
        }

        print("PASS")
    }
}
