// Regression test: a page restored from the back-forward cache must get its
// page styles back.
//
// WebKit removes the sheets that browser.scripting.insertCSS adds when a page
// leaves through a cross-site commit, so a restored page comes back with its
// hides gone. The shipped content script reapplies them on pageshow. This runs
// the shipped content.js and background.js in a real WKWebExtensionController,
// against a local HTTP server, with a native stub that answers the background's
// native calls. Pages are served from 127.0.0.1 and localhost, so moving between
// them is a cross-site navigation.
//
// Run from the repository root:
//   swiftc -parse-as-library scripts/test_content_bfcache_restore.swift -o /tmp/wbe-bfcache-restore
//   /tmp/wbe-bfcache-restore [path/to/Resources] [port]
// The default Resources folder is "wBlock Scripts (iOS)/Resources". Exits 0 when
// every check passes.

import AppKit
import WebKit

let defaultResources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("wBlock Scripts (iOS)/Resources", isDirectory: true)
let commandArguments = CommandLine.arguments
let resourcesURL = (commandArguments.count > 1
    ? URL(fileURLWithPath: commandArguments[1], isDirectory: true)
    : defaultResources).standardizedFileURL
let serverPort = commandArguments.count > 2 ? (Int(commandArguments[2]) ?? 18765) : 18765

// Serves one page for every /page request; the query string only tells pages apart.
let serverSource = #"""
import http.server, sys
PAGE = b'''<!doctype html><html><head><meta charset="utf-8"><title>page</title></head><body>
<h1>page</h1>
<div class="ad-slot-0" id="ad0">Sponsored 0</div>
<div class="ad-slot-1" id="ad1">Sponsored 1</div>
<div class="ad-slot-2" id="ad2">Sponsored 2</div>
<div id="organic">Organic</div>
<script>
  window.__marker = Math.random().toString(36).slice(2);
  window.__ps = [];
  addEventListener('pageshow', e => window.__ps.push(e.persisted));
</script>
</body></html>'''
class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def do_GET(self):
        if not self.path.startswith('/page'):
            self.send_response(404); self.send_header('Content-Length', '0'); self.end_headers(); return
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Cache-Control', 'private, max-age=0')
        self.send_header('Content-Length', str(len(PAGE)))
        self.end_headers()
        self.wfile.write(PAGE)
    def log_message(self, *args): pass
http.server.ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1])), Handler).serve_forever()
"""#

@MainActor final class Tab: NSObject, WKWebExtensionTab {
    let webView: WKWebView
    weak var win: Window?
    init(webView: WKWebView) { self.webView = webView }
    func webView(for context: WKWebExtensionContext) -> WKWebView? { webView }
    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { win }
    func url(for context: WKWebExtensionContext) -> URL? { webView.url }
}

@MainActor final class Window: NSObject, WKWebExtensionWindow {
    var tab: Tab!
    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] { [tab] }
    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { tab }
}

struct Snapshot: Decodable {
    let host: String
    let marker: String
    let ps: [Bool]
    let styled: Bool
    let visible: [Int]
    let title: String
}

@MainActor final class Harness: NSObject, WKWebExtensionControllerDelegate, WKNavigationDelegate {
    private let windowObject = Window()
    private var context: WKWebExtensionContext!
    private var controller: WKWebExtensionController!
    private var webView: WKWebView!
    private var pendingNavigation: CheckedContinuation<Void, Never>?
    private var nativeLog: [String] = []
    private(set) var failures = 0

    // Native stub state. The site state answers the background's authoritative lookups.
    private var siteDisabled = false
    private var sitePaused = false
    private var failingLookups = false
    // Adds 999 unused selectors ahead of the two real hides, so the page has 1001 rules:
    // two insert chunks, with ad-slot-1 alone in the second.
    private var wideStyles = false

    // Every page gets the same hides: two selectors and one procedural rule.
    private let procedural = #"{"selector":[{"type":"css-selector","arg":"div.ad-slot-2"},{"type":"has-text","arg":"Sponsored 2"}],"action":{"type":"style","arg":"display: none !important"}}"#

    func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] { [windowObject] }
    func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { windowObject }

    func webExtensionController(_ controller: WKWebExtensionController, sendMessage message: Any, toApplicationWithIdentifier applicationIdentifier: String?, for extensionContext: WKWebExtensionContext) async throws -> Any? {
        let body = message as? [String: Any] ?? [:]
        let action = (body["action"] as? String) ?? (body["type"] as? String) ?? "config"
        nativeLog.append(action)
        if action == "getBlockingState" || action == "getSiteDisabledState" || action == "getBlockingPausedState" {
            return ["ok": true, "disabled": siteDisabled, "paused": sitePaused] as [String: Any]
        }
        guard action == "InitContentScript" else { return ["ok": true] as [String: Any] }
        if failingLookups {
            throw NSError(domain: "wblock-test", code: 1, userInfo: [NSLocalizedDescriptionKey: "native unavailable"])
        }
        let payload: [String: Any] = [
            "css": (wideStyles ? (0..<999).map { ".filler-\($0)" } : []) + [".ad-slot-0", ".ad-slot-1"],
            "styles": [],
            "procedural": [procedural],
            "scriptlets": [],
            "userScripts": [],
            "engineTimestamp": 1,
            "disabled": siteDisabled,
            "paused": sitePaused
        ]
        return ["type": "InitContentScript", "payload": payload, "userScripts": []] as [String: Any]
    }

    func setUp() async throws {
        let ext = try await WKWebExtension(resourceBaseURL: resourcesURL)
        if !ext.errors.isEmpty { throw NSError(domain: "wblock-test", code: 2, userInfo: [NSLocalizedDescriptionKey: "extension errors: \(ext.errors)"]) }
        context = WKWebExtensionContext(for: ext)
        context.hasAccessToPrivateData = true
        controller = WKWebExtensionController(configuration: .nonPersistent())
        controller.delegate = self
        for permission in ext.requestedPermissions { context.setPermissionStatus(.grantedExplicitly, for: permission) }
        for pattern in ext.allRequestedMatchPatterns { context.setPermissionStatus(.grantedExplicitly, for: pattern) }
        context.setPermissionStatus(.grantedExplicitly, for: WKWebExtension.MatchPattern.allHostsAndSchemes())
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.webExtensionController = controller
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.navigationDelegate = self
        let tab = Tab(webView: webView)
        tab.win = windowObject
        windowObject.tab = tab
        try controller.load(context)
        try await context.loadBackgroundContent()
        controller.didOpenWindow(windowObject)
        controller.didOpenTab(tab)
        controller.didFocusWindow(windowObject)
        controller.didActivateTab(tab, previousActiveTab: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { resumeNavigation() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { resumeNavigation() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { resumeNavigation() }

    private func resumeNavigation() {
        pendingNavigation?.resume()
        pendingNavigation = nil
    }

    // Starts a navigation, waits for it (or a timeout), then lets the page settle.
    private func navigate(_ start: () -> Void) async {
        await withCheckedContinuation { continuation in
            pendingNavigation = continuation
            start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                Task { @MainActor in self.resumeNavigation() }
            }
        }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
    }

    private var openCount = 0
    // Each open gets its own query string. Loading the URL already on screen replaces
    // its history entry, which then never reaches the back-forward cache.
    private func open(_ url: String) async {
        openCount += 1
        let unique = url + "&run=\(openCount)"
        await navigate { webView.load(URLRequest(url: URL(string: unique)!)) }
    }

    private func click(_ url: String) async {
        await navigate { webView.evaluateJavaScript("location.href = \(String(reflecting: url))", completionHandler: nil) }
    }

    private func back() async { await navigate { webView.goBack() } }
    private func forward() async { await navigate { webView.goForward() } }

    private func run(_ script: String) async {
        _ = try? await webView.evaluateJavaScript(script)
    }

    private func snapshot() async -> Snapshot? {
        let js = """
        (() => {
          const hidden = i => getComputedStyle(document.getElementById('ad' + i)).display === 'none';
          return JSON.stringify({
            host: location.host,
            marker: window.__marker || '',
            ps: window.__ps || [],
            styled: getComputedStyle(document.documentElement).getPropertyValue('--wblock-frame-styles').trim() !== '',
            visible: [0, 1, 2].filter(i => !hidden(i)),
            title: document.title
          });
        })()
        """
        guard let value = try? await webView.evaluateJavaScript(js) as? String else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: Data(value.utf8))
    }

    private func lookups() -> Int { nativeLog.filter { $0 == "InitContentScript" }.count }

    private func expect(_ ok: Bool, _ name: String, _ detail: String = "") {
        print("  \(ok ? "PASS" : "FAIL"): \(name)\(detail.isEmpty ? "" : " [\(detail)]")")
        if !ok { failures += 1 }
    }

    private func describe(_ snapshot: Snapshot?) -> String {
        guard let s = snapshot else { return "no snapshot" }
        return "host=\(s.host) styled=\(s.styled) visible=\(s.visible) ps=\(s.ps)"
    }

    func runScenarios() async {
        let a = "http://127.0.0.1:\(serverPort)/page?id=a"
        let crossSite = "http://localhost:\(serverPort)/page?id=b"
        let sameSite = "http://127.0.0.1:\(serverPort)/page?id=b"

        print("cross-site back and forward, three rounds")
        await open(a)
        guard let first = await snapshot() else { expect(false, "first load readable"); return }
        expect(first.visible.isEmpty, "first load applies hides", describe(first))
        await click(crossSite)
        for round in 1...3 {
            nativeLog.removeAll()
            await back()
            let s = await snapshot()
            expect(s?.marker == first.marker && s?.ps.last == true, "round \(round): bfcache restore", describe(s))
            expect(s?.visible.isEmpty == true, "round \(round): hides restored", describe(s))
            expect(lookups() == 1, "round \(round): one native lookup for the restore", "lookups=\(lookups())")
            await forward()
        }

        print("same-site back keeps the sheets, nothing is reapplied")
        await open(a)
        let sameFirst = await snapshot()
        await click(sameSite)
        nativeLog.removeAll()
        await back()
        let same = await snapshot()
        expect(same?.marker == sameFirst?.marker && same?.ps.last == true, "bfcache restore", describe(same))
        expect(same?.visible.isEmpty == true, "hides still applied", describe(same))
        expect(lookups() == 0, "no restore lookup, so no duplicate sheet", "lookups=\(lookups())")

        print("site disabled while the page was cached: no hides restored")
        await open(a)
        await click(crossSite)
        siteDisabled = true
        nativeLog.removeAll()
        await back()
        siteDisabled = false
        let disabled = await snapshot()
        expect(disabled?.ps.last == true, "bfcache restore", describe(disabled))
        expect(disabled?.styled == false && disabled?.visible.contains(0) == true && disabled?.visible.contains(1) == true, "hides not restored", describe(disabled))

        print("site paused while the page was cached: no hides restored")
        await open(a)
        await click(crossSite)
        sitePaused = true
        await back()
        sitePaused = false
        let paused = await snapshot()
        expect(paused?.ps.last == true, "bfcache restore", describe(paused))
        expect(paused?.styled == false && paused?.visible.contains(0) == true, "hides not restored", describe(paused))

        print("native lookup fails during the restore: retried, then left unstyled until the next restore")
        await open(a)
        await click(crossSite)
        failingLookups = true
        await back()
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        let failed = await snapshot()
        expect(failed?.ps.last == true, "bfcache restore", describe(failed))
        expect(failed?.visible.contains(0) == true, "unstyled after retries are exhausted", describe(failed))
        failingLookups = false
        await forward()
        await back()
        let recovered = await snapshot()
        expect(recovered?.visible.isEmpty == true, "next restore applies hides", describe(recovered))

        print("challenge page: no restore")
        await open(a)
        await run("document.title = 'Just a moment...'")
        await click(crossSite)
        nativeLog.removeAll()
        await back()
        let challenge = await snapshot()
        expect(challenge?.ps.last == true, "bfcache restore", describe(challenge))
        expect(challenge?.visible.contains(0) == true && lookups() == 0, "no restore lookup or styles", "lookups=\(lookups()) \(describe(challenge))")

        print("1001 hides in two insert chunks: the second chunk is restored too")
        wideStyles = true
        await open(a)
        let wideFirst = await snapshot()
        expect(wideFirst?.visible.isEmpty == true, "first load applies hides from both chunks", describe(wideFirst))
        await click(crossSite)
        nativeLog.removeAll()
        await back()
        let wide = await snapshot()
        expect(wide?.ps.last == true, "bfcache restore", describe(wide))
        expect(wide?.visible.isEmpty == true, "restore applies hides from both chunks", describe(wide))
        expect(lookups() == 1, "one native lookup for the restore", "lookups=\(lookups())")
        wideStyles = false
    }
}

@main struct Main {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-c", serverSource, String(serverPort)]
        do { try server.run() } catch {
            print("could not start the local server: \(error)")
            exit(2)
        }
        func finish(_ code: Int32) -> Never {
            server.terminate()
            exit(code)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) {
            print("TIMEOUT")
            finish(3)
        }
        Task { @MainActor in
            let probeURL = URL(string: "http://127.0.0.1:\(serverPort)/page")!
            for _ in 0..<50 {
                if let (_, response) = try? await URLSession.shared.data(from: probeURL),
                   (response as? HTTPURLResponse)?.statusCode == 200 { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            let harness = Harness()
            do { try await harness.setUp() } catch {
                print("setup failed: \(error)")
                finish(2)
            }
            await harness.runScenarios()
            print(harness.failures == 0 ? "ALL PASSED" : "\(harness.failures) CHECK(S) FAILED")
            finish(harness.failures == 0 ? 0 : 1)
        }
        app.run()
    }
}
