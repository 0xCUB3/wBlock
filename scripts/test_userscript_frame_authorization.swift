import Foundation
import wBlockCoreService

@main
struct UserScriptFrameAuthorizationTests {
    static func main() {
        var script = UserScript(name: "Frame policy", content: "")
        script.matches = ["https://example.com/allowed/*"]
        script.isEnabled = true
        script.grant = ["GM_setValue"]
        func allows(_ candidate: UserScript, url: String = "https://example.com/allowed/page", top: Bool = true, disabled: Bool = false, paused: Bool = false) -> Bool {
            UserScriptFrameAuthorization.allows(candidate, pageURL: url, isTopFrame: top, disabledOnSite: disabled, paused: paused)
        }
        precondition(allows(script))
        precondition(allows(script, top: false))
        precondition(!allows(script, url: "https://other.example/allowed/page"))
        precondition(!allows(script, url: "https://example.com/denied/page"))
        precondition(!allows(script, url: "about:blank"))
        precondition(!allows(script, url: "https:///"))
        precondition(!allows(script, disabled: true))
        precondition(!allows(script, paused: true))
        script.noframes = true
        precondition(allows(script))
        precondition(!allows(script, top: false))
        script.isEnabled = false
        precondition(!allows(script))
        script.isEnabled = true
        script.excludeMatches = ["https://example.com/allowed/*"]
        precondition(!allows(script))
        precondition(script.usesGMStorage)
        script.grant = ["GM_setValue", " none "]
        precondition(!script.usesGMStorage)
        script.grant = [" GM.setValue "]
        precondition(script.usesGMStorage)
        print("PASS: native userscript frame, site, pause and storage grant authorization")
    }
}
